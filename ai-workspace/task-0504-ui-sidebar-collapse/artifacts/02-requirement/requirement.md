# 需求文档：为 Sidebar 添加折叠/展开能力和快捷键

> Task ID: task-0504-ui-sidebar-collapse
> 优先级: P0 | 类型: design | 路由: 绘·设计 → 矩·架构

---

## 1. 背景

AudioRecord Mac 录音应用采用 NSSplitView 实现左右分栏布局。左侧 Sidebar（240px）承载录制源选择和已录制文件列表，右侧为内容区（波形、轨道、控制面板）。

**当前问题**：
- `MainWindowView.swift` 第 312 行 `canCollapseSubview` 返回 `false`，Sidebar 始终展示且不可折叠
- 窗口宽度仅 800px 时，Sidebar 占 30%，内容区略紧凑
- 用户录制过程中，可能更希望看到完整波形而非一直展示 Sidebar
- 对比同类专业音频软件（Logic Pro、Audacity），均支持 Sidebar 折叠

## 2. 目标

为 Sidebar 添加折叠/展开能力，让用户可以按需隐藏侧边栏以获得更多内容区空间。

## 3. 功能需求

### 3.1 折叠行为
- [ ] Sidebar 支持折叠（宽度 → 0，动画过渡）
- [ ] Sidebar 支持展开（恢复到 240px，动画过渡）
- [ ] 启动时默认展开 Sidebar（保持当前行为不变）
- [ ] 折叠状态下，内容区自动占满窗口宽度

### 3.2 触发方式
- [ ] 提供 toolbar 按钮（sidebar.leading 图标）或 Sidebar 顶部折叠按钮
- [ ] 键盘快捷键 `⌘+Shift+S`（或 `⌘+Option+S`，与系统不冲突）
- [ ] 菜单栏 View → Toggle Sidebar

### 3.3 状态持久化
- [ ] 通过 UserDefaults 保存 Sidebar 是否展开
- [ ] 下次启动恢复上次的折叠/展开状态

### 3.4 动画要求
- [ ] 折叠/展开使用 250ms 的 ease-in-out 动画
- [ ] 折叠过程中 Sidebar 内容 clip 不溢出
- [ ] 动画过程中不触发约束冲突警告

## 4. 设计约束

- 必须保持 Industrial Design 风格一致性（暗色主题、青色点缀）
- 折叠按钮图标尺寸不超过 16×16pt
- 不引入新的第三方依赖

## 5. 技术约束

| 文件 | 当前行为 | 需要修改 |
|------|---------|----------|
| `MainWindowView.swift:312` | `canCollapseSubview` 返回 `false` | 对 sidebarView 返回 `true` |
| `MainWindowView.swift:93` | `sidebarView.widthAnchor.constraint(equalToConstant: 240)` | 需改为可变宽度或使用 NSSplitView 的 position |
| `MainWindowView.swift:300-305` | splitView min/max 约束 | 折叠时 min 需为 0 |
| `AppDelegate.swift` | 无 Sidebar 状态读写 | 新增 UserDefaults 读写 |

## 6. 验收标准

| # | 条件 | 通过标准 |
|---|------|---------|
| 1 | 快捷键触发 | 按 `⌘+Shift+S` 后 Sidebar 折叠/展开，带动画 |
| 2 | 按钮触发 | 点击 toolbar 或 sidebar 按钮可切换 |
| 3 | 启动默认 | 首次启动 Sidebar 展开 |
| 4 | 状态恢复 | 关闭时折叠 → 重启后仍折叠 |
| 5 | 动画流畅 | 无卡顿、无约束冲突日志 |
| 6 | 功能不受影响 | 折叠状态下录制、播放功能正常 |

## 7. 参考

- macOS HIG: Sidebars https://developer.apple.com/design/human-interface-guidelines/sidebars
- Logic Pro X 的 Inspector 折叠行为
- NSSplitViewController 的 `toggleSidebar:` action
