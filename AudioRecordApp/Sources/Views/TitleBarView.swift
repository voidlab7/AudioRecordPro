import Cocoa

/// 标题栏委托
protocol TitleBarViewDelegate: AnyObject {
    func titleBarDidRequestExport(_ view: TitleBarView)
}

/// 自定义标题栏视图 — App名称 + 录制目标 + 导出按钮
/// 位于窗口顶部 38px 区域（一体化标题栏），与红绿灯按钮同行
class TitleBarView: NSView {
    
    // MARK: - Properties
    weak var delegate: TitleBarViewDelegate?
    private(set) var isExportEnabled: Bool = false
    
    // MARK: - UI Components
    private let appTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Loocap")
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = IndustrialColors.onSurface.withAlphaComponent(0.8)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    /// UI-003: 源名 Capsule 药丸容器（设计实测 #202F2E 暗青底 + 薄荷细边）
    private let targetCapsule: NSView = {
        let v = NSView()
        v.wantsLayer = true
        // v3.1: Figma #13BBA3@0.15，按老板截图渲染观感折中 @0.30
        v.layer?.backgroundColor = NSColor(hex: "#13BBA3").withAlphaComponent(0.30).cgColor
        v.layer?.cornerRadius = 11
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor(hex: "#13BBA3").withAlphaComponent(0.25).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let targetLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = IndustrialColors.primaryFixed
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let exportButton: NSButton = {
        let btn = NSButton(title: "导出".localized, target: nil, action: nil)
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        btn.isEnabled = false
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
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
        // 标题栏透明，与窗口一体化
        layer?.backgroundColor = NSColor.clear.cgColor
        
        addSubview(appTitleLabel)
        addSubview(targetCapsule)
        targetCapsule.addSubview(targetLabel)
        addSubview(exportButton)

        exportButton.target = self
        exportButton.action = #selector(exportClicked)

        NSLayoutConstraint.activate([
            // App 标题在左侧（避开红绿灯 ~76px）
            appTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 78),
            appTitleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // UI-003: 录制目标居中翠绿药丸（label 上下左右内边距 10/6）
            targetCapsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            targetCapsule.centerYAnchor.constraint(equalTo: centerYAnchor),
            targetCapsule.leadingAnchor.constraint(greaterThanOrEqualTo: appTitleLabel.trailingAnchor, constant: 16),
            targetLabel.topAnchor.constraint(equalTo: targetCapsule.topAnchor, constant: 3),
            targetLabel.bottomAnchor.constraint(equalTo: targetCapsule.bottomAnchor, constant: -3),
            targetLabel.leadingAnchor.constraint(equalTo: targetCapsule.leadingAnchor, constant: 12),
            targetLabel.trailingAnchor.constraint(equalTo: targetCapsule.trailingAnchor, constant: -12),

            // 导出按钮右侧
            exportButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            exportButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            exportButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            targetCapsule.trailingAnchor.constraint(lessThanOrEqualTo: exportButton.leadingAnchor, constant: -16),
        ])
    }
    
    // MARK: - Public
    
    func updateTargetDescription(_ description: String) {
        targetLabel.stringValue = "Selected Source: %@".localized(description)
    }

    /// 更新录制目标文字 — 多选格式：1 个源显示 App 名，多个显示 "A, B +N"
    /// - Parameter names: 选中音源名称数组（有序）
    func updateTargetNames(_ names: [String]) {
        let inner: String
        if names.isEmpty {
            inner = "未选择录制目标".localized
        } else if names.count == 1 {
            inner = names[0]
        } else {
            // "A, B +N" 格式：显示前 2 个名 + 剩余数
            let displayNames = names.prefix(2).joined(separator: ", ")
            let remaining = names.count - 2
            if remaining > 0 {
                inner = "\(displayNames) +\(remaining)"
            } else {
                inner = displayNames
            }
        }
        targetLabel.stringValue = "Selected Source: %@".localized(inner)
    }
    
    func setExportEnabled(_ enabled: Bool) {
        isExportEnabled = enabled
        exportButton.isEnabled = enabled
    }
    
    // MARK: - Actions
    @objc private func exportClicked() {
        guard isExportEnabled else { return }
        delegate?.titleBarDidRequestExport(self)
    }
}
