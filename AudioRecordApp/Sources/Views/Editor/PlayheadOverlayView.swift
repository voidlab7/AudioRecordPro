import Cocoa

// MARK: - PlayheadOverlayView
/// 播放头/游标线 — 覆盖在 ruler + 所有 track 行上方。
/// x 坐标公式与 TimeRulerView.timeToPixel 完全一致（基于 headerWidth 偏移），
/// 保证 playhead 与 ruler 时间刻度"精准卡住"。
///
/// UI-030 剪映风格：
/// - 白色细竖线从 ruler 贯穿到容器底部
/// - U 形圆角手柄恒在顶部、骑在 ruler 行内（老板 10-27 强调：严禁画在底部）
/// - 播放头在 0:00 与末端时整体内收 clamp，手柄完整可见不越界
/// 坐标惯例：本视图非翻转（y-up），视觉顶部 = y 大。
class PlayheadOverlayView: NSView {

    // MARK: - Public Configuration

    /// 左侧轨道头宽度 — 跳过此区域（与 TimeRulerView 保持一致）
    var headerWidth: CGFloat = 80

    /// ruler 高度（U 形手柄骑在 ruler 行内）
    var rulerHeight: CGFloat = 22

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

    // MARK: - Drawing (UI-030 剪映风格 · UI-033 圆角矩形手柄)

    /// 手柄描边宽
    private static let handleStroke: CGFloat = 3
    /// 圆角矩形半宽（描边中心线）
    private static let handleHalfW: CGFloat = 5.5
    /// 圆角矩形描边中心线高度（顶边→底边）
    private static let handleSqH: CGFloat = 12
    /// 圆角半径
    private static let handleRadius: CGFloat = 4

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 仅在可见时间范围内绘制
        guard playbackTime >= visibleStartTime,
              playbackTime <= visibleStartTime + visibleDuration else { return }

        let x = playheadX
        let topY = bounds.height

        // 0:00 / 末端不越界：手柄半宽内收 clamp，竖线与手柄一起移动不分离
        let halfHandle = Self.handleHalfW + Self.handleStroke / 2
        let drawX = min(max(x, headerWidth + halfHandle), bounds.width - halfHandle)

        let top = topY - Self.handleStroke / 2 - 1            // 顶边描边中心线（贴容器顶内侧）
        let rectBottom = top - Self.handleSqH                 // 矩形底边（描边中心线）

        // 1) 白色细竖线 — 从矩形底边中点贯穿到容器底部（顶端藏在底边描边内）
        let line = NSBezierPath()
        line.lineWidth = 1.25
        line.move(to: NSPoint(x: drawX, y: 0))
        line.line(to: NSPoint(x: drawX, y: rectBottom))
        IndustrialColors.textPrimary.withAlphaComponent(0.92).setStroke()
        line.stroke()

        // 2) 手柄 — 骑在 ruler 行：圆角矩形描边轮廓（UI-033 定稿：老板发参考图，去三角）
        let rect = NSRect(x: drawX - Self.handleHalfW,
                          y: rectBottom,
                          width: Self.handleHalfW * 2,
                          height: Self.handleSqH)
        let handle = NSBezierPath(roundedRect: rect, xRadius: Self.handleRadius, yRadius: Self.handleRadius)
        handle.lineWidth = Self.handleStroke
        IndustrialColors.textPrimary.withAlphaComponent(0.95).setStroke()
        handle.stroke()
    }
}
