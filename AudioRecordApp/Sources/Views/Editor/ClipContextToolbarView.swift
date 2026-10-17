import Cocoa

// MARK: - ClipContextToolbarDelegate
protocol ClipContextToolbarDelegate: AnyObject {
    func clipContextToolbarDidTap(_ toolbar: ClipContextToolbarView, action: ClipContextToolbarView.Action)
}

// MARK: - ClipContextToolbarView
/// UI-020: Clip 上下文工具条（B 稿 .ctx）— 选中 Clip 后上方浮出
/// 高 34 圆角 8 底 #1D232C 阴影 0 4 16 black@50%；六命令与常驻动作栏双入口等价
class ClipContextToolbarView: NSView {

    // MARK: - Action
    enum Action: String, CaseIterable {
        case trim = "裁剪"
        case split = "切分"
        case silenceTrim = "静音裁剪"
        case normalize = "标准化"
        case fade = "淡入淡出"
        case delete = "删除"
    }

    // MARK: - 轻量 hover 按钮（B 稿 .ctx button：11px / padding 4 9 / 圆角 5 / hover 变底色）
    private final class CtxButton: NSView {
        let action: Action
        var onClick: (() -> Void)?
        var isEnabled: Bool = true { didSet { updateAppearance() } }
        private let label = NSTextField(labelWithString: "")
        private var isHovering = false

        init(action: Action) {
            self.action = action
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 5
            label.stringValue = action.rawValue.localized
            label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            label.textColor = IndustrialColors.textSecondary
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 9),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -9)
            ])
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
            updateAppearance()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private func updateAppearance() {
            label.textColor = isEnabled
                ? (action == .delete ? IndustrialColors.error : IndustrialColors.textSecondary)
                : IndustrialColors.textSecondary.withAlphaComponent(0.35)
            layer?.backgroundColor = (isHovering && isEnabled)
                ? IndustrialColors.surfaceContainerHigh.cgColor
                : NSColor.clear.cgColor
        }

        override func mouseEntered(with event: NSEvent) { isHovering = true; updateAppearance() }
        override func mouseExited(with event: NSEvent) { isHovering = false; updateAppearance() }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            layer?.backgroundColor = IndustrialColors.surface.cgColor
            onClick?()
        }
        override func mouseUp(with event: NSEvent) {
            // 按压态恢复；hover 态由 mouseEntered/Exited 跟踪区自行修正
            updateAppearance()
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: label.intrinsicContentSize.width + 18, height: 24)
        }
    }

    // MARK: - UI
    private var buttons: [Action: CtxButton] = [:]

    // MARK: - Properties
    weak var delegate: ClipContextToolbarDelegate?

    // MARK: - Init
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
        layer?.backgroundColor = IndustrialColors.editorCtxToolbarBg.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = IndustrialColors.borderMuted.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowRadius = 8
        layer?.shadowOffset = NSSize(width: 0, height: -4)  // flipped 坐标下「下方」阴影

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for action in Action.allCases {
            let btn = CtxButton(action: action)
            btn.onClick = { [weak self] in
                self?.delegate?.clipContextToolbarDidTap(self!, action: action)
            }
            buttons[action] = btn
            stack.addArrangedSubview(btn)
        }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
        ])
    }

    // MARK: - Public

    /// UI-020 单子「不做什么」：删除现状无命令 → 置灰（记 TODO 回池）
    func setActionEnabled(_ action: Action, enabled: Bool) {
        buttons[action]?.isEnabled = enabled
    }
}
