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

    /// V2.0: 编辑器会话（透明处理 .arlock 解密/重新加密）
    private var editSession: FileManagerUtils.EditSession?
    
    // 预览播放
    private var previewEngine: AVAudioEngine?
    private var previewPlayerNode: AVAudioPlayerNode?
    private var isPreviewPlaying: Bool = false
    private var previewTimer: Timer?
    private var previewStartHostTime: UInt64 = 0
    /// FIX-003: 预览代际 token——stop() 触发的旧 buffer completion 不得误杀新一轮播放
    private var previewGeneration = 0
    
    // 编辑器视图组件
    private let navigationBar = EditorNavigationBar()
    private let scrollBarView = HorizontalScrollBarView()
    private let toolbar = EditorToolbar()
    private let statusBar = EditorStatusBar()
    /// FEAT-001 S2 → UI-019: 转写分栏（design-B：轨道区与动作栏之间的常驻分栏，默认 186px，可拖拽/折叠）
    private let transcriptPanel = TranscriptPanelView()
    private var transcriptPanelHeightConstraint: NSLayoutConstraint?
    /// UI-019: 分栏展开状态（折叠 = 34px 仅标题条）
    private var isTranscriptVisible = true
    private var isTranscribing = false
    
    /// P0-B: 多轨道容器（替代原来的单个 waveformView）
    private let trackContainerView = TrackContainerView()

    /// UI-020: Clip 上下文工具条（选中 Clip 后上方浮出，浮在轨道区之上）
    // UI-028: ClipContextToolbarView 已移除——六命令统一从顶部导航栏（EditorNavigationBar）入口
    
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
        // V2.0: 清理加密编辑会话（临时 .m4a 文件）
        editSession?.cleanup()
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
        transcriptPanel.translatesAutoresizingMaskIntoConstraints = false

        editorView.addSubview(navigationBar)
        editorView.addSubview(trackContainerView)
        editorView.addSubview(scrollBarView)
        editorView.addSubview(toolbar)
        editorView.addSubview(transcriptPanel)
        editorView.addSubview(statusBar)

        // UI-028: 浮动上下文工具条已移除——切分/删除并入导航栏工具组（EditorToolType）
        navigationBar.setToolEnabled(.delete, enabled: false)

        // P0-B: 默认创建第一轨
        let defaultTrack = EditorAudioTrack(name: file.name, color: .coral)
        trackContainerView.tracks = [defaultTrack]

        scrollBarHeightConstraint = scrollBarView.heightAnchor.constraint(equalToConstant: 0)

        // FEAT-001 S2 → UI-019: 转写分栏高度（design-B：默认 186px 常驻，折叠 34px）
        transcriptPanelHeightConstraint = transcriptPanel.heightAnchor.constraint(equalToConstant: IndustrialSpacing.editorTranscriptDefaultHeight)

        // P0-A: 存储约束引用（嵌入模式下将高度压为 0）
        navBarHeightConstraint = navigationBar.heightAnchor.constraint(equalToConstant: IndustrialSpacing.editorNavBarHeight)
        toolbarHeightConstraint = toolbar.heightAnchor.constraint(equalToConstant: IndustrialSpacing.editorToolbarHeight)
        statusBarHeightConstraint = statusBar.heightAnchor.constraint(equalToConstant: IndustrialSpacing.editorStatusBarHeight)

        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: editorView.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),
            navBarHeightConstraint!,

            // UI-019 design-B 骨架 + UI-032 轨道带垂直居中：
            // 轨道区 layoutGuide（navigationBar ↔ transcriptPanel），trackContainer（intrinsic：
            // ruler 22 + N×140）在区间内垂直居中——对标剪映；多轨超高时 centerY(500)
            // 让位于 top≥(required)，容器回退贴顶+滚动（bottom≤ 749 放行溢出）。
            trackContainerView.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            trackContainerView.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),
        ])

        let trackArea = NSLayoutGuide()
        editorView.addLayoutGuide(trackArea)
        NSLayoutConstraint.activate([
            trackArea.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            trackArea.bottomAnchor.constraint(equalTo: transcriptPanel.topAnchor),
            trackArea.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            trackArea.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),

            trackContainerView.topAnchor.constraint(greaterThanOrEqualTo: trackArea.topAnchor),
        ])
        // 优先级需建约束后设置（anchor 构造器无 priority 参数）：
        // 多轨超高时 centerY(500) 让位于 top≥(required)，bottom≤(749) 放行溢出 → 回退贴顶+滚动
        let bottomFits = trackContainerView.bottomAnchor.constraint(lessThanOrEqualTo: trackArea.bottomAnchor)
        bottomFits.priority = NSLayoutConstraint.Priority(749)
        let centered = trackContainerView.centerYAnchor.constraint(equalTo: trackArea.centerYAnchor)
        centered.priority = NSLayoutConstraint.Priority(500)
        NSLayoutConstraint.activate([bottomFits, centered])

        NSLayoutConstraint.activate([

            // UI-019: 滚动条贴轨道区底部（原锚 toolbar，现动作栏移到分栏下方）
            scrollBarView.leadingAnchor.constraint(equalTo: editorView.leadingAnchor, constant: IndustrialSpacing.md),
            scrollBarView.trailingAnchor.constraint(equalTo: editorView.trailingAnchor, constant: -IndustrialSpacing.md),
            scrollBarView.bottomAnchor.constraint(equalTo: transcriptPanel.topAnchor, constant: -IndustrialSpacing.xs),
            scrollBarHeightConstraint,

            // UI-019: 转写分栏常驻——夹在轨道区与动作栏之间（B 稿 .trans 位于 .mid 底部、.actions 上方）
            transcriptPanel.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            transcriptPanel.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),
            transcriptPanel.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            transcriptPanelHeightConstraint!,

            // UI-019: 动作栏（toolbar）移到分栏下方、状态栏上方（B 稿 .actions）
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
        // UI-019: 分栏默认展开，文稿开关高亮
        toolbar.updateTranscriptToggle(isOn: true)
    }
    
    private func setupDelegates() {
        navigationBar.delegate = self
        waveformView.delegate = self
        toolbar.delegate = self
        toolbar.zoomControls.delegate = self
        scrollBarView.delegate = self
        transcriptPanel.delegate = self
        // UI-020: 读数三框可键入
        toolbar.selectionReadout.delegate = self
    }
    
    // MARK: - Audio Loading
    
    private func loadAudio() {
        EditorViewController.currentlyEditingURL = file.url
        waveformView.setLoadingState()
        navigationBar.setAllToolsEnabled(false)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // V2.0: .arlock 透明解密到临时 .m4a
                let editSession = try FileManagerUtils.shared.prepareForEditing(url: self.file.url)
                self.editSession = editSession
                let playableURL = editSession.playableURL
                
                let audioFile = try AVAudioFile(forReading: playableURL)
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
                        modifiedAt: modifiedAt,
                        playableURL: playableURL  // V2.0: .arlock 场景下指向临时 .m4a
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
                        // UI-020: 读数三框键入上界
                        self.toolbar.selectionReadout.totalDuration = duration
                        self.updateStatusBar()
                        // UI-019: 分栏常驻，独立加载路径也装载文稿
                        self.loadTranscriptForCurrentFile()
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
                            self.waveformView.loadError = "无法分配音频缓冲区（文件可能过大或内存不足）".localized
                            self.waveformView.isLoading = false
                            self.waveformView.needsDisplay = true
                            EditorViewController.currentlyEditingURL = nil
                            self.logger.error("无法分配音频缓冲区")
                        }
                        return
                    }
                    
                    try audioFile.read(into: buffer)

                    // DEBUG V2.0: 验证 buffer 内容
                    let readFrames = Int(buffer.frameLength)
                    var bufMax: Float = 0
                    if let chData = buffer.floatChannelData, readFrames > 0 {
                        for i in 0..<min(readFrames, 1000) {
                            let v = abs(chData[0][i])
                            if v > bufMax { bufMax = v }
                        }
                    }
                    self.logger.info("🔍 DEBUG: playableURL=\(playableURL.lastPathComponent), fileExists=\(FileManager.default.fileExists(atPath: playableURL.path)), readFrames=\(readFrames), firstFrameMax=\(bufMax)")

                    DispatchQueue.main.async {
                        self.audioBuffer = buffer
                        self.audioFormat = format
                        self.waveformView.loadAudio(from: buffer, sampleRate: format.sampleRate)
                        self.navigationBar.setAllToolsEnabled(true)
                        self.navigationBar.setToolEnabled(.trim, enabled: false)
                        // UI-020: 读数三框键入上界
                        self.toolbar.selectionReadout.totalDuration = Double(buffer.frameLength) / format.sampleRate
                        self.updateStatusBar()
                        // UI-019: 分栏常驻，独立加载路径也装载文稿
                        self.loadTranscriptForCurrentFile()
                        self.logger.info("编辑器加载完成: \(self.file.name), 帧数: \(frameCount), 采样率: \(format.sampleRate)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.waveformView.loadError = "无法读取音频文件: %@".localized(error.localizedDescription)
                    self.waveformView.isLoading = false
                    self.waveformView.needsDisplay = true
                    EditorViewController.currentlyEditingURL = nil
                    self.logger.error("加载音频文件失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Edit Operations
    
    /// INFRA-006: 无人值守自验时抑制失败弹窗（runModal 会卡死自测流水线）
    var suppressCommandAlerts = false

    /// 执行编辑命令；返回是否成功（失败已弹提示且不入历史）。UI-023/UI-022: 结果回传供调用方分流 UI 状态。
    @discardableResult
    func executeCommand(_ command: EditCommand) -> Bool {
        guard var buffer = audioBuffer else { return false }

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
            return true
        } else {
            guard !suppressCommandAlerts else {
                logger.warning("命令失败（自验静默）: \(command.description)")
                return false
            }
            // BUG-008 fix: 操作失败时提示用户
            let alert = NSAlert()
            alert.messageText = "操作失败".localized
            alert.informativeText = "无法执行「%@」。可能是音频信号过弱或数据异常。".localized(command.description)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定".localized)
            alert.runModal()
            return false
        }
    }

    // MARK: - INFRA-006 UI 自验 lite 通道

    /// 触发器 "N uitest" → 录音停止自动进编辑器后由 MainViewController 调用本方法。
    /// App 内脚本化执行 split/delete/undo/redo + 自进程 AX 按钮枚举（XCUITest 同源视角，自身进程免 TCC），
    /// 每步结果吐 UXEventLog("UITest", step)；外部 `scripts/test-ui-lite.sh` 读日志断言。
    /// 无人值守闭环的关键：不依赖 XCUITest Runner，绕开 LOOP-05 卡死的系统拉起链路。
    func runLiteSelftest() {
        var failures: [String] = []
        suppressCommandAlerts = true
        defer { suppressCommandAlerts = false }
        func report(_ step: String, _ pass: Bool, _ detail: [String: Any]) {
            UXEventLog.shared.module("UITest", step, ok: pass, detail: detail)
            if !pass { failures.append(step) }
        }

        guard let buffer = audioBuffer, let format = audioFormat, buffer.frameLength > 0 else {
            report("baseline", false, ["reason": "no buffer"])
            UXEventLog.shared.module("UITest", "done", ok: false, detail: ["failures": "baseline"])
            return
        }
        let sr = format.sampleRate
        let n0 = Int(buffer.frameLength)
        let dur = Double(buffer.frameLength) / sr
        report("baseline", true, ["frames": n0, "sr": sr, "duration_sec": (dur * 1000).rounded() / 1000])

        // 1) split @ 中点（口径 A：切分不动时间轴）→ 命令成功 + 切分线落位 + 样本数不变
        // （切分线在 handleSplit 的 UI 侧职责内，lite 序列直接调命令层须自画，模拟完整用户路径）
        let splitOK = executeCommand(SplitAudioClipCommand(time: dur / 2))
        if splitOK {
            waveformView.splitPointTime = dur / 2
            waveformView.needsDisplay = true
        }
        let framesAfterSplit = Int(audioBuffer?.frameLength ?? 0)
        report("split", splitOK && waveformView.splitPointTime != nil && framesAfterSplit == n0,
               ["ok": splitOK, "split_point": waveformView.splitPointTime ?? -1, "frames": framesAfterSplit])

        // 2) delete 中段 [25%, 75%] → 样本数按公式精确减少（±2 容差防 rounding 边缘）
        let del = DeleteSelectionCommand(startTime: dur * 0.25, endTime: dur * 0.75,
                                         sampleRate: sr, totalFrames: audioBuffer?.frameLength ?? 0)
        let delOK = executeCommand(del)
        let nDel = Int(audioBuffer?.frameLength ?? 0)
        let expectDel = n0 - Int((dur * 0.5 * sr).rounded())
        report("delete", delOK && abs(nDel - expectDel) <= 2,
               ["ok": delOK, "frames": nDel, "expected": expectDel])

        // 3) undo → 恢复 n0；4) redo → 回到删除后
        undo()
        let nUndo = Int(audioBuffer?.frameLength ?? 0)
        report("undo", nUndo == n0, ["frames": nUndo, "expected": n0])
        redo()
        let nRedo = Int(audioBuffer?.frameLength ?? 0)
        report("redo", abs(nRedo - expectDel) <= 2, ["frames": nRedo, "expected": expectDel])

        // 5) 自进程 AX 枚举：验证 AX 树可达性（XCUITest 查询的就是这条树）。
        // 判据 = windows 可读且遍历完成；按钮数作信息字段（自定义控件未设 accessibility role 时为 0，是真实暴露度信息）
        let axApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var buttons: [String] = []
        var nodeCount = 0
        func walk(_ el: AXUIElement, depth: Int) {
            guard depth < 10 else { return }
            nodeCount += 1
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else { return }
            if role == "AXButton" {
                var tRef: CFTypeRef?, dRef: CFTypeRef?
                let title = (AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &tRef) == .success) ? (tRef as? String) ?? "" : ""
                let desc = (AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &dRef) == .success) ? (dRef as? String) ?? "" : ""
                buttons.append(title.isEmpty ? desc : title)
            }
            var kidsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kidsRef) == .success,
               let kids = kidsRef as? [AXUIElement] {
                kids.forEach { walk($0, depth: depth + 1) }
            }
        }
        var axOK = false
        var winCount = 0
        var winsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
           let wins = winsRef as? [AXUIElement] {
            winCount = wins.count
            wins.forEach { walk($0, depth: 0) }
            axOK = winCount > 0 && nodeCount > 0
        }
        report("ax_enumerate", axOK, ["windows": winCount, "nodes": nodeCount,
                                      "button_count": buttons.count, "buttons": Array(buttons.prefix(12))])

        UXEventLog.shared.module("UITest", "done", ok: failures.isEmpty,
                                 detail: ["failures": failures.joined(separator: ","),
                                          "steps": 6 - failures.count])
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
                // V2.0: .arlock 自动重新加密；标准文件直接写回
                if let editSession = self.editSession {
                    try FileManagerUtils.shared.finalizeEdit(session: editSession, buffer: buffer, format: format)
                } else {
                    // 兜底：标准音频文件
                    let audioFile = try AVAudioFile(forWriting: self.file.url, settings: format.settings)
                    try audioFile.write(from: buffer)
                }

                DispatchQueue.main.async {
                    self.hasUnsavedChanges = false
                    self.editHistory.clear()
                    self.updateUndoRedoState()
                    self.navigationBar.setFileName("%@ ✓ 已保存".localized(self.file.name))
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
                    alert.messageText = "保存失败".localized
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "确定".localized)
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
            alert.messageText = "请先创建选区".localized
            alert.informativeText = "在波形上拖拽以选择要保留的区域，然后点击裁剪。".localized
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定".localized)
            alert.runModal()
            return
        }
        
        let totalDuration = Double(audioBuffer?.frameLength ?? 0) / format.sampleRate
        
        // 边界检查：极短文件或极短选区
        let selectionDuration = selection.upperBound - selection.lowerBound
        if selectionDuration < 0.1 {
            let alert = NSAlert()
            alert.messageText = "选区过短".localized
            alert.informativeText = "裁剪选区至少需要 0.1 秒。当前选区仅 %@ 秒。".localized(String(format: "%.2f", selectionDuration))
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定".localized)
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
            alert.messageText = "未检测到静音段".localized
            alert.informativeText = "当前阈值 %@ dB、最小时长 %@s 下未发现静音段。".localized(String(Int(params.thresholdDB)), String(format: "%.1f", params.minDuration))
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定".localized)
            alert.runModal()
            return
        }
        
        // 汇总信息
        let totalSilence = segments.reduce(0) { $0 + $1.duration }
        
        let alert = NSAlert()
        alert.messageText = "检测到 %@ 个静音段".localized(String(segments.count))
        alert.informativeText = "总计 %@ 秒静音。\n阈值: %@ dB，最小时长: %@s\n\n是否删除所有静音段？".localized(String(format: "%.1f", totalSilence), String(Int(params.thresholdDB)), String(format: "%.1f", params.minDuration))
        alert.alertStyle = .informational
        alert.addButton(withTitle: "删除全部".localized)
        alert.addButton(withTitle: "取消".localized)
        
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
        alert.messageText = "音量标准化".localized
        alert.informativeText = "选择目标响度预设：".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "播客 (-16 LUFS)".localized)
        alert.addButton(withTitle: "YouTube (-14 LUFS)".localized)
        alert.addButton(withTitle: "广播 (-24 LUFS)".localized)
        alert.addButton(withTitle: "取消".localized)
        
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
        alert.messageText = "淡入淡出".localized
        alert.informativeText = "将对整个音频应用淡入淡出效果。\n\n淡入: 0.5s / 淡出: 1.0s / 对数曲线\n\n音频时长: %@s".localized(String(format: "%.1f", totalDuration))
        alert.alertStyle = .informational
        alert.addButton(withTitle: "应用".localized)
        alert.addButton(withTitle: "仅淡入".localized)
        alert.addButton(withTitle: "仅淡出".localized)
        alert.addButton(withTitle: "取消".localized)
        
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
        if fadeIn > 0 { desc.append("淡入 %@s".localized(String(format: "%.1f", fadeIn))) }
        if fadeOut > 0 { desc.append("淡出 %@s".localized(String(format: "%.1f", fadeOut))) }
        logger.info("淡入淡出完成: \(desc.joined(separator: " + "))")
    }
    
    // MARK: - Exit
    
    func requestExit() {
        if hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "有未保存的编辑".localized
            alert.informativeText = "当前编辑尚未保存，是否保存后退出？".localized
            alert.addButton(withTitle: "保存".localized)
            alert.addButton(withTitle: "放弃".localized)
            alert.addButton(withTitle: "取消".localized)
            
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
        waveformView.loadError = "录音过大，已跳过编辑器加载，避免应用无响应".localized
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
        case .split:
            handleSplit()   // UI-028: 原浮动条切分入口并入（播放头位置切分）
        case .silenceTrim:
            performSilenceTrim()
        case .normalize:
            performNormalize()
        case .fade:
            performFade()
        case .delete:
            performDelete()  // UI-028: 原浮动条删除选区入口并入（UI-022 命令）
        }
    }
}

// MARK: - EditorWaveformViewDelegate
extension EditorViewController: EditorWaveformViewDelegate {
    /// UI-034 R2: 音量线拖拽 → 回放增益实时联动（clip 级；导出不应用，老板拍板 a）
    func editorWaveformView(_ view: EditorWaveformView, didChangeGain gain: Float) {
        previewPlayerNode?.volume = gain
    }

    func editorWaveformView(_ view: EditorWaveformView, didChangeSelection range: ClosedRange<TimeInterval>?) {
        let hasSelection = range != nil
        navigationBar.setToolEnabled(.trim, enabled: hasSelection)
        navigationBar.setToolEnabled(.fade, enabled: true)
        navigationBar.setToolEnabled(.normalize, enabled: true)
        navigationBar.setToolEnabled(.silenceTrim, enabled: true)
        // UI-022: 上下文工具条删除按钮随选区动态置灰/解除
        navigationBar.setToolEnabled(.delete, enabled: hasSelection)  // UI-028: 删除选区依赖选区，置灰语义沿用

        // UI-020: 读数三框同步（selection == nil 时显示 —）
        if let r = range {
            toolbar.selectionReadout.selectionStart = r.lowerBound
            toolbar.selectionReadout.selectionEnd = r.upperBound
            toolbar.selectionReadout.update(start: r.lowerBound, end: r.upperBound)
        } else {
            toolbar.selectionReadout.selectionStart = nil
            toolbar.selectionReadout.selectionEnd = nil
            toolbar.selectionReadout.update(start: nil, end: nil)
        }
    }

    func editorWaveformView(_ view: EditorWaveformView, didSeekTo time: TimeInterval) {
        waveformView.updatePlaybackTime(time)
        // 同步 playhead overlay（TrackContainerView 级别，与 ruler 共享坐标系）
        trackContainerView.updatePlayhead(time: time)
        statusBar.updateCurrentTime(time)
        // UI-021: seek 同步转写联动（当前句高亮 + 波形区间）
        syncTranscriptLinkage(at: time)
        // FIX-003(编辑器): 播放中选点 = 无缝跳播（stopPreview 已不归零，startPreview 读新 playhead 起播）
        if isPreviewPlaying {
            UXEventLog.shared.module("Editor", "seek", ok: true, detail: ["target_sec": time, "wasPlaying": true])
            startPreview()
        } else {
            UXEventLog.shared.module("Editor", "seek", ok: true, detail: ["target_sec": time, "wasPlaying": false])
        }
    }

    func editorWaveformViewDidChangeViewport(_ view: EditorWaveformView) {
        guard !isUpdatingFromExternalSource else { return }
        // P0-B: 同步横向贯通的时间刻度尺 viewport
        trackContainerView.updateRulerViewport(
            start: view.currentVisibleStartTime,
            duration: view.currentVisibleDuration
        )
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

    /// FEAT-001 S2 → UI-019: 切换转写分栏折叠（186px 展开 ↔ 34px 标题条，200ms easeOut）
    func editorToolbarDidToggleTranscript(_ toolbar: EditorToolbar) {
        toggleTranscriptFold()
        UXEventLog.shared.action("transcript_toggle", detail: ["visible": isTranscriptVisible])
    }

    /// UI-019: 折叠/展开切换（animator 默认隐式动画 ≈200ms，符合规格 §1.3 easeOut）
    private func toggleTranscriptFold() {
        isTranscriptVisible.toggle()
        let target: CGFloat = isTranscriptVisible ? IndustrialSpacing.editorTranscriptDefaultHeight : IndustrialSpacing.editorTranscriptFoldedHeight
        transcriptPanelHeightConstraint?.animator().constant = target
        transcriptPanel.setFolded(!isTranscriptVisible)
        toolbar.updateTranscriptToggle(isOn: isTranscriptVisible)
    }
}

// MARK: - Transcript Panel（FEAT-001 S2 + UI-019 拖拽/折叠）
extension EditorViewController: TranscriptPanelDelegate {

    /// UI-019: 拖柄拖拽调高（范围 34px ～ 60% 编辑区高）
    func transcriptPanel(_ panel: TranscriptPanelView, didDragToHeight height: CGFloat) {
        let maxHeight = editorView.bounds.height * 0.6
        let clamped = max(IndustrialSpacing.editorTranscriptFoldedHeight, min(maxHeight, height))
        // 拖拽中展开态生效；若从折叠态直接拖则同时解除折叠
        if clamped > IndustrialSpacing.editorTranscriptFoldedHeight && !isTranscriptVisible {
            isTranscriptVisible = true
            transcriptPanel.setFolded(false)
            toolbar.updateTranscriptToggle(isOn: true)
        }
        transcriptPanelHeightConstraint?.constant = clamped
    }

    /// UI-019: 双击拖柄 → 折叠/展开
    func transcriptPanelDidToggleFold(_ panel: TranscriptPanelView) {
        toggleTranscriptFold()
    }

    /// UI-021: 点句跳转（播放头落句起点 + 波形区间 teal 高亮，B 稿 state=5）
    func transcriptPanel(_ panel: TranscriptPanelView, didTapSegment segmentIndex: Int, start: TimeInterval, end: TimeInterval) {
        transcriptPanel(panel, didSeekSearchHit: start, end: end)
        UXEventLog.shared.action("transcript_seek", detail: ["segment": segmentIndex, "start_sec": start, "end_sec": end])
    }

    /// UI-021: 搜索命中跳转（与点句同联动）
    func transcriptPanel(_ panel: TranscriptPanelView, didSeekSearchHit start: TimeInterval, end: TimeInterval) {
        waveformView.segmentHighlight = start...max(start + 0.001, end)
        // 播放头落句起点（复用既有 seek 链路：播放中无缝跳播，停止时仅移游标）
        editorWaveformView(waveformView, didSeekTo: start)
    }

    /// UI-021: 播放时间 → 转写联动（当前句高亮滚动 + 波形区间随句移动）
    private func syncTranscriptLinkage(at time: TimeInterval) {
        if let seg = transcriptPanel.segmentContaining(time) {
            transcriptPanel.updateActiveSegment(seg.segmentIndex)
            let range = seg.start...max(seg.start + 0.001, seg.end)
            if waveformView.segmentHighlight != range {
                waveformView.segmentHighlight = range
            }
        } else {
            transcriptPanel.updateActiveSegment(nil)
            waveformView.segmentHighlight = nil
        }
    }

    /// 加载当前文件的转写文稿（有则展示，无则空态）
    private func loadTranscriptForCurrentFile() {
        if let transcript = TranscriptionService.shared.loadTranscript(for: file.url) {
            transcriptPanel.show(transcript: transcript)
        } else {
            transcriptPanel.setEmptyState()
        }
        // UI-021: 换文稿即清句↔波形联动状态
        transcriptPanel.updateActiveSegment(nil)
        waveformView.segmentHighlight = nil
    }

    func transcriptPanelDidTapTranscribe(_ panel: TranscriptPanelView) {
        guard !isTranscribing else { return }
        isTranscribing = true
        transcriptPanel.setTranscribing(true)
        UXEventLog.shared.action("transcribe_manual", detail: ["file": file.name])
        let url = file.url
        Task {
            do {
                let transcript = try await TranscriptionService.shared.transcribeRecording(
                    at: url,
                    localeID: TranscriptPanelView.preferredLocaleID
                )
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcriptPanel.setTranscribing(false)
                    self.transcriptPanel.show(transcript: transcript)
                    self.transcriptPanel.showStatus("转写完成: %d 字".localized(transcript.fullText.count))
                    UXEventLog.shared.module("Editor", "transcribe_done", ok: true, detail: ["chars": transcript.fullText.count, "file": self.file.name])
                }
            } catch {
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcriptPanel.setTranscribing(false)
                    self.transcriptPanel.showStatus("转写失败: %@".localized(error.localizedDescription))
                    UXEventLog.shared.module("Editor", "transcribe_done", ok: false, detail: ["error": error.localizedDescription])
                }
            }
        }
    }

    func transcriptPanelDidTapExport(_ panel: TranscriptPanelView) {
        guard let transcript = TranscriptionService.shared.loadTranscript(for: file.url) else { return }
        let savePanel = NSSavePanel()
        // FEAT-002: txt 与 md 双格式，面板底部下拉可选；默认 txt（老板主诉求）
        let txtType = UTType(filenameExtension: "txt") ?? .plainText
        let mdType = UTType(filenameExtension: "md") ?? .utf8PlainText
        savePanel.allowedContentTypes = [txtType, mdType]
        let baseName = file.name.replacingOccurrences(of: ".", with: "_")
        savePanel.nameFieldStringValue = "\(baseName).txt"
        savePanel.begin { [weak self] response in
            guard response == .OK, let target = savePanel.url else { return }
            // 按所选扩展名分派格式（面板格式下拉决定扩展名）
            let isTxt = target.pathExtension.lowercased() != "md"
            let content: String
            if isTxt {
                content = TranscriptPanelView.plainText(for: transcript, fileName: self?.file.name ?? baseName)
            } else {
                content = TranscriptPanelView.markdown(for: transcript, fileName: self?.file.name ?? baseName)
            }
            do {
                try content.write(to: target, atomically: true, encoding: .utf8)
                // 硬验证：读回确认内容非空且含全文
                let readBack = try String(contentsOf: target, encoding: .utf8)
                let ok = readBack.contains(transcript.fullText.prefix(20))
                UXEventLog.shared.module("Editor", "transcript_export", ok: ok, detail: ["path": target.lastPathComponent, "format": isTxt ? "txt" : "md", "bytes": readBack.utf8.count])
                // 反馈显示在文稿面板内（嵌入模式 statusBar 隐藏不可见——S2 老板报障点）
                self?.transcriptPanel.showStatus(ok ? "已导出: %@".localized(target.lastPathComponent) : "导出校验失败".localized)
                self?.logger.info("文稿导出成功: \(target.path) (\(readBack.utf8.count) bytes, \(isTxt ? "txt" : "md"))")
            } catch {
                UXEventLog.shared.module("Editor", "transcript_export", ok: false, detail: ["error": error.localizedDescription])
                self?.transcriptPanel.showStatus("导出失败: %@".localized(error.localizedDescription))
            }
        }
    }
}

// MARK: - Preview Playback
extension EditorViewController {

    func startPreview() {
        guard let buffer = audioBuffer, let format = audioFormat else { return }
        stopPreview()
        previewGeneration += 1
        let generation = previewGeneration

        // FIX-003(编辑器): 从 playhead 位置起播；已播到末尾则回 0 重播
        let totalDuration = Double(buffer.frameLength) / format.sampleRate
        var startOffset = waveformView.currentPlayheadPosition
        if startOffset < 0 { startOffset = 0 }
        if startOffset >= totalDuration - 0.05 { startOffset = 0 }
        let startFrame = AVAudioFrameCount(startOffset * format.sampleRate)

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            // AVAudioPlayerNode 不支持 offset 调度——从起始帧切片 buffer
            let playBuffer: AVAudioPCMBuffer
            if startFrame > 0, let sliced = Self.sliceBuffer(buffer, fromFrame: startFrame) {
                playBuffer = sliced
            } else {
                playBuffer = buffer
            }
            playerNode.scheduleBuffer(playBuffer, completionHandler: { [weak self] in
                // 代际防护：stop() 会触发旧 completion，异步回来时不得误杀新一轮播放
                DispatchQueue.main.async {
                    guard let self = self, generation == self.previewGeneration else { return }
                    self.stopPreview()
                }
            })
            playerNode.play()

            previewEngine = engine
            previewPlayerNode = playerNode
            isPreviewPlaying = true
            toolbar.updatePreviewState(isPlaying: true)

            // BUG-005 fix: 启动游标跟踪 timer（从起始 offset 累计）
            previewStartHostTime = mach_absolute_time()
            previewTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
                guard let self = self, self.isPreviewPlaying else { return }
                var info = mach_timebase_info_data_t()
                mach_timebase_info(&info)
                let elapsed = Double(mach_absolute_time() - self.previewStartHostTime) * Double(info.numer) / Double(info.denom) / 1_000_000_000
                let clampedTime = min(startOffset + elapsed, totalDuration)
                self.waveformView.updatePlaybackTime(clampedTime)
                self.trackContainerView.updatePlayhead(time: clampedTime)
                self.statusBar.updateCurrentTime(clampedTime)
                // UI-021: 转写联动（当前句高亮滚动 + 波形区间随句移动）
                self.syncTranscriptLinkage(at: clampedTime)
            }

            UXEventLog.shared.module("Editor", "play", ok: true, detail: ["start_sec": startOffset, "duration_sec": totalDuration, "file": file.name])
            logger.info("预览播放开始: offset=\(startOffset)s / \(totalDuration)s")
        } catch {
            logger.error("预览播放失败: \(error.localizedDescription)")
        }
    }

    func stopPreview() {
        previewGeneration += 1  // 使挂起的 buffer completion 全部失效
        previewTimer?.invalidate()
        previewTimer = nil
        previewPlayerNode?.stop()
        previewEngine?.stop()
        previewPlayerNode = nil
        previewEngine = nil
        isPreviewPlaying = false
        toolbar.updatePreviewState(isPlaying: false)
        // FIX-003(编辑器): 停止不再强制把 playhead 归零——保留选点位置，点播放从该处开始。
        // 自然播完时 timer 最后一帧已把 playhead 推到末尾（clampedTime = duration），下次播放自动回 0。
    }

    /// FIX-003(编辑器): 从指定帧切片 PCM buffer（float 非交织按声道拷贝，其余按字节平移）
    private static func sliceBuffer(_ buffer: AVAudioPCMBuffer, fromFrame: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let total = buffer.frameLength
        guard fromFrame > 0, fromFrame < total else { return nil }
        let frames = total - fromFrame
        guard let sliced = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames) else { return nil }
        sliced.frameLength = frames
        if let src = buffer.floatChannelData, let dst = sliced.floatChannelData {
            let bytes = Int(frames) * MemoryLayout<Float>.size
            for ch in 0..<Int(buffer.format.channelCount) {
                memcpy(dst[ch], src[ch].advanced(by: Int(fromFrame)), bytes)
            }
            return sliced
        }
        // 非 float 交织格式：按每帧字节平移整块拷贝
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        guard let srcPtr = buffer.audioBufferList.pointee.mBuffers.mData,
              let dstPtr = sliced.audioBufferList.pointee.mBuffers.mData else { return nil }
        memcpy(dstPtr, srcPtr.advanced(by: Int(fromFrame) * bytesPerFrame), Int(frames) * bytesPerFrame)
        return sliced
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
                self.loadTranscriptForCurrentFile()
                self.logger.info("编辑器 session 加载完成: \(self.file.name)")
            } else {
                self.waveformView.loadError = session.loadError ?? "加载失败".localized
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
        trackContainerView.updatePlayhead(time: state.playheadPosition)
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
    
    /// 切分 clip（P1-E → UI-023 转正）
    func handleSplit() {
        // P1-E: 在播放头位置切分 clip
        let time = waveformView.currentPlayheadPosition

        // 播放头边界检查
        guard time > 0.01, time < waveformView.totalDuration - 0.01 else {
            logger.warning("切分失败：播放头在边界位置")
            return
        }
        let cmd = SplitAudioClipCommand(time: time)
        // UI-023: 命令失败（样本级边界拒切等）不画切分线、不标脏
        guard executeCommand(cmd) else { return }
        hasUnsavedChanges = true
        waveformView.splitPointTime = time
        waveformView.needsDisplay = true
        updateStatusBar()
        logger.info("切分 audio clip at: \(String(format: "%.2f", time))s, splitFrame=\(cmd.splitFrame)")
    }
    
    /// 删除选区（UI-022）：删掉 [start, end) 样本，播放头夹到选区起点，选区清空
    func performDelete() {
        guard let buffer = audioBuffer, let format = audioFormat else { return }
        guard let selection = waveformView.selection else { return }

        let command = DeleteSelectionCommand(
            startTime: selection.lowerBound,
            endTime: selection.upperBound,
            sampleRate: format.sampleRate,
            totalFrames: buffer.frameLength
        )
        guard executeCommand(command) else { return }

        // 选区清空（新时长下不再有效）→ 播放头夹到删除点
        waveformView.clearSelection()
        let seekTarget = min(selection.lowerBound, waveformView.totalDuration)
        editorWaveformView(waveformView, didSeekTo: seekTarget)
        updateStatusBar()
        logger.info("删除选区完成: \(String(format: "%.2f", selection.lowerBound))s ~ \(String(format: "%.2f", selection.upperBound))s，剩余 \(String(format: "%.2f", waveformView.totalDuration))s")
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


// MARK: - SelectionReadoutDelegate（UI-020）
extension EditorViewController: SelectionReadoutDelegate {
    func selectionReadout(_ readout: SelectionReadoutView, didCommitStart start: TimeInterval?, end: TimeInterval?) {
        guard let s = start, let e = end, e > s else { return }
        let clampedS = max(0, min(s, waveformView.totalDuration))
        let clampedE = max(0, min(e, waveformView.totalDuration))
        guard clampedE > clampedS else { return }
        waveformView.setSelection(start: clampedS, end: clampedE)
        logger.info("UI-020 读数键入生效: \(clampedS)s ~ \(clampedE)s")
    }
}
