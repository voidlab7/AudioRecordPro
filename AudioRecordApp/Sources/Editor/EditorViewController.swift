import Cocoa
import AVFoundation

// MARK: - Delegate Protocol
protocol EditorViewControllerDelegate: AnyObject {
    func editorDidSave(_ editor: EditorViewController, file: RecordedFileInfo)
    func editorDidCancel(_ editor: EditorViewController)
}

// MARK: - EditorViewController
/// 音频编辑器控制器 — 管理编辑器生命周期、音频数据、撤销栈
class EditorViewController {
    
    // MARK: - Properties
    let file: RecordedFileInfo
    weak var delegate: EditorViewControllerDelegate?
    
    /// 当前正在编辑的文件 URL（供外部检查文件锁定）
    static var currentlyEditingURL: URL?
    
    private var audioBuffer: AVAudioPCMBuffer?
    private var audioFormat: AVAudioFormat?
    private let editHistory = EditHistory()
    private let logger = Logger.shared
    private let maxEditableFileSize: Int64 = 500 * 1024 * 1024
    private let maxEditableDuration: TimeInterval = 30 * 60
    private let maxEditablePCMBytes: Int64 = 1_000 * 1024 * 1024
    
    // 预览播放
    private var previewEngine: AVAudioEngine?
    private var previewPlayerNode: AVAudioPlayerNode?
    private var isPreviewPlaying: Bool = false
    private var previewTimer: Timer?
    private var previewStartHostTime: UInt64 = 0
    
    // 编辑器视图组件
    private let navigationBar = EditorNavigationBar()
    private let scrollBarView = HorizontalScrollBarView()
    private let toolbar = EditorToolbar()
    private let statusBar = EditorStatusBar()
    
    /// P0-B: 多轨道容器（替代原来的单个 waveformView）
    private let trackContainerView = TrackContainerView()
    
    /// 便捷：主轨道波形视图（第一轨）
    private var waveformView: EditorWaveformView {
        trackContainerView.waveformView(for: 0) ?? EditorWaveformView()
    }

    /// 编辑器的根视图
    let editorView = EditorRootView()

    /// P0-A: 嵌入模式 — 当嵌入到 MainWindowView 时，隐藏自带的 navigationBar/toolbar
    /// 编辑操作统一由 MainWindowView 的 EditToolbarView 触发
    var isEmbedded: Bool = false {
        didSet {
            guard isEmbedded != oldValue else { return }
            
            // 隐藏所有 UI chrome
            navigationBar.isHidden = isEmbedded
            toolbar.isHidden = isEmbedded
            statusBar.isHidden = isEmbedded
            scrollBarView.isHidden = isEmbedded
            
            if isEmbedded {
                // 简单策略：把所有 chrome 高度压为 0
                // 原有约束链不变：navBar(0h) → trackContainer → scrollBar(0h) → toolbar(0h) → statusBar(0h)
                // 结果：trackContainer 自动填满整个 editorView
                navBarHeightConstraint?.constant = 0
                scrollBarHeightConstraint.constant = 0
                toolbarHeightConstraint?.constant = 0
                statusBarHeightConstraint?.constant = 0
            } else {
                // 恢复标准高度
                navBarHeightConstraint?.constant = IndustrialSpacing.editorNavBarHeight
                scrollBarHeightConstraint.constant = 0  // scroll bar 默认就是 0
                toolbarHeightConstraint?.constant = IndustrialSpacing.editorToolbarHeight
                statusBarHeightConstraint?.constant = IndustrialSpacing.editorStatusBarHeight
            }
        }
    }
    
    // P0-A: 约束引用（嵌入模式下修改常量值）
    private var navBarHeightConstraint: NSLayoutConstraint?
    private var toolbarHeightConstraint: NSLayoutConstraint?
    private var statusBarHeightConstraint: NSLayoutConstraint?

    private var hasUnsavedChanges: Bool = false

    /// 防止 viewport 更新回环
    private var isUpdatingFromExternalSource = false

    /// 滚动条高度约束（显隐切换）
    private var scrollBarHeightConstraint: NSLayoutConstraint!

    /// 关联的编辑会话（用于状态保持和缓存）
    private var session: EditorSession?

    // MARK: - Initialization

    init(file: RecordedFileInfo) {
        self.file = file
        self.session = nil
        setupEditorView()
        setupDelegates()
        loadAudio()
    }

    /// 使用已有 session 初始化（支持缓存复用，V2.1 文件联动）
    init(file: RecordedFileInfo, session: EditorSession) {
        self.file = file
        self.session = session
        setupEditorView()
        setupDelegates()

        // 如果 session 已加载，直接使用缓存数据
        if session.isLoaded, let buffer = session.audioBuffer, let format = session.audioFormat {
            self.audioBuffer = buffer
            self.audioFormat = format
            waveformView.loadAudio(from: buffer, sampleRate: format.sampleRate)
            navigationBar.setAllToolsEnabled(true)
            navigationBar.setToolEnabled(.trim, enabled: false)
            updateStatusBar()
            // 恢复视图状态
            restoreViewportState(session.viewportState)
            logger.info("编辑器从 session 缓存加载: \(file.name)")
        } else {
            // session 未加载，触发加载
            loadAudioWithSession()
        }
    }
    
    deinit {
        stopPreview()
        EditorViewController.currentlyEditingURL = nil
        cleanupTempFiles()
    }
    
    // MARK: - Setup
    
    private func setupEditorView() {
        editorView.wantsLayer = true
        editorView.layer?.backgroundColor = IndustrialColors.surfaceContainerLowest.cgColor
        editorView.translatesAutoresizingMaskIntoConstraints = false
        editorView.keyHandler = self

        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        trackContainerView.translatesAutoresizingMaskIntoConstraints = false
        scrollBarView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        editorView.addSubview(navigationBar)
        editorView.addSubview(trackContainerView)
        editorView.addSubview(scrollBarView)
        editorView.addSubview(toolbar)
        editorView.addSubview(statusBar)

        // P0-B: 默认创建第一轨
        let defaultTrack = EditorAudioTrack(name: file.name, color: .coral)
        trackContainerView.tracks = [defaultTrack]

        scrollBarHeightConstraint = scrollBarView.heightAnchor.constraint(equalToConstant: 0)

        // P0-A: 存储约束引用（嵌入模式下将高度压为 0）
        navBarHeightConstraint = navigationBar.heightAnchor.constraint(equalToConstant: IndustrialSpacing.editorNavBarHeight)
        toolbarHeightConstraint = toolbar.heightAnchor.constraint(equalToConstant: IndustrialSpacing.editorToolbarHeight)
        statusBarHeightConstraint = statusBar.heightAnchor.constraint(equalToConstant: IndustrialSpacing.editorStatusBarHeight)

        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: editorView.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),
            navBarHeightConstraint!,

            // trackContainer 在 navBar 和 scrollBar 之间（嵌入模式下两者高度都为 0 → 自动填满）
            trackContainerView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            trackContainerView.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            trackContainerView.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),
            trackContainerView.bottomAnchor.constraint(equalTo: scrollBarView.topAnchor, constant: -IndustrialSpacing.xs),

            scrollBarView.leadingAnchor.constraint(equalTo: editorView.leadingAnchor, constant: IndustrialSpacing.md),
            scrollBarView.trailingAnchor.constraint(equalTo: editorView.trailingAnchor, constant: -IndustrialSpacing.md),
            scrollBarView.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -IndustrialSpacing.xs),
            scrollBarHeightConstraint,

            toolbar.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            toolbarHeightConstraint!,

            statusBar.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: editorView.bottomAnchor),
            statusBarHeightConstraint!
        ])

        navigationBar.setFileName(file.name)
    }
    
    private func setupDelegates() {
        navigationBar.delegate = self
        waveformView.delegate = self
        toolbar.delegate = self
        toolbar.zoomControls.delegate = self
        scrollBarView.delegate = self
    }
    
    // MARK: - Audio Loading
    
    private func loadAudio() {
        EditorViewController.currentlyEditingURL = file.url
        waveformView.setLoadingState()
        navigationBar.setAllToolsEnabled(false)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let audioFile = try AVAudioFile(forReading: self.file.url)
                let format = audioFile.processingFormat
                let fileLength = audioFile.length
                let duration = format.sampleRate > 0 ? Double(fileLength) / format.sampleRate : self.file.duration
                
                // Determine file attributes for cache key
                let attrs = try FileManager.default.attributesOfItem(atPath: self.file.url.path)
                let fileSize = (attrs[.size] as? Int64) ?? 0
                let modifiedAt = (attrs[.modificationDate] as? Date) ?? Date()
                
                // Decide: tile mode for large files, legacy buffer for short files
                let useTileMode = duration > 60 || fileSize > 50 * 1024 * 1024  // >1min or >50MB
                
                if useTileMode {
                    // Build AudioAsset for tile-based waveform
                    let assetID = AudioAsset.makeID(
                        url: self.file.url,
                        fileSize: fileSize,
                        modifiedAt: modifiedAt,
                        algorithmVersion: WaveformTileProvider.algorithmVersion
                    )
                    let asset = AudioAsset(
                        id: assetID,
                        url: self.file.url,
                        duration: duration,
                        sampleRate: format.sampleRate,
                        channelCount: Int(format.channelCount),
                        fileSize: fileSize,
                        modifiedAt: modifiedAt
                    )
                    
                    // Still load full buffer for editing if within limits
                    var editBuffer: AVAudioPCMBuffer? = nil
                    if !self.shouldRejectFullBufferEditing(duration: duration, format: format) {
                        let frameCount = AVAudioFrameCount(fileLength)
                        if frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
                            try audioFile.read(into: buffer)
                            editBuffer = buffer
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.audioBuffer = editBuffer
                        self.audioFormat = format
                        self.waveformView.loadAudioAsset(asset)
                        self.navigationBar.setAllToolsEnabled(editBuffer != nil)
                        if editBuffer != nil {
                            self.navigationBar.setToolEnabled(.trim, enabled: false)
                        }
                        self.updateStatusBar()
                        self.logger.info("编辑器加载完成(tile模式): \(self.file.name), 时长: \(String(format: "%.1f", duration))s, 采样率: \(format.sampleRate)")
                    }
                } else {
                    // Short file: legacy full-buffer approach
                    if self.shouldRejectFullBufferEditing(duration: duration, format: format) {
                        DispatchQueue.main.async {
                            self.showLargeFileEditingNotice(duration: duration, format: format)
                        }
                        return
                    }
                    
                    let frameCount = AVAudioFrameCount(fileLength)
                    
                    guard frameCount > 0,
                          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        DispatchQueue.main.async {
                            self.waveformView.loadError = "无法分配音频缓冲区（文件可能过大或内存不足）"
                            self.waveformView.isLoading = false
                            self.waveformView.needsDisplay = true
                            EditorViewController.currentlyEditingURL = nil
                            self.logger.error("无法分配音频缓冲区")
                        }
                        return
                    }
                    
                    try audioFile.read(into: buffer)
                    
                    DispatchQueue.main.async {
                        self.audioBuffer = buffer
                        self.audioFormat = format
                        self.waveformView.loadAudio(from: buffer, sampleRate: format.sampleRate)
                        self.navigationBar.setAllToolsEnabled(true)
                        self.navigationBar.setToolEnabled(.trim, enabled: false)
                        self.updateStatusBar()
                        self.logger.info("编辑器加载完成: \(self.file.name), 帧数: \(frameCount), 采样率: \(format.sampleRate)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.waveformView.loadError = "无法读取音频文件: \(error.localizedDescription)"
                    self.waveformView.isLoading = false
                    self.waveformView.needsDisplay = true
                    EditorViewController.currentlyEditingURL = nil
                    self.logger.error("加载音频文件失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Edit Operations
    
    func executeCommand(_ command: EditCommand) {
        guard var buffer = audioBuffer else { return }
        
        if editHistory.execute(command, on: &buffer) {
            audioBuffer = buffer
            hasUnsavedChanges = true
            // Refresh waveform: use legacy buffer reload (works for both tile and non-tile mode)
            waveformView.loadAudio(from: buffer, sampleRate: audioFormat?.sampleRate ?? 48000)
            // Also invalidate tile caches so next tile-mode load uses fresh data
            waveformView.invalidateAllTiles()
            updateUndoRedoState()
            updateStatusBar()
            logger.info("执行编辑操作: \(command.description)")
        } else {
            // BUG-008 fix: 操作失败时提示用户
            let alert = NSAlert()
            alert.messageText = "操作失败"
            alert.informativeText = "无法执行「\(command.description)」。可能是音频信号过弱或数据异常。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    func undo() {
        guard var buffer = audioBuffer else { return }
        
        if editHistory.undo(on: &buffer) {
            audioBuffer = buffer
            hasUnsavedChanges = editHistory.stepCount > 0
            waveformView.loadAudio(from: buffer, sampleRate: audioFormat?.sampleRate ?? 48000)
            waveformView.invalidateAllTiles()
            updateUndoRedoState()
            updateStatusBar()
            logger.info("撤销编辑操作")
        }
    }
    
    func redo() {
        guard var buffer = audioBuffer else { return }
        
        if editHistory.redo(on: &buffer) {
            audioBuffer = buffer
            hasUnsavedChanges = true
            waveformView.loadAudio(from: buffer, sampleRate: audioFormat?.sampleRate ?? 48000)
            waveformView.invalidateAllTiles()
            updateUndoRedoState()
            updateStatusBar()
            logger.info("重做编辑操作")
        }
    }
    
    func save() {
        guard let buffer = audioBuffer, let format = audioFormat else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 保存前备份
                let backupURL = self.file.url.deletingLastPathComponent().appendingPathComponent(".backup_\(self.file.url.lastPathComponent)")
                try? FileManager.default.copyItem(at: self.file.url, to: backupURL)
                
                let audioFile = try AVAudioFile(forWriting: self.file.url, settings: format.settings)
                try audioFile.write(from: buffer)
                
                // 清理备份
                try? FileManager.default.removeItem(at: backupURL)
                
                DispatchQueue.main.async {
                    self.hasUnsavedChanges = false
                    self.editHistory.clear()
                    self.updateUndoRedoState()
                    self.navigationBar.setFileName("\(self.file.name) ✓ 已保存")
                    self.logger.info("保存完成: \(self.file.name)")
                    self.delegate?.editorDidSave(self, file: self.file)
                    // BUG-004 fix: 2 秒后恢复文件名显示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard let self = self else { return }
                        self.navigationBar.setFileName(self.file.name)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.logger.error("保存失败: \(error.localizedDescription)")
                    let alert = NSAlert()
                    alert.messageText = "保存失败"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            }
        }
    }
    
    // MARK: - Trim (REQ-1.1-02)
    
    /// 执行裁剪：保留选区内的音频，删除选区外的部分
    func performTrim() {
        guard let format = audioFormat else { return }
        guard let selection = waveformView.selection else {
            // BUG-002 fix: 无选区时提示用户
            let alert = NSAlert()
            alert.messageText = "请先创建选区"
            alert.informativeText = "在波形上拖拽以选择要保留的区域，然后点击裁剪。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        let totalDuration = Double(audioBuffer?.frameLength ?? 0) / format.sampleRate
        
        // 边界检查：极短文件或极短选区
        let selectionDuration = selection.upperBound - selection.lowerBound
        if selectionDuration < 0.1 {
            let alert = NSAlert()
            alert.messageText = "选区过短"
            alert.informativeText = "裁剪选区至少需要 0.1 秒。当前选区仅 \(String(format: "%.2f", selectionDuration)) 秒。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        // 如果选区已经覆盖整个音频，无需裁剪
        if selection.lowerBound <= 0.05 && selection.upperBound >= totalDuration - 0.05 {
            logger.info("选区已覆盖全部音频，无需裁剪")
            return
        }
        
        let command = TrimCommand(
            startTime: selection.lowerBound,
            endTime: selection.upperBound,
            sampleRate: format.sampleRate,
            totalFrames: audioBuffer?.frameLength ?? 0
        )
        
        executeCommand(command)
        
        // 裁剪后清除选区（新波形的范围变了）
        waveformView.clearSelection()
        
        logger.info("裁剪完成: 保留 \(String(format: "%.1f", selection.lowerBound))s ~ \(String(format: "%.1f", selection.upperBound))s")
    }
    
    // MARK: - Silence Trim (REQ-1.1-03)
    
    /// 静音裁剪：检测静音段 → 用户确认 → 删除
    func performSilenceTrim() {
        guard let buffer = audioBuffer, let format = audioFormat else { return }
        
        // 检测静音段
        let params = SilenceTrimCommand.DetectionParams()
        let segments = SilenceTrimCommand.detectSilence(in: buffer, sampleRate: format.sampleRate, params: params)
        
        if segments.isEmpty {
            let alert = NSAlert()
            alert.messageText = "未检测到静音段"
            alert.informativeText = "当前阈值 \(Int(params.thresholdDB)) dB、最小时长 \(String(format: "%.1f", params.minDuration))s 下未发现静音段。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        // 汇总信息
        let totalSilence = segments.reduce(0) { $0 + $1.duration }
        
        let alert = NSAlert()
        alert.messageText = "检测到 \(segments.count) 个静音段"
        alert.informativeText = "总计 \(String(format: "%.1f", totalSilence)) 秒静音。\n阈值: \(Int(params.thresholdDB)) dB，最小时长: \(String(format: "%.1f", params.minDuration))s\n\n是否删除所有静音段？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "删除全部")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        
        let command = SilenceTrimCommand(segments: segments, sampleRate: format.sampleRate)
        executeCommand(command)
        waveformView.clearSelection()
        
        logger.info("静音裁剪完成: 删除 \(segments.count) 段, 共 \(String(format: "%.1f", totalSilence))s")
    }
    
    // MARK: - Normalize (REQ-1.1-04)
    
    /// 音量标准化：选择预设 → 应用 LUFS 归一化
    func performNormalize() {
        guard let format = audioFormat else { return }
        
        let alert = NSAlert()
        alert.messageText = "音量标准化"
        alert.informativeText = "选择目标响度预设："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "播客 (-16 LUFS)")
        alert.addButton(withTitle: "YouTube (-14 LUFS)")
        alert.addButton(withTitle: "广播 (-24 LUFS)")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        
        let preset: NormalizePreset
        switch response {
        case .alertFirstButtonReturn:
            preset = .podcast
        case .alertSecondButtonReturn:
            preset = .youtube
        case .alertThirdButtonReturn:
            preset = .broadcast
        default:
            return
        }
        
        let command = NormalizeCommand(preset: preset, sampleRate: format.sampleRate)
        executeCommand(command)
        logger.info("标准化完成: \(preset.rawValue) (\(String(format: "%.0f", preset.targetLUFS)) LUFS)")
    }
    
    // MARK: - Fade (REQ-1.1-05)
    
    /// 淡入淡出：默认淡入 0.5s + 淡出 1.0s，对数曲线
    func performFade() {
        guard let format = audioFormat else { return }
        guard let buffer = audioBuffer else { return }
        
        let totalDuration = Double(buffer.frameLength) / format.sampleRate
        
        let alert = NSAlert()
        alert.messageText = "淡入淡出"
        alert.informativeText = "将对整个音频应用淡入淡出效果。\n\n淡入: 0.5s / 淡出: 1.0s / 对数曲线\n\n音频时长: \(String(format: "%.1f", totalDuration))s"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "应用")
        alert.addButton(withTitle: "仅淡入")
        alert.addButton(withTitle: "仅淡出")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        
        let fadeIn: TimeInterval
        let fadeOut: TimeInterval
        
        switch response {
        case .alertFirstButtonReturn:
            fadeIn = min(0.5, totalDuration * 0.3)
            fadeOut = min(1.0, totalDuration * 0.3)
        case .alertSecondButtonReturn:
            fadeIn = min(0.5, totalDuration * 0.3)
            fadeOut = 0
        case .alertThirdButtonReturn:
            fadeIn = 0
            fadeOut = min(1.0, totalDuration * 0.3)
        default:
            return
        }
        
        let command = FadeCommand(fadeIn: fadeIn, fadeOut: fadeOut, curve: .logarithmic, sampleRate: format.sampleRate)
        executeCommand(command)
        
        var desc: [String] = []
        if fadeIn > 0 { desc.append("淡入 \(String(format: "%.1f", fadeIn))s") }
        if fadeOut > 0 { desc.append("淡出 \(String(format: "%.1f", fadeOut))s") }
        logger.info("淡入淡出完成: \(desc.joined(separator: " + "))")
    }
    
    // MARK: - Exit
    
    func requestExit() {
        if hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "有未保存的编辑"
            alert.informativeText = "当前编辑尚未保存，是否保存后退出？"
            alert.addButton(withTitle: "保存")
            alert.addButton(withTitle: "放弃")
            alert.addButton(withTitle: "取消")
            
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                save()
            case .alertSecondButtonReturn:
                EditorViewController.currentlyEditingURL = nil
                delegate?.editorDidCancel(self)
            default:
                break // 取消，留在编辑器
            }
        } else {
            EditorViewController.currentlyEditingURL = nil
            delegate?.editorDidCancel(self)
        }
    }
    
    // MARK: - Private Helpers
    
    private func updateUndoRedoState() {
        navigationBar.updateUndoRedoState(canUndo: editHistory.canUndo, canRedo: editHistory.canRedo)
        navigationBar.updateSaveState(hasUnsavedChanges: hasUnsavedChanges)
    }
    
    private func updateStatusBar() {
        guard let buffer = audioBuffer, let format = audioFormat else { return }
        let duration = Double(buffer.frameLength) / format.sampleRate
        statusBar.update(
            duration: duration,
            sampleRate: format.sampleRate,
            channels: Int(format.channelCount),
            editSteps: editHistory.stepCount,
            maxSteps: editHistory.maxSteps
        )
    }
    
    private func shouldRejectFullBufferEditing(duration: TimeInterval, format: AVAudioFormat) -> Bool {
        let estimatedPCMBytes = Int64(duration * format.sampleRate) * Int64(max(1, format.channelCount)) * Int64(MemoryLayout<Float>.size)
        return file.size > maxEditableFileSize || duration > maxEditableDuration || estimatedPCMBytes > maxEditablePCMBytes
    }
    
    private func showLargeFileEditingNotice(duration: TimeInterval, format: AVAudioFormat) {
        audioBuffer = nil
        audioFormat = nil
        waveformView.isLoading = false
        waveformView.loadError = "录音过大，已跳过编辑器加载，避免应用无响应"
        waveformView.needsDisplay = true
        navigationBar.setAllToolsEnabled(false)
        statusBar.update(
            duration: duration,
            sampleRate: format.sampleRate,
            channels: Int(format.channelCount),
            editSteps: 0,
            maxSteps: editHistory.maxSteps
        )
        EditorViewController.currentlyEditingURL = nil
        logger.warning("跳过超大文件编辑加载: \(file.name), 大小: \(file.formattedSize), 时长: \(String(format: "%.1f", duration))s")
    }
    
    private func cleanupTempFiles() {
        // 清理编辑器临时文件（undo 磁盘缓存等）
        let tempDir = FileManager.default.temporaryDirectory
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent.hasPrefix("undo-") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - EditorNavigationBarDelegate
extension EditorViewController: EditorNavigationBarDelegate {
    func editorNavigationBarDidTapBack(_ bar: EditorNavigationBar) {
        requestExit()
    }
    
    func editorNavigationBarDidTapUndo(_ bar: EditorNavigationBar) {
        undo()
    }
    
    func editorNavigationBarDidTapRedo(_ bar: EditorNavigationBar) {
        redo()
    }
    
    func editorNavigationBarDidTapSave(_ bar: EditorNavigationBar) {
        save()
    }
    
    func editorNavigationBarDidSelectTool(_ bar: EditorNavigationBar, tool: EditorToolType) {
        logger.info("选择工具: \(tool.rawValue)")
        switch tool {
        case .trim:
            performTrim()
        case .silenceTrim:
            performSilenceTrim()
        case .normalize:
            performNormalize()
        case .fade:
            performFade()
        }
    }
}

// MARK: - EditorWaveformViewDelegate
extension EditorViewController: EditorWaveformViewDelegate {
    func editorWaveformView(_ view: EditorWaveformView, didChangeSelection range: ClosedRange<TimeInterval>?) {
        let hasSelection = range != nil
        navigationBar.setToolEnabled(.trim, enabled: hasSelection)
        navigationBar.setToolEnabled(.fade, enabled: true)
        navigationBar.setToolEnabled(.normalize, enabled: true)
        navigationBar.setToolEnabled(.silenceTrim, enabled: true)
    }

    func editorWaveformView(_ view: EditorWaveformView, didSeekTo time: TimeInterval) {
        waveformView.updatePlaybackTime(time)
        statusBar.updateCurrentTime(time)
    }

    func editorWaveformViewDidChangeViewport(_ view: EditorWaveformView) {
        guard !isUpdatingFromExternalSource else { return }
        syncControlsToWaveformState()
    }
}

// MARK: - EditorToolbarDelegate
extension EditorViewController: EditorToolbarDelegate {
    func editorToolbarDidTapPreviewPlay(_ toolbar: EditorToolbar) {
        if isPreviewPlaying {
            stopPreview()
        } else {
            startPreview()
        }
    }
    
    func editorToolbarDidTapPreviewStop(_ toolbar: EditorToolbar) {
        stopPreview()
    }
}

// MARK: - Preview Playback
extension EditorViewController {
    
    func startPreview() {
        guard let buffer = audioBuffer, let format = audioFormat else { return }
        stopPreview()
        
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        do {
            try engine.start()
            playerNode.scheduleBuffer(buffer, completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.stopPreview()
                }
            })
            playerNode.play()
            
            previewEngine = engine
            previewPlayerNode = playerNode
            isPreviewPlaying = true
            toolbar.updatePreviewState(isPlaying: true)
            
            // BUG-005 fix: 启动游标跟踪 timer
            let totalDuration = Double(buffer.frameLength) / format.sampleRate
            previewStartHostTime = mach_absolute_time()
            previewTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
                guard let self = self, self.isPreviewPlaying else { return }
                var info = mach_timebase_info_data_t()
                mach_timebase_info(&info)
                let elapsed = Double(mach_absolute_time() - self.previewStartHostTime) * Double(info.numer) / Double(info.denom) / 1_000_000_000
                let clampedTime = min(elapsed, totalDuration)
                self.waveformView.updatePlaybackTime(clampedTime)
                self.statusBar.updateCurrentTime(clampedTime)
            }
            
            logger.info("预览播放开始")
        } catch {
            logger.error("预览播放失败: \(error.localizedDescription)")
        }
    }
    
    func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewPlayerNode?.stop()
        previewEngine?.stop()
        previewPlayerNode = nil
        previewEngine = nil
        isPreviewPlaying = false
        toolbar.updatePreviewState(isPlaying: false)
        waveformView.updatePlaybackTime(0)
    }

    // MARK: - Session State Management (V2.1 文件联动)

    /// 使用 session 异步加载音频
    private func loadAudioWithSession() {
        guard let session = session else {
            loadAudio()
            return
        }

        EditorViewController.currentlyEditingURL = file.url
        waveformView.setLoadingState()
        navigationBar.setAllToolsEnabled(false)

        session.loadAudio { [weak self] success in
            guard let self = self else { return }
            if success, let buffer = session.audioBuffer, let format = session.audioFormat {
                self.audioBuffer = buffer
                self.audioFormat = format
                self.waveformView.loadAudio(from: buffer, sampleRate: format.sampleRate)
                self.navigationBar.setAllToolsEnabled(true)
                self.navigationBar.setToolEnabled(.trim, enabled: false)
                self.updateStatusBar()
                self.restoreViewportState(session.viewportState)
                self.logger.info("编辑器 session 加载完成: \(self.file.name)")
            } else {
                self.waveformView.loadError = session.loadError ?? "加载失败"
                self.waveformView.isLoading = false
                self.waveformView.needsDisplay = true
                EditorViewController.currentlyEditingURL = nil
                self.logger.error("session 加载失败: \(session.loadError ?? "unknown")")
            }
        }
    }

    /// 获取当前视口状态（供 SessionManager 保存）
    func currentViewportState() -> ViewportState {
        return ViewportState(
            zoomLevel: waveformView.currentZoomLevel,
            scrollOffset: waveformView.currentScrollOffset,
            playheadPosition: waveformView.currentPlayheadPosition
        )
    }

    /// 获取当前选区范围
    func currentSelectionRange() -> Range<Int>? {
        return waveformView.currentSelectionRange
    }

    /// 恢复视口状态
    private func restoreViewportState(_ state: ViewportState) {
        isUpdatingFromExternalSource = true
        waveformView.setZoomLevel(state.zoomLevel)
        waveformView.setScrollOffset(state.scrollOffset)
        waveformView.setPlayheadPosition(state.playheadPosition)
        isUpdatingFromExternalSource = false
        syncControlsToWaveformState()
    }

    // MARK: - Zoom/Scroll State Sync

    /// 将波形视图当前状态同步到缩放控件和滚动条
    private func syncControlsToWaveformState() {
        let zoomControls = toolbar.zoomControls
        let currentZoom = CGFloat(waveformView.currentZoomLevel)
        let maxZoom = waveformView.maxZoomLevel

        zoomControls.maxZoomLevel = maxZoom
        zoomControls.zoomLevel = currentZoom
        zoomControls.isAtMinZoom = currentZoom <= 1.0
        zoomControls.isAtMaxZoom = currentZoom >= maxZoom

        let totalDur = waveformView.totalDuration
        let visDur = waveformView.visibleDuration
        scrollBarView.visibleRatio = totalDur > 0 ? CGFloat(visDur / totalDur) : 1.0

        let scrollableRange = totalDur - visDur
        scrollBarView.scrollPosition = scrollableRange > 0
            ? CGFloat(waveformView.currentScrollOffset / scrollableRange)
            : 0

        // 显隐滚动条
        let shouldShowScrollBar = currentZoom > 1.0
        scrollBarView.isBarVisible = shouldShowScrollBar
        scrollBarHeightConstraint.constant = shouldShowScrollBar ? HorizontalScrollBarView.barHeight : 0
    }
}

// MARK: - ZoomControlsDelegate
extension EditorViewController: ZoomControlsDelegate {
    func zoomControlsDidTapZoomIn(_ controls: ZoomControlsView) {
        isUpdatingFromExternalSource = true
        waveformView.zoomIn(anchorX: nil)
        isUpdatingFromExternalSource = false
        syncControlsToWaveformState()
    }

    func zoomControlsDidTapZoomOut(_ controls: ZoomControlsView) {
        isUpdatingFromExternalSource = true
        waveformView.zoomOut(anchorX: nil)
        isUpdatingFromExternalSource = false
        syncControlsToWaveformState()
    }

    func zoomControlsDidTapFitAll(_ controls: ZoomControlsView) {
        isUpdatingFromExternalSource = true
        waveformView.fitAll()
        isUpdatingFromExternalSource = false
        syncControlsToWaveformState()
    }

    func zoomControls(_ controls: ZoomControlsView, didChangeSliderTo level: CGFloat) {
        isUpdatingFromExternalSource = true
        waveformView.setZoomLevel(Double(level))
        isUpdatingFromExternalSource = false
        syncControlsToWaveformState()
    }
}

// MARK: - HorizontalScrollBarDelegate
extension EditorViewController: HorizontalScrollBarDelegate {
    func scrollBar(_ scrollBar: HorizontalScrollBarView, didScrollTo position: CGFloat) {
        let totalDur = waveformView.totalDuration
        let visDur = waveformView.visibleDuration
        let scrollableRange = totalDur - visDur
        let offset = Double(position) * scrollableRange

        isUpdatingFromExternalSource = true
        waveformView.setScrollOffset(offset)
        isUpdatingFromExternalSource = false
        syncControlsToWaveformState()
    }
}

// MARK: - EditorRootView (Keyboard Handler)

/// 编辑器根视图 — 支持键盘快捷键处理
class EditorRootView: NSView {
    weak var keyHandler: EditorKeyboardHandler?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?.handleKeyDown(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

/// 键盘事件处理协议
protocol EditorKeyboardHandler: AnyObject {
    func handleKeyDown(_ event: NSEvent) -> Bool
}

// MARK: - EditorViewController + Keyboard
extension EditorViewController: EditorKeyboardHandler {
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCmd = flags.contains(.command)
        let hasShift = flags.contains(.shift)

        guard let chars = event.charactersIgnoringModifiers else { return false }

        // Cmd 组合键
        if hasCmd {
            switch chars {
            case "=", "+":
                // Cmd+= / Cmd++ : 放大
                waveformView.zoomIn(anchorX: nil)
                syncControlsToWaveformState()
                return true
            case "-":
                // Cmd+- : 缩小
                waveformView.zoomOut(anchorX: nil)
                syncControlsToWaveformState()
                return true
            case "0":
                // Cmd+0 : Fit All
                waveformView.fitAll()
                syncControlsToWaveformState()
                return true
            case "1":
                // Cmd+1 : 缩放到约 1 秒/屏
                zoomToVisibleDuration(1.0)
                return true
            case "2":
                // Cmd+2 : 缩放到约 10 秒/屏
                zoomToVisibleDuration(10.0)
                return true
            case "3":
                // Cmd+3 : 缩放到约 1 分钟/屏
                zoomToVisibleDuration(60.0)
                return true
            default:
                break
            }
        }

        // 方向键（无 Cmd）
        if !hasCmd {
            let keyCode = event.keyCode
            switch keyCode {
            case 123: // ←
                let scrollAmount = hasShift ? waveformView.visibleDuration * 0.5 : waveformView.visibleDuration * 0.1
                waveformView.setScrollOffset(waveformView.currentScrollOffset - scrollAmount)
                syncControlsToWaveformState()
                return true
            case 124: // →
                let scrollAmount = hasShift ? waveformView.visibleDuration * 0.5 : waveformView.visibleDuration * 0.1
                waveformView.setScrollOffset(waveformView.currentScrollOffset + scrollAmount)
                syncControlsToWaveformState()
                return true
            case 115: // Home
                waveformView.setScrollOffset(0)
                syncControlsToWaveformState()
                return true
            case 119: // End
                waveformView.setScrollOffset(waveformView.totalDuration - waveformView.visibleDuration)
                syncControlsToWaveformState()
                return true
            default:
                break
            }
        }

        return false
    }

    /// 缩放到指定可见时长（秒）
    private func zoomToVisibleDuration(_ targetDuration: TimeInterval) {
        let totalDur = waveformView.totalDuration
        guard totalDur > 0 else { return }
        let targetLevel = totalDur / min(targetDuration, totalDur)
        isUpdatingFromExternalSource = true
        waveformView.setZoomLevel(targetLevel)
        isUpdatingFromExternalSource = false
        syncControlsToWaveformState()
    }
    
    // MARK: - P0-A: 公开工具栏操作方法（供 MainWindowView EditToolbarView 调用）
    // 仅编辑器 embedded 模式使用。独立模式走 EditorNavigationBar/EditorToolbar。
    
    /// 切分 clip（P1-E）
    func handleSplit() {
        // P1-E: 在播放头位置切分 clip
        let time = waveformView.currentPlayheadPosition
        
        // 播放头边界检查
        guard time > 0.01, time < waveformView.totalDuration - 0.01 else {
            logger.warning("切分失败：播放头在边界位置")
            return
        }
        let cmd = SplitAudioClipCommand(time: time)
        executeCommand(cmd)
        hasUnsavedChanges = true
        waveformView.splitPointTime = time
        waveformView.needsDisplay = true
        updateStatusBar()
        logger.info("切分 audio clip at: \(String(format: "%.2f", time))s")
    }
    
    /// 静音裁剪
    func handleSilence() {
        performSilenceTrim()
    }
    
    /// 裁剪选区
    func handleTrim() {
        performTrim()
    }
    
    /// 标准化
    func handleNormalize() {
        performNormalize()
    }
    
    /// 淡入淡出
    func handleFade() {
        performFade()
    }
}

// MARK: - PropertiesPanelViewDelegate (P0: 右侧属性面板联动)
extension EditorViewController: PropertiesPanelViewDelegate {
    
    func propertiesPanel(_ panel: PropertiesPanelView, didChangeVolume volume: Float) {
        // TODO: 实时调整预览音量（不修改 buffer，只改 playerNode gain）
        previewPlayerNode?.volume = powf(10.0, volume / 20.0)  // dB → linear
        logger.info("音量调整: \(String(format: "%.1f", volume))dB")
    }
    
    func propertiesPanel(_ panel: PropertiesPanelView, didChangeFadeIn duration: TimeInterval) {
        // P0-3: Fade-in 时长由属性面板控制
        // 当前仅记录值，后续 P0-3 完成后联动到 Clip 模型的 fadeInDuration
        logger.info("淡入时长: \(String(format: "%.1f", duration))s")
    }
    
    func propertiesPanel(_ panel: PropertiesPanelView, didChangeFadeOut duration: TimeInterval) {
        // P0-3: Fade-out 时长由属性面板控制
        logger.info("淡出时长: \(String(format: "%.1f", duration))s")
    }
    
    func propertiesPanel(_ panel: PropertiesPanelView, didToggleEffect effectId: String, enabled: Bool) {
        logger.info("音效 \(effectId): \(enabled ? "开启" : "关闭")")
        // 后续实现各音效的处理逻辑
    }
}

