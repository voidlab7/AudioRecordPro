import Cocoa

// MARK: - 实时转写文本条（FEAT-001 S1）
//
// 录制中显示在主窗口正下方的非激活浮动条：
// - 定稿文本（黑色/主色）+ volatile 中间结果（次要色）
// - S2 会把这段文本升级为完整「文稿」页签；本面板是 S1 的最小可视层

final class LiveTranscriptPanel: NSPanel {

    private let finalizedLabel = NSTextField(labelWithString: "")
    private let volatileLabel = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 1200, height: 120))
        content.material = .hudWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 10

        // 标题
        let title = NSTextField(labelWithString: "实时转写".localized)
        title.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        title.textColor = NSColor.secondaryLabelColor

        // volatile（引擎中间结果，灰显）
        volatileLabel.font = NSFont.systemFont(ofSize: 13)
        volatileLabel.textColor = NSColor.secondaryLabelColor
        volatileLabel.lineBreakMode = .byWordWrapping
        volatileLabel.maximumNumberOfLines = 2

        // 定稿文本（主色，可滚动）
        finalizedLabel.font = NSFont.systemFont(ofSize: 13)
        finalizedLabel.textColor = NSColor.labelColor
        finalizedLabel.lineBreakMode = .byTruncatingTail
        finalizedLabel.maximumNumberOfLines = 3

        let stack = NSStackView(views: [title, volatileLabel, finalizedLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // 长文本从底部对齐（最新内容可见）
        stack.distribution = .gravityAreas

        contentView = content
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 0),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: 0),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 0),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 0),
        ])
    }

    /// 追加到主窗口正下方（宽度对齐窗口）
    func show(for window: NSWindow?) {
        guard let window else { return }
        let frame = window.frame
        let height: CGFloat = 120
        setFrame(NSRect(x: frame.minX, y: frame.minY - height - 8, width: frame.width, height: height), display: true)
        alphaValue = 0
        orderFrontRegardless()
        animator().alphaValue = 1
    }

    func update(finalized: String, volatile: String) {
        finalizedLabel.stringValue = finalized
        volatileLabel.stringValue = volatile
    }

    func dismiss() {
        animator().alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.orderOut(nil)
        }
    }
}
