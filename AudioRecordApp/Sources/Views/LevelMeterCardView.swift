import Cocoa

/// Right-side vertical level meter card — L/R channels, segmented LED style, dB scale, peak hold
/// REQ-2.0-04: Full UI optimization with professional audio tool standards
/// Layout (left to right): dB scale text + tick lines + LED bar L + gap + LED bar R
class LevelMeterCardView: NSView {
    
    // MARK: - Properties
    private var leftLevel: Float = 0.0
    private var rightLevel: Float = 0.0
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
    private let barWidth: CGFloat = 12          // REQ: 12px bar width
    private let barGap: CGFloat = 4             // REQ: 4px L/R gap
    private let labelAreaWidth: CGFloat = 20    // REQ: 20px dB label area
    private let tickLength: CGFloat = 4         // Tick line length
    private let tickGap: CGFloat = 2            // Tick to bar gap
    private let topPadding: CGFloat = 24        // REQ: 24px top padding
    private let bottomPadding: CGFloat = 28     // REQ: 28px bottom (for peak value)
    private let horizontalPadding: CGFloat = 6  // REQ: 6px left/right padding
    
    // LED segment constants — REQ: segmented LED style
    private let segmentHeight: CGFloat = 3      // REQ: 3px per segment
    private let segmentGap: CGFloat = 1         // REQ: 1px gap between segments
    
    // Clip indicator size
    private let clipSize: CGFloat = 6           // REQ: 6x6px clip indicator
    
    // LED colors — REQ: four-color segments
    private let ledGreen = NSColor(calibratedRed: 0.133, green: 0.773, blue: 0.369, alpha: 1.0)   // #22C55E
    private let ledYellow = NSColor(calibratedRed: 0.961, green: 0.620, blue: 0.043, alpha: 1.0)  // #F59E0B
    private let ledOrange = NSColor(calibratedRed: 0.976, green: 0.451, blue: 0.086, alpha: 1.0)  // #F97316
    private let ledRed = NSColor(calibratedRed: 0.937, green: 0.267, blue: 0.267, alpha: 1.0)     // #EF4444
    
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
    }
    
    // MARK: - Public Methods
    
    func updateLevels(left: Float, right: Float) {
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
        
        // 1. Draw background slots (unfilled LED segments)
        drawBackgroundSegments(x: barsStartX, barWidth: barWidth, meterTop: meterTop, meterHeight: meterHeight)
        drawBackgroundSegments(x: barsStartX + barWidth + barGap, barWidth: barWidth, meterTop: meterTop, meterHeight: meterHeight)
        
        // 2. Draw L/R channel LED segments (fill from bottom up)
        drawLEDChannel(level: leftLevel, peak: leftPeak, x: barsStartX, barWidth: barWidth, meterTop: meterTop, meterHeight: meterHeight)
        drawLEDChannel(level: rightLevel, peak: rightPeak, x: barsStartX + barWidth + barGap, barWidth: barWidth, meterTop: meterTop, meterHeight: meterHeight)
        
        // 3. Draw dB scale (text + tick lines)
        drawDBScale(labelX: contentStartX, tickEndX: barsStartX - tickGap, meterTop: meterTop, meterBottom: meterBottom, meterHeight: meterHeight)
        
        // 4. Draw L/R labels below bars
        drawChannelLabels(barsStartX: barsStartX, meterTop: meterTop)
        
        // 5. Draw peak value display in bottom padding area
        drawPeakValue(barsStartX: barsStartX, meterTop: meterTop)
        
        // 6. Draw Clip indicator at top of bars
        drawClipIndicator(barsStartX: barsStartX, meterBottom: meterBottom)
    }
    
    // MARK: - LED Segment Drawing
    
    /// Draw unfilled background segments (REQ: white @ 0.04)
    private func drawBackgroundSegments(x: CGFloat, barWidth: CGFloat, meterTop: CGFloat, meterHeight: CGFloat) {
        let segmentStride = segmentHeight + segmentGap
        let segmentCount = Int(meterHeight / segmentStride)
        let bgColor = NSColor.white.withAlphaComponent(0.04)
        
        for i in 0..<segmentCount {
            // Segments drawn from bottom (meterTop) upward
            let segY = meterTop + CGFloat(i) * segmentStride
            let segRect = NSRect(x: x + 1, y: segY, width: barWidth - 2, height: segmentHeight)
            bgColor.setFill()
            NSBezierPath(rect: segRect).fill()
        }
    }
    
    /// Draw filled LED segments with four-color gradient (REQ: segmented LED style)
    /// Segments fill from bottom to top: index 0 = bottom (green), high index = top (red)
    private func drawLEDChannel(level: Float, peak: Float, x: CGFloat, barWidth: CGFloat, meterTop: CGFloat, meterHeight: CGFloat) {
        let segmentStride = segmentHeight + segmentGap
        let segmentCount = Int(meterHeight / segmentStride)
        let filledSegments = Int(Float(segmentCount) * level)
        
        guard filledSegments > 0 else {
            // Still draw peak hold line if present
            if peak > 0.01 {
                drawPeakHoldLine(peak: peak, x: x, barWidth: barWidth, meterTop: meterTop, meterHeight: meterHeight, segmentCount: segmentCount)
            }
            return
        }
        
        for i in 0..<filledSegments {
            // i=0 is the bottom segment (lowest y), filled upward
            let segY = meterTop + CGFloat(i) * segmentStride
            let segRect = NSRect(x: x + 1, y: segY, width: barWidth - 2, height: segmentHeight)
            
            // Determine color based on segment position (REQ: four-color zones)
            // position 0.0 = bottom (green), position 1.0 = top (red)
            let position = Float(i) / Float(segmentCount)
            let color = colorForPosition(position)
            color.setFill()
            NSBezierPath(rect: segRect).fill()
        }
        
        // Draw peak hold line
        if peak > 0.01 {
            drawPeakHoldLine(peak: peak, x: x, barWidth: barWidth, meterTop: meterTop, meterHeight: meterHeight, segmentCount: segmentCount)
        }
    }
    
    /// Draw peak hold line — REQ: 2px width, dynamic color, easeOut decay
    private func drawPeakHoldLine(peak: Float, x: CGFloat, barWidth: CGFloat, meterTop: CGFloat, meterHeight: CGFloat, segmentCount: Int) {
        // Peak line position: from bottom up
        let peakY = meterTop + CGFloat(peak) * meterHeight
        let peakColor = peakHoldColor(for: peak)
        peakColor.setStroke()
        let peakLine = NSBezierPath()
        peakLine.lineWidth = 2.0  // REQ: 2px peak line
        peakLine.move(to: NSPoint(x: x + 1, y: peakY))
        peakLine.line(to: NSPoint(x: x + barWidth - 1, y: peakY))
        peakLine.stroke()
    }
    
    /// Get LED color for segment position (REQ: green/yellow/orange/red zones)
    /// position 0.0 = bottom, 1.0 = top
    private func colorForPosition(_ position: Float) -> NSColor {
        switch position {
        case 0..<0.6:
            return ledGreen
        case 0.6..<0.8:
            return ledYellow
        case 0.8..<0.95:
            return ledOrange
        default:
            return ledRed
        }
    }
    
    /// Get peak hold line color based on peak position (REQ: dynamic coloring)
    private func peakHoldColor(for position: Float) -> NSColor {
        if position >= 0.95 {
            return ledRed
        } else if position >= 0.8 {
            return ledOrange.withAlphaComponent(0.9)
        } else if position >= 0.6 {
            return ledYellow.withAlphaComponent(0.9)
        } else {
            return NSColor.white.withAlphaComponent(0.8)
        }
    }
    
    // MARK: - dB Scale Drawing
    
    /// Draw dB scale with -3dB critical point (REQ: 0dB at top, red 0dB label)
    private func drawDBScale(labelX: CGFloat, tickEndX: CGFloat, meterTop: CGFloat, meterBottom: CGFloat, meterHeight: CGFloat) {
        // REQ: Complete scale sequence [0, -3, -6, -12, -24, -48]
        let dbValues: [Float] = [0, -3, -6, -12, -24, -48]
        
        let tickColor = IndustrialColors.onSurfaceVariant.withAlphaComponent(0.2)
        
        for db in dbValues {
            // 0dB at top (meterBottom), -60dB at bottom (meterTop)
            // normalized: 0dB → 1.0, -60dB → 0.0
            let normalized = (db - minDB) / (maxDB - minDB)
            let y = meterTop + CGFloat(normalized) * meterHeight
            
            // REQ: 0dB label in red (#EF4444), others with improved opacity 0.55
            let labelColor: NSColor = (db == 0)
                ? ledRed
                : IndustrialColors.onSurfaceVariant.withAlphaComponent(0.55)
            
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
    
    /// Draw L/R labels below bars with improved visibility (REQ: 9px, semibold, 0.75 opacity)
    private func drawChannelLabels(barsStartX: CGFloat, meterTop: CGFloat) {
        // REQ: L label uses onSurface color
        let lAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: IndustrialColors.onSurface.withAlphaComponent(0.75)
        ]
        // REQ: R label uses onSurfaceVariant color (subtle distinction)
        let rAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: IndustrialColors.onSurfaceVariant.withAlphaComponent(0.75)
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
        
        // REQ: Color based on level
        let valueColor: NSColor
        if clampedDB > -3 {
            valueColor = ledRed           // REQ: Danger (> -3dB)
        } else if clampedDB > -6 {
            valueColor = ledYellow         // REQ: High (-6 ~ -3dB)
        } else {
            valueColor = IndustrialColors.onSurfaceVariant  // REQ: Normal (< -6dB)
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
            // REQ: Dim red when not triggered (0.15 opacity)
            ledRed.withAlphaComponent(0.15).setFill()
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
