import Cocoa
import ServiceManagement

/// 设置窗口控制器 — macOS 标准偏好设置窗口（工业风格）
class SettingsWindowController: NSWindowController {
    
    // MARK: - Singleton
    static let shared = SettingsWindowController()
    
    // MARK: - Settings Keys
    struct Keys {
        static let recordingFormat = "recordingFormat"
        static let sampleRate = "sampleRate"
        static let recordingsDirectory = "recordingsDirectory"
        static let launchAtLogin = "launchAtLogin"
    }
    
    // MARK: - UI Components
    private let formatPopup = NSPopUpButton()
    private let sampleRatePopup = NSPopUpButton()
    private let directoryLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
    
    // MARK: - Initialization
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.appearance = NSAppearance(named: .darkAqua)
        
        super.init(window: window)
        
        setupUI()
        loadSettings()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = IndustrialColors.surface.cgColor
        
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
        ])
        
        // 标题
        let titleLabel = makeLabel("录制设置", size: 16, bold: true)
        stackView.addArrangedSubview(titleLabel)
        
        // 录制格式
        let formatRow = makeRow("录制格式:", formatPopup)
        formatPopup.addItems(withTitles: ["M4A (AAC)", "WAV (PCM)"])
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        stackView.addArrangedSubview(formatRow)
        
        // 采样率
        let sampleRateRow = makeRow("采样率:", sampleRatePopup)
        sampleRatePopup.addItems(withTitles: ["44100 Hz", "48000 Hz"])
        sampleRatePopup.target = self
        sampleRatePopup.action = #selector(sampleRateChanged)
        stackView.addArrangedSubview(sampleRateRow)
        
        // 存储位置
        directoryLabel.textColor = NSColor.secondaryLabelColor
        directoryLabel.font = NSFont.systemFont(ofSize: 11)
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        directoryLabel.maximumNumberOfLines = 1
        directoryLabel.preferredMaxLayoutWidth = 280
        
        let browseButton = NSButton(title: "更改…", target: self, action: #selector(browseDirectory))
        browseButton.bezelStyle = .rounded
        
        let dirInner = NSStackView(views: [directoryLabel, browseButton])
        dirInner.spacing = 8
        let dirRow = makeRow("存储位置:", dirInner)
        stackView.addArrangedSubview(dirRow)
        
        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 432).isActive = true
        stackView.addArrangedSubview(separator)
        
        // 应用设置标题
        let appTitleLabel = makeLabel("应用设置", size: 16, bold: true)
        stackView.addArrangedSubview(appTitleLabel)
        
        // 开机启动
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)
        configureControl(launchAtLoginCheckbox)
        stackView.addArrangedSubview(launchAtLoginCheckbox)
    }
    
    // MARK: - Factory Methods
    private func makeLabel(_ text: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.textColor = NSColor.labelColor
        return label
    }
    
    private func makeRow(_ title: String, _ control: NSView) -> NSStackView {
        let label = makeLabel(title)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 80).isActive = true
        
        configureControl(control)
        
        let row = NSStackView(views: [label, control])
        row.spacing = 12
        row.alignment = .centerY
        return row
    }
    
    private func configureControl(_ control: NSView) {
        if let popup = control as? NSPopUpButton {
            popup.font = NSFont.systemFont(ofSize: 13)
        }
    }
    
    // MARK: - Settings Load/Save
    private func loadSettings() {
        let defaults = UserDefaults.standard
        
        // 录制格式
        let format = defaults.string(forKey: Keys.recordingFormat) ?? "m4a"
        formatPopup.selectItem(at: format == "wav" ? 1 : 0)
        
        // 采样率
        let rate = defaults.integer(forKey: Keys.sampleRate)
        sampleRatePopup.selectItem(at: rate == 44100 ? 0 : 1)
        
        // 存储位置
        let dir = defaults.string(forKey: Keys.recordingsDirectory)
            ?? FileManagerUtils.shared.getRecordingsDirectory().path
        directoryLabel.stringValue = dir
        
        // 开机启动
        launchAtLoginCheckbox.state = defaults.bool(forKey: Keys.launchAtLogin) ? .on : .off
    }
    
    // MARK: - Actions
    @objc private func formatChanged() {
        let format = formatPopup.indexOfSelectedItem == 0 ? "m4a" : "wav"
        UserDefaults.standard.set(format, forKey: Keys.recordingFormat)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
    
    @objc private func sampleRateChanged() {
        let rate = sampleRatePopup.indexOfSelectedItem == 0 ? 44100 : 48000
        UserDefaults.standard.set(rate, forKey: Keys.sampleRate)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
    
    @objc private func browseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择"
        panel.message = "选择录音文件保存位置"
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                UserDefaults.standard.set(url.path, forKey: Keys.recordingsDirectory)
                self?.directoryLabel.stringValue = url.path
                NotificationCenter.default.post(name: .settingsChanged, object: nil)
            }
        }
    }
    
    @objc private func launchAtLoginChanged() {
        let enabled = launchAtLoginCheckbox.state == .on
        UserDefaults.standard.set(enabled, forKey: Keys.launchAtLogin)
        
        // macOS 13+ 使用 SMAppService
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger.shared.error("设置开机启动失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Show
    func showSettings() {
        loadSettings()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let settingsChanged = Notification.Name("SettingsChanged")
}
