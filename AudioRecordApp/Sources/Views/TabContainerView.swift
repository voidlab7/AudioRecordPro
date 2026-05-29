import Cocoa
import Foundation

// MARK: - TabItem
struct TabItem {
    let id: String
    let title: String
    let icon: String?
    let view: NSView
    
    init(id: String, title: String, icon: String? = nil, view: NSView) {
        self.id = id
        self.title = title
        self.icon = icon
        self.view = view
    }
}

// MARK: - Delegate Protocol
protocol TabContainerViewDelegate: AnyObject {
    func tabContainerViewDidSelectTab(_ view: TabContainerView, tabId: String)
}

// MARK: - TabContainerView
/// Tab容器视图 - 管理多个Tab的切换
class TabContainerView: NSView {
    
    // MARK: - UI Components
    private let tabBarView = NSView()
    private let contentView = NSView()
    private var tabButtons: [String: IndustrialTabButtonView] = [:]
    private var selectedTabId: String?
    private var tabButtonConstraints: [NSLayoutConstraint] = []
    
    // MARK: - Properties
    weak var delegate: TabContainerViewDelegate?
    private var tabs: [TabItem] = []
    
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
        // Industrial Design: 透明背景（不覆盖父视图）
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        setupTabBar()
        setupContentView()
        setupConstraints()
    }
    
    private func setupTabBar() {
        tabBarView.wantsLayer = true
        // Industrial Design: 深灰背景
        tabBarView.layer?.backgroundColor = IndustrialColors.surfaceContainerHigh.cgColor
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabBarView)
    }
    
    private func setupContentView() {
        contentView.wantsLayer = true
        // Industrial Design: 透明背景（不覆盖）
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Tab栏约束
            tabBarView.topAnchor.constraint(equalTo: topAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 44),
            
            // 内容视图约束
            contentView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    // MARK: - Public Methods
    
    /// 添加Tab
    func addTab(_ tab: TabItem) {
        tabs.append(tab)
        createTabButton(for: tab)
        
        // 如果是第一个Tab，自动选中
        if selectedTabId == nil {
            selectTab(tab.id)
        }
    }
    
    /// 选择Tab
    func selectTab(_ tabId: String) {
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return }
        
        // 更新按钮状态
        updateTabButtonStates(selectedId: tabId)
        
        // 更新内容视图
        updateContentView(with: tab)
        
        selectedTabId = tabId
        delegate?.tabContainerViewDidSelectTab(self, tabId: tabId)
    }
    
    /// 获取当前选中的Tab ID
    func getSelectedTabId() -> String? {
        return selectedTabId
    }
    
    /// 获取指定Tab的视图
    func getTabView(_ tabId: String) -> NSView? {
        return tabs.first(where: { $0.id == tabId })?.view
    }
    
    // MARK: - Private Methods
    
    private func createTabButton(for tab: TabItem) {
        let button = IndustrialTabButtonView(title: tab.title, icon: tab.icon)
        let index = tabs.count - 1
        button.onClick = { [weak self] in
            guard let self = self, index >= 0 && index < self.tabs.count else { return }
            self.selectTab(self.tabs[index].id)
        }
        
        tabButtons[tab.id] = button
        tabBarView.addSubview(button)
        
        // Rebuild all button constraints from scratch
        rebuildAllTabButtonConstraints()
    }
    
    private func rebuildAllTabButtonConstraints() {
        // Remove all existing tab button constraints
        NSLayoutConstraint.deactivate(tabButtonConstraints)
        tabButtonConstraints.removeAll()
        
        guard !tabs.isEmpty else { return }
        
        var constraints: [NSLayoutConstraint] = []
        var previousButton: IndustrialTabButtonView?
        
        for (index, tab) in tabs.enumerated() {
            guard let button = tabButtons[tab.id] else { continue }
            button.translatesAutoresizingMaskIntoConstraints = false
            
            // Vertical centering and height
            constraints.append(button.centerYAnchor.constraint(equalTo: tabBarView.centerYAnchor))
            constraints.append(button.heightAnchor.constraint(equalToConstant: 32))
            
            if index == 0 {
                // First button: leading anchor
                constraints.append(button.leadingAnchor.constraint(equalTo: tabBarView.leadingAnchor, constant: 8))
            } else if let prev = previousButton {
                // Subsequent buttons: follow previous button with gap
                constraints.append(button.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: 4))
                // Equal width to first button
                let firstButton = tabButtons[tabs[0].id]!
                constraints.append(button.widthAnchor.constraint(equalTo: firstButton.widthAnchor))
            }
            
            // Last button: trailing anchor
            if index == tabs.count - 1 {
                constraints.append(button.trailingAnchor.constraint(equalTo: tabBarView.trailingAnchor, constant: -8))
            }
            
            previousButton = button
        }
        
        NSLayoutConstraint.activate(constraints)
        tabButtonConstraints = constraints
    }
    
    private func updateTabButtonStates(selectedId: String) {
        for (tabId, button) in tabButtons {
            button.isSelectedTab = (tabId == selectedId)
        }
    }
    
    private func updateContentView(with tab: TabItem) {
        // 移除当前内容视图的所有子视图
        for subview in contentView.subviews {
            subview.removeFromSuperview()
        }
        
        // 添加新的内容视图
        tab.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tab.view)
        
        NSLayoutConstraint.activate([
            tab.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            tab.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tab.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tab.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
}
