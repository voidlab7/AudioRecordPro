import Cocoa
import Foundation
import AVFoundation

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

// RecordedFileInfo 已移动到 AudioRecordKit/Sources/API/Types.swift

// MARK: - Delegate Protocol
protocol RecordedFilesViewDelegate: AnyObject {
    func recordedFilesViewDidSelectFile(_ view: RecordedFilesView, file: RecordedFileInfo)
    func recordedFilesViewDidDoubleClickFile(_ view: RecordedFilesView, file: RecordedFileInfo)
    func recordedFilesViewDidRenameFile(_ view: RecordedFilesView, file: RecordedFileInfo, newName: String)
    func recordedFilesViewDidRequestEditFile(_ view: RecordedFilesView, file: RecordedFileInfo)
}

// MARK: - RecordedFilesView
/// 已录制文件列表视图 — 完全自绘，避免 NSTableView 系统白底/蓝色选中态
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
            // File list fills the entire view
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
            // 右键菜单（仅重命名，不暴露文件路径）
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

    private func loadRecordedFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsPath = documentsPath.appendingPathComponent("AudioRecordings")

        var files: [RecordedFileInfo] = []

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: recordingsPath, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])

            let audioExtensions: Set<String> = ["wav", "m4a", "mp3", "aac", "caf", "aiff", "flac"]
            for url in fileURLs {
                // 只处理音频文件，跳过 .zip 等非音频文件
                guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let fileSize = resourceValues.fileSize ?? 0
                let creationDate = resourceValues.creationDate ?? Date()
                let duration = getAudioFileDuration(url: url)

                let fileInfo = RecordedFileInfo(
                    url: url,
                    name: url.lastPathComponent,
                    date: creationDate,
                    duration: duration,
                    size: Int64(fileSize)
                )

                files.append(fileInfo)
            }

            files.sort { $0.date > $1.date }
        } catch {
            logger.error("加载录制文件失败: \(error.localizedDescription)")
        }

        recordedFiles = files
    }

    private func getAudioFileDuration(url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            return Double(audioFile.length) / audioFile.fileFormat.sampleRate
        } catch {
            logger.warning("无法获取音频文件时长: \(error.localizedDescription)")
            return 0
        }
    }


    
    @objc private func handleRenameFile(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RecordedFileInfo else { return }
        let alert = NSAlert()
        alert.messageText = "重命名录音"
        alert.informativeText = "输入新文件名（不含扩展名）："
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        let ext = file.url.pathExtension
        input.stringValue = file.url.deletingPathExtension().lastPathComponent
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        delegate?.recordedFilesViewDidRenameFile(self, file: file, newName: "\(newName).\(ext)")
    }
    
    // handleShowInFinder 已移除 — 文件路径不对用户暴露，导出是付费功能入口
}

// MARK: - IndustrialRecordedFileRowView
/// 自绘录音文件行 — 工业资产列表风格，替代 NSTableView 行
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
        // BUG-FIX-2: 垂直居中 — 用自定义 cell 替换默认 cell
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

        // 编辑按钮（hover 时出现，覆盖 formatBadge 位置）— BUG-011 fix: 统一 Industrial 风格
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
        // 文件名：去掉扩展名，简化显示
        let displayName = file.url.deletingPathExtension().lastPathComponent
        // 进一步美化：将下划线和日期格式简化
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
        // 检查是否点击了编辑按钮区域
        let location = convert(event.locationInWindow, from: nil)
        if !editButton.isHidden && editButton.frame.contains(location) {
            return // 让编辑按钮处理
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DMakeTranslation(0, -1, 0)
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        layer?.transform = CATransform3DIdentity
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        let location = convert(event.locationInWindow, from: nil)
        if !editButton.isHidden && editButton.frame.contains(location) {
            return // 编辑按钮已处理
        }
        onSelect?()
        if event.clickCount >= 2 {
            onDoubleClick?()
        }
    }

    @objc private func editButtonClicked() {
        onEdit?()
    }
}
