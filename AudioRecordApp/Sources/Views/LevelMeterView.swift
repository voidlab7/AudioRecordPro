import Cocoa
import Foundation

/// 音频电平表视图
class LevelMeterView: NSView {
    private var level: Float = 0.0
    // bars 从左到右表示时间序列（最左=最旧，最右=最新）
    private var bars: [Float] = Array(repeating: 0.0, count: 180)
    
    private enum Style {
        case recording
        case playback
    }
    
    private var style: Style = .recording
    /// Whether recording is active — controls waveform color (red) vs idle center line (white)
    private(set) var isRecording: Bool = false
    private var sensitivityMultiplier: Float = 1.6
    private var compressionExponent: Float = 0.45 // 越小越跳
    // 干净包络：上升略快、下降稍慢，避免每根柱子乱跳
    private var smoothUpWeight: Float = 0.38
    private var smoothDownWeight: Float = 0.20
    // 分贝映射参数（避免轻易顶满）
    private let meterMinDB: Float = -60.0        // -60dB 作为噪声地板
    private let meterGamma: Float = 1.5          // 固定刻度：更强压缩，高电平更难顶满
    private let meterHeadroom: Float = 0.80      // 固定刻度：顶部留更多余量
    // 噪声门（视图侧）
    private let noiseGateThreshold: Float = 0.02
    private let noiseGateReleaseMs: Double = 200
    private let nearSilenceFloor: Float = 0.003
    private var belowThresholdSince: CFAbsoluteTime?

    // 峰值保持与回落
    private var peakHoldLevel: Float = 0.0
    private var lastUpdateTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private let peakHoldMs: Double = 800      // 保持时间
    private let peakDecayPerSec: Float = 1.2  // 超过保持期后每秒衰减幅度（线性）
    private var peakHoldSince: CFAbsoluteTime?
    // 采样稀疏：控制推进频率
    private var updateTick: Int = 0
    private let sampleInterval: Int = 5   // 每5次刷新推进一次，横向更稀疏
    // 平滑左移：子像素位移 + 触发整列推进
    private var xOffset: CGFloat = 0.0
    private var advanceWidth: CGFloat = 2.0   // 每列的推进宽度（barWidth+spacing），实时在 draw 里更新
    private let stepPerFrame: CGFloat = 0.5   // 每帧左移像素，数值越大越快
    // 视觉低通：Mac 原生录音波形需要干净包络，不做人为毛刺
    private var visualPrevLevel: Float = 0.0
    private var recentRawLevels: [Float] = []
    private let adaptiveWindowSize = 96
    private let visualAlpha: Float = 0.38
    private let waveformFloor: Float = 0.012
    private let waveformQuantizationSteps: Float = 64
    
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
        
        // Industrial Design: 深色基底 + 硬边圆角 + 边框
        layer?.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
        layer?.cornerRadius = IndustrialCornerRadius.xs  // 2px 硬边
        layer?.borderWidth = 1
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
    }
    
    /// Mark recording started — waveform turns red and begins scrolling
    func startRecording() {
        isRecording = true
        needsDisplay = true
    }
    
    /// Mark recording stopped — waveform freezes
    func stopRecording() {
        isRecording = false
        needsDisplay = true
    }
    
    /// 更新音频电平（记录模式：把最新值推入最右侧，并整体向左滚动）
    func updateLevel(_ newLevel: Float) {
        level = max(0, min(1, newLevel))
        appendLevelToBars()
        needsDisplay = true
    }
    
    private func appendLevelToBars() {
        // 非线性提升灵敏度，增强视觉动态
        // 噪声门：若持续低于阈值超过 releaseMs，则硬置为0
        let now = CFAbsoluteTimeGetCurrent()
        if level < noiseGateThreshold {
            if belowThresholdSince == nil { belowThresholdSince = now }
        } else {
            belowThresholdSince = nil
        }
        var effectiveLevel = level
        var isSilent = false
        if let t0 = belowThresholdSince, (now - t0) * 1000.0 >= noiseGateReleaseMs {
            // 静音门：静音达到释放时间后，视图电平强制为0
            effectiveLevel = 0
            isSilent = true
        }
        // 将电平映射为“绝对响度 + 局部动态”，避免高响度音乐一直满格
        let boosted: Float
        if isSilent {
            boosted = 0
            recentRawLevels.removeAll()
        } else {
            let linear = max(nearSilenceFloor, min(1.0, effectiveLevel * sensitivityMultiplier))
            recentRawLevels.append(linear)
            if recentRawLevels.count > adaptiveWindowSize {
                recentRawLevels.removeFirst(recentRawLevels.count - adaptiveWindowSize)
            }
            
            let db = 20.0 * log10(linear)
            let absoluteEnvelope = max(0.0, min(1.0, (db + 52.0) / 52.0))
            let localMin = recentRawLevels.min() ?? 0.0
            let localMax = recentRawLevels.max() ?? 1.0
            let localRange = max(0.035, localMax - localMin)
            let localEnvelope = max(0.0, min(1.0, (linear - localMin) / localRange))
            boosted = max(0.08, min(meterHeadroom, 0.18 + absoluteEnvelope * 0.32 + localEnvelope * 0.42))
        }
        let last = bars.last ?? 0
        // 上行/下行分别平滑：下行更快回落
        let isFalling = boosted < last
        let upKeep = 1.0 - smoothUpWeight
        let downKeep = 1.0 - smoothDownWeight
        let smoothed: Float
        if isSilent {
            smoothed = 0
        } else {
            if isFalling {
                smoothed = last * downKeep + boosted * smoothDownWeight
            } else {
                smoothed = last * upKeep + boosted * smoothUpWeight
            }
        }

        // 峰值保持/回落
        let now2 = CFAbsoluteTimeGetCurrent()
        let dt = Float(now2 - lastUpdateTime)
        lastUpdateTime = now2
        if isSilent {
            peakHoldLevel = 0
        } else if smoothed > peakHoldLevel {
            peakHoldLevel = smoothed
            peakHoldSince = now2
        } else {
            if let t0 = peakHoldSince, (now2 - t0) * 1000.0 >= peakHoldMs {
                peakHoldLevel = max(0, peakHoldLevel - peakDecayPerSec * dt)
            }
        }
        // 可选视觉低通
        let visualBase = isSilent ? 0 : (visualPrevLevel * (1.0 - visualAlpha) + smoothed * visualAlpha)
        visualPrevLevel = visualBase

        // 干净包络：不加随机毛刺；保留静音小线，量化高度避免锯齿抖动
        let display: Float
        if isSilent {
            display = 0
        } else {
            let floored = max(waveformFloor, min(meterHeadroom, visualBase))
            display = (floored * waveformQuantizationSteps).rounded() / waveformQuantizationSteps
        }
        // 更新推进动画计数
        updateTick += 1
        // 子像素左移
        xOffset += stepPerFrame
        if xOffset >= advanceWidth {
            // 触发整列推进一格
            xOffset -= advanceWidth
            if !bars.isEmpty {
                for i in 0..<(bars.count - 1) { bars[i] = bars[i + 1] }
                // 按采样间隔更新最后一根高度，否则保持
                if updateTick % sampleInterval == 0 {
                    bars[bars.count - 1] = display
                }
            }
        } else {
            // 未推进时，只在采样间隔命中时更新最右条高度
            if updateTick % sampleInterval == 0, !bars.isEmpty {
                bars[bars.count - 1] = display
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 清除背景
        context.clear(dirtyRect)
        
        // 绘制背景 — 深色工业底板内承载原生录音红色波形
        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        IndustrialColors.surfaceContainerLow.setFill()
        backgroundPath.fill()
        
        // 绘制细条录音波形
        drawBars(in: dirtyRect)
    }
    
    private func drawBars(in rect: NSRect) {
        let horizontalPadding: CGFloat = 18
        let verticalPadding: CGFloat = 12
        let insetRect = NSRect(
            x: rect.minX + horizontalPadding,
            y: rect.minY + verticalPadding,
            width: rect.width - horizontalPadding * 2,
            height: rect.height - verticalPadding * 2
        )
        
        // Center line: white when idle, dimmed when recording (waveform takes focus)
        let centerLineColor: NSColor
        if isRecording {
            centerLineColor = IndustrialColors.gridMedium.withAlphaComponent(0.4)
        } else {
            // Idle state: visible white center line as the default "audio track"
            centerLineColor = NSColor(white: 1.0, alpha: 0.25)
        }
        centerLineColor.setStroke()
        let centerLine = NSBezierPath()
        centerLine.lineWidth = 1
        centerLine.move(to: NSPoint(x: insetRect.minX, y: insetRect.midY))
        centerLine.line(to: NSPoint(x: insetRect.maxX, y: insetRect.midY))
        centerLine.stroke()
        
        let desiredBarWidth: CGFloat = 1.2
        let desiredSpacing: CGFloat = 2.3
        let totalBars = CGFloat(bars.count)
        let desiredUsedWidth = desiredBarWidth * totalBars + desiredSpacing * max(0, totalBars - 1)
        let scale = min(1.0, insetRect.width / max(1, desiredUsedWidth))
        let barWidth = max(0.9, desiredBarWidth * scale)
        let barSpacing = max(1.2, desiredSpacing * scale)
        let usedWidth = barWidth * totalBars + barSpacing * max(0, totalBars - 1)
        let startX = insetRect.minX + max(0, (insetRect.width - usedWidth) / 2)
        advanceWidth = barWidth + barSpacing
        
        for (index, barLevel) in bars.enumerated() {
            // Skip drawing bars with zero level (no audio data yet)
            guard barLevel > 0 else { continue }
            
            let x = startX + CGFloat(index) * (barWidth + barSpacing) - xOffset
            guard x >= insetRect.minX - advanceWidth && x <= insetRect.maxX else { continue }
            
            let normalized = CGFloat(barLevel)
            let halfHeight = max(1.2, normalized * insetRect.height * 0.5)
            let barRect = NSRect(
                x: x,
                y: insetRect.midY - halfHeight,
                width: barWidth,
                height: halfHeight * 2
            )
            let alpha = max(0.32, min(1.0, 0.34 + normalized * 0.7))
            let path = NSBezierPath(roundedRect: barRect, xRadius: 0.7, yRadius: 0.7)
            IndustrialColors.waveformSoft.withAlphaComponent(alpha).setFill()
            path.fill()
        }
        
        if peakHoldLevel > 0 {
            let lastX = insetRect.minX + CGFloat(max(0, bars.count - 1)) * (barWidth + barSpacing) - xOffset
            let peakHeight = CGFloat(peakHoldLevel) * insetRect.height * 0.5
            let peakY = insetRect.midY + peakHeight
            
            IndustrialColors.waveformAccent.withAlphaComponent(0.75).setStroke()
            let peakPath = NSBezierPath()
            peakPath.lineWidth = 1.0
            peakPath.move(to: NSPoint(x: lastX - 1, y: peakY))
            peakPath.line(to: NSPoint(x: lastX + barWidth + 1, y: peakY))
            peakPath.stroke()
        }
    }
    
    /// 重置电平表
    func reset() {
        level = 0.0
        visualPrevLevel = 0.0
        recentRawLevels.removeAll()
        bars = Array(repeating: 0.0, count: 180)
        isRecording = false
        needsDisplay = true
    }
    
    // MARK: - Style Controls
    enum SensitivityPreset { case stable, normal, sensitive }
    func setSensitivityPreset(_ preset: SensitivityPreset) {
        switch preset {
        case .stable:
            sensitivityMultiplier = 1.2
            compressionExponent = 0.55
            smoothUpWeight = 0.30
            smoothDownWeight = 0.16
        case .normal:
            sensitivityMultiplier = 1.6
            compressionExponent = 0.45
            smoothUpWeight = 0.38
            smoothDownWeight = 0.20
        case .sensitive:
            sensitivityMultiplier = 1.9
            compressionExponent = 0.4
            smoothUpWeight = 0.46
            smoothDownWeight = 0.24
        }
    }
    
    /// 开始动画
    func startAnimation() {
        // 可以在这里添加更复杂的动画逻辑
    }
    
    /// 停止动画
    func stopAnimation() {
        stopRecording()
        reset()
    }
}
