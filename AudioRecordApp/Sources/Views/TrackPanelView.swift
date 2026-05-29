import Cocoa

/// 轨道板委托
protocol TrackPanelViewDelegate: AnyObject {
    func trackPanelDidToggleMute(_ view: TrackPanelView, trackIndex: Int)
    func trackPanelDidToggleSolo(_ view: TrackPanelView, trackIndex: Int)
}

/// 左侧轨道控制板 — 显示轨道名称、🔊(Mute) 和 S(Solo) 按钮
/// 预留多轨道：纵向 NSStackView 排列
class TrackPanelView: NSView {
    
    // MARK: - Properties
    weak var delegate: TrackPanelViewDelegate?
    private let tracksStack = NSStackView()
    private var trackRows: [TrackRowView] = []
    
    static let panelWidth: CGFloat = 100
    
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
        layer?.backgroundColor = IndustrialColors.surfaceContainer.cgColor
        
        // 右侧边框
        let rightBorder = CALayer()
        rightBorder.backgroundColor = IndustrialColors.outlineVariant.cgColor
        rightBorder.frame = CGRect(x: TrackPanelView.panelWidth - 1, y: 0, width: 1, height: 10000)
        layer?.addSublayer(rightBorder)
        
        tracksStack.orientation = .vertical
        tracksStack.spacing = 0
        tracksStack.alignment = .leading
        tracksStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tracksStack)
        
        NSLayoutConstraint.activate([
            tracksStack.topAnchor.constraint(equalTo: topAnchor),
            tracksStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            tracksStack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    
    // MARK: - Public
    
    func updateTracks(_ tracks: [TrackInfo]) {
        // 清除旧行
        for row in trackRows {
            tracksStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        trackRows.removeAll()
        
        for (index, track) in tracks.enumerated() {
            let row = TrackRowView(track: track, index: index)
            row.onMuteToggle = { [weak self] idx in
                guard let self = self else { return }
                self.delegate?.trackPanelDidToggleMute(self, trackIndex: idx)
            }
            row.onSoloToggle = { [weak self] idx in
                guard let self = self else { return }
                self.delegate?.trackPanelDidToggleSolo(self, trackIndex: idx)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            tracksStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: tracksStack.widthAnchor),
                row.heightAnchor.constraint(equalToConstant: 60),
            ])
            trackRows.append(row)
        }
        
        // 空状态
        if tracks.isEmpty {
            let emptyRow = TrackRowView(track: TrackInfo(icon: "speaker.wave.2.fill", title: "未选择", isActive: false, sourceType: ""), index: 0)
            emptyRow.translatesAutoresizingMaskIntoConstraints = false
            tracksStack.addArrangedSubview(emptyRow)
            NSLayoutConstraint.activate([
                emptyRow.widthAnchor.constraint(equalTo: tracksStack.widthAnchor),
                emptyRow.heightAnchor.constraint(equalToConstant: 60),
            ])
            trackRows.append(emptyRow)
        }
    }
}

// MARK: - TrackRowView
/// 单条轨道行：图标 + 名称 + [🔊][S]
private class TrackRowView: NSView {
    var onMuteToggle: ((Int) -> Void)?
    var onSoloToggle: ((Int) -> Void)?
    private let trackIndex: Int
    private var isMuted = false
    
    private let iconLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let muteButton = NSButton()
    private let soloButton = NSButton()
    
    init(track: TrackInfo, index: Int) {
        self.trackIndex = index
        super.init(frame: .zero)
        
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
        
        // 底部边框
        let bottomBorder = CALayer()
        bottomBorder.backgroundColor = IndustrialColors.outlineVariant.cgColor
        bottomBorder.frame = CGRect(x: 0, y: 0, width: 10000, height: 1)
        layer?.addSublayer(bottomBorder)
        
        // Icon
        if let appIcon = track.appIcon {
            let imageView = NSImageView()
            imageView.image = appIcon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
            ])
        } else {
            // Render SF Symbol as image if possible, fallback to text
            if let sfImage = NSImage(systemSymbolName: track.icon, accessibilityDescription: track.title) {
                let imageView = NSImageView()
                imageView.image = sfImage
                imageView.contentTintColor = IndustrialColors.onSurfaceVariant
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(imageView)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                ])
            } else {
                iconLabel.stringValue = track.icon
                iconLabel.font = NSFont.systemFont(ofSize: 14)
                iconLabel.isBordered = false
                iconLabel.isEditable = false
                iconLabel.backgroundColor = .clear
                iconLabel.translatesAutoresizingMaskIntoConstraints = false
                addSubview(iconLabel)
                NSLayoutConstraint.activate([
                    iconLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    iconLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                ])
            }
        }
        
        // 轨道名称
        nameLabel.stringValue = track.title
        nameLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        nameLabel.textColor = IndustrialColors.onSurface
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isBordered = false
        nameLabel.isEditable = false
        nameLabel.backgroundColor = .clear
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 26),
        ])
        
        // Mute 按钮（喇叭图标）
        if let muteImg = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "静音") {
            muteButton.image = muteImg
            muteButton.imageScaling = .scaleProportionallyDown
        }
        muteButton.bezelStyle = .inline
        muteButton.isBordered = false
        muteButton.title = ""
        muteButton.contentTintColor = IndustrialColors.onSurfaceVariant
        muteButton.target = self
        muteButton.action = #selector(muteClicked)
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(muteButton)
        
        // Solo 按钮
        soloButton.title = "S"
        soloButton.bezelStyle = .inline
        soloButton.isBordered = false
        soloButton.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        soloButton.contentTintColor = IndustrialColors.onSurfaceVariant
        soloButton.target = self
        soloButton.action = #selector(soloClicked)
        soloButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(soloButton)
        
        NSLayoutConstraint.activate([
            muteButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            muteButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            muteButton.widthAnchor.constraint(equalToConstant: 22),
            muteButton.heightAnchor.constraint(equalToConstant: 18),
            
            soloButton.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: 4),
            soloButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            soloButton.widthAnchor.constraint(equalToConstant: 18),
            soloButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    @objc private func muteClicked() {
        isMuted.toggle()
        if isMuted {
            if let img = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: "取消静音") {
                muteButton.image = img
            }
            muteButton.contentTintColor = IndustrialColors.statusWarning
        } else {
            if let img = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "静音") {
                muteButton.image = img
            }
            muteButton.contentTintColor = IndustrialColors.onSurfaceVariant
        }
        onMuteToggle?(trackIndex)
    }
    
    @objc private func soloClicked() {
        onSoloToggle?(trackIndex)
    }
}
