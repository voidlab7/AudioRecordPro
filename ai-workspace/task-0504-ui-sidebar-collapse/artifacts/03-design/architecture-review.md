# 架构评审：Sidebar 折叠/展开能力

> 角色: 矩·架构师 | Task: task-0504-ui-sidebar-collapse
> 日期: 2026-05-05 | 状态: Review Complete

---

## 1. 技术方案总览

采用 **NSSplitViewController + toggleSidebar:** 原生方案，最小侵入式改造。

---

## 2. 核心修改：canCollapseSubview

### 2.1 当前代码（MainWindowView.swift:312）

```swift
func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
    return false // 禁止折叠
}
```

### 2.2 修改方案

```swift
func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
    return subview == sidebarView // 仅允许 Sidebar 折叠
}
```

### 2.3 影响评估

| 影响项 | 风险 | 说明 |
|--------|------|------|
| 双击分隔线 | 低 | NSSplitView 默认双击折叠，需确认是否需要禁用 |
| 拖动到极限 | 低 | 拖到 < minPosition 时自动触发折叠动画 |
| Sidebar 内部状态 | 无 | 折叠只是视觉隐藏，SidebarView 实例保持不变 |
| 进程列表刷新 | 无 | 折叠状态下后台刷新仍然正常 |
| 录制功能 | 无 | 录制不依赖 Sidebar 显示状态 |

---

## 3. 快捷键方案：⌘+Shift+S

### 3.1 实现方式

**方案 A（推荐）：NSMenuItem + toggleSidebar: action**

```swift
// 在 AppDelegate 或 MainMenu 中添加菜单项
let viewMenu = NSMenu(title: "View")
let toggleItem = NSMenuItem(
    title: "Toggle Sidebar",
    action: #selector(NSSplitViewController.toggleSidebar(_:)),
    keyEquivalent: "s"
)
toggleItem.keyEquivalentModifierMask = [.command, .shift]
viewMenu.addItem(toggleItem)
```

**优势**：
- 系统原生支持 `toggleSidebar:` 响应链路
- 菜单中自动显示快捷键标注
- 无需自定义 key event 处理

### 3.2 冲突检查

| 快捷键 | 系统/应用使用 | 冲突? |
|--------|--------------|-------|
| ⌘+S | Save（当前应用无文档保存） | ❌ 无冲突 |
| ⌘+Shift+S | Save As（当前应用无此功能） | ❌ 无冲突 |
| ⌘+Option+S | 无 | ❌ 备选 |

**结论**：`⌘+Shift+S` 可安全使用。

### 3.3 响应链路

```
⌘+Shift+S
  → NSApplication.sendAction(_:to:from:)
  → NSWindow (MainWindow)
  → MainWindowView (或 NSSplitViewController)
  → toggleSidebar:
  → NSSplitView.setPosition(_:ofDividerAt:) 动画
```

---

## 4. 折叠/展开实现

### 4.1 推荐方案：NSSplitView.animator().setPosition

```swift
// MainWindowView 中新增方法
func toggleSidebar(animated: Bool = true) {
    let isCollapsed = splitView.isSubviewCollapsed(sidebarView)
    
    if isCollapsed {
        // 展开
        let targetWidth = IndustrialSpacing.sidebarWidth // 240
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = IndustrialAnimation.sidebarToggle // 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                splitView.animator().setPosition(targetWidth, ofDividerAt: 0)
            }
        } else {
            splitView.setPosition(targetWidth, ofDividerAt: 0)
        }
    } else {
        // 折叠
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = IndustrialAnimation.sidebarToggle
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                splitView.animator().setPosition(0, ofDividerAt: 0)
            }
        } else {
            splitView.setPosition(0, ofDividerAt: 0)
        }
    }
    
    // 保存状态
    saveSidebarState(collapsed: !isCollapsed)
}
```

### 4.2 约束调整

当前 `sidebarView.widthAnchor.constraint(equalToConstant: 240)` 会阻止折叠。

**修改**：
```swift
// 移除固定宽度约束
// sidebarView.widthAnchor.constraint(equalToConstant: IndustrialSpacing.sidebarWidth)

// 改为通过 SplitView delegate 控制
func splitView(_ splitView: NSSplitView,
               constrainMinCoordinate proposedMinimumPosition: CGFloat,
               ofSubviewAt dividerIndex: Int) -> CGFloat {
    return 0  // 允许折叠到 0（之前是 200）
}
```

### 4.3 展开时的最小宽度保护

```swift
func splitView(_ splitView: NSSplitView,
               constrainMinCoordinate proposedMinimumPosition: CGFloat,
               ofSubviewAt dividerIndex: Int) -> CGFloat {
    // 如果正在展开状态，最小宽度为 200
    // 如果正在折叠（position < 50），允许到 0
    let currentPosition = splitView.subviews[0].frame.width
    return currentPosition < 50 ? 0 : 200
}
```

---

## 5. 状态持久化方案

### 5.1 UserDefaults Key

```swift
private let sidebarCollapsedKey = "AudioRecord.sidebar.isCollapsed"
```

### 5.2 保存时机

- 每次 toggle 完成后保存
- 应用退出时**不需要**额外保存（toggle 已保存）

### 5.3 读取时机

- `setupView()` 中，在 `setupSplitView()` 之后检查：

```swift
private func restoreSidebarState() {
    let isCollapsed = UserDefaults.standard.bool(forKey: sidebarCollapsedKey)
    if isCollapsed {
        // 无动画折叠（启动时不需要动画）
        splitView.setPosition(0, ofDividerAt: 0)
    }
}
```

### 5.4 首次启动

- `UserDefaults.bool(forKey:)` 默认返回 `false`
- 即首次启动时 `isCollapsed = false` → Sidebar 展开（符合需求）

---

## 6. Toolbar 按钮集成

### 6.1 添加 NSToolbarItem

```swift
// AppDelegate.swift 的 createMainWindow() 中
let toolbar = NSToolbar(identifier: "MainToolbar")
toolbar.delegate = self  // 新增 delegate
toolbar.displayMode = .iconOnly
toolbar.showsBaselineSeparator = false
window.toolbar = toolbar
```

### 6.2 Toolbar Delegate

```swift
extension AppDelegate: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, 
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .toggleSidebar {
            let item = NSToolbarItem(itemIdentifier: .toggleSidebar)
            item.label = "Toggle Sidebar"
            item.toolTip = "Show or hide the sidebar (⇧⌘S)"
            item.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "Toggle Sidebar")
            item.action = #selector(toggleSidebarAction(_:))
            item.target = nil  // 走响应链
            return item
        }
        return nil
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .flexibleSpace]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .flexibleSpace]
    }
}
```

---

## 7. 文件修改清单

| 文件 | 修改类型 | 说明 |
|------|---------|------|
| `MainWindowView.swift` | 修改 | canCollapseSubview、移除固定宽度约束、新增 toggleSidebar() |
| `MainWindowView.swift` | 修改 | constrainMinCoordinate 改为允许 0 |
| `AppDelegate.swift` | 修改 | Toolbar delegate、菜单项 |
| `IndustrialDesignTokens.swift` | 新增 | `IndustrialAnimation.sidebarToggle = 0.25` |
| 新文件（可选） | 新增 | `SidebarStateManager.swift` 或直接写在 MainWindowView 中 |

---

## 8. 风险评估

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| 折叠时约束冲突 | 中 | 控制台警告 | 移除固定宽度约束，改为 delegate 控制 |
| 折叠动画卡顿 | 低 | 用户体验 | 使用 animator() 系统原生动画 |
| toggleSidebar: 响应链失败 | 低 | 快捷键无效 | 自定义 action 方法作为 fallback |
| 折叠后 Sidebar 接收事件 | 极低 | 逻辑错误 | 系统自动 clip，不会接收鼠标事件 |

---

## 9. 架构审查结论

| 项 | 决策 |
|----|------|
| 实现方式 | ✅ NSSplitView 原生 collapse + animator |
| 快捷键 | ✅ ⌘+Shift+S via NSMenuItem |
| 持久化 | ✅ UserDefaults 单 key |
| 约束策略 | ✅ 移除固定宽度，delegate 控制 min/max |
| 风险等级 | ✅ 低（原生 API，无 hack） |
| 预估工时 | 2-3 小时实现 + 1 小时测试 |
