import Cocoa
import Foundation

// MARK: - MainWindowView (V2.0 重构 — 录编一体化布局)
/// 主窗口视图 - 轨道+轨道板模式
///
/// 布局：
/// ┌──────────────────────────────────────────────────────────────────┐
/// │  标题栏：[AudioRecord]  [录制目标]                     [导出 ▶]  │
/// ├──────────────────────────────────────────────────────────────────┤
/// │  编辑工具栏：[裁剪] [标准化] [淡入] [淡出]                       │
/// ├────────┬──────────────────────────────────────────┬──────────────┤
/// │ 轨道板  │  波形 + 时间刻度尺                        │  电平表卡片  │
/// │ [🔊][S]│  ~~~波形区域~~~                           │  L ▓▓░░     │
/// │        │  [缩放滚动条]                              │  R ▓▓░░     │
/// ├────────┴──────────────────────────────────────────┴──────────────┤
/// │  控制面板：00:00.00  [▶] [● REC] [■]  48kHz·32bit·立体声         │
/// ├──────────────────────────────────────────────────────────────────┤
/// │  状态栏                                                          │
/// └──────────────────────────────────────────────────────────────────┘
class MainWindowView: NSView {
    
    // MARK: - UI Components
    private let splitView = NSSplitView()
    private let sidebarView = SidebarView()
    private let contentView = NSView()
    
    // V2.0 新增组件
    private let titleBarView = TitleBarView()
    private let editToolbarView = EditToolbarView()
    private let trackPanelView = TrackPanelView()
    private let levelMeterCardView = LevelMeterCardView()
    private var trackPanelWidthConstraint: NSLayoutConstraint!
    
    // 录制模式内容
    private let recordingContentView = NSView()
    private let waveformView = WaveformView()
    private let controlPanelView = ControlPanelView()
    private let statusBarView = StatusBarView()
    
    // 中间区域容器（轨道板 + 波形 + 电平表）
    private let middleAreaView = NSView()
    
    // 当前选中/最近完成的文件（用于导出/编辑工具栏操作）
    private var lastCompletedFile: RecordedFileInfo?
    
    // 保留旧组件引用（兼容）
    private let tracksView = TracksView()
    private let levelMetersOverlay = LevelMetersOverlay()
    
    // 编辑器（由 EditorViewController 管理）
    private var currentEditorView: NSView?
    private(set) var isInEditorMode: Bool = false
    
    // Sidebar 折叠状态
    private(set) var isSidebarCollapsed: Bool = false
    private var sidebarWidthBeforeCollapse: CGFloat = 260
    
    // MARK: - 工作区模型（REQ-2.0-05 简化：3 态）
    // idle → recording → editing（录制完成后自动进入编辑器）
    enum ViewMode {
        case idle            // 录制准备态 — 等待录制
        case recording       // 录制进行态 — 实时波形滚动
        case editing         // 编辑态 — 进入 EditorViewController
    }
    private(set) var currentMode: ViewMode = .idle
    
    // MARK: - Properties
    weak var delegate: MainWindowViewDelegate?
    private var availableProcesses: [AudioProcessInfo] = []
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surface.cgColor
        
        // Accessibility identifiers for AI interaction testing
        setAccessibilityIdentifier("MainWindowView")
        
        setupTitleBar()
        setupSplitView()
        setupSidebar()
        setupContentView()
        setupConstraints()
        setupAccessibility()
    }
    
    private func setupAccessibility() {
        // 标记自身为 accessibility group
        setAccessibilityRole(.group)
        setAccessibilityElement(true)

        sidebarView.setAccessibilityIdentifier("Sidebar")
        sidebarView.setAccessibilityRole(.group)
        sidebarView.setAccessibilityElement(true)

        waveformView.setAccessibilityIdentifier("WaveformView")
        waveformView.setAccessibilityRole(.group)
        waveformView.setAccessibilityElement(true)
        // REQ-2.0-02: idle 态 accessibility
        waveformView.setAccessibilityLabel("录制准备区域")
        waveformView.setAccessibilityHelp("按空格键或点击录制按钮开始录制")

        levelMeterCardView.setAccessibilityIdentifier("LevelMeter")
        levelMeterCardView.setAccessibilityRole(.group)
        levelMeterCardView.setAccessibilityElement(true)

        statusBarView.setAccessibilityIdentifier("StatusBar")
        statusBarView.setAccessibilityRole(.group)
        statusBarView.setAccessibilityElement(true)

        controlPanelView.setAccessibilityIdentifier("ControlPanel")
        controlPanelView.setAccessibilityRole(.group)
        controlPanelView.setAccessibilityElement(true)

        editToolbarView.setAccessibilityIdentifier("EditToolbar")
        editToolbarView.setAccessibilityRole(.toolbar)
        editToolbarView.setAccessibilityElement(true)

        titleBarView.setAccessibilityIdentifier("TitleBar")
        titleBarView.setAccessibilityRole(.group)
        titleBarView.setAccessibilityElement(true)
    }
    
    // MARK: - Setup Title Bar
    private func setupTitleBar() {
        titleBarView.delegate = self
        titleBarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleBarView)
    }
    
    // MARK: - Setup Split View
    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.arrangesAllSubviews = true
        splitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitView)
    }
    
    override func layout() {
        super.layout()
        if splitView.subviews.count >= 2 && sidebarView.frame.width < 10 {
            splitView.setPosition(IndustrialSpacing.sidebarWidth, ofDividerAt: 0)
        }
    }
    
    private func setupSidebar() {
        sidebarView.delegate = self
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(sidebarView)
    }
    
    // MARK: - Setup Content View (V2.0 布局)
    private func setupContentView() {
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = IndustrialColors.surfaceContainerLowest.cgColor
        contentView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(contentView)
        
        // 录制模式容器
        recordingContentView.wantsLayer = true
        recordingContentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(recordingContentView)
        
        NSLayoutConstraint.activate([
            recordingContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            recordingContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            recordingContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            recordingContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        // V2.0: 编辑工具栏
        editToolbarView.delegate = self
        editToolbarView.translatesAutoresizingMaskIntoConstraints = false
        recordingContentView.addSubview(editToolbarView)
        
        // V2.0: 中间区域容器（轨道板 + 波形 + 电平表）
        middleAreaView.wantsLayer = true
        middleAreaView.translatesAutoresizingMaskIntoConstraints = false
        recordingContentView.addSubview(middleAreaView)
        
        // V2.0: 轨道板（左侧）
        trackPanelView.delegate = self
        trackPanelView.translatesAutoresizingMaskIntoConstraints = false
        middleAreaView.addSubview(trackPanelView)
        
        // 波形视图（中间）
        waveformView.delegate = self
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        middleAreaView.addSubview(waveformView)
        
        // V2.0: 独立电平表卡片（右侧）
        levelMeterCardView.translatesAutoresizingMaskIntoConstraints = false
        middleAreaView.addSubview(levelMeterCardView)
        
        // 控制面板（底部）
        controlPanelView.delegate = self
        controlPanelView.translatesAutoresizingMaskIntoConstraints = false
        recordingContentView.addSubview(controlPanelView)
        
        // 状态栏
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        recordingContentView.addSubview(statusBarView)
        
        // 旧组件 — 保留引用但隐藏
        tracksView.delegate = self
        tracksView.isHidden = true
        levelMetersOverlay.isHidden = true
        
        // V2.0: 初始态 — 隐藏编辑工具栏和轨道板（仅在编辑态显示）
        editToolbarView.isHidden = true
        editToolbarView.setEnabled(false)
        trackPanelView.isHidden = true
        // trackPanelWidthConstraint 初始值为 0（在 setupConstraints 中设置）
    }
    
    // MARK: - Constraints (V2.0 新布局)
    private func setupConstraints() {
        let editToolbarHeight: CGFloat = 36
        let controlPanelHeight: CGFloat = 90
        let statusBarHeight: CGFloat = 32
        let levelMeterWidth: CGFloat = 80
        trackPanelWidthConstraint = trackPanelView.widthAnchor.constraint(equalToConstant: 0)  // 初始隐藏态为 0
        
        NSLayoutConstraint.activate([
            // 标题栏（窗口顶部 38px）
            titleBarView.topAnchor.constraint(equalTo: topAnchor),
            titleBarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleBarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleBarView.heightAnchor.constraint(equalToConstant: 38),
            
            // SplitView 紧接标题栏下方
            splitView.topAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // 编辑工具栏（content 顶部）
            editToolbarView.topAnchor.constraint(equalTo: recordingContentView.topAnchor),
            editToolbarView.leadingAnchor.constraint(equalTo: recordingContentView.leadingAnchor),
            editToolbarView.trailingAnchor.constraint(equalTo: recordingContentView.trailingAnchor),
            editToolbarView.heightAnchor.constraint(equalToConstant: editToolbarHeight),
            
            // 中间区域（编辑工具栏 ~ 控制面板之间）
            middleAreaView.topAnchor.constraint(equalTo: editToolbarView.bottomAnchor),
            middleAreaView.leadingAnchor.constraint(equalTo: recordingContentView.leadingAnchor),
            middleAreaView.trailingAnchor.constraint(equalTo: recordingContentView.trailingAnchor),
            middleAreaView.bottomAnchor.constraint(equalTo: controlPanelView.topAnchor, constant: -IndustrialSpacing.xs),
            
            // 轨道板（中间区域左侧）
            trackPanelView.topAnchor.constraint(equalTo: middleAreaView.topAnchor),
            trackPanelView.leadingAnchor.constraint(equalTo: middleAreaView.leadingAnchor),
            trackPanelView.bottomAnchor.constraint(equalTo: middleAreaView.bottomAnchor),
            trackPanelWidthConstraint,
            
            // 电平表卡片（中间区域右侧）
            levelMeterCardView.topAnchor.constraint(equalTo: middleAreaView.topAnchor, constant: IndustrialSpacing.sm),
            levelMeterCardView.trailingAnchor.constraint(equalTo: middleAreaView.trailingAnchor, constant: -IndustrialSpacing.sm),
            levelMeterCardView.bottomAnchor.constraint(equalTo: middleAreaView.bottomAnchor, constant: -IndustrialSpacing.sm),
            levelMeterCardView.widthAnchor.constraint(equalToConstant: levelMeterWidth),
            
            // 波形视图（轨道板和电平表之间）
            waveformView.topAnchor.constraint(equalTo: middleAreaView.topAnchor, constant: IndustrialSpacing.sm),
            waveformView.leadingAnchor.constraint(equalTo: trackPanelView.trailingAnchor, constant: IndustrialSpacing.xs),
            waveformView.trailingAnchor.constraint(equalTo: levelMeterCardView.leadingAnchor, constant: -IndustrialSpacing.xs),
            waveformView.bottomAnchor.constraint(equalTo: middleAreaView.bottomAnchor, constant: -IndustrialSpacing.sm),
            waveformView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            
            // 控制面板（满宽，无左右间距）
            controlPanelView.leadingAnchor.constraint(equalTo: recordingContentView.leadingAnchor),
            controlPanelView.trailingAnchor.constraint(equalTo: recordingContentView.trailingAnchor),
            controlPanelView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor, constant: -IndustrialSpacing.xs),
            controlPanelView.heightAnchor.constraint(equalToConstant: controlPanelHeight),
            
            // 状态栏
            statusBarView.leadingAnchor.constraint(equalTo: recordingContentView.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: recordingContentView.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: recordingContentView.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: statusBarHeight)
        ])
    }
    
    // MARK: - Public Methods (兼容旧接口)
    func updateStatus(_ status: String) {
        statusBarView.updateStatus(status)
    }
    
    func updateTimer(_ timeString: String) {
        controlPanelView.updateTimer(timeString)
    }
    
    func updateLevel(_ level: Float) {
        // V2.0: 电平同时更新到独立卡片和轨道电平
        levelMeterCardView.updateLevel(level)
        tracksView.updateLevel(level)
    }
    
    func updatePeakLevel(_ peakLevel: Float) {
        waveformView.updatePeakLevel(peakLevel)
    }
    
    func updateMode(_ mode: RecordingMode) {
        // 预留
    }
    
    func updateRecordingState(_ state: RecordingState) {
        controlPanelView.updateRecordingState(state)
        switch state {
        case .preparing, .recording:
            if !waveformView.isRecording {
                waveformView.startRecording()
            }
            switchToMode(.recording)
        case .idle:
            waveformView.stopRecording()
            levelMeterCardView.reset()
            // REQ-2.0-05：录制完成后由 Controller 直接调用 enterEditor
            // 这里只需切回 idle 态，编辑器过渡由 Controller 负责
            if currentMode == .recording {
                switchToMode(.idle)
            }
        case .error:
            waveformView.stopRecording()
            levelMeterCardView.reset()
            switchToMode(.idle)
        default:
            break
        }
    }
    
    func updateProcessList(_ processes: [AudioProcessInfo]) {
        availableProcesses = processes
        sidebarView.updateProcessList(processes)
    }
    
    func restoreProcessSelection(_ processes: [AudioProcessInfo]) {
        sidebarView.restoreProcessSelection(processes)
    }
    
    func updateTracksDisplay() {
        var tracks: [TrackInfo] = []
        let selectedProcesses = sidebarView.getSelectedProcesses()
        
        if let process = selectedProcesses.first {
            let appIcon = sidebarView.getIconForProcess(process)
            tracks.append(TrackInfo(
                icon: "",
                title: process.name,
                isActive: true,
                appIcon: appIcon,
                sourceType: "应用声音"
            ))
        } else if sidebarView.isSystemAudioSourceSelected() {
            tracks.append(TrackInfo(
                icon: "speaker.wave.2.fill",
                title: "系统声音",
                isActive: true,
                sourceType: "系统混音"
            ))
        }
        
        if sidebarView.isMicrophoneSourceSelected() {
            tracks.append(TrackInfo(
                icon: "mic.fill",
                title: "麦克风",
                isActive: true,
                sourceType: "麦克风输入"
            ))
        }
        
        // V2.0: 更新轨道板
        trackPanelView.updateTracks(tracks)
        tracksView.updateTracks(tracks)
        
        // 更新标题栏录制目标
        if let process = selectedProcesses.first {
            titleBarView.updateTargetDescription(process.name)
            controlPanelView.updateTargetDescription(process.name)
        } else if sidebarView.isSystemAudioSourceSelected() {
            titleBarView.updateTargetDescription("系统声音")
            controlPanelView.updateTargetDescription("全部系统声音")
        } else {
            titleBarView.updateTargetDescription("未选择录制目标")
            controlPanelView.updateTargetDescription("未选择录制目标")
        }
    }
    
    func debugButtonPosition() {}
    
    // MARK: - Public Query APIs
    func isSystemAudioSourceSelected() -> Bool {
        return sidebarView.isSystemAudioSourceSelected()
    }
    
    func isMicrophoneSourceSelected() -> Bool {
        return sidebarView.isMicrophoneSourceSelected()
    }
    
    func addRecordedFile(_ file: RecordedFileInfo) {
        sidebarView.addRecordedFile(file)
    }
    
    func refreshRecordedFiles() {
        sidebarView.refreshRecordedFiles()
    }
    
    func loadRecordedFiles(_ files: [RecordedFileInfo]) {
        sidebarView.loadRecordedFiles(files)
    }

    func updatePlaybackDisplay(fileName: String?, currentTime: TimeInterval, duration: TimeInterval, isPlaying: Bool, isPaused: Bool) {
        tracksView.isHidden = true  // V2.0: 旧 TracksView 始终隐藏
        tracksView.updatePlaybackDisplay(
            fileName: fileName,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            isPaused: isPaused
        )
        controlPanelView.updatePlaybackPaused(isPaused)
    }
    
    func loadFileWaveform(url: URL) {
        // Load waveform for preview (editing is handled by Controller via enterEditor)
        waveformView.loadWaveform(from: url)
    }
    
    func updateWaveformProgress(_ progress: Double) {
        waveformView.updatePlaybackProgress(progress)
    }
    
    // MARK: - V2.0 状态切换（REQ-2.0-05 简化）
    // 三态：idle（准备）/ recording（录制中）/ editing（编辑器）
    
    private func switchToMode(_ mode: ViewMode) {
        guard mode != currentMode else { return }
        currentMode = mode
        
        switch mode {
        case .idle:
            // 录制准备态：隐藏编辑能力，只展示录制相关 UI
            editToolbarView.setEnabled(false)
            editToolbarView.isHidden = true
            trackPanelView.isHidden = true
            trackPanelWidthConstraint.constant = 0
            titleBarView.setExportEnabled(false)
            // REQ-2.0-02: idle 态引导文案 + accessibility
            statusBarView.updateIdleGuide(targetName: sidebarView.getSelectedProcessName())
            waveformView.setAccessibilityLabel("录制准备区域")
            waveformView.setAccessibilityHelp("按空格键或点击录制按钮开始录制")

        case .recording:
            // 录制进行态：隐藏编辑能力，显示实时波形
            editToolbarView.setEnabled(false)
            editToolbarView.isHidden = true
            trackPanelView.isHidden = true
            trackPanelWidthConstraint.constant = 0
            titleBarView.setExportEnabled(false)
            // REQ-2.0-02: 更新 accessibility
            waveformView.setAccessibilityLabel("录制波形")
            waveformView.setAccessibilityHelp("正在录制音频")

        case .editing:
            // 编辑态：进入 EditorViewController（REQ-2.0-05）
            editToolbarView.setEnabled(true)
            editToolbarView.isHidden = false
            trackPanelView.isHidden = false
            trackPanelWidthConstraint.constant = TrackPanelView.panelWidth
            titleBarView.setExportEnabled(true)        }
    }
    
    // MARK: - Editor Mode
    
    func showEditor(_ editorView: NSView) {
        guard !isInEditorMode else {
            // 已在编辑模式：使用 cross-dissolve
            crossDissolveEditor(to: editorView)
            return
        }
        isInEditorMode = true
        currentEditorView = editorView

        // Enable export button when entering editor mode
        switchToMode(.editing)

        editorView.translatesAutoresizingMaskIntoConstraints = false
        editorView.alphaValue = 0
        contentView.addSubview(editorView)

        NSLayoutConstraint.activate([
            editorView.topAnchor.constraint(equalTo: contentView.topAnchor),
            editorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        recordingContentView.isHidden = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = IndustrialAnimation.long
            context.timingFunction = IndustrialAnimation.timingFunction
            editorView.animator().alphaValue = 1.0
        }
    }

    /// Cross-dissolve 切换编辑器视图 — 无闪烁过渡（V2.1 文件联动）
    func crossDissolveEditor(to newEditorView: NSView) {
        guard isInEditorMode else {
            showEditor(newEditorView)
            return
        }

        let oldView = currentEditorView
        currentEditorView = newEditorView

        newEditorView.translatesAutoresizingMaskIntoConstraints = false
        newEditorView.alphaValue = 0
        contentView.addSubview(newEditorView)

        NSLayoutConstraint.activate([
            newEditorView.topAnchor.constraint(equalTo: contentView.topAnchor),
            newEditorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            newEditorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            newEditorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // Cross-dissolve: 新旧视图同时动画
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2  // 200ms cross-dissolve
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            newEditorView.animator().alphaValue = 1.0
            oldView?.animator().alphaValue = 0
        }, completionHandler: {
            oldView?.removeFromSuperview()
        })
    }
    
    func hideEditor() {
        guard isInEditorMode else { return }
        isInEditorMode = false
        
        // Restore to idle mode (disable export button)
        switchToMode(.idle)
        
        currentEditorView?.removeFromSuperview()
        currentEditorView = nil
        
        recordingContentView.isHidden = false
        recordingContentView.alphaValue = 0
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = IndustrialAnimation.long
            context.timingFunction = IndustrialAnimation.timingFunction
            recordingContentView.animator().alphaValue = 1.0
        }
    }
}


// MARK: - SidebarViewDelegate
extension MainWindowView: SidebarViewDelegate {
    func sidebarViewDidChangeSourceSelection(_ view: SidebarView) {
        if isInEditorMode {
            hideEditor()
        }
        updateTracksDisplay()
    }
    
    func sidebarViewDidSelectProcesses(_ view: SidebarView, pids: [pid_t]) {
        delegate?.mainWindowViewDidSelectProcesses(self, pids: pids)
        updateTracksDisplay()
    }
    
    func sidebarViewDidRequestProcessRefresh(_ view: SidebarView) {
        delegate?.mainWindowViewDidRequestProcessRefresh(self)
    }

    func sidebarViewDidSelectFile(_ view: SidebarView, file: RecordedFileInfo) {
        lastCompletedFile = file
        delegate?.mainWindowViewDidSelectRecordedFile(self, file: file)
    }
    
    func sidebarViewDidDoubleClickFile(_ view: SidebarView, file: RecordedFileInfo) {
        delegate?.mainWindowViewDidSelectRecordedFile(self, file: file)
    }
    
    func sidebarViewDidRenameFile(_ view: SidebarView, file: RecordedFileInfo, newName: String) {
        delegate?.mainWindowViewDidRenameFile(self, file: file, newName: newName)
    }
    
    func sidebarViewDidChangeMixAudio(_ view: SidebarView, enabled: Bool) {
        delegate?.mainWindowViewDidChangeMixAudio(self, enabled: enabled)
    }
    
    func sidebarViewDidRequestEditFile(_ view: SidebarView, file: RecordedFileInfo) {
        delegate?.mainWindowViewDidRequestEditFile(self, file: file)
    }
}

// MARK: - TracksViewDelegate
extension MainWindowView: TracksViewDelegate {
    func tracksViewDidUpdateTracks(_ view: TracksView, tracks: [TrackInfo]) {}

    func tracksViewDidTogglePlayback(_ view: TracksView) {
        delegate?.mainWindowViewDidPlayRecording(self)
    }

    func tracksViewDidStopPlayback(_ view: TracksView) {
        delegate?.mainWindowViewDidStopPlayback(self)
    }
}

// MARK: - ControlPanelViewDelegate
extension MainWindowView: ControlPanelViewDelegate {
    func controlPanelViewDidStartRecording(_ view: ControlPanelView) {
        delegate?.mainWindowViewDidStartRecording(self)
    }
    
    func controlPanelViewDidStopRecording(_ view: ControlPanelView) {
        delegate?.mainWindowViewDidStopRecording(self)
    }

    func controlPanelViewDidTogglePlayback(_ view: ControlPanelView) {
        delegate?.mainWindowViewDidPlayRecording(self)
    }

    func controlPanelViewDidStopPlayback(_ view: ControlPanelView) {
        delegate?.mainWindowViewDidStopPlayback(self)
    }
}

// MARK: - TitleBarViewDelegate
extension MainWindowView: TitleBarViewDelegate {
    func titleBarDidRequestExport(_ view: TitleBarView) {
        // Use the last completed file or ask delegate to handle export
        if let file = lastCompletedFile {
            delegate?.mainWindowViewDidRequestExportAudio(self, file: file)
        } else {
            // Fallback: let controller determine which file to export
            delegate?.mainWindowViewDidDownloadRecording(self)
        }
    }
}

// MARK: - EditToolbarViewDelegate
extension MainWindowView: EditToolbarViewDelegate {
    func editToolbarDidRequestTrim(_ view: EditToolbarView) {
        // 编辑操作将在后续版本实现
        // 当前通过进入编辑器来执行裁剪
        if let file = lastCompletedFile {
            delegate?.mainWindowViewDidRequestEditFile(self, file: file)
        }
    }
    
    func editToolbarDidRequestNormalize(_ view: EditToolbarView) {
        if let file = lastCompletedFile {
            delegate?.mainWindowViewDidRequestEditFile(self, file: file)
        }
    }
    
    func editToolbarDidRequestFadeIn(_ view: EditToolbarView) {
        if let file = lastCompletedFile {
            delegate?.mainWindowViewDidRequestEditFile(self, file: file)
        }
    }
    
    func editToolbarDidRequestFadeOut(_ view: EditToolbarView) {
        if let file = lastCompletedFile {
            delegate?.mainWindowViewDidRequestEditFile(self, file: file)
        }
    }
}

// MARK: - TrackPanelViewDelegate
extension MainWindowView: TrackPanelViewDelegate {
    func trackPanelDidToggleMute(_ view: TrackPanelView, trackIndex: Int) {
        // V2.0: Mute 功能预留
    }
    
    func trackPanelDidToggleSolo(_ view: TrackPanelView, trackIndex: Int) {
        // V2.0: Solo 功能预留
    }
}

// MARK: - NSSplitViewDelegate
extension MainWindowView: NSSplitViewDelegate {
    
    func splitView(_ splitView: NSSplitView,
                   constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 0
    }
    
    func splitView(_ splitView: NSSplitView,
                   constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 320
    }
    
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return subview == sidebarView
    }
    
    func splitView(_ splitView: NSSplitView, shouldCollapseSubview subview: NSView, forDoubleClickOnDividerAt dividerIndex: Int) -> Bool {
        return subview == sidebarView
    }
    
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        return view == contentView
    }
    
    func splitViewDidResizeSubviews(_ notification: Notification) {
        let sidebarWidth = sidebarView.frame.width
        if sidebarWidth < 80 && !isSidebarCollapsed {
            collapseSidebar(animated: false)
        } else if sidebarWidth >= 80 && isSidebarCollapsed {
            isSidebarCollapsed = false
        }
    }
    
    func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        return proposedEffectiveRect
    }
}

// MARK: - Sidebar Collapse
extension MainWindowView {
    
    func toggleSidebar() {
        if isSidebarCollapsed {
            expandSidebar()
        } else {
            collapseSidebar()
        }
    }
    
    func collapseSidebar(animated: Bool = true) {
        guard !isSidebarCollapsed else { return }
        sidebarWidthBeforeCollapse = max(200, sidebarView.frame.width)
        isSidebarCollapsed = true
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = IndustrialAnimation.long
                context.timingFunction = IndustrialAnimation.timingFunction
                splitView.animator().setPosition(0, ofDividerAt: 0)
            }
        } else {
            splitView.setPosition(0, ofDividerAt: 0)
        }
    }
    
    func expandSidebar(animated: Bool = true) {
        guard isSidebarCollapsed else { return }
        isSidebarCollapsed = false
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = IndustrialAnimation.long
                context.timingFunction = IndustrialAnimation.timingFunction
                splitView.animator().setPosition(sidebarWidthBeforeCollapse, ofDividerAt: 0)
            }
        } else {
            splitView.setPosition(sidebarWidthBeforeCollapse, ofDividerAt: 0)
        }
    }
}

// MARK: - WaveformViewDelegate
extension MainWindowView: WaveformViewDelegate {
    func waveformView(_ view: WaveformView, didSeekToProgress progress: Double) {
        delegate?.mainWindowViewDidSeekToProgress(self, progress: progress)
    }
}

// MARK: - Delegate Protocol
protocol MainWindowViewDelegate: AnyObject {
    func mainWindowViewDidSwitchMode(_ view: MainWindowView)
    func mainWindowViewDidStartRecording(_ view: MainWindowView)
    func mainWindowViewDidStopRecording(_ view: MainWindowView)
    func mainWindowViewDidPlayRecording(_ view: MainWindowView)
    func mainWindowViewDidDownloadRecording(_ view: MainWindowView)
    func mainWindowViewDidChangeFormat(_ view: MainWindowView, format: String)
    func mainWindowViewDidOpenPermissions(_ view: MainWindowView)
    func mainWindowViewDidStopPlayback(_ view: MainWindowView)
    func mainWindowViewDidSelectRecordedFile(_ view: MainWindowView, file: RecordedFileInfo)
    func mainWindowViewDidSelectProcesses(_ view: MainWindowView, pids: [pid_t])
    func mainWindowViewDidRequestProcessRefresh(_ view: MainWindowView)
    func mainWindowViewDidRequestExportAudio(_ view: MainWindowView, file: RecordedFileInfo)
    func mainWindowViewDidRenameFile(_ view: MainWindowView, file: RecordedFileInfo, newName: String)
    func mainWindowViewDidChangeMixAudio(_ view: MainWindowView, enabled: Bool)
    func mainWindowViewDidSeekToProgress(_ view: MainWindowView, progress: Double)
    func mainWindowViewDidRequestEditFile(_ view: MainWindowView, file: RecordedFileInfo)
}
