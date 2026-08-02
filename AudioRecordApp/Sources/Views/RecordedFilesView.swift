import Cocoa
import Foundation

// BUG-FIX-2: 格式 badge 文字垂直居中
private class FormatBadgeCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        let minimumHeight = cellSize(forBounds: rect).height
        titleRect.origin.y += (titleRect.height - minimumHeight) / 2.0
        titleRect.size.height = minimumHeight
        return titleRect
    }
    
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
}

// MARK: - Delegate Protocol
protocol RecordedFilesViewDelegate: AnyObject {
    func recordedFilesViewDidSelectFile(_ view: RecordedFilesView, file: RecordedFileInfo)
    func recordedFilesViewDidDoubleClickFile(_ view: RecordedFilesView, file: RecordedFileInfo)
    func recordedFilesViewDidRenameFile(_ view: RecordedFilesView, file: RecordedFileInfo, newName: String)
    func recordedFilesViewDidRequestEditFile(_ view: RecordedFilesView, file: RecordedFileInfo)
}

// MARK: - RecordedFilesView (V2.0: .arlock)
/// 已录制文件列表视图 — 读取 .arlock 元数据展示
class RecordedFilesView: NSView {

    // MARK: - UI Components
    private let scrollView = NSScrollView()
    private let fileStack = NSStackView()

    // MARK: - Properties
    weak var delegate: RecordedFilesViewDelegate?
    private var recordedFiles: [RecordedFileInfo] = []
    private var selectedFile: RecordedFileInfo?
    private let logger = Logger.shared

    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        loadRecordedFiles()
        rebuildFileRows()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        loadRecordedFiles()
        rebuildFileRows()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surfaceContainer.cgColor
        setupScrollStack()
        setupConstraints()
    }

    private func setupScrollStack() {
        fileStack.orientation = .vertical
        fileStack.spacing = IndustrialSpacing.sm
        fileStack.alignment = .leading
        fileStack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        fileStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = fileStack
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            fileStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: IndustrialSpacing.sm),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: IndustrialSpacing.sm),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -IndustrialSpacing.sm),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -IndustrialSpacing.sm)
        ])
    }

    // MARK: - Public Methods

    func refreshFiles() {
        loadRecordedFiles()
        rebuildFileRows()
    }

    func addRecordedFile(_ file: RecordedFileInfo) {
        recordedFiles.insert(file, at: 0)
        selectedFile = file
        rebuildFileRows()
    }

    func loadRecordedFiles(_ files: [RecordedFileInfo]) {
        recordedFiles = files
        logger.info("已加载 \(files.count) 个录音文件到列表")
        rebuildFileRows()
    }

    // MARK: - Private Methods

    private func rebuildFileRows() {
        for view in fileStack.arrangedSubviews {
            fileStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if recordedFiles.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "暂无录制文件")
            emptyLabel.font = IndustrialTypography.label
            emptyLabel.textColor = IndustrialColors.textTertiary
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            fileStack.addArrangedSubview(emptyLabel)
            emptyLabel.widthAnchor.constraint(equalTo: fileStack.widthAnchor, constant: -8).isActive = true
            emptyLabel.heightAnchor.constraint(equalToConstant: 48).isActive = true
            return
        }

        for file in recordedFiles {
            let row = IndustrialRecordedFileRowView(file: file)
            row.isSelectedRow = (selectedFile?.url == file.url)
            row.onSelect = { [weak self] in
                guard let self = self else { return }
                self.selectedFile = file
                self.rebuildFileRows()
                self.delegate?.recordedFilesViewDidSelectFile(self, file: file)
            }
            row.onDoubleClick = { [weak self] in
                guard let self = self else { return }
                self.delegate?.recordedFilesViewDidDoubleClickFile(self, file: file)
            }
            row.onEdit = { [weak self] in
                guard let self = self else { return }
                self.delegate?.recordedFilesViewDidRequestEditFile(self, file: file)
            }
            let contextMenu = NSMenu()
            let renameItem = NSMenuItem(title: "重命名…", action: #selector(handleRenameFile(_:)), keyEquivalent: "")
            renameItem.target = self
            renameItem.representedObject = file
            contextMenu.addItem(renameItem)
            row.menu = contextMenu
            row.translatesAutoresizingMaskIntoConstraints = false
            fileStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: fileStack.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 64).isActive = true
        }
    }

    // MARK: - V2.0: 读取 .arlock 文件列表
    
    private func loadRecordedFiles() {
        let arlockFiles = FileManagerUtils.shared.getRecordingFiles()
        
        var files: [RecordedFileInfo] = []
        
        for url in arlockFiles {
            // 尝试读取 .arlock 元数据
            if let metadata = try? AudioFileEncryptor.shared.decryptMetadataOnly(from: url),
               let fileSize = FileManagerUtils.shared.getFileSize(at: url) {
                let displayName = metadata.title.isEmpty ? url.deletingPathExtension().lastPathComponent : metadata.title
                let fileInfo = RecordedFileInfo(
                    url: url,
                    name: displayName,
                    date: ISO8601DateFormatter().date(from: metadata.createdAt) ?? Date(),
                    duration: metadata.durationSec,
                    size: fileSize
                )
                files.append(fileInfo)
            } else {
                // 解密失败（文件损坏/非本设备/旧格式），跳过并记录
                logger.warning("跳过无法读取的 .arlock: \(url.lastPathComponent)")
            }
        }
        
        // 按日期降序
        files.sort { $0.date > $1.date }
        recordedFiles = files
    }

    @objc private func handleRenameFile(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RecordedFileInfo else { return }
        let alert = NSAlert()
        alert.messageText = "重命名录音"
        alert.informativeText = "为这条录音起个易记的名字。文件名（不含扩展名）："
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        // V2.1: 默认值用显示名（已是「进程名_日期」格式），不再是 UUID
        input.stringValue = file.name
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        // 全选便于直接覆盖
        DispatchQueue.main.async {
            input.currentEditor()?.selectedRange = NSRange(location: 0, length: input.stringValue.count)
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        guard newName != file.name else { return }  // 没改就不通知

        // V2.1: 真正持久化到 .arlock 元数据（delegate → MainViewController → AudioFileEncryptor.updateTitle）
        delegate?.recordedFilesViewDidRenameFile(self, file: file, newName: newName)
    }
}

// MARK: - IndustrialRecordedFileRowView
final class IndustrialRecordedFileRowView: NSView {
    var onSelect: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onEdit: (() -> Void)?
    var isSelectedRow: Bool = false { didSet { updateAppearance() } }

    private let indicatorLayer = CALayer()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let formatBadge = NSTextField(labelWithString: "")
    private let editButton = NSButton()
    private var isHovering = false

    init(file: RecordedFileInfo) {
        super.init(frame: .zero)
        setupView()
        configure(with: file)
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

        iconView.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Audio File")
        iconView.contentTintColor = IndustrialColors.primaryContainer
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        nameLabel.font = IndustrialTypography.body
        nameLabel.textColor = IndustrialColors.onSurface
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        metaLabel.font = IndustrialTypography.monoDB
        metaLabel.textColor = IndustrialColors.onSurfaceVariant
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metaLabel)

        formatBadge.font = IndustrialTypography.label
        formatBadge.textColor = IndustrialColors.primary
        formatBadge.alignment = .center
        let badgeCell = FormatBadgeCell(textCell: "")
        badgeCell.isEditable = false
        badgeCell.isBordered = false
        badgeCell.drawsBackground = false
        badgeCell.alignment = .center
        badgeCell.font = IndustrialTypography.label
        badgeCell.textColor = IndustrialColors.primary
        formatBadge.cell = badgeCell
        formatBadge.wantsLayer = true
        formatBadge.layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        formatBadge.layer?.cornerRadius = IndustrialCornerRadius.xs
        formatBadge.layer?.borderWidth = 1
        formatBadge.layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        formatBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formatBadge)

        editButton.bezelStyle = .inline
        editButton.isBordered = false
        editButton.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: "编辑")
        editButton.contentTintColor = IndustrialColors.primary
        editButton.target = self
        editButton.action = #selector(editButtonClicked)
        editButton.isHidden = true
        editButton.wantsLayer = true
        editButton.layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        editButton.layer?.cornerRadius = IndustrialCornerRadius.xs
        editButton.layer?.borderWidth = 1
        editButton.layer?.borderColor = IndustrialColors.primaryContainer.cgColor
        editButton.toolTip = "编辑此录音"
        editButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            formatBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            formatBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            formatBadge.widthAnchor.constraint(equalToConstant: 42),
            formatBadge.heightAnchor.constraint(equalToConstant: 22),

            editButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            editButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: 28),
            editButton.heightAnchor.constraint(equalToConstant: 22),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            nameLabel.trailingAnchor.constraint(equalTo: formatBadge.leadingAnchor, constant: -10),

            metaLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),
            metaLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor)
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }

    private func configure(with file: RecordedFileInfo) {
        let displayName = file.name
        let prettyName = displayName
            .replacingOccurrences(of: "系统音频_", with: "")
            .replacingOccurrences(of: "_", with: " ")
        nameLabel.stringValue = prettyName.isEmpty ? displayName : prettyName
        metaLabel.stringValue = "\(file.formattedDuration)  ·  \(file.formattedSize)"
        formatBadge.isHidden = true  // 不暴露文件格式
    }

    override func layout() {
        super.layout()
        indicatorLayer.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isSelectedRow ? IndustrialColors.surfaceContainerHighest : (isHovering ? IndustrialColors.surfaceContainerHigh : IndustrialColors.surfaceContainerLow)).cgColor
        layer?.borderColor = (isSelectedRow || isHovering ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant).cgColor
        indicatorLayer.isHidden = !isSelectedRow
        nameLabel.textColor = isSelectedRow ? IndustrialColors.primary : IndustrialColors.onSurface
        formatBadge.layer?.borderColor = (isSelectedRow ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant).cgColor
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
        let location = convert(event.locationInWindow, from: nil)
        if !editButton.isHidden && editButton.frame.contains(location) { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DMakeTranslation(0, -1, 0)
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        layer?.transform = CATransform3DIdentity
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        let location = convert(event.locationInWindow, from: nil)
        if !editButton.isHidden && editButton.frame.contains(location) { return }
        onSelect?()
        if event.clickCount >= 2 {
            onDoubleClick?()
        }
    }

    @objc private func editButtonClicked() {
        onEdit?()
    }
}
