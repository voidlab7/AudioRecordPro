import Cocoa
import Foundation

// MARK: - StatusBarView
/// 状态栏视图 - 多段技术信息展示（设备/采样率/位深/格式/CPU/磁盘）
class StatusBarView: NSView {
    
    // MARK: - UI Components
    private let stackView = NSStackView()
    
    // 各信息段
    private let statusIndicator = NSView()  // 状态圆点
    private let statusLabel = NSTextField(labelWithString: "就绪")
    private let deviceLabel = NSTextField(labelWithString: "—")
    private let sampleRateLabel = NSTextField(labelWithString: "48kHz")
    private let bitDepthLabel = NSTextField(labelWithString: "32-bit")
    private let formatLabel = NSTextField(labelWithString: "")
    private let cpuLabel = NSTextField(labelWithString: "")
    private let diskLabel = NSTextField(labelWithString: "")
    
    // MARK: - Properties
    private var currentStatus: String = "就绪"
    
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
        // Industrial Design 背景 + 顶部边框
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surface.cgColor
        
        setupTopBorder()
        setupStackView()
        setupConstraints()
        updateDiskSpace()
    }
    
    private func setupTopBorder() {
        let borderLayer = CALayer()
        borderLayer.backgroundColor = IndustrialColors.outlineVariant.cgColor
        borderLayer.frame = CGRect(x: 0, y: 0, width: 10000, height: 1)
        layer?.addSublayer(borderLayer)
    }
    
    override func layout() {
        super.layout()
        // 更新顶部边框宽度
        layer?.sublayers?.first(where: { $0.backgroundColor == IndustrialColors.outlineVariant.cgColor })?.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }
    
    private func setupStackView() {
        stackView.orientation = .horizontal
        stackView.spacing = 0
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        
        // 状态圆点指示器
        statusIndicator.wantsLayer = true
        statusIndicator.layer?.backgroundColor = IndustrialColors.statusSuccess.cgColor
        statusIndicator.layer?.cornerRadius = 3.5
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusIndicator.widthAnchor.constraint(equalToConstant: 7),
            statusIndicator.heightAnchor.constraint(equalToConstant: 7)
        ])
        
        // 配置各标签样式
        let allLabels = [statusLabel, deviceLabel, sampleRateLabel, bitDepthLabel, formatLabel, cpuLabel, diskLabel]
        for label in allLabels {
            label.font = IndustrialTypography.monoDB
            label.textColor = IndustrialColors.onSurfaceVariant
            label.isBordered = false
            label.isEditable = false
            label.backgroundColor = .clear
            label.alignment = .left
            label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
        
        // 状态标签特殊样式（更亮）
        statusLabel.textColor = IndustrialColors.primary
        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        
        // 组装 stackView（精简：只保留核心信息）
        stackView.addArrangedSubview(statusIndicator)
        stackView.addArrangedSubview(makeSpacerView(width: 6))
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(makeSeparator())
        stackView.addArrangedSubview(sampleRateLabel)
        stackView.addArrangedSubview(makeSeparator())
        stackView.addArrangedSubview(formatLabel)
        
        // 尾部弹性空间
        let trailingSpacer = NSView()
        trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stackView.addArrangedSubview(trailingSpacer)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    // MARK: - Factory Methods
    
    /// 创建分隔符视图（竖线 + 两侧间距）
    private func makeSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = IndustrialColors.outlineVariant.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 17),
            container.heightAnchor.constraint(equalToConstant: 14),
            line.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 10)
        ])
        
        return container
    }
    
    /// 创建水平间距视图
    private func makeSpacerView(width: CGFloat) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: width).isActive = true
        return spacer
    }
    
    // MARK: - Public Methods
    
    /// 更新总体状态文本（兼容旧接口）
    /// - Parameter status: 状态描述字符串，会尝试映射为精确状态
    func updateStatus(_ status: String) {
        currentStatus = status
        // 映射旧状态到新显示（兼容旧调用点）
        let uppercased = status.uppercased()
        if uppercased.contains("录") || uppercased.contains("RECORD") {
            updateRecordingState(.recording)
        } else if uppercased.contains("播放") || uppercased.contains("PLAY") {
            updateRecordingState(.playing)
        } else if uppercased.contains("错误") || uppercased.contains("ERROR") || uppercased.contains("FAULT") {
            updateRecordingState(.error)
        } else {
            updateRecordingState(.idle)
        }
    }
    
    /// 精确更新状态（新接口，REQ-2.0-02）
    /// - Parameter state: 录制状态枚举
    func updateRecordingState(_ state: RecordingState) {
        switch state {
        case .idle:
            statusLabel.stringValue = "准备录制"
            statusIndicator.layer?.backgroundColor = IndustrialColors.statusSuccess.cgColor
        case .preparing:
            statusLabel.stringValue = "● 准备中"
            statusIndicator.layer?.backgroundColor = IndustrialColors.statusWarning.cgColor
        case .recording:
            statusLabel.stringValue = "● 录制中"
            statusIndicator.layer?.backgroundColor = IndustrialColors.statusCritical.cgColor
        case .stopping:
            statusLabel.stringValue = "● 停止中"
            statusIndicator.layer?.backgroundColor = IndustrialColors.statusWarning.cgColor
        case .playing:
            statusLabel.stringValue = "● 播放中"
            statusIndicator.layer?.backgroundColor = IndustrialColors.primary.cgColor
        case .error:
            statusLabel.stringValue = "● 错误"
            statusIndicator.layer?.backgroundColor = IndustrialColors.statusDanger.cgColor
        }
    }
    
    func getCurrentStatus() -> String {
        return currentStatus
    }
    
    /// 更新 idle 态引导文案（REQ-2.0-02）
    /// - Parameter targetName: 当前录制目标名称
    func updateIdleGuide(targetName: String?) {
        if let name = targetName, !name.isEmpty {
            statusLabel.stringValue = "准备录制：\(name)"
        } else {
            statusLabel.stringValue = "选择录制目标，点击 ● 开始"
        }
        statusIndicator.layer?.backgroundColor = IndustrialColors.statusSuccess.cgColor
    }
    
    /// 更新音频设备名称
    func updateDevice(_ name: String) {
        deviceLabel.stringValue = name.isEmpty ? "—" : name
    }
    
    /// 更新采样率
    func updateSampleRate(_ rate: Int) {
        if rate >= 1000 {
            sampleRateLabel.stringValue = "\(rate / 1000)kHz"
        } else {
            sampleRateLabel.stringValue = "\(rate)Hz"
        }
    }
    
    /// 更新位深度
    func updateBitDepth(_ depth: Int) {
        bitDepthLabel.stringValue = "\(depth)-bit"
    }
    
    /// 更新文件格式
    func updateFormat(_ format: String) {
        formatLabel.stringValue = format.uppercased()
    }
    
    /// 更新 CPU 使用率
    func updateCPU(_ usage: Double) {
        let displayUsage = Int(usage.rounded())
        cpuLabel.stringValue = "CPU \(displayUsage)%"
        // 颜色语义：正常绿 → 警告琥珀 → 危险红
        if usage > 80 {
            cpuLabel.textColor = IndustrialColors.statusDanger
        } else if usage > 50 {
            cpuLabel.textColor = IndustrialColors.statusWarning
        } else {
            cpuLabel.textColor = IndustrialColors.onSurfaceVariant
        }
    }
    
    /// 更新磁盘剩余空间（自动格式化）
    private func updateDiskSpace() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            if let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let available = values.volumeAvailableCapacityForImportantUsage {
                let gb = Double(available) / 1_073_741_824.0
                DispatchQueue.main.async {
                    if gb >= 100 {
                        self.diskLabel.stringValue = String(format: "%.0fGB", gb)
                    } else {
                        self.diskLabel.stringValue = String(format: "%.1fGB", gb)
                    }
                }
            }
        }
    }
}
