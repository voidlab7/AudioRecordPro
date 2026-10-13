import Cocoa
import Foundation
import AVFoundation

/// 波形视图委托 — 处理用户交互（如 seek 拖动播放）
protocol WaveformViewDelegate: AnyObject {
    /// 用户在波形上点击/拖动，请求跳转到指定进度（0.0~1.0）
    func waveformView(_ view: WaveformView, didSeekToProgress progress: Double)
    /// FIX-003: 用户开始拖拽 scrubbing（播放器应暂停静音，跟手显示 playhead）
    func waveformViewDidBeginScrubbing(_ view: WaveformView)
    /// FIX-003: 用户松手结束 scrubbing（播放器从松手位置恢复播放）
    func waveformViewDidEndScrubbing(_ view: WaveformView)
}

// 默认空实现（避免无关 conformer 破坏）
extension WaveformViewDelegate {
    func waveformViewDidBeginScrubbing(_ view: WaveformView) {}
    func waveformViewDidEndScrubbing(_ view: WaveformView) {}
}

/// 音频波形显示视图 - 类似图2的波形效果
class WaveformView: NSView {
    
    // MARK: - Properties
    weak var delegate: WaveformViewDelegate?
    
    private var waveformData: [Float] = []
    var selectedSourceName: String = "系统音频".localized { didSet { needsDisplay = true } }
    private var rawPeakData: [Float] = []  // 原始 PCM 峰值（未归一化），与 extractWaveformSamples 同源
    private var maxDataPoints: Int = 260
    private(set) var isRecording: Bool = false
    private var smoothedLevel: Float = 0.0
    private var recentRawLevels: [Float] = []
    private let adaptiveWindowSize = 96
    private let logger = Logger.shared
    
    // Apple 原生录音波形样式：细竖条、留白、红色游标
    private var barWidth: CGFloat = 1.2
    private var barSpacing: CGFloat = 2.2
    private var maxBarHeight: CGFloat = 118.0
    
    // 录制时长跟踪（用于动态时间刻度）
    private var recordingStartTime: Date?
    private var recordingDuration: TimeInterval = 0
    
    // 静态波形文件时长
    private var staticFileDuration: TimeInterval = 0
    
    // 动画相关
    private var displayTimer: Timer?
    
    // 静态波形展示模式（选中已录制文件时）
    private var staticWaveformData: [Float]?
    private var isShowingStaticWaveform: Bool = false
    private var waveformLoadID = UUID()
    private let waveformLoadQueue = DispatchQueue(label: "com.audiorecord.waveform.load", qos: .userInitiated)
    private let waveformReadChunkFrames: AVAudioFrameCount = 131_072
    private let maxFramesPerWaveformBucket: AVAudioFrameCount = 8_192
    
    // 播放进度（0.0~1.0），用于在静态波形上显示播放位置游标
    private var playbackProgress: CGFloat = 0.0
    private var isDragging: Bool = false
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private let equalizerContainer = CALayer()
    private var equalizerBars: [CALayer] = []

    private func setupView() {
        wantsLayer = true
        // UI-003: 画布背景对齐设计稿实测 #14161A
        layer?.backgroundColor = NSColor(hex: "#14161A").cgColor
        setupEqualizer()
        layer?.cornerRadius = 4
        layer?.borderWidth = 0
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        
        waveformData = []
    }
    
    
    // MARK: - Public Methods
    
    /// 更新音频电平数据（RMS，仅保留用于向后兼容）
    func updateLevel(_ level: Float) {
        // 如果有 peakLevel 回调在用，这个 RMS 数据不再驱动波形
        // updateLevel 现在只在无 peakLevel 时作为 fallback
        guard rawPeakData.isEmpty && isRecording else { return }
        
        let normalizedLevel = max(0, min(1, level))
        let gatedLevel = normalizedLevel < 0.006 ? 0.0 : normalizedLevel
        
        recentRawLevels.append(gatedLevel)
        if recentRawLevels.count > adaptiveWindowSize {
            recentRawLevels.removeFirst(recentRawLevels.count - adaptiveWindowSize)
        }
        
        let estimatedDB = gatedLevel * 96.0 - 96.0
        let absoluteEnvelope = max(0.0, min(1.0, (estimatedDB + 52.0) / 52.0))
        let localMin = recentRawLevels.min() ?? 0.0
        let localMax = recentRawLevels.max() ?? 1.0
        let localRange = max(0.035, localMax - localMin)
        let localEnvelope = max(0.0, min(1.0, (gatedLevel - localMin) / localRange))
        
        let targetLevel = gatedLevel == 0 ? 0.0 : max(0.05, min(1.0, 0.10 + absoluteEnvelope * 0.45 + localEnvelope * 0.45))
        let alpha: Float = targetLevel > smoothedLevel ? 0.45 : 0.20
        smoothedLevel = smoothedLevel * (1.0 - alpha) + targetLevel * alpha
        
        let quantizedLevel = (smoothedLevel * 64).rounded() / 64
        waveformData.append(quantizedLevel)
        
        if waveformData.count > maxDataPoints {
            waveformData.removeFirst(waveformData.count - maxDataPoints)
        }
        
        DispatchQueue.main.async {
            self.needsDisplay = true
        }
    }
    
    /// 更新 PCM 峰值（与播放波形 extractWaveformSamples 完全同源）
    /// 录制时每次音频回调取一个 PCM 峰值，存入 rawPeakData，绘制时全局归一化
    func updatePeakLevel(_ peakLevel: Float) {
        guard isRecording else { return }
        
        // 存储原始 PCM 峰值
        rawPeakData.append(peakLevel)
        
        // 全局归一化：与 extractWaveformSamples 的 `peaks.map { $0 / maxPeak }` 完全一致
        let maxPeak = rawPeakData.max() ?? 1.0
        let normalizedPeak: Float = maxPeak > 0 ? peakLevel / maxPeak : 0
        
        waveformData.append(normalizedPeak)
        
        // 当 rawPeakData 增长时，重新归一化所有 waveformData（保持全局一致）
        // 每 50 个采样做一次全量归一化（平衡性能和一致性）
        if rawPeakData.count % 50 == 0 {
            let currentMax = rawPeakData.max() ?? 1.0
            if currentMax > 0 {
                waveformData = rawPeakData.map { $0 / currentMax }
            }
        }
        
        if waveformData.count > maxDataPoints {
            waveformData.removeFirst(waveformData.count - maxDataPoints)
        }
        if rawPeakData.count > maxDataPoints {
            rawPeakData.removeFirst(rawPeakData.count - maxDataPoints)
        }
        
        // 已在 main queue，直接触发重绘（避免双重 async 导致丢帧）
        needsDisplay = true
    }
    
    /// 开始录制
    func startRecording() {
        isRecording = true
        logger.info("🔬 [FIX004] WaveformView.startRecording → isRecording=true")
        waveformLoadID = UUID()
        isShowingStaticWaveform = false
        staticWaveformData = nil
        rawPeakData.removeAll()
        waveformData = Array(repeating: 0.0, count: 0)
        recordingStartTime = Date()
        recordingDuration = 0
        startAnimation()
    }
    
    /// 停止录制
    func stopRecording() {
        isRecording = false
        if let start = recordingStartTime {
            recordingDuration = Date().timeIntervalSince(start)
        }
        recordingStartTime = nil
        stopAnimation()
        // 不清空波形数据——等 loadWaveform() 加载真实 PCM 波形后自然替换
        smoothedLevel = 0
        recentRawLevels.removeAll()
        rawPeakData.removeAll()
        needsDisplay = true
    }
    
    /// 重置波形
    func reset() {
        smoothedLevel = 0
        recentRawLevels.removeAll()
        rawPeakData.removeAll()
        waveformData.removeAll()
        waveformLoadID = UUID()
        isShowingStaticWaveform = false
        staticWaveformData = nil
        recordingDuration = 0
        staticFileDuration = 0
        needsDisplay = true
    }
    
    /// 从音频文件加载静态波形并展示
    func loadWaveform(from url: URL) {
        isShowingStaticWaveform = true
        staticWaveformData = nil
        staticFileDuration = 0
        playbackProgress = 0
        let loadID = UUID()
        waveformLoadID = loadID
        needsDisplay = true
        
        let targetBars = max(100, min(600, Int(max(bounds.width, 600) / (barWidth + barSpacing))))
        
        waveformLoadQueue.async { [weak self] in
            guard let self = self else { return }
            let result = self.extractWaveformSamples(from: url, targetBars: targetBars)
            
            DispatchQueue.main.async {
                guard self.waveformLoadID == loadID else { return }
                self.staticWaveformData = result.samples
                self.staticFileDuration = result.duration
                self.needsDisplay = true
            }
        }
    }
    
    /// 清除静态波形（回到空白/实时模式）
    func clearStaticWaveform() {
        waveformLoadID = UUID()
        isShowingStaticWaveform = false
        staticWaveformData = nil
        playbackProgress = 0
        needsDisplay = true
    }
    
    /// 更新播放进度（0.0~1.0），会在静态波形上绘制进度游标
    func updatePlaybackProgress(_ progress: Double) {
        let clamped = CGFloat(max(0, min(1, progress)))
        guard abs(clamped - playbackProgress) > 0.001 || clamped == 0 else { return }
        playbackProgress = clamped
        if isShowingStaticWaveform && !isDragging {
            needsDisplay = true
        }
    }
    
    // MARK: - Mouse Interaction (Seek)
    
    override func mouseDown(with event: NSEvent) {
        guard isShowingStaticWaveform, staticWaveformData != nil else {
            super.mouseDown(with: event)
            return
        }
        isDragging = true
        delegate?.waveformViewDidBeginScrubbing(self)
        seekToMouseLocation(event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else {
            super.mouseDragged(with: event)
            return
        }
        seekToMouseLocation(event)
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDragging else {
            super.mouseUp(with: event)
            return
        }
        isDragging = false
        delegate?.waveformViewDidEndScrubbing(self)
    }
    
    private func seekToMouseLocation(_ event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let timelineInsetX: CGFloat = 84
        let timelineWidth = max(1, bounds.width - timelineInsetX * 2)
        let relativeX = location.x - timelineInsetX
        let progress = max(0, min(1, Double(relativeX / timelineWidth)))
        
        playbackProgress = CGFloat(progress)
        needsDisplay = true
        delegate?.waveformView(self, didSeekToProgress: progress)
    }
    
    // MARK: - Waveform Extraction
    
    /// 从音频文件提取归一化采样峰值数组（用于静态波形绘制）
    private func extractWaveformSamples(from url: URL, targetBars: Int) -> (samples: [Float], duration: TimeInterval) {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let totalFrames = AVAudioFramePosition(audioFile.length)
            let sampleRate = format.sampleRate
            let duration = sampleRate > 0 ? Double(totalFrames) / sampleRate : 0
            
            guard totalFrames > 0, targetBars > 0 else { return ([], duration) }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: waveformReadChunkFrames) else {
                logger.error("无法分配波形读取缓冲区")
                return ([], duration)
            }
            
            let channelCount = Int(format.channelCount)
            let framesPerBucket = max(1, Int64(totalFrames) / Int64(targetBars))
            let bucketReadFrames = AVAudioFrameCount(min(Int64(maxFramesPerWaveformBucket), framesPerBucket))
            var peaks = Array(repeating: Float(0), count: targetBars)
            
            for bucketIndex in 0..<targetBars {
                let bucketStartFrame = Int64(bucketIndex) * framesPerBucket
                guard bucketStartFrame < Int64(totalFrames) else { break }
                audioFile.framePosition = AVAudioFramePosition(bucketStartFrame)
                
                let remainingFrames = Int64(totalFrames) - bucketStartFrame
                let readFrames = AVAudioFrameCount(min(Int64(bucketReadFrames), remainingFrames))
                buffer.frameLength = readFrames
                try audioFile.read(into: buffer, frameCount: readFrames)
                
                guard let channelData = buffer.floatChannelData else { break }
                let framesRead = Int(buffer.frameLength)
                if framesRead == 0 { continue }
                
                var bucketPeak: Float = 0
                for frame in 0..<framesRead {
                    for channel in 0..<channelCount {
                        bucketPeak = max(bucketPeak, abs(channelData[channel][frame]))
                    }
                }
                peaks[bucketIndex] = bucketPeak
            }
            
            let maxPeak = peaks.max() ?? 1.0
            if maxPeak > 0 {
                peaks = peaks.map { $0 / maxPeak }
            }
            
            return (peaks, duration)
        } catch {
            logger.error("读取音频波形失败: \(error.localizedDescription)")
            return ([], 0)
        }
    }
    
    // MARK: - Animation
    
    private func startAnimation() {
        stopAnimation()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }
    
    private func stopAnimation() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // UI-006: 网格背景所有状态铺满画布（原仅 idle 画，录制态只剩 timelineRect 中线——老板看到的"中间一块"）
        drawCanvasGrid(in: bounds)
        if !isRecording && !isShowingStaticWaveform && waveformData.isEmpty {
            drawIdlePlaceholder(in: bounds)
            return
        }

        equalizerContainer.isHidden = true
        if isRecording || (isShowingStaticWaveform && staticFileDuration > 0) || recordingDuration > 0 {
            drawNativeTimeline(in: bounds)
        }
        if isRecording {
            drawSourceLabel(in: bounds)
        }
        if isShowingStaticWaveform {
            if let data = staticWaveformData, !data.isEmpty {
                drawStaticWaveform(in: bounds, data: data)
            }
        } else if !waveformData.isEmpty {
            drawWaveform(in: bounds)
            drawPlayhead(in: bounds)
        }
    }

    // MARK: - v3.1 Idle 均衡器动效（Figma 规格：5 柱脉冲）
    private func setupEqualizer() {
        let heights: [CGFloat] = [16, 28, 32, 24, 12]
        let barW: CGFloat = 4, gap: CGFloat = 6
        let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
        equalizerContainer.frame = NSRect(x: 0, y: 0, width: total, height: 32)
        for (i, h) in heights.enumerated() {
            let bar = CALayer()
            bar.backgroundColor = NSColor(hex: "#13BBA3").cgColor
            bar.cornerRadius = 2
            bar.bounds = CGRect(x: 0, y: 0, width: barW, height: h)
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.position = CGPoint(x: CGFloat(i) * (barW + gap) + barW / 2, y: 16)
            // 脉冲：纵向缩放呼吸，错相位
            let anim = CABasicAnimation(keyPath: "transform.scale.y")
            anim.fromValue = 0.45
            anim.toValue = 1.0
            anim.duration = [0.7, 0.95, 1.15, 0.8, 1.05][i]
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.beginTime = CACurrentMediaTime() + Double(i) * 0.13
            bar.add(anim, forKey: "eqPulse")
            equalizerContainer.addSublayer(bar)
            equalizerBars.append(bar)
        }
        layer?.addSublayer(equalizerContainer)
    }

    private func updateEqualizerGeometry(cardRect: NSRect) {
        equalizerContainer.isHidden = false
        equalizerContainer.position = CGPoint(x: cardRect.midX, y: cardRect.midY)
    }

    /// UI-003: 画布细网格背景（Stitch v2 设计稿）
    /// 设计实测：#181A1E on #14161A，亮度差仅 +2~4（极隐约）；间距 45px@2x = 30pt
    private func drawCanvasGrid(in rect: NSRect) {
        let gridSize: CGFloat = 30
        let gridPath = NSBezierPath()
        var x = rect.minX + gridSize
        while x < rect.maxX {
            gridPath.move(to: NSPoint(x: x, y: rect.minY))
            gridPath.line(to: NSPoint(x: x, y: rect.maxY))
            x += gridSize
        }
        var y = rect.minY + gridSize
        while y < rect.maxY {
            gridPath.move(to: NSPoint(x: rect.minX, y: y))
            gridPath.line(to: NSPoint(x: rect.maxX, y: y))
            y += gridSize
        }
        NSColor.white.withAlphaComponent(0.035).setStroke()
        gridPath.lineWidth = 1
        gridPath.stroke()    }

    /// UI-003: idle 态——发光图标卡片 + Ready to Record + Space 键帽副标题 + 左上 Ready 状态点
    /// FIX-004: 录音态左上角常显当前录制源——「不知道在录系统声还是麦」的 UI 缺口修复
    /// （原 `MainWindowView.updateMode` 为空实现「预留」）
    private func drawSourceLabel(in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: IndustrialColors.onSurfaceVariant
        ]
        // 录制中红点（与 idle 态绿点 Ready 同位呼应）
        let dot = NSBezierPath(ovalIn: NSRect(x: 16, y: rect.maxY - 22, width: 6, height: 6))
        NSColor.systemRed.setFill()
        dot.fill()
        ("REC · " + selectedSourceName as NSString).draw(at: NSPoint(x: 28, y: rect.maxY - 26), withAttributes: attrs)
    }

    private func drawIdlePlaceholder(in rect: NSRect) {
        let centerX = rect.midX
        let centerY = rect.midY

        // 左上极简状态：绿点 + Ready（点色对齐设计薄荷 #13BBA3）
        let dotSize: CGFloat = 6
        let dot = NSBezierPath(ovalIn: NSRect(x: 16, y: rect.maxY - 22, width: dotSize, height: dotSize))
        NSColor(hex: "#13BBA3").setFill()
        dot.fill()
        let readyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: IndustrialColors.onSurfaceVariant
        ]
        ("Ready" as NSString).draw(at: NSPoint(x: 28, y: rect.maxY - 26), withAttributes: readyAttrs)

        // 图标卡片（设计实测：#2E3336→#272D2E 灰卡轻渐变，无明显光晕；微弱环境光）
        let cardSize: CGFloat = 76
        let cardRect = NSRect(x: centerX - cardSize / 2, y: centerY + 30, width: cardSize, height: cardSize)
        NSGraphicsContext.current?.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        glow.shadowBlurRadius = 14
        glow.shadowOffset = NSSize(width: 0, height: 3)
        glow.set()
        let card = NSBezierPath(roundedRect: cardRect, xRadius: 16, yRadius: 16)
        NSColor(hex: "#2B3034").setFill()
        card.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        card.lineWidth = 1
        NSColor.white.withAlphaComponent(0.07).setStroke()
        card.stroke()

        updateEqualizerGeometry(cardRect: cardRect)

        // 标题（亮白）
        let title = "Ready to Record"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: IndustrialColors.onSurface
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        (title as NSString).draw(at: NSPoint(x: centerX - titleSize.width / 2, y: centerY - 6),
                                 withAttributes: titleAttrs)

        // 一行副标题：Press record or hit [Space] to start（Space 键帽）
        let subFont = NSFont.systemFont(ofSize: 11)
        let subColor = IndustrialColors.onSurfaceVariant
        let prefix = "Press record or hit "
        let suffix = " to start"
        let keyText = "Space"
        let prefixSize = (prefix as NSString).size(withAttributes: [.font: subFont, .foregroundColor: subColor])
        let keyCapWidth: CGFloat = 42
        let keyCapHeight: CGFloat = 17
        let suffixSize = (suffix as NSString).size(withAttributes: [.font: subFont, .foregroundColor: subColor])
        let totalWidth = prefixSize.width + 6 + keyCapWidth + 6 + suffixSize.width
        var cursorX = centerX - totalWidth / 2
        let baseY = centerY - 34

        (prefix as NSString).draw(at: NSPoint(x: cursorX, y: baseY + 2),
                                  withAttributes: [.font: subFont, .foregroundColor: subColor])
        cursorX += prefixSize.width + 6

        // Space 键帽（描边圆角矩形 + 居中文字）
        let keyCap = NSBezierPath(roundedRect: NSRect(x: cursorX, y: baseY, width: keyCapWidth, height: keyCapHeight), xRadius: 4, yRadius: 4)
        keyCap.lineWidth = 1
        IndustrialColors.outline.setStroke()
        keyCap.stroke()
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: IndustrialColors.onSurfaceVariant
        ]
        let keySize = (keyText as NSString).size(withAttributes: keyAttrs)
        (keyText as NSString).draw(at: NSPoint(x: cursorX + (keyCapWidth - keySize.width) / 2, y: baseY + 3.5),
                                   withAttributes: keyAttrs)
        cursorX += keyCapWidth + 6

        (suffix as NSString).draw(at: NSPoint(x: cursorX, y: baseY + 2),
                                  withAttributes: [.font: subFont, .foregroundColor: subColor])
    }
    
    private func drawNativeTimeline(in rect: NSRect) {
        let centerY = rect.midY
        let timelineInsetX: CGFloat = 84
        let timelineRect = NSRect(
            x: timelineInsetX,
            y: 42,
            width: max(1, rect.width - timelineInsetX * 2),
            height: max(1, rect.height - 88)
        )
        
        // 只有实际录制/预览才会调用本方法；静音零位线保持中性灰，不模拟录制进度。
        IndustrialColors.gridMedium.withAlphaComponent(0.5).setStroke()
        let centerLine = NSBezierPath()
        centerLine.lineWidth = 1
        centerLine.setLineDash([3, 3], count: 2, phase: 0)
        centerLine.move(to: NSPoint(x: timelineRect.minX, y: centerY))
        centerLine.line(to: NSPoint(x: timelineRect.maxX, y: centerY))
        centerLine.stroke()
        
        guard isRecording || recordingDuration > 0 || (isShowingStaticWaveform && staticFileDuration > 0) else {
            return
        }

        let tickColor = IndustrialColors.onSurfaceVariant.withAlphaComponent(0.24)
        tickColor.setStroke()
        let tickPath = NSBezierPath()
        tickPath.lineWidth = 1
        let tickCount = 8
        for i in 0...tickCount {
            let x = timelineRect.minX + timelineRect.width * CGFloat(i) / CGFloat(tickCount)
            tickPath.move(to: NSPoint(x: x, y: timelineRect.minY - 12))
            tickPath.line(to: NSPoint(x: x, y: timelineRect.minY - 4))
        }
        tickPath.stroke()
        
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: IndustrialTypography.monoDB,
            .foregroundColor: IndustrialColors.textTertiary.withAlphaComponent(0.68),
            .kern: 0.2
        ]
        
        // 动态时间刻度：根据实际时长计算
        let totalDuration: TimeInterval
        if isShowingStaticWaveform && staticFileDuration > 0 {
            totalDuration = staticFileDuration
        } else if let start = recordingStartTime {
            totalDuration = max(5, Date().timeIntervalSince(start))
        } else if recordingDuration > 0 {
            totalDuration = recordingDuration
        } else {
            totalDuration = 5.0  // 默认显示 5 秒范围
        }
        
        let labelCount = 5
        for i in 0..<labelCount {
            let timeAtTick = totalDuration * Double(i) / Double(labelCount - 1)
            let minutes = Int(timeAtTick) / 60
            let seconds = Int(timeAtTick) % 60
            let label = String(format: "%d:%02d", minutes, seconds)
            let x = timelineRect.minX + timelineRect.width * CGFloat(i) / CGFloat(labelCount - 1) - 12
            label.draw(at: NSPoint(x: x, y: timelineRect.minY - 30), withAttributes: labelAttributes)
        }
    }
    
    private func drawWaveform(in rect: NSRect) {
        // FIX-004: 录制态全零（静音）也画基线——「在录但静音」必须与「没在录」可区分（不死寂）
        guard waveformData.contains(where: { $0 > 0 }) || isRecording else { return }
        
        let timelineInsetX: CGFloat = 84
        let timelineRect = NSRect(
            x: timelineInsetX,
            y: 42,
            width: max(1, rect.width - timelineInsetX * 2),
            height: max(1, rect.height - 88)
        )
        let centerY = rect.midY
        let drawHeight = min(maxBarHeight, timelineRect.height * 0.82)
        let step = barWidth + barSpacing
        let maxVisibleBars = Int(floor(timelineRect.width / step))
        
        // 左起右滚：最新数据在右端，填满后左侧数据被裁切
        let startIndex = max(0, waveformData.count - maxVisibleBars)
        let visibleData = Array(waveformData[startIndex...])
        guard visibleData.count > 1 else { return }
        
        // P0-1: 填充波形渲染
        let pixelsPerSample = timelineRect.width / CGFloat(maxVisibleBars)
        let startX = timelineRect.minX
        
        let upperPath = NSBezierPath()
        var lowerPoints: [(x: CGFloat, y: CGFloat)] = []
        var firstPoint = true
        
        for (offset, level) in visibleData.enumerated() {
            let x = startX + CGFloat(offset) * pixelsPerSample
            guard x <= timelineRect.maxX else { break }
            
            let normalized = CGFloat(max(0, level))
            // FIX-004: 最低振幅 1.5pt——静音段呈现细基线带（0.5pt 视觉上不可见）
            let amplitude = max(1.5, normalized * drawHeight * 0.48)
            
            if firstPoint {
                upperPath.move(to: NSPoint(x: x, y: centerY + amplitude))
                lowerPoints.append((x, centerY - amplitude))
                firstPoint = false
            } else {
                upperPath.line(to: NSPoint(x: x, y: centerY + amplitude))
                lowerPoints.append((x, centerY - amplitude))
            }
        }
        
        guard !lowerPoints.isEmpty else { return }
        
        // 合并为闭合填充路径：上包络 → 下包络反向
        let filledPath = NSBezierPath()
        filledPath.append(upperPath)
        for pt in lowerPoints.reversed() {
            filledPath.line(to: NSPoint(x: pt.x, y: pt.y))
        }
        filledPath.close()
        
        // 填充主体
        IndustrialColors.waveformCoral.withAlphaComponent(0.75).setFill()
        filledPath.fill()
        
        // 包络线（下包络用 lowerPoints 构建）
        let lowerPath = NSBezierPath()
        if let first = lowerPoints.first {
            lowerPath.move(to: NSPoint(x: first.x, y: first.y))
            for pt in lowerPoints.dropFirst() {
                lowerPath.line(to: NSPoint(x: pt.x, y: pt.y))
            }
        }
        
        IndustrialColors.waveformCoral.withAlphaComponent(0.95).setStroke()
        upperPath.lineWidth = 1.0
        upperPath.stroke()
        lowerPath.lineWidth = 1.0
        lowerPath.stroke()
    }
    
    private func drawPlayhead(in rect: NSRect) {
        // 录制模式不再绘制固定 playhead，最右端的波形就是「现在」
    }
    
    /// 绘制静态波形（已录制文件预览）+ 播放进度游标
    private func drawStaticWaveform(in rect: NSRect, data: [Float]) {
        let timelineInsetX: CGFloat = 84
        let timelineRect = NSRect(
            x: timelineInsetX,
            y: 42,
            width: max(1, rect.width - timelineInsetX * 2),
            height: max(1, rect.height - 88)
        )
        let centerY = rect.midY
        let drawHeight = min(maxBarHeight, timelineRect.height * 0.82)
        
        let totalBars = data.count
        guard totalBars > 1 else { return }
        
        // P0-1: 填充波形渲染
        let pixelWidth = timelineRect.width
        let bucketsCount = min(Int(pixelWidth), totalBars)
        guard bucketsCount > 1 else { return }
        let samplesPerBucket = max(1, totalBars / bucketsCount)
        
        let progressBucket = Int(playbackProgress * CGFloat(bucketsCount))
        
        // 构建上下包络路径 — 已播放/未播放两段
        let playedUpperPath = NSBezierPath()
        var playedLowerPts: [(CGFloat, CGFloat)] = []
        let unplayedUpperPath = NSBezierPath()
        var unplayedLowerPts: [(CGFloat, CGFloat)] = []
        
        var playedFirst = true
        var unplayedFirst = true
        
        for i in 0..<bucketsCount {
            let bucketStart = i * samplesPerBucket
            let bucketEnd = min(bucketStart + samplesPerBucket, totalBars)
            var maxVal: Float = 0
            for j in bucketStart..<bucketEnd {
                if data[j] > maxVal { maxVal = data[j] }
            }
            
            let x = timelineRect.minX + CGFloat(i) / CGFloat(bucketsCount) * pixelWidth
            let amplitude = CGFloat(maxVal) * drawHeight * 0.48
            let upperY = centerY + amplitude
            let lowerY = centerY - amplitude
            
            let isPlayed = i <= progressBucket && playbackProgress > 0
            
            if isPlayed {
                if playedFirst {
                    playedUpperPath.move(to: NSPoint(x: x, y: upperY))
                    playedLowerPts.append((x, lowerY))
                    playedFirst = false
                } else {
                    playedUpperPath.line(to: NSPoint(x: x, y: upperY))
                    playedLowerPts.append((x, lowerY))
                }
            } else {
                if unplayedFirst {
                    unplayedUpperPath.move(to: NSPoint(x: x, y: upperY))
                    unplayedLowerPts.append((x, lowerY))
                    unplayedFirst = false
                } else {
                    unplayedUpperPath.line(to: NSPoint(x: x, y: upperY))
                    unplayedLowerPts.append((x, lowerY))
                }
            }
        }
        
        // 辅助：将上下点数组合并为闭合填充路径
        func makeFilledPath(upper: NSBezierPath, lowerPts: [(CGFloat, CGFloat)]) -> NSBezierPath {
            let filled = NSBezierPath()
            filled.append(upper)
            for pt in lowerPts.reversed() {
                filled.line(to: NSPoint(x: pt.0, y: pt.1))
            }
            filled.close()
            return filled
        }
        
        // 辅助：从点数组构建 NSBezierPath
        func makeStrokePath(from pts: [(CGFloat, CGFloat)]) -> NSBezierPath {
            let path = NSBezierPath()
            if let first = pts.first {
                path.move(to: NSPoint(x: first.0, y: first.1))
                for pt in pts.dropFirst() {
                    path.line(to: NSPoint(x: pt.0, y: pt.1))
                }
            }
            return path
        }
        
        // 绘制已播放区域（较亮）
        if !playedFirst {
            let playedFilled = makeFilledPath(upper: playedUpperPath, lowerPts: playedLowerPts)
            IndustrialColors.waveformCoral.withAlphaComponent(0.85).setFill()
            playedFilled.fill()
            IndustrialColors.waveformCoral.setStroke()
            playedUpperPath.lineWidth = 1.0
            playedUpperPath.stroke()
            let playedLowerStroke = makeStrokePath(from: playedLowerPts)
            playedLowerStroke.lineWidth = 1.0
            playedLowerStroke.stroke()
        }
        
        // 绘制未播放区域（较暗）
        if !unplayedFirst {
            let unplayedFilled = makeFilledPath(upper: unplayedUpperPath, lowerPts: unplayedLowerPts)
            IndustrialColors.waveformCoral.withAlphaComponent(0.35).setFill()
            unplayedFilled.fill()
            IndustrialColors.waveformCoral.withAlphaComponent(0.5).setStroke()
            unplayedUpperPath.lineWidth = 1.0
            unplayedUpperPath.stroke()
            let unplayedLowerStroke = makeStrokePath(from: unplayedLowerPts)
            unplayedLowerStroke.lineWidth = 1.0
            unplayedLowerStroke.stroke()
        }
        
        // 绘制播放进度游标线
        if playbackProgress > 0 {
            let playheadX = timelineRect.minX + playbackProgress * pixelWidth
            
            IndustrialColors.waveformAccent.setStroke()
            let playhead = NSBezierPath()
            playhead.lineWidth = 1.6
            playhead.move(to: NSPoint(x: playheadX, y: timelineRect.minY))
            playhead.line(to: NSPoint(x: playheadX, y: timelineRect.maxY))
            playhead.stroke()
            
            // 游标顶部小圆点
            IndustrialColors.waveformAccent.setFill()
            NSBezierPath(ovalIn: NSRect(x: playheadX - 3, y: timelineRect.maxY - 4, width: 6, height: 6)).fill()
        }
    }
    
    // MARK: - Deinit
    
    deinit {
        stopAnimation()
    }
}

// MARK: - WaveformView Extensions

extension WaveformView {
    
    /// 设置波形样式
    func setStyle(barWidth: CGFloat = 1.2, spacing: CGFloat = 2.2, maxHeight: CGFloat = 118.0) {
        self.barWidth = barWidth
        self.barSpacing = spacing
        self.maxBarHeight = maxHeight
    }
    
    /// 设置数据点数量
    func setMaxDataPoints(_ count: Int) {
        maxDataPoints = max(50, min(500, count))
        waveformData = Array(repeating: 0.0, count: maxDataPoints)
    }
}
