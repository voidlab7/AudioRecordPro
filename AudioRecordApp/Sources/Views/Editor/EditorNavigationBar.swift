import Cocoa
import AVFoundation

// MARK: - Delegate Protocol
protocol EditorNavigationBarDelegate: AnyObject {
    func editorNavigationBarDidTapBack(_ bar: EditorNavigationBar)
    func editorNavigationBarDidTapUndo(_ bar: EditorNavigationBar)
    func editorNavigationBarDidTapRedo(_ bar: EditorNavigationBar)
    func editorNavigationBarDidTapSave(_ bar: EditorNavigationBar)
    func editorNavigationBarDidSelectTool(_ bar: EditorNavigationBar, tool: EditorToolType)
}

// MARK: - EditorNavigationBar
/// 编辑器导航栏 — 参考剪映顶部工具栏布局
/// 左侧: ◀返回 | ↩撤销 ↪重做 | ✂裁剪 ⫿静音 📊标准化 🔊淡入淡出
/// 右侧: [保存]
class EditorNavigationBar: NSView {
    
    // MARK: - UI Components
    private let backButton = IndustrialCompactIconButton(symbol: "◀")
    private let separatorView1 = NSView()
    private let undoButton = IndustrialCompactIconButton(symbol: "↩")
    private let redoButton = IndustrialCompactIconButton(symbol: "↪")
    private let separatorView2 = NSView()
    private var toolButtons: [EditorToolType: IndustrialCompactIconButton] = [:]
    private let saveButton = IndustrialButtonView(title: "保存", icon: nil)
    private let bottomSeparator = CALayer()
    
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
        
        // 编辑工具图标（参考剪映：纯图标一排）
        for tool in EditorToolType.allCases {
            let button = IndustrialCompactIconButton(symbol: "")
            if let image = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.rawValue) {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                button.setImage(image.withSymbolConfiguration(config))
            }
            button.toolTip = tool.rawValue
            button.translatesAutoresizingMaskIntoConstraints = false
            button.onClick = { [weak self] in
                guard let self else { return }
                self.selectTool(tool)
                self.delegate?.editorNavigationBarDidSelectTool(self, tool: tool)
            }
            addSubview(button)
            toolButtons[tool] = button
        }
        
        // 保存
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.isEnabled = false
        saveButton.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.editorNavigationBarDidTapSave(self)
        }
        addSubview(saveButton)
    }
    
    private func setupSeparator(_ sep: NSView) {
        sep.wantsLayer = true
        sep.layer?.backgroundColor = IndustrialColors.outlineVariant.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)
    }
    
    private func setupConstraints() {
        // 左侧组: ◀ | ↩ ↪ | tool1 tool2 tool3 tool4
        NSLayoutConstraint.activate([
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
        ])
        
        // 编辑工具按钮紧跟分隔线2
        let toolOrder = EditorToolType.allCases
        var prevView: NSView = separatorView2
        for tool in toolOrder {
            guard let button = toolButtons[tool] else { continue }
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: prevView.trailingAnchor, constant: prevView === separatorView2 ? 6 : 2),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            prevView = button
        }
        
        // 右侧: 保存
        NSLayoutConstraint.activate([
            saveButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            saveButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 56),
            saveButton.heightAnchor.constraint(equalToConstant: 26)
        ])
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
    
    func updateSaveState(hasUnsavedChanges: Bool) {
        saveButton.isEnabled = hasUnsavedChanges
        if hasUnsavedChanges {
            saveButton.layer?.borderColor = IndustrialColors.primaryContainer.cgColor
            saveButton.layer?.borderWidth = 1
        } else {
            saveButton.layer?.borderWidth = 0
        }
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
        selectedTool = tool
        for (type, button) in toolButtons {
            if type == tool {
                button.layer?.borderColor = IndustrialColors.primaryContainer.cgColor
                button.layer?.borderWidth = 1.5
            } else {
                button.layer?.borderWidth = 0
            }
        }
    }
}
