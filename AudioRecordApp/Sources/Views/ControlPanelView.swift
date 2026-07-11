import Cocoa
import Foundation

// MARK: - VerticalCenteredTextFieldCell
/// 自定义 Cell，让 NSTextField 文本垂直居中
private class VerticalCenteredTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        let minimumHeight = cellSize(forBounds: rect).height
        titleRect.origin.y += (titleRect.height - minimumHeight) / 2.0
        titleRect.size.height = minimumHeight
        return titleRect
    }
    
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
}

// MARK: - Delegate Protocol
protocol ControlPanelViewDelegate: AnyObject {
    func controlPanelViewDidStartRecording(_ view: ControlPanelView)
    func controlPanelViewDidStopRecording(_ view: ControlPanelView)
    func controlPanelViewDidTogglePlayback(_ view: ControlPanelView)
    func controlPanelViewDidStopPlayback(_ view: ControlPanelView)
}

// MARK: - ControlPanelView
/// 控制面板视图 - 负责录音按钮和计时器显示
class ControlPanelView: NSView {
    
    // MARK: - UI Components
    private let headerLabel = NSTextField(labelWithString: "")  // 清空多余标题
    private let statusBadge: NSTextField = {
        let field = NSTextField(labelWithString: "待命")
        // 替换 cell 为垂直居中版本
        let cell = VerticalCenteredTextFieldCell(textCell: "待命")
        cell.isEditable = false
        cell.isBordered = false
        cell.drawsBackground = false
        cell.alignment = .center
        field.cell = cell
        return field
    }()
    private let readoutLabel = NSTextField(labelWithString: "")
    private let timerLabel = TimerLabel()
    private let playButton = IndustrialCompactIconButton(symbol: "▶")
    private let stopButton = IndustrialCompactIconButton(symbol: "■")
    private let buttonContainer = NSView()
    private let buttonBaseLayer = CALayer()
    private let recordButton = IndustrialRecordButtonView()
    private let outerRingLayer = CAShapeLayer()
    private let innerSquareLayer = CALayer()
    private let topSeparator = CALayer()
    private let stopSquareSize: CGFloat = 12

    // MARK: - Properties
    weak var delegate: ControlPanelViewDelegate?
    private var currentRecordingState: RecordingState = .idle
    private var currentTargetDescription: String = "全部系统声音"
    private var buttonWidthConstraint: NSLayoutConstraint?
    private var buttonHeightConstraint: NSLayoutConstraint?
    private let normalButtonSize: CGFloat = 48
    private let recordingButtonSize: CGFloat = 36
    
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
        layer?.backgroundColor = IndustrialColors.surfaceContainerLow.cgColor
        
        setupPanelChrome()
        setupTimer()
        setupTransportKeys()
        setupButtonContainer()
        setupRecordButton()
        setupConstraints()
    }
    
    private func setupPanelChrome() {
        layer?.borderWidth = 0
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        
        topSeparator.backgroundColor = IndustrialColors.outline.cgColor
        topSeparator.opacity = 0.45
        layer?.addSublayer(topSeparator)
        
        headerLabel.isHidden = true
        headerLabel.font = IndustrialTypography.label
        headerLabel.textColor = IndustrialColors.onSurface
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)
        
        statusBadge.isHidden = true
        statusBadge.font = IndustrialTypography.label
        statusBadge.textColor = IndustrialColors.primary
        statusBadge.alignment = .center
        statusBadge.usesSingleLineMode = true
        statusBadge.cell?.isScrollable = false
        statusBadge.cell?.wraps = false
        // 垂直居中：通过内边距调整
        if let cell = statusBadge.cell as? NSTextFieldCell {
            cell.lineBreakMode = .byClipping
        }
        statusBadge.wantsLayer = true
        statusBadge.layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        statusBadge.layer?.borderWidth = 0
        statusBadge.layer?.borderColor = IndustrialColors.primaryContainer.cgColor
        statusBadge.layer?.cornerRadius = IndustrialCornerRadius.xs
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusBadge)
        
        readoutLabel.isHidden = true
        readoutLabel.font = IndustrialTypography.monoDB
        readoutLabel.textColor = IndustrialColors.onSurfaceVariant
        readoutLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(readoutLabel)
    }
    
    private func setupTimer() {
        timerLabel.stringValue = "00:00.00"
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Industrial Design: 青色发光（使用 CALayer）
        timerLabel.wantsLayer = true
        timerLabel.layer?.shadowColor = IndustrialColors.glowCyan.cgColor
        timerLabel.layer?.shadowRadius = 8
        timerLabel.layer?.shadowOpacity = 0.8
        timerLabel.layer?.shadowOffset = .zero
        
        addSubview(timerLabel)
    }
    
    private func setupTransportKeys() {
        [playButton, stopButton].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }
        // Accessibility identifiers for AI interaction testing
        playButton.setAccessibilityIdentifier("PlayButton")
        playButton.setAccessibilityLabel("Play")
        playButton.setAccessibilityRole(.button)
        playButton.setAccessibilityElement(true)
        stopButton.setAccessibilityIdentifier("StopButton")
        stopButton.setAccessibilityLabel("Stop")
        stopButton.setAccessibilityRole(.button)
        stopButton.setAccessibilityElement(true)
        playButton.isEnabled = true
        stopButton.isEnabled = false
        playButton.onClick = { [weak self] in
            guard let self = self else { return }
            switch self.currentRecordingState {
            case .recording, .preparing, .stopping:
                break
            default:
                self.delegate?.controlPanelViewDidTogglePlayback(self)
            }
        }
        stopButton.onClick = { [weak self] in
            guard let self = self else { return }
            switch self.currentRecordingState {
            case .recording, .preparing:
                self.delegate?.controlPanelViewDidStopRecording(self)
            case .playing:
                self.delegate?.controlPanelViewDidStopPlayback(self)
            default:
                break
            }
        }
    }
    
    private func setupButtonContainer() {
        buttonContainer.wantsLayer = true
        buttonContainer.layer?.backgroundColor = NSColor.clear.cgColor
        buttonContainer.layer?.masksToBounds = false
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonContainer)
        
        // 按钮底座：柔和圆角 + 内凹阴影
        buttonBaseLayer.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        buttonBaseLayer.borderColor = IndustrialColors.outlineVariant.cgColor
        buttonBaseLayer.borderWidth = 0
        buttonBaseLayer.cornerRadius = IndustrialCornerRadius.md
        buttonBaseLayer.shadowColor = NSColor.black.cgColor
        buttonBaseLayer.shadowRadius = 4
        buttonBaseLayer.shadowOpacity = 0.3
        buttonBaseLayer.shadowOffset = CGSize(width: 0, height: 2)
        buttonContainer.layer?.addSublayer(buttonBaseLayer)
        
        // 外环（柔和灰色）
        outerRingLayer.fillColor = NSColor.clear.cgColor
        outerRingLayer.strokeColor = IndustrialColors.outlineVariant.withAlphaComponent(0.4).cgColor
        outerRingLayer.lineWidth = 2.5
        outerRingLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        buttonContainer.layer?.addSublayer(outerRingLayer)
    }
    
    private func setupRecordButton() {
        // Accessibility identifier for AI interaction testing
        recordButton.setAccessibilityIdentifier("RecordButton")
        recordButton.setAccessibilityLabel("Record")
        recordButton.setAccessibilityRole(.button)
        recordButton.setAccessibilityElement(true)
        
        recordButton.wantsLayer = true
        recordButton.layer?.backgroundColor = IndustrialColors.statusCritical.cgColor
        recordButton.layer?.cornerRadius = 24
        
        // BUG-FIX-3: 简化发光效果，只保留单层柔和阴影
        recordButton.layer?.masksToBounds = false
        recordButton.layer?.shadowColor = IndustrialColors.statusCritical.cgColor
        recordButton.layer?.shadowOffset = CGSize(width: 0, height: 0)
        recordButton.layer?.shadowRadius = 12
        recordButton.layer?.shadowOpacity = 0.5
        
        // Industrial: 边框而非发光
        recordButton.layer?.borderWidth = 0
        recordButton.layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        
        recordButton.onClick = { [weak self] in
            self?.recordButtonClicked()
        }
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(recordButton)
        
        // Industrial: 添加 Hover/Press 交互追踪
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        buttonContainer.addTrackingArea(trackingArea)
        
        // 录制中视觉：内部白色方块（表示停止）
        if let layer = recordButton.layer {
            innerSquareLayer.backgroundColor = NSColor.white.cgColor
            innerSquareLayer.cornerRadius = 3
            innerSquareLayer.isHidden = true
            // 关闭隐式动画，避免约束动画时方块出现闪烁放大
            innerSquareLayer.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "hidden": NSNull(),
                "contents": NSNull()
            ]
            innerSquareLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            innerSquareLayer.bounds = CGRect(x: 0, y: 0, width: stopSquareSize, height: stopSquareSize)
            innerSquareLayer.position = CGPoint(x: recordButton.bounds.midX, y: recordButton.bounds.midY)
            layer.addSublayer(innerSquareLayer)
        }
    }
    
    private func setupConstraints() {
        let containerW = buttonContainer.widthAnchor.constraint(equalToConstant: 48)
        let containerH = buttonContainer.heightAnchor.constraint(equalToConstant: 48)
        let w = recordButton.widthAnchor.constraint(equalToConstant: normalButtonSize)
        let h = recordButton.heightAnchor.constraint(equalToConstant: normalButtonSize)
        
        buttonWidthConstraint = w
        buttonHeightConstraint = h
        
        NSLayoutConstraint.activate([
            // 头部标签紧贴顶部
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: IndustrialSpacing.md),
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            
            statusBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -IndustrialSpacing.md),
            statusBadge.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            statusBadge.widthAnchor.constraint(equalToConstant: 104),
            statusBadge.heightAnchor.constraint(equalToConstant: 20),
            
            // Transport 区域居中（适配 90px 高度）
            buttonContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonContainer.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 6),
            containerW,
            containerH,
            
            recordButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            recordButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            w,
            h,
            
            // Transport 按钮紧凑分组
            playButton.trailingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: -12),
            playButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            stopButton.leadingAnchor.constraint(equalTo: buttonContainer.trailingAnchor, constant: 12),
            stopButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            
            // 计时器居中对齐：放在录制按钮左侧，与按钮组整体居中
            timerLabel.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -16),
            timerLabel.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            
            // readout 标签隐藏（信息已移到状态栏）—— 放在底部不可见处
            readoutLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: IndustrialSpacing.md),
            readoutLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -IndustrialSpacing.md),
            readoutLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
    
    // MARK: - Actions
    @objc private func recordButtonClicked() {
        switch currentRecordingState {
        case .idle, .error:
            // 立即给出视觉反馈，但不改写最终状态样式，交由 updateRecordingState 统一控制
            innerSquareLayer.isHidden = true
            delegate?.controlPanelViewDidStartRecording(self)
        case .preparing, .recording:
            // 录制中点击应保持停止方块可见，直到状态进入 stopping/idle
            innerSquareLayer.isHidden = false
            delegate?.controlPanelViewDidStopRecording(self)
        case .stopping, .playing:
            break
        }
    }
    
    // MARK: - Public Methods
    func updateTimer(_ timeString: String) {
        timerLabel.stringValue = timeString

    }
    
    /// 更新录制目标描述（显示在 readout 行）
    func updateTargetDescription(_ description: String) {
        currentTargetDescription = description
        if currentRecordingState == .idle {
            readoutLabel.stringValue = ""
        }
    }

    func updatePlaybackPaused(_ isPaused: Bool) {
        guard currentRecordingState == .playing else { return }
        statusBadge.stringValue = isPaused ? "已暂停" : "播放中"
        readoutLabel.stringValue = ""
        playButton.setSymbol(isPaused ? "▶" : "Ⅱ")
        stopButton.isEnabled = true
    }
    
    func updateRecordingState(_ state: RecordingState) {
        currentRecordingState = state
        
        // 根据设计文档 REQ-2.0-02：准备就绪时只显示 REC 按钮
        let isRecording = (state == .recording || state == .preparing || state == .stopping)
        let isPlaying = (state == .playing)
        
        // 按钮显示/隐藏逻辑
        playButton.isHidden = !isPlaying  // 只有回看态显示播放按钮
        stopButton.isHidden = !isRecording  // 只有录制中/准备中/停止中显示停止按钮
        // recordButton 一直显示：idle/error 时是 REC，recording 时变为停止样式
        
        switch state {
        case .idle:
            statusBadge.stringValue = "准备就绪"
            statusBadge.textColor = IndustrialColors.primary
            statusBadge.layer?.borderColor = IndustrialColors.primaryContainer.cgColor
            readoutLabel.stringValue = ""
            recordButton.isEnabled = true
            playButton.isEnabled = false
            playButton.setSymbol("▶")
            stopButton.isEnabled = false
            innerSquareLayer.isHidden = true  // 显示 REC 圆形
            recordButton.layer?.backgroundColor = IndustrialColors.statusCritical.cgColor
            recordButton.layer?.cornerRadius = normalButtonSize / 2
            recordButton.layer?.shadowColor = IndustrialColors.statusCritical.cgColor
            recordButton.layer?.shadowRadius = 12
            recordButton.layer?.shadowOpacity = 0.5
            recordButton.layer?.borderColor = IndustrialColors.outlineVariant.cgColor
            setRecordButtonSize(normalButtonSize, animated: true)
            // REQ-2.0-02: idle 态录制按钮呼吸动画（视觉焦点暗示）
            startIdleBreathAnimation()
            
        case .preparing:
            stopIdleBreathAnimation()
            statusBadge.stringValue = "准备中"
            statusBadge.textColor = IndustrialColors.statusWarning
            statusBadge.layer?.borderColor = IndustrialColors.statusWarning.cgColor
            readoutLabel.stringValue = ""
            recordButton.isEnabled = false
            playButton.isEnabled = false
            playButton.setSymbol("▶")
            stopButton.isEnabled = true
            innerSquareLayer.isHidden = true
            recordButton.layer?.backgroundColor = IndustrialColors.statusCritical.withAlphaComponent(0.6).cgColor
            recordButton.layer?.cornerRadius = normalButtonSize / 2
            recordButton.layer?.shadowColor = IndustrialColors.statusCritical.cgColor
            recordButton.layer?.shadowRadius = 8
            recordButton.layer?.shadowOpacity = 0.3
            setRecordButtonSize(normalButtonSize, animated: false)
            
        case .recording:
            statusBadge.stringValue = "录制中"
            statusBadge.textColor = IndustrialColors.statusDanger
            statusBadge.layer?.borderColor = IndustrialColors.statusDanger.cgColor
            readoutLabel.stringValue = ""
            recordButton.isEnabled = true
            playButton.isEnabled = false
            playButton.setSymbol("▶")
            stopButton.isEnabled = true
            innerSquareLayer.isHidden = false  // 显示停止方块
            recordButton.layer?.backgroundColor = IndustrialColors.statusCritical.cgColor
            recordButton.layer?.cornerRadius = recordingButtonSize / 2
            recordButton.layer?.shadowColor = IndustrialColors.statusCritical.cgColor
            recordButton.layer?.shadowRadius = 16
            recordButton.layer?.shadowOpacity = 0.7
            recordButton.layer?.borderColor = IndustrialColors.statusDanger.cgColor
            setRecordButtonSize(recordingButtonSize, animated: true)
            
        case .stopping:
            statusBadge.stringValue = "停止中"
            statusBadge.textColor = IndustrialColors.statusWarning
            statusBadge.layer?.borderColor = IndustrialColors.statusWarning.cgColor
            readoutLabel.stringValue = ""
            recordButton.isEnabled = false
            stopButton.isEnabled = false
            innerSquareLayer.isHidden = false
            recordButton.layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
            recordButton.layer?.cornerRadius = recordingButtonSize / 2
            recordButton.layer?.shadowRadius = 6
            recordButton.layer?.shadowOpacity = 0.3
            setRecordButtonSize(recordingButtonSize, animated: false)
            
        case .playing:
            statusBadge.stringValue = "回看态"
            statusBadge.textColor = IndustrialColors.primary
            statusBadge.layer?.borderColor = IndustrialColors.primaryContainer.cgColor
            readoutLabel.stringValue = ""
            recordButton.isEnabled = false
            playButton.isEnabled = true
            playButton.setSymbol("Ⅱ")
            stopButton.isEnabled = true
            innerSquareLayer.isHidden = true
            recordButton.layer?.backgroundColor = IndustrialColors.statusCritical.withAlphaComponent(0.4).cgColor
            recordButton.layer?.cornerRadius = normalButtonSize / 2
            recordButton.layer?.shadowRadius = 8
            recordButton.layer?.shadowOpacity = 0.3
            setRecordButtonSize(normalButtonSize, animated: true)
            
        case .error:
            statusBadge.stringValue = "错误"
            statusBadge.textColor = IndustrialColors.statusDanger
            statusBadge.layer?.borderColor = IndustrialColors.statusDanger.cgColor
            readoutLabel.stringValue = ""
            recordButton.isEnabled = true
            playButton.isEnabled = false
            playButton.setSymbol("▶")
            stopButton.isEnabled = false
            innerSquareLayer.isHidden = true
            recordButton.layer?.backgroundColor = IndustrialColors.statusDanger.cgColor
            recordButton.layer?.cornerRadius = normalButtonSize / 2
            recordButton.layer?.shadowColor = IndustrialColors.glowDanger.cgColor
            recordButton.layer?.shadowRadius = 20
            recordButton.layer?.shadowOpacity = 1.0
            setRecordButtonSize(normalButtonSize, animated: false)
        }
    }
    
    // MARK: - Layout
    override func layout() {
        super.layout()
        
        // 更新顶部硬边分隔线
        topSeparator.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        
        // 更新按钮硬件底座
        buttonBaseLayer.frame = buttonContainer.bounds.insetBy(dx: 3, dy: 3)
        
        // 更新内方块的位置与外环路径
        layoutStopSquareLayer()
        
        // 外环路径：以容器中间为圆心，稍大于内部按钮，保留间距
        let bounds = buttonContainer.bounds
        if bounds.width > 0 && bounds.height > 0 {
            outerRingLayer.frame = bounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = min(bounds.width, bounds.height) / 2 - outerRingLayer.lineWidth / 2 - 1
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: center.x, y: center.y), radius: radius, startAngle: 0, endAngle: 360)
            // 构造 CGPath 兼容旧系统
            let cgPath = CGMutablePath()
            cgPath.addArc(center: CGPoint(x: center.x, y: center.y), radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
            outerRingLayer.path = cgPath
        }
    }

    // MARK: - REQ-2.0-02 Idle Breath Animation
    
    /// idle 态录制按钮呼吸动画——微妙的发光脉冲暗示"可点击"
    private func startIdleBreathAnimation() {
        stopIdleBreathAnimation()
        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.fromValue = 0.3
        animation.toValue = 0.7
        animation.duration = 2.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        recordButton.layer?.add(animation, forKey: "idleBreath")
    }
    
    /// 停止呼吸动画
    private func stopIdleBreathAnimation() {
        recordButton.layer?.removeAnimation(forKey: "idleBreath")
    }

    // MARK: - Helpers
    private func layoutStopSquareLayer() {
        guard recordButton.bounds.width > 0, recordButton.bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        innerSquareLayer.bounds = CGRect(x: 0, y: 0, width: stopSquareSize, height: stopSquareSize)
        innerSquareLayer.position = CGPoint(x: recordButton.bounds.midX, y: recordButton.bounds.midY)
        CATransaction.commit()
    }

    private func setRecordButtonSize(_ size: CGFloat, animated: Bool) {
        guard let w = buttonWidthConstraint, let h = buttonHeightConstraint else { return }
        w.constant = size
        h.constant = size
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                layoutSubtreeIfNeeded()
                layoutStopSquareLayer()
            } completionHandler: { [weak self] in
                self?.layoutStopSquareLayer()
            }
        } else {
            layoutSubtreeIfNeeded()
            layoutStopSquareLayer()
        }
    }
}
