import Cocoa
import Foundation

/// 电平表叠加组件 — 纵向 L/R 柱状图，绿→红渐变 + 峰值保持横线
/// 参考剪映电平表：dB 刻度 + 颜色渐变 + 峰值白线
class LevelMetersOverlay: NSView {
    
    // MARK: - Properties
    private var leftLevel: Float = 0.0
    private var rightLevel: Float = 0.0
    private var leftPeak: Float = 0.0
    private var rightPeak: Float = 0.0
    private var peakHoldTime: TimeInterval = 1.0
    private var peakDecayRate: Float = 0.03
    private var leftPeakTimestamp: Date?
    private var rightPeakTimestamp: Date?
    
    // dB 刻度范围
    private let minDB: Float = -60
    private let maxDB: Float = 6
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    // MARK: - Public Methods
    
    func updateLevels(left: Float, right: Float) {
        let now = Date()
        let targetLeft = max(0, min(1, left))
        let targetRight = max(0, min(1, right))
        
        // 快速攻击（立即跟随上升）+ 柔和释放（缓慢下降）
        let attackRate: Float = 0.8    // 上升时快速跟随
        let releaseRate: Float = 0.15  // 下降时平滑衰减
        
        leftLevel += (targetLeft > leftLevel)
            ? (targetLeft - leftLevel) * attackRate
            : (targetLeft - leftLevel) * releaseRate
        rightLevel += (targetRight > rightLevel)
            ? (targetRight - rightLevel) * attackRate
            : (targetRight - rightLevel) * releaseRate
        
        // 峰值保持
        updatePeak(level: leftLevel, peak: &leftPeak, timestamp: &leftPeakTimestamp, now: now)
        updatePeak(level: rightLevel, peak: &rightPeak, timestamp: &rightPeakTimestamp, now: now)
        
        needsDisplay = true
    }
    
    func updateLevel(_ level: Float) {
        updateLevels(left: level, right: level)
    }
    
    func reset() {
        leftLevel = 0; rightLevel = 0
        leftPeak = 0; rightPeak = 0
        leftPeakTimestamp = nil; rightPeakTimestamp = nil
        needsDisplay = true
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let barWidth: CGFloat = 14
        let gap: CGFloat = 4
        let labelWidth: CGFloat = 10
        let totalBarWidth = barWidth * 2 + gap
        let startX = bounds.width - totalBarWidth - 2
        
        // 绘制区域
        let meterTop: CGFloat = 4
        let meterBottom: CGFloat = bounds.height - 18
        let meterHeight = meterBottom - meterTop
        
        guard meterHeight > 10 else { return }
        
        // 背景槽
        let slotColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        slotColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: startX, y: meterTop, width: barWidth, height: meterHeight), xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: NSRect(x: startX + barWidth + gap, y: meterTop, width: barWidth, height: meterHeight), xRadius: 2, yRadius: 2).fill()
        
        // 绘制左右声道
        drawChannel(level: leftLevel, peak: leftPeak, x: startX, barWidth: barWidth, meterTop: meterTop, meterHeight: meterHeight)
        drawChannel(level: rightLevel, peak: rightPeak, x: startX + barWidth + gap, barWidth: barWidth, meterTop: meterTop, meterHeight: meterHeight)
        
        // dB 刻度
        drawDBScale(x: startX - labelWidth - 2, meterTop: meterTop, meterHeight: meterHeight, labelWidth: labelWidth)
        
        // L / R 标签
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.5, alpha: 1.0)
        ]
        "L".draw(at: NSPoint(x: startX + barWidth / 2 - 3, y: meterBottom + 4), withAttributes: labelAttrs)
        "R".draw(at: NSPoint(x: startX + barWidth + gap + barWidth / 2 - 3, y: meterBottom + 4), withAttributes: labelAttrs)
    }
    
    private func drawChannel(level: Float, peak: Float, x: CGFloat, barWidth: CGFloat, meterTop: CGFloat, meterHeight: CGFloat) {
        let fillHeight = CGFloat(level) * meterHeight
        guard fillHeight > 0 else { return }
        
        let fillRect = NSRect(x: x + 1, y: meterTop + 1, width: barWidth - 2, height: fillHeight)
        
        // 绿→黄→红渐变（从下到上）
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.3, alpha: 1.0), 0.0),    // 绿
            (NSColor(calibratedRed: 0.5, green: 0.8, blue: 0.2, alpha: 1.0), 0.5),    // 黄绿
            (NSColor(calibratedRed: 0.9, green: 0.8, blue: 0.1, alpha: 1.0), 0.75),   // 黄
            (NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.15, alpha: 1.0), 1.0)    // 红
        )
        
        // clip 到填充区域
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1).addClip()
        // 渐变绘制在完整高度上（颜色位置对应 dB 范围），但只显示填充部分
        gradient?.draw(in: NSRect(x: x + 1, y: meterTop + 1, width: barWidth - 2, height: meterHeight - 2), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        
        // 峰值保持横线（白色细线）
        if peak > 0.01 {
            let peakY = meterTop + CGFloat(peak) * meterHeight
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let peakLine = NSBezierPath()
            peakLine.lineWidth = 1.5
            peakLine.move(to: NSPoint(x: x + 1, y: peakY))
            peakLine.line(to: NSPoint(x: x + barWidth - 1, y: peakY))
            peakLine.stroke()
        }
    }
    
    private func drawDBScale(x: CGFloat, meterTop: CGFloat, meterHeight: CGFloat, labelWidth: CGFloat) {
        let dbValues: [Float] = [0, -6, -12, -20, -30, -50]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.4, alpha: 1.0)
        ]
        
        for db in dbValues {
            let normalized = (db - minDB) / (maxDB - minDB)
            let y = meterTop + CGFloat(normalized) * meterHeight
            let label = db == 0 ? "0" : "\(Int(db))"
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: x + labelWidth - size.width, y: y - size.height / 2), withAttributes: attrs)
            
            // 小刻度线
            NSColor(calibratedWhite: 0.25, alpha: 1.0).setStroke()
            let tick = NSBezierPath()
            tick.lineWidth = 0.5
            tick.move(to: NSPoint(x: x + labelWidth + 1, y: y))
            tick.line(to: NSPoint(x: x + labelWidth + 3, y: y))
            tick.stroke()
        }
    }
    
    // MARK: - Private
    
    private func updatePeak(level: Float, peak: inout Float, timestamp: inout Date?, now: Date) {
        if level > peak {
            peak = level
            timestamp = now
        } else if let ts = timestamp, now.timeIntervalSince(ts) > peakHoldTime {
            peak = max(0, peak - peakDecayRate)
            if peak <= 0 { timestamp = nil }
        }
    }
}
