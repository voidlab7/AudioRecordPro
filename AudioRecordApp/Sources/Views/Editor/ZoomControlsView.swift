import Cocoa

// MARK: - ZoomControlsDelegate
protocol ZoomControlsDelegate: AnyObject {
    func zoomControlsDidTapZoomIn(_ controls: ZoomControlsView)
    func zoomControlsDidTapZoomOut(_ controls: ZoomControlsView)
    func zoomControlsDidTapFitAll(_ controls: ZoomControlsView)
    func zoomControls(_ controls: ZoomControlsView, didChangeSliderTo level: CGFloat)
}

// MARK: - ZoomControlsView
/// 缩放控件组：[🔍−] ━━━●━━━━━ [🔍+] [⊞ Fit All]
class ZoomControlsView: NSView {

    // MARK: - Properties
    weak var delegate: ZoomControlsDelegate?

    /// 当前缩放级别（外部设置时同步滑块位置）
    var zoomLevel: CGFloat = 1.0 {
        didSet { updateSliderPosition() }
    }

    /// 最大缩放级别（用于对数映射计算）
    var maxZoomLevel: CGFloat = 100.0 {
        didSet { updateSliderPosition() }
    }

    /// 是否到达最小缩放（控制 zoomOut 按钮 disabled）
    var isAtMinZoom: Bool = true {
        didSet { zoomOutButton.isEnabled = !isAtMinZoom; updateButtonAppearance() }
    }

    /// 是否到达最大缩放（控制 zoomIn 按钮 disabled）
    var isAtMaxZoom: Bool = false {
        didSet { zoomInButton.isEnabled = !isAtMaxZoom; updateButtonAppearance() }
    }

    // MARK: - UI Components
    private let zoomOutButton = NSButton()
    private let zoomSlider = NSSlider()
    private let zoomInButton = NSButton()
    private let fitAllButton = NSButton()
    private let separatorLayer = CALayer()

    // 滑块约束（响应式宽度）
    private var sliderWidthConstraint: NSLayoutConstraint!
    private var sliderVisible: Bool = true

    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true

        // 分隔符（左侧竖线）
        separatorLayer.backgroundColor = IndustrialColors.outlineVariant.withAlphaComponent(0.5).cgColor
        layer?.addSublayer(separatorLayer)

        // 缩小按钮
        configureIconButton(zoomOutButton, symbolName: "minus.magnifyingglass", accessibilityLabel: "缩小")
        zoomOutButton.target = self
        zoomOutButton.action = #selector(handleZoomOut)
        addSubview(zoomOutButton)

        // 缩放滑块
        zoomSlider.translatesAutoresizingMaskIntoConstraints = false
        zoomSlider.minValue = 0
        zoomSlider.maxValue = 1
        zoomSlider.doubleValue = 0
        zoomSlider.target = self
        zoomSlider.action = #selector(handleSliderChange)
        zoomSlider.isContinuous = true
        zoomSlider.controlSize = .small
        zoomSlider.setAccessibilityLabel("缩放级别")
        addSubview(zoomSlider)

        // 放大按钮
        configureIconButton(zoomInButton, symbolName: "plus.magnifyingglass", accessibilityLabel: "放大")
        zoomInButton.target = self
        zoomInButton.action = #selector(handleZoomIn)
        addSubview(zoomInButton)

        // Fit All 按钮
        configureIconButton(fitAllButton, symbolName: "arrow.left.and.right.square", accessibilityLabel: "适应全部")
        fitAllButton.target = self
        fitAllButton.action = #selector(handleFitAll)
        fitAllButton.toolTip = "适应全部 (⌘0)"
        addSubview(fitAllButton)

        setupConstraints()
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, accessibilityLabel: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .toolbar
        button.isBordered = false
        button.imagePosition = .imageOnly

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }

        button.contentTintColor = IndustrialColors.onSurfaceVariant
        button.setAccessibilityLabel(accessibilityLabel)

        // 尺寸
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func setupConstraints() {
        sliderWidthConstraint = zoomSlider.widthAnchor.constraint(equalToConstant: 100)

        NSLayoutConstraint.activate([
            // 缩小按钮
            zoomOutButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: IndustrialSpacing.sm),
            zoomOutButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 滑块
            zoomSlider.leadingAnchor.constraint(equalTo: zoomOutButton.trailingAnchor, constant: IndustrialSpacing.xs),
            zoomSlider.centerYAnchor.constraint(equalTo: centerYAnchor),
            sliderWidthConstraint,

            // 放大按钮
            zoomInButton.leadingAnchor.constraint(equalTo: zoomSlider.trailingAnchor, constant: IndustrialSpacing.xs),
            zoomInButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Fit All 按钮
            fitAllButton.leadingAnchor.constraint(equalTo: zoomInButton.trailingAnchor, constant: IndustrialSpacing.sm),
            fitAllButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            fitAllButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -IndustrialSpacing.sm)
        ])
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // 分隔符定位（左端竖线）
        separatorLayer.frame = CGRect(x: 0, y: (bounds.height - 16) / 2, width: 1, height: 16)
    }

    /// 根据可用宽度更新响应式布局
    func updateForAvailableWidth(_ width: CGFloat) {
        if width > 200 {
            // 全部显示
            zoomSlider.isHidden = false
            sliderWidthConstraint.constant = min(120, max(80, width - 120))
            sliderVisible = true
        } else if width > 120 {
            // 隐藏滑块
            zoomSlider.isHidden = true
            sliderVisible = false
        } else {
            // 仅 FitAll
            zoomSlider.isHidden = true
            zoomOutButton.isHidden = true
            zoomInButton.isHidden = true
            sliderVisible = false
        }
    }

    // MARK: - Actions

    @objc private func handleZoomIn() {
        delegate?.zoomControlsDidTapZoomIn(self)
    }

    @objc private func handleZoomOut() {
        delegate?.zoomControlsDidTapZoomOut(self)
    }

    @objc private func handleFitAll() {
        delegate?.zoomControlsDidTapFitAll(self)
    }

    @objc private func handleSliderChange() {
        let position = CGFloat(zoomSlider.doubleValue)
        let level = logMappingToZoomLevel(position)
        delegate?.zoomControls(self, didChangeSliderTo: level)
    }

    // MARK: - Log Mapping (对数映射)

    /// zoomLevel → sliderPosition (0.0 ~ 1.0)
    private func zoomLevelToSliderPosition(_ level: CGFloat) -> CGFloat {
        guard maxZoomLevel > 1.0 else { return 0 }
        return log(max(1.0, level)) / log(maxZoomLevel)
    }

    /// sliderPosition (0.0 ~ 1.0) → zoomLevel
    private func logMappingToZoomLevel(_ position: CGFloat) -> CGFloat {
        guard maxZoomLevel > 1.0 else { return 1.0 }
        return pow(maxZoomLevel, max(0, min(1, position)))
    }

    // MARK: - State Sync

    private func updateSliderPosition() {
        let position = zoomLevelToSliderPosition(zoomLevel)
        zoomSlider.doubleValue = Double(position)
        zoomSlider.setAccessibilityValue("缩放 \(Int(zoomLevel))x")
    }

    private func updateButtonAppearance() {
        zoomOutButton.contentTintColor = isAtMinZoom
            ? IndustrialColors.onSurfaceVariant.withAlphaComponent(0.35)
            : IndustrialColors.onSurfaceVariant
        zoomInButton.contentTintColor = isAtMaxZoom
            ? IndustrialColors.onSurfaceVariant.withAlphaComponent(0.35)
            : IndustrialColors.onSurfaceVariant
    }

    // MARK: - Hover Tracking

    private var hoveredButton: NSButton?
    private var hoverBackgroundLayers: [NSButton: CALayer] = [:]

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // Per-button tracking areas for hover effect
        for button in [zoomOutButton, zoomInButton, fitAllButton] {
            let area = NSTrackingArea(
                rect: button.frame,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: ["button": button]
            )
            addTrackingArea(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo,
              let button = info["button"] as? NSButton,
              button.isEnabled else { return }

        hoveredButton = button
        button.contentTintColor = IndustrialColors.onSurface

        // Add hover background
        let bgLayer = CALayer()
        bgLayer.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        bgLayer.cornerRadius = IndustrialCornerRadius.xs
        bgLayer.frame = button.frame.insetBy(dx: -2, dy: -2)
        layer?.insertSublayer(bgLayer, at: 0)
        hoverBackgroundLayers[button] = bgLayer
    }

    override func mouseExited(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo,
              let button = info["button"] as? NSButton else { return }

        hoveredButton = nil
        // Restore original tint
        if button == zoomOutButton {
            button.contentTintColor = isAtMinZoom
                ? IndustrialColors.onSurfaceVariant.withAlphaComponent(0.35)
                : IndustrialColors.onSurfaceVariant
        } else if button == zoomInButton {
            button.contentTintColor = isAtMaxZoom
                ? IndustrialColors.onSurfaceVariant.withAlphaComponent(0.35)
                : IndustrialColors.onSurfaceVariant
        } else {
            button.contentTintColor = IndustrialColors.onSurfaceVariant
        }

        // Remove hover background
        hoverBackgroundLayers[button]?.removeFromSuperlayer()
        hoverBackgroundLayers[button] = nil
    }
}
