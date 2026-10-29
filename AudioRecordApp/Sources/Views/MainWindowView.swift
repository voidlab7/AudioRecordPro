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
    // UI-006 R2（2026-10-12 老板打回「顶部留白」）：中间区域顶部约束常量随模式切换——
    // idle/录制态 editToolbar 隐藏时不占位（0，画布顶到标题栏）；编辑态恢复工具栏高度占位
    private var middleAreaTopConstraint: NSLayoutConstraint!
    private let editToolbarHeight: CGFloat = 36
    
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
    private var isCaptureRunning = false

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
        waveformView.setAccessibilityLabel("录制准备区域".localized)
        waveformView.setAccessibilityHelp("按空格键或点击录制按钮开始录制".localized)

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
    
    private var didApplyInitialSidebarWidth = false

    override func layout() {
        super.layout()
        // v3.1: 初次布局无条件应用侧栏宽度（旧条件 width<10 在 NSSplitView 自动布局后永不触发，导致 412 不生效）
        if !didApplyInitialSidebarWidth && splitView.subviews.count >= 2 {
            splitView.setPosition(IndustrialSpacing.sidebarWidth, ofDividerAt: 0)
            didApplyInitialSidebarWidth = true
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
        
        // 控制面板（底部）
        controlPanelView.delegate = self
        controlPanelView.translatesAutoresizingMaskIntoConstraints = false
        recordingContentView.addSubview(controlPanelView)

        // UI-005（2026-10-12 老板裁决）：红钮居中锚 = 波形画布中心（侧栏↔电平表之间的视觉中心）
        controlPanelView.setCenteringAnchor(waveformView.centerXAnchor)

        // 状态栏
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        recordingContentView.addSubview(statusBarView)

        // UI-008 R2（2026-10-12 老板「到最底部」）：电平列提为 recordingContentView 直属全高右栏，
        // 压在控制栏/状态栏之上，从画布顶贯穿到窗口最底部（z 序需在 statusBar 之后添加）
        levelMeterCardView.translatesAutoresizingMaskIntoConstraints = false
        recordingContentView.addSubview(levelMeterCardView)
        
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
        let controlPanelHeight: CGFloat = 90
        let statusBarHeight: CGFloat = 32
        let levelMeterWidth: CGFloat = 80
        trackPanelWidthConstraint = trackPanelView.widthAnchor.constraint(equalToConstant: 0)  // 初始隐藏态为 0
        middleAreaTopConstraint = middleAreaView.topAnchor.constraint(equalTo: recordingContentView.topAnchor, constant: 0)  // 初始 idle：不占工具栏位
        
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
            
            // 中间区域（编辑工具栏 ~ 控制面板之间）；顶部常量随模式切换（UI-006 R2）
            // UI-012（2026-10-13）：底部零空隙——网格直通到底部分割线，不留空白带
            middleAreaTopConstraint,
            middleAreaView.leadingAnchor.constraint(equalTo: recordingContentView.leadingAnchor),
            middleAreaView.trailingAnchor.constraint(equalTo: recordingContentView.trailingAnchor),
            middleAreaView.bottomAnchor.constraint(equalTo: controlPanelView.topAnchor, constant: 0),
            
            // 轨道板（中间区域左侧）
            trackPanelView.topAnchor.constraint(equalTo: middleAreaView.topAnchor),
            trackPanelView.leadingAnchor.constraint(equalTo: middleAreaView.leadingAnchor),
            trackPanelView.bottomAnchor.constraint(equalTo: middleAreaView.bottomAnchor),
            trackPanelWidthConstraint,
            
            // 电平表卡片（右侧全高栏）——UI-008 R2: top 对齐画布顶，bottom 直落窗口最底部
            levelMeterCardView.topAnchor.constraint(equalTo: middleAreaView.topAnchor),
            levelMeterCardView.trailingAnchor.constraint(equalTo: recordingContentView.trailingAnchor, constant: -IndustrialSpacing.sm),
            levelMeterCardView.bottomAnchor.constraint(equalTo: recordingContentView.bottomAnchor),
            levelMeterCardView.widthAnchor.constraint(equalToConstant: levelMeterWidth),
            
            // 波形视图（轨道板和电平表之间）；顶部 0 让网格顶到标题栏边界（UI-006：满铺）
            // UI-012：底部 0 贴控制栏顶缘——网格画到分割线处，分割线直接压在网格收尾上
            waveformView.topAnchor.constraint(equalTo: middleAreaView.topAnchor),
            waveformView.leadingAnchor.constraint(equalTo: trackPanelView.trailingAnchor, constant: IndustrialSpacing.xs),
            waveformView.trailingAnchor.constraint(equalTo: levelMeterCardView.leadingAnchor, constant: -IndustrialSpacing.xs),
            waveformView.bottomAnchor.constraint(equalTo: middleAreaView.bottomAnchor, constant: 0),
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
        guard isCaptureRunning else { return }
        levelMeterCardView.updateLevel(level)
        tracksView.updateLevel(level)
    }

    func updatePeakLevel(_ peakLevel: Float) {
        guard isCaptureRunning else { return }
        waveformView.updatePeakLevel(peakLevel)
    }
    
    func updateMode(_ mode: RecordingMode) {
        // FIX-004: 源指示落地——录音态画布左上角 REC·源名 常显（原为空实现「预留」）
        switch mode {
        case .microphone:
            waveformView.selectedSourceName = "麦克风".localized
        case .specificProcess:
            waveformView.selectedSourceName = "特定进程".localized
        case .systemMixdown:
            waveformView.selectedSourceName = "系统音频".localized
        }
    }
    
    func updateRecordingState(_ state: RecordingState) {
        Logger.shared.info("🖥️ UI 状态机: → \(state)")
        controlPanelView.updateRecordingState(state)
        switch state {
        case .preparing:
            isCaptureRunning = false
            levelMeterCardView.reset()
            waveformView.reset()
            switchToMode(.recording)
        case .recording:
            isCaptureRunning = true
            if !waveformView.isRecording {
                waveformView.startRecording()
            }
            switchToMode(.recording)
        case .idle:
            isCaptureRunning = false
            waveformView.stopRecording()
            waveformView.reset()
            levelMeterCardView.reset()
            // REQ-2.0-05：录制完成后由 Controller 直接调用 enterEditor
            // 这里只需切回 idle 态，编辑器过渡由 Controller 负责
            if currentMode == .recording {
                switchToMode(.idle)
            }
        case .error:
            isCaptureRunning = false
            waveformView.stopRecording()
            waveformView.reset()
            levelMeterCardView.reset()
            switchToMode(.idle)
        case .stopping:
            isCaptureRunning = false
            levelMeterCardView.reset()
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
                sourceType: "应用声音".localized
            ))
        } else if sidebarView.isSystemAudioSourceSelected() {
            tracks.append(TrackInfo(
                icon: "speaker.wave.2.fill",
                title: "系统声音".localized,
                isActive: true,
                sourceType: "系统混音".localized
            ))
        }
        
        if sidebarView.isMicrophoneSourceSelected() {
            tracks.append(TrackInfo(
                icon: "mic.fill",
                title: "麦克风".localized,
                isActive: true,
                sourceType: "麦克风输入".localized
            ))
        }
        
        // V2.0: 更新轨道板
        trackPanelView.updateTracks(tracks)
        tracksView.updateTracks(tracks)
        
        // 更新标题栏录制目标
        if let process = selectedProcesses.first {
            titleBarView.updateTargetDescription(process.name)
            controlPanelView.updateTargetDescription(process.name)
            waveformView.selectedSourceName = process.name
        } else if sidebarView.isSystemAudioSourceSelected() {
            titleBarView.updateTargetDescription("系统声音".localized)
            controlPanelView.updateTargetDescription("全部系统声音".localized)
            waveformView.selectedSourceName = "系统音频".localized
        } else {
            titleBarView.updateTargetDescription("未选择录制目标".localized)
            controlPanelView.updateTargetDescription("未选择录制目标".localized)
            waveformView.selectedSourceName = "未选择录制目标".localized
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

    /// FIX-006 自测钩子：转发麦克风混录开关（selftest 触发器用）
    func setMicrophoneMixEnabled(_ enabled: Bool) {
        sidebarView.setMicrophoneMixEnabled(enabled)
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
            middleAreaTopConstraint.constant = 0  // UI-006 R2: 工具栏隐藏不占位，画布顶到标题栏
            trackPanelView.isHidden = true
            trackPanelWidthConstraint.constant = 0
            titleBarView.setExportEnabled(false)
            // REQ-2.0-02: idle 态引导文案 + accessibility
            statusBarView.updateIdleGuide(targetName: sidebarView.getSelectedProcessName())
            waveformView.setAccessibilityLabel("录制准备区域".localized)
            waveformView.setAccessibilityHelp("按空格键或点击录制按钮开始录制".localized)

        case .recording:
            // 录制进行态：隐藏编辑能力，显示实时波形
            editToolbarView.setEnabled(false)
            editToolbarView.isHidden = true
            middleAreaTopConstraint.constant = 0  // UI-006 R2: 同 idle
            trackPanelView.isHidden = true
            trackPanelWidthConstraint.constant = 0
            titleBarView.setExportEnabled(false)
            // REQ-2.0-02: 更新 accessibility
            waveformView.setAccessibilityLabel("录制波形".localized)
            waveformView.setAccessibilityHelp("正在录制音频".localized)

        case .editing:
            // 编辑态：进入 EditorViewController（REQ-2.0-05）
            editToolbarView.setEnabled(true)
            editToolbarView.isHidden = false
            middleAreaTopConstraint.constant = editToolbarHeight  // UI-006 R2: 工具栏可见恢复占位
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
        NSLog("[E2E] hideEditor — entering, currentMode=%@", "\(currentMode)")
        guard isInEditorMode else { NSLog("[E2E] hideEditor — SKIP not in editor mode"); return }
        isInEditorMode = false
        NSLog("[E2E] hideEditor — restoring editor views to recording layout")
        
        // Restore to idle mode (disable export button)
        switchToMode(.idle)
        
        // BUGFIX(2026-09-20): 回到录制区必须是干净的准备态。
        // 之前 waveformView 保留上一次录音的波形（stopRecording 有意不清数据，
        // 等 loadWaveform 替换，但 loadFileWaveform 从未被控制器调用），
        // 导致从编辑器切回录制区时右侧波形仍是旧音频。
        waveformView.reset()
        levelMeterCardView.reset()
        lastCompletedFile = nil
        // 可观测性：供回放断言「切回录制区后状态已重置」
        UXEventLog.shared.state("record_area_reset", detail: ["from": "editor"])
        
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
    
    func editToolbarDidRequestSplit(_ view: EditToolbarView) {
        // P0 编辑器预留
    }
    
    func editToolbarDidRequestSilence(_ view: EditToolbarView) {
        // P0 编辑器预留
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
        return IndustrialSpacing.sidebarWidth  // UI-004: 260（老板裁决 2026-10-12）
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

    func waveformViewDidBeginScrubbing(_ view: WaveformView) {
        delegate?.mainWindowViewDidBeginScrubbing(self)
    }

    func waveformViewDidEndScrubbing(_ view: WaveformView) {
        delegate?.mainWindowViewDidEndScrubbing(self)
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
    func mainWindowViewDidBeginScrubbing(_ view: MainWindowView)
    func mainWindowViewDidEndScrubbing(_ view: MainWindowView)
    func mainWindowViewDidRequestEditFile(_ view: MainWindowView, file: RecordedFileInfo)
}
