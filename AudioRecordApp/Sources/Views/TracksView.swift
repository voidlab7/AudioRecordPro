import Cocoa
import Foundation

// TrackInfo 已移动到 AudioRecordKit/Sources/API/Types.swift

// MARK: - Delegate Protocol
protocol TracksViewDelegate: AnyObject {
    func tracksViewDidUpdateTracks(_ view: TracksView, tracks: [TrackInfo])
    func tracksViewDidTogglePlayback(_ view: TracksView)
    func tracksViewDidStopPlayback(_ view: TracksView)
}

// MARK: - TracksView
/// 轨道视图 - 负责显示和管理音频轨道（动态 1~2 条轨道）
class TracksView: NSView {
    
    // MARK: - UI Components
    private let tracksStack = NSStackView()
    private let mixOutputLabel = NSTextField(labelWithString: "")
    private let playbackPanel = NSView()
    private let playbackTitleLabel = NSTextField(labelWithString: "播放")
    private let playbackFileLabel = NSTextField(labelWithString: "未选择文件")
    private let playbackTimeLabel = NSTextField(labelWithString: "00:00 / 00:00")
    private let playbackProgress = NSProgressIndicator()
    private let playbackToggleButton = IndustrialButtonView(title: "播放/暂停", icon: "playpause.fill")
    private let playbackStopButton = IndustrialButtonView(title: "停止", icon: "stop.fill")
    
    // MARK: - Empty State
    private let emptyStateContainer = NSView()
    private let emptyStateIcon = NSTextField(labelWithString: "◁")
    private let emptyStateLabel = NSTextField(labelWithString: "请选择音频源")
    private let emptyStateHint = NSTextField(labelWithString: "从左侧选择应用或系统声音")
    
    // MARK: - Properties
    weak var delegate: TracksViewDelegate?
    private var currentTracks: [TrackInfo] = []
    private var trackRowViews: [NSView] = []  // 保持对轨道行视图的引用
    
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
        // Industrial Design 背景
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surfaceContainer.cgColor
        
        // 边框
        layer?.borderWidth = 1
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        
        // 先把子视图都 addSubview，再设置约束
        tracksStack.orientation = .vertical
        tracksStack.spacing = IndustrialSpacing.sm
        tracksStack.alignment = .leading
        tracksStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tracksStack)
        
        // 混合输出说明标签
        setupMixOutputLabel()
        
        // 空状态引导
        setupEmptyState()
        
        playbackPanel.translatesAutoresizingMaskIntoConstraints = false
        playbackPanel.isHidden = true
        addSubview(playbackPanel)
        
        setupTracksStack()
        setupPlaybackPanel()
    }
    
    private func setupEmptyState() {
        emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.wantsLayer = true
        addSubview(emptyStateContainer)
        
        // 箭头图标（指向左侧 sidebar）
        emptyStateIcon.font = NSFont.systemFont(ofSize: 24, weight: .ultraLight)
        emptyStateIcon.textColor = IndustrialColors.onSurfaceVariant.withAlphaComponent(0.5)
        emptyStateIcon.isBordered = false
        emptyStateIcon.isEditable = false
        emptyStateIcon.backgroundColor = .clear
        emptyStateIcon.alignment = .center
        emptyStateIcon.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.addSubview(emptyStateIcon)
        
        // 主文案
        emptyStateLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        emptyStateLabel.textColor = IndustrialColors.onSurfaceVariant.withAlphaComponent(0.6)
        emptyStateLabel.isBordered = false
        emptyStateLabel.isEditable = false
        emptyStateLabel.backgroundColor = .clear
        emptyStateLabel.alignment = .center
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: IndustrialColors.onSurfaceVariant.withAlphaComponent(0.6),
            .kern: 1.2
        ]
        emptyStateLabel.attributedStringValue = NSAttributedString(string: "请选择音频源", attributes: labelAttrs)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.addSubview(emptyStateLabel)
        
        // 辅助提示
        emptyStateHint.font = IndustrialTypography.monoDB
        emptyStateHint.textColor = IndustrialColors.textTertiary.withAlphaComponent(0.5)
        emptyStateHint.isBordered = false
        emptyStateHint.isEditable = false
        emptyStateHint.backgroundColor = .clear
        emptyStateHint.alignment = .center
        emptyStateHint.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.addSubview(emptyStateHint)
        
        NSLayoutConstraint.activate([
            emptyStateContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStateContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyStateContainer.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
            
            emptyStateIcon.centerXAnchor.constraint(equalTo: emptyStateContainer.centerXAnchor),
            emptyStateIcon.topAnchor.constraint(equalTo: emptyStateContainer.topAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: emptyStateContainer.centerXAnchor),
            emptyStateLabel.topAnchor.constraint(equalTo: emptyStateIcon.bottomAnchor, constant: 8),
            
            emptyStateHint.centerXAnchor.constraint(equalTo: emptyStateContainer.centerXAnchor),
            emptyStateHint.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: 4),
            emptyStateHint.bottomAnchor.constraint(equalTo: emptyStateContainer.bottomAnchor)
        ])
    }
    
    private func setupMixOutputLabel() {
        mixOutputLabel.stringValue = "📤 混合输出为单文件"
        mixOutputLabel.isBordered = false
        mixOutputLabel.isEditable = false
        mixOutputLabel.backgroundColor = .clear
        mixOutputLabel.font = IndustrialTypography.small
        mixOutputLabel.textColor = IndustrialColors.textTertiary
        mixOutputLabel.translatesAutoresizingMaskIntoConstraints = false
        mixOutputLabel.isHidden = true  // 默认隐藏，2轨时显示
        addSubview(mixOutputLabel)
    }
    
    private func setupTracksStack() {
        NSLayoutConstraint.activate([
            tracksStack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            tracksStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            tracksStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            
            // 混合输出标签在 tracksStack 下方
            mixOutputLabel.topAnchor.constraint(equalTo: tracksStack.bottomAnchor, constant: 8),
            mixOutputLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            mixOutputLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            
            // tracksStack + mixOutputLabel 不能超过 playbackPanel
            mixOutputLabel.bottomAnchor.constraint(lessThanOrEqualTo: playbackPanel.topAnchor, constant: -8),
            tracksStack.bottomAnchor.constraint(lessThanOrEqualTo: playbackPanel.topAnchor, constant: -28)
        ])
    }

    private func setupPlaybackPanel() {
        playbackPanel.wantsLayer = true
        playbackPanel.layer?.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
        playbackPanel.layer?.cornerRadius = IndustrialCornerRadius.xs
        playbackPanel.layer?.borderWidth = 1
        playbackPanel.layer?.borderColor = IndustrialColors.outlineVariant.cgColor

        // 标题和时间标签隐藏（Transport Control 已有计时器）
        playbackTitleLabel.isHidden = true
        playbackTimeLabel.isHidden = true

        playbackFileLabel.font = IndustrialTypography.small
        playbackFileLabel.textColor = IndustrialColors.onSurface
        playbackFileLabel.lineBreakMode = .byTruncatingMiddle
        playbackFileLabel.translatesAutoresizingMaskIntoConstraints = false

        playbackProgress.isIndeterminate = false
        playbackProgress.minValue = 0
        playbackProgress.maxValue = 1
        playbackProgress.doubleValue = 0
        playbackProgress.controlSize = .small
        playbackProgress.style = .bar
        playbackProgress.translatesAutoresizingMaskIntoConstraints = false

        playbackToggleButton.onClick = { [weak self] in
            guard let self = self else { return }
            self.delegate?.tracksViewDidTogglePlayback(self)
        }
        playbackToggleButton.translatesAutoresizingMaskIntoConstraints = false

        playbackStopButton.onClick = { [weak self] in
            guard let self = self else { return }
            self.delegate?.tracksViewDidStopPlayback(self)
        }
        playbackStopButton.translatesAutoresizingMaskIntoConstraints = false

        [playbackFileLabel, playbackProgress, playbackToggleButton, playbackStopButton].forEach {
            playbackPanel.addSubview($0)
        }

        NSLayoutConstraint.activate([
            playbackPanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            playbackPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            playbackPanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            playbackPanel.heightAnchor.constraint(equalToConstant: 48),

            // 文件名在顶行
            playbackFileLabel.leadingAnchor.constraint(equalTo: playbackPanel.leadingAnchor, constant: 12),
            playbackFileLabel.topAnchor.constraint(equalTo: playbackPanel.topAnchor, constant: 6),
            playbackFileLabel.trailingAnchor.constraint(equalTo: playbackPanel.trailingAnchor, constant: -12),

            // 按钮 + 进度条在底行
            playbackToggleButton.leadingAnchor.constraint(equalTo: playbackPanel.leadingAnchor, constant: 12),
            playbackToggleButton.bottomAnchor.constraint(equalTo: playbackPanel.bottomAnchor, constant: -6),
            playbackToggleButton.widthAnchor.constraint(equalToConstant: 100),
            playbackToggleButton.heightAnchor.constraint(equalToConstant: 22),

            playbackStopButton.leadingAnchor.constraint(equalTo: playbackToggleButton.trailingAnchor, constant: 6),
            playbackStopButton.centerYAnchor.constraint(equalTo: playbackToggleButton.centerYAnchor),
            playbackStopButton.widthAnchor.constraint(equalToConstant: 56),
            playbackStopButton.heightAnchor.constraint(equalToConstant: 22),

            playbackProgress.leadingAnchor.constraint(equalTo: playbackStopButton.trailingAnchor, constant: 8),
            playbackProgress.trailingAnchor.constraint(equalTo: playbackPanel.trailingAnchor, constant: -12),
            playbackProgress.centerYAnchor.constraint(equalTo: playbackToggleButton.centerYAnchor)
        ])
    }
    
    // MARK: - Public Methods
    func updateTracks(_ tracks: [TrackInfo]) {
        currentTracks = tracks
        
        // 隐藏轨道卡片区域（REQ-1.0-14：去除冗余进程详情卡片）
        // 左侧 Sidebar 已显示选中进程，此处不再重复展示
        tracksStack.isHidden = true
        emptyStateContainer.isHidden = true
        mixOutputLabel.isHidden = true
        
        delegate?.tracksViewDidUpdateTracks(self, tracks: tracks)
    }
    
    func updateLevel(_ level: Float) {
        // 将电平分发到所有轨道中的 LevelMeterView
        for row in trackRowViews {
            for subview in row.subviews {
                if let meter = subview as? LevelMeterView {
                    meter.updateLevel(level)
                }
            }
        }
    }

    func updatePlaybackDisplay(fileName: String?, currentTime: TimeInterval, duration: TimeInterval, isPlaying: Bool, isPaused: Bool) {
        guard let fileName = fileName else {
            playbackPanel.isHidden = true
            playbackProgress.doubleValue = 0
            playbackFileLabel.stringValue = "未选择文件"
            playbackTimeLabel.stringValue = "00:00 / 00:00"
            playbackToggleButton.isEnabled = false
            playbackStopButton.isEnabled = false
            return
        }

        playbackPanel.isHidden = false
        playbackTitleLabel.stringValue = isPaused ? "已暂停" : (isPlaying ? "播放中" : "就绪")
        playbackFileLabel.stringValue = fileName
        playbackTimeLabel.stringValue = "\(formatPlaybackTime(currentTime)) / \(formatPlaybackTime(duration))"
        playbackProgress.doubleValue = duration > 0 ? min(1.0, max(0.0, currentTime / duration)) : 0
        playbackToggleButton.isEnabled = true
        playbackStopButton.isEnabled = isPlaying || isPaused
    }
    
    func clearTracks() {
        // 清空现有轨道
        for view in tracksStack.arrangedSubviews {
            tracksStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        trackRowViews.removeAll()
    }
    
    // MARK: - Private Methods — Track Management
    
    /// 重建所有轨道（可选对最后一条做 fade-in 动画）
    private func rebuildAllTracks(animateLastTrackIn: Bool = false) {
        clearTracks()
        
        for (index, track) in currentTracks.enumerated() {
            let trackView = createTrackRow(track)
            tracksStack.addArrangedSubview(trackView)
            trackRowViews.append(trackView)
            
            // 宽度约束
            trackView.widthAnchor.constraint(equalTo: tracksStack.widthAnchor).isActive = true
            
            // 对最后一条轨道做动画（麦克风轨加入）
            if animateLastTrackIn && index == currentTracks.count - 1 {
                trackView.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    trackView.animator().alphaValue = 1.0
                }
            }
        }
    }
    
    /// 动画移除最后一条轨道
    private func animateRemoveLastTrack() {
        guard let lastView = trackRowViews.last else {
            rebuildAllTracks()
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            lastView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.tracksStack.removeArrangedSubview(lastView)
            lastView.removeFromSuperview()
            self.trackRowViews.removeLast()
            
            // 刷新剩余轨道内容（标题/图标可能变化）
            self.refreshExistingTracks()
        })
    }
    
    /// 刷新现有轨道的内容（不重建视图）
    private func refreshExistingTracks() {
        for (index, trackView) in trackRowViews.enumerated() {
            guard index < currentTracks.count else { break }
            updateTrackRowContent(trackView, with: currentTracks[index])
        }
    }
    
    /// 更新轨道行内容（标题、图标、来源标注）
    private func updateTrackRowContent(_ trackView: NSView, with track: TrackInfo) {
        // 通过 tag 找到子视图
        if let titleLabel = trackView.viewWithTag(201) as? NSTextField {
            let titleText = track.title.uppercased()
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: IndustrialColors.onSurface,
                .kern: 0.4
            ]
            titleLabel.attributedStringValue = NSAttributedString(string: titleText, attributes: titleAttributes)
        }
        if let sourceLabel = trackView.viewWithTag(202) as? NSTextField {
            let sourceAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: IndustrialColors.textTertiary.withAlphaComponent(0.6),
                .kern: 1.6
            ]
            sourceLabel.attributedStringValue = NSAttributedString(string: track.sourceType.uppercased(), attributes: sourceAttributes)
        }
    }
    
    /// 创建单条轨道行视图
    private func createTrackRow(_ track: TrackInfo) -> NSView {
        let trackView = NSView()
        trackView.wantsLayer = true
        trackView.layer?.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
        trackView.layer?.cornerRadius = IndustrialCornerRadius.xs
        trackView.layer?.borderWidth = 1
        trackView.layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        trackView.translatesAutoresizingMaskIntoConstraints = false
        
        // 顶部头部区域（图标 + 标题）
        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        
        // 图标：优先使用应用图标，否则使用 Emoji
        let iconView: NSView
        if let appIcon = track.appIcon {
            let imageView = NSImageView()
            imageView.image = appIcon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            iconView = imageView
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 20),
                imageView.heightAnchor.constraint(equalToConstant: 20)
            ])
        } else {
            let iconLabel = NSTextField()
            iconLabel.stringValue = track.icon
            iconLabel.isBordered = false
            iconLabel.isEditable = false
            iconLabel.backgroundColor = .clear
            iconLabel.font = NSFont.systemFont(ofSize: 16)
            iconLabel.translatesAutoresizingMaskIntoConstraints = false
            iconView = iconLabel
        }
        
        // Industrial: 大写标题、12px Bold、高对比度白色、0.4px 字距
        let titleLabel = NSTextField()
        titleLabel.tag = 201  // 用 tag 方便后续更新
        let titleText = track.title.uppercased()
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: IndustrialColors.onSurface,
            .kern: 0.4
        ]
        titleLabel.attributedStringValue = NSAttributedString(string: titleText, attributes: titleAttributes)
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(iconView)
        headerView.addSubview(titleLabel)

        // 电平表
        let levelMeter = LevelMeterView()
        levelMeter.translatesAutoresizingMaskIntoConstraints = false
        
        // 来源标注（降级：9px + 暗灰 + 宽字距 = 工业标注风格）
        let sourceLabel = NSTextField()
        sourceLabel.tag = 202
        let sourceAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: IndustrialColors.textTertiary.withAlphaComponent(0.6),
            .kern: 1.6
        ]
        sourceLabel.attributedStringValue = NSAttributedString(string: track.sourceType.uppercased(), attributes: sourceAttributes)
        sourceLabel.isBordered = false
        sourceLabel.isEditable = false
        sourceLabel.backgroundColor = .clear
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false

        trackView.addSubview(headerView)
        trackView.addSubview(levelMeter)
        trackView.addSubview(sourceLabel)

        NSLayoutConstraint.activate([
            trackView.heightAnchor.constraint(equalToConstant: 100),

            // Header 布局
            headerView.topAnchor.constraint(equalTo: trackView.topAnchor, constant: 10),
            headerView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: 12),
            headerView.trailingAnchor.constraint(lessThanOrEqualTo: trackView.trailingAnchor, constant: -12),
            headerView.heightAnchor.constraint(equalToConstant: 22),

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor),

            // LevelMeter 在中间
            levelMeter.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 6),
            levelMeter.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: 12),
            levelMeter.trailingAnchor.constraint(equalTo: trackView.trailingAnchor, constant: -12),
            levelMeter.bottomAnchor.constraint(equalTo: sourceLabel.topAnchor, constant: -4),
            
            // 来源标注在底部
            sourceLabel.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: 12),
            sourceLabel.bottomAnchor.constraint(equalTo: trackView.bottomAnchor, constant: -6),
            sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo: trackView.trailingAnchor, constant: -12),
        ])
        
        return trackView
    }

    private func formatPlaybackTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "00:00" }
        let totalSeconds = Int(time.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Convenience Extensions
extension TracksView {
    /// 根据侧边栏选择创建轨道信息
    static func createTracksFromSelection(
        systemSelected: Bool,
        microphoneSelected: Bool,
        selectedProcesses: [AudioProcessInfo]
    ) -> [TrackInfo] {
        var tracks: [TrackInfo] = []
        
        if let process = selectedProcesses.first {
            tracks.append(TrackInfo(
                icon: "📱",
                title: process.name,
                isActive: true,
                sourceType: "应用声音"
            ))
        } else if systemSelected {
            tracks.append(TrackInfo(
                icon: "speaker.wave.2.fill",
                title: "全部系统声音",
                isActive: true,
                sourceType: "系统混音"
            ))
        }
        
        if microphoneSelected {
            tracks.append(TrackInfo(
                icon: "mic.fill",
                title: "同时录入麦克风",
                isActive: true,
                sourceType: "麦克风输入"
            ))
        }
        
        return tracks
    }
}
