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
    private var rawPeakData: [Float] = []  // 原始 PCM 峰值（未归一化），FIX-010: 仅作可见窗重映射数据源
    private var runningPeakMax: Float = 0  // FIX-010: 自开始录音起的累计最大峰值（只增不减，全局线性参考值）
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

    // MARK: UI-010: 录音态渲染风格（旧橙色包络保留可切，不做物理删除）
    enum RenderStyle {
        case envelope       // 旧方案：橙色填充包络（备用）
        case roundedBars    // 新方案：绿色圆头竖条（参考图定版）
    }
    /// 切换渲染风格：改这一行即可回退旧包络
    private static let renderStyle: RenderStyle = .roundedBars
    /// 圆头竖条参数（参考图实测 @2x：条宽≈间隙≈3-4px → 1x 各 2pt）
    private let vbBarWidth: CGFloat = 2.0
    private let vbBarGap: CGFloat = 2.0
    /// 竖条渐变（顶部亮薄荷 → 根部品牌绿），复用单实例
    private lazy var barGradient: NSGradient = NSGradient(
        starting: NSColor(hex: "#8FF0CF"),
        ending: NSColor(hex: "#13BBA3")
    )!
    
    // 录制时长跟踪（用于动态时间刻度）
    private var recordingStartTime: Date?
    private var recordingDuration: TimeInterval = 0
    
    // 静态波形文件时长
    private var staticFileDuration: TimeInterval = 0
    
    // 动画相关
    private var displayTimer: Timer?

    // FIX-008: 平滑滚动（层驱动连续平移）+ 静态层缓存 + draw() 耗时打点
    private let barInterval: CFTimeInterval = 0.05          // 20 条/秒（UI-014 裁决口径，本单不动速度）
    private var barBucketStart: CFAbsoluteTime = 0          // FIX-009: 当前时间桶起点（按时间聚合出条）
    private var barBucketPeak: Float = 0                    // FIX-009: 桶内 max-hold 峰值
    private var lastBarAppendTime: CFAbsoluteTime = 0       // 最近落杆时刻（平移相位锚点）
    private var translationTimer: Timer?                    // 60Hz：只推条形层位移（GPU 合成），不触发 CPU 重绘
    private let barsClipLayer = CALayer()                   // 裁剪层：条形只在 timelineRect 内可见（右缘冒头/左缘消失）
    private let barsStripLayer = CALayer()                  // 条形内容层：contents = 离屏渲染的条带图
    private var dataVersion = 0                             // 数据版本号：每次追加/重置 +1（满窗裁剪后 count 不变，count 判重会冻屏）
    private var stripDataVersion = -1                       // 已渲染条带对应的数据版本（去重，避免 60Hz 重复渲染）
    private var stripBoundsSize: NSSize = .zero             // 已渲染条带对应的视图尺寸（resize 失效）
    private var gridCacheImage: CGImage?                    // 网格静态层离屏缓存
    private var gridCacheSize: NSSize = .zero
    private let stripGlowPad: CGFloat = 6                   // 条带图两侧光晕余量
    private var drawStatCount = 0
    private var drawStatTotalMs: Double = 0
    private var drawStatMaxMs: Double = 0
    
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // FIX-008 自验钩子：合成 20Hz 峰值流驱动录制态动画（无音频采集，离线取证用）。
        // 触发三通道：--selftest-waveform 参数 / FIX008_SELFTEST=1 环境变量 / 容器 tmp 放 fix008_trigger 文件
        //（WorkBuddy 会话内 open 的 args/env 均不透传，文件触发为自验主通道）
        let byEnv = ProcessInfo.processInfo.environment["FIX008_SELFTEST"] == "1"
        let byArg = ProcessInfo.processInfo.arguments.contains("--selftest-waveform")
        let triggerPath = NSTemporaryDirectory() + "fix008_trigger"
        let byTrigger = FileManager.default.fileExists(atPath: triggerPath)
        if byTrigger { try? FileManager.default.removeItem(atPath: triggerPath) }
        if window != nil, byEnv || byArg || byTrigger {
            FileManager.default.createFile(atPath: NSTemporaryDirectory() + "fix008_hook_seen", contents: Data("env=\(byEnv) arg=\(byArg) trigger=\(byTrigger)".utf8))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startSelftestWaveform()
            }
        }
    }

    private func startSelftestWaveform() {
        logger.info("🧪 [FIX-008] selftest waveform 启动（合成峰值流）")
        startRecording()
        Timer.scheduledTimer(withTimeInterval: barInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            let t = CFAbsoluteTimeGetCurrent()
            let synthetic = Float(abs(sin(t * 2.1)) * 0.7 + abs(sin(t * 5.3)) * 0.3)
            self.updatePeakLevel(synthetic)
        }
    }
    
    private let equalizerContainer = CALayer()
    private var equalizerBars: [CALayer] = []

    private func setupView() {
        wantsLayer = true
        // UI-003: 画布背景对齐设计稿实测 #14161A
        layer?.backgroundColor = NSColor(hex: "#14161A").cgColor
        setupEqualizer()
        // FIX-008: 条形内容层——录制态条形由它承载（draw() 不再逐条重绘），位移走 GPU 合成
        // R2: 条形只在 timelineRect 内可见——右缘冒头、左缘滑出消失（裁剪层包裹）
        barsClipLayer.anchorPoint = CGPoint(x: 0, y: 0)
        barsClipLayer.masksToBounds = true
        barsClipLayer.isHidden = true
        layer?.addSublayer(barsClipLayer)
        barsStripLayer.anchorPoint = CGPoint(x: 0, y: 0)
        barsStripLayer.contentsGravity = .bottomLeft
        barsStripLayer.masksToBounds = true
        barsClipLayer.addSublayer(barsStripLayer)
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
        dataVersion += 1
        lastBarAppendTime = CFAbsoluteTimeGetCurrent()  // FIX-008: 平移相位锚点
        
        if waveformData.count > maxDataPoints {
            waveformData.removeFirst(waveformData.count - maxDataPoints)
        }
        
        DispatchQueue.main.async {
            self.needsDisplay = true
        }
    }
    
    /// 更新 PCM 峰值（与播放波形 extractWaveformSamples 完全同源）
    /// FIX-009: 探针实锤（2026-10-17 真实混录录音）——峰值回调 94~189 次/秒随模式漂移，逐回调出条 = 条距不稳定 + 梳齿空隙。
    /// 现改为**按时间聚合出条**：单调时钟固定 barInterval 时间桶，桶内所有回调峰值取 max-hold，出条节奏恒定 20 条/秒。
    func updatePeakLevel(_ peakLevel: Float) {
        guard isRecording else { return }

        let now = CFAbsoluteTimeGetCurrent()
        if barBucketStart == 0 { barBucketStart = now }
        if peakLevel > barBucketPeak { barBucketPeak = peakLevel }
        guard now - barBucketStart >= barInterval else { return }

        let bucketPeak = barBucketPeak
        barBucketPeak = 0
        barBucketStart = now
        appendBar(bucketPeak)
    }

    /// FIX-009: 把一个时间桶的 max-hold 峰值落为一根条（原 updatePeakLevel 主体）
    private func appendBar(_ peakLevel: Float) {
        // 存储原始 PCM 峰值
        rawPeakData.append(peakLevel)

        // FIX-010: 全局线性归一化——参考值 = 本次录音迄今最大峰值（running max，只增不减），
        // 与编辑态「峰值 / 整段最大值」同规则（共用 WaveformAmplitudeMapper）。
        // 静默期底噪不再被滑窗自动增益放大（原注释写「全局」实为 260 点滑窗，名实不符，根因修复）。
        let maxGrew = peakLevel > runningPeakMax
        if maxGrew { runningPeakMax = peakLevel }
        let normalizedPeak = WaveformAmplitudeMapper.normalized(peakLevel, referenceMax: runningPeakMax)

        waveformData.append(normalizedPeak)
        dataVersion += 1

        // running max 增长时，可见窗内历史条按新参考重映射（保持与最新条同一口径）
        if maxGrew {
            waveformData = rawPeakData.map { WaveformAmplitudeMapper.normalized($0, referenceMax: runningPeakMax) }
            stripDataVersion = -1  // FIX-008: 值变版本不变，强制条带重渲
        }

        if waveformData.count > maxDataPoints {
            waveformData.removeFirst(waveformData.count - maxDataPoints)
        }
        if rawPeakData.count > maxDataPoints {
            rawPeakData.removeFirst(rawPeakData.count - maxDataPoints)
        }

        // 已在 main queue，直接触发重绘（避免双重 async 导致丢帧）
        lastBarAppendTime = CFAbsoluteTimeGetCurrent()  // FIX-008: 平移相位锚点
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
        runningPeakMax = 0  // FIX-010: running max 随新录音复位
        waveformData = Array(repeating: 0.0, count: 0)
        barBucketStart = 0   // FIX-009: 时间桶状态复位
        barBucketPeak = 0
        recordingStartTime = Date()
        recordingDuration = 0
        dataVersion += 1
        stripDataVersion = -1     // FIX-008: 条带缓存失效
        lastBarAppendTime = CFAbsoluteTimeGetCurrent()
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
        runningPeakMax = 0  // FIX-010: running max 复位
        barBucketStart = 0   // FIX-009: 时间桶状态复位
        barBucketPeak = 0
        needsDisplay = true
    }
    
    /// 重置波形
    func reset() {
        smoothedLevel = 0
        recentRawLevels.removeAll()
        rawPeakData.removeAll()
        runningPeakMax = 0  // FIX-010: running max 复位
        waveformData.removeAll()
        waveformLoadID = UUID()
        isShowingStaticWaveform = false
        staticWaveformData = nil
        recordingDuration = 0
        staticFileDuration = 0
        dataVersion += 1
        stripDataVersion = -1  // FIX-008: 条带缓存失效
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
        let timelineInsetX: CGFloat = 28
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
        // 20Hz：时间轴/源标签等 draw() 内容刷新（条形已不在 draw() 里画）
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
        // FIX-008: 60Hz 连续平移——只改条形层 position（GPU 合成插值），不触发 CPU 重绘
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateStripTranslation()
        }
        RunLoop.main.add(t, forMode: .common)
        translationTimer = t
    }

    private func stopAnimation() {
        displayTimer?.invalidate()
        displayTimer = nil
        translationTimer?.invalidate()
        translationTimer = nil
        // 可见性统一由 clip 层管理（draw() 按 20Hz 翻转）；strip 不单独设 isHidden，
        // 否则 startAnimation→stopAnimation 置真后无人解开，条带永久隐身（R2 实测踩坑）
        barsClipLayer.isHidden = true
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        let drawStart = CFAbsoluteTimeGetCurrent()
        defer { recordDrawCost(start: drawStart) }
        super.draw(dirtyRect)
        // UI-006: 网格背景所有状态铺满画布（原仅 idle 画，录制态只剩 timelineRect 中线——老板看到的"中间一块"）
        // FIX-008: 网格走离屏缓存 blit，不再逐线重画
        drawGridCached(in: bounds)
        if !isRecording && !isShowingStaticWaveform && waveformData.isEmpty {
            drawIdlePlaceholder(in: bounds)
            barsClipLayer.isHidden = true
            return
        }

        equalizerContainer.isHidden = true
        // FIX-008: 录制态圆头条形由条形层承载（60Hz 连续平移），draw() 不再逐条重绘
        let useStripLayer = isRecording && Self.renderStyle == .roundedBars && !waveformData.isEmpty
        barsClipLayer.isHidden = !useStripLayer
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
            switch Self.renderStyle {
            case .envelope:
                drawWaveform(in: bounds)
                drawPlayhead(in: bounds)
            case .roundedBars:
                if !useStripLayer {
                    drawRoundedBars(in: bounds)  // 停止后静态兜底（数据保留场景）
                }
            }
        }
    }

    /// FIX-008: draw() 耗时打点（验收 ≤2ms 证据），每 200 次汇总落日志 + /tmp 文件（取证用）
    private func recordDrawCost(start: CFAbsoluteTime) {
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        drawStatCount += 1
        drawStatTotalMs += ms
        drawStatMaxMs = max(drawStatMaxMs, ms)
        if drawStatCount >= 200 {
            let avg = drawStatTotalMs / Double(drawStatCount)
            logger.info("⏱️ [FIX-008] draw() 近200次: avg=\(String(format: "%.2f", avg))ms max=\(String(format: "%.2f", drawStatMaxMs))ms")
            // 沙箱应用：写容器内 tmp（绝对 /tmp 会被沙箱拒绝）
            let line = String(format: "%@ draw近200次 avg=%.2fms max=%.2fms\n",
                              DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium),
                              avg, drawStatMaxMs)
            let path = NSTemporaryDirectory() + "loocap_draw_stats.log"
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(line.data(using: .utf8)!)
                fh.closeFile()
            } else {
                FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
            }
            drawStatCount = 0
            drawStatTotalMs = 0
            drawStatMaxMs = 0
        }
    }

    /// UI-010: 绿色圆头竖条渲染——上下对称镜像、条宽≈间隙、轻光晕、顶部微渐变。
    /// 静音/小信号收缩为中线上的最小圆点行（不整体消失，与 FIX-004 呼应）。
    private func drawRoundedBars(in rect: NSRect) {
        let timelineInsetX: CGFloat = 28
        let timelineRect = NSRect(
            x: timelineInsetX,
            y: 42,
            width: max(1, rect.width - timelineInsetX * 2),
            height: max(1, rect.height - 88)
        )
        let centerY = rect.midY
        let drawHeight = min(maxBarHeight, timelineRect.height * 0.82)
        let step = vbBarWidth + vbBarGap
        let maxVisibleBars = Int(floor(timelineRect.width / step))

        // 左起右滚：最新数据在右端
        let startIndex = max(0, waveformData.count - maxVisibleBars)
        let visibleData = Array(waveformData[startIndex...])
        guard !visibleData.isEmpty else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        // 轻光晕：品牌绿低透明泛光
        let glow = NSShadow()
        glow.shadowColor = NSColor(hex: "#13BBA3").withAlphaComponent(0.5)
        glow.shadowBlurRadius = 3
        glow.shadowOffset = .zero
        glow.set()

        for (offset, level) in visibleData.enumerated() {
            let x = timelineRect.minX + CGFloat(offset) * step
            guard x <= timelineRect.maxX else { break }
            // 最小半径 1pt → 静音时为 2pt 圆点行（圆头天然成点）
            let amplitude = max(1.0, CGFloat(max(0, level)) * drawHeight * 0.48)
            let barRect = NSRect(x: x, y: centerY - amplitude, width: vbBarWidth, height: amplitude * 2)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: vbBarWidth / 2, yRadius: vbBarWidth / 2)
            // 顶端亮 → 根部深（-90°：从上到下）
            barGradient.draw(in: barPath, angle: -90)
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: - FIX-008: 条形层连续平移 + 静态层缓存

    private var timelineRectForBars: NSRect {
        NSRect(x: 28, y: 42, width: max(1, bounds.width - 56), height: max(1, bounds.height - 88))
    }

    /// 60Hz 驱动：数据有新增（版本号变化）才离屏重渲条带（实际 ~20Hz）；每帧只做相位插值推层位移（GPU 合成）。
    /// R2（老板 10-13 口述「从最右边往最左边」）：右端锚定——最新条右缘贴 timeline 右缘冒头，
    /// 全部历史条随相位连续左移；未满窗/满窗同一公式（追加瞬间 (n-1) 增一且相位归零，两者相抵，像素级连续）。
    private func updateStripTranslation() {
        guard isRecording, Self.renderStyle == .roundedBars, !waveformData.isEmpty, bounds.width > 0 else { return }
        let timelineRect = timelineRectForBars
        let step = vbBarWidth + vbBarGap
        let maxVisibleBars = max(2, Int(floor(timelineRect.width / step)))

        if stripDataVersion != dataVersion || !NSEqualSizes(stripBoundsSize, bounds.size) {
            // 裁剪层对齐 timelineRect（子层坐标系与视图绘制坐标系同向，直接用 origin）
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            barsClipLayer.bounds = CGRect(x: 0, y: 0, width: timelineRect.width, height: timelineRect.height)
            barsClipLayer.position = CGPoint(x: timelineRect.minX, y: timelineRect.minY)
            CATransaction.commit()
            renderBarsStrip(timelineRect: timelineRect, step: step, maxVisibleBars: maxVisibleBars)
            stripDataVersion = dataVersion
            stripBoundsSize = bounds.size
        }

        let n = CGFloat(min(waveformData.count, maxVisibleBars))
        let elapsed = max(0, CFAbsoluteTimeGetCurrent() - lastBarAppendTime)
        let phase = min(0.999, elapsed / barInterval)
        // 最新条右缘 = 裁剪层右缘 - phase*step；其余历史条在条带图内按 step 排其左
        let x = timelineRect.width - vbBarWidth - stripGlowPad - (n - 1) * step - CGFloat(phase) * step
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barsStripLayer.position = CGPoint(x: x, y: 0)
        CATransaction.commit()
    }

    /// 离屏渲染条带：最新条固定在条带图最右槽位（平移公式保证其右缘贴 timeline 右缘冒头），
    /// 历史条按 step 向左排列，平移全交给 layer.position。条形样式（圆头/渐变/光晕）与 UI-010 保持一致。
    private func renderBarsStrip(timelineRect: NSRect, step: CGFloat, maxVisibleBars: Int) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let stripW = CGFloat(maxVisibleBars) * step + stripGlowPad * 2
        let stripH = timelineRect.height
        let pixelsW = Int(stripW * scale), pixelsH = Int(stripH * scale)
        guard pixelsW > 0, pixelsH > 0,
              let cg = CGContext(data: nil, width: pixelsW, height: pixelsH, bitsPerComponent: 8,
                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // 顶部原点，与 draw() 坐标语义一致
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: stripH)
        cg.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        let centerY = stripH / 2
        let drawHeight = min(maxBarHeight, timelineRect.height * 0.82)
        let startIndex = max(0, waveformData.count - maxVisibleBars)
        let visibleData = Array(waveformData[startIndex...])
        let glow = NSShadow()
        glow.shadowColor = NSColor(hex: "#13BBA3").withAlphaComponent(0.5)
        glow.shadowBlurRadius = 3
        glow.shadowOffset = .zero
        glow.set()
        for (offset, level) in visibleData.enumerated() {
            let x = stripGlowPad + CGFloat(offset) * step
            let amplitude = max(1.0, CGFloat(max(0, level)) * drawHeight * 0.48)
            let barRect = NSRect(x: x, y: centerY - amplitude, width: vbBarWidth, height: amplitude * 2)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: vbBarWidth / 2, yRadius: vbBarWidth / 2)
            barGradient.draw(in: barPath, angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let image = cg.makeImage() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barsStripLayer.contentsScale = scale
        barsStripLayer.bounds = CGRect(x: 0, y: 0, width: stripW, height: stripH)
        barsStripLayer.contents = image
        CATransaction.commit()
    }

    /// FIX-008: 网格静态层——只画一次/resize 重画，draw() 只做位图 blit
    private func drawGridCached(in rect: NSRect) {
        if gridCacheImage == nil || !NSEqualSizes(gridCacheSize, rect.size) {
            gridCacheImage = renderGridImage(rect: rect)
            gridCacheSize = rect.size
        }
        guard let img = gridCacheImage else {
            drawCanvasGrid(in: rect)  // 兜底：缓存失败走原路
            return
        }
        NSGraphicsContext.current?.cgContext.draw(img, in: rect)
    }

    private func renderGridImage(rect: NSRect) -> CGImage? {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelsW = Int(rect.width * scale), pixelsH = Int(rect.height * scale)
        guard pixelsW > 0, pixelsH > 0,
              let cg = CGContext(data: nil, width: pixelsW, height: pixelsH, bitsPerComponent: 8,
                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: rect.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        drawCanvasGrid(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        return cg.makeImage()
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
        let timelineInsetX: CGFloat = 28
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
        
        let timelineInsetX: CGFloat = 28
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
        let timelineInsetX: CGFloat = 28
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
