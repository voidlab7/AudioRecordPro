import Cocoa

/// Right-side vertical level meter card — L/R channels, segmented LED style, dB scale, peak hold
/// REQ-2.0-04: Full UI optimization with professional audio tool standards
/// Layout (left to right): dB scale text + tick lines + LED bar L + gap + LED bar R
class LevelMeterCardView: NSView {
    
    // MARK: - Properties
    private var leftLevel: Float = 0.0
    private var rightLevel: Float = 0.0
    private var hasAudioData = false
    private var leftPeak: Float = 0.0
    private var rightPeak: Float = 0.0
    private var peakHoldTime: TimeInterval = 1.5  // REQ: 1.5s hold time
    private var peakDecayRate: Float = 0.08       // REQ: easeOut decay (exponential)
    private var leftPeakTimestamp: Date?
    private var rightPeakTimestamp: Date?
    
    // Clip indicator state
    private var clipTriggered: Bool = false
    private var clipTimestamp: Date?
    private let clipHoldDuration: TimeInterval = 3.0  // REQ: 3s clip hold
    
    // dB scale range — REQ: maxDB = 0 (0dB at top)
    private let minDB: Float = -60
    private let maxDB: Float = 0
    
    // Layout constants — REQ: optimized for 80px card width
    private let barWidth: CGFloat = 10          // UI-003 v3: Figma 规格 10px 条宽
    private let fillWidth: CGFloat = 6          // UI-003 v3: Figma 规格 6px 信号填充宽
    private let barGap: CGFloat = 4             // REQ: 4px L/R gap
    private let labelAreaWidth: CGFloat = 20    // REQ: 20px dB label area
    private let tickLength: CGFloat = 4         // Tick line length
    private let tickGap: CGFloat = 2            // Tick to bar gap
    private let topPadding: CGFloat = 24        // REQ: 24px top padding
    private let bottomPadding: CGFloat = 28     // REQ: 28px bottom (for peak value)
    private let horizontalPadding: CGFloat = 6  // REQ: 6px left/right padding

    // Clip indicator size
    private let clipSize: CGFloat = 6           // REQ: 6x6px clip indicator

    // UI-003 v3: Figma 电平表渐变（无红段，顶即黄）#10B981→#34D399@50%→#FBBF24
    private let gradBottom = NSColor(hex: "#10B981")
    private let gradMid = NSColor(hex: "#34D399")
    private let gradTop = NSColor(hex: "#FBBF24")
    private let ledRed = NSColor(hex: "#FF3B30")  // 仅用于实际削波指示（UI-002：红色只用于实际峰值/削波）
    
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
        layer?.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
        layer?.cornerRadius = IndustrialCornerRadius.sm
        layer?.borderWidth = 0
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        setAccessibilityLabel("未监测".localized)
    }
    
    // MARK: - Public Methods
    
    func updateLevels(left: Float, right: Float) {
        hasAudioData = true
        setAccessibilityLabel("实时电平".localized)
        let now = Date()
        let targetLeft = max(0, min(1, left))
        let targetRight = max(0, min(1, right))
        
        let attackRate: Float = 0.8
        let releaseRate: Float = 0.12
        
        leftLevel += (targetLeft > leftLevel)
            ? (targetLeft - leftLevel) * attackRate
            : (targetLeft - leftLevel) * releaseRate
        rightLevel += (targetRight > rightLevel)
            ? (targetRight - rightLevel) * attackRate
            : (targetRight - rightLevel) * releaseRate
        
        updatePeak(level: leftLevel, peak: &leftPeak, timestamp: &leftPeakTimestamp, now: now)
        updatePeak(level: rightLevel, peak: &rightPeak, timestamp: &rightPeakTimestamp, now: now)
        
        // REQ: Clip detection — trigger when level >= 1.0 (0dB)
        if leftLevel >= 1.0 || rightLevel >= 1.0 {
            clipTriggered = true
            clipTimestamp = now
        }
        
        // REQ: Auto-clear clip after 3 seconds
        if clipTriggered, let ts = clipTimestamp, now.timeIntervalSince(ts) > clipHoldDuration {
            clipTriggered = false
            clipTimestamp = nil
        }
        
        needsDisplay = true
    }
    
    func updateLevel(_ level: Float) {
        updateLevels(left: level, right: level)
    }
    
    func reset() {
        hasAudioData = false
        setAccessibilityLabel("未监测".localized)
        leftLevel = 0; rightLevel = 0
        leftPeak = 0; rightPeak = 0
        leftPeakTimestamp = nil; rightPeakTimestamp = nil
        clipTriggered = false; clipTimestamp = nil
        needsDisplay = true
    }
    
    // MARK: - Mouse Events (Clip reset)
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let clipRect = clipIndicatorRect()
        // REQ: Expand click area to 12x12 for usability
        let expandedClipRect = clipRect.insetBy(dx: -3, dy: -3)
        if expandedClipRect.contains(location) && clipTriggered {
            clipTriggered = false
            clipTimestamp = nil
            needsDisplay = true
            return
        }
        super.mouseDown(with: event)
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // macOS coordinate system: y=0 at bottom, y increases upward
        // meterBottom = top of meter area (higher y), meterTop = bottom of meter area (lower y)
        let meterTop = bottomPadding          // bottom of meter bars (lower y)
        let meterBottom = bounds.height - topPadding  // top of meter bars (higher y)
        let meterHeight = meterBottom - meterTop
        guard meterHeight > 20 else { return }
        
        // Calculate layout: content centered with horizontal padding
        let totalBarsWidth = barWidth * 2 + barGap
        let totalContentWidth = labelAreaWidth + tickLength + tickGap + totalBarsWidth
        let contentStartX = (bounds.width - totalContentWidth) / 2
        let barsStartX = contentStartX + labelAreaWidth + tickLength + tickGap
        
        // 0. UI-003 v3: 顶部 DB METER 标题（9px mono #A3A3A3，Figma §3）
        drawTitle()
        
        // 1. Draw background slots (Figma: 10px r2 fill #171717@0.90 stroke white@0.10)
        drawBarSlot(x: barsStartX, meterTop: meterTop, meterHeight: meterHeight)
        drawBarSlot(x: barsStartX + barWidth + barGap, meterTop: meterTop, meterHeight: meterHeight)
        
        // 2. Draw L/R channel gradient fills (fill from bottom up)
        if hasAudioData {
            drawGradientChannel(level: leftLevel, peak: leftPeak, x: barsStartX, meterTop: meterTop, meterHeight: meterHeight)
            drawGradientChannel(level: rightLevel, peak: rightPeak, x: barsStartX + barWidth + barGap, meterTop: meterTop, meterHeight: meterHeight)
        }

        // 3. Draw dB scale (text + tick lines)
        drawDBScale(labelX: contentStartX, tickEndX: barsStartX - tickGap, meterTop: meterTop, meterBottom: meterBottom, meterHeight: meterHeight)
        
        // 4. Draw L/R labels below bars
        drawChannelLabels(barsStartX: barsStartX, meterTop: meterTop)
        
        if hasAudioData {
            drawPeakValue(barsStartX: barsStartX, meterTop: meterTop)
            drawClipIndicator(barsStartX: barsStartX, meterBottom: meterBottom)
        }
        // UI-008（2026-10-12 老板定）：「未监测」浮层文字已删——未监测态用置灰空条表达，AX 标签保留
    }
    
    // MARK: - Title
    
    /// UI-003 v3: DB METER title — 9px mono #A3A3A3 centered at top (Figma §3)
    private func drawTitle() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor(hex: "#A3A3A3").withAlphaComponent(0.9)
        ]
        let text = "DB METER"
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: bounds.height - size.height - 6), withAttributes: attrs)
    }
    
    // MARK: - Bar Slot & Gradient Fill (UI-003 v3 Figma 规格)
    
    /// Figma §3: 条 10px 宽 r=2，fill #171717@0.90，stroke white@0.10
    private func drawBarSlot(x: CGFloat, meterTop: CGFloat, meterHeight: CGFloat) {
        let slotRect = NSRect(x: x, y: meterTop, width: barWidth, height: meterHeight)
        let path = NSBezierPath(roundedRect: slotRect, xRadius: 2, yRadius: 2)
        NSColor(hex: "#171717").withAlphaComponent(0.90).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    
    /// Figma §3: 信号填充 6px 宽，渐变 #10B981→#34D399@50%→#FBBF24（无红段，顶即黄）
    private func drawGradientChannel(level: Float, peak: Float, x: CGFloat, meterTop: CGFloat, meterHeight: CGFloat) {
        let fillHeight = CGFloat(level) * meterHeight
        let fillX = x + (barWidth - fillWidth) / 2
        
        if fillHeight > 0 {
            let clipPath = NSBezierPath(roundedRect: NSRect(x: fillX, y: meterTop + 1, width: fillWidth, height: fillHeight), xRadius: 2, yRadius: 2)
            NSGraphicsContext.saveGraphicsState()
            clipPath.addClip()
            // 渐变绘制在整个槽高上（颜色位置对应 dB 范围），clip 只显示底部填充
            let gradient = NSGradient(colorsAndLocations:
                (gradBottom, 0.0),
                (gradMid, 0.5),
                (gradTop, 1.0)
            )
            gradient?.draw(in: NSRect(x: fillX, y: meterTop + 1, width: fillWidth, height: meterHeight - 2), angle: 90)
            NSGraphicsContext.restoreGraphicsState()
        }
        
        // 峰值保持横线（白 / 顶部峰值转黄，无红）
        if peak > 0.01 {
            drawPeakHoldLine(peak: peak, x: x, meterTop: meterTop, meterHeight: meterHeight)
        }
    }
    
    /// Peak hold line — 2px，白@0.9；峰值进入顶部 5% 区转 #FBBF24
    private func drawPeakHoldLine(peak: Float, x: CGFloat, meterTop: CGFloat, meterHeight: CGFloat) {
        let peakY = meterTop + CGFloat(peak) * meterHeight
        let peakColor: NSColor = peak >= 0.95 ? gradTop : NSColor.white.withAlphaComponent(0.9)
        peakColor.setStroke()
        let peakLine = NSBezierPath()
        peakLine.lineWidth = 2.0
        peakLine.move(to: NSPoint(x: x + 1, y: peakY))
        peakLine.line(to: NSPoint(x: x + barWidth - 1, y: peakY))
        peakLine.stroke()
    }
    
    // MARK: - dB Scale Drawing
    
    /// Draw dB scale with 0dB at top; reserve red for actual peaks and clipping.
    private func drawDBScale(labelX: CGFloat, tickEndX: CGFloat, meterTop: CGFloat, meterBottom: CGFloat, meterHeight: CGFloat) {
        // REQ: Complete scale sequence [0, -3, -6, -12, -24, -48]
        let dbValues: [Float] = [0, -3, -6, -12, -24, -48]
        
        let tickColor = IndustrialColors.onSurfaceVariant.withAlphaComponent(0.2)
        
        for db in dbValues {
            // 0dB at top (meterBottom), -60dB at bottom (meterTop)
            // normalized: 0dB → 1.0, -60dB → 0.0
            let normalized = (db - minDB) / (maxDB - minDB)
            let y = meterTop + CGFloat(normalized) * meterHeight
            
            let labelColor = IndustrialColors.onSurfaceVariant.withAlphaComponent(hasAudioData ? 0.55 : 0.3)
            
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: labelColor
            ]
            
            // dB text (right-aligned within label area)
            let label = db == 0 ? " 0" : "\(Int(db))"
            let size = label.size(withAttributes: labelAttrs)
            let textX = labelX + labelAreaWidth - size.width - 1
            label.draw(at: NSPoint(x: textX, y: y - size.height / 2), withAttributes: labelAttrs)
            
            // Tick line
            tickColor.setStroke()
            let tick = NSBezierPath()
            tick.lineWidth = 0.5
            tick.move(to: NSPoint(x: labelX + labelAreaWidth, y: y))
            tick.line(to: NSPoint(x: tickEndX, y: y))
            tick.stroke()
        }
    }
    
    // MARK: - Channel Labels
    
    /// Draw L/R labels below bars — UI-003 v3: Figma §3 mono 10px w700 #A3A3A3
    private func drawChannelLabels(barsStartX: CGFloat, meterTop: CGFloat) {
        let labelColor = NSColor(hex: "#A3A3A3").withAlphaComponent(hasAudioData ? 0.95 : 0.35)
        let lAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: labelColor
        ]
        let rAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: labelColor
        ]
        
        let lSize = "L".size(withAttributes: lAttrs)
        let rSize = "R".size(withAttributes: rAttrs)
        
        // REQ: 6px gap between label and bar bottom — labels below bars
        let labelY = meterTop - 6 - lSize.height
        "L".draw(at: NSPoint(x: barsStartX + (barWidth - lSize.width) / 2, y: labelY), withAttributes: lAttrs)
        "R".draw(at: NSPoint(x: barsStartX + barWidth + barGap + (barWidth - rSize.width) / 2, y: labelY), withAttributes: rAttrs)
    }
    
    // MARK: - Peak Value Display
    
    /// Draw peak dB value at bottom (REQ: monospacedDigit 9px, dynamic color)
    private func drawPeakValue(barsStartX: CGFloat, meterTop: CGFloat) {
        // REQ: Display higher of L/R peak
        let peakLevel = max(leftLevel, rightLevel)
        guard peakLevel > 0.001 else { return }
        
        // Convert level to dB
        let peakDB: Float
        if peakLevel <= 0 {
            peakDB = -60
        } else {
            peakDB = 20 * log10(peakLevel)
        }
        let clampedDB = max(-60, min(0, peakDB))
        
        // REQ: Color based on level — UI-003 v3 无红段：危险 #FBBF24、偏高 #34D399、正常灰
        let valueColor: NSColor
        if clampedDB > -3 {
            valueColor = gradTop           // Danger (> -3dB) — 顶黄（无红段）
        } else if clampedDB > -6 {
            valueColor = gradMid           // High (-6 ~ -3dB)
        } else {
            valueColor = IndustrialColors.onSurfaceVariant  // Normal (< -6dB)
        }
        
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: valueColor
        ]
        
        // Format: -XX.X
        let valueText = String(format: "%.1f", clampedDB)
        let valueSize = valueText.size(withAttributes: valueAttrs)
        
        // Center below the bars in bottom padding area
        let centerX = barsStartX + barWidth + barGap / 2
        let valueX = centerX - valueSize.width / 2
        let valueY: CGFloat = 6  // Near the very bottom of the view
        
        valueText.draw(at: NSPoint(x: valueX, y: valueY), withAttributes: valueAttrs)
    }
    
    // MARK: - Clip Indicator
    
    /// Calculate clip indicator rect (at top of bars)
    private func clipIndicatorRect() -> NSRect {
        let meterBottom = bounds.height - topPadding
        let totalBarsWidth = barWidth * 2 + barGap
        let totalContentWidth = labelAreaWidth + tickLength + tickGap + totalBarsWidth
        let contentStartX = (bounds.width - totalContentWidth) / 2
        let barsStartX = contentStartX + labelAreaWidth + tickLength + tickGap
        let centerX = barsStartX + barWidth + barGap / 2
        // Clip indicator sits just above the top of the meter bars
        return NSRect(x: centerX - clipSize / 2, y: meterBottom + 2, width: clipSize, height: clipSize)
    }
    
    /// Draw Clip indicator (REQ: 6x6 red square, 3s hold, click to reset)
    private func drawClipIndicator(barsStartX: CGFloat, meterBottom: CGFloat) {
        let centerX = barsStartX + barWidth + barGap / 2
        // Clip indicator at top of meter area
        let clipRect = NSRect(x: centerX - clipSize / 2, y: meterBottom + 2, width: clipSize, height: clipSize)
        
        if clipTriggered {
            // REQ: Bright red when triggered
            ledRed.setFill()
        } else {
            IndustrialColors.onSurfaceVariant.withAlphaComponent(0.15).setFill()
        }
        NSBezierPath(rect: clipRect).fill()
    }
    
    // MARK: - Private Helpers
    
    /// Update peak with easeOut decay (REQ: non-linear decay)
    private func updatePeak(level: Float, peak: inout Float, timestamp: inout Date?, now: Date) {
        if level > peak {
            peak = level
            timestamp = now
        } else if let ts = timestamp, now.timeIntervalSince(ts) > peakHoldTime {
            // REQ: easeOut decay (exponential, not linear)
            peak *= 0.92
            if peak < 0.01 {
                peak = 0
                timestamp = nil
            }
        }
    }
}
