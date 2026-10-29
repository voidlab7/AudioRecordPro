import Cocoa
import AVFoundation

// MARK: - EditorWaveformView Delegate
protocol EditorWaveformViewDelegate: AnyObject {
func editorWaveformView(_ view: EditorWaveformView, didChangeSelection range: ClosedRange<TimeInterval>?)
func editorWaveformView(_ view: EditorWaveformView, didSeekTo time: TimeInterval)
/// UI-034: clip 增益变化（拖拽音量线触发；播放预览联动，导出不应用）
func editorWaveformView(_ view: EditorWaveformView, didChangeGain gain: Float)
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
    // UI-029: clip 选中态标记——用户首次点击/拖拽波形后置 true（选中描边显示条件）
    private var isClipInteracted = false
    
    // 播放游标
    private var playbackTime: TimeInterval = 0
    
    // 交互状态
    private enum DragMode { case none, panScroll, leftHandle, rightHandle, seeking, creating, trimLeft, trimRight, gainDrag }
    private var dragMode: DragMode = .none
    private var dragStartX: CGFloat = 0
    private var dragStartVisibleStart: TimeInterval = 0
    private var dragCreateStartTime: TimeInterval = 0
    private var dragTrimStartTime: TimeInterval = 0  // P1-D: trim 起始值
    
    // P0-C: Clip 视觉边界
    var showClipBorders: Bool = true
    var clipColor: NSColor = IndustrialColors.waveformBase

    /// P0-C: Clip 名称（绘制在 clip 块上方，作为占位标签）
    /// 后续接入 AudioClip 模型后，改用 `clip.name`
    var clipName: String?
    
    // P1-E: Split 切分线位置
    var splitPointTime: TimeInterval?

    // UI-021: 转写句↔波形联动区间（teal 10% 底 + 左右 2px teal 边；B 稿 state=5 segLink）
    var segmentHighlight: ClosedRange<TimeInterval>? {
        didSet { if oldValue != segmentHighlight { needsDisplay = true } }
    }
    
    // P2-F: Fade 时长
    var fadeInTime: TimeInterval = 0
    var fadeOutTime: TimeInterval = 0

    // UI-034: clip 级播放增益（1.0=100%）。R1 仅渲染高度映射（播放链路 R2 接线）；
    // 老板拍板 a：音量仅播放预览+界面可视化，导出=原始音频
    var clipGain: Float = 1.0 {
        didSet {
            let clamped = max(0, min(clipGain, 2.0))
            if clamped != clipGain { clipGain = clamped; return }
            if oldValue != clipGain { needsDisplay = true }
        }
    }

    /// UI-034: 波形上缘到 clip 顶的音量线活动带高度（R2 音量线+拖拽点在此带内）
    static let volumeLaneHeight: CGFloat = 18
    
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
            loadError = "无法读取音频数据".localized
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
        // FIX-010: 与录音态共用同一映射函数（整段 max 线性归一化 + 静音门限）
        for i in 0..<quickPeaks.count {
            quickPeaks[i] = WaveformAmplitudeMapper.normalized(quickPeaks[i], referenceMax: quickMax)
        }

        // 立即显示（主线程，< 5ms）
        allSamples = quickPeaks
        isLoading = false
        fitAll()
        needsDisplay = true

        // Phase 2: 后台精细计算完整 peak（使用指针算术避免 Swift Range 开销）
        // INFRA-006 竞态修复: 必须捕获 buffer 保活——此前只捕 weak self、却解引用外层 channelData 裸指针，
        // 连续编辑（undo/redo/delete）替换 audioBuffer 后旧 buffer 释放 → 后台闭包 use-after-free（SIGSEGV，
        // 崩溃报告 Loocap-2026-10-22-225344.ips 实锤；lite 通道毫秒级连发首跑钓出）。
        DispatchQueue.global(qos: .utility).async { [weak self, buffer] in
            guard let self = self, let channelData = buffer.floatChannelData else { return }

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
            // FIX-010: 与录音态共用同一映射函数（Phase 1/2 同口径，无先后跳变）
            for i in 0..<peaks.count {
                peaks[i] = WaveformAmplitudeMapper.normalized(peaks[i], referenceMax: maxPeak)
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
        drawSegmentHighlight(in: dirtyRect)    // UI-021: 句区间高亮（波形下层）
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
        // 注：playhead 抽离到 TrackContainerView 层的 PlayheadOverlayView 统一绘制，
        //     x 坐标与 ruler 共享同一公式（精准卡住时间刻度）
        drawSelectionHandles(in: dirtyRect)
        drawTrimHandles(in: dirtyRect)           // P1-D: Trim 拖柄
        drawFadeHandles(in: dirtyRect)           // P2-F: Fade 三角拖柄

        // P0-C: Clip 标签（绘制在 clip 块上方 4px 处，标识当前 clip 名称）
        drawClipNameLabel(in: dirtyRect)

        // UI-035: 波形底部操作引导文字已移除（老板 10-27「这个字体不要」；
        // 引导虽删，选区/工具栏交互照旧）
    }
    
    private func drawLoadingState(in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: IndustrialTypography.body,
            .foregroundColor: IndustrialColors.textTertiary
        ]
        let text = "加载波形...".localized
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
        let text = "选择文件进入编辑".localized
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
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
    
    /// UI-021: 转写句区间高亮（B 稿 state=5 segLink：teal 10% 底 + 左右 2px teal 边）
    private func drawSegmentHighlight(in rect: NSRect) {
        guard let range = segmentHighlight, range.lowerBound < totalDuration else { return }
        let leftX = max(waveformRect.minX, timeToPixel(range.lowerBound))
        let rightX = min(waveformRect.maxX, timeToPixel(range.upperBound))
        guard rightX > leftX else { return }
        let bandRect = NSRect(x: leftX, y: waveformRect.minY, width: rightX - leftX, height: waveformRect.height)
        IndustrialColors.primary.withAlphaComponent(0.10).setFill()
        NSBezierPath(rect: bandRect).fill()
        // 左右 2px teal 边
        IndustrialColors.primary.setStroke()
        for edgeX in [leftX + 1, rightX - 1] {
            let line = NSBezierPath()
            line.lineWidth = 2
            line.move(to: NSPoint(x: edgeX, y: waveformRect.minY))
            line.line(to: NSPoint(x: edgeX, y: waveformRect.maxY))
            line.stroke()
        }
    }

    private func drawSelectionOverlay(in rect: NSRect) {
        // UI-029: clip 选中亮框改为「选中才显示」——默认（打开编辑器）无边框（老板 10-27：
        // 「默认没有这个选中的边框」；拍板 a=选中保留细描边，剪映同款）。
        // 单 clip 检视器无「点空白取消」语义：用户首次点击/拖拽波形即视为选中（isClipInteracted）；
        // 每次进编辑器都是新视图实例，交互标记天然重置
        if !allSamples.isEmpty && isClipInteracted {
            let borderRect = waveformRect.insetBy(dx: 1, dy: 8)
            let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: IndustrialSpacing.editorClipSelectionRadius, yRadius: IndustrialSpacing.editorClipSelectionRadius)
            IndustrialColors.editorClipSelectionFill.setFill()
            borderPath.fill()
            IndustrialColors.editorClipSelectionStroke.setStroke()
            borderPath.lineWidth = 1.5
            borderPath.stroke()
        }

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

        // UI-034 R1: 单边语义——顶部留 volumeLaneHeight 给音量线（剪映语言）
        let drawHeight = envelopeFullHeight

        // UI-025 R2: 剪映式实心剪影（老板 10-25 深夜对比图打回柱状——回改连续填充包络，
        // 底版=原 P0-1 填充波形，加 FIX-004 静音基线与包络平滑）；UI-034 R1 起改单边向上
        let pixelCount = max(2, Int(waveformRect.width))
        let startSampleIndex = Int(Double(allSamples.count) * visibleStartTime / totalDuration)
        let endSampleIndex = min(allSamples.count, Int(Double(allSamples.count) * (visibleStartTime + visibleDuration) / totalDuration))
        let sampleRange = max(1, endSampleIndex - startSampleIndex)
        let samplesPerColumn = max(1, sampleRange / pixelCount)

        var points: [(x: CGFloat, amp: CGFloat)] = []
        points.reserveCapacity(pixelCount)

        // UI-036 R15d 修复：列→样本按「时间比例」映射。旧实现每列固定步进 samplesPerColumn=max(1, range/pixels)
        // 个样本，样本数 < 像素数时（如 Phase2 targetBars=250 vs 851px）波形只画 count/pixels 比例就 break——
        // 右端截断、与 clip 边框错位（老板 10-29 实机圈红）；且 Phase1/Phase2 样本数不同导致截断位置漂移。
        // 新实现：列 i 取样本区间 [frac0·range, frac1·range)，样本复用铺满全宽。
        for i in 0..<pixelCount {
            let frac0 = Double(i) / Double(pixelCount)
            let frac1 = Double(i + 1) / Double(pixelCount)
            let bucketStart = startSampleIndex + Int(frac0 * Double(sampleRange))
            var bucketEnd = startSampleIndex + max(Int(frac0 * Double(sampleRange)) + 1, Int(frac1 * Double(sampleRange)))
            bucketEnd = min(max(bucketEnd, bucketStart + 1), endSampleIndex)
            guard bucketStart < allSamples.count, bucketEnd <= allSamples.count else { break }

            // 取桶内最大值作为包络
            var maxVal: Float = 0
            for j in bucketStart..<bucketEnd {
                let s = allSamples[j]
                if s > maxVal { maxVal = s }
            }

            let x = waveformRect.minX + CGFloat(i) / CGFloat(pixelCount - 1) * waveformRect.width
            // FIX-004 同款下限：静音段保留 3pt 基线带；UI-034 R1: amp=自基线向上全高（镜像 *0.5 退役）
            let amplitude = max(1.5, CGFloat(maxVal) * drawHeight)
            points.append((x: x, amp: amplitude))
        }

        smoothEnvelope(&points)
        drawGainAwareEnvelope(points: points)
        // 选区外遮罩已由 drawSelectionOverlay 处理，这里不重复
    }

    private func drawSelectionHandles(in rect: NSRect) {
        guard let sel = selection else { return }
        let handleWidth = IndustrialSpacing.editorHandleWidth
        let handleColor = IndustrialColors.editorHandle

        // UI-020: B 稿 .hdl i — 高 60% 圆角 2，垂直居中于亮框
        let borderRect = waveformRect.insetBy(dx: 1, dy: 8)
        let handleHeight = borderRect.height * 0.6
        let handleY = borderRect.midY - handleHeight / 2

        for time in [sel.lowerBound, sel.upperBound] {
            let x = timeToPixel(time) - handleWidth / 2
            let handleRect = NSRect(x: x, y: handleY, width: handleWidth, height: handleHeight)

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
        // UI-029: 任何点击/拖拽波形都视为「选中 clip」（选中描边自此显示；进编辑器默认无边框）
        isClipInteracted = true
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

        // UI-034 R2: 音量线拖拽判定（拖拽圆点 ±14pt 或音量线 ±8pt）——优先于 seek
        if isHitVolumeGrip(location) {
            dragMode = .gainDrag
            applyGainDrag(to: location)
            return
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
        case .gainDrag:
            applyGainDrag(to: location)
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

        if currentTiles.isEmpty {
            // No tiles available yet — draw skeleton placeholder
            drawSkeletonWaveform(in: rect)
            return
        }

        // UI-025 R2: 剪映式实心剪影——peak 序列一次包络填充（离散柱状打回，老板对比图 10-25）。
        // FIX-010 幅度映射保留（WaveformAmplitudeMapper.normalized，静音门限仍生效）；
        // 柱状时代的 per-bar alpha 渐变随柱状语言退役——剪影单色填充，与 bars 路径行为对齐。
        // UI-034 R1 起改单边向上（顶部留 volumeLaneHeight 给音量线）。
        var points: [(x: CGFloat, amp: CGFloat)] = []
        let drawHeight = envelopeFullHeight

        for tile in currentTiles {
            guard !tile.peaks.isEmpty, tile.duration > 0 else { continue }

            let peakDuration = tile.duration / Double(tile.peaks.count)

            for (i, peak) in tile.peaks.enumerated() {
                let peakTime = tile.sourceStartTime + Double(i) * peakDuration

                // Skip peaks outside visible range
                guard peakTime + peakDuration >= visibleStartTime,
                      peakTime <= visibleStartTime + visibleDuration else { continue }

                let x = timeToPixel(peakTime)
                // ±2pt 容差桥接 tile 边界，避免剪影在 tile 接缝断开
                guard x >= waveformRect.minX - 2, x <= waveformRect.maxX + 2 else { continue }

                let mapped = WaveformAmplitudeMapper.normalized(peak.amplitude, referenceMax: 1.0)
                // UI-034 R1: amp=自基线向上全高（镜像 *0.5 退役）
                let amplitude = max(1.5, CGFloat(mapped) * drawHeight)
                points.append((x: x, amp: amplitude))
            }
        }

        guard !points.isEmpty else { return }
        points.sort { $0.x < $1.x }
        smoothEnvelope(&points)
        drawGainAwareEnvelope(points: points)
    }

    private func drawSkeletonWaveform(in rect: NSRect) {
        // UI-034 R1: 占位剪影同走单边语言（低透明度 + 呼吸动画）
        let drawHeight = envelopeFullHeight
        let pixelCount = max(2, Int(waveformRect.width))

        var points: [(x: CGFloat, amp: CGFloat)] = []
        points.reserveCapacity(pixelCount)
        for i in 0..<pixelCount {
            let x = waveformRect.minX + CGFloat(i) / CGFloat(pixelCount - 1) * waveformRect.width
            let phase = sin(CGFloat(i) * 0.15 + skeletonPhase) * 0.3 + 0.5
            points.append((x: x, amp: max(1.5, phase * drawHeight * 0.2)))
        }
        smoothEnvelope(&points)
        WaveformEnvelopeRenderer.fillUpward(points: points, baselineY: waveformRect.minY + 2,
                                            color: IndustrialColors.waveformBase.withAlphaComponent(0.12))
    }

    // MARK: - UI-034 R1: 剪映式单边波形 + 音量暗轮廓分层

    /// UI-034: 100% 增益满幅高度（渲染与拖拽换算共用标尺）
    private var envelopeFullHeight: CGFloat {
        (waveformRect.height - Self.volumeLaneHeight) * 0.82
    }
    /// UI-034: 波形基线 y（clip 下缘对齐）
    private var envelopeBaselineY: CGFloat { waveformRect.minY + 2 }
    /// UI-034: 波形最大渲染高度（触顶前上限）
    private var envelopeMaxAmp: CGFloat { waveformRect.height - 4 - Self.volumeLaneHeight }
    /// UI-034: 音量线 y = 满幅标尺 × gain；过 100% 后钳到 maxAmp
    private var volumeLineY: CGFloat {
        envelopeBaselineY + min(envelopeFullHeight * CGFloat(clipGain), envelopeMaxAmp)
    }
    /// UI-034: 过载态（gain > 100%）
    private var isOverdriven: Bool { clipGain > 1.001 }

    /// 单边渲染入口：波形贴 clip 下缘向上生长（下半让位剪映语言）。
    /// UI-036 R15b（老板实机 10-29）：①过载变红=**波形顶部溢出段**变红（超过 100% 满幅的部分），
    /// 波形 0…100% 段与音量线均不变红；②音量线/圆点改「很浅」的低存在感样式（恒浅色，永不变红）。
    /// UI-036 R15c（老板实机 10-29）：③删除暗轮廓层（调音量后波纹「重影」，原始形状不再叠加显示）；
    /// ④删除播放头×音量线交叉处的拖拽圆点（拖拽热区保留，只去视觉）。
    /// points 的 amp 已含 FIX-004 静音基线下限（1.5pt 半带）与包络平滑，按 100% 音量标定。
    private func drawGainAwareEnvelope(points: [(x: CGFloat, amp: CGFloat)]) {
        guard !points.isEmpty else { return }
        let baselineY = envelopeBaselineY
        let maxAmp = envelopeMaxAmp
        let fullHeight = envelopeFullHeight

        // UI-036 R15b: 过载溢出层——先画增益高度整段警示色，再用基色盖住 0…100% 段，
        // 只露出超过满幅标尺的「顶部」段（老板：变红说的是波纹，且只有顶部）
        if isOverdriven {
            let driven = points.map { (x: $0.x, amp: max(1.5, min($0.amp * CGFloat(clipGain), maxAmp))) }
            WaveformEnvelopeRenderer.fillUpward(points: driven, baselineY: baselineY,
                                                color: IndustrialColors.waveformOverdrive)
        }

        // 波形主体（基色）：gain≤100% 时=amp×gain；过载时钳到 100% 满幅（溢出段已由红色层画出）
        let cap = isOverdriven ? fullHeight : maxAmp
        let scaled = points.map { (x: $0.x, amp: max(1.5, min($0.amp * CGFloat(clipGain), cap))) }
        WaveformEnvelopeRenderer.fillUpward(points: scaled, baselineY: baselineY,
                                            color: IndustrialColors.waveformBase)

        drawVolumeLine()
    }

    /// UI-034 R2: 音量包络线（横贯 clip 的水平线，y=gain 满幅标尺×gain）
    /// UI-036 R15b: 恒「很浅」低存在感（白色半透明），过载也不变红（红色只属波形顶部溢出段）
    /// UI-036 R15c: 播放头交叉处的拖拽圆点删除（老板：这个交叉点不要）；拖拽热区在线上不变
    private func drawVolumeLine() {
        let lineColor = NSColor.white.withAlphaComponent(0.35)
        let y = volumeLineY

        let line = NSBezierPath()
        line.lineWidth = 1.5
        line.move(to: NSPoint(x: waveformRect.minX + 2, y: y))
        line.line(to: NSPoint(x: waveformRect.maxX - 2, y: y))
        lineColor.setStroke()
        line.stroke()
    }

    /// UI-034 R2: 音量拖拽热区——拖拽圆点 ±14pt 或音量线 ±8pt（限 clip 区内）
    private func isHitVolumeGrip(_ location: NSPoint) -> Bool {
        guard location.x >= waveformRect.minX, location.x <= waveformRect.maxX,
              location.y >= waveformRect.minY, location.y <= waveformRect.maxY else { return false }
        let y = volumeLineY
        let dotX = min(max(timeToPixel(playbackTime), waveformRect.minX + 12), waveformRect.maxX - 12)
        let nearDot = abs(location.x - dotX) < 14 && abs(location.y - y) < 14
        let nearLine = location.y > y - 8 && location.y < y + 8
        return nearDot || nearLine
    }

    /// UI-034 R2: 拖拽换算——鼠标 y 反解 gain（0...2.0），渲染与播放联动同步走
    private func applyGainDrag(to location: NSPoint) {
        let raw = (location.y - envelopeBaselineY) / envelopeFullHeight
        clipGain = Float(min(max(raw, 0), 2.0))
        delegate?.editorWaveformView(self, didChangeGain: clipGain)
    }

    // MARK: - UI-025 R2: 剪映式实心镜像剪影共用件（类内薄封装，实现在文件尾 WaveformEnvelopeRenderer）

    /// 由幅度点列构建上下镜像闭合包络，一次填充（连续剪影，替代离散柱状）。
    /// points 需按 x 升序且无重复；amp 为半高（centerY±amp），已含静音基线下限。
    private func fillMirrorEnvelope(points: [(x: CGFloat, amp: CGFloat)], centerY: CGFloat, color: NSColor) {
        WaveformEnvelopeRenderer.fillMirror(points: points, centerY: centerY, color: color)
    }

    /// 包络点 3 点加权移动平均（首尾保形）：削像素级锯齿，保留峰谷自然起伏（对标剪映参考轮廓）
    private func smoothEnvelope(_ points: inout [(x: CGFloat, amp: CGFloat)]) {
        WaveformEnvelopeRenderer.smooth(&points)
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

    /// 绘制 trim 拖柄 — UI-020: 红色 4px 柄画在选区框两外侧（B 稿 .trimh：裁剪语义外扩）
    /// 位置随选区边界（外侧偏移 5px），拖拽命中由选区柄 14px 热区统一承接
    private func drawTrimHandles(in rect: NSRect) {
        guard let sel = selection else { return }

        let trimColor = IndustrialColors.editorTrimHandle
        let handleWidth: CGFloat = 4
        let outerOffset: CGFloat = 5  // B 稿 trimh.l{left:-5px} / trimh.r{right:-5px}

        let borderRect = waveformRect.insetBy(dx: 1, dy: 8)

        // 左 trim 拖柄（选区左边界外侧）
        let leftX = timeToPixel(sel.lowerBound) - outerOffset
        if leftX - handleWidth / 2 >= waveformRect.minX {
            let leftHandleRect = NSRect(
                x: leftX - handleWidth / 2,
                y: borderRect.minY,
                width: handleWidth,
                height: borderRect.height
            )
            let leftPath = NSBezierPath(roundedRect: leftHandleRect, xRadius: 1, yRadius: 2)
            trimColor.setFill()
            leftPath.fill()
        }

        // 右 trim 拖柄（选区右边界外侧）
        let rightX = timeToPixel(sel.upperBound) + outerOffset
        if rightX + handleWidth / 2 <= waveformRect.maxX {
            let rightHandleRect = NSRect(
                x: rightX - handleWidth / 2,
                y: borderRect.minY,
                width: handleWidth,
                height: borderRect.height
            )
            let rightPath = NSBezierPath(roundedRect: rightHandleRect, xRadius: 1, yRadius: 2)
            trimColor.setFill()
            rightPath.fill()
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

/// UI-025 R2: 剪映式实心镜像剪影渲染共用件（EditorWaveformView / WaveformView 两态同语言）
enum WaveformEnvelopeRenderer {

    /// 由幅度点列构建上下镜像闭合包络，一次填充（连续剪影，替代离散柱状）。
    /// points 需按 x 升序且无重复；amp 为半高（centerY±amp），已含静音基线下限。
    static func fillMirror(points: [(x: CGFloat, amp: CGFloat)], centerY: CGFloat, color: NSColor) {
        guard let first = points.first, let last = points.last else { return }
        color.setFill()
        guard points.count >= 2, last.x > first.x else {
            // 退化：单点/零宽 → FIX-004 同款 3pt 基线带
            NSBezierPath(rect: NSRect(x: first.x, y: centerY - 1.5,
                                      width: max(1, last.x - first.x), height: 3)).fill()
            return
        }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: first.x, y: centerY - first.amp))
        for p in points.dropFirst() { path.line(to: NSPoint(x: p.x, y: centerY - p.amp)) }
        for p in points.reversed() { path.line(to: NSPoint(x: p.x, y: centerY + p.amp)) }
        path.close()
        path.fill()
    }

    /// 包络点 3 点加权移动平均（首尾保形）：削像素级锯齿，保留峰谷自然起伏（对标剪映参考轮廓）
    static func smooth(_ points: inout [(x: CGFloat, amp: CGFloat)]) {
        guard points.count > 2 else { return }
        var result = points
        for i in 1..<(points.count - 1) {
            result[i].amp = (points[i - 1].amp + points[i].amp * 2 + points[i + 1].amp) / 4
        }
        points = result
    }

    /// UI-034 R1: 剪映式单边包络——由幅度点列构建「基线向上」闭合剪影，一次填充。
    /// points 按 x 升序且无重复；amp 为自 baselineY 向上的高度（已含静音基线下限）。
    static func fillUpward(points: [(x: CGFloat, amp: CGFloat)], baselineY: CGFloat, color: NSColor) {
        guard let first = points.first, let last = points.last else { return }
        color.setFill()
        guard points.count >= 2, last.x > first.x else {
            // 退化：单点/零宽 → FIX-004 同款 3pt 静音基线带（贴基线向上）
            NSBezierPath(rect: NSRect(x: first.x, y: baselineY,
                                      width: max(1, last.x - first.x), height: 3)).fill()
            return
        }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: first.x, y: baselineY))
        for p in points { path.line(to: NSPoint(x: p.x, y: baselineY + p.amp)) }
        path.line(to: NSPoint(x: last.x, y: baselineY))
        path.close()
        path.fill()
    }
}
