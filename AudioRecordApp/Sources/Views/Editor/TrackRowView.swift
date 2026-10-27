import Cocoa

// MARK: - TrackRowViewDelegate
protocol EditorTrackRowViewDelegate: AnyObject {
    func trackRowDidRequestMute(_ row: EditorTrackRowView)
    /// UI-019: 轨道头音量滑块变化（0.0～1.0）
    func trackRowDidChangeVolume(_ row: EditorTrackRowView, volume: Float)
}

// MARK: - VolumeSliderView（UI-019：轨道头音量滑块）
/// 3px 圆角轨 + 9px 圆形旋钮；自行处理点击/拖拽，热区整条轨道高度外扩 8px
final class VolumeSliderView: NSView {

    var onValueChange: ((Float) -> Void)?
    private(set) var value: Float = 1.0

    private let trackLayer = CALayer()
    private let knobLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        trackLayer.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        trackLayer.cornerRadius = 2
        layer?.addSublayer(trackLayer)
        knobLayer.backgroundColor = IndustrialColors.onSurfaceVariant.cgColor
        knobLayer.cornerRadius = 4.5
        layer?.addSublayer(knobLayer)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        trackLayer.frame = CGRect(x: 0, y: h / 2 - 1.5, width: bounds.width, height: 3)
        let knobX = max(0, min(bounds.width - 9, bounds.width * CGFloat(value) - 4.5))
        knobLayer.frame = CGRect(x: knobX, y: h / 2 - 4.5, width: 9, height: 9)
    }

    func setValue(_ v: Float, notify: Bool) {
        value = max(0, min(1, v))
        needsLayout = true
        if notify { onValueChange?(value) }
    }

    private func ratio(for locationInWindow: NSPoint) -> Float {
        let local = convert(locationInWindow, from: nil)
        return Float(max(0, min(1, local.x / max(1, bounds.width))))
    }

    override func mouseDown(with event: NSEvent) { setValue(ratio(for: event.locationInWindow), notify: true) }
    override func mouseDragged(with event: NSEvent) { setValue(ratio(for: event.locationInWindow), notify: true) }
}

// MARK: - EditorTrackRowView（P0-B：单条轨道行）
/// 一条轨道的组合视图：左侧轨道头 + 右侧波形区域
/// UI-019（design-B）：轨道头 80→88，音量滑块 / 16×16 M / 回放电平行
/// UI-031：去左缘颜色条；波形小图标橙→青绿；静音改线性喇叭图标（去 M 字母）；S（solo）按钮与功能移除；音量滑条保留
class EditorTrackRowView: NSView {

    // MARK: - Constants
    /// UI-019: 88px（80→88，容纳颜色条与音量滑块，规格表 §1.3）
    static let headerWidth: CGFloat = 88
    /// 轨道行高度 = 140（容器），其中 clip 块占 ~90px（居中 64%），
    /// 上下各 25px 留白给 clip 标签和呼吸感。
    /// 体现"轨道是容器，clip 是被吸附内容"的设计意图。
    static let rowHeight: CGFloat = 140

    // MARK: - Properties
    weak var delegate: EditorTrackRowViewDelegate?

    let trackIndex: Int
    let waveformView = EditorWaveformView()

    private let headerView = NSView()
    private let trackIconView = NSImageView()
    private let trackNameLabel = NSTextField(labelWithString: "")
    /// UI-019: 轨道元信息行（编号），9 mono
    private let trackMetaLabel = NSTextField(labelWithString: "")
    /// UI-019: 音量滑块
    private let volumeSlider = VolumeSliderView()
    /// UI-031: 静音按钮（线性喇叭图标，去「M」字母）
    private let muteButton = NSButton()
    /// UI-019: 回放电平行（4px 条；头宽固定 88 → 轨宽 64，宽度用常量约束刷新）
    private let levelTrack = NSView()
    private let levelFill = NSView()
    private var levelWidthConstraint: NSLayoutConstraint!
    private let levelTrackWidth: CGFloat = EditorTrackRowView.headerWidth - 24
    private let trackColor: NSColor

    // MARK: - Init
    init(trackIndex: Int, trackName: String, trackColor: NSColor) {
        self.trackIndex = trackIndex
        self.trackColor = trackColor
        super.init(frame: .zero)

        trackNameLabel.stringValue = trackName
        trackMetaLabel.stringValue = String(format: "%02d", trackIndex + 1)
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

        // 轨道图标（与轨道名同行，规格表 §1.2：轨道名 11 Semibold）
        // UI-031: 图标橙→青绿（waveformBase，与波形色族统一）
        if let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
            trackIconView.image = img
            trackIconView.contentTintColor = IndustrialColors.waveformBase
            trackIconView.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(trackIconView)
        }

        // 轨道名称
        trackNameLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        trackNameLabel.textColor = IndustrialColors.onSurface
        trackNameLabel.lineBreakMode = .byTruncatingTail
        trackNameLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(trackNameLabel)

        // UI-019: 元信息（编号 9 mono）
        trackMetaLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        trackMetaLabel.textColor = IndustrialColors.textTertiary
        trackMetaLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(trackMetaLabel)

        // UI-019: 音量滑块（规格表 §1.3：3px 轨 + 9px 旋钮）
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.onValueChange = { [weak self] value in
            guard let self else { return }
            self.delegate?.trackRowDidChangeVolume(self, volume: value)
        }
        headerView.addSubview(volumeSlider)

        // UI-031: 静音按钮 — 剪映线性喇叭图标（去「M」字母，去边框），16×16 热区
        muteButton.isBordered = false
        muteButton.setButtonType(.momentaryChange)
        muteButton.image = NSImage(systemSymbolName: "speaker", accessibilityDescription: "静音".localized)
        muteButton.imageScaling = .scaleProportionallyDown
        muteButton.contentTintColor = IndustrialColors.textTertiary
        muteButton.target = self
        muteButton.action = #selector(muteTapped)
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(muteButton)

        // UI-019: 回放电平行（4px 圆角轨 + 填充条，R1 骨架落位）
        levelTrack.wantsLayer = true
        levelTrack.layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        levelTrack.layer?.cornerRadius = 2
        levelTrack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(levelTrack)

        levelFill.wantsLayer = true
        levelFill.layer?.backgroundColor = trackColor.cgColor
        levelFill.layer?.cornerRadius = 2
        levelFill.translatesAutoresizingMaskIntoConstraints = false
        levelTrack.addSubview(levelFill)

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

        // 轨道行固定高度 140，不拉伸填满（上下留白给多轨预留）
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        levelWidthConstraint = levelFill.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: h),

            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            headerView.widthAnchor.constraint(equalToConstant: hw),

            // 竖排内容列：名行 / 编号 / 音量 / 静音 / 电平（gap 5，规格表 §1.3）
            trackIconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            trackIconView.centerYAnchor.constraint(equalTo: trackNameLabel.centerYAnchor),
            trackIconView.widthAnchor.constraint(equalToConstant: 13),
            trackIconView.heightAnchor.constraint(equalToConstant: 13),

            trackNameLabel.leadingAnchor.constraint(equalTo: trackIconView.trailingAnchor, constant: 5),
            trackNameLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 18),
            trackNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -8),

            trackMetaLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            trackMetaLabel.topAnchor.constraint(equalTo: trackNameLabel.bottomAnchor, constant: 3),

            volumeSlider.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            volumeSlider.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            volumeSlider.topAnchor.constraint(equalTo: trackMetaLabel.bottomAnchor, constant: 7),
            volumeSlider.heightAnchor.constraint(equalToConstant: 14),

            muteButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            muteButton.topAnchor.constraint(equalTo: volumeSlider.bottomAnchor, constant: 6),
            muteButton.widthAnchor.constraint(equalToConstant: 16),
            muteButton.heightAnchor.constraint(equalToConstant: 16),

            levelTrack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            levelTrack.widthAnchor.constraint(equalToConstant: levelTrackWidth),
            levelTrack.topAnchor.constraint(equalTo: muteButton.bottomAnchor, constant: 6),
            levelTrack.heightAnchor.constraint(equalToConstant: 4),
            levelTrack.bottomAnchor.constraint(lessThanOrEqualTo: headerView.bottomAnchor, constant: -10),

            levelFill.leadingAnchor.constraint(equalTo: levelTrack.leadingAnchor),
            levelFill.topAnchor.constraint(equalTo: levelTrack.topAnchor),
            levelFill.bottomAnchor.constraint(equalTo: levelTrack.bottomAnchor),
            levelWidthConstraint,

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

    // MARK: - Public API

    /// 设置音量（0～1）并刷新旋钮位置
    func setVolume(_ value: Float) {
        volumeSlider.setValue(value, notify: false)
    }

    /// UI-019: 回放电平更新（0～1；R1 骨架落位，播放联动后续接）
    func updatePlayLevel(_ level: Float) {
        let clamped = CGFloat(max(0, min(1, level)))
        levelWidthConstraint.constant = levelTrackWidth * clamped
        levelTrack.needsLayout = true
    }

    /// 更新 Mute 状态视觉（UI-031：静音=speaker.slash + coral，未静音=speaker + 灰；波形同步变暗）
    func updateMuteState(_ muted: Bool) {
        muteButton.image = NSImage(systemSymbolName: muted ? "speaker.slash" : "speaker",
                                   accessibilityDescription: "静音".localized)
        muteButton.contentTintColor = muted ? IndustrialColors.waveformCoral : IndustrialColors.textTertiary
        waveformView.alphaValue = muted ? 0.3 : 1.0
    }

    // MARK: - Button Actions
    @objc private func muteTapped() { delegate?.trackRowDidRequestMute(self) }
}
