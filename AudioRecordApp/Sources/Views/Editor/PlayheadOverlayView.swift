import Cocoa

// MARK: - PlayheadOverlayView
/// 播放头/游标线 — 覆盖在 ruler + 所有 track 行上方。
/// x 坐标公式与 TimeRulerView.timeToPixel 完全一致（基于 headerWidth 偏移），
/// 保证 playhead 与 ruler 时间刻度"精准卡住"。
///
/// 关键点：
/// - 三角形手柄画在 ruler 底部（剪映风格，倒三角指向波形）
/// - 垂直线从 ruler 底部一直贯穿到 trackContainer 底部（横跨多轨时也一致）
class PlayheadOverlayView: NSView {

    // MARK: - Public Configuration

    /// 左侧轨道头宽度 — 跳过此区域（与 TimeRulerView 保持一致）
    var headerWidth: CGFloat = 80

    /// ruler 高度（手柄顶部锚到 ruler 底部）
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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 仅在可见时间范围内绘制
        guard playbackTime >= visibleStartTime,
              playbackTime <= visibleStartTime + visibleDuration else { return }

        let x = playheadX

        // 1) 三角形手柄 — 倒三角，顶部贴 ruler 底部（剪映风格）
        let handleTopY: CGFloat = rulerHeight - 1   // ruler 底部内侧 1px
        let handleSize: CGFloat = 8
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: x, y: handleTopY))
        triangle.line(to: NSPoint(x: x - handleSize / 2, y: handleTopY - handleSize))
        triangle.line(to: NSPoint(x: x + handleSize / 2, y: handleTopY - handleSize))
        triangle.close()
        IndustrialColors.waveformAccent.setFill()
        triangle.fill()

        // 2) 垂直线 — 从 ruler 底部一直贯穿到 view 底部（横跨所有轨道行）
        let lineStartY: CGFloat = handleTopY - handleSize
        let line = NSBezierPath()
        line.lineWidth = 1.5
        line.move(to: NSPoint(x: x, y: lineStartY))
        line.line(to: NSPoint(x: x, y: bounds.height))
        IndustrialColors.waveformAccent.setStroke()
        line.stroke()
    }
}
