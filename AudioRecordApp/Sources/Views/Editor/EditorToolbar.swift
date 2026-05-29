import Cocoa

// MARK: - Editor Tool Type
enum EditorToolType: String, CaseIterable {
    case trim = "裁剪"
    case silenceTrim = "静音裁剪"
    case normalize = "标准化"
    case fade = "淡入淡出"

    var iconName: String {
        switch self {
        case .trim: return "scissors"
        case .silenceTrim: return "waveform.badge.minus"
        case .normalize: return "chart.bar.fill"
        case .fade: return "speaker.wave.2"
        }
    }
}

// MARK: - Delegate Protocol
protocol EditorToolbarDelegate: AnyObject {
    func editorToolbarDidTapPreviewPlay(_ toolbar: EditorToolbar)
    func editorToolbarDidTapPreviewStop(_ toolbar: EditorToolbar)
}

// MARK: - EditorToolbar
/// 编辑器底部播放控制栏 — 左侧播放/暂停/停止 + 右侧缩放控件
class EditorToolbar: NSView {

    // MARK: - UI Components
    private let previewPlayButton = IndustrialCompactIconButton(symbol: "▶")
    private let previewStopButton = IndustrialCompactIconButton(symbol: "■")
    private let topSeparator = CALayer()

    /// 缩放控件组（公开，供 EditorViewController 设置 delegate）
    let zoomControls = ZoomControlsView()

    // MARK: - Properties
    weak var delegate: EditorToolbarDelegate?

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

        topSeparator.backgroundColor = IndustrialColors.outlineVariant.cgColor
        layer?.addSublayer(topSeparator)

        // 播放控制（左侧）
        previewPlayButton.translatesAutoresizingMaskIntoConstraints = false
        previewPlayButton.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.editorToolbarDidTapPreviewPlay(self)
        }
        addSubview(previewPlayButton)

        previewStopButton.translatesAutoresizingMaskIntoConstraints = false
        previewStopButton.isEnabled = false
        previewStopButton.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.editorToolbarDidTapPreviewStop(self)
        }
        addSubview(previewStopButton)

        // 缩放控件（右侧）
        zoomControls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomControls)

        NSLayoutConstraint.activate([
            // 播放控制左侧
            previewPlayButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: IndustrialSpacing.md),
            previewPlayButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            previewStopButton.leadingAnchor.constraint(equalTo: previewPlayButton.trailingAnchor, constant: IndustrialSpacing.sm),
            previewStopButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 缩放控件右侧
            zoomControls.trailingAnchor.constraint(equalTo: trailingAnchor),
            zoomControls.centerYAnchor.constraint(equalTo: centerYAnchor),
            zoomControls.heightAnchor.constraint(equalTo: heightAnchor)
        ])
    }

    override func layout() {
        super.layout()
        topSeparator.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)

        // 响应式：根据可用宽度调整缩放控件
        let playControlsWidth: CGFloat = 80  // 估算播放控制区域宽度
        let availableWidth = bounds.width - playControlsWidth - IndustrialSpacing.md * 2
        zoomControls.updateForAvailableWidth(availableWidth)
    }

    // MARK: - Public Methods

    func updatePreviewState(isPlaying: Bool) {
        previewPlayButton.setSymbol(isPlaying ? "Ⅱ" : "▶")
        previewStopButton.isEnabled = isPlaying
    }

    // 编辑工具相关方法保留接口但不操作（工具已移到 NavigationBar）
    func setToolEnabled(_ tool: EditorToolType, enabled: Bool) {}
    func setAllToolsEnabled(_ enabled: Bool) {}
}
