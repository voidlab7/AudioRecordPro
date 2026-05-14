# 架构评审：优化默认窗口尺寸适配 Sidebar 布局

> 角色: 矩·架构师 | Task: task-0504-ui-window-size
> 日期: 2026-05-05 | 状态: Review Complete

---

## 1. 修改清单

### 1.1 窗口尺寸修改

**文件**: `AppDelegate.swift`

```swift
// 第 122 行：初始尺寸
// Before:
let windowSize = NSMakeRect(0, 0, 800, 500)
// After:
let windowSize = NSMakeRect(0, 0, 960, 600)

// 第 158 行：强制设置
// Before:
let newFrame = NSMakeRect(0, 0, 800, 500)
// After:
let newFrame = NSMakeRect(0, 0, 960, 600)

// 第 171 行：最小尺寸（保持不变）
window.minSize = NSSize(width: 800, height: 500)
```

### 1.2 Sidebar 宽度修改

**文件**: `IndustrialDesignTokens.swift`

```swift
// 第 287 行
// Before:
static let sidebarWidth: CGFloat = 240
// After:
static let sidebarWidth: CGFloat = 260
```

**文件**: `MainWindowView.swift`

```swift
// 第 93 行：宽度约束
sidebarView.widthAnchor.constraint(equalToConstant: IndustrialSpacing.sidebarWidth)
// → 无需改代码，因为引用的是 token，修改 token 即可

// 第 300-305 行：min/max 约束
func splitView(_ splitView: NSSplitView,
               constrainMinCoordinate proposedMinimumPosition: CGFloat,
               ofSubviewAt dividerIndex: Int) -> CGFloat {
    return 220 // Before: 200, After: 220（比 260 小一点，允许微调）
}

func splitView(_ splitView: NSSplitView,
               constrainMaxCoordinate proposedMaximumPosition: CGFloat,
               ofSubviewAt dividerIndex: Int) -> CGFloat {
    return 400 // 保持不变
}
```

### 1.3 WaveformView 比例修改

**文件**: `MainWindowView.swift`

```swift
// 第 100 行
// Before:
waveformView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.42)
// After:
waveformView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.38)
```

### 1.4 ControlPanel 高度修改（可选，依赖另一任务）

**文件**: `MainWindowView.swift`

```swift
// 第 118 行
// Before:
controlPanelView.heightAnchor.constraint(equalToConstant: 150)
// After (如果 control-panel-height 任务已实施):
controlPanelView.heightAnchor.constraint(equalToConstant: 120)
```

---

## 2. 约束链分析

### 2.1 垂直约束链（内容区）

```
contentView.top
  │
  ├─ md (间距)
  │
  ├─ waveformView.top
  │    height = contentView.height × 0.38
  │    minHeight = 200
  ├─ waveformView.bottom
  │
  ├─ gutter (间距)
  │
  ├─ tracksView.top
  │    height = 弹性 (bottom 锚定到 controlPanel.top)
  ├─ tracksView.bottom
  │
  ├─ controlPanelView.top
  │    height = 120 (固定)
  ├─ controlPanelView.bottom
  │
  ├─ statusBarView.top
  │    height = 28 (固定)
  ├─ statusBarView.bottom
  │
contentView.bottom
```

### 2.2 潜在约束冲突

| 场景 | 窗口高度 | waveform(38%) | control(120) | status(28) | 间距(~16) | tracks(弹性) |
|------|---------|---------------|-------------|-----------|----------|-------------|
| 默认 960×600 | 600 | 228 | 120 | 28 | 16 | **208** ✅ |
| 最小 800×500 | 500 | 190 | 120 | 28 | 16 | **146** ✅ |
| 极端缩小 | 450 | 171 | 120 | 28 | 16 | **115** ✅ |

**注意**：waveform minHeight=200 在 500px 窗口时（38%=190）可能冲突。

**解决方案**：
```swift
// 将 minHeight 优先级降低
let minHeightConstraint = waveformView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
minHeightConstraint.priority = .defaultHigh  // 750, 低于 required(1000)
```

或将 minHeight 从 200 降为 180。

---

## 3. 响应式布局方案

### 3.1 Sidebar 宽度自适应（可选增强）

```swift
// 窗口 resize 时调整 Sidebar 宽度
override func viewDidLayout() {
    super.viewDidLayout()
    let windowWidth = bounds.width
    
    if windowWidth < 900 {
        // 窄窗口：Sidebar 缩到 240
        sidebarWidthConstraint.constant = 240
    } else {
        // 正常：Sidebar 260
        sidebarWidthConstraint.constant = 260
    }
}
```

### 3.2 实现建议

- Phase 1（本次）：只改默认尺寸和比例，不做响应式
- Phase 2（后续）：配合 sidebar-collapse 实现响应式

---

## 4. 风险评估

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| waveform minHeight 约束冲突 | 中 | 控制台警告 | 降低 minHeight 到 180 或降优先级 |
| 13寸屏幕窗口偏大 | 低 | 用户手动缩小 | minSize 保持 800×500 |
| Sidebar 260px 文字仍截断 | 极低 | 美观 | 已验证多数进程名 ≤ 25 字符 |
| 已有用户窗口位置记忆 | 无 | 无 | 已禁用 setFrameAutosaveName |

---

## 5. 测试要点

| # | 测试项 | 步骤 |
|---|--------|------|
| 1 | 默认尺寸 | 全新启动，验证窗口 960×600 居中 |
| 2 | 最小缩放 | 拖到最小，验证 800×500 无约束报错 |
| 3 | 13寸适配 | 在 1440×900 屏幕验证不超出 |
| 4 | Sidebar 宽度 | 验证进程名显示（Chrome、Spotify 等） |
| 5 | 波形区域 | 验证波形绘制在 228px 高度正常 |
| 6 | TracksView | 验证可显示 2+ 轨道行 |
| 7 | 构建 | `build-app.sh` 无错误 |

---

## 6. 架构审查结论

| 项 | 决策 |
|----|------|
| 改动范围 | ✅ 4 个文件，≤ 10 行代码 |
| 约束风险 | ✅ 低（已分析冲突点） |
| 向后兼容 | ✅ minSize 不变 |
| 实施依赖 | ⚠️ 可选依赖 control-panel-height 任务 |
| 预估工时 | ✅ 30 分钟改动 + 30 分钟测试 |
| 建议顺序 | 先改尺寸+Sidebar宽度 → 测试 → 再改比例 |
