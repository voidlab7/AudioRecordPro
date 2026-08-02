import Cocoa

// MARK: - TrackRowViewDelegate
protocol EditorTrackRowViewDelegate: AnyObject {
    func trackRowDidRequestMute(_ row: EditorTrackRowView)
    func trackRowDidRequestSolo(_ row: EditorTrackRowView)
}

// MARK: - EditorTrackRowView（P0-B：单条轨道行）
/// 一条轨道的组合视图：左侧轨道头 + 右侧波形区域
class EditorTrackRowView: NSView {
    
    // MARK: - Constants
    static let headerWidth: CGFloat = 80
    /// 轨道行高度 = 140（容器），其中 clip 块占 ~90px（居中 64%），
    /// 上下各 25px 留白给 clip 标签和呼吸感。
    /// 体现"轨道是容器，clip 是被吸附内容"的设计意图。
    static let rowHeight: CGFloat = 140
    
    // MARK: - Properties
    weak var delegate: EditorTrackRowViewDelegate?
    
    let trackIndex: Int
    let waveformView = EditorWaveformView()
    
    private let headerView = NSView()
    private let trackNumberLabel = NSTextField(labelWithString: "")
    private let trackIconView = NSImageView()
    private let trackNameLabel = NSTextField(labelWithString: "")
    private let muteButton = NSButton()
    private let soloButton = NSButton()
    private let trackColor: NSColor
    
    // MARK: - Init
    init(trackIndex: Int, trackName: String, trackColor: NSColor) {
        self.trackIndex = trackIndex
        self.trackColor = trackColor
        super.init(frame: .zero)

        trackNumberLabel.stringValue = "\(trackIndex + 1)"
        trackNameLabel.stringValue = trackName
        setupView()
        // P0-C: 把轨道名作为占位 clip 名称（后续接入 AudioClip 后改用 clip.name）
        waveformView.clipName = trackName
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        
        // 轨道头背景
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = IndustrialColors.surfaceContainer.cgColor
        headerView.layer?.borderWidth = 0.5
        headerView.layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)
        
        // 轨道编号
        trackNumberLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        trackNumberLabel.textColor = IndustrialColors.textTertiary
        trackNumberLabel.alignment = .center
        trackNumberLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(trackNumberLabel)
        
        // 轨道图标
        if let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
            trackIconView.image = img
            trackIconView.contentTintColor = trackColor
            trackIconView.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(trackIconView)
        }
        
        // 轨道名称
        trackNameLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        trackNameLabel.textColor = IndustrialColors.onSurface
        trackNameLabel.lineBreakMode = .byTruncatingTail
        trackNameLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(trackNameLabel)
        
        // Mute 按钮
        muteButton.title = "M"
        muteButton.bezelStyle = .inline
        muteButton.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        muteButton.target = self
        muteButton.action = #selector(muteTapped)
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(muteButton)
        
        // Solo 按钮
        soloButton.title = "S"
        soloButton.bezelStyle = .inline
        soloButton.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        soloButton.target = self
        soloButton.action = #selector(soloTapped)
        soloButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(soloButton)
        
        // 波形区域
        waveformView.wantsLayer = true
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(waveformView)
        
        // 底部分割线
        let bottomDivider = NSView()
        bottomDivider.wantsLayer = true
        bottomDivider.layer?.backgroundColor = IndustrialColors.outlineVariant.cgColor
        bottomDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomDivider)
        
        let h = Self.rowHeight
        let hw = Self.headerWidth
        
        // 轨道行固定高度 120，不拉伸填满（上下留白给多轨预留）
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: h),
            
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            headerView.widthAnchor.constraint(equalToConstant: hw),
            
            trackNumberLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 4),
            trackNumberLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            
            trackIconView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            trackIconView.topAnchor.constraint(equalTo: trackNumberLabel.bottomAnchor, constant: 4),
            trackIconView.widthAnchor.constraint(equalToConstant: 16),
            trackIconView.heightAnchor.constraint(equalToConstant: 16),
            
            trackNameLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            trackNameLabel.topAnchor.constraint(equalTo: trackIconView.bottomAnchor, constant: 4),
            trackNameLabel.widthAnchor.constraint(lessThanOrEqualTo: headerView.widthAnchor, constant: -8),
            
            muteButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 4),
            muteButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -4),
            muteButton.widthAnchor.constraint(equalToConstant: 22),
            muteButton.heightAnchor.constraint(equalToConstant: 18),
            
            soloButton.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: 2),
            soloButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -4),
            soloButton.widthAnchor.constraint(equalToConstant: 22),
            soloButton.heightAnchor.constraint(equalToConstant: 18),
            
            waveformView.leadingAnchor.constraint(equalTo: headerView.trailingAnchor),
            waveformView.topAnchor.constraint(equalTo: topAnchor),
            waveformView.trailingAnchor.constraint(equalTo: trailingAnchor),
            waveformView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            bottomDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomDivider.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
    
    // MARK: - Button Actions
    @objc private func muteTapped() { delegate?.trackRowDidRequestMute(self) }
    @objc private func soloTapped() { delegate?.trackRowDidRequestSolo(self) }
    
    /// 更新 Mute 状态视觉
    func updateMuteState(_ muted: Bool) {
        muteButton.contentTintColor = muted ? IndustrialColors.waveformCoral : nil
        waveformView.alphaValue = muted ? 0.3 : 1.0
    }
    
    /// 更新 Solo 状态视觉
    func updateSoloState(_ solo: Bool) {
        soloButton.contentTintColor = solo ? IndustrialColors.waveformAccent : nil
    }
}
