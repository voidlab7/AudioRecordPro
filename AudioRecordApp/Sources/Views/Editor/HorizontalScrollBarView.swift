import Cocoa

// MARK: - HorizontalScrollBarDelegate
protocol HorizontalScrollBarDelegate: AnyObject {
    /// 用户拖动 thumb 或点击轨道时触发
    func scrollBar(_ scrollBar: HorizontalScrollBarView, didScrollTo position: CGFloat)
}

// MARK: - HorizontalScrollBarView
/// 自定义横向滚动条（波形区下方）— 显示当前可见范围占总时长的比例
class HorizontalScrollBarView: NSView {

    // MARK: - Constants
    static let barHeight: CGFloat = 12       // 总高度（含 padding）
    static let trackHeight: CGFloat = 4      // 轨道高度
    static let minThumbWidth: CGFloat = 40   // 最小 thumb 宽度

    // MARK: - Properties
    weak var delegate: HorizontalScrollBarDelegate?

    /// 可见范围占总时长的比例（0.0 ~ 1.0），决定 thumb 宽度
    var visibleRatio: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }

    /// 滚动位置（0.0 ~ 1.0），决定 thumb 在轨道中的位置
    var scrollPosition: CGFloat = 0.0 {
        didSet { needsDisplay = true }
    }

    /// 是否显示（zoomLevel > 1.0 时显示）
    var isBarVisible: Bool = false {
        didSet {
            if isBarVisible != oldValue {
                animateVisibility(isBarVisible)
            }
        }
    }

    // 交互状态
    private var isDragging: Bool = false
    private var dragStartX: CGFloat = 0
    private var dragStartPosition: CGFloat = 0

    // Track 区域
    private var trackRect: NSRect {
        let trackY = (bounds.height - Self.trackHeight) / 2
        return NSRect(x: IndustrialSpacing.sm, y: trackY,
                      width: bounds.width - IndustrialSpacing.sm * 2, height: Self.trackHeight)
    }

    // Thumb 计算
    private var thumbRect: NSRect {
        let track = trackRect
        let thumbWidth = max(Self.minThumbWidth, track.width * visibleRatio)
        let availableWidth = track.width - thumbWidth
        let thumbX = track.minX + availableWidth * min(1.0, max(0.0, scrollPosition))
        let thumbY = (bounds.height - 6) / 2  // thumb 比轨道稍高
        return NSRect(x: thumbX, y: thumbY, width: thumbWidth, height: 6)
    }

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
        layer?.backgroundColor = NSColor.clear.cgColor
        alphaValue = 0  // 初始隐藏

        setAccessibilityRole(.scrollBar)
        setAccessibilityLabel("时间位置")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let track = trackRect
        let thumb = thumbRect

        // 绘制轨道
        let trackColor = IndustrialColors.outlineVariant.withAlphaComponent(0.3)
        let trackPath = NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2)
        trackColor.setFill()
        trackPath.fill()

        // 绘制 Thumb
        let thumbColor = isDragging
            ? IndustrialColors.primary.withAlphaComponent(0.8)
            : IndustrialColors.primary.withAlphaComponent(0.6)
        let thumbPath = NSBezierPath(roundedRect: thumb, xRadius: 2, yRadius: 2)
        thumbColor.setFill()
        thumbPath.fill()
    }

    // MARK: - Mouse Interaction

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let thumb = thumbRect

        if thumb.contains(location) {
            // 开始拖动 thumb
            isDragging = true
            dragStartX = location.x
            dragStartPosition = scrollPosition
            needsDisplay = true
        } else if trackRect.contains(location) {
            // 点击轨道空白区：跳到该位置
            let track = trackRect
            let thumbW = max(Self.minThumbWidth, track.width * visibleRatio)
            let availableWidth = track.width - thumbW
            guard availableWidth > 0 else { return }
            let newPosition = (location.x - track.minX - thumbW / 2) / availableWidth
            scrollPosition = max(0, min(1, newPosition))
            needsDisplay = true
            delegate?.scrollBar(self, didScrollTo: scrollPosition)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let location = convert(event.locationInWindow, from: nil)
        let deltaX = location.x - dragStartX
        let track = trackRect
        let thumbW = max(Self.minThumbWidth, track.width * visibleRatio)
        let availableWidth = track.width - thumbW
        guard availableWidth > 0 else { return }

        let deltaPosition = deltaX / availableWidth
        scrollPosition = max(0, min(1, dragStartPosition + deltaPosition))
        needsDisplay = true
        delegate?.scrollBar(self, didScrollTo: scrollPosition)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
    }

    // MARK: - Hover Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .mouseMoved],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if thumbRect.contains(location) || isDragging {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Visibility Animation

    private func animateVisibility(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = IndustrialAnimation.long
            context.timingFunction = IndustrialAnimation.timingFunction
            self.animator().alphaValue = visible ? 1.0 : 0.0
        }
    }

    // MARK: - Accessibility

    override func accessibilityValue() -> Any? {
        return "位置 \(Int(scrollPosition * 100))%"
    }
}
