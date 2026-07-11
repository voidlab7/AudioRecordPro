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
        title: "录制全部系统声音",
        subtitle: "",
        systemSymbolName: "speaker.wave.3.fill"
    )
    private let micHeader = NSTextField()
    private let refreshButton = IndustrialButtonView(title: "刷新", icon: "arrow.clockwise")
    private let appsScroll = NSScrollView()
    private let appsStack = NSStackView()
    private let microphonePanel = IndustrialMicrophoneRowView()
    
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

        // 移除旧的网格和边框层
        layer?.sublayers?.filter { $0.name == "grid" || $0.name == "border" }.forEach { $0.removeFromSuperlayer() }
        
        // 绘制网格纹理
        let gridLayer = CAShapeLayer()
        gridLayer.name = "grid"
        let path = CGMutablePath()
        let spacing = IndustrialSpacing.gridTextureInterval
        
        // 垂直线
        var x: CGFloat = 0
        while x <= bounds.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
            x += spacing
        }
        
        // 水平线
        var y: CGFloat = 0
        while y <= bounds.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }
        
        gridLayer.path = path
        gridLayer.strokeColor = IndustrialColors.gridLight.cgColor
        gridLayer.lineWidth = 1
        gridLayer.fillColor = nil
        layer?.insertSublayer(gridLayer, at: 0)
        
        // 右侧边框
        let borderLayer = CALayer()
        borderLayer.name = "border"
        borderLayer.backgroundColor = IndustrialColors.outlineVariant.cgColor
        borderLayer.frame = CGRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
        layer?.addSublayer(borderLayer)
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
        audioRecorderTabView.addSubview(microphonePanel)
        
        // 创建Tab
        let audioRecorderTab = TabItem(
            id: "audioRecorder",
            title: "录制",
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
            title: "文件",
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
            textField.font = IndustrialTypography.h2 // 14px Bold
            textField.textColor = IndustrialColors.onSurface // 亮灰
            textField.translatesAutoresizingMaskIntoConstraints = false
        }
        
        styleHeader(targetHeader, "系统音频")
        styleHeader(appsHeader, "App音频")
        styleHeader(micHeader, "麦克风设备")
    }
    
    private func setupTargetControls() {
        // 系统音频（混音）选择行
        systemTargetRow.translatesAutoresizingMaskIntoConstraints = false
        systemTargetRow.isSelectedTarget = true  // 默认选中
        systemTargetRow.onClick = { [weak self] in
            self?.selectSystemAudioTarget()
        }
        
        microphonePanel.translatesAutoresizingMaskIntoConstraints = false
        microphonePanel.onChange = { [weak self] enabled in
            self?.microphoneInputChanged(enabled: enabled)
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
        appsScroll.layer?.borderWidth = 1
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
            refreshButton.widthAnchor.constraint(equalToConstant: 80),
            refreshButton.heightAnchor.constraint(equalToConstant: 24),
            
            appsScroll.topAnchor.constraint(equalTo: appsHeader.bottomAnchor, constant: 8),
            appsScroll.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 12),
            appsScroll.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -12),
            appsScroll.bottomAnchor.constraint(equalTo: micHeader.topAnchor, constant: -12),
            
            // 第三段：麦克风设备（固定在底部）
            micHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            micHeader.trailingAnchor.constraint(lessThanOrEqualTo: audioRecorderTabView.trailingAnchor, constant: -16),
            micHeader.bottomAnchor.constraint(equalTo: microphonePanel.topAnchor, constant: -8),
            
            microphonePanel.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 12),
            microphonePanel.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -12),
            microphonePanel.bottomAnchor.constraint(equalTo: audioRecorderTabView.bottomAnchor, constant: -12),
            microphonePanel.heightAnchor.constraint(equalToConstant: 44)
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
    
    private func microphoneInputChanged(enabled: Bool) {
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
        return microphonePanel.isSelected
    }
    
    func getSelectedProcesses() -> [AudioProcessInfo] {
        return availableProcesses.filter { selectedPIDs.contains($0.pid) }
    }
    
    /// REQ-2.0-02: 获取当前选中录制目标的名称（用于状态栏引导文案）
    /// Phase 0: 1选返回名字，多选返回"A, B +N"格式
    func getSelectedProcessName() -> String? {
        if isSystemAudioSourceSelected() {
            return "系统声音"
        }
        let names = selectedSources.filter { $0.pid != nil }.map { $0.displayName }
        switch names.count {
        case 0: return "系统声音"
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
            let emptyLabel = NSTextField(labelWithString: "未检测到音频进程")
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
    
    private let indicatorLayer = CALayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private var isHovering = false
    
    init(title: String, subtitle: String, systemSymbolName: String) {
        super.init(frame: .zero)
        setupView()
        titleLabel.stringValue = title
        metaLabel.stringValue = subtitle
        metaLabel.isHidden = subtitle.isEmpty
        iconView.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: title)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.xs
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        
        indicatorLayer.backgroundColor = IndustrialColors.primaryContainer.cgColor
        indicatorLayer.isHidden = true
        layer?.addSublayer(indicatorLayer)
        
        iconView.contentTintColor = IndustrialColors.onSurfaceVariant
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        titleLabel.font = IndustrialTypography.body
        titleLabel.textColor = IndustrialColors.onSurface
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        metaLabel.font = IndustrialTypography.monoDB
        metaLabel.textColor = IndustrialColors.textTertiary
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metaLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
        
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }
    
    override func layout() {
        super.layout()
        indicatorLayer.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
    }
    
    private func updateAppearance() {
        layer?.backgroundColor = (isSelectedTarget ? IndustrialColors.surfaceContainerHighest : (isHovering ? IndustrialColors.surfaceContainerHigh : IndustrialColors.surfaceContainerLow)).cgColor
        layer?.borderColor = (isSelectedTarget || isHovering ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant).cgColor
        indicatorLayer.isHidden = !isSelectedTarget
        titleLabel.textColor = isSelectedTarget ? IndustrialColors.primary : IndustrialColors.onSurface
        iconView.contentTintColor = isSelectedTarget ? IndustrialColors.primary : IndustrialColors.onSurfaceVariant
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

// MARK: - IndustrialMicrophonePanelView
/// 底部附加输入面板：麦克风不是主目标，而是叠加到当前录制目标。
final class IndustrialMicrophonePanelView: NSView {
    var onChange: ((Bool) -> Void)?
    var isMicrophoneIncluded: Bool { microphoneToggle.state == .on }
    
    private let titleLabel = NSTextField(labelWithString: "附加麦克风")
    private let microphoneToggle = IndustrialToggleView(title: "同时录入麦克风")
    private let hintLabel = NSTextField(labelWithString: "混合到录制目标")
    private let meterLabel = NSTextField(labelWithString: "▂▃▅▆▇")
    
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
        layer?.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
        layer?.cornerRadius = IndustrialCornerRadius.xs
        layer?.borderWidth = 1
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        
        titleLabel.font = IndustrialTypography.label
        titleLabel.textColor = IndustrialColors.onSurface
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        microphoneToggle.translatesAutoresizingMaskIntoConstraints = false
        microphoneToggle.onChange = { [weak self] enabled in
            self?.updateAppearance()
            self?.onChange?(enabled)
        }
        addSubview(microphoneToggle)
        
        hintLabel.font = IndustrialTypography.monoDB
        hintLabel.textColor = IndustrialColors.textTertiary
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)
        
        meterLabel.font = IndustrialTypography.monoDB
        meterLabel.textColor = IndustrialColors.primaryContainer
        meterLabel.alignment = .right
        meterLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(meterLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            
            microphoneToggle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            microphoneToggle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            microphoneToggle.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: meterLabel.leadingAnchor, constant: -8),
            
            meterLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            meterLabel.centerYAnchor.constraint(equalTo: hintLabel.centerYAnchor)
        ])
        
        updateAppearance()
    }
    
    private func updateAppearance() {
        let enabled = microphoneToggle.state == .on
        layer?.borderColor = (enabled ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant).cgColor
        meterLabel.alphaValue = enabled ? 1.0 : 0.35
        hintLabel.stringValue = enabled ? "麦克风已混入" : "混合到录制目标"
    }
}

// MARK: - IndustrialMicrophoneRowView
/// 紧凑麦克风行 — 🎤图标 + 标题，点击切换选中/未选中（边框高亮）
final class IndustrialMicrophoneRowView: NSView {
    var onChange: ((Bool) -> Void)?
    var isSelected: Bool = false { didSet { updateAppearance() } }
    
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "同时录入麦克风")
    private let subtitleLabel = NSTextField(labelWithString: "混合录入当前目标")
    
    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
        layer?.cornerRadius = IndustrialCornerRadius.xs
        layer?.borderWidth = 1
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        
        // 麦克风图标
        if let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "麦克风") {
            iconView.image = image
        }
        iconView.contentTintColor = IndustrialColors.onSurfaceVariant
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        titleLabel.font = IndustrialTypography.body
        titleLabel.textColor = IndustrialColors.onSurface
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        subtitleLabel.font = IndustrialTypography.monoDB
        subtitleLabel.textColor = IndustrialColors.textTertiary
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
        
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }
    
    private func updateAppearance() {
        layer?.borderColor = (isSelected ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant).cgColor
        layer?.borderWidth = isSelected ? 2 : 1
        layer?.backgroundColor = (isSelected ? IndustrialColors.surfaceContainerHigh : IndustrialColors.surfaceContainerLow).cgColor
        iconView.contentTintColor = isSelected ? IndustrialColors.primary : IndustrialColors.onSurfaceVariant
        titleLabel.textColor = isSelected ? IndustrialColors.primary : IndustrialColors.onSurface
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        if !isSelected {
            layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        updateAppearance()
    }
    
    override func mouseDown(with event: NSEvent) {
        isSelected.toggle()
        onChange?(isSelected)
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
        layer?.borderWidth = 1

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
        boxLayer.borderWidth = 1
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
    
    private let indicatorLayer = CALayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
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
        layer?.borderWidth = 1  // 未选中态 1px outlineVariant，选中态 2px primaryContainer
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        
        indicatorLayer.backgroundColor = IndustrialColors.primaryContainer.cgColor
        indicatorLayer.isHidden = true
        layer?.addSublayer(indicatorLayer)
        
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
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
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
        indicatorLayer.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
    }
    
    private func updateAppearance() {
        // 边框高亮多选：选中 = surfaceContainerHighest 背景 + 2px primaryContainer 边框
        // 未选中 = surfaceContainerLow 背景 + 1px outlineVariant 边框
        if isSelectedRow {
            layer?.backgroundColor = IndustrialColors.surfaceContainerHighest.cgColor
            layer?.borderWidth = 2
            layer?.borderColor = IndustrialColors.primaryContainer.cgColor
            indicatorLayer.isHidden = true
            titleLabel.textColor = IndustrialColors.primary
        } else {
            layer?.backgroundColor = (isHovering ? IndustrialColors.surfaceContainerHigh : IndustrialColors.surfaceContainerLow).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = IndustrialColors.outlineVariant.cgColor
            indicatorLayer.isHidden = true
            titleLabel.textColor = IndustrialColors.onSurface
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
