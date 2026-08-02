import Cocoa
import AVFoundation
import UniformTypeIdentifiers

/// 导出卡片窗口控制器 (V2.0)
/// 仿照剪映的导出对话框，但精简为纯音频版本
class ExportCardWindowController: NSWindowController {
    
    // MARK: - Singleton
    static let shared = ExportCardWindowController()
    
    // MARK: - Input
    private var fileURL: URL!
    private var fileName: String = ""
    private var duration: TimeInterval = 0
    private var fileSize: Int64 = 0
    
    // MARK: - UI
    private let nameField = NSTextField()
    private let formatPopup = NSPopUpButton()
    private let durationLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let locationLabel = NSTextField(labelWithString: "")
    private let locationButton = NSButton()
    private let exportButton = NSButton(title: "导出", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    
    private let logger = Logger.shared
    private let exportService = ExportService.shared
    
    // MARK: - Init
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "导出"
        window.isReleasedWhenClosed = false
        window.center()
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Show
    
    /// 显示导出卡片
    /// - Parameters:
    ///   - fileURL: 源 .arlock 文件 URL
    ///   - displayName: 文件显示名（从 metadata.title）
    ///   - duration: 时长
    ///   - fileSize: 加密文件大小
    func show(fileURL: URL, displayName: String, duration: TimeInterval, fileSize: Int64) {
        self.fileURL = fileURL
        self.fileName = displayName
        self.duration = duration
        self.fileSize = fileSize
        
        nameField.stringValue = displayName
        
        // 格式化时长
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        durationLabel.stringValue = "时长: \(String(format: "%d:%02d", minutes, seconds))"
        
        // 文件大小
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        sizeFormatter.countStyle = .file
        sizeLabel.stringValue = "源文件大小: \(sizeFormatter.string(fromByteCount: fileSize))"
        
        // 默认位置：桌面
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        locationLabel.stringValue = desktop?.path ?? "~/Desktop"
        
        // 默认格式：M4A
        formatPopup.selectItem(at: 0)
        
        statusLabel.stringValue = ""
        progressIndicator.isHidden = true
        
        exportButton.isEnabled = true
        cancelButton.isEnabled = true
        
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1).cgColor
        
        // 标题
        let titleLabel = makeLabel("导出录音", size: 16, bold: true)
        titleLabel.frame = NSRect(x: 24, y: 312, width: 200, height: 24)
        contentView.addSubview(titleLabel)
        
        // 文件名
        let nameLabel = makeLabel("文件名:", size: 12)
        nameLabel.frame = NSRect(x: 24, y: 270, width: 80, height: 20)
        nameField.frame = NSRect(x: 110, y: 268, width: 340, height: 24)
        nameField.font = NSFont.systemFont(ofSize: 13)
        nameField.bezelStyle = .squareBezel
        contentView.addSubview(nameLabel)
        contentView.addSubview(nameField)
        
        // 格式
        let formatLabel = makeLabel("格式:", size: 12)
        formatLabel.frame = NSRect(x: 24, y: 230, width: 80, height: 20)
        formatPopup.frame = NSRect(x: 110, y: 226, width: 340, height: 26)
        formatPopup.font = NSFont.systemFont(ofSize: 13)
        formatPopup.addItems(withTitles: AudioExportFormat.allCases.map { $0.displayName })
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        contentView.addSubview(formatLabel)
        contentView.addSubview(formatPopup)
        
        // 导出位置
        let locTitle = makeLabel("导出至:", size: 12)
        locTitle.frame = NSRect(x: 24, y: 190, width: 80, height: 20)
        locationLabel.frame = NSRect(x: 110, y: 188, width: 260, height: 24)
        locationLabel.font = NSFont.systemFont(ofSize: 12)
        locationLabel.textColor = NSColor.secondaryLabelColor
        locationLabel.isEditable = false
        locationLabel.isSelectable = false
        locationLabel.isBezeled = false
        locationLabel.drawsBackground = false
        locationButton.title = "选择…"
        locationButton.bezelStyle = .rounded
        locationButton.target = self
        locationButton.action = #selector(chooseLocation)
        locationButton.frame = NSRect(x: 376, y: 186, width: 76, height: 28)
        contentView.addSubview(locTitle)
        contentView.addSubview(locationLabel)
        contentView.addSubview(locationButton)
        
        // 分隔线
        let separator = NSBox(frame: NSRect(x: 24, y: 160, width: 432, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)
        
        // 信息
        durationLabel.frame = NSRect(x: 24, y: 130, width: 432, height: 18)
        durationLabel.font = NSFont.systemFont(ofSize: 12)
        durationLabel.textColor = NSColor.secondaryLabelColor
        contentView.addSubview(durationLabel)
        
        sizeLabel.frame = NSRect(x: 24, y: 110, width: 432, height: 18)
        sizeLabel.font = NSFont.systemFont(ofSize: 12)
        sizeLabel.textColor = NSColor.secondaryLabelColor
        contentView.addSubview(sizeLabel)
        
        // 状态
        statusLabel.frame = NSRect(x: 24, y: 80, width: 432, height: 18)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = NSColor.systemOrange
        contentView.addSubview(statusLabel)
        
        // 进度条
        progressIndicator.frame = NSRect(x: 24, y: 60, width: 432, height: 4)
        progressIndicator.isIndeterminate = true
        progressIndicator.isHidden = true
        contentView.addSubview(progressIndicator)
        
        // 按钮
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.frame = NSRect(x: 300, y: 20, width: 76, height: 32)
        contentView.addSubview(cancelButton)
        
        exportButton.bezelStyle = .rounded
        exportButton.target = self
        exportButton.action = #selector(exportClicked)
        exportButton.frame = NSRect(x: 384, y: 20, width: 72, height: 32)
        contentView.addSubview(exportButton)
    }
    
    private func makeLabel(_ text: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.textColor = NSColor.labelColor
        return label
    }
    
    // MARK: - Actions
    
    @objc private func formatChanged() {
        let idx = formatPopup.indexOfSelectedItem
        guard idx >= 0 && idx < AudioExportFormat.allCases.count else { return }
        let format = AudioExportFormat.allCases[idx]
        
        if idx >= 2 {
            statusLabel.stringValue = "⚠️ \(format.displayName) 需要安装 ffmpeg"
            statusLabel.textColor = NSColor.systemOrange
        } else {
            statusLabel.stringValue = ""
        }
    }
    
    @objc private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.title = "选择导出位置"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: locationLabel.stringValue)
        if panel.runModal() == .OK, let url = panel.url {
            locationLabel.stringValue = url.path
        }
    }
    
    @objc private func cancelClicked() {
        window?.close()
    }
    
    @objc private func exportClicked() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            statusLabel.stringValue = "❌ 文件名不能为空"
            return
        }
        
        let formatIdx = formatPopup.indexOfSelectedItem
        guard formatIdx >= 0 && formatIdx < AudioExportFormat.allCases.count else { return }
        let format = AudioExportFormat.allCases[formatIdx]
        
        let outputURL = URL(fileURLWithPath: locationLabel.stringValue)
            .appendingPathComponent(name)
            .appendingPathExtension(format.fileExtension)
        
        // 检查文件已存在
        if FileManager.default.fileExists(atPath: outputURL.path) {
            let alert = NSAlert()
            alert.messageText = "文件已存在"
            alert.informativeText = "\(outputURL.lastPathComponent) 已存在，要覆盖吗？"
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        
        // 开始导出
        startExport(format: format, outputURL: outputURL)
    }
    
    private func startExport(format: AudioExportFormat, outputURL: URL) {
        // 禁用按钮
        exportButton.isEnabled = false
        cancelButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "正在解密并转码…"
        statusLabel.textColor = NSColor.secondaryLabelColor
        
        exportService.export(arlockURL: fileURL, targetFormat: format) { [weak self] success, outURL, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.progressIndicator.stopAnimation(nil)
                self.progressIndicator.isHidden = true
                self.exportButton.isEnabled = true
                self.cancelButton.isEnabled = true
                
                if success, let url = outURL {
                    self.statusLabel.stringValue = "✅ 导出成功：\(url.lastPathComponent)"
                    self.statusLabel.textColor = NSColor.systemGreen
                    
                    // 在 Finder 中显示
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    
                    // 2 秒后自动关闭
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.window?.close()
                    }
                } else {
                    let errMsg = error?.localizedDescription ?? "未知错误"
                    self.statusLabel.stringValue = "❌ \(errMsg)"
                    self.statusLabel.textColor = NSColor.systemRed
                }
            }
        }
    }
}
