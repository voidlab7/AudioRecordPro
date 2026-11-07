import Cocoa
import Foundation

// MARK: - FlippedClipView
/// 翻转坐标系的 NSClipView — 让 documentView 内容不满时从顶部开始布局
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { return true }
}

// MARK: - Delegate Protocol
protocol SidebarViewDelegate: AnyObject {
    func sidebarViewDidChangeSourceSelection(_ view: SidebarView)
    func sidebarViewDidSelectProcesses(_ view: SidebarView, pids: [pid_t])
    func sidebarViewDidRequestProcessRefresh(_ view: SidebarView)
    func sidebarViewDidSelectFile(_ view: SidebarView, file: RecordedFileInfo)
    func sidebarViewDidDoubleClickFile(_ view: SidebarView, file: RecordedFileInfo)
    func sidebarViewDidRenameFile(_ view: SidebarView, file: RecordedFileInfo, newName: String)
    func sidebarViewDidChangeMixAudio(_ view: SidebarView, enabled: Bool)
    func sidebarViewDidRequestEditFile(_ view: SidebarView, file: RecordedFileInfo)
}

/// 选择超限回调闭包类型
typealias SidebarSelectionLimitHandler = (SidebarView) -> Void

// MARK: - SidebarView
/// 侧边栏视图 - 负责音频源选择和进程列表管理，集成Tab切换功能
class SidebarView: NSView, TabContainerViewDelegate, RecordedFilesViewDelegate {
    
    // MARK: - UI Components
    private let tabContainer = TabContainerView()
    private let audioRecorderTabView = NSView()
    private let recordedFilesTabView = NSView()
    
    // 音频录制Tab的组件
    private let targetHeader = NSTextField()
    private let appsHeader = NSTextField()
    private let systemTargetRow = IndustrialAudioTargetRowView(
        title: "录制全部系统声音".localized,
        subtitle: "默认输出主设备".localized,
        systemSymbolName: "speaker.wave.3.fill"
    )
    private let micHeader = NSTextField()
    private let refreshButton = IndustrialButtonView(title: "刷新".localized, icon: "arrow.clockwise")
    private let appsScroll = NSScrollView()
    private let appsStack = NSStackView()

    // FEAT-004: 麦克风输入设备选择行（UI-015: 自绘行内选择器，弃 NSPopUpButton）
    // UI-043 R3（2026-11-07 老板定）：「同时录入麦克风」开关行整个退役——勾选即开关，
    // 设备列表常显。micMixEnabled = 有勾选行（等价旧 microphonePanel.isSelected 语义）。
    private let micDeviceRow = NSView()
    private let micDeviceSelector = IndustrialMicDeviceSelectorView()
    /// 麦克风混录开关（R3: 勾选行驱动；默认关 = 全不勾）
    private var micMixEnabled: Bool = false
    
    // 已录制文件Tab的组件
    private let recordedFilesView = RecordedFilesView()
    
    // MARK: - Properties
    weak var delegate: SidebarViewDelegate?
    /// 选择超限回调（已达 5 个时触发，用于弹出 Toast）
    var onSelectionLimitReached: ((SidebarView) -> Void)?
    private var availableProcesses: [AudioProcessInfo] = []
    private var selectedPIDs: [pid_t] = []
    /// Phase 0 多选状态：按选中顺序存储的音频源
    /// Cmd+click 追加，单击替换；录制时只取 first
    private(set) var selectedSources: [AudioSource] = []
    /// 录制中锁定标志：录制期间禁止侧边栏切换
    var isRecordingLocked: Bool = false
    private let logger = Logger.shared
    /// 线程安全的图标缓存（后台预加载 + 主线程读取）
    private let iconCache = NSCache<NSString, NSImage>()
    
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
        // Industrial Design 背景：深灰
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surfaceContainer.cgColor
        
        setupTabContainer()
        setupAudioRecorderTab()
        setupRecordedFilesTab()
        setupConstraints()
    }
    
    // 在视图布局完成后绘制网格纹理和边框
    override func layout() {
        super.layout()

        // v3.1: 移除 UI-001 旧网格纹理（设计稿侧栏无网格）
    }
    
    private func setupTabContainer() {
        tabContainer.delegate = self
        tabContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabContainer)
    }
    
    private func setupAudioRecorderTab() {
        // 设置音频录制Tab的内容
        audioRecorderTabView.translatesAutoresizingMaskIntoConstraints = false
        
        setupHeaders()
        setupTargetControls()
        setupRefreshButton()
        setupAppsTable()
        
        // 添加所有组件到audioRecorderTabView
        audioRecorderTabView.addSubview(targetHeader)
        audioRecorderTabView.addSubview(systemTargetRow)
        audioRecorderTabView.addSubview(appsHeader)
        audioRecorderTabView.addSubview(refreshButton)
        audioRecorderTabView.addSubview(appsScroll)
        audioRecorderTabView.addSubview(micHeader)
        audioRecorderTabView.addSubview(micDeviceRow)
        
        // 创建Tab
        let audioRecorderTab = TabItem(
            id: "audioRecorder",
            title: "录制".localized,
            icon: "waveform",
            view: audioRecorderTabView
        )
        tabContainer.addTab(audioRecorderTab)
    }
    
    private func setupRecordedFilesTab() {
        // 设置已录制文件Tab的内容
        recordedFilesTabView.translatesAutoresizingMaskIntoConstraints = false
        
        recordedFilesView.delegate = self
        recordedFilesView.translatesAutoresizingMaskIntoConstraints = false
        recordedFilesTabView.addSubview(recordedFilesView)
        
        NSLayoutConstraint.activate([
            recordedFilesView.topAnchor.constraint(equalTo: recordedFilesTabView.topAnchor),
            recordedFilesView.leadingAnchor.constraint(equalTo: recordedFilesTabView.leadingAnchor),
            recordedFilesView.trailingAnchor.constraint(equalTo: recordedFilesTabView.trailingAnchor),
            recordedFilesView.bottomAnchor.constraint(equalTo: recordedFilesTabView.bottomAnchor)
        ])
        
        // 创建Tab
        let recordedFilesTab = TabItem(
            id: "recordedFiles",
            title: "文件".localized,
            icon: "folder",
            view: recordedFilesTabView
        )
        tabContainer.addTab(recordedFilesTab)
    }
    
    private func setupHeaders() {
        func styleHeader(_ textField: NSTextField, _ title: String) {
            textField.stringValue = title
            textField.isBordered = false
            textField.isEditable = false
            textField.backgroundColor = .clear
            // v3.1: Figma 规格 — 大写 11px w600 #A3A3A3@0.80
            textField.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            textField.textColor = NSColor(hex: "#A3A3A3").withAlphaComponent(0.8)
            textField.translatesAutoresizingMaskIntoConstraints = false
        }
        
        styleHeader(targetHeader, "系统声音".localized.uppercased())
        styleHeader(appsHeader, "应用声音".localized.uppercased())
        styleHeader(micHeader, "麦克风".localized.uppercased())
    }
    
    private func setupTargetControls() {
        // 系统音频（混音）选择行
        systemTargetRow.translatesAutoresizingMaskIntoConstraints = false
        systemTargetRow.isSelectedTarget = true  // 默认选中
        systemTargetRow.onClick = { [weak self] in
            self?.selectSystemAudioTarget()
        }

        // FEAT-004: 麦克风输入设备选择行
        setupMicDeviceRow()
    }

    /// FEAT-004: 设备选择行构建 + 热插拔刷新（UI-015: 改用 IndustrialMicDeviceSelectorView）
    private func setupMicDeviceRow() {
        micDeviceRow.wantsLayer = true
        micDeviceRow.translatesAutoresizingMaskIntoConstraints = false

        micDeviceSelector.translatesAutoresizingMaskIntoConstraints = false
        micDeviceSelector.onSelect = { [weak self] option, reselect in
            self?.micDeviceSelected(option, reselect: reselect)
        }
        micDeviceRow.addSubview(micDeviceSelector)

        NSLayoutConstraint.activate([
            micDeviceSelector.topAnchor.constraint(equalTo: micDeviceRow.topAnchor),
            micDeviceSelector.leadingAnchor.constraint(equalTo: micDeviceRow.leadingAnchor),
            micDeviceSelector.trailingAnchor.constraint(equalTo: micDeviceRow.trailingAnchor),
            micDeviceSelector.bottomAnchor.constraint(equalTo: micDeviceRow.bottomAnchor),
        ])

        refreshMicDeviceList()
        MicDeviceManager.shared.onDevicesChanged { [weak self] in
            self?.refreshMicDeviceList()
        }
    }

    /// UI-043 R2/R3: 列表 = 实际探测到的麦克风，常显；勾选索引由 micMixEnabled + preferred 推导。
    /// - micMixEnabled=false → selectedIndex=-1（全不勾 = 不录麦克风）
    /// - micMixEnabled=true：preferred 有效 → 勾该行；preferred=nil（跟随）→ 勾系统默认设备行（投影，不写 UD）
    /// 所选设备失效时清除钉选并提示（混录保持开，勾落系统默认投影）。
    private func refreshMicDeviceList() {
        let devices = MicDeviceManager.shared.listMicrophones()
        let preferred = MicDeviceManager.shared.preferredDeviceUID
        let preferredValid = preferred == nil || devices.contains { $0.uid == preferred }

        var options: [IndustrialMicDeviceSelectorView.Option] = []
        for d in devices {
            options.append(IndustrialMicDeviceSelectorView.Option(
                uid: d.uid,
                displayName: MicDeviceManager.shared.displayName(for: d),
                subtitle: nil,
                isCurrent: d.isSystemDefault
            ))
        }

        let systemDefaultIndex = devices.firstIndex(where: { $0.isSystemDefault }) ?? 0
        var selectedIndex = -1
        if micMixEnabled {
            selectedIndex = systemDefaultIndex
            if let uid = preferred, let idx = devices.firstIndex(where: { $0.uid == uid }) {
                selectedIndex = idx
            }
        }
        micDeviceSelector.configure(options: options, selectedIndex: selectedIndex)

        // 失效处理：清除持久化 + selector 提示（勾落系统默认投影，混录保持开）
        if let uid = preferred, !preferredValid {
            MicDeviceManager.shared.preferredDeviceUID = nil
            micDeviceSelector.isInvalid = true
            logger.warning("🎤 [FEAT004] 所选设备失效已回退: uid=\(uid)")
            // preferred 已清，按跟随语义重配勾选索引
            var fallback = -1
            if micMixEnabled { fallback = systemDefaultIndex }
            micDeviceSelector.configure(options: options, selectedIndex: fallback)
        } else {
            micDeviceSelector.isInvalid = false
        }

        // UI-027: 无设备空态（header 显示「未检测到」）
        micDeviceSelector.emptyStateText = devices.isEmpty ? "未检测到".localized : nil
    }

    /// UI-043 R3: 勾选即开关（2026-11-07 老板定，原「拍板 a 回跟随」随开关行退役）——
    /// - 点未勾行：开启混录 + 钉选该设备（写 preferredDeviceUID）
    /// - 点已勾行：取消勾选 = 关闭混录（全不勾，preferred 保留不清理，下次勾行即钉新设备）
    private func micDeviceSelected(_ option: IndustrialMicDeviceSelectorView.Option, reselect: Bool) {
        guard let uid = option.uid, !uid.isEmpty else { return }
        if reselect {
            guard micMixEnabled else { return }
            micMixEnabled = false
            logger.info("🎤 [UI-043 R3] 取消勾选 → 麦克风混录关闭")
            refreshMicDeviceList()
            microphoneMixChanged(enabled: false)
            return
        }
        let wasEnabled = micMixEnabled
        micMixEnabled = true
        MicDeviceManager.shared.preferredDeviceUID = uid
        logger.info("🎤 [FEAT004] 麦克风设备 → \(option.displayName) (uid=\(uid))")
        refreshMicDeviceList()
        if !wasEnabled {
            microphoneMixChanged(enabled: true)
        }
    }
    
    private func setupRefreshButton() {
        refreshButton.onClick = { [weak self] in
            self?.refreshButtonClicked()
        }
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        // P1-2 fix: 挂载到 audioRecorderTabView 而非 self，确保约束参照一致
    }
    
    private func setupAppsTable() {
        appsStack.orientation = .vertical
        appsStack.spacing = 1
        appsStack.alignment = .leading
        appsStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        appsStack.translatesAutoresizingMaskIntoConstraints = false
        
        // 使用翻转的 ClipView，确保内容从顶部开始布局
        let flippedClipView = FlippedClipView()
        flippedClipView.drawsBackground = false
        appsScroll.contentView = flippedClipView
        appsScroll.documentView = appsStack
        appsScroll.drawsBackground = false
        appsScroll.hasVerticalScroller = true
        appsScroll.hasHorizontalScroller = false
        appsScroll.autohidesScrollers = true
        appsScroll.translatesAutoresizingMaskIntoConstraints = false
        appsScroll.wantsLayer = true
        appsScroll.layer?.cornerRadius = IndustrialCornerRadius.sm
        appsScroll.layer?.borderWidth = 0
        appsScroll.layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        
        NSLayoutConstraint.activate([
            appsStack.topAnchor.constraint(equalTo: appsScroll.contentView.topAnchor),
            appsStack.widthAnchor.constraint(equalTo: appsScroll.contentView.widthAnchor)
        ])
    }
    
    private func setupConstraints() {
        // Tab容器约束
        NSLayoutConstraint.activate([
            tabContainer.topAnchor.constraint(equalTo: topAnchor),
            tabContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // 音频录制Tab内部的约束 — 三段式布局
        NSLayoutConstraint.activate([
            // 第一段：系统音频
            targetHeader.topAnchor.constraint(equalTo: audioRecorderTabView.topAnchor, constant: 16),
            targetHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            targetHeader.trailingAnchor.constraint(lessThanOrEqualTo: audioRecorderTabView.trailingAnchor, constant: -16),
            
            systemTargetRow.topAnchor.constraint(equalTo: targetHeader.bottomAnchor, constant: 8),
            systemTargetRow.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 12),
            systemTargetRow.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -12),
            systemTargetRow.heightAnchor.constraint(equalToConstant: 52),
            
            // 第二段：App音频
            appsHeader.topAnchor.constraint(equalTo: systemTargetRow.bottomAnchor, constant: 16),
            appsHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            appsHeader.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -8),
            
            refreshButton.centerYAnchor.constraint(equalTo: appsHeader.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -16),
            // 宽高只给下限，具体尺寸由 intrinsicContentSize 决定（BUG-013）：
            // 钉死 80×24 会与内部 28 高度约束冲突，且英文 "REFRESH"+图标(~100pt) 装不下被压缩变形
            refreshButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            refreshButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            
            appsScroll.topAnchor.constraint(equalTo: appsHeader.bottomAnchor, constant: 8),
            appsScroll.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 12),
            appsScroll.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -12),
            appsScroll.bottomAnchor.constraint(equalTo: micHeader.topAnchor, constant: -12),
            
            // 第三段：麦克风设备（固定在底部）
            micHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            micHeader.trailingAnchor.constraint(lessThanOrEqualTo: audioRecorderTabView.trailingAnchor, constant: -16),
            micHeader.bottomAnchor.constraint(equalTo: micDeviceRow.topAnchor, constant: -8),

            // FEAT-004: 麦克风输入设备选择行（固定最底）
            // UI-015: 高度由 selector 内容驱动（展开时撑开）
            micDeviceRow.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 12),
            micDeviceRow.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -12),
            micDeviceRow.bottomAnchor.constraint(equalTo: audioRecorderTabView.bottomAnchor, constant: -12),
            micDeviceRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
    }
    
    // MARK: - Actions
    private func selectSystemAudioTarget() {
        // 录制中锁定：禁止切换音源
        guard !isRecordingLocked else { return }
        logger.info("录制目标切换为：全部系统声音（无进程选中）")
        selectedPIDs = []
        selectedSources = [AudioSource(kind: .system)]
        systemTargetRow.isSelectedTarget = true
        rebuildProcessRows()
        delegate?.sidebarViewDidSelectProcesses(self, pids: [])
        delegate?.sidebarViewDidChangeSourceSelection(self)
    }
    
    /// UI-043 R3: 麦克风混录状态变化统一出口（勾选/取消勾选驱动，selftest 钩子同走此路）
    private func microphoneMixChanged(enabled: Bool) {
        logger.info("麦克风附加输入: \(enabled ? "开启" : "关闭")")
        delegate?.sidebarViewDidChangeMixAudio(self, enabled: enabled)
        delegate?.sidebarViewDidChangeSourceSelection(self)
    }
    
    @objc private func refreshButtonClicked() {
        delegate?.sidebarViewDidRequestProcessRefresh(self)
    }
    
    // MARK: - TabContainerViewDelegate
    func tabContainerViewDidSelectTab(_ view: TabContainerView, tabId: String) {
        logger.info("侧边栏切换到Tab: \(tabId)")
        UXEventLog.shared.state("tab_changed", detail: ["tab": tabId])
        if tabId == "audioRecorder" {
            // 切到录制 Tab → 通知 delegate 回到录制态
            delegate?.sidebarViewDidChangeSourceSelection(self)
        }
    }
    
    // MARK: - RecordedFilesViewDelegate
    func recordedFilesViewDidSelectFile(_ view: RecordedFilesView, file: RecordedFileInfo) {
        delegate?.sidebarViewDidSelectFile(self, file: file)
    }
    
    func recordedFilesViewDidDoubleClickFile(_ view: RecordedFilesView, file: RecordedFileInfo) {
        // 双击文件，从Finder中打开
        delegate?.sidebarViewDidDoubleClickFile(self, file: file)
    }
    
    func recordedFilesViewDidRenameFile(_ view: RecordedFilesView, file: RecordedFileInfo, newName: String) {
        delegate?.sidebarViewDidRenameFile(self, file: file, newName: newName)
    }
    
    func recordedFilesViewDidRequestEditFile(_ view: RecordedFilesView, file: RecordedFileInfo) {
        delegate?.sidebarViewDidRequestEditFile(self, file: file)
    }
    
    
    // MARK: - Public Methods
    func updateProcessList(_ processes: [AudioProcessInfo]) {
        availableProcesses = processes
        preloadIcons(for: processes)
        rebuildProcessRows()
    }
    
    func restoreProcessSelection(_ processes: [AudioProcessInfo]) {
        // 不恢复任何选择，完全重置状态
        logger.info("📝 完全重置UI状态，不恢复任何进程选择")
        selectedPIDs = []
        selectedSources = [AudioSource(kind: .system)]
        rebuildProcessRows()
    }
    
    func isSystemAudioSourceSelected() -> Bool {
        // 没有选中任何进程 = 系统声音
        return selectedPIDs.isEmpty
    }
    
    func isMicrophoneSourceSelected() -> Bool {
        // UI-043 R3: 有勾选行 = 混录麦克风（原开关行 isSelected 语义）
        return micMixEnabled
    }

    /// FIX-006/007 自测钩子：编程开/关麦克风混录（selftest 触发器用）。
    /// R3: enabled=true 勾到跟随投影（系统默认设备行，preferred 保持 nil 动态跟随）；
    /// enabled=false 全不勾。等价旧「点开关行」语义，lite 触发器 `mix` 位无需改动。
    func setMicrophoneMixEnabled(_ enabled: Bool) {
        guard micMixEnabled != enabled else { return }
        micMixEnabled = enabled
        refreshMicDeviceList()
        microphoneMixChanged(enabled: enabled)
    }
    
    func getSelectedProcesses() -> [AudioProcessInfo] {
        return availableProcesses.filter { selectedPIDs.contains($0.pid) }
    }
    
    /// REQ-2.0-02: 获取当前选中录制目标的名称（用于状态栏引导文案）
    /// Phase 0: 1选返回名字，多选返回"A, B +N"格式
    func getSelectedProcessName() -> String? {
        if isSystemAudioSourceSelected() {
            return "系统声音".localized
        }
        let names = selectedSources.filter { $0.pid != nil }.map { $0.displayName }
        switch names.count {
        case 0: return "系统声音".localized
        case 1: return names[0]
        case 2: return "\(names[0]), \(names[1])"
        default: return "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }
    
    /// 获取指定进程的应用图标
    func getIconForProcess(_ process: AudioProcessInfo) -> NSImage {
        return getCachedIcon(for: process)
    }
    
    // MARK: - Process Rows
    private func rebuildProcessRows() {
        // Update system target row selection state based on whether any process is selected
        systemTargetRow.isSelectedTarget = selectedPIDs.isEmpty
        
        for view in appsStack.arrangedSubviews {
            appsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if availableProcesses.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "未检测到音频进程".localized)
            emptyLabel.font = IndustrialTypography.label
            emptyLabel.textColor = IndustrialColors.textTertiary
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            appsStack.addArrangedSubview(emptyLabel)
            emptyLabel.widthAnchor.constraint(equalTo: appsStack.widthAnchor, constant: -8).isActive = true
            emptyLabel.heightAnchor.constraint(equalToConstant: 40).isActive = true
            return
        }

        for process in availableProcesses {
            let row = IndustrialProcessRowView(process: process, icon: getCachedIcon(for: process))
            row.isSelectedRow = selectedPIDs.contains(process.pid)
            row.onClick = { [weak self] in
                guard let self = self else { return }
                guard !self.isRecordingLocked else { return }
                let pid = process.pid
                let isCmdClick = NSEvent.modifierFlags.contains(.command)
                if isCmdClick {
                    if let idx = self.selectedPIDs.firstIndex(where: { $0 == pid }) {
                        self.selectedPIDs.remove(at: idx)
                        self.selectedSources.removeAll { $0.pid == pid }
                    } else {
                        guard self.selectedPIDs.count < 5 else {
                            self.onSelectionLimitReached?(self)
                            return
                        }
                        self.selectedPIDs.append(pid)
                        self.selectedSources.append(AudioSource(kind: .process(pid: process.pid, name: process.name, bundleID: process.bundleID)))
                    }
                } else {
                    if self.selectedPIDs == [pid] {
                        self.selectedPIDs = []
                        self.selectedSources = [AudioSource(kind: .system)]
                    } else {
                        self.selectedPIDs = [pid]
                        self.selectedSources = [AudioSource(kind: .process(pid: process.pid, name: process.name, bundleID: process.bundleID))]
                    }
                }
                self.rebuildProcessRows()
                self.delegate?.sidebarViewDidSelectProcesses(self, pids: Array(self.selectedPIDs))
                self.delegate?.sidebarViewDidChangeSourceSelection(self)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 40).isActive = true
            appsStack.addArrangedSubview(row)
        }
        

    }
    
    // MARK: - Private Methods
    private func preloadIcons(for processes: [AudioProcessInfo]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for process in processes {
                let key = process.path as NSString
                if !process.path.isEmpty && self.iconCache.object(forKey: key) == nil {
                    // 使用改进的 loadAppIcon 方法，支持 Helper 进程图标映射和 bundleID 查找
                    let icon = self.loadAppIcon(for: process.path, bundleID: process.bundleID)
                    // 调整图标大小以优化性能
                    icon.size = NSSize(width: 24, height: 24)
                    
                    // NSCache 是线程安全的，可直接在后台线程写入
                    self.iconCache.setObject(icon, forKey: key)
                    
                    DispatchQueue.main.async {
                        self.logger.debug("🔄 预加载图标: \(process.name) -> \(process.path)")
                    }
                } else if process.path.isEmpty {
                    self.logger.debug("⚠️ 跳过预加载（路径为空）: \(process.name)")
                }
            }
        }
    }
    
    private func getCachedIcon(for process: AudioProcessInfo) -> NSImage {
        let key = process.path as NSString
        if let cachedIcon = iconCache.object(forKey: key) {
            return cachedIcon
        }
        
        // 如果缓存中没有，立即加载并缓存（传入 bundleID 以支持更精确的图标查找）
        let icon = loadAppIcon(for: process.path, bundleID: process.bundleID)
        icon.size = NSSize(width: 24, height: 24)
        iconCache.setObject(icon, forKey: key)
        
        return icon
    }
    
    /// 加载应用图标，支持多种方式
    private func loadAppIcon(for path: String, bundleID: String = "") -> NSImage {
        // 特殊处理: 各种浏览器 Helper 进程使用主应用图标
        if let mainAppPath = getMainAppPathForHelper(path: path) {
            let icon = NSWorkspace.shared.icon(forFile: mainAppPath)
            if icon.size.width > 0 && icon.size.height > 0 {
                logger.debug("✅ Helper 进程使用主应用图标: \(mainAppPath)")
                return icon
            }
        }
        
        // 方法1: 直接从 .app bundle 路径加载
        if path.hasSuffix(".app") {
            let icon = NSWorkspace.shared.icon(forFile: path)
            // 检查是否成功加载了真实的应用图标（不是默认文件图标）
            if icon.representations.count > 1 || (icon.size.width > 16 && icon.size.height > 16) {
                logger.debug("✅ 从 .app bundle 加载图标成功: \(path)")
                return icon
            } else {
                logger.debug("⚠️ 从 .app bundle 加载的是默认图标，尝试其他方法: \(path)")
            }
        }
        
        // 方法2: 尝试从可执行文件路径向上查找主 .app bundle（跳过 Helpers）
        let bundlePath = findMainAppBundlePath(from: path)
        if bundlePath != path {
            let icon = NSWorkspace.shared.icon(forFile: bundlePath)
            if icon.size.width > 0 && icon.size.height > 0 {
                logger.debug("✅ 从主应用 bundle 路径加载图标成功: \(bundlePath)")
                return icon
            }
        }
        
        // 方法3: 通过 bundleID 查找主应用路径并获取图标
        if !bundleID.isEmpty {
            // 尝试从 Helper 的 bundleID 推导主应用 bundleID
            let mainBundleID = deriveMainAppBundleID(from: bundleID)
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainBundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                if icon.representations.count > 1 || (icon.size.width > 16 && icon.size.height > 16) {
                    logger.debug("✅ 从 bundleID 查找主应用图标成功: \(mainBundleID) -> \(appURL.path)")
                    return icon
                }
            }
            // 也尝试直接用原始 bundleID 查找
            if mainBundleID != bundleID, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                if icon.representations.count > 1 || (icon.size.width > 16 && icon.size.height > 16) {
                    logger.debug("✅ 从原始 bundleID 加载图标成功: \(bundleID) -> \(appURL.path)")
                    return icon
                }
            }
        }
        
        // 方法4: 使用通用应用图标（不使用当前 App 图标）
        logger.debug("⚠️ 所有方法都失败，使用通用应用图标: \(path)")
        return NSWorkspace.shared.icon(forFile: "/Applications")
    }
    
    /// 从 Helper 进程的 bundleID 推导主应用的 bundleID
    /// 例如: "com.google.Chrome.helper" → "com.google.Chrome"
    ///       "com.google.Chrome.helper.renderer" → "com.google.Chrome"
    private func deriveMainAppBundleID(from helperBundleID: String) -> String {
        let lowered = helperBundleID.lowercased()
        // Remove common helper suffixes
        let suffixes = [".helper.renderer", ".helper.gpu", ".helper.plugin", ".helper", ".renderer", ".gpu"]
        for suffix in suffixes {
            if lowered.hasSuffix(suffix) {
                let endIndex = helperBundleID.index(helperBundleID.endIndex, offsetBy: -suffix.count)
                return String(helperBundleID[helperBundleID.startIndex..<endIndex])
            }
        }
        return helperBundleID
    }
    
    /// 从可执行文件路径查找 .app bundle 路径
    private func findAppBundlePath(from executablePath: String) -> String {
        let url = URL(fileURLWithPath: executablePath)
        var currentURL = url
        
        while currentURL.path != "/" {
            if currentURL.pathExtension == "app" {
                return currentURL.path
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        return executablePath
    }
    
    /// 从可执行文件路径查找主应用 .app bundle 路径（跳过 Helpers/Frameworks）
    private func findMainAppBundlePath(from executablePath: String) -> String {
        let url = URL(fileURLWithPath: executablePath)
        var currentURL = url
        var foundApp: URL?
        
        while currentURL.path != "/" {
            if currentURL.pathExtension == "app" {
                foundApp = currentURL
                // 如果路径包含 Helpers 或 Frameworks，继续向上查找主应用
                if currentURL.path.contains("/Helpers/") || 
                   currentURL.path.contains("/Frameworks/") ||
                   currentURL.lastPathComponent.contains("Helper") {
                    currentURL = currentURL.deletingLastPathComponent()
                    continue
                }
                // 找到主应用
                return currentURL.path
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        // 如果没有找到主应用，返回找到的第一个.app，或原始路径
        return foundApp?.path ?? executablePath
    }
    

    
    /// 获取 Helper 进程对应的主应用路径（通用方案，不再逐品牌硬编码）
    private func getMainAppPathForHelper(path: String) -> String? {
        // 通用方案：从路径中提取最顶层的 .app bundle
        // 例如 /Applications/Comet.app/.../Helpers/Comet Helper.app/.../Comet Helper
        //    → /Applications/Comet.app
        let mainPath = findMainAppBundlePath(from: path)
        if mainPath != path && FileManager.default.fileExists(atPath: mainPath) {
            return mainPath
        }
        return nil
    }
    
    /// 刷新已录制文件列表
    func refreshRecordedFiles() {
        recordedFilesView.refreshFiles()
    }
    
    /// 加载录音文件列表（启动时使用）
    func loadRecordedFiles(_ files: [RecordedFileInfo]) {
        recordedFilesView.loadRecordedFiles(files)
    }
    
    /// 添加新的录制文件到列表
    func addRecordedFile(_ file: RecordedFileInfo) {
        recordedFilesView.addRecordedFile(file)
    }
}

// MARK: - IndustrialAudioTargetRowView
/// 固定录制目标行：全部系统声音。它与具体应用进程互斥。
final class IndustrialAudioTargetRowView: NSView {
    var onClick: (() -> Void)?
    var isSelectedTarget: Bool = false { didSet { updateAppearance() } }

    private let gradientLayer = CAGradientLayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let checkBadge = NSView()
    private let checkGlyph = NSTextField(labelWithString: "✓")
    // UI-003 v3 批次2k: 未选中态右侧 radio 空圈（系统卡 16px stroke #525252，Figma §2）
    private let radioEmptyBadge = NSView()
    private var titleCenterYConstraint: NSLayoutConstraint!
    private var isHovering = false
    
    init(title: String, subtitle: String, systemSymbolName: String) {
        super.init(frame: .zero)
        setupView()
        titleLabel.stringValue = title
        metaLabel.stringValue = subtitle
        metaLabel.isHidden = subtitle.isEmpty
        // 有副题时标题上移，形成两行堆叠（Figma 系统声音卡 54 高双行布局）
        titleCenterYConstraint.constant = subtitle.isEmpty ? 0 : -9
        iconView.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: title)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.xs
        layer?.borderWidth = 0
        translatesAutoresizingMaskIntoConstraints = false

        // UI-003: 选中态底色对齐设计稿实测 #13BBA3 柔和薄荷纯色（非饱和渐变）
        gradientLayer.colors = [NSColor(hex: "#13BBA3").cgColor, NSColor(hex: "#13BBA3").cgColor]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.isHidden = true
        layer?.addSublayer(gradientLayer)

        iconView.contentTintColor = IndustrialColors.onSurfaceVariant
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.font = IndustrialTypography.body
        titleLabel.textColor = IndustrialColors.onSurface
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        metaLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        metaLabel.textColor = NSColor(hex: "#A3A3A3")
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metaLabel)

        // UI-003 v3.1: 选中态右侧白色圆勾（16px 白底 + mint 勾，Figma 规格）
        checkBadge.wantsLayer = true
        checkBadge.layer?.backgroundColor = NSColor.white.cgColor
        checkBadge.layer?.cornerRadius = 8
        checkBadge.isHidden = true
        checkBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkBadge)

        checkGlyph.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        checkGlyph.textColor = NSColor(hex: "#13BBA3")
        checkGlyph.alignment = .center
        checkGlyph.translatesAutoresizingMaskIntoConstraints = false
        checkBadge.addSubview(checkGlyph)

        // UI-003 v3 批次2k: 未选中态 radio 空圈（16px stroke #525252）
        radioEmptyBadge.wantsLayer = true
        radioEmptyBadge.layer?.backgroundColor = NSColor.clear.cgColor
        radioEmptyBadge.layer?.borderWidth = 1
        radioEmptyBadge.layer?.borderColor = NSColor(hex: "#525252").cgColor
        radioEmptyBadge.layer?.cornerRadius = 8
        radioEmptyBadge.isHidden = true
        radioEmptyBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(radioEmptyBadge)

        titleCenterYConstraint = titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleCenterYConstraint,
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkBadge.leadingAnchor, constant: -6),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            checkBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            checkBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkBadge.widthAnchor.constraint(equalToConstant: 16),
            checkBadge.heightAnchor.constraint(equalToConstant: 16),

            radioEmptyBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            radioEmptyBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            radioEmptyBadge.widthAnchor.constraint(equalToConstant: 16),
            radioEmptyBadge.heightAnchor.constraint(equalToConstant: 16),

            checkGlyph.centerXAnchor.constraint(equalTo: checkBadge.centerXAnchor),
            checkGlyph.centerYAnchor.constraint(equalTo: checkBadge.centerYAnchor)
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    private func updateAppearance() {
        if isSelectedTarget {
            layer?.backgroundColor = NSColor.clear.cgColor
            gradientLayer.isHidden = false
            titleLabel.textColor = .white
            iconView.contentTintColor = .white
            checkBadge.isHidden = false
            radioEmptyBadge.isHidden = true
            // Figma §2 选中行副题：Focused App Capture #CCFBF1@0.90
            metaLabel.stringValue = "正在捕获所选应用".localized
            metaLabel.textColor = NSColor(hex: "#CCFBF1").withAlphaComponent(0.90)
            metaLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        } else {
            gradientLayer.isHidden = true
            checkBadge.isHidden = true
            radioEmptyBadge.isHidden = false
            // Figma §2 系统卡副题：Default Output Master #A3A3A3 10px w400
            metaLabel.stringValue = "默认输出主设备".localized
            metaLabel.textColor = NSColor(hex: "#A3A3A3")
            metaLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            if isHovering {
                layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
                titleLabel.textColor = IndustrialColors.onSurface
                iconView.contentTintColor = IndustrialColors.onSurfaceVariant
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                titleLabel.textColor = IndustrialColors.onSurface
                iconView.contentTintColor = IndustrialColors.onSurfaceVariant
            }
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.pointingHand.set()
        updateAppearance()
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.arrow.set()
        layer?.transform = CATransform3DIdentity
        updateAppearance()
    }
    
    override func mouseDown(with event: NSEvent) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DMakeTranslation(0, -1, 0)
        CATransaction.commit()
    }
    
    override func mouseUp(with event: NSEvent) {
        layer?.transform = CATransform3DIdentity
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

// MARK: - IndustrialCheckboxView
/// 工业风格方形 Checkbox — 遵循 IndustrialColors 设计令牌
final class IndustrialCheckboxView: NSView {
    var isChecked: Bool = false { didSet { updateAppearance() } }
    var isEnabled: Bool = true { didSet { updateAppearance(); isHidden = !isEnabled ? false : isHidden } }
    var onClick: (() -> Void)?

    private let boxLayer = CALayer()
    private let checkmarkLayer = CATextLayer()
    private let titleLayer = CATextLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.xs
        layer?.borderWidth = 0

        // Accessibility: Checkbox 标识
        setAccessibilityElement(true)
        setAccessibilityIdentifier("ProcessCheckbox")
        setAccessibilityRole(.checkBox)

        // Checkbox 方形框
        boxLayer.cornerRadius = IndustrialCornerRadius.xs
        layer?.addSublayer(boxLayer)

        // ✓ 勾号
        checkmarkLayer.string = "✓"
        checkmarkLayer.fontSize = 11
        checkmarkLayer.alignmentMode = .center
        checkmarkLayer.isWrapped = false
        checkmarkLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        boxLayer.addSublayer(checkmarkLayer)

        updateAppearance()
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 16
        let y = (bounds.height - size) / 2
        boxLayer.frame = CGRect(x: 0, y: y, width: size, height: size)
        checkmarkLayer.frame = CGRect(x: 0, y: -1, width: size, height: size)
    }

    private func updateAppearance() {
        guard let layer = layer else { return }
        let boxColor: NSColor
        let borderColor: NSColor
        let checkColor: NSColor

        if !isEnabled {
            boxColor = IndustrialColors.surfaceContainerLow
            borderColor = IndustrialColors.outlineVariant.withAlphaComponent(0.4)
            checkColor = NSColor.clear
            layer.opacity = 0.4
        } else if isChecked {
            boxColor = IndustrialColors.primaryContainer
            borderColor = IndustrialColors.primaryContainer
            checkColor = IndustrialColors.onPrimaryContainer
            layer.opacity = 1.0
        } else {
            boxColor = IndustrialColors.surfaceContainerLow
            borderColor = IndustrialColors.outlineVariant
            checkColor = NSColor.clear
            layer.opacity = 1.0
        }

        boxLayer.backgroundColor = boxColor.cgColor
        boxLayer.borderColor = borderColor.cgColor
        boxLayer.borderWidth = 0
        checkmarkLayer.foregroundColor = checkColor.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        if isEnabled { onClick?() }
    }

    override func mouseUp(with event: NSEvent) {
        if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    override func resetCursorRects() {
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

// MARK: - IndustrialProcessRowView
/// 自绘进程行 — 去除 NSTableView 系统白底/蓝色选中态，边框高亮表示选中
final class IndustrialProcessRowView: NSView {
    var onClick: (() -> Void)?
    var isSelectedRow: Bool = false { didSet { updateAppearance() } }

    private let gradientLayer = CAGradientLayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let checkBadge = NSView()
    private let checkGlyph = NSTextField(labelWithString: "✓")
    // UI-003 v3 批次2k: 未选中态右侧 radio 空圈（App 行 14px stroke #404040，Figma §2）
    private let radioEmptyBadge = NSView()
    private var isHovering = false
    
    init(process: AudioProcessInfo, icon: NSImage) {
        super.init(frame: .zero)
        setupView()
        configure(process: process, icon: icon)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.xs
        layer?.borderWidth = 0  // 未选中态无边框，选中态翡翠渐变
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        // UI-003: 选中态底色 #13BBA3（与系统声音行一致）
        gradientLayer.colors = [NSColor(hex: "#13BBA3").cgColor, NSColor(hex: "#13BBA3").cgColor]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.isHidden = true
        layer?.addSublayer(gradientLayer)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Accessibility: 进程行标识（通过外部 configure 设置具体 pid）
        setAccessibilityElement(true)
        setAccessibilityRole(.row)

        titleLabel.font = IndustrialTypography.body
        titleLabel.textColor = IndustrialColors.onSurface
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // UI-003 v3.1: 选中态右侧白色圆勾（16px 白底 + mint 勾，Figma 规格）
        checkBadge.wantsLayer = true
        checkBadge.layer?.backgroundColor = NSColor.white.cgColor
        checkBadge.layer?.cornerRadius = 8
        checkBadge.isHidden = true
        checkBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkBadge)

        checkGlyph.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        checkGlyph.textColor = NSColor(hex: "#13BBA3")
        checkGlyph.alignment = .center
        checkGlyph.translatesAutoresizingMaskIntoConstraints = false
        checkBadge.addSubview(checkGlyph)

        // UI-003 v3 批次2k: 未选中态 radio 空圈（14px stroke #404040）
        radioEmptyBadge.wantsLayer = true
        radioEmptyBadge.layer?.backgroundColor = NSColor.clear.cgColor
        radioEmptyBadge.layer?.borderWidth = 1
        radioEmptyBadge.layer?.borderColor = NSColor(hex: "#404040").cgColor
        radioEmptyBadge.layer?.cornerRadius = 7
        radioEmptyBadge.isHidden = true
        radioEmptyBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(radioEmptyBadge)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkBadge.leadingAnchor, constant: -6),

            checkBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            checkBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkBadge.widthAnchor.constraint(equalToConstant: 16),
            checkBadge.heightAnchor.constraint(equalToConstant: 16),

            radioEmptyBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            radioEmptyBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            radioEmptyBadge.widthAnchor.constraint(equalToConstant: 14),
            radioEmptyBadge.heightAnchor.constraint(equalToConstant: 14),

            checkGlyph.centerXAnchor.constraint(equalTo: checkBadge.centerXAnchor),
            checkGlyph.centerYAnchor.constraint(equalTo: checkBadge.centerYAnchor)
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }

    private func configure(process: AudioProcessInfo, icon: NSImage) {
        iconView.image = icon
        titleLabel.stringValue = process.name
        // Accessibility: 用 pid 唯一标识每一行
        let pidStr = String(process.pid)
        setAccessibilityIdentifier("ProcessRow-\(pidStr)")
        setAccessibilityLabel(process.name)
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    private func updateAppearance() {
        if isSelectedRow {
            layer?.backgroundColor = NSColor.clear.cgColor
            gradientLayer.isHidden = false
            titleLabel.textColor = .white
            checkBadge.isHidden = false
            radioEmptyBadge.isHidden = true
        } else {
            gradientLayer.isHidden = true
            checkBadge.isHidden = true
            radioEmptyBadge.isHidden = false
            if isHovering {
                layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
                titleLabel.textColor = IndustrialColors.onSurface
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                titleLabel.textColor = IndustrialColors.onSurface
            }
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.pointingHand.set()
        updateAppearance()
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.arrow.set()
        layer?.transform = CATransform3DIdentity
        updateAppearance()
    }
    
    override func mouseDown(with event: NSEvent) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DMakeTranslation(0, -1, 0)
        CATransaction.commit()
    }
    
    override func mouseUp(with event: NSEvent) {
        layer?.transform = CATransform3DIdentity
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

// MARK: - IndustrialTableRowView
/// Industrial 风格表格行 — 文件列表暂用，进程列表已改为完全自绘
class IndustrialTableRowView: NSTableRowView {

    private let indicatorLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 青色指示条（默认隐藏）
        indicatorLayer.backgroundColor = IndustrialColors.primaryContainer.cgColor
        indicatorLayer.isHidden = true
        layer?.addSublayer(indicatorLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        // 左侧 3px 宽指示条
        indicatorLayer.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
    }

    override var isSelected: Bool {
        didSet {
            indicatorLayer.isHidden = !isSelected
            needsDisplay = true
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // Industrial: 选中背景 surfaceContainerHighest
        IndustrialColors.surfaceContainerHighest.setFill()
        NSBezierPath(rect: bounds).fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // Industrial: 默认透明背景
        if !isSelected {
            IndustrialColors.surfaceContainer.setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }

    // Hover 效果
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = nil
        }
    }
}

// MARK: - IndustrialMicDeviceSelectorView
/// UI-015/UI-043: 自绘麦克风设备选择器（弃用 NSPopUpButton；UI-043 去掉「跟随系统默认」伪行）。
/// UI-043 R4（2026-11-07 老板实机反馈「下拉箭头都可以不要，直接就是选项」）：「设备」分组头与
/// 折叠交互整个退役——MICROPHONE 段标题下**直接平铺设备选项**，无头无箭头。
/// - 异常/空态提示（失效警告 / 「未检测到」）改为列表首行 statusLabel（正常态隐藏不占位）
/// - 选项 displayName 由 MicDeviceManager.displayName(for:) 友好化处理（Aggregate 子设备解析）
final class IndustrialMicDeviceSelectorView: NSView {
    /// 一个选项数据
    struct Option {
        /// 具体设备 UID（UI-043 后列表无 uid=nil 伪行；跟随语义由 Sidebar 写 preferredDeviceUID=nil）
        let uid: String?
        /// 行内主标
        let displayName: String
        /// 预留副标字段（R2 起行内不再渲染；当前唯一调用方恒传 nil）
        let subtitle: String?
        /// 该设备是否对应当前系统默认设备（行内 hint）
        let isCurrent: Bool
    }

    /// reselect=true：再点当前已勾选行（R3：取消勾选 = 关闭混录）
    var onSelect: ((Option, Bool) -> Void)?

    /// 所选设备失效时为 true（列表首行警告提示）
    var isInvalid: Bool = false { didSet { updateAppearance() } }

    /// UI-027: 无设备时的提示文案（非 nil 且列表为空时优先显示）
    var emptyStateText: String? { didSet { updateAppearance() } }

    /// R4: 异常/空态提示行——常驻 listStack 首项，正常态 isHidden（NSStackView 不占位）
    private let statusLabel = NSTextField(labelWithString: "")
    private let listStack = NSStackView()

    private var options: [Option] = []
    private var selectedIndex: Int = 0

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
        layer?.cornerRadius = IndustrialCornerRadius.xs
        layer?.borderWidth = 0
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = IndustrialTypography.body
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        listStack.orientation = .vertical
        listStack.spacing = 2
        listStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        listStack.alignment = .leading
        listStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(listStack)

        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: topAnchor),
            listStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])

        updateAppearance()
    }

    /// UI-043 R3: selectedIndex=-1 合法（全不勾 = 混录关）
    func configure(options: [Option], selectedIndex: Int) {
        self.options = options
        self.selectedIndex = max(-1, min(selectedIndex, options.count - 1))
        rebuildList()
        updateAppearance()
    }

    private func rebuildList() {
        for v in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        // R4: 提示行常驻首项（正常态隐藏不占位，NSStackView 自动收起）
        listStack.addArrangedSubview(statusLabel)
        statusLabel.leadingAnchor.constraint(equalTo: listStack.leadingAnchor, constant: 10).isActive = true
        statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: listStack.trailingAnchor, constant: -12).isActive = true
        // UI-043: 伪行删除后不再在 idx==1 插分隔线（否则会插进第二台真设备前）
        for (idx, opt) in options.enumerated() {
            let row = IndustrialMicDeviceOptionRowView(option: opt, isSelected: idx == self.selectedIndex)
            row.onClick = { [weak self] in
                guard let self = self else { return }
                self.selected(at: idx)
            }
            listStack.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: listStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: listStack.trailingAnchor).isActive = true
        }
    }

    private func selected(at idx: Int) {
        guard idx >= 0 && idx < options.count else { return }
        if idx == selectedIndex {
            // UI-043 R3：再点已勾选 → reselect=true，由 Sidebar 取消勾选关闭混录
            onSelect?(options[idx], true)
            return
        }
        selectedIndex = idx
        rebuildList()
        updateAppearance()
        onSelect?(options[idx], false)
    }

    private func updateAppearance() {
        if isInvalid {
            statusLabel.stringValue = "所选设备已失效，已回退系统默认".localized
            statusLabel.textColor = IndustrialColors.statusWarning
            statusLabel.isHidden = false
        } else if options.isEmpty, let empty = emptyStateText {
            statusLabel.stringValue = empty
            statusLabel.textColor = IndustrialColors.textTertiary
            statusLabel.isHidden = false
        } else {
            // R4: 正常态无任何头部——纯设备选项平铺；当前勾选由行内 checkbox 表达
            statusLabel.isHidden = true
        }
    }
}

// MARK: - IndustrialMicDeviceOptionRowView
/// UI-027: 设备行。UI-043 R2（2026-11-07 老板参考图）：左侧自绘 checkbox（勾选态 primary 填充+白勾、
/// 未选态描边空块）+ 圆底麦克风图标 + 设备名——「直接勾选的形式」，选中态由 checkbox 表达，标题不再 semibold。
final class IndustrialMicDeviceOptionRowView: NSView {
    var onClick: (() -> Void)?
    private let checkBox = MicCheckIndicator()
    private let micBadge = NSView()
    private let micIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isHovering = false

    init(option: IndustrialMicDeviceSelectorView.Option, isSelected: Bool) {
        super.init(frame: .zero)
        setupView()
        configure(option: option, isSelected: isSelected)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.xs
        translatesAutoresizingMaskIntoConstraints = false

        checkBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkBox)

        micBadge.wantsLayer = true
        micBadge.layer?.backgroundColor = IndustrialColors.primary.cgColor
        micBadge.layer?.cornerRadius = 11
        micBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(micBadge)

        if let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
            micIcon.image = img
        }
        micIcon.contentTintColor = .white
        micIcon.translatesAutoresizingMaskIntoConstraints = false
        micBadge.addSubview(micIcon)

        titleLabel.font = IndustrialTypography.body
        titleLabel.textColor = IndustrialColors.onSurface
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),

            checkBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            checkBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkBox.widthAnchor.constraint(equalToConstant: 16),
            checkBox.heightAnchor.constraint(equalToConstant: 16),

            micBadge.leadingAnchor.constraint(equalTo: checkBox.trailingAnchor, constant: 8),
            micBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            micBadge.widthAnchor.constraint(equalToConstant: 22),
            micBadge.heightAnchor.constraint(equalToConstant: 22),

            micIcon.centerXAnchor.constraint(equalTo: micBadge.centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: micBadge.centerYAnchor),
            micIcon.widthAnchor.constraint(equalToConstant: 12),
            micIcon.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: micBadge.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    private func configure(option: IndustrialMicDeviceSelectorView.Option, isSelected: Bool) {
        titleLabel.stringValue = option.displayName
        // R2: subtitle 字段保留但不再渲染（当前唯一调用方恒传 nil）；选中态全由 checkbox 表达
        checkBox.isChecked = isSelected
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.pointingHand.set()
        layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.arrow.set()
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - MicCheckIndicator
/// UI-043 R2: 勾选框自绘——选中=primary 填充圆角块+白色对勾路径；未选=outlineVariant 描边空块。
final class MicCheckIndicator: NSView {
    var isChecked: Bool = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard NSGraphicsContext.current != nil else { return }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4.5, yRadius: 4.5)
        if isChecked {
            IndustrialColors.primary.setFill()
            path.fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: rect.midX - 3.2, y: rect.midY + 0.4))
            check.line(to: NSPoint(x: rect.midX - 1.0, y: rect.midY - 2.4))
            check.line(to: NSPoint(x: rect.midX + 3.4, y: rect.midY + 2.8))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            path.lineWidth = 1.2
            IndustrialColors.outlineVariant.setStroke()
            path.stroke()
        }
    }
}
