# 设计规范：Sidebar 折叠/展开能力

> 角色: 绘·设计师 | Task: task-0504-ui-sidebar-collapse
> 日期: 2026-05-05 | 状态: Review Complete

---

## 1. 设计目标

在保持 Industrial Design 风格一致性的前提下，为 Sidebar 添加可折叠/展开能力，让用户按需获得更多内容区空间。

---

## 2. 折叠按钮设计

### 2.1 位置方案：**Toolbar 左侧（推荐）**

```
┌──────────────────────────────────────────────────────────┐
│ [◀] 音频录制工具                          🔴 🟡 🟢      │  ← Toolbar
├──────────────┬───────────────────────────────────────────┤
│  Sidebar     │  Content                                  │
```

**理由**：
- macOS 标准模式，用户已有认知（Finder、Xcode、Mail 都在 Toolbar 有 sidebar toggle）
- 使用 `NSToolbarItem` 的 `toggleSidebar:` action，系统原生支持
- 不侵占 Sidebar 内部空间

### 2.2 图标设计

| 状态 | 图标 | SF Symbol |
|------|------|-----------|
| Sidebar 展开时 | ◀│ | `sidebar.leading` |
| Sidebar 折叠时 | │▶ | `sidebar.leading` (自动翻转) |

- 图标尺寸：16×16pt
- 图标颜色：`IndustrialColors.onSurfaceVariant`（#bbc9cd）
- Hover 颜色：`IndustrialColors.primary`（#8aebff 青色）

### 2.3 备选方案（不推荐）

- ❌ Sidebar 顶部内置按钮 — 折叠后按钮也消失，无法展开
- ❌ 浮动按钮 — 遮挡内容，不符合 Industrial Design 简洁原则

---

## 3. 折叠/展开动画

### 3.1 动画参数

| 属性 | 值 |
|------|---|
| 时长 | 250ms |
| 曲线 | `ease-in-out` (NSAnimation.Curve.easeInOut) |
| 宽度变化 | 240px → 0px（折叠）/ 0px → 240px（展开） |
| 内容区 | 同步扩展/收缩，跟随 SplitView 自然行为 |

### 3.2 折叠过程视觉行为

```
帧 0 (0ms):     [Sidebar 240px] | [Content 560px]
帧 1 (60ms):    [Sidebar 180px] | [Content 620px]   ← Sidebar 内容开始 clip
帧 2 (125ms):   [Sidebar 100px] | [Content 700px]   ← Sidebar 文字不可见
帧 3 (200ms):   [Sidebar 30px]  | [Content 770px]   ← 仅分隔线可见
帧 4 (250ms):   [Content 800px]                      ← 完全折叠
```

### 3.3 关键视觉细节

- **Clip 行为**：折叠过程中 Sidebar 内容通过 `clipsToBounds` 裁剪，不溢出
- **分隔线**：折叠完成后分隔线隐藏（非 0px divider 漏出）
- **内容区过渡**：波形和轨道区域平滑扩展，无跳动
- **无 alpha 动画**：不使用渐隐效果（Industrial Design 偏好硬边过渡）

### 3.4 展开过程

- 与折叠完全反向
- 展开完成后 Sidebar 恢复所有交互能力
- 展开动画完成前不响应 Sidebar 内部点击

---

## 4. 折叠状态的视觉表现

### 4.1 完全折叠时

```
┌──────────────────────────────────────────────────────────┐
│ [▶│] 音频录制工具                         🔴 🟡 🟢      │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  WaveformView (占满宽度)                                 │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  TracksView                                              │
├──────────────────────────────────────────────────────────┤
│  ControlPanel                                            │
├──────────────────────────────────────────────────────────┤
│  StatusBar                                               │
└──────────────────────────────────────────────────────────┘
```

### 4.2 无残留元素

- 折叠后不显示窄条/mini sidebar
- 完全让出空间给内容区
- 仅 Toolbar 按钮提示可恢复

---

## 5. 快捷键视觉反馈

- 按下 `⌘+Shift+S` 时：Toolbar 按钮短暂高亮（100ms 青色闪烁）
- 菜单栏显示快捷键标注：`View → Toggle Sidebar  ⇧⌘S`

---

## 6. 设计 Token 补充

建议在 `IndustrialDesignTokens.swift` 中补充：

```swift
struct IndustrialAnimation {
    static let sidebarToggle: TimeInterval = 0.25  // 250ms
    static let standard: TimeInterval = 0.15       // 150ms (已有)
    static let slow: TimeInterval = 0.35           // 350ms
}
```

---

## 7. 可访问性

- Toolbar 按钮需设置 `accessibilityLabel = "Toggle Sidebar"`
- VoiceOver 朗读："Sidebar, collapsed" / "Sidebar, expanded"
- 动画应遵守系统 `reduceMotion` 偏好（如开启则直接切换，无动画）

---

## 8. 设计审查结论

| 项 | 决策 |
|----|------|
| 按钮位置 | ✅ Toolbar 左侧 |
| 图标 | ✅ SF Symbol `sidebar.leading` 16pt |
| 动画时长 | ✅ 250ms ease-in-out |
| 折叠方式 | ✅ 宽度归零，clip 裁剪 |
| 残留元素 | ✅ 无（完全折叠） |
| 状态持久化 | ✅ 见架构方案 |
