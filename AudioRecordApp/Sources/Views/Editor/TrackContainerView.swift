import Cocoa
 import Cocoa

// MARK: - TrackContainerView（P0-B：多轨道容器）
/// 垂直排列 N 条音频轨道的容器视图
/// 每条轨道 = 轨道头（M/S按钮+名称） + 波形区域
class TrackContainerView: NSView {

    // MARK: - Properties
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()

    /// 横向贯通的时间刻度尺 — 跳过左侧轨道头列（headerWidth）
    /// P0-B: ruler 在工具栏正下方、横跨所有轨道行；
    ///       左侧 80px 轨道头不绘制刻度（M/S 按钮所在列保持纯净）
    private let rulerView = TimeRulerView()
    private let rulerHeight: CGFloat = 22

    /// 轨道行
    private(set) var trackRows: [EditorTrackRowView] = []

    /// 动态计算自身 intrinsic 高度（ruler + 行数 * rowHeight），
    /// 供父视图（EditorViewController）的 centerY 约束配合使用。
    /// 调用 `invalidateIntrinsicContentSize()` 必须在 tracks 变更后触发。
    override var intrinsicContentSize: NSSize {
        let rowsHeight = CGFloat(trackRows.count) * EditorTrackRowView.rowHeight
        return NSSize(width: NSView.noIntrinsicMetric, height: rulerHeight + rowsHeight)
    }
    
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

        // P0-B 修复：trackContainerView 自身高度 = rulerHeight(22) + N*rowHeight（intrinsic），
        // 通过 hugging/compression resistance 锁死。父视图（EditorViewController）
        // 用 centerY 让本视图垂直居中于编辑器。内部布局最简化：ruler 在顶部，
        // stackView 紧贴 ruler 下方填满底部（确定性的，不依赖 spacer 拉伸）。

        // 锁定自身高度 = intrinsic 高度（ruler + 轨道总高）
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        // P0-B: 横向贯通的时间刻度尺（位于 stackView 顶部之上、轨道头列之外）
        rulerView.translatesAutoresizingMaskIntoConstraints = false
        rulerView.headerWidth = EditorTrackRowView.headerWidth  // 跳过轨道头列
        addSubview(rulerView)

        // stackView 装轨道行（不设任何 spacer — 让行紧贴 ruler 下方）
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.distribution = .fill
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        // 关键：ruler 顶部固定，stackView 紧贴 ruler 下方填满底部
        // — 不再依赖 NSStackView spacer 拉伸（已知 bug：.fill 按添加顺序分配剩余空间）
        NSLayoutConstraint.activate([
            // 横向贯通时间刻度尺：贯通整个 trackContainer 宽度（含轨道头列）
            rulerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rulerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rulerView.topAnchor.constraint(equalTo: topAnchor),
            rulerView.heightAnchor.constraint(equalToConstant: rulerHeight),

            // stackView：紧贴 ruler 下方，bottom 锚到 self.bottom（确定性）
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: rulerView.bottomAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Public API

    /// 同步时间刻度尺的 viewport（外部在波形缩放/滚动时调用）
    /// - Parameters:
    ///   - start: 可见时间起点（秒）
    ///   - duration: 可见时间长度（秒）
    func updateRulerViewport(start: TimeInterval, duration: TimeInterval) {
        rulerView.updateViewport(start: start, duration: duration)
    }
    
    // MARK: - Track Management
    
    private func rebuildTracks() {
        stackView.subviews.forEach { $0.removeFromSuperview() }
        trackRows.removeAll()

        // P0-B 修复：移除所有 spacer。NSStackView `.fill` distribution 按 hugging
        // priority 顺序拉伸 subview（多 spacer 同优先级时按添加顺序），
        // 会导致"第一个 spacer 撑开、第二个 spacer 高度 = 0"的 bug，
        // 单轨时 row 贴底而非居中。
        // 新策略：trackContainerView 自身高度 = rulerHeight(22) + N*rowHeight
        // （由 intrinsic 决定 + hugging/compression resistance 锁死），
        // 父视图用 centerY 居中。stackView 内部只装轨道行，无 spacer。

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

        // 通知 Auto Layout 刷新 trackContainerView 的 intrinsic 高度
        invalidateIntrinsicContentSize()
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
    
    func trackRowDidRequestSolo(_ row: EditorTrackRowView) {
        guard let index = trackRows.firstIndex(where: { $0 === row }),
              index < tracks.count else { return }
        tracks[index].isSolo.toggle()
        row.updateSoloState(tracks[index].isSolo)
    }
}
