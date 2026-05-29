import Cocoa

// MARK: - IndustrialButtonView
final class IndustrialButtonView: NSView {
    var onClick: (() -> Void)?
    var isEnabled: Bool = true { didSet { updateAppearance() } }

    private let titleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let iconName: String?
    private var isHovering = false
    private var isPressing = false

    init(title: String, icon: String? = nil) {
        self.iconName = icon
        super.init(frame: .zero)
        titleLabel.stringValue = title.uppercased()
        setupView()
    }

    required init?(coder: NSCoder) {
        self.iconName = nil
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.sm
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        if let iconName, let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            iconView.image = image
            iconView.contentTintColor = IndustrialColors.onSurfaceVariant
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)
        }

        titleLabel.font = IndustrialTypography.label
        titleLabel.textColor = IndustrialColors.onSurfaceVariant
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        if iconView.superview != nil {
            NSLayoutConstraint.activate([
                // icon + title 作为整体居中；title 轻微右移，为左侧 icon 留空间
                titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 8),
                iconView.trailingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: -IndustrialSpacing.xs),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 14),
                iconView.heightAnchor.constraint(equalToConstant: 14),
                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: IndustrialSpacing.sm),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -IndustrialSpacing.sm)
            ])
        } else {
            NSLayoutConstraint.activate([
                titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: IndustrialSpacing.sm),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -IndustrialSpacing.sm)
            ])
        }

        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28)
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }

    // BUG-013 fix: 提供 intrinsicContentSize 防止宽度坍缩
    override var intrinsicContentSize: NSSize {
        let titleSize = titleLabel.intrinsicContentSize
        let iconWidth: CGFloat = iconView.superview != nil ? 14 + IndustrialSpacing.xs : 0
        let padding = IndustrialSpacing.sm * 2
        return NSSize(width: titleSize.width + iconWidth + padding + 8, height: 28)
    }

    private func updateAppearance() {
        guard let layer else { return }
        if !isEnabled {
            layer.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
            layer.borderColor = IndustrialColors.outlineVariant.withAlphaComponent(0.35).cgColor
            titleLabel.textColor = IndustrialColors.textTertiary.withAlphaComponent(0.55)
            iconView.contentTintColor = IndustrialColors.textTertiary.withAlphaComponent(0.55)
            alphaValue = 0.65
            return
        }

        alphaValue = 1
        layer.backgroundColor = (isHovering ? IndustrialColors.surfaceContainerHigh : IndustrialColors.surfaceContainerLow).cgColor
        layer.borderColor = (isHovering ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant).cgColor
        layer.shadowColor = IndustrialColors.shadowColor.cgColor
        layer.shadowRadius = isPressing ? 3 : (isHovering ? 8 : 4)
        layer.shadowOpacity = isHovering ? 0.45 : 0.22
        layer.shadowOffset = CGSize(width: 0, height: isPressing ? 1 : 2)
        titleLabel.textColor = isHovering ? IndustrialColors.primary : IndustrialColors.onSurfaceVariant
        iconView.contentTintColor = isHovering ? IndustrialColors.primary : IndustrialColors.onSurfaceVariant
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovering = true
        NSCursor.pointingHand.set()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressing = false
        NSCursor.arrow.set()
        layer?.transform = CATransform3DIdentity
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressing = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DMakeTranslation(0, -2, 0)
        CATransaction.commit()
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        isPressing = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DIdentity
        CATransaction.commit()
        updateAppearance()
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

// MARK: - IndustrialCompactIconButton
/// 紧凑版 icon button（28×28），用于导航栏、操作栏等空间受限的场景
final class IndustrialCompactIconButton: NSView {
    var onClick: (() -> Void)?
    var isEnabled: Bool = true {
        didSet {
            updateAppearance()
            setAccessibilityEnabled(isEnabled)
        }
    }

    private let iconLabel = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private var isHovering = false
    private var useImage = false

    init(symbol: String) {
        super.init(frame: .zero)
        // Try SF Symbol first, fallback to text character
        if let sfImage = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol) {
            iconImageView.image = sfImage
            iconImageView.isHidden = false
            iconLabel.isHidden = true
            useImage = true
        } else {
            iconLabel.stringValue = symbol
        }
        setupView()
    }

    func setSymbol(_ symbol: String) {
        iconLabel.stringValue = symbol
        iconLabel.isHidden = false
        iconImageView.isHidden = true
        useImage = false
    }
    
    func setImage(_ image: NSImage?) {
        guard let image = image else { return }
        iconImageView.image = image
        iconImageView.isHidden = false
        iconLabel.isHidden = true
        useImage = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.sm
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        iconLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        iconLabel.textColor = IndustrialColors.onSurfaceVariant
        iconLabel.alignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconLabel)
        
        iconImageView.contentTintColor = IndustrialColors.onSurfaceVariant
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.isHidden = true
        addSubview(iconImageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32),
            iconLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16)
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        let active = isEnabled && isHovering
        alphaValue = isEnabled ? 1.0 : 0.42
        // 参考 Transport 面板：微妙内凹阴影 + 柔和背景
        layer.backgroundColor = (active ? IndustrialColors.surfaceContainerHighest : IndustrialColors.surfaceContainerHigh).cgColor
        layer.borderColor = (active ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant.withAlphaComponent(0.5)).cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowRadius = active ? 1 : 2
        layer.shadowOpacity = active ? 0.1 : 0.25
        layer.shadowOffset = CGSize(width: 0, height: active ? 0 : 1)
        let tintColor = active ? IndustrialColors.primary : IndustrialColors.onSurfaceVariant
        iconLabel.textColor = tintColor
        iconImageView.contentTintColor = tintColor
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovering = true
        NSCursor.pointingHand.set()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.arrow.set()
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.transform = CATransform3DMakeTranslation(0, -1, 0)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.transform = CATransform3DIdentity
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

// MARK: - IndustrialToggleView
final class IndustrialToggleView: NSView {
    var onChange: ((Bool) -> Void)?
    var state: NSControl.StateValue = .off { didSet { updateAppearance() } }
    var isEnabled: Bool = true { didSet { updateAppearance() } }

    private let boxView = NSView()
    private let checkLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private var isHovering = false

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.stringValue = title
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        boxView.wantsLayer = true
        boxView.layer?.cornerRadius = IndustrialCornerRadius.xs
        boxView.layer?.borderWidth = 1
        boxView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(boxView)

        checkLabel.stringValue = "✓"
        checkLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        checkLabel.textColor = IndustrialColors.surface
        checkLabel.alignment = .center
        checkLabel.translatesAutoresizingMaskIntoConstraints = false
        boxView.addSubview(checkLabel)

        titleLabel.font = IndustrialTypography.body
        titleLabel.textColor = IndustrialColors.onSurfaceVariant
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            boxView.leadingAnchor.constraint(equalTo: leadingAnchor),
            boxView.centerYAnchor.constraint(equalTo: centerYAnchor),
            boxView.widthAnchor.constraint(equalToConstant: 16),
            boxView.heightAnchor.constraint(equalToConstant: 16),
            checkLabel.centerXAnchor.constraint(equalTo: boxView.centerXAnchor),
            checkLabel.centerYAnchor.constraint(equalTo: boxView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: boxView.trailingAnchor, constant: IndustrialSpacing.sm),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }

    private func updateAppearance() {
        let on = state == .on
        checkLabel.isHidden = !on
        boxView.layer?.backgroundColor = on ? IndustrialColors.primaryContainer.cgColor : IndustrialColors.surfaceContainerLow.cgColor
        boxView.layer?.borderColor = on ? IndustrialColors.primary.cgColor : (isHovering ? IndustrialColors.primaryContainer.cgColor : IndustrialColors.outlineVariant.cgColor)
        titleLabel.textColor = !isEnabled ? IndustrialColors.textTertiary.withAlphaComponent(0.55) : (on ? IndustrialColors.onSurface : IndustrialColors.onSurfaceVariant)
        alphaValue = isEnabled ? 1 : 0.55
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovering = true
        NSCursor.pointingHand.set()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.arrow.set()
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        state = state == .on ? .off : .on
        onChange?(state == .on)
    }
}

// MARK: - IndustrialTabButtonView
final class IndustrialTabButtonView: NSView {
    var onClick: (() -> Void)?
    var isSelectedTab: Bool = false { didSet { updateAppearance() } }

    private let titleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var isHovering = false

    init(title: String, icon: String?) {
        super.init(frame: .zero)
        titleLabel.stringValue = title.uppercased()
        if let icon, let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            iconView.image = image
        }
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.sm
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        iconView.contentTintColor = IndustrialColors.onSurfaceVariant
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.font = IndustrialTypography.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Allow external width constraints to override intrinsic content size
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: IndustrialSpacing.sm),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: IndustrialSpacing.xs),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -IndustrialSpacing.sm)
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }

    private func updateAppearance() {
        let active = isSelectedTab || isHovering
        layer?.backgroundColor = (isSelectedTab ? IndustrialColors.surfaceContainerHighest : (isHovering ? IndustrialColors.surfaceContainerHigh : NSColor.clear)).cgColor
        layer?.borderColor = (active ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant.withAlphaComponent(0.4)).cgColor
        titleLabel.textColor = isSelectedTab ? IndustrialColors.primary : IndustrialColors.onSurfaceVariant
        iconView.contentTintColor = isSelectedTab ? IndustrialColors.primary : IndustrialColors.onSurfaceVariant
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSCursor.pointingHand.set()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSCursor.arrow.set()
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.transform = CATransform3DMakeTranslation(0, -1, 0)
    }

    override func mouseUp(with event: NSEvent) {
        layer?.transform = CATransform3DIdentity
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}
// MARK: - IndustrialRecordButtonView
final class IndustrialRecordButtonView: NSView {
    var onClick: (() -> Void)?
    var isEnabled: Bool = true {
        didSet {
            alphaValue = isEnabled ? 1 : 0.55
            setAccessibilityEnabled(isEnabled)
        }
    }

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
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        NSCursor.pointingHand.set()
        layer?.shadowRadius += 4
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        layer?.transform = CATransform3DIdentity
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DMakeTranslation(0, -3, 0)
        layer?.shadowRadius = max(6, (layer?.shadowRadius ?? 12) - 6)
        layer?.shadowOpacity = 0.65
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DIdentity
        CATransaction.commit()
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}
// MARK: - IndustrialIconButtonView
final class IndustrialIconButtonView: NSView {
    var onClick: (() -> Void)?
    var isEnabled: Bool = true { didSet { updateAppearance() } }

    private let iconLabel = NSTextField(labelWithString: "")
    private var isHovering = false
    private var isPressing = false

    init(symbol: String) {
        super.init(frame: .zero)
        iconLabel.stringValue = symbol
        setupView()
    }

    func setSymbol(_ symbol: String) {
        iconLabel.stringValue = symbol
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.sm
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        iconLabel.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        iconLabel.textColor = IndustrialColors.onSurfaceVariant
        iconLabel.alignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 64),
            heightAnchor.constraint(equalToConstant: 64),
            iconLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
            iconLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6)
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        let active = isEnabled && (isHovering || isPressing)
        alphaValue = isEnabled ? 1.0 : 0.42
        layer.backgroundColor = (isPressing ? IndustrialColors.surfaceContainerHighest : (active ? IndustrialColors.surfaceContainerHigh : IndustrialColors.surfaceContainerLow)).cgColor
        layer.borderColor = (active ? IndustrialColors.primaryContainer : IndustrialColors.outlineVariant).cgColor
        layer.shadowColor = IndustrialColors.shadowColor.cgColor
        layer.shadowRadius = isPressing ? 3 : (isHovering ? 8 : 5)
        layer.shadowOpacity = isHovering ? 0.45 : 0.25
        layer.shadowOffset = CGSize(width: 0, height: isPressing ? 1 : 2)
        iconLabel.textColor = active ? IndustrialColors.primary : IndustrialColors.onSurfaceVariant
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovering = true
        NSCursor.pointingHand.set()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressing = false
        NSCursor.arrow.set()
        layer?.transform = CATransform3DIdentity
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressing = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DMakeTranslation(0, -2, 0)
        CATransaction.commit()
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        isPressing = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.standard)
        layer?.transform = CATransform3DIdentity
        CATransaction.commit()
        updateAppearance()
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}
