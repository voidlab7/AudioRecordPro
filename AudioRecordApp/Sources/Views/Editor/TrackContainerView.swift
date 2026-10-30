import Cocoa
 import Cocoa

// MARK: - TrackContainerSeekDelegate（UI-037）
/// 空白区（标尺 / 轨道带上下留白）点击/拖拽 seek 回调。
/// 波形行内部的交互（seek/选区/裁剪/音量线）由 EditorWaveformView 自行处理，不走此协议。
protocol TrackContainerViewSeekDelegate: AnyObject {
    /// time 为按可见区换算的原始时间（可能超出音频时长），由实现方 clamp。
    func trackContainerView(_ view: TrackContainerView, didSeekTo time: TimeInterval)
}

// MARK: - TrackContainerView（P0-B：多轨道容器）
/// 垂直排列 N 条音频轨道的容器视图
/// 每条轨道 = 轨道头（静音喇叭） + 波形区域
///
/// UI-037 布局分层（对标设计稿「标尺贴顶 + 播放头顶到底」）：
/// - 容器自身铺满轨道区（EditorViewController 钉 top/bottom 于 trackArea，不再整体居中）
/// - ruler 贴容器顶部（工具栏正下方，高 22 不变）
/// - 轨道行 stack 在「ruler 下沿 ↔ 容器底部」区间垂直居中；多轨超高回退贴 ruler 下沿 + 溢出
/// - playhead overlay 铺满容器 = 竖线从标尺顶贯穿到轨道区底
class TrackContainerView: NSView {

    // MARK: - Properties
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()

    /// 横向贯通的时间刻度尺 — 跳过左侧轨道头列（headerWidth）
    /// UI-037: ruler 固定贴轨道区顶部（navigationBar 正下方），不再随轨道带居中；
    ///       左侧 88px 轨道头不绘制刻度（喇叭按钮所在列保持纯净）
    private let rulerView = TimeRulerView()
    private let rulerHeight: CGFloat = 22

    /// 播放头/游标线 overlay — 覆盖整个轨道区（ruler 顶 → 容器底），
    /// x 坐标与 ruler 共享同一公式（精准卡住时间刻度）
    private let playheadOverlay = PlayheadOverlayView()

    /// UI-037: 轨道带的可用区间（ruler 下沿 ↔ 容器底部），stack 在其间垂直居中
    private let trackBandArea = NSLayoutGuide()

    /// 轨道行
    private(set) var trackRows: [EditorTrackRowView] = []

    /// UI-037: 空白区 seek 回调
    weak var seekDelegate: TrackContainerViewSeekDelegate?

    /// viewport 缓存（供空白区点击的 x → time 换算，与 ruler/playhead 同步）
    private var visibleStartTime: TimeInterval = 0
    private var visibleDuration: TimeInterval = 1

    /// 轨道数据
    var tracks: [EditorAudioTrack] = [] {
        didSet { rebuildTracks() }
    }

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
        layer?.backgroundColor = IndustrialColors.surfaceContainerLowest.cgColor

        // UI-037: 容器高度不再由内容 intrinsic 决定（父视图钉满轨道区）；
        // 内部分两层——ruler+playhead overlay（顶锚、铺满全高）与轨道行 stack（居中）。

        // P0-B: 横向贯通的时间刻度尺（位于 stackView 顶部之上、轨道头列之外）
        rulerView.translatesAutoresizingMaskIntoConstraints = false
        rulerView.headerWidth = EditorTrackRowView.headerWidth  // 跳过轨道头列
        addSubview(rulerView)

        // stackView 装轨道行（不设 spacer — 高度 = 行内容高，在 trackBandArea 内居中）
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.distribution = .fill
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        // 播放头 overlay — 覆盖整个轨道区（ruler 顶 → 容器底），
        // x 坐标与 ruler 共享同一公式，竖线贯穿全高（含轨道带上下留白）
        playheadOverlay.translatesAutoresizingMaskIntoConstraints = false
        playheadOverlay.headerWidth = EditorTrackRowView.headerWidth  // 与 ruler 同步
        playheadOverlay.rulerHeight = rulerHeight
        addSubview(playheadOverlay)

        // UI-037: 轨道带区间 = ruler 下沿 ↔ 容器底部
        addLayoutGuide(trackBandArea)

        // 关键约束：
        // - ruler 贴容器顶（铺满宽）
        // - stack 在 trackBandArea 内垂直居中（500）；多轨超高时 top≥(required)
        //   让 stack 贴 ruler 下沿、bottom≤(749) 放行溢出（回退贴顶，与 UI-032 语义同构）
        let stackBottomFits = stackView.bottomAnchor.constraint(lessThanOrEqualTo: trackBandArea.bottomAnchor)
        stackBottomFits.priority = NSLayoutConstraint.Priority(749)
        let stackCentered = stackView.centerYAnchor.constraint(equalTo: trackBandArea.centerYAnchor)
        stackCentered.priority = NSLayoutConstraint.Priority(500)

        NSLayoutConstraint.activate([
            // 横向贯通时间刻度尺：贯通整个容器宽度（含轨道头列），贴顶
            rulerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rulerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rulerView.topAnchor.constraint(equalTo: topAnchor),
            rulerView.heightAnchor.constraint(equalToConstant: rulerHeight),

            // 轨道带区间（ruler 下沿 ↔ 底部）
            trackBandArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackBandArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackBandArea.topAnchor.constraint(equalTo: rulerView.bottomAnchor),
            trackBandArea.bottomAnchor.constraint(equalTo: bottomAnchor),

            // stack：横向贯通；top≥ 区间顶（required）；居中(500)/溢出放行(749) 见上
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: trackBandArea.topAnchor),
            stackBottomFits,
            stackCentered,

            // playhead overlay 覆盖整个容器（在 ruler 和 stackView 之上）——UI-037 竖线顶到底
            playheadOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            playheadOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            playheadOverlay.topAnchor.constraint(equalTo: topAnchor),
            playheadOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Public API

    /// 同步时间刻度尺的 viewport（外部在波形缩放/滚动时调用）
    /// - Parameters:
    ///   - start: 可见时间起点（秒）
    ///   - duration: 可见时间长度（秒）
    func updateRulerViewport(start: TimeInterval, duration: TimeInterval) {
        let s = max(0, start)
        let d = max(0.001, duration)
        visibleStartTime = s
        visibleDuration = d
        rulerView.updateViewport(start: s, duration: d)
        // playhead overlay 共享 ruler 坐标系 — 同步
        playheadOverlay.visibleStartTime = s
        playheadOverlay.visibleDuration = d
    }

    /// 同步播放头位置（外部在 seek / 播放进度更新时调用）
    func updatePlayhead(time: TimeInterval) {
        playheadOverlay.playbackTime = time
    }

    // MARK: - UI-037 空白区 seek（点击标尺 / 轨道带留白处拖拽跳播）

    /// 画布 x（容器坐标）→ 时间。与 PlayheadOverlayView.playheadX / TimeRulerView.timeToPixel
    /// 共享同一坐标系（headerWidth 偏移 + 可见区比例），互为逆变换。
    /// 不做 [0, totalDuration] clamp（容器不知道音频时长，由 delegate 实现方负责）。
    func seekTime(forCanvasX x: CGFloat) -> TimeInterval {
        let timeWidth = bounds.width - EditorTrackRowView.headerWidth
        guard timeWidth > 0, visibleDuration > 0 else { return visibleStartTime }
        let clampedX = min(max(x, EditorTrackRowView.headerWidth), bounds.width)
        let ratio = Double((clampedX - EditorTrackRowView.headerWidth) / timeWidth)
        return visibleStartTime + ratio * visibleDuration
    }

    /// 时间 → 画布 x（seekTime 的逆变换；lite 通道往返断言用）
    func canvasX(forSeekTime time: TimeInterval) -> CGFloat {
        let timeWidth = bounds.width - EditorTrackRowView.headerWidth
        guard timeWidth > 0, visibleDuration > 0 else { return EditorTrackRowView.headerWidth }
        let ratio = CGFloat((time - visibleStartTime) / visibleDuration)
        return EditorTrackRowView.headerWidth + ratio * timeWidth
    }

    private func handleEmptyAreaSeek(at point: NSPoint) {
        // 轨道头列（x < headerWidth）不 seek：该列是喇叭按钮/留白，语义为「轨道管理」
        guard point.x >= EditorTrackRowView.headerWidth else { return }
        let time = seekTime(forCanvasX: point.x)
        UXEventLog.shared.module("Editor", "seek_empty_area", ok: true,
                                detail: ["target_sec": (time * 1000).rounded() / 1000])
        seekDelegate?.trackContainerView(self, didSeekTo: time)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        handleEmptyAreaSeek(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        // 空白区按住拖动 = 持续 seek（对标剪映拖播放头）
        let point = convert(event.locationInWindow, from: nil)
        handleEmptyAreaSeek(at: point)
    }

    // MARK: - Track Management

    private func rebuildTracks() {
        stackView.subviews.forEach { $0.removeFromSuperview() }
        trackRows.removeAll()

        // UI-037: stack 高度 = 行内容高（行 min 140 required + hugging 750 > centerY 500，
        // 行不会被拉伸），stack 在 trackBandArea 内垂直居中；多轨超高回退贴 ruler 下沿 + 溢出。

        for (index, track) in tracks.enumerated() {
            let row = EditorTrackRowView(
                trackIndex: index,
                trackName: track.name,
                trackColor: trackColor(for: track.color)
            )
            row.delegate = self
            row.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(row)
            trackRows.append(row)
        }
    }

    /// 获取指定轨道的波形视图
    func waveformView(for trackIndex: Int) -> EditorWaveformView? {
        guard trackIndex < trackRows.count else { return nil }
        return trackRows[trackIndex].waveformView
    }

    // MARK: - Track Color Mapping
    private func trackColor(for clipColor: ClipColor) -> NSColor {
        switch clipColor {
        case .coral: return IndustrialColors.waveformCoral
        case .cyan: return IndustrialColors.waveformAccent
        case .gold: return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        case .purple: return NSColor(calibratedRed: 0.7, green: 0.53, blue: 1.0, alpha: 1.0)
        case .green: return NSColor(calibratedRed: 0.5, green: 0.78, blue: 0.52, alpha: 1.0)
        }
    }
}

// MARK: - TrackRowViewDelegate
extension TrackContainerView: EditorTrackRowViewDelegate {
    func trackRowDidRequestMute(_ row: EditorTrackRowView) {
        guard let index = trackRows.firstIndex(where: { $0 === row }),
              index < tracks.count else { return }
        tracks[index].isMuted.toggle()
        row.updateMuteState(tracks[index].isMuted)
    }
}
