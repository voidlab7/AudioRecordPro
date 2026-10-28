import Cocoa
import AVFoundation

// MARK: - Delegate Protocol
protocol EditorNavigationBarDelegate: AnyObject {
    func editorNavigationBarDidTapBack(_ bar: EditorNavigationBar)
    func editorNavigationBarDidTapUndo(_ bar: EditorNavigationBar)
    func editorNavigationBarDidTapRedo(_ bar: EditorNavigationBar)
    func editorNavigationBarDidSelectTool(_ bar: EditorNavigationBar, tool: EditorToolType)
}

// MARK: - EditorNavigationBar
/// 编辑器导航栏 — UI-026 剪映风重构：
/// 无边框线性图标（常态无底色、hover 才出底色）、按功能分组、组间分隔线；激活工具=青绿着色
/// 左侧: ◀返回 | ↩撤销 ↪重做 | ✂裁剪 ⫿切分 🗑删除 | 🔇静音裁剪 📊标准化 🔊淡入淡出
class EditorNavigationBar: NSView {

    // MARK: - UI Components
    private let backButton = IndustrialCompactIconButton(symbol: "◀")
    private let separatorView1 = NSView()
    private let undoButton = IndustrialCompactIconButton(symbol: "↩")
    private let redoButton = IndustrialCompactIconButton(symbol: "↪")
    private let separatorView2 = NSView()
    private let separatorView3 = NSView()
    private var toolButtons: [EditorToolType: IndustrialCompactIconButton] = [:]
    private let bottomSeparator = CALayer()

    /// UI-026: 工具按功能分组（组间分隔线）——时间轴结构操作 | 音频效果操作
    private let toolGroups: [[EditorToolType]] = [
        [.trim, .split, .delete],
        [.silenceTrim, .normalize, .fade],
    ]
    
    // MARK: - Properties
    weak var delegate: EditorNavigationBarDelegate?
    private var selectedTool: EditorToolType?
    
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
        layer?.backgroundColor = IndustrialColors.surfaceContainerLowest.cgColor
        
        bottomSeparator.backgroundColor = IndustrialColors.outlineVariant.cgColor
        layer?.addSublayer(bottomSeparator)
        
        setupButtons()
        setupConstraints()
    }
    
    private func setupButtons() {
        // 返回
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.editorNavigationBarDidTapBack(self)
        }
        addSubview(backButton)
        
        // 分隔线 1
        setupSeparator(separatorView1)
        
        // 撤销/重做
        undoButton.translatesAutoresizingMaskIntoConstraints = false
        undoButton.isEnabled = false
        undoButton.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.editorNavigationBarDidTapUndo(self)
        }
        addSubview(undoButton)
        
        redoButton.translatesAutoresizingMaskIntoConstraints = false
        redoButton.isEnabled = false
        redoButton.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.editorNavigationBarDidTapRedo(self)
        }
        addSubview(redoButton)
        
        // 分隔线 2
        setupSeparator(separatorView2)

        // UI-026: 分隔线 3（工具组间）
        setupSeparator(separatorView3)
        
        // 编辑工具图标（UI-026 剪映风：无边框线性图标、按功能分组；切分/删除为 UI-028 并入）
        for tool in EditorToolType.allCases {
            let button = IndustrialCompactIconButton(symbol: "")
            button.hasRestingBackground = false
            if let image = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.rawValue.localized) {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                button.setImage(image.withSymbolConfiguration(config))
            }
            button.toolTip = tool.rawValue.localized  // REL-003: rawValue=中文 key，显示点走本地化
            button.translatesAutoresizingMaskIntoConstraints = false
            button.onClick = { [weak self] in
                guard let self else { return }
                self.selectTool(tool)
                self.delegate?.editorNavigationBarDidSelectTool(self, tool: tool)
            }
            addSubview(button)
            toolButtons[tool] = button
        }
    }
    
    private func setupSeparator(_ sep: NSView) {
        sep.wantsLayer = true
        sep.layer?.backgroundColor = IndustrialColors.outlineVariant.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)
    }
    
    private func setupConstraints() {
        // 左侧组: ◀ | ↩ ↪ | 组1(裁剪 切分 删除) | 组2(静音裁剪 标准化 淡入淡出)
        var all: [NSLayoutConstraint] = [
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            separatorView1.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 6),
            separatorView1.centerYAnchor.constraint(equalTo: centerYAnchor),
            separatorView1.widthAnchor.constraint(equalToConstant: 1),
            separatorView1.heightAnchor.constraint(equalToConstant: 18),

            undoButton.leadingAnchor.constraint(equalTo: separatorView1.trailingAnchor, constant: 6),
            undoButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            redoButton.leadingAnchor.constraint(equalTo: undoButton.trailingAnchor, constant: 2),
            redoButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            separatorView2.leadingAnchor.constraint(equalTo: redoButton.trailingAnchor, constant: 6),
            separatorView2.centerYAnchor.constraint(equalTo: centerYAnchor),
            separatorView2.widthAnchor.constraint(equalToConstant: 1),
            separatorView2.heightAnchor.constraint(equalToConstant: 18),
        ]

        // UI-026: 工具按功能分组布局，组间用分隔线 3
        var prevView: NSView = separatorView2
        for (groupIndex, group) in toolGroups.enumerated() {
            for tool in group {
                guard let button = toolButtons[tool] else { continue }
                all.append(button.leadingAnchor.constraint(equalTo: prevView.trailingAnchor, constant: prevView === separatorView2 || prevView === separatorView3 ? 6 : 2))
                all.append(button.centerYAnchor.constraint(equalTo: centerYAnchor))
                prevView = button
            }
            if groupIndex < toolGroups.count - 1 {
                all.append(separatorView3.leadingAnchor.constraint(equalTo: prevView.trailingAnchor, constant: 6))
                all.append(separatorView3.centerYAnchor.constraint(equalTo: centerYAnchor))
                all.append(separatorView3.widthAnchor.constraint(equalToConstant: 1))
                all.append(separatorView3.heightAnchor.constraint(equalToConstant: 18))
                prevView = separatorView3
            }
        }
        NSLayoutConstraint.activate(all)
    }
    
    override func layout() {
        super.layout()
        bottomSeparator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    }
    
    // MARK: - Public Methods

    func setFileName(_ name: String) {
        // 文件名不再在导航栏中显示（空间让给工具图标）
    }

    /// 设置完整文件信息（V2.1 文件联动）
    /// 显示: 文件名 | 时长 | 采样率·位深·声道 | 大小
    func setFileInfo(_ file: RecordedFileInfo, format: AVAudioFormat? = nil) {
        // 在 backButton 右侧或状态栏中显示信息
        // 当前导航栏空间紧张，文件信息通过 EditorStatusBar 展示
        // 此方法预留用于未来扩展或 tooltip
    }
    
    func updateUndoRedoState(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    func setToolEnabled(_ tool: EditorToolType, enabled: Bool) {
        toolButtons[tool]?.isEnabled = enabled
    }
    
    func setAllToolsEnabled(_ enabled: Bool) {
        for button in toolButtons.values {
            button.isEnabled = enabled
        }
    }
    
    // MARK: - Private
    
    private func selectTool(_ tool: EditorToolType) {
        // UI-026: 选中态=青绿着色（无边框语义）；再点同工具取消激活
        let wasActive = (selectedTool == tool)
        selectedTool = wasActive ? nil : tool
        for (type, button) in toolButtons {
            button.isTintColorActive = (type == selectedTool)
        }
    }
}
