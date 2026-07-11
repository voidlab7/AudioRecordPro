import Cocoa
import Foundation
import AVFoundation

/// 波形视图委托 — 处理用户交互（如 seek 拖动播放）
protocol WaveformViewDelegate: AnyObject {
    /// 用户在波形上点击/拖动，请求跳转到指定进度（0.0~1.0）
    func waveformView(_ view: WaveformView, didSeekToProgress progress: Double)
}

/// 音频波形显示视图 - 类似图2的波形效果
class WaveformView: NSView {
    
    // MARK: - Properties
    weak var delegate: WaveformViewDelegate?
    
    private var waveformData: [Float] = []
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
    
    private func setupView() {
        wantsLayer = true
        // Industrial Design: 深灰背景
        layer?.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
        layer?.cornerRadius = 4
        layer?.borderWidth = 0
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        
        // 初始化波形数据
        waveformData = Array(repeating: 0.0, count: maxDataPoints)
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
        let displayLevel = max(quantizedLevel, isRecording ? 0.012 : 0.0)
        waveformData.append(displayLevel)
        
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
        waveformData = Array(repeating: 0.0, count: maxDataPoints)
        isShowingStaticWaveform = false
        staticWaveformData = nil
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
        drawNativeTimeline(in: dirtyRect)
        
        if isShowingStaticWaveform, let data = staticWaveformData, !data.isEmpty {
            drawStaticWaveform(in: dirtyRect, data: data)
        } else if isRecording {
            drawWaveform(in: dirtyRect)
            drawPlayhead(in: dirtyRect)
        } else if waveformData.isEmpty {
            // REQ-2.0-02: idle 态引导占位内容
            drawIdlePlaceholder(in: dirtyRect)
        } else {
            drawWaveform(in: dirtyRect)
            drawPlayhead(in: dirtyRect)
        }
    }
    
    /// REQ-2.0-02: 绘制 idle 态引导占位内容
    private func drawIdlePlaceholder(in rect: NSRect) {
        let centerX = rect.midX
        let centerY = rect.midY
        
        // Draw waveform SF Symbol icon with reduced opacity
        let iconSize: CGFloat = 44
        let iconRect = NSRect(
            x: centerX - iconSize / 2,
            y: centerY + 2,
            width: iconSize,
            height: iconSize
        )
        
        if let symbolImage = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "录制") {
            let config = NSImage.SymbolConfiguration(pointSize: 38, weight: .ultraLight)
            let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
            configured.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.35)
        }
        
        // Draw guide text below icon
        let guideText = "点击 ● 开始录制"
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: IndustrialTypography.body,
            .foregroundColor: IndustrialColors.textTertiary
        ]
        let textSize = (guideText as NSString).size(withAttributes: textAttributes)
        let textPoint = NSPoint(
            x: centerX - textSize.width / 2,
            y: centerY - textSize.height - 8
        )
        (guideText as NSString).draw(at: textPoint, withAttributes: textAttributes)
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
        
        // 中线：虚线样式
        // 录制时从右到左渐变（白→红），表示录制在进行中
        if isRecording {
            // 录制进度（0~1），用于颜色渐变
            let step = barWidth + barSpacing
            let maxVisibleBars = Int(floor(timelineRect.width / step))
            let filledBars = min(waveformData.count, maxVisibleBars)
            let fillRatio = CGFloat(filledBars) / CGFloat(max(1, maxVisibleBars))
            let coloredWidth = timelineRect.width * fillRatio
            
            // 已录制部分：红色虚线（从左到 coloredWidth）
            if coloredWidth > 0 {
                IndustrialColors.waveformAccent.withAlphaComponent(0.6).setStroke()
                let redLine = NSBezierPath()
                redLine.lineWidth = 1
                redLine.setLineDash([3, 3], count: 2, phase: 0)
                redLine.move(to: NSPoint(x: timelineRect.minX, y: centerY))
                redLine.line(to: NSPoint(x: timelineRect.minX + coloredWidth, y: centerY))
                redLine.stroke()
            }
            
            // 未录制部分：白色虚线（从 coloredWidth 到右端）
            if coloredWidth < timelineRect.width {
                IndustrialColors.gridMedium.withAlphaComponent(0.5).setStroke()
                let whiteLine = NSBezierPath()
                whiteLine.lineWidth = 1
                whiteLine.setLineDash([3, 3], count: 2, phase: 0)
                whiteLine.move(to: NSPoint(x: timelineRect.minX + coloredWidth, y: centerY))
                whiteLine.line(to: NSPoint(x: timelineRect.maxX, y: centerY))
                whiteLine.stroke()
            }
        } else {
            // Idle state: visible white center line (no dashes — clean solid line)
            NSColor(white: 1.0, alpha: 0.22).setStroke()
            let centerLine = NSBezierPath()
            centerLine.lineWidth = 1
            centerLine.move(to: NSPoint(x: timelineRect.minX, y: centerY))
            centerLine.line(to: NSPoint(x: timelineRect.maxX, y: centerY))
            centerLine.stroke()
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
        guard !waveformData.isEmpty else { return }
        
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
            let amplitude = max(0.5, normalized * drawHeight * 0.48)
            
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
