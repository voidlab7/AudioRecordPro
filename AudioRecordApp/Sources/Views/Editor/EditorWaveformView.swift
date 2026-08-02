import Cocoa
import AVFoundation

// MARK: - EditorWaveformView Delegate
protocol EditorWaveformViewDelegate: AnyObject {
    func editorWaveformView(_ view: EditorWaveformView, didChangeSelection range: ClosedRange<TimeInterval>?)
    func editorWaveformView(_ view: EditorWaveformView, didSeekTo time: TimeInterval)
    /// Viewport 变化通知（缩放/滚动后触发，用于同步外部控件）
    func editorWaveformViewDidChangeViewport(_ view: EditorWaveformView)
}

// MARK: - EditorWaveformView
/// 编辑器波形视图 — 支持缩放/滚动/选区拖柄
class EditorWaveformView: NSView {
    
    // MARK: - Properties
    weak var delegate: EditorWaveformViewDelegate?
    
    private var allSamples: [Float] = []
    private var sampleRate: Double = 48000
    private(set) var totalDuration: TimeInterval = 0
    private var channelCount: Int = 2
    
    // Tile mode (V2.0 virtual timeline)
    private var useTileMode: Bool = false
    private var tileProvider: WaveformTileProvider?
    private var currentTiles: [WaveformTile] = []
    private var audioAsset: AudioAsset?
    
    // 视口状态
    private(set) var visibleStartTime: TimeInterval = 0
    private(set) var visibleDuration: TimeInterval = 0
    private(set) var zoomLevel: CGFloat = 1.0

    /// 当前可见时间起点（只读 getter — 供外部 ruler 同步）
    var currentVisibleStartTime: TimeInterval { visibleStartTime }
    /// 当前可见时间长度（只读 getter — 供外部 ruler 同步）
    var currentVisibleDuration: TimeInterval { visibleDuration }
    
    // 选区
    private var selectionStart: TimeInterval?
    private var selectionEnd: TimeInterval?
    
    // 播放游标
    private var playbackTime: TimeInterval = 0
    
    // 交互状态
    private enum DragMode { case none, panScroll, leftHandle, rightHandle, seeking, creating, trimLeft, trimRight }
    private var dragMode: DragMode = .none
    private var dragStartX: CGFloat = 0
    private var dragStartVisibleStart: TimeInterval = 0
    private var dragCreateStartTime: TimeInterval = 0
    private var dragTrimStartTime: TimeInterval = 0  // P1-D: trim 起始值
    
    // P0-C: Clip 视觉边界
    var showClipBorders: Bool = true
    var clipColor: NSColor = IndustrialColors.waveformCoral

    /// P0-C: Clip 名称（绘制在 clip 块上方，作为占位标签）
    /// 后续接入 AudioClip 模型后，改用 `clip.name`
    var clipName: String?
    
    // P1-D: Trim 拖柄位置（相对时间偏移）
    var clipTrimStart: TimeInterval = 0
    var clipTrimEnd: TimeInterval = 0
    
    // P1-E: Split 切分线位置
    var splitPointTime: TimeInterval?
    
    // P2-F: Fade 时长
    var fadeInTime: TimeInterval = 0
    var fadeOutTime: TimeInterval = 0
    
    // 波形绘制参数
    private let barWidth: CGFloat = 1.2
    private let barSpacing: CGFloat = 2.2
    
    // 加载状态
    var isLoading: Bool = false
    var loadError: String?
    
    // Skeleton animation phase (for tile loading placeholder)
    private var skeletonPhase: CGFloat = 0
    private var skeletonTimer: Timer?
    
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
        layer?.borderWidth = 1
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
    }
    
    // MARK: - Public API (Tile Mode)
    
    /// Load audio using tile-based virtual timeline (for large files).
    func loadAudioAsset(_ asset: AudioAsset) {
        isLoading = false
        loadError = nil
        useTileMode = true
        
        self.audioAsset = asset
        self.totalDuration = asset.duration
        self.sampleRate = asset.sampleRate
        self.channelCount = asset.channelCount
        self.allSamples = [] // Clear legacy samples
        
        let provider = WaveformTileProvider(asset: asset)
        provider.delegate = self
        self.tileProvider = provider
        
        fitAll()
        requestVisibleTiles()
    }
    
    /// Request tiles for the current viewport (called after scroll/zoom).
    private func requestVisibleTiles() {
        guard useTileMode, let provider = tileProvider else { return }
        let viewport = TimelineViewport(
            visibleStartTime: visibleStartTime,
            visibleDuration: visibleDuration,
            viewWidth: waveformRect.width
        )
        currentTiles = provider.requestTiles(for: viewport, totalDuration: totalDuration)
        needsDisplay = true
    }
    
    /// Invalidate tile cache for a time range (after edit operations).
    func invalidateTiles(in timeRange: ClosedRange<TimeInterval>) {
        tileProvider?.invalidateTiles(overlapping: timeRange)
        requestVisibleTiles()
    }
    
    /// Invalidate all tile caches (after full buffer replacement).
    func invalidateAllTiles() {
        tileProvider?.invalidateAll()
        requestVisibleTiles()
    }
    
    // MARK: - Public API (Legacy Buffer Mode)

    func loadAudio(from buffer: AVAudioPCMBuffer, sampleRate: Double) {
        useTileMode = false
        tileProvider?.cancelAll()
        tileProvider = nil
        currentTiles = []
        audioAsset = nil
        loadError = nil

        self.sampleRate = sampleRate
        self.channelCount = Int(buffer.format.channelCount)
        let totalFrames = Int(buffer.frameLength)
        self.totalDuration = Double(totalFrames) / sampleRate

        guard let channelData = buffer.floatChannelData, totalFrames > 0 else {
            loadError = "无法读取音频数据"
            isLoading = false
            needsDisplay = true
            return
        }

        let channels = Int(buffer.format.channelCount)
        let viewWidth = bounds.width
        let barW = barWidth
        let barS = barSpacing

        // 剪映策略：先用超低精度采样极速显示全局概览，再异步精细化
        // Phase 1: 立即显示粗略波形（跳跃采样，< 5ms）
        let quickBars = max(100, min(600, Int(viewWidth > 0 ? viewWidth / (barW + barS) : 300)))
        let quickStep = max(1, totalFrames / quickBars)
        var quickPeaks = [Float]()
        quickPeaks.reserveCapacity(quickBars)

        var idx = 0
        while idx < totalFrames && quickPeaks.count < quickBars {
            var peak: Float = 0
            // 只采样 1 个点（不遍历整个 bucket）
            for ch in 0..<channels {
                let s = abs(channelData[ch][idx])
                if s > peak { peak = s }
            }
            quickPeaks.append(peak)
            idx += quickStep
        }

        let quickMax = quickPeaks.max() ?? 1.0
        if quickMax > 0 {
            for i in 0..<quickPeaks.count { quickPeaks[i] /= quickMax }
        }

        // 立即显示（主线程，< 5ms）
        allSamples = quickPeaks
        isLoading = false
        fitAll()
        needsDisplay = true

        // Phase 2: 后台精细计算完整 peak（使用指针算术避免 Swift Range 开销）
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let targetBars = max(200, min(2000, Int(viewWidth > 0 ? viewWidth / (barW + barS) : 600)))
            let framesPerBucket = max(1, totalFrames / targetBars)
            var peaks = [Float](repeating: 0, count: targetBars)

            // 使用指针直接访问，避免 Swift Debug 模式下 Range 迭代的巨大开销
            for ch in 0..<channels {
                let ptr = channelData[ch]
                for bucketIndex in 0..<targetBars {
                    let startFrame = bucketIndex * framesPerBucket
                    let endFrame = min(startFrame + framesPerBucket, totalFrames)
                    var bucketPeak = peaks[bucketIndex]
                    var frame = startFrame
                    while frame < endFrame {
                        let s = abs(ptr[frame])
                        if s > bucketPeak { bucketPeak = s }
                        frame += 1
                    }
                    peaks[bucketIndex] = bucketPeak
                }
            }

            let maxPeak = peaks.max() ?? 1.0
            if maxPeak > 0 {
                for i in 0..<peaks.count { peaks[i] /= maxPeak }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.allSamples = peaks
                self.needsDisplay = true
            }
        }
    }
    
    func setLoadingState() {
        isLoading = true
        loadError = nil
        allSamples = []
        currentTiles = []
        needsDisplay = true
    }

    // MARK: - Viewport State Query & Restore (V2.1 文件联动)

    /// 当前缩放级别
    var currentZoomLevel: Double { Double(zoomLevel) }

    /// 当前滚动偏移（秒）
    var currentScrollOffset: Double { visibleStartTime }

    /// 当前播放头位置（秒）
    var currentPlayheadPosition: Double { playbackTime }

    /// 当前选区范围（采样帧范围）
    var currentSelectionRange: Range<Int>? {
        guard let start = selectionStart, let end = selectionEnd else { return nil }
        let startFrame = Int(start * sampleRate)
        let endFrame = Int(end * sampleRate)
        guard startFrame < endFrame else { return nil }
        return startFrame..<endFrame
    }

    /// 设置缩放级别
    func setZoomLevel(_ level: Double) {
        zoomLevel = CGFloat(max(1.0, level))
        visibleDuration = totalDuration / Double(zoomLevel)
        if useTileMode { requestVisibleTiles() } else { needsDisplay = true }
        delegate?.editorWaveformViewDidChangeViewport(self)
    }

    /// 设置滚动偏移（秒）
    func setScrollOffset(_ offset: Double) {
        visibleStartTime = max(0, min(offset, totalDuration - visibleDuration))
        if useTileMode { requestVisibleTiles() } else { needsDisplay = true }
        delegate?.editorWaveformViewDidChangeViewport(self)
    }

    /// 设置播放头位置（秒）
    func setPlayheadPosition(_ position: Double) {
        playbackTime = max(0, min(position, totalDuration))
        needsDisplay = true
    }
    
    func fitAll() {
        visibleStartTime = 0
        visibleDuration = totalDuration
        zoomLevel = 1.0
        needsDisplay = true
        delegate?.editorWaveformViewDidChangeViewport(self)
    }

    func zoomIn(anchorX: CGFloat? = nil) {
        let anchor = anchorX ?? bounds.midX
        let anchorTime = pixelToTime(anchor)
        zoomLevel = min(zoomLevel * 1.5, maxZoomLevel)
        visibleDuration = totalDuration / Double(zoomLevel)
        visibleStartTime = max(0, min(anchorTime - visibleDuration * Double(anchor / bounds.width), totalDuration - visibleDuration))
        if useTileMode { requestVisibleTiles() } else { needsDisplay = true }
        delegate?.editorWaveformViewDidChangeViewport(self)
    }

    func zoomOut(anchorX: CGFloat? = nil) {
        let anchor = anchorX ?? bounds.midX
        let anchorTime = pixelToTime(anchor)
        zoomLevel = max(zoomLevel / 1.5, 1.0)
        visibleDuration = totalDuration / Double(zoomLevel)
        visibleStartTime = max(0, min(anchorTime - visibleDuration * Double(anchor / bounds.width), totalDuration - visibleDuration))
        if useTileMode { requestVisibleTiles() } else { needsDisplay = true }
        delegate?.editorWaveformViewDidChangeViewport(self)
    }
    
    func setSelection(start: TimeInterval, end: TimeInterval) {
        selectionStart = start
        selectionEnd = end
        needsDisplay = true
        delegate?.editorWaveformView(self, didChangeSelection: start...end)
    }
    
    func clearSelection() {
        selectionStart = nil
        selectionEnd = nil
        needsDisplay = true
        delegate?.editorWaveformView(self, didChangeSelection: nil)
    }
    
    var selection: ClosedRange<TimeInterval>? {
        guard let s = selectionStart, let e = selectionEnd else { return nil }
        return min(s, e)...max(s, e)
    }
    
    func updatePlaybackTime(_ time: TimeInterval) {
        playbackTime = time
        needsDisplay = true
    }
    
    func getAudioInfo() -> (duration: TimeInterval, sampleRate: Double, channels: Int) {
        return (totalDuration, sampleRate, channelCount)
    }
    
    // MARK: - Coordinate Transforms
    
    var maxZoomLevel: CGFloat {
        guard totalDuration > 0 else { return 1.0 }
        return CGFloat(totalDuration * sampleRate / 600)
    }
    
    /// 上下留白（用于 clip 标签 + 视觉呼吸感）
    private let clipInsetVertical: CGFloat = 25

    /// Clip 块矩形（"被吸附"的内容区）— 居中、占轨道行约 64% 高度
    /// 轨道是 140px 容器，clip 块 = 90px，clip 块上下各 25px 留白给标签和呼吸感
    private var waveformRect: NSRect {
        let availableHeight = max(20, bounds.height - clipInsetVertical * 2)
        return NSRect(
            x: 0,
            y: clipInsetVertical,
            width: bounds.width,
            height: availableHeight
        )
    }
    
    private func timeToPixel(_ time: TimeInterval) -> CGFloat {
        guard visibleDuration > 0 else { return 0 }
        return CGFloat((time - visibleStartTime) / visibleDuration) * waveformRect.width + waveformRect.minX
    }
    
    private func pixelToTime(_ x: CGFloat) -> TimeInterval {
        guard waveformRect.width > 0 else { return 0 }
        return visibleStartTime + Double((x - waveformRect.minX) / waveformRect.width) * visibleDuration
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if isLoading {
            drawLoadingState(in: dirtyRect)
            return
        }
        
        if let error = loadError {
            drawErrorState(in: dirtyRect, message: error)
            return
        }
        
        let hasData = useTileMode ? !currentTiles.isEmpty : !allSamples.isEmpty
        guard hasData || useTileMode else {
            drawEmptyState(in: dirtyRect)
            return
        }

        // P0-B: 时间刻度尺由 TrackContainerView 顶部的 TimeRulerView 横向贯通绘制
        // （轨道头列跳过），这里不再调用 drawTimeRuler。
        drawSelectionOverlay(in: dirtyRect)
        
        if useTileMode {
            drawWaveformTiles(in: dirtyRect)
        } else {
            drawWaveformBars(in: dirtyRect)
        }
        
        // P0-C~P2-F: Clip 视觉元素（按层级从底到顶绘制）
        if showClipBorders { drawClipBorders(in: dirtyRect) }
        if splitPointTime != nil { drawClipSplitLine(in: dirtyRect) }
        drawFadeOverlay(in: dirtyRect)          // P2-F: Fade 渐变遮罩
        drawPlayhead(in: dirtyRect)
        drawSelectionHandles(in: dirtyRect)
        drawTrimHandles(in: dirtyRect)           // P1-D: Trim 拖柄
        drawFadeHandles(in: dirtyRect)           // P2-F: Fade 三角拖柄

        // P0-C: Clip 标签（绘制在 clip 块上方 4px 处，标识当前 clip 名称）
        drawClipNameLabel(in: dirtyRect)

        // BUG-010 fix: 无选区时显示操作引导
        if selection == nil {
            drawGuideText(in: dirtyRect)
        }
    }
    
    private func drawLoadingState(in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: IndustrialTypography.body,
            .foregroundColor: IndustrialColors.textTertiary
        ]
        let text = "加载波形..."
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
    
    private func drawErrorState(in rect: NSRect, message: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: IndustrialTypography.body,
            .foregroundColor: IndustrialColors.error
        ]
        let size = message.size(withAttributes: attrs)
        message.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
    
    private func drawEmptyState(in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: IndustrialTypography.body,
            .foregroundColor: IndustrialColors.textTertiary
        ]
        let text = "选择文件进入编辑"
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }
    
    private func drawGuideText(in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: IndustrialTypography.monoDB,
            .foregroundColor: IndustrialColors.textTertiary.withAlphaComponent(0.5)
        ]
        let text = "↔ 在波形上拖拽创建选区，然后使用工具栏操作"
        let size = text.size(withAttributes: attrs)
        // 显示在波形区底部
        let y = waveformRect.minY + 4
        text.draw(at: NSPoint(x: waveformRect.midX - size.width / 2, y: y), withAttributes: attrs)
    }
    
    private func drawTimeRuler(in rect: NSRect) {
        let rulerY = waveformRect.maxY + 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: IndustrialColors.textTertiary.withAlphaComponent(0.68)
        ]

        let tickColor = IndustrialColors.onSurfaceVariant.withAlphaComponent(0.24)
        tickColor.setStroke()
        let tickPath = NSBezierPath()
        tickPath.lineWidth = 1

        // 自适应时间步长 — 目标: 主刻度间隔 60~150px，保证任何缩放级别都有合理密度
        let pixelsPerSecond = waveformRect.width / CGFloat(max(0.001, visibleDuration))

        // 按照目标间距 80px 反算步长，然后对齐到"好看"的整数
        let rawStep = Double(80.0 / pixelsPerSecond)
        let step: TimeInterval
        let subSteps: Int
        let formatLabel: (TimeInterval) -> String

        // 对齐到人类友好的步长：0.01, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300...
        let niceSteps: [TimeInterval] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        var chosenStep: TimeInterval = 5.0
        for ns in niceSteps {
            if ns >= rawStep {
                chosenStep = ns
                break
            }
        }
        step = chosenStep

        // 子刻度数量
        if step < 0.1 {
            subSteps = 5
        } else if step <= 0.5 {
            subSteps = 5
        } else if step <= 2 {
            subSteps = 4
        } else if step <= 10 {
            subSteps = 5
        } else if step == 15 {
            subSteps = 3
        } else if step == 30 {
            subSteps = 6
        } else {
            subSteps = 5
        }

        // 时间格式根据精度自适应
        if step < 0.1 {
            formatLabel = { t in
                let m = Int(t) / 60; let s = Int(t) % 60
                let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 1000)
                return String(format: "%d:%02d.%03d", m, s, ms)
            }
        } else if step < 1.0 {
            formatLabel = { t in
                let m = Int(t) / 60; let s = Int(t) % 60
                let cs = Int((t.truncatingRemainder(dividingBy: 1)) * 10)
                return cs == 0 ? String(format: "%d:%02d", m, s) : String(format: "%d:%02d.%d", m, s, cs)
            }
        } else if step < 60 {
            formatLabel = { t in
                let m = Int(t) / 60; let s = Int(t) % 60
                return String(format: "%d:%02d", m, s)
            }
        } else {
            formatLabel = { t in
                let m = Int(t) / 60; let s = Int(t) % 60
                return String(format: "%d:%02d", m, s)
            }
        }
        
        // 主刻度
        let firstTick = ceil(visibleStartTime / step) * step
        var t = firstTick
        while t <= visibleStartTime + visibleDuration {
            let x = timeToPixel(t)
            
            // 主刻度线（长）
            tickPath.move(to: NSPoint(x: x, y: rulerY))
            tickPath.line(to: NSPoint(x: x, y: rulerY + 8))
            
            // 时间标签
            let label = formatLabel(t)
            label.draw(at: NSPoint(x: x + 2, y: rulerY + 8), withAttributes: attrs)
            
            // 子刻度线（短）
            let subStep = step / Double(subSteps)
            for j in 1..<subSteps {
                let subTime = t + subStep * Double(j)
                let subX = timeToPixel(subTime)
                if subX >= waveformRect.minX && subX <= waveformRect.maxX {
                    tickPath.move(to: NSPoint(x: subX, y: rulerY))
                    tickPath.line(to: NSPoint(x: subX, y: rulerY + 4))
                }
            }
            
            t += step
        }
        tickPath.stroke()
        
        // 中线
        IndustrialColors.gridMedium.withAlphaComponent(0.5).setStroke()
        let centerLine = NSBezierPath()
        centerLine.lineWidth = 1
        centerLine.setLineDash([3, 3], count: 2, phase: 0)
        centerLine.move(to: NSPoint(x: waveformRect.minX, y: waveformRect.midY))
        centerLine.line(to: NSPoint(x: waveformRect.maxX, y: waveformRect.midY))
        centerLine.stroke()
    }
    
    private func drawSelectionOverlay(in rect: NSRect) {
        guard let sel = selection else { return }
        let leftX = timeToPixel(sel.lowerBound)
        let rightX = timeToPixel(sel.upperBound)
        
        // 选区外遮罩（左侧）
        if leftX > waveformRect.minX {
            IndustrialColors.editorDimOverlay.setFill()
            NSBezierPath(rect: NSRect(x: waveformRect.minX, y: waveformRect.minY, width: leftX - waveformRect.minX, height: waveformRect.height)).fill()
        }
        
        // 选区外遮罩（右侧）
        if rightX < waveformRect.maxX {
            IndustrialColors.editorDimOverlay.setFill()
            NSBezierPath(rect: NSRect(x: rightX, y: waveformRect.minY, width: waveformRect.maxX - rightX, height: waveformRect.height)).fill()
        }
    }
    
    private func drawWaveformBars(in rect: NSRect) {
        guard !allSamples.isEmpty, visibleDuration > 0 else { return }
        
        let centerY = waveformRect.midY
        let drawHeight = waveformRect.height * 0.82
        
        // P0-1: 填充波形渲染（Filled Waveform）
        // 构建上下包络路径，替代离散柱状条
        let pixelWidth = waveformRect.width
        let pixelCount = Int(pixelWidth)
        guard pixelCount > 0 else { return }
        
        let startSampleIndex = Int(Double(allSamples.count) * visibleStartTime / totalDuration)
        let endSampleIndex = min(allSamples.count, Int(Double(allSamples.count) * (visibleStartTime + visibleDuration) / totalDuration))
        let sampleRange = max(1, endSampleIndex - startSampleIndex)
        
        // 为每个像素列计算 min/max 峰值（降采样）
        let bucketsCount = min(pixelCount, sampleRange)
        guard bucketsCount > 0 else { return }
        let samplesPerBucket = max(1, sampleRange / bucketsCount)
        
        // 构建上包络路径（从左到右）
        let upperPath = NSBezierPath()
        var lowerPoints: [(x: CGFloat, y: CGFloat)] = []
        var firstPoint = true
        
        for i in 0..<bucketsCount {
            let bucketStart = startSampleIndex + i * samplesPerBucket
            let bucketEnd = min(bucketStart + samplesPerBucket, endSampleIndex)
            guard bucketStart < allSamples.count, bucketEnd <= allSamples.count else { break }
            
            // 取桶内最大值作为包络
            var maxVal: Float = 0
            for j in bucketStart..<bucketEnd {
                let s = allSamples[j]
                if s > maxVal { maxVal = s }
            }
            
            let x = waveformRect.minX + CGFloat(i) / CGFloat(bucketsCount) * pixelWidth
            let amplitude = CGFloat(maxVal) * drawHeight * 0.48
            
            let upperY = centerY + amplitude
            let lowerY = centerY - amplitude
            
            if firstPoint {
                upperPath.move(to: NSPoint(x: x, y: upperY))
                lowerPoints.append((x, lowerY))
                firstPoint = false
            } else {
                upperPath.line(to: NSPoint(x: x, y: upperY))
                lowerPoints.append((x, lowerY))
            }
        }
        
        guard !lowerPoints.isEmpty else { return }
        
        // 合并为闭合填充路径：上包络 → 下包络反向 → 闭合
        let filledPath = NSBezierPath()
        filledPath.append(upperPath)
        for pt in lowerPoints.reversed() {
            filledPath.line(to: NSPoint(x: pt.x, y: pt.y))
        }
        filledPath.close()
        
        // 绘制填充
        IndustrialColors.waveformCoral.withAlphaComponent(0.75).setFill()
        filledPath.fill()
        
        // 绘制包络线（增加波形边缘清晰度）
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
        
        // 选区外遮罩已由 drawSelectionOverlay 处理，这里不重复
    }
    
    private func drawPlayhead(in rect: NSRect) {
        let x = timeToPixel(playbackTime)
        guard x >= waveformRect.minX - 10, x <= waveformRect.maxX + 10 else { return }

        // 顶部三角形手柄（参考剪映/Audio One）
        // P0-B: ruler 已抽离到独立的 TimeRulerView，waveformRect 恢复为整块 bounds；
        //       三角形手柄改为完全在视图内（顶点靠上沿，底边在波形内 ~8px），
        //       不再伸出视图顶部。
        let handleSize: CGFloat = 10
        let handleY = waveformRect.maxY
        let trianglePath = NSBezierPath()
        // 顶点朝上贴在视图顶部内侧
        trianglePath.move(to: NSPoint(x: x, y: handleY - 1))
        // 底边向下 handleSize-2
        trianglePath.line(to: NSPoint(x: x - handleSize / 2, y: handleY - handleSize + 2))
        trianglePath.line(to: NSPoint(x: x + handleSize / 2, y: handleY - handleSize + 2))
        trianglePath.close()
        IndustrialColors.waveformAccent.setFill()
        trianglePath.fill()

        // 贯穿垂直线
        IndustrialColors.waveformAccent.setStroke()
        let playhead = NSBezierPath()
        playhead.lineWidth = 1.5
        playhead.move(to: NSPoint(x: x, y: waveformRect.minY))
        playhead.line(to: NSPoint(x: x, y: handleY - handleSize + 2))
        playhead.stroke()
    }
    
    private func drawSelectionHandles(in rect: NSRect) {
        guard let sel = selection else { return }
        let handleWidth = IndustrialSpacing.editorHandleWidth
        let handleColor = IndustrialColors.editorHandle
        
        for time in [sel.lowerBound, sel.upperBound] {
            let x = timeToPixel(time) - handleWidth / 2
            let handleRect = NSRect(x: x, y: waveformRect.minY + 8, width: handleWidth, height: waveformRect.height - 16)
            
            handleColor.setFill()
            NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
            
            // 抓手纹理（3 条水平线）
            handleColor.withAlphaComponent(0.5).setStroke()
            let lineY = handleRect.midY
            for offset: CGFloat in [-3, 0, 3] {
                let line = NSBezierPath()
                line.lineWidth = 0.5
                line.move(to: NSPoint(x: handleRect.minX + 0.5, y: lineY + offset))
                line.line(to: NSPoint(x: handleRect.maxX - 0.5, y: lineY + offset))
                line.stroke()
            }
        }
    }

    // MARK: - Mouse Interaction

    /// 触控板捏合缩放手势
    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let factor = 1.0 + event.magnification
        let anchorTime = pixelToTime(location.x)

        zoomLevel = max(1.0, min(zoomLevel * CGFloat(factor), maxZoomLevel))
        visibleDuration = totalDuration / Double(zoomLevel)
        visibleStartTime = max(0, min(anchorTime - visibleDuration * Double(location.x / bounds.width),
                                       totalDuration - visibleDuration))

        if useTileMode { requestVisibleTiles() } else { needsDisplay = true }
        delegate?.editorWaveformViewDidChangeViewport(self)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let location = convert(event.locationInWindow, from: nil)
            if event.scrollingDeltaY > 0 {
                zoomIn(anchorX: location.x)
            } else if event.scrollingDeltaY < 0 {
                zoomOut(anchorX: location.x)
            }
        } else {
            let scrollAmount = visibleDuration * Double(event.scrollingDeltaX / bounds.width) * 0.5
            visibleStartTime = max(0, min(visibleStartTime - scrollAmount, totalDuration - visibleDuration))
            if useTileMode { requestVisibleTiles() } else { needsDisplay = true }
            delegate?.editorWaveformViewDidChangeViewport(self)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        dragStartX = location.x
        dragStartVisibleStart = visibleStartTime
        
        // 检查是否命中已有选区拖柄
        if let sel = selection {
            let leftHandleX = timeToPixel(sel.lowerBound)
            let rightHandleX = timeToPixel(sel.upperBound)
            let hitZone = IndustrialSpacing.editorHandleHitZone
            
            if abs(location.x - leftHandleX) < hitZone {
                dragMode = .leftHandle
                return
            }
            if abs(location.x - rightHandleX) < hitZone {
                dragMode = .rightHandle
                return
            }
        }
        
        // 点击 = 先移动游标（seek），拖拽超过阈值才创建选区
        let time = max(0, min(pixelToTime(location.x), totalDuration))
        dragCreateStartTime = time
        dragMode = .seeking
        // 立即 seek 到点击位置
        playbackTime = time
        needsDisplay = true
        delegate?.editorWaveformView(self, didSeekTo: time)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let time = max(0, min(pixelToTime(location.x), totalDuration))
        
        switch dragMode {
        case .leftHandle:
            if let end = selectionEnd {
                selectionStart = min(time, end - 0.1)
                needsDisplay = true
                if let sel = selection { delegate?.editorWaveformView(self, didChangeSelection: sel) }
            }
        case .rightHandle:
            if let start = selectionStart {
                selectionEnd = max(time, start + 0.1)
                needsDisplay = true
                if let sel = selection { delegate?.editorWaveformView(self, didChangeSelection: sel) }
            }
        case .seeking:
            // 拖拽超过 5px 阈值 → 转为创建选区
            if abs(location.x - dragStartX) > 5 {
                dragMode = .creating
                selectionStart = min(dragCreateStartTime, time)
                selectionEnd = max(dragCreateStartTime, time)
                needsDisplay = true
                if let sel = selection { delegate?.editorWaveformView(self, didChangeSelection: sel) }
            } else {
                // 仍在拖拽阈值内，更新 seek 位置
                playbackTime = time
                needsDisplay = true
                delegate?.editorWaveformView(self, didSeekTo: time)
            }
        case .creating:
            selectionStart = min(dragCreateStartTime, time)
            selectionEnd = max(dragCreateStartTime, time)
            needsDisplay = true
            if let sel = selection { delegate?.editorWaveformView(self, didChangeSelection: sel) }
        default:
            break
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if dragMode == .creating {
            if let sel = selection, (sel.upperBound - sel.lowerBound) < 0.05 {
                clearSelection()
            } else {
                window?.invalidateCursorRects(for: self)
            }
        }
        dragMode = .none
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let sel = selection else { return }
        let hitZone = IndustrialSpacing.editorHandleHitZone
        
        let leftX = timeToPixel(sel.lowerBound)
        let rightX = timeToPixel(sel.upperBound)
        
        addCursorRect(NSRect(x: leftX - hitZone, y: waveformRect.minY, width: hitZone * 2, height: waveformRect.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: rightX - hitZone, y: waveformRect.minY, width: hitZone * 2, height: waveformRect.height), cursor: .resizeLeftRight)
    }
    
    // MARK: - Tile Rendering
    
    private func drawWaveformTiles(in rect: NSRect) {
        guard visibleDuration > 0 else { return }
        
        let centerY = waveformRect.midY
        let drawHeight = waveformRect.height * 0.82
        let step = barWidth + barSpacing
        
        if currentTiles.isEmpty {
            // No tiles available yet — draw skeleton placeholder
            drawSkeletonWaveform(in: rect)
            return
        }
        
        for tile in currentTiles {
            guard !tile.peaks.isEmpty, tile.duration > 0 else { continue }
            
            let peakDuration = tile.duration / Double(tile.peaks.count)
            
            for (i, peak) in tile.peaks.enumerated() {
                let peakTime = tile.sourceStartTime + Double(i) * peakDuration
                
                // Skip peaks outside visible range
                guard peakTime + peakDuration >= visibleStartTime,
                      peakTime <= visibleStartTime + visibleDuration else { continue }
                
                let x = timeToPixel(peakTime)
                guard x >= waveformRect.minX - step, x <= waveformRect.maxX + step else { continue }
                
                let amplitude = max(1.5, CGFloat(peak.amplitude) * drawHeight * 0.5)
                
                let isInSelection = selection.map { $0.contains(peakTime) } ?? true
                let level = CGFloat(peak.amplitude)
                let alpha: CGFloat = isInSelection
                    ? max(0.34, min(1.0, 0.34 + level * 0.66))
                    : max(0.15, min(0.4, 0.15 + level * 0.25))
                
                let barRect = NSRect(x: x, y: centerY - amplitude, width: barWidth, height: amplitude * 2)
                let path = NSBezierPath(roundedRect: barRect, xRadius: 0.6, yRadius: 0.6)
                IndustrialColors.waveformCoral.withAlphaComponent(alpha).setFill()
                path.fill()
            }
        }
    }
    
    private func drawSkeletonWaveform(in rect: NSRect) {
        let centerY = waveformRect.midY
        let drawHeight = waveformRect.height * 0.82
        let step = barWidth + barSpacing
        let barCount = Int(waveformRect.width / step)
        
        // Draw low-opacity placeholder bars with subtle animation hint
        for i in 0..<barCount {
            let x = waveformRect.minX + CGFloat(i) * step
            let phase = sin(CGFloat(i) * 0.15 + skeletonPhase) * 0.3 + 0.5
            let amplitude = max(1.5, phase * drawHeight * 0.2)
            
            let barRect = NSRect(x: x, y: centerY - amplitude, width: barWidth, height: amplitude * 2)
            let path = NSBezierPath(roundedRect: barRect, xRadius: 0.6, yRadius: 0.6)
            IndustrialColors.waveformCoral.withAlphaComponent(0.12).setFill()
            path.fill()
        }
    }
}

// MARK: - WaveformTileProviderDelegate
extension EditorWaveformView: WaveformTileProviderDelegate {
    func tileProvider(_ provider: WaveformTileProvider, didLoadTiles keys: [WaveformTileKey]) {
        // Tiles are now available — re-request to pick them up from cache
        requestVisibleTiles()
    }
    
    func tileProvider(_ provider: WaveformTileProvider, didFailForKey key: WaveformTileKey, error: Error) {
        // Tile generation failed — log but don't block other tiles
        // The skeleton will remain for this tile's region
    }
}

// MARK: - P0-C Clip 视觉边界（无边框，参考剪映）
extension EditorWaveformView {

    /// P0-C: 无边框版 — 不画描边，仅保留扩展点（后续可画极淡背景 fill）
    /// 剪映风格：轨道无边框、clip 无边框，靠波形本身和 chip 标签标识
    private func drawClipBorders(in rect: NSRect) {
        // 故意留空：移除原描边（半透明白色 stroke），参考剪映无边框风格
    }

    /// 绘制 clip 名称 chip — 位于 clip 块**内部左上角**（inset 8px）
    /// 剪映风格：深色半透明圆角背景 + 白字，作为悬浮在波形左上角的"标签 chip"
    /// （占位实现：当前用轨道名/文件名；后续接入 AudioClip 后改用 clip.name）
    private func drawClipNameLabel(in rect: NSRect) {
        guard let name = clipName, !name.isEmpty else { return }
        guard waveformRect.width > 16, waveformRect.height > 16 else { return }

        // 1) 文字属性（剪映风格：白字 + 10pt medium）
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        // 2) 截断（避免超出波形块宽度）
        let maxWidth = waveformRect.width - 24  // 两侧各留 8px inset
        let truncated = truncate(name: name, font: font, maxWidth: maxWidth)
        let textSize = truncated.size(withAttributes: textAttrs)

        // 3) chip 几何：clip 块左上角内 8px，圆角 4px，padding 6x3
        let chipRect = NSRect(
            x: waveformRect.minX + 8,
            y: waveformRect.maxY - textSize.height - 12,  // macOS Y 向上，maxY 是顶部
            width: textSize.width + 12,
            height: textSize.height + 6
        )
        guard chipRect.maxX <= waveformRect.maxX - 4 else { return }  // 超出波形右边界不画

        // 4) chip 背景：黑色半透明 55% 圆角
        let chipPath = NSBezierPath(roundedRect: chipRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.55).setFill()
        chipPath.fill()

        // 5) 文字绘制（chip 内居中）
        let textPoint = NSPoint(
            x: chipRect.minX + 6,
            y: chipRect.minY + 3
        )
        truncated.draw(at: textPoint, withAttributes: textAttrs)
    }

    /// 按 maxWidth 截断文字（添加 ellipsis）
    private func truncate(name: String, font: NSFont, maxWidth: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if name.size(withAttributes: attrs).width <= maxWidth {
            return name
        }
        let ellipsis = "…"
        _ = ellipsis.size(withAttributes: attrs).width
        var endIndex = name.endIndex
        while endIndex > name.startIndex {
            let candidate = String(name[name.startIndex..<endIndex]) + ellipsis
            if candidate.size(withAttributes: attrs).width <= maxWidth {
                return candidate
            }
            endIndex = name.index(before: endIndex)
        }
        return ellipsis
    }
}

// MARK: - P1-D Trim 拖柄
extension EditorWaveformView {
    
    /// 绘制 trim 拖柄（cyan 竖线 + 抓握线）
    private func drawTrimHandles(in rect: NSRect) {
        guard selection != nil else { return }
        
        let trimColor = IndustrialColors.waveformAccent
        let handleWidth: CGFloat = 4
        
        // 左 trim 拖柄
        let leftTime = clipTrimStart > 0 ? clipTrimStart : (selectionStart ?? visibleStartTime)
        let leftX = timeToPixel(leftTime)
        if leftX >= waveformRect.minX && leftX <= waveformRect.maxX {
            let leftHandleRect = NSRect(
                x: leftX - handleWidth / 2,
                y: waveformRect.minY + 4,
                width: handleWidth,
                height: waveformRect.height - 8
            )
            let leftPath = NSBezierPath(roundedRect: leftHandleRect, xRadius: 1, yRadius: 2)
            trimColor.setFill()
            leftPath.fill()
            
            // 三条抓握横线
            drawGripLines(at: leftX, in: waveformRect, color: trimColor)
        }
        
        // 右 trim 拖柄
        let clipEnd = clipTrimEnd > 0 ? clipTrimEnd : totalDuration
        let rightTime = selectionEnd ?? totalDuration
        let rightX = timeToPixel(min(rightTime, clipEnd == 0 ? totalDuration : clipEnd))
        if rightX >= waveformRect.minX && rightX <= waveformRect.maxX {
            let rightHandleRect = NSRect(
                x: rightX - handleWidth / 2,
                y: waveformRect.minY + 4,
                width: handleWidth,
                height: waveformRect.height - 8
            )
            let rightPath = NSBezierPath(roundedRect: rightHandleRect, xRadius: 1, yRadius: 2)
            trimColor.setFill()
            rightPath.fill()
            
            // 三条抓握横线
            drawGripLines(at: rightX, in: waveformRect, color: trimColor)
        }
    }
    
    /// 在 x 位置绘制抓握线
    private func drawGripLines(at x: CGFloat, in rect: NSRect, color: NSColor) {
        color.setStroke()
        for i in 0..<3 {
            let cy = rect.midY - 6 + CGFloat(i) * 6
            let path = NSBezierPath()
            path.lineWidth = 0.5
            path.move(to: NSPoint(x: x - 1.5, y: cy))
            path.line(to: NSPoint(x: x + 1.5, y: cy))
            path.stroke()
        }
    }
}

// MARK: - P1-E Split 切分虚线
extension EditorWaveformView {
    
    /// 绘制切分点虚线
    private func drawClipSplitLine(in rect: NSRect) {
        guard let splitTime = splitPointTime else { return }
        let x = timeToPixel(splitTime)
        guard x >= waveformRect.minX && x <= waveformRect.maxX else { return }
        
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        
        let dash: [CGFloat] = [4, 4]
        path.setLineDash(dash, count: 2, phase: 0)
        path.move(to: NSPoint(x: x, y: waveformRect.minY + 4))
        path.line(to: NSPoint(x: x, y: waveformRect.maxY - 4))
        path.stroke()
    }
}

// MARK: - P2-F Fade 拖柄 & 渐变遮罩
extension EditorWaveformView {
    
    /// 绘制 fade 渐变遮罩（淡入/淡出区域波形渐变透明）
    private func drawFadeOverlay(in rect: NSRect) {
        guard fadeInTime > 0 || fadeOutTime > 0 else { return }
        
        if fadeInTime > 0 {
            let fadeRightX = timeToPixel(visibleStartTime + fadeInTime)
            let fadeLeftX = timeToPixel(visibleStartTime)
            let fadeWidth = fadeRightX - fadeLeftX
            if fadeWidth > 0 {
                // 渐变从透明（波形正常）到不透明（覆盖波形）
                let gradient = NSGradient(
                    starting: IndustrialColors.surfaceContainer.withAlphaComponent(0.6),
                    ending: IndustrialColors.surfaceContainer.withAlphaComponent(0.0)
                )
                let fadeFrame = NSRect(x: fadeLeftX, y: waveformRect.minY + 2, width: fadeWidth, height: waveformRect.height - 4)
                gradient?.draw(in: fadeFrame, angle: 0)
            }
        }
        
        if fadeOutTime > 0 {
            let fadeLeftX = timeToPixel(totalDuration - fadeOutTime)
            let fadeRightX = timeToPixel(totalDuration)
            let fadeWidth = fadeRightX - fadeLeftX
            if fadeWidth > 0 {
                let gradient = NSGradient(
                    starting: IndustrialColors.surfaceContainer.withAlphaComponent(0.0),
                    ending: IndustrialColors.surfaceContainer.withAlphaComponent(0.6)
                )
                let fadeFrame = NSRect(x: fadeLeftX, y: waveformRect.minY + 2, width: fadeWidth, height: waveformRect.height - 4)
                gradient?.draw(in: fadeFrame, angle: 0)
            }
        }
    }
    
    /// 绘制 fade 白色三角拖柄
    private func drawFadeHandles(in rect: NSRect) {
        guard selection != nil else { return }
        
        let triangleSize: CGFloat = 8
        
        // 淡入三角（左上角）
        if fadeInTime > 0 {
            let fx = timeToPixel(visibleStartTime + fadeInTime)
            let fy = waveformRect.maxY - 4
            drawTriangle(at: NSPoint(x: fx, y: fy), size: triangleSize, pointing: .up, color: .white)
        }
        
        // 淡出三角（右上角）
        if fadeOutTime > 0 {
            let fx = timeToPixel(totalDuration - fadeOutTime)
            let fy = waveformRect.maxY - 4
            drawTriangle(at: NSPoint(x: fx, y: fy), size: triangleSize, pointing: .up, color: .white)
        }
    }
    
    private enum TriangleDirection { case up, down, left, right }
    
    private func drawTriangle(at point: NSPoint, size: CGFloat, pointing: TriangleDirection, color: NSColor) {
        color.setFill()
        let path = NSBezierPath()
        let hw = size / 2
        let hh = size * 0.866 / 2  // equilateral triangle height
        
        switch pointing {
        case .up:
            path.move(to: NSPoint(x: point.x, y: point.y + hh))
            path.line(to: NSPoint(x: point.x - hw, y: point.y - hh))
            path.line(to: NSPoint(x: point.x + hw, y: point.y - hh))
        case .down:
            path.move(to: NSPoint(x: point.x, y: point.y - hh))
            path.line(to: NSPoint(x: point.x - hw, y: point.y + hh))
            path.line(to: NSPoint(x: point.x + hw, y: point.y + hh))
        case .left:
            path.move(to: NSPoint(x: point.x - hh, y: point.y))
            path.line(to: NSPoint(x: point.x + hh, y: point.y - hw))
            path.line(to: NSPoint(x: point.x + hh, y: point.y + hw))
        case .right:
            path.move(to: NSPoint(x: point.x + hh, y: point.y))
            path.line(to: NSPoint(x: point.x - hh, y: point.y - hw))
            path.line(to: NSPoint(x: point.x - hh, y: point.y + hw))
        }
        path.close()
        path.fill()
    }
}
