import Cocoa

// MARK: - PlayheadOverlayView
/// 播放头/游标线 — 覆盖整个轨道区（UI-037：ruler 顶 → 容器底贯穿）。
/// x 坐标公式与 TimeRulerView.timeToPixel 完全一致（基于 headerWidth 偏移），
/// 保证 playhead 与 ruler 时间刻度"精准卡住"。
///
/// UI-030 剪映风格：
/// - 白色细竖线从容器顶贯穿到容器底（UI-037：含轨道带上下留白区）
/// - 圆角矩形手柄恒在顶部、骑在 ruler 行内（老板 10-27 强调：严禁画在底部）
/// - 播放头在 0:00 与末端时整体内收 clamp，手柄完整可见不越界
/// UI-037: 纯显示层，hitTest 恒穿透——不拦截波形行（seek/选区/音量线拖拽）
/// 与容器空白区（seek）的鼠标事件。
/// 坐标惯例：本视图非翻转（y-up），视觉顶部 = y 大。
class PlayheadOverlayView: NSView {

    // MARK: - Public Configuration

    /// 左侧轨道头宽度 — 跳过此区域（与 TimeRulerView 保持一致）
    var headerWidth: CGFloat = 80

    /// ruler 高度（手柄骑在 ruler 行内；UI-045 默认值随 mockup 标尺 22→24）
    var rulerHeight: CGFloat = 24

    /// 当前可见时间起点（秒）
    var visibleStartTime: TimeInterval = 0 {
        didSet { if visibleStartTime != oldValue { needsDisplay = true } }
    }

    /// 当前可见时间长度（秒）
    var visibleDuration: TimeInterval = 1 {
        didSet { if visibleDuration != oldValue { needsDisplay = true } }
    }

    /// 当前播放头位置（秒）
    var playbackTime: TimeInterval = 0 {
        didSet { if playbackTime != oldValue { needsDisplay = true } }
    }

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
        // 透明背景 — 只画 playhead 本身
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// UI-037: 纯显示层 — 鼠标事件全部穿透到下层（波形行 / 标尺 / 容器空白区）。
    /// 否则 overlay 覆盖整个轨道区会拦截波形行的 seek/选区/音量线拖拽。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 一次性更新所有 viewport 相关属性（避免多次 invalidating）
    func update(playbackTime: TimeInterval, visibleStartTime: TimeInterval, visibleDuration: TimeInterval) {
        let changed = self.playbackTime != playbackTime ||
                      self.visibleStartTime != visibleStartTime ||
                      self.visibleDuration != visibleDuration
        self.playbackTime = playbackTime
        self.visibleStartTime = visibleStartTime
        self.visibleDuration = visibleDuration
        if changed { needsDisplay = true }
    }

    // MARK: - Coordinate Transform
    // 与 TimeRulerView.timeToPixel 完全一致：
    //   x = headerWidth + (t - visibleStartTime) / visibleDuration * (bounds.width - headerWidth)
    // 这保证 playhead 与 ruler 刻度"精准卡住"。

    private var playheadX: CGFloat {
        let timeWidth = bounds.width - headerWidth
        guard timeWidth > 0, visibleDuration > 0 else { return headerWidth }
        let ratio = CGFloat((playbackTime - visibleStartTime) / visibleDuration)
        return headerWidth + ratio * timeWidth
    }

    // MARK: - Drawing (UI-030 剪映风格 · UI-045 手柄对齐 mockup 3:303)

    /// 手柄宽（mockup 8 ×1.111 → 9）
    private static let handleW: CGFloat = 9
    /// 手柄高（mockup 12.5 ×1.111 → 14）
    private static let handleH: CGFloat = 14
    /// 手柄顶部距容器顶（mockup y=1）
    private static let handleTopGap: CGFloat = 1
    /// 圆角半径
    private static let handleRadius: CGFloat = 3

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 仅在可见时间范围内绘制
        guard playbackTime >= visibleStartTime,
              playbackTime <= visibleStartTime + visibleDuration else { return }

        let x = playheadX
        let topY = bounds.height

        // 0:00 / 末端不越界：手柄半宽内收 clamp，竖线与手柄一起移动不分离
        let halfHandle = Self.handleW / 2
        let drawX = min(max(x, headerWidth + halfHandle), bounds.width - halfHandle)

        let rectTop = topY - Self.handleTopGap                 // 手柄顶（贴容器顶内侧 1px）
        let rectBottom = rectTop - Self.handleH                // 手柄底

        // 1) 白色细竖线 — 从手柄底边中点贯穿到容器底部
        let line = NSBezierPath()
        line.lineWidth = 1.25
        line.move(to: NSPoint(x: drawX, y: 0))
        line.line(to: NSPoint(x: drawX, y: rectBottom))
        IndustrialColors.textPrimary.withAlphaComponent(0.92).setStroke()
        line.stroke()

        // 2) 手柄 — 骑在 ruler 行：实心圆角矩形（mockup 3:303 fills 白 0.95，无描边）
        let rect = NSRect(x: drawX - halfHandle,
                          y: rectBottom,
                          width: Self.handleW,
                          height: Self.handleH)
        let handle = NSBezierPath(roundedRect: rect, xRadius: Self.handleRadius, yRadius: Self.handleRadius)
        IndustrialColors.textPrimary.withAlphaComponent(0.95).setFill()
        handle.fill()
    }
}
