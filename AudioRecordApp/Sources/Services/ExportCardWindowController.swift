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
    private let exportButton = NSButton(title: "导出".localized, target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消".localized, target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    
    private let logger = Logger.shared
    private let exportService = ExportService.shared

    // 沙盒导出目录授权（powerbox 授权随 App 重启失效，用安全作用域书签持久化）
    private let exportDirectoryBookmarkKey = "exportDirectoryBookmark"
    private var accessedExportURL: URL?
    
    // MARK: - Init
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "导出".localized
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
        durationLabel.stringValue = "时长: %@".localized(String(format: "%d:%02d", minutes, seconds))
        
        // 文件大小
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        sizeFormatter.countStyle = .file
        sizeLabel.stringValue = "源文件大小: %@".localized(sizeFormatter.string(fromByteCount: fileSize))
        
        // 默认位置：真实用户桌面。
        // 注意：沙盒内 FileManager.desktopDirectory 返回容器内 Desktop，必须用 NSHomeDirectory 拼接真实路径。
        locationLabel.stringValue = NSHomeDirectory() + "/Desktop"
        
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
        let titleLabel = makeLabel("导出录音".localized, size: 16, bold: true)
        titleLabel.frame = NSRect(x: 24, y: 312, width: 200, height: 24)
        contentView.addSubview(titleLabel)
        
        // 文件名
        let nameLabel = makeLabel("文件名:".localized, size: 12)
        nameLabel.frame = NSRect(x: 24, y: 270, width: 80, height: 20)
        nameField.frame = NSRect(x: 110, y: 268, width: 340, height: 24)
        nameField.font = NSFont.systemFont(ofSize: 13)
        nameField.bezelStyle = .squareBezel
        contentView.addSubview(nameLabel)
        contentView.addSubview(nameField)
        
        // 格式
        let formatLabel = makeLabel("格式:".localized, size: 12)
        formatLabel.frame = NSRect(x: 24, y: 230, width: 80, height: 20)
        formatPopup.frame = NSRect(x: 110, y: 226, width: 340, height: 26)
        formatPopup.font = NSFont.systemFont(ofSize: 13)
        formatPopup.addItems(withTitles: AudioExportFormat.allCases.map { $0.displayName })
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        contentView.addSubview(formatLabel)
        contentView.addSubview(formatPopup)
        
        // 导出位置
        let locTitle = makeLabel("导出至:".localized, size: 12)
        locTitle.frame = NSRect(x: 24, y: 190, width: 80, height: 20)
        locationLabel.frame = NSRect(x: 110, y: 188, width: 260, height: 24)
        locationLabel.font = NSFont.systemFont(ofSize: 12)
        locationLabel.textColor = NSColor.secondaryLabelColor
        locationLabel.isEditable = false
        locationLabel.isSelectable = false
        locationLabel.isBezeled = false
        locationLabel.drawsBackground = false
        locationButton.title = "选择…".localized
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
        
        // FLAC/OGG 仅在 ffmpeg 不可用时显示警告
        if format == .flac || format == .ogg {
            let hasFFmpeg = ExportService.hasFFmpeg()
            if !hasFFmpeg {
                statusLabel.stringValue = "⚠️ %@ 需要 ffmpeg (brew install ffmpeg)".localized(format.displayName)
                statusLabel.textColor = NSColor.systemOrange
            } else {
                statusLabel.stringValue = ""
            }
        } else {
            statusLabel.stringValue = ""
        }
    }
    
    @objc private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.title = "选择导出位置".localized
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: locationLabel.stringValue)
        if panel.runModal() == .OK, let url = panel.url {
            locationLabel.stringValue = url.path
            // 沙盒：面板选择即授权，立即开始访问并持久化安全作用域书签（重启后仍有效）
            stopAccessingExportDirectory()
            if url.startAccessingSecurityScopedResource() {
                accessedExportURL = url
            }
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: exportDirectoryBookmarkKey)
            } catch {
                logger.warning("保存导出目录书签失败: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func cancelClicked() {
        window?.close()
    }

    // MARK: - 沙盒目录授权

    /// 结束当前已授权目录的访问
    private func stopAccessingExportDirectory() {
        if let url = accessedExportURL {
            url.stopAccessingSecurityScopedResource()
            accessedExportURL = nil
        }
    }

    /// 恢复已保存书签的目录访问
    private func resolveSavedBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: exportDirectoryBookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    /// 确保导出目录已获得沙盒写权限（powerbox 授权随重启失效，书签可恢复）
    private func ensureExportDirectoryAccess(for dir: URL) -> Bool {
        // 本次会话已授权该目录
        if let accessed = accessedExportURL, accessed.path == dir.path { return true }
        // 尝试从书签恢复
        if let resolved = resolveSavedBookmark(), resolved.path == dir.path {
            accessedExportURL = resolved
            return true
        }
        return false
    }
    
    @objc private func exportClicked() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            statusLabel.stringValue = "❌ 文件名不能为空".localized
            return
        }
        
        let formatIdx = formatPopup.indexOfSelectedItem
        guard formatIdx >= 0 && formatIdx < AudioExportFormat.allCases.count else { return }
        let format = AudioExportFormat.allCases[formatIdx]
        
        let outputURL = URL(fileURLWithPath: locationLabel.stringValue)
            .appendingPathComponent(name)
            .appendingPathExtension(format.fileExtension)

        // 沙盒：确保导出目录已授权（powerbox 授权随重启失效，书签可恢复）
        let outputDir = URL(fileURLWithPath: locationLabel.stringValue)
        guard ensureExportDirectoryAccess(for: outputDir) else {
            statusLabel.stringValue = "⚠️ 请先点击「选择…」授权导出目录".localized
            statusLabel.textColor = NSColor.systemOrange
            return
        }

        // 检查文件已存在
        if FileManager.default.fileExists(atPath: outputURL.path) {
            let alert = NSAlert()
            alert.messageText = "文件已存在".localized
            alert.informativeText = "%@ 已存在，要覆盖吗？".localized(outputURL.lastPathComponent)
            alert.addButton(withTitle: "覆盖".localized)
            alert.addButton(withTitle: "取消".localized)
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        
        // 开始导出
        startExport(format: format, outputURL: outputURL)
    }
    
    private func startExport(format: AudioExportFormat, outputURL: URL) {
        UXEventLog.shared.action("export_start", detail: ["format": format.fileExtension])
        UXEventLog.shared.module("Export", "start", detail: ["format": format.fileExtension])
        // 禁用按钮
        exportButton.isEnabled = false
        cancelButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "正在解密并转码…".localized
        statusLabel.textColor = NSColor.secondaryLabelColor
        
        exportService.exportToFile(arlockURL: fileURL, outputURL: outputURL, targetFormat: format) { [weak self] success, outURL, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.progressIndicator.stopAnimation(nil)
                self.progressIndicator.isHidden = true
                self.exportButton.isEnabled = true
                self.cancelButton.isEnabled = true
                
                if success, let url = outURL {
                    UXEventLog.shared.module("Export", "done", ok: true, detail: ["format": format.fileExtension])
                    UXEventLog.shared.artifact("export_file_created", path: url.path, detail: ["format": format.fileExtension])
                    self.statusLabel.stringValue = "✅ 导出成功：%@".localized(url.lastPathComponent)
                    self.statusLabel.textColor = NSColor.systemGreen
                    
                    // 在 Finder 中显示
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    
                    // 2 秒后自动关闭
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.window?.close()
                    }
                } else {
                    if let error {
                        UXEventLog.shared.module("Export", "done", ok: false, detail: ["format": format.fileExtension, "error": error.localizedDescription])
                    } else {
                        UXEventLog.shared.action("export_cancelled", detail: ["format": format.fileExtension])
                    }
                    let errMsg = error?.localizedDescription ?? "已取消".localized
                    self.statusLabel.stringValue = error == nil ? "已取消导出".localized : "❌ %@".localized(errMsg)
                    self.statusLabel.textColor = NSColor.systemRed
                }
            }
        }
    }
}
