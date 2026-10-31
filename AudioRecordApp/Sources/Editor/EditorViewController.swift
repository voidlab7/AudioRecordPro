import Cocoa
import AVFoundation
import CryptoKit

// MARK: - Delegate Protocol
protocol EditorViewControllerDelegate: AnyObject {
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
    /// FIX-020: 回放增益节点（EQ globalGain，dB 直设；每轮 startPreview 重建，stopPreview 回收）
    private var previewGainNode: AVAudioUnitEQ?
    private var isPreviewPlaying: Bool = false
    private var previewTimer: Timer?
    private var previewStartHostTime: UInt64 = 0
    /// FIX-003: 预览代际 token——stop() 触发的旧 buffer completion 不得误杀新一轮播放
    private var previewGeneration = 0
    /// UI-039: 空格键局部事件监视器（随 editorView 挂/摘窗口挂撤）
    private var spaceKeyMonitor: Any?
    
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

    /// FEAT-007: 草稿恢复防重入（一次加载只应用一次）
    private var draftApplied = false

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

        // FEAT-007: 草稿有编辑时禁用缓存 buffer——缓存可能是上次会话编辑过的结果，
        // 复用会导致草稿重放「二次叠加」；必须从原始文件重新加载再重放
        let draftHasEdits = EditDraftStore.shared.hasEdits(for: file.url)
        if session.isLoaded, !draftHasEdits,
           let buffer = session.audioBuffer, let format = session.audioFormat {
            self.audioBuffer = buffer
            self.audioFormat = format
            waveformView.loadAudio(from: buffer, sampleRate: format.sampleRate)
            navigationBar.setAllToolsEnabled(true)
            navigationBar.setToolEnabled(.trim, enabled: false)
            updateStatusBar()
            // FEAT-007: 恢复增益（音量线状态随草稿）
            if let draft = EditDraftStore.shared.draft(for: file.url), draft.clipGain != 1.0 {
                waveformView.clipGain = draft.clipGain
                logger.info("草稿增益已恢复: \(draft.clipGain)")
            }
            // 恢复视图状态
            restoreViewportState(session.viewportState)
            logger.info("编辑器从 session 缓存加载: \(file.name)")
        } else {
            if draftHasEdits {
                logger.info("草稿有编辑，跳过 session 缓存从原始文件加载: \(file.name)")
            }
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
        // UI-039: 兜底撤监视器（正常路径 viewDidMoveToWindow(nil) 已撤，此处防泄漏）
        if let monitor = spaceKeyMonitor {
            if Thread.isMainThread {
                NSEvent.removeMonitor(monitor)
            } else {
                DispatchQueue.main.sync { NSEvent.removeMonitor(monitor) }
            }
            spaceKeyMonitor = nil
        }
    }
    
    // MARK: - Setup
    
    private func setupEditorView() {
        editorView.wantsLayer = true
        editorView.layer?.backgroundColor = IndustrialColors.surfaceContainerLowest.cgColor
        editorView.translatesAutoresizingMaskIntoConstraints = false
        editorView.keyHandler = self
        // UI-039: 空格键监视器随编辑器视图的窗口存在性挂/撤
        editorView.windowPresenceChanged = { [weak self] present in
            self?.updateSpaceKeyMonitor(present: present)
        }

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

            // UI-019 design-B 骨架 + UI-037 标尺贴顶分层：
            // trackContainer 钉满轨道区 layoutGuide（navigationBar ↔ transcriptPanel），
            // 内部由 TrackContainerView 分层——ruler 贴容器顶（=工具栏正下方），
            // 轨道行 stack 在「ruler 下沿 ↔ 容器底」内垂直居中（对标剪映），
            // 多轨超高时贴 ruler 下沿 + 溢出（bottom≤749 语义已在容器内部承载）。
            // 播放头 overlay 铺满容器 = 竖线从标尺顶贯穿到轨道区底。
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

            // UI-037: 容器钉满轨道区（原 UI-032 的整体 centerY 居中上移到容器内部
            // 的轨道行 stack 层——标尺不再随轨道带漂移）
            trackContainerView.topAnchor.constraint(equalTo: trackArea.topAnchor),
            trackContainerView.bottomAnchor.constraint(equalTo: trackArea.bottomAnchor),
        ])

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
        trackContainerView.seekDelegate = self  // UI-037: 空白区 seek
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
                        // FEAT-007: 加载完成后恢复草稿（命令栈重放 + 增益）
                        self.applyDraftIfNeeded()
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
                        // FEAT-007: 加载完成后恢复草稿（命令栈重放 + 增益）
                        self.applyDraftIfNeeded()
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
            // FEAT-007: 草稿自动保存——命令入栈即落盘，无「保存」概念
            EditDraftStore.shared.append(command.draftSpec,
                                         historyPosition: editHistory.position,
                                         for: file.url)
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
    /// App 内脚本化执行 split/delete/undo/redo + 自进程 AX 按钮枚举 + seek 对齐往返断言（UI-037）
    /// + 回放增益设值断言（FIX-020）
    /// （XCUITest 同源视角，自身进程免 TCC），
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

        // FEAT-007: 记录原始 .arlock 哈希（自验「原始文件永不覆盖」的基准）
        let originalHash = Self.sha256Hex(of: file.url)
        report("baseline_hash", originalHash != nil, ["sha256_prefix": originalHash?.prefix(16) ?? "-"])

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

        // FEAT-007 5) 草稿已自动落盘：split+delete 两条命令在栈，指针在 redo 后位置
        EditDraftStore.shared.flushForTesting()
        let draft = EditDraftStore.shared.draft(for: file.url)
        let draftOK = draft != nil
            && draft?.commands.count == 2
            && draft?.currentIndex == 1
            && draft?.hasRenderableEdits == true
        report("draft_saved", draftOK, [
            "ok": draftOK,
            "commands": draft?.commands.count ?? -1,
            "index": draft?.currentIndex ?? -99,
        ])

        // FEAT-007 6) 原始 .arlock 字节不变（非破坏编辑核心承诺）
        let hashAfterEdits = Self.sha256Hex(of: file.url)
        let untouched = originalHash != nil && hashAfterEdits == originalHash
        report("original_untouched", untouched, ["sha256_prefix": hashAfterEdits?.prefix(16) ?? "-"])

        // FEAT-007 7) 渲染引擎通路验证：渲染引擎（导出同核）对当前 buffer 深拷贝 + gain=1 幂等，
        // 帧数与样本字节不变（命令级重放正确性由 SDK 单测覆盖，见 EditDraftTests）
        var renderFrames = -1
        if let current = audioBuffer, let fresh = DraftRenderEngine.duplicate(current) {
            if let rendered = DraftRenderEngine.render(input: fresh,
                                                       commands: [],
                                                       currentIndex: -1,
                                                       clipGain: 1.0,
                                                       factory: { DraftSpecFactory.command(from: $0, buffer: $1) }) {
                renderFrames = Int(rendered.frameLength)
            }
        }
        report("draft_render", renderFrames == nRedo, ["frames": renderFrames, "expected": nRedo])

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

        // 6) UI-037: seek 对齐断言（标尺/空白区 seek 换算与 playhead/ruler 同坐标系往返）。
        // 时间→x→时间往返误差 <10ms 且 x 落在 header 列右侧，证明空白区点击 seek
        // 与时间刻度精准卡住（PlayheadOverlayView.playheadX 同公式互逆）。
        trackContainerView.updateRulerViewport(start: 0, duration: dur)
        let seekTarget = dur * 0.3
        let seekX = trackContainerView.canvasX(forSeekTime: seekTarget)
        let seekRoundTrip = trackContainerView.seekTime(forCanvasX: seekX)
        report("seek_align", abs(seekRoundTrip - seekTarget) < 0.01 && seekX >= EditorTrackRowView.headerWidth,
               ["target_sec": (seekTarget * 1000).rounded() / 1000,
                "x": (seekX * 10).rounded() / 10,
                "roundtrip_sec": (seekRoundTrip * 1000).rounded() / 1000])

        // 7) FIX-020: 回放增益设值断言——EQ globalGain 与 clipGain 对应。
        // 真实链路验证三件事：①建链（startPreview）即应用当前增益（旧 bug 主因=重建节点后从不读取）；
        // ②播放中改增益实时映射（走拖线同款 delegate 路径）；③停止后节点回收。
        // 起始 gain=0 → EQ −96dB，全程静音，lite 无噪音输出。
        waveformView.clipGain = 0
        startPreview()
        var gainOK = true
        var nodeAlive = false
        if let eq = previewGainNode {
            nodeAlive = true
            gainOK = gainOK && abs(Double(eq.globalGain) - GainScale.playbackDB(for: 0)) < 0.01
            waveformView.clipGain = 1.0
            editorWaveformView(waveformView, didChangeGain: waveformView.clipGain)  // 拖线同款 delegate 路径
            gainOK = gainOK && abs(Double(eq.globalGain) - GainScale.playbackDB(for: 1.0)) < 0.01
            waveformView.clipGain = 4.0
            editorWaveformView(waveformView, didChangeGain: waveformView.clipGain)
            gainOK = gainOK && abs(Double(eq.globalGain) - GainScale.playbackDB(for: 4.0)) < 0.01
        } else {
            gainOK = false
        }
        stopPreview()
        let gainStoppedClean = previewGainNode == nil && previewPlayerNode == nil
        // 增益映射纯函数断言：1.0→0dB / 上限 10.0→+20dB / 0→−96dB 静音（钳制与标尺同源）
        let gainMapOK = abs(GainScale.playbackDB(for: 1.0)) < 0.001
            && abs(GainScale.playbackDB(for: GainScale.maxLinear) - 20.0) < 0.001
            && GainScale.playbackDB(for: 0) == GainScale.muteDB
        waveformView.clipGain = 1.0  // 复位视图与草稿
        EditDraftStore.shared.setGain(1.0, for: file.url)
        report("playback_gain", gainOK && gainStoppedClean && gainMapOK,
               ["ok": gainOK && gainStoppedClean && gainMapOK,
                "node_alive": nodeAlive,
                "gain0_db": GainScale.playbackDB(for: 0),
                "gain1_db": GainScale.playbackDB(for: 1.0),
                "gain4_db": (GainScale.playbackDB(for: 4.0) * 1000).rounded() / 1000,
                "stopped_clean": gainStoppedClean])

        // 8) UI-041: 波形精细层（视口逐列真峰值）——放大态切换判定 + 精细数组形态。
        // 粗路径（固定桶复制+平滑）放大后呈死平带（老板实机反馈，对照剪映有波纹）；
        // 断言：①精细层已挂 buffer ②放大后命中精细判定 ③列数==pixelCount
        // ④数组可画（有起伏，或区段低于 −60dBFS 门限全归零——两者均属正确渲染）。
        // 注：不硬断言「概览态必走粗路径」——selftest 时序内 allSamples 常为 Phase1 极粗桶
        // （~100 桶 < 列数），此时概览态切精细层本身就是更真实的渲染；Phase2 桶密度判定
        // 由 WaveformViewportPeaksTests.testFitAllStaysCoarse 以合成口径覆盖。
        let fineState0 = waveformView.debugFineLayerState()
        let fineAttached = fineState0 != nil
        waveformView.setZoomLevel(64)
        let fineState = waveformView.debugFineLayerState()
        let fineActive = fineState?.fineActive == true
        let finePeaks = fineState?.peaks ?? []
        let finePixelCount = fineState?.pixelCount ?? 0
        let shapeOK = fineActive && finePixelCount > 1 && finePeaks.count == finePixelCount
        let drawableOK = finePeaks.contains { $0 > 0 } || finePeaks.allSatisfy { $0 == 0 }
        waveformView.fitAll()  // 复位概览态
        report("fine_peaks", fineAttached && shapeOK && drawableOK,
               ["ok": fineAttached && shapeOK && drawableOK,
                "fine_attached": fineAttached,
                "fine_active": fineActive,
                "pixel_count": finePixelCount,
                "peak_max": ((finePeaks.max() ?? 0) * 1000).rounded() / 1000,
                "peak_range": (((finePeaks.max() ?? 0) - (finePeaks.min() ?? 0)) * 1000).rounded() / 1000])

        // 9) UI-039: 空格键 toggle 播放/暂停——合成空格 keyDown 走 handleSpaceKeyEvent
        //    同一分发路径（监视器与 lite 共用，SpaceKeyPolicy 三态判定 SpaceKeyPolicyTests
        //    单测覆盖）。断言六件：toggle→播放；再 toggle→暂停且 playhead 原位（暂停语义
        //    不归零）；keyRepeat 帧不切换；Cmd+Space 组合放行不切换（R10 坑1 显式位判定
        //    回归）；文本输入框聚焦时不触发播放（真窗口 makeFirstResponder 隔离断言，
        //    R10 遗留「留实机确认」项的确定性闭环）；收尾 stopPreview 清场。
        func synthSpace(isARepeat: Bool, command: Bool = false) -> NSEvent? {
            guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true) else { return nil }
            cg.keyboardSetUnicodeString(stringLength: 1, unicodeString: [0x20])  // 空格字符：charactersIgnoringModifiers guard 需要（R10 坑2）
            cg.setIntegerValueField(.keyboardEventAutorepeat, value: isARepeat ? 1 : 0)
            if command {
                cg.flags = .maskCommand
            }
            return NSEvent(cgEvent: cg)
        }
        let spaceStart = dur * 0.5
        editorWaveformView(waveformView, didSeekTo: spaceStart)  // 摆非零起点：暂停后必须原位（暂停语义=不归零）
        let evPlay = synthSpace(isARepeat: false).flatMap { handleSpaceKeyEvent($0) }
        let nowPlaying = isPreviewPlaying
        let evPause = synthSpace(isARepeat: false).flatMap { handleSpaceKeyEvent($0) }
        let nowPaused = !isPreviewPlaying
        // 同步连发下 cursor timer（33ms）一帧未跑，暂停后 playhead 应精确停在起点（stopPreview 不动 playhead）
        let playheadKept = abs(waveformView.currentPlayheadPosition - spaceStart) < 0.1
        let evRepeat = synthSpace(isARepeat: true).flatMap { handleSpaceKeyEvent($0) }
        let repeatSwallowed = !isPreviewPlaying   // repeat 帧吞掉但不得把播放拉起
        let evCmd = synthSpace(isARepeat: false, command: true).flatMap { handleSpaceKeyEvent($0) }
        let cmdPassed = evCmd == false && !isPreviewPlaying   // Cmd+Space 放行且不切换
        // 文本焦点隔离：真窗口挂临时输入框并置为 firstResponder（field editor 语义与
        // 选区读数三框/搜索框一致），空格必须放行（不消费、不切换），随后恢复并断言恢复后可 toggle
        var textFocusIsolated = false
        var resumeToggleWorks = false
        if let window = editorView.window {
            let scratchField = NSTextField(frame: NSRect(x: -200, y: -200, width: 10, height: 10))
            scratchField.isEditable = true
            editorView.addSubview(scratchField)
            window.makeFirstResponder(scratchField)
            let isolated = Self.textEntryFirstResponder(in: window)
            let evWhileFocused = synthSpace(isARepeat: false).flatMap { handleSpaceKeyEvent($0) }
            textFocusIsolated = isolated && evWhileFocused == false && !isPreviewPlaying
            window.makeFirstResponder(nil)
            scratchField.removeFromSuperview()
            if let evResume = synthSpace(isARepeat: false).flatMap({ handleSpaceKeyEvent($0) }), evResume {
                resumeToggleWorks = isPreviewPlaying   // 恢复后空格再触发播放
            }
        }
        stopPreview()  // 清场：无论断言成败不外溢播放
        let spaceOK = (evPlay == true) && nowPlaying && (evPause == true) && nowPaused
            && playheadKept && (evRepeat == true) && repeatSwallowed && cmdPassed
            && textFocusIsolated && resumeToggleWorks
        let frDesc: String
        let keyWin: Bool
        if let window = editorView.window {
            frDesc = String(describing: type(of: window.firstResponder))
            keyWin = window.isKeyWindow
        } else {
            frDesc = "no-window"
            keyWin = false
        }
        report("space_toggle", spaceOK,
               ["toggle_play": nowPlaying, "toggle_pause": nowPaused,
                "ev_play": evPlay == true, "ev_pause": evPause == true,
                "ev_repeat": evRepeat == true, "repeat_swallowed": repeatSwallowed,
                "ev_cmd": evCmd == false, "cmd_passed": cmdPassed,
                "playhead_kept": playheadKept,
                "playhead_start": (spaceStart * 100).rounded() / 100,
                "playhead_after": (waveformView.currentPlayheadPosition * 100).rounded() / 100,
                "text_focus_isolated": textFocusIsolated,
                "resume_toggle_works": resumeToggleWorks,
                "first_responder": frDesc, "key_window": keyWin])

        // 10) UI-042 + 老板 10-31 实机补充（「轨道头都不动，像文档的冻结首行」）：
        // 真实窗口 setFrame 驱动（触发完整 Auto Layout → EditorWaveformView.layout() 全真实
        // 路径，替代此前手动调 applyResizeLock 的模拟口径）。断言四件：
        // ①pps 恒定（波形不拉伸）②非零起点锚左缘保持 ③niceStep 档位不变
        // ④轨道头列冻结——行内波形左缘恒为 headerWidth(88)，窗口伸缩不侵占头列（冻结首列实证）。
        // 锚点数学：fitAll→2x zoom→滚到 0.2dur 后，0.8x（0.2+0.4dur）/1.25x（0.2+0.5dur）
        // 两轮 start+duration 均未越尾，锚定断言有区分度。
        // 抗干扰：实机验收期老板触控板/鼠标事件会污染 viewport（捏合改 zoom、双指平移改
        // start，R2 实锤 v0 被外部事件改写）——探针失败自动重摆重试一次（随机干扰不连续命中）。
        var resizeOK = false
        var resizeDetail: [String: Any] = ["skipped": "no-resizable-window"]
        if let win = editorView.window, win.styleMask.contains(.resizable) {
            let f0 = win.frame
            // 先归一化窗口到当前 frame（消除历史布局状态/lastLaidOutWidth 的不确定性），
            // 再摆 viewport——保证后续 narrow/wide 两轮的锁定推导链条完全确定
            win.setFrame(f0, display: true)
            win.contentView?.layoutSubtreeIfNeeded()
            let w0 = waveformView.bounds.width
            if w0 > 40, f0.width > 200 {
                func niceStep(forPPS p: Double) -> TimeInterval {
                    let raw = 80.0 / max(p, 0.001)
                    for s: TimeInterval in [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600] {
                        if s >= raw { return s }
                    }
                    return 600
                }

                // 单轮探针：摆 viewport → 真实 resize 两轮 → 断言四件 → 还原窗口复位。
                // 视口基准一律用 waveformView.totalDuration（lite 顶层 dur 是 undo 后全长，
                // 而 redo 停在删除态 → total=一半，错用会令锚点数学全错，R2 实锤）。
                // wide 轮回到 f0 原宽（0.8×1.0）：0.2+0.5total 未越尾，无 clamp 干扰锚点断言。
                func runResizeProbe(attempt: Int) -> (Bool, [String: Any]) {
                    let total = waveformView.totalDuration
                    waveformView.fitAll()
                    waveformView.setZoomLevel(2)
                    waveformView.setScrollOffset(total * 0.2)
                    let v0 = waveformView.currentVisibleDuration
                    let start0 = waveformView.currentVisibleStartTime
                    let pps0 = ViewportResizeLock.pixelsPerSecond(viewWidth: w0, visibleDuration: v0)
                    let headerX0 = trackContainerView.trackRows.first?.waveformView.frame.origin.x ?? -1

                    func performRealResize(_ scale: CGFloat) -> (pps: Double, start: TimeInterval, w: CGFloat, headerX: CGFloat) {
                        win.setFrame(NSRect(origin: f0.origin,
                                            size: NSSize(width: f0.width * scale, height: f0.height)),
                                     display: true)
                        win.contentView?.layoutSubtreeIfNeeded()  // 强制同步 Auto Layout pass（真实 layout 链）
                        let w = waveformView.bounds.width
                        let pps = ViewportResizeLock.pixelsPerSecond(viewWidth: w, visibleDuration: waveformView.currentVisibleDuration)
                        return (pps, waveformView.currentVisibleStartTime, w,
                                trackContainerView.trackRows.first?.waveformView.frame.origin.x ?? -1)
                    }

                    let narrow = performRealResize(0.8)
                    let wide = performRealResize(1.0)  // 回原宽：锁映射下 v 应精确还原 v0
                    win.setFrame(f0, display: true)    // 还原窗口（自验零副作用）
                    win.contentView?.layoutSubtreeIfNeeded()

                    let relNarrow = pps0 > 0 ? abs(narrow.pps - pps0) / pps0 : 1
                    let relWide = pps0 > 0 ? abs(wide.pps - pps0) / pps0 : 1
                    let ppsStable = relNarrow < 0.02 && relWide < 0.02
                    let stepStable = niceStep(forPPS: pps0) == niceStep(forPPS: narrow.pps)
                        && niceStep(forPPS: pps0) == niceStep(forPPS: wide.pps)
                    let anchorHeld = abs(narrow.start - start0) < 0.001 && abs(wide.start - start0) < 0.001
                    // 冻结首列：波形行内左缘 == headerWidth(88)，两轮真实 resize 后不动
                    let headerFrozen = abs(narrow.headerX - headerX0) < 0.5
                        && abs(wide.headerX - headerX0) < 0.5
                        && abs(headerX0 - EditorTrackRowView.headerWidth) < 0.5
                    let ok = ppsStable && stepStable && anchorHeld && headerFrozen
                    waveformView.fitAll()  // 复位概览态
                    let detail: [String: Any] = [
                        "ok": ok,
                        "real_window_resize": true,
                        "attempt": attempt,
                        "w0": (w0 * 10).rounded() / 10,
                        "total": (total * 1000).rounded() / 1000,
                        "v0": (v0 * 1000).rounded() / 1000,
                        "pps0": (pps0 * 100).rounded() / 100,
                        "pps_narrow": (narrow.pps * 100).rounded() / 100,
                        "pps_wide": (wide.pps * 100).rounded() / 100,
                        "rel_narrow_pct": (relNarrow * 10000).rounded() / 100,
                        "rel_wide_pct": (relWide * 10000).rounded() / 100,
                        "step_stable": stepStable,
                        "anchor_start0": (start0 * 1000).rounded() / 1000,
                        "anchor_narrow": (narrow.start * 1000).rounded() / 1000,
                        "anchor_wide": (wide.start * 1000).rounded() / 1000,
                        "header_x0": (headerX0 * 10).rounded() / 10,
                        "header_x_narrow": (narrow.headerX * 10).rounded() / 10,
                        "header_x_wide": (wide.headerX * 10).rounded() / 10,
                        "header_frozen": headerFrozen,
                    ]
                    return (ok, detail)
                }

                let first = runResizeProbe(attempt: 1)
                if first.0 {
                    resizeOK = true
                    resizeDetail = first.1
                } else {
                    let second = runResizeProbe(attempt: 2)
                    resizeOK = second.0
                    resizeDetail = second.1
                    if !second.0 { resizeDetail["first_attempt_also_failed"] = true }
                }
            } else {
                resizeDetail = ["skipped": "window-too-small"]
            }
        }
        report("resize_lock", resizeOK, resizeDetail)

        UXEventLog.shared.module("UITest", "done", ok: failures.isEmpty,
                                 detail: ["failures": failures.joined(separator: ","),
                                          "steps": 15 - failures.count])
    }

    /// FEAT-007: 文件 SHA256 十六进制摘要（自验「原始文件永不覆盖」判据）
    private static func sha256Hex(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
            // FEAT-007: 撤销指针同步进草稿（重开后撤销延续）
            EditDraftStore.shared.syncIndex(editHistory.position, for: file.url)
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
            // FEAT-007: 重做指针同步进草稿
            EditDraftStore.shared.syncIndex(editHistory.position, for: file.url)
            logger.info("重做编辑操作")
        }
    }
    
    // MARK: - FEAT-007 草稿恢复

    /// 加载完成后恢复草稿：原始 buffer + 命令栈重放 + 增益。
    /// 幂等（draftApplied 防重入）；草稿失效/重放失败时丢弃草稿，回落到原始音频。
    private func applyDraftIfNeeded() {
        guard !draftApplied, audioBuffer != nil, audioFormat != nil else { return }
        draftApplied = true

        guard let draft = EditDraftStore.shared.draft(for: file.url) else { return }

        // 完整性校验：原始文件被替换（大小不一致）→ 草稿不可信，丢弃
        guard EditDraftStore.shared.isDraftValid(draft, originalURL: file.url) else {
            logger.warning("草稿与原始文件不匹配，丢弃草稿: \(file.name)")
            EditDraftStore.shared.remove(for: file.url)
            return
        }

        // 增益恢复（音量线状态，无论有无命令栈）
        if draft.clipGain != 1.0 {
            waveformView.clipGain = draft.clipGain
            // FIX-020: 正在预览则同步到 EQ；未播放时由 startPreview 建链时应用
            previewGainNode?.globalGain = Float(GainScale.playbackDB(for: draft.clipGain))
            logger.info("草稿增益已恢复: \(draft.clipGain)")
        }

        // 命令栈重放（含已撤销段之间的指针位置；重放同时捕获 undo 数据，撤销延续）
        guard draft.hasEdits, let format = audioFormat else { return }
        guard var buffer = audioBuffer else { return }
        if editHistory.replay(specs: draft.commands,
                              upTo: draft.currentIndex,
                              on: &buffer,
                              factory: { DraftSpecFactory.command(from: $0, buffer: $1) }) {
            audioBuffer = buffer
            hasUnsavedChanges = editHistory.stepCount > 0
            waveformView.loadAudio(from: buffer, sampleRate: format.sampleRate)
            waveformView.invalidateAllTiles()
            // 重放后指针可能与草稿记录有偏差（maxSteps 截断），以历史栈为准回写对齐
            if editHistory.position != draft.currentIndex {
                EditDraftStore.shared.syncIndex(editHistory.position, for: file.url)
            }
            updateUndoRedoState()
            updateStatusBar()
            logger.info("草稿已恢复: \(draft.commands.count) 条命令 @\(editHistory.position), \(file.name)")
        } else {
            // replay 失败已内部回滚（buffer 与历史栈不变）；草稿损坏，丢弃防反复失败
            logger.error("草稿重放失败，已丢弃草稿: \(file.name)")
            EditDraftStore.shared.remove(for: file.url)
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
        // FEAT-007: 非破坏编辑——草稿已随每次编辑自动落盘，无「保存」概念，直接退出
        EditorViewController.currentlyEditingURL = nil
        delegate?.editorDidCancel(self)
    }
    
    // MARK: - Private Helpers
    
    private func updateUndoRedoState() {
        navigationBar.updateUndoRedoState(canUndo: editHistory.canUndo, canRedo: editHistory.canRedo)
        // FEAT-007: 无「保存」概念——编辑即草稿自动落盘；hasUnsavedChanges 仅作「有编辑」标记
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
    /// UI-034 R2: 音量线拖拽 → 回放增益实时联动（clip 级）
    /// FEAT-007 (2026-10-30): 增益随草稿自动落盘并纳入导出渲染（取代 UI-034 拍板 a「导出不应用增益」）
    func editorWaveformView(_ view: EditorWaveformView, didChangeGain gain: Float) {
        // FIX-020: 播放中实时拖线 → EQ globalGain（dB 直设，−24～+20 全标尺）；
        // 未在播放时节点为 nil，仅落草稿，下次 startPreview 建链即应用
        previewGainNode?.globalGain = Float(GainScale.playbackDB(for: gain))
        EditDraftStore.shared.setGain(gain, for: file.url)
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

// MARK: - TrackContainerViewSeekDelegate（UI-037：标尺/空白区点击拖拽 seek）
extension EditorViewController: TrackContainerViewSeekDelegate {
    /// 空白区 seek：clamp 到音频时长后复用波形行 seek 的统一链路
    /// （playhead overlay 同步、状态栏、转写联动、播放中无缝跳播全继承）。
    func trackContainerView(_ view: TrackContainerView, didSeekTo time: TimeInterval) {
        let clamped = max(0, min(time, waveformView.totalDuration))
        editorWaveformView(waveformView, didSeekTo: clamped)
    }
}

// MARK: - EditorToolbarDelegate
extension EditorViewController: EditorToolbarDelegate {
    func editorToolbarDidTapPreviewPlay(_ toolbar: EditorToolbar) {
        togglePlayback()   // UI-039: 空格键与播放按钮收敛为同一控制入口
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

    /// UI-039: 空格键播放/暂停切换。暂停复用 stopPreview（FIX-003 保留 playhead 位置
    /// = 暂停语义），再按 startPreview 从暂停处续播——与工具栏播放按钮同一控制入口，
    /// 不另起播放逻辑。
    func togglePlayback() {
        if isPreviewPlaying {
            stopPreview()
        } else {
            startPreview()
        }
    }

    // MARK: 空格键局部监视器（UI-039）

    /// 编辑器激活期间拦截空格键（编辑器窗口聚焦 + firstResponder 非文本编辑视图）。
    /// 为什么用局部监视器而不是 EditorRootView.keyDown：工程无焦点保障链（无
    /// makeFirstResponder 调用），编辑器打开后 firstResponder 可能是 toolbar 输入框
    /// 或窗口自身，「打开编辑器直接按空格」在 keyDown 方案下不可靠；监视器 +
    /// firstResponder 文本判定把需求细项 2 的隔离变成显式可断言规则，且点击按钮
    /// 后空格仍触发播放（剪映同款行为，不随按钮聚焦失效）。UI-040（主界面空格
    /// 录音）可用同构机制分派，两单天然正交。
    /// 线程约定：viewDidMoveToWindow 与 NSEvent 分发均主线程（同 UXEventLog 先例）。
    private func updateSpaceKeyMonitor(present: Bool) {
        if present, spaceKeyMonitor == nil {
            spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // 编辑器窗口聚焦（需求细项 1）在窗口分发层判定：局部监视器只收本 app
                // 事件，非 key 窗口时正常键盘事件本就进不来，此 guard 防的是 CGEvent
                // 注入等合成边缘；lite 直调 handleSpaceKeyEvent 测逻辑分发，不受
                // 「哪个 app 在前台」污染（R3 实锤：无人值守跑批时主窗口非 key 属常态）。
                guard let window = self.editorView.window, window.isKeyWindow,
                      self.handleSpaceKeyEvent(event) else { return event }
                return nil   // 消费：事件不再进入后续分发（防双触发）
            }
            // 初始焦点收归：编辑器挂载时 keyViewLoop 可能把初始焦点分配给可编辑控件
            // （搜索框/选区读数框），用户未点击输入框时空格会打进输入框而非播放
            // （lite 第 14 步实锤：全序列 textFocus=true → 空格全部 passthrough）。
            // 收归到窗口自身 = 空格直接可播；用户显式点击输入框时焦点自然进入（显式
            // 意图不受影响，未提交内容走 textDidEndEditing 正常 commit）。
            // 延迟一拍：等 AppKit 完成初始 firstResponder 分配再做判定。
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.editorView.window,
                      Self.textEntryFirstResponder(in: window) else { return }
                window.makeFirstResponder(nil)
            }
        } else if !present, let monitor = spaceKeyMonitor {
            NSEvent.removeMonitor(monitor)
            spaceKeyMonitor = nil
        }
    }

    /// 空格键逻辑分发（lite 第 14 步以合成事件走同一路径）。
    /// 窗口级判定（编辑器挂载/isKeyWindow）在监视器闭包；此处只管事件语义。
    /// 返回 true = 事件已消费。
    func handleSpaceKeyEvent(_ event: NSEvent) -> Bool {
        guard let window = editorView.window else { return false }   // 编辑器已摘出窗口
        // 修饰键 rawValue 先过 deviceIndependentFlagsMask 交集（与既有 handleKeyDown 同口径），
        // 判定委托 SpaceKeyPolicy（Kit 纯函数，SpaceKeyPolicyTests 单测覆盖）
        let rawModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        let textFocus = Self.textEntryFirstResponder(in: window)
        switch SpaceKeyPolicy.decide(keyCode: event.keyCode,
                                     rawModifiers: rawModifiers,
                                     isARepeat: event.isARepeat,
                                     textEntryFocus: textFocus) {
        case .passthrough:
            return false
        case .swallowRepeat:
            return true   // 长按连发帧吞掉但不切换
        case .toggle:
            UXEventLog.shared.module("Editor", "space_toggle", ok: true,
                                     detail: ["wasPlaying": isPreviewPlaying,
                                              "text_focus": textFocus])
            togglePlayback()
            return true
        }
    }

    /// 窗口 firstResponder 是否文本编辑视图（需求细项 2：输入框聚焦时空格保持正常输入）。
    /// - NSTextView 全覆盖输入路径：可编辑 field editor（选区读数三框/搜索框编辑态）
    ///   与只读可选文稿视图（TranscriptTextView）都是 NSTextView → 一律放行（不误触优先）。
    /// - 可编辑 NSTextField 兜底（field editor 尚未接管的理论窗口期）。
    static func textEntryFirstResponder(in window: NSWindow) -> Bool {
        let firstResponder = window.firstResponder
        if firstResponder is NSTextView { return true }
        if let textField = firstResponder as? NSTextField, textField.isEditable { return true }
        return false
    }

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
        // FIX-020: 回放增益链 playerNode → EQ(globalGain) → mainMixer。
        // 旧实现的缺陷：增益只写在「当时存在的」playerNode.volume（0...1，升益被钳），
        // 且每轮播放重建节点后从不读取 clipGain——先拖线再点播放等于白调。
        // 现改为：①建链即按当前 clipGain 设 EQ globalGain（dB 直设，−24～+20 全标尺可放大）；
        // ②升降益同走单一 EQ 路径（不再用 playerNode.volume 双路径）。
        // 过载处理：+dB 放大超满刻度时在输出设备处硬削波，与导出链（DraftRenderEngine.applyGain
        // 的 ±1 限幅）同口径，过载段波形红色溢出层（UI-036 R15b）即视觉警示。
        // 注：Apple 峰值限幅器 AU 组件在 macOS 26 仍存在（AudioComponentFindNext 实证 'lmtr'），
        // 但 SDK 已移除 AVAudioUnitDynamicsProcessor 同步包装类与 AVAudioUnit(componentDescription:)
        // 便捷 init，仅剩 async instantiate——给建链引入时序不确定性，本单不做；后续若要防爆音软限幅，
        // 走「编辑器加载时 async 预热限幅器节点」路线（见 docs/证据/2026-10-31-FIX020-*.md）。
        let gainNode = AVAudioUnitEQ(numberOfBands: 1)
        gainNode.bands[0].filterType = .parametric
        gainNode.bands[0].bypass = true  // 频段旁路——EQ 只承担 globalGain 全带增益
        engine.attach(playerNode)
        engine.attach(gainNode)
        engine.connect(playerNode, to: gainNode, format: format)
        engine.connect(gainNode, to: engine.mainMixerNode, format: format)
        gainNode.globalGain = Float(GainScale.playbackDB(for: waveformView.clipGain))

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
            previewGainNode = gainNode
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
        previewGainNode = nil
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
                // FEAT-007: session 加载完成后恢复草稿（命令栈重放 + 增益）
                self.applyDraftIfNeeded()
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

    /// FEAT-007: 当前 buffer 帧数（lite 自验草稿恢复断言用；加载中为 0）
    var currentFrameCount: Int {
        Int(audioBuffer?.frameLength ?? 0)
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
        // UI-042: 全显+右端留白态（resize 拉宽越过全音频）zoomLevel < 1——控件量表从 1 起，钳显示值
        zoomControls.zoomLevel = max(1.0, currentZoom)
        zoomControls.isAtMinZoom = currentZoom <= 1.0
        zoomControls.isAtMaxZoom = currentZoom >= maxZoom

        let totalDur = waveformView.totalDuration
        let visDur = waveformView.visibleDuration
        // UI-042: 留白态可见比例可 > 1，滚动条口径钳到 1（全显）
        scrollBarView.visibleRatio = totalDur > 0 ? CGFloat(min(1.0, visDur / totalDur)) : 1.0

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
    /// UI-039: 挂载状态变化回调（挂进窗口 = 编辑器激活，摘出 = 退出）。
    /// 空格键局部监视器随此挂/撤（addLocalMonitorForEvents 是 app 级拦截，
    /// 生命周期必须跟随编辑器视图的窗口存在性，否则主界面空格被误拦）。
    var windowPresenceChanged: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowPresenceChanged?(window != nil)
    }

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
        // FIX-020: 属性面板音量路径退役（UI-034 R3 起面板无音量入口=死代码）——
        // 删 playerNode.volume 写入防误用旧双路径；增益唯一入口=音量线（clipGain→EQ globalGain）。
        // delegate 签名保留（协议稳定）。
        logger.info("属性面板音量调整已忽略(无 UI 入口): \(String(format: "%.1f", volume))dB")
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
