import Cocoa
import Foundation

// MARK: - Delegate Protocol
protocol SidebarViewDelegate: AnyObject {
    func sidebarViewDidChangeSourceSelection(_ view: SidebarView)
    func sidebarViewDidSelectProcesses(_ view: SidebarView, pids: [pid_t])
    func sidebarViewDidRequestProcessRefresh(_ view: SidebarView)
    func sidebarViewDidSelectFile(_ view: SidebarView, file: RecordedFileInfo)
    func sidebarViewDidDoubleClickFile(_ view: SidebarView, file: RecordedFileInfo)
    func sidebarViewDidRequestExportToMP3(_ view: SidebarView, file: RecordedFileInfo)
    func sidebarViewDidChangeMixAudio(_ view: SidebarView, enabled: Bool)
}

// MARK: - SidebarView
/// 侧边栏视图 - 负责音频源选择和进程列表管理，集成Tab切换功能
class SidebarView: NSView, TabContainerViewDelegate, RecordedFilesViewDelegate {
    
    // MARK: - UI Components
    private let tabContainer = TabContainerView()
    private let audioRecorderTabView = NSView()
    private let recordedFilesTabView = NSView()
    
    // 音频录制Tab的组件
    private let targetHeader = NSTextField()
    private let targetHintLabel = NSTextField()
    private let appsHeader = NSTextField()
    private let systemTargetRow = IndustrialAudioTargetRowView(
        title: "全部系统声音",
        subtitle: "CAPTURE FULL MAC OUTPUT",
        systemSymbolName: "speaker.wave.3.fill"
    )
    private let refreshButton = IndustrialButtonView(title: "刷新", icon: "arrow.clockwise")
    private let appsScroll = NSScrollView()
    private let appsStack = NSStackView()
    private let microphonePanel = IndustrialMicrophonePanelView()
    
    // 已录制文件Tab的组件
    private let recordedFilesView = RecordedFilesView()
    
    // MARK: - Properties
    weak var delegate: SidebarViewDelegate?
    private var availableProcesses: [AudioProcessInfo] = []
    private var selectedPIDs: [pid_t] = []
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
        audioRecorderTabView.addSubview(targetHintLabel)
        audioRecorderTabView.addSubview(systemTargetRow)
        audioRecorderTabView.addSubview(appsHeader)
        audioRecorderTabView.addSubview(refreshButton)
        audioRecorderTabView.addSubview(appsScroll)
        audioRecorderTabView.addSubview(microphonePanel)
        
        // 创建Tab
        let audioRecorderTab = TabItem(
            id: "audioRecorder",
            title: "Audio Recorder",
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
            title: "Saved Files",
            icon: "folder",
            view: recordedFilesTabView
        )
        tabContainer.addTab(recordedFilesTab)
    }
    
    private func setupHeaders() {
        func styleHeader(_ textField: NSTextField, _ title: String) {
            textField.stringValue = title.uppercased() // Industrial Design: 大写标题
            textField.isBordered = false
            textField.isEditable = false
            textField.backgroundColor = .clear
            textField.font = IndustrialTypography.h2 // 14px Bold
            textField.textColor = IndustrialColors.onSurface // 亮灰
            textField.translatesAutoresizingMaskIntoConstraints = false
        }
        
        styleHeader(targetHeader, "录制目标")
        styleHeader(appsHeader, "选择应用声音")
        
        targetHintLabel.stringValue = "先选要录的声音；麦克风作为附加输入"
        targetHintLabel.isBordered = false
        targetHintLabel.isEditable = false
        targetHintLabel.backgroundColor = .clear
        targetHintLabel.font = IndustrialTypography.small
        targetHintLabel.textColor = IndustrialColors.textTertiary
        targetHintLabel.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupTargetControls() {
        systemTargetRow.translatesAutoresizingMaskIntoConstraints = false
        systemTargetRow.isSelectedTarget = true
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
        // Industrial: 完全自绘进程列表，不再使用 NSTableView
        appsStack.orientation = .vertical
        appsStack.spacing = IndustrialSpacing.sm
        appsStack.alignment = .leading
        appsStack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        appsStack.translatesAutoresizingMaskIntoConstraints = false
        
        appsScroll.documentView = appsStack
        appsScroll.drawsBackground = false
        appsScroll.hasVerticalScroller = true
        appsScroll.hasHorizontalScroller = false
        appsScroll.autohidesScrollers = true
        appsScroll.translatesAutoresizingMaskIntoConstraints = false
        // P1-2 附带修复: 不在此处 addSubview，由 setupAudioRecorderTab 统一挂载到 audioRecorderTabView
        
        NSLayoutConstraint.activate([
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
        
        // 音频录制Tab内部的约束
        NSLayoutConstraint.activate([
            targetHeader.topAnchor.constraint(equalTo: audioRecorderTabView.topAnchor, constant: 16),
            targetHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            targetHeader.trailingAnchor.constraint(lessThanOrEqualTo: audioRecorderTabView.trailingAnchor, constant: -16),
            
            targetHintLabel.topAnchor.constraint(equalTo: targetHeader.bottomAnchor, constant: 4),
            targetHintLabel.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            targetHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: audioRecorderTabView.trailingAnchor, constant: -16),
            
            systemTargetRow.topAnchor.constraint(equalTo: targetHintLabel.bottomAnchor, constant: 10),
            systemTargetRow.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 12),
            systemTargetRow.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -12),
            systemTargetRow.heightAnchor.constraint(equalToConstant: 56),
            
            appsHeader.topAnchor.constraint(equalTo: systemTargetRow.bottomAnchor, constant: 18),
            appsHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            appsHeader.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -8),
            
            refreshButton.centerYAnchor.constraint(equalTo: appsHeader.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -16),
            refreshButton.widthAnchor.constraint(equalToConstant: 80),
            refreshButton.heightAnchor.constraint(equalToConstant: 24),
            
            microphonePanel.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 12),
            microphonePanel.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -12),
            microphonePanel.bottomAnchor.constraint(equalTo: audioRecorderTabView.bottomAnchor, constant: -12),
            microphonePanel.heightAnchor.constraint(equalToConstant: 92),
            
            appsScroll.topAnchor.constraint(equalTo: appsHeader.bottomAnchor, constant: 10),
            appsScroll.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 12),
            appsScroll.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -12),
            appsScroll.bottomAnchor.constraint(equalTo: microphonePanel.topAnchor, constant: -12)
        ])
    }
    
    // MARK: - Actions
    private func selectSystemAudioTarget() {
        logger.info("录制目标切换为：全部系统声音")
        selectedPIDs = []
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
    }
    
    // MARK: - RecordedFilesViewDelegate
    func recordedFilesViewDidSelectFile(_ view: RecordedFilesView, file: RecordedFileInfo) {
        delegate?.sidebarViewDidSelectFile(self, file: file)
    }
    
    func recordedFilesViewDidDoubleClickFile(_ view: RecordedFilesView, file: RecordedFileInfo) {
        // 双击文件，从Finder中打开
        delegate?.sidebarViewDidDoubleClickFile(self, file: file)
    }
    
    func recordedFilesViewDidRequestExportToMP3(_ view: RecordedFilesView, file: RecordedFileInfo) {
        // 导出为MP3格式
        delegate?.sidebarViewDidRequestExportToMP3(self, file: file)
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
        rebuildProcessRows()
    }
    
    func isSystemAudioSourceSelected() -> Bool {
        return selectedPIDs.isEmpty
    }
    
    func isMicrophoneSourceSelected() -> Bool {
        return microphonePanel.isMicrophoneIncluded
    }
    
    func getSelectedProcesses() -> [AudioProcessInfo] {
        return availableProcesses.filter { selectedPIDs.contains($0.pid) }
    }
    
    /// 获取指定进程的应用图标
    func getIconForProcess(_ process: AudioProcessInfo) -> NSImage {
        return getCachedIcon(for: process.path)
    }
    
    // MARK: - Process Rows
    private func rebuildProcessRows() {
        systemTargetRow.isSelectedTarget = selectedPIDs.isEmpty
        
        for view in appsStack.arrangedSubviews {
            appsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        if availableProcesses.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "NO AUDIO PROCESSES DETECTED")
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
            let row = IndustrialProcessRowView(process: process, icon: getCachedIcon(for: process.path))
            row.isSelectedRow = selectedPIDs.contains(process.pid)
            row.onClick = { [weak self] in
                guard let self = self else { return }
                self.selectedPIDs = [process.pid]
                self.systemTargetRow.isSelectedTarget = false
                self.rebuildProcessRows()
                self.delegate?.sidebarViewDidSelectProcesses(self, pids: [process.pid])
                self.delegate?.sidebarViewDidChangeSourceSelection(self)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            appsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: appsStack.widthAnchor, constant: -8).isActive = true
            row.heightAnchor.constraint(equalToConstant: 52).isActive = true
        }
    }
    
    // MARK: - Private Methods
    private func preloadIcons(for processes: [AudioProcessInfo]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for process in processes {
                let key = process.path as NSString
                if !process.path.isEmpty && self.iconCache.object(forKey: key) == nil {
                    // 使用改进的 loadAppIcon 方法，支持 Helper 进程图标映射
                    let icon = self.loadAppIcon(for: process.path)
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
    
    private func getCachedIcon(for path: String) -> NSImage {
        let key = path as NSString
        if let cachedIcon = iconCache.object(forKey: key) {
            return cachedIcon
        }
        
        // 如果缓存中没有，立即加载并缓存
        let icon = loadAppIcon(for: path)
        icon.size = NSSize(width: 24, height: 24)
        iconCache.setObject(icon, forKey: key)
        
        return icon
    }
    
    /// 加载应用图标，支持多种方式
    private func loadAppIcon(for path: String) -> NSImage {
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
        
        // 方法3: 尝试从 Bundle ID 获取图标
        if let bundleID = getBundleID(from: path) {
            let icon = NSWorkspace.shared.icon(forFile: bundleID)
            if icon.size.width > 0 && icon.size.height > 0 {
                logger.debug("✅ 从 Bundle ID 加载图标成功: \(bundleID)")
                return icon
            }
        }
        
        // 方法4: 使用默认图标
        logger.debug("⚠️ 所有方法都失败，使用默认图标: \(path)")
        return NSImage(named: NSImage.applicationIconName) ?? NSImage(named: NSImage.multipleDocumentsName)!
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
    
    /// 从路径获取 Bundle ID（简化版本）
    private func getBundleID(from path: String) -> String? {
        // 这里可以扩展更复杂的 Bundle ID 获取逻辑
        // 目前返回 nil，让系统使用默认图标
        return nil
    }
    
    /// 获取 Helper 进程对应的主应用路径
    private func getMainAppPathForHelper(path: String) -> String? {
        let lowerPath = path.lowercased()
        
        // Chrome 主应用或 Helper -> Chrome 主应用
        if lowerPath.contains("google chrome") {
            let chromeAppPath = "/Applications/Google Chrome.app"
            if FileManager.default.fileExists(atPath: chromeAppPath) {
                return chromeAppPath
            }
        }
        
        // Edge Helper -> Edge 主应用
        if lowerPath.contains("microsoft edge helper") || lowerPath.contains("microsoft edge framework") {
            let edgeAppPath = "/Applications/Microsoft Edge.app"
            if FileManager.default.fileExists(atPath: edgeAppPath) {
                return edgeAppPath
            }
        }
        
        // Firefox Helper -> Firefox 主应用
        if lowerPath.contains("firefox") && lowerPath.contains("helper") {
            let firefoxAppPath = "/Applications/Firefox.app"
            if FileManager.default.fileExists(atPath: firefoxAppPath) {
                return firefoxAppPath
            }
        }
        
        // Safari Helper -> Safari 主应用
        if lowerPath.contains("safari") && lowerPath.contains("helper") {
            let safariAppPath = "/System/Applications/Safari.app"
            if FileManager.default.fileExists(atPath: safariAppPath) {
                return safariAppPath
            }
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
        titleLabel.stringValue = title.uppercased()
        metaLabel.stringValue = subtitle.uppercased()
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
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
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
    
    private let titleLabel = NSTextField(labelWithString: "ADD MICROPHONE")
    private let microphoneToggle = IndustrialToggleView(title: "同时录入麦克风")
    private let hintLabel = NSTextField(labelWithString: "MIX INTO SELECTED TARGET")
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
        hintLabel.stringValue = enabled ? "MIC WILL BE MIXED IN" : "MIX INTO SELECTED TARGET"
    }
}

// MARK: - IndustrialProcessRowView
/// 自绘进程行 — 去除 NSTableView 系统白底/蓝色选中态
final class IndustrialProcessRowView: NSView {
    var onClick: (() -> Void)?
    var isSelectedRow: Bool = false { didSet { updateAppearance() } }
    
    private let indicatorLayer = CALayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
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
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        
        indicatorLayer.backgroundColor = IndustrialColors.primaryContainer.cgColor
        indicatorLayer.isHidden = true
        layer?.addSublayer(indicatorLayer)
        
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
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
        
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }
    
    private func configure(process: AudioProcessInfo, icon: NSImage) {
        iconView.image = icon
        titleLabel.stringValue = process.name.uppercased()
        metaLabel.stringValue = "PID \(process.pid)   PROCESS TAP"
    }
    
    override func layout() {
        super.layout()
        indicatorLayer.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
    }
    
    private func updateAppearance() {
        layer?.backgroundColor = (isSelectedRow ? IndustrialColors.surfaceContainerHighest : (isHovering ? IndustrialColors.surfaceContainerHigh : IndustrialColors.surfaceContainerLow)).cgColor
        layer?.borderColor = (isSelectedRow || isHovering ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant).cgColor
        indicatorLayer.isHidden = !isSelectedRow
        titleLabel.textColor = isSelectedRow ? IndustrialColors.primary : IndustrialColors.onSurface
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
