import Cocoa

/// 编辑工具栏委托
protocol EditToolbarViewDelegate: AnyObject {
    func editToolbarDidRequestTrim(_ view: EditToolbarView)
    func editToolbarDidRequestNormalize(_ view: EditToolbarView)
    func editToolbarDidRequestFadeIn(_ view: EditToolbarView)
    func editToolbarDidRequestFadeOut(_ view: EditToolbarView)
}

/// 顶部编辑工具栏 — 录制态禁用，编辑态自动激活
/// 包含裁剪、标准化、淡入、淡出等编辑操作
class EditToolbarView: NSView {
    
    // MARK: - Properties
    weak var delegate: EditToolbarViewDelegate?
    private(set) var isEnabled: Bool = false
    
    // MARK: - UI Components
    private let stackView = NSStackView()
    private let trimButton = EditToolbarButton(title: "裁剪", symbol: "scissors")
    private let normalizeButton = EditToolbarButton(title: "标准化", symbol: "waveform.badge.magnifyingglass")
    private let fadeInButton = EditToolbarButton(title: "淡入", symbol: "arrow.up.right")
    private let fadeOutButton = EditToolbarButton(title: "淡出", symbol: "arrow.down.right")
    private let separator = NSView()
    
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
        
        // 底部边框线
        let bottomBorder = CALayer()
        bottomBorder.backgroundColor = IndustrialColors.outlineVariant.cgColor
        bottomBorder.frame = CGRect(x: 0, y: 0, width: 10000, height: 1)
        layer?.addSublayer(bottomBorder)
        
        // Stack
        stackView.orientation = .horizontal
        stackView.spacing = 2
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        // 按钮
        let buttons = [trimButton, normalizeButton, fadeInButton, fadeOutButton]
        for btn in buttons {
            btn.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(btn)
            btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        
        // 弹性空间
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(spacer)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        
        // 按钮点击
        trimButton.onClick = { [weak self] in
            guard let self = self, self.isEnabled else { return }
            self.delegate?.editToolbarDidRequestTrim(self)
        }
        normalizeButton.onClick = { [weak self] in
            guard let self = self, self.isEnabled else { return }
            self.delegate?.editToolbarDidRequestNormalize(self)
        }
        fadeInButton.onClick = { [weak self] in
            guard let self = self, self.isEnabled else { return }
            self.delegate?.editToolbarDidRequestFadeIn(self)
        }
        fadeOutButton.onClick = { [weak self] in
            guard let self = self, self.isEnabled else { return }
            self.delegate?.editToolbarDidRequestFadeOut(self)
        }
        
        // 初始禁用
        setEnabled(false)
    }
    
    // MARK: - Public
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        let alpha: CGFloat = enabled ? 1.0 : 0.35
        [trimButton, normalizeButton, fadeInButton, fadeOutButton].forEach { btn in
            btn.alphaValue = alpha
            btn.isUserInteractionEnabled = enabled
        }
    }
}

// MARK: - EditToolbarButton
/// 编辑工具栏内的小按钮
private class EditToolbarButton: NSView {
    var onClick: (() -> Void)?
    var isUserInteractionEnabled: Bool = true
    
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var isHovering = false
    
    init(title: String, symbol: String) {
        super.init(frame: .zero)
        
        wantsLayer = true
        layer?.cornerRadius = IndustrialCornerRadius.sm
        
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            iconView.image = img
            iconView.contentTintColor = IndustrialColors.onSurfaceVariant
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)
        }
        
        label.stringValue = title
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = IndustrialColors.onSurfaceVariant
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(tracking)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func mouseEntered(with event: NSEvent) {
        guard isUserInteractionEnabled else { return }
        isHovering = true
        layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func mouseDown(with event: NSEvent) {
        guard isUserInteractionEnabled else { return }
        layer?.backgroundColor = IndustrialColors.surfaceContainerHighest.cgColor
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isUserInteractionEnabled else { return }
        layer?.backgroundColor = isHovering ? IndustrialColors.surfaceContainerHigh.cgColor : NSColor.clear.cgColor
        if isHovering { onClick?() }
    }
}
