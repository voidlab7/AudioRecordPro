import Cocoa

// MARK: - TrackContainerView（P0-B：多轨道容器）
/// 垂直排列 N 条音频轨道的容器视图
/// 每条轨道 = 轨道头（M/S按钮+名称） + 波形区域
class TrackContainerView: NSView {
    
    // MARK: - Properties
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    
    /// 轨道行
    private(set) var trackRows: [EditorTrackRowView] = []
    
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
        
        // 简化布局：stackView 居中、水平铺满、垂直按内容撑开
        // 单轨时上下自动有 spacer 留白；多轨时子视图按 hugging 高度堆叠
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.distribution = .fill
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        // 关键：stackView 自身不强制垂直填满
        // top/bottom 用 >= 约束（最小边界），加 centerY 让其按内容居中
        // 水平方向仍铺满到容器边缘
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    
    // MARK: - Track Management
    
    private func rebuildTracks() {
        stackView.subviews.forEach { $0.removeFromSuperview() }
        trackRows.removeAll()
        
        /// 创建弹性 spacer（垂直方向低优先级，可被压缩）
        func makeSpacer() -> NSView {
            let s = NSView()
            s.translatesAutoresizingMaskIntoConstraints = false
            s.setContentHuggingPriority(.defaultLow, for: .vertical)
            s.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            return s
        }
        
        // 单轨：上下加 spacer 让轨道在容器中垂直居中
        if tracks.count == 1 {
            stackView.addArrangedSubview(makeSpacer())
        }
        
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
        
        // 单轨：下方 spacer + 尾部填充
        if tracks.count == 1 {
            stackView.addArrangedSubview(makeSpacer())
        } else if tracks.count > 1 {
            // 多轨：底部 spacer 让最后一个轨道不拉伸
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.setContentHuggingPriority(.init(1), for: .vertical)
            stackView.addArrangedSubview(spacer)
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
    
    func trackRowDidRequestSolo(_ row: EditorTrackRowView) {
        guard let index = trackRows.firstIndex(where: { $0 === row }),
              index < tracks.count else { return }
        tracks[index].isSolo.toggle()
        row.updateSoloState(tracks[index].isSolo)
    }
}
