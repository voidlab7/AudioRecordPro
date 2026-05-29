import Cocoa

// MARK: - EditorStatusBar
/// 编辑器状态栏 — 播放时间 / 时长 / 采样率 / 声道 / 编辑步数
class EditorStatusBar: NSView {
    
    // MARK: - UI Components
    private let timeLabel = NSTextField(labelWithString: "00:00.000")
    private let separatorView1 = NSView()
    private let durationLabel = NSTextField(labelWithString: "")
    private let separatorView2 = NSView()
    private let infoLabel = NSTextField(labelWithString: "")
    private let topSeparator = CALayer()
    
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
        layer?.backgroundColor = IndustrialColors.surface.cgColor
        
        topSeparator.backgroundColor = IndustrialColors.outlineVariant.cgColor
        layer?.addSublayer(topSeparator)
        
        // 当前时间（大号，醒目）
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = IndustrialColors.primary
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)
        
        // 分隔线
        for sep in [separatorView1, separatorView2] {
            sep.wantsLayer = true
            sep.layer?.backgroundColor = IndustrialColors.outlineVariant.cgColor
            sep.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sep)
        }
        
        // 总时长
        durationLabel.font = IndustrialTypography.monoDB
        durationLabel.textColor = IndustrialColors.onSurfaceVariant
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(durationLabel)
        
        // 技术信息
        infoLabel.font = IndustrialTypography.monoDB
        infoLabel.textColor = IndustrialColors.textTertiary
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoLabel)
        
        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            separatorView1.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 10),
            separatorView1.centerYAnchor.constraint(equalTo: centerYAnchor),
            separatorView1.widthAnchor.constraint(equalToConstant: 1),
            separatorView1.heightAnchor.constraint(equalToConstant: 12),
            
            durationLabel.leadingAnchor.constraint(equalTo: separatorView1.trailingAnchor, constant: 10),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            separatorView2.leadingAnchor.constraint(equalTo: durationLabel.trailingAnchor, constant: 10),
            separatorView2.centerYAnchor.constraint(equalTo: centerYAnchor),
            separatorView2.widthAnchor.constraint(equalToConstant: 1),
            separatorView2.heightAnchor.constraint(equalToConstant: 12),
            
            infoLabel.leadingAnchor.constraint(equalTo: separatorView2.trailingAnchor, constant: 10),
            infoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
    }
    
    override func layout() {
        super.layout()
        topSeparator.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }
    
    // MARK: - Public Methods
    
    func update(duration: TimeInterval, sampleRate: Double, channels: Int, editSteps: Int, maxSteps: Int) {
        durationLabel.stringValue = "总时长 \(formatTime(duration))"
        let sampleRateStr = "\(Int(sampleRate / 1000))kHz"
        let channelStr = channels == 1 ? "单声道" : "立体声"
        infoLabel.stringValue = "\(sampleRateStr) · \(channelStr) · 编辑 \(editSteps)/\(maxSteps)"
    }
    
    /// 更新当前播放/游标时间
    func updateCurrentTime(_ time: TimeInterval) {
        timeLabel.stringValue = formatTimePrecise(time)
    }
    
    private func formatTime(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let cs = Int((t.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, cs)
    }
    
    private func formatTimePrecise(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, ms)
    }
}
