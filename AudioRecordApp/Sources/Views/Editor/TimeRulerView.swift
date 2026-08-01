import Cocoa

// MARK: - TimeRulerView
/// 横向贯通的时间刻度尺视图 — 放置在工具栏下方、轨道列表上方。
/// 不在左侧轨道头列（`headerWidth` 区域）绘制刻度，保持轨道头纯净。
/// Viewport（visibleStartTime / visibleDuration）由外部同步（跟随波形缩放/滚动）。
class TimeRulerView: NSView {

    // MARK: - Public Configuration

    /// 左侧轨道头宽度 — 刻度尺跳过此区域（M/S 按钮所在列不绘制）
    var headerWidth: CGFloat = 80

    /// 当前可见时间起点（秒）
    var visibleStartTime: TimeInterval = 0 {
        didSet { if visibleStartTime != oldValue { needsDisplay = true } }
    }

    /// 当前可见时间长度（秒）
    var visibleDuration: TimeInterval = 1 {
        didSet { if visibleDuration != oldValue { needsDisplay = true } }
    }

    /// 刻度步长（秒）— 由外部根据缩放级别计算；nil 时自适应
    var overrideStep: TimeInterval?

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
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// 更新 viewport（同时设置开始和时长，触发一次重绘）
    func updateViewport(start: TimeInterval, duration: TimeInterval) {
        let s = max(0, start)
        let d = max(0.001, duration)
        if visibleStartTime != s || visibleDuration != d {
            visibleStartTime = s
            visibleDuration = d
            needsDisplay = true
        }
    }

    // MARK: - Layout

    /// 实际可绘制刻度的矩形（跳过 headerWidth 区域）
    private var rulerRect: NSRect {
        return NSRect(
            x: headerWidth,
            y: 0,
            width: max(0, bounds.width - headerWidth),
            height: bounds.height
        )
    }

    /// 时间 → 像素
    private func timeToPixel(_ time: TimeInterval) -> CGFloat {
        guard visibleDuration > 0 else { return rulerRect.minX }
        let ratio = CGFloat((time - visibleStartTime) / visibleDuration)
        return rulerRect.minX + ratio * rulerRect.width
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 跳过 headerWidth 区域，背景透明
        guard rulerRect.width > 0, rulerRect.height > 0 else { return }

        // 1) 顶部细线（与设计稿一致：刻度尺底部分割）
        let bottomY: CGFloat = 0
        IndustrialColors.outlineVariant.withAlphaComponent(0.45).setStroke()
        let bottomLine = NSBezierPath()
        bottomLine.lineWidth = 0.5
        bottomLine.move(to: NSPoint(x: rulerRect.minX, y: bottomY))
        bottomLine.line(to: NSPoint(x: rulerRect.maxX, y: bottomY))
        bottomLine.stroke()

        // 2) 计算自适应步长（与 EditorWaveformView 共享策略）
        let pixelsPerSecond = rulerRect.width / CGFloat(max(0.001, visibleDuration))
        let rawStep = Double(80.0 / pixelsPerSecond)
        let step: TimeInterval = overrideStep ?? Self.chooseNiceStep(rawStep)
        let subSteps = Self.chooseSubSteps(step: step)

        // 3) 字体与颜色（与设计稿一致：单色 textTertiary 透明）
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: IndustrialColors.textTertiary.withAlphaComponent(0.68)
        ]
        let tickColor = IndustrialColors.onSurfaceVariant.withAlphaComponent(0.24)
        tickColor.setStroke()

        // 4) 绘制主刻度 + 时间标签 + 子刻度
        let firstTick = ceil(visibleStartTime / step) * step
        var t = firstTick
        while t <= visibleStartTime + visibleDuration {
            let x = timeToPixel(t)
            if x < rulerRect.minX - 1 || x > rulerRect.maxX + 1 {
                t += step
                continue
            }

            // 主刻度线（向下短）
            let mainPath = NSBezierPath()
            mainPath.lineWidth = 1
            mainPath.move(to: NSPoint(x: x, y: 6))
            mainPath.line(to: NSPoint(x: x, y: 0))
            mainPath.stroke()

            // 时间标签（紧贴主刻度右侧）
            let label = Self.formatLabel(time: t, step: step)
            label.draw(at: NSPoint(x: x + 2, y: 8), withAttributes: attrs)

            // 子刻度线（更短）
            let subStep = step / Double(subSteps)
            if subStep > 0 {
                for j in 1..<subSteps {
                    let subTime = t + subStep * Double(j)
                    let subX = timeToPixel(subTime)
                    if subX >= rulerRect.minX && subX <= rulerRect.maxX {
                        let subPath = NSBezierPath()
                        subPath.lineWidth = 1
                        subPath.move(to: NSPoint(x: subX, y: 3))
                        subPath.line(to: NSPoint(x: subX, y: 0))
                        subPath.stroke()
                    }
                }
            }

            t += step
        }
    }

    // MARK: - Step Selection (与 EditorWaveformView 共享策略)

    /// 从 niceSteps 中选第一个 >= rawStep 的值
    private static let niceSteps: [TimeInterval] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]

    private static func chooseNiceStep(_ rawStep: Double) -> TimeInterval {
        for ns in niceSteps {
            if ns >= rawStep { return ns }
        }
        return niceSteps.last ?? 5.0
    }

    /// 每个主刻度之间的子刻度数量
    private static func chooseSubSteps(step: TimeInterval) -> Int {
        if step < 0.1 { return 5 }
        if step <= 0.5 { return 5 }
        if step <= 2 { return 4 }
        if step <= 10 { return 5 }
        if step == 15 { return 3 }
        if step == 30 { return 6 }
        return 5
    }

    /// 时间格式（与 EditorWaveformView 保持一致）
    private static func formatLabel(time: TimeInterval, step: TimeInterval) -> String {
        if step < 0.1 {
            let m = Int(time) / 60
            let s = Int(time) % 60
            let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
            return String(format: "%d:%02d.%03d", m, s, ms)
        } else if step < 1.0 {
            let m = Int(time) / 60
            let s = Int(time) % 60
            let cs = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
            return cs == 0
                ? String(format: "%d:%02d", m, s)
                : String(format: "%d:%02d.%d", m, s, cs)
        } else {
            let m = Int(time) / 60
            let s = Int(time) % 60
            return String(format: "%d:%02d", m, s)
        }
    }
}
