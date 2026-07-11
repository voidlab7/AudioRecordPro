# REQ-2.0-06 多应用同时录音 — UI 设计文档

> 版本: V1.0 | 创建: 2026-05-30 | 状态: 待审核
> 设计师: 绘 | 评审人: PM_枢、CEO_锋

---

## 0. 设计决策汇总

| # | 决策点 | 决定 | 理由 |
|---|--------|------|------|
| 1 | Checkbox 样式 | 工业风格方形 Checkbox | 与 Industrial 设计系统一致，方形更紧凑，适合密集列表 |
| 2 | 多轨道波形颜色 | 每条轨道不同颜色（冷色系渐变） | 多轨核心价值是区分，颜色是最直观的区分方式 |
| 3 | 轨道选中态 | 左侧蓝色竖条 + 背景色变化 | 与现有 `IndustrialProcessRowView` 的 indicatorLayer 模式一致 |
| 4 | 应用退出"已断开"态 | 灰色覆盖 + 红色断连图标 + 虚线波形 | 红色=警告，虚线波形=不完整，信息密度最高 |
| 5 | 超过 5 个音源提示 | 内联 Toast 提示 | Modal 打断流程，Toast 轻量且不阻塞 |
| 6 | 空状态（0 个选中） | 保留现有箭头引导空状态 | 现有空状态已很好，保留并优化文案 |

---

## 1. 整体布局架构

```
┌──────────────────────────────────────────────────────┐
│  导航栏（文件名 + Transport Controls）                │
├────────────┬─────────────────────────────────────────┤
│            │  ┌──────────────────────────────────┐   │
│  侧边栏    │  │  Track 1: Chrome (蓝色波形)     │   │
│  (250px)  │  ├──────────────────────────────────┤   │
│            │  │  Track 2: Music (青色波形)      │   │
│  □ Chrome  │  ├──────────────────────────────────┤   │
│  □ Music   │  │  Track 3: QQ (紫色波形)        │   │
│  □ QQ      │  ├──────────────────────────────────┤   │
│            │  │  Track 4: Mic (绿色波形)        │   │
│  ☑ 麦克风  │  └──────────────────────────────────┘   │
│            │          [播放控制面板]                 │
└────────────┴─────────────────────────────────────────┘
```

### 空间分配规则
- **1 条轨道**: 高度铺满轨道区域（最小高度 120px）
- **2~5 条轨道**: 等分高度，每条轨道最小高度 80px
- **5 条轨道**: 每条轨道高度 = (轨道区高度 - 间距) / 5

---

## 2. 侧边栏改造设计

### 2.1 现有结构（改造前）

```
┌─────────────────────┐
│ 录制目标             │
│ 先选要录的声音...   │
│ ┌─────────────────┐ │
│ │ 🎤 同时录入麦克风 │ │  ← 无 Checkbox
│ └─────────────────┘ │
│ 选择应用声音         │
│ ┌─────────────────┐ │
│ │� Chrome   系统音│ │  ← 点击整行选中（单选）
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │� Music    系统音│ │
│ └─────────────────┘ │
└─────────────────────┘
```

### 2.2 改造后结构（多选 Checkbox）

```
┌─────────────────────┐
│ 录制目标             │
│ 勾选多个应用同时录制 │  ← 文案更新
│ ┌─────────────────┐ │
│ │☑ 🎤 麦克风输入  │ │  ← 独立 Checkbox
│ └─────────────────┘ │
│ 选择应用声音         │
│ ┌─────────────────┐ │
│ │☐ 📱 Chrome      │ │  ← 每行前面加 Checkbox
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │☑ 📱 Music       │ │  ← 选中态：蓝色竖条 + Checkbox 勾选
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │☐ 📱 QQ          │ │
│ └─────────────────┘ │
│                     │
│ 已选 2/5 个音源    │  ← 底部状态栏
└─────────────────────┘
```

### 2.3 Industrial Checkbox 规范

沿用 `IndustrialColors` 设计令牌，自定义方形 Checkbox（不使用系统 `NSButton` checkbox 样式）：

```swift
// Checkbox 视觉规范
let checkboxSize: CGFloat = 16
let checkboxCornerRadius: CGFloat = 3  // 方形微圆角

// 未选中态
- fillColor: IndustrialColors.surfaceContainerLow
- borderColor: IndustrialColors.outlineVariant
- borderWidth: 1px

// 选中态
- fillColor: IndustrialColors.primaryContainer
- borderColor: IndustrialColors.primaryContainer
- checkmark: 白色 ✓（系统符号 "checkmark"）

// Hover 态
- fillColor: IndustrialColors.surfaceContainerHigh
- borderColor: IndustrialColors.primaryContainer (半透明)
```

### 2.4 交互规则

| 操作 | 行为 |
|------|------|
| 点击 Checkbox | 切换该条目选中状态，不触发其他条目 |
| 点击行空白区域 | 等同于点击该行 Checkbox |
| 选中第 5 个后继续勾选第 6 个 | 拒绝勾选，触发 Toast 提示"最多同时录制 5 个音源" |
| 录制中点击 Checkbox | 无响应（UI 锁定，Checkbox 变灰） |
| Cmd+Click | 切换该条目（多选修饰键，可选实现 V2.1） |

### 2.5 底部状态栏

在侧边栏底部增加固定状态栏（高度 32px）：

```
┌─────────────────────┐
│ 已选 2/5 个音源     │  ← 实时计数
│ [开始录制] 按钮      │  ← 或显示"录制中..."
└─────────────────────┘
```

- 字体: `IndustrialTypography.small` (10px Mono)
- 颜色: `IndustrialColors.textTertiary`
- 背景: `IndustrialColors.surfaceContainerLow`

---

## 3. 多轨道显示设计

### 3.1 轨道卡片结构

每条轨道是一个 `NSView`，结构如下：

```
┌────────────────────────────────────────┐
│ ┌──┐ Track 1: Google Chrome          │  ← 头部区（32px）
│ │图标│ system-audio • 录制中 ●        │
│ └──┘                                     │
├────────────────────────────────────────┤
│                                        │
│  ━━━━━━╸╸╸╸━━━━━━━━╸╸━━━━━━━━━  │  ← 波形区（弹性高度）
│   波形滚动方向 →                     │
│                                        │
├────────────────────────────────────────┤
│  00:00:00  •  DB: -12 │ Mute │ Solo │  ← 底部状态栏（24px）
└────────────────────────────────────────┘
```

### 3.2 轨道颜色方案（冷色系渐变）

| 轨道序号 | 主题色 | 波形颜色 | 波形渐变 |
|---------|--------|---------|---------|
| 1 | 蓝 | `#5B9BD5` | 蓝→浅蓝 |
| 2 | 青 | `#2EC4B6` | 青→浅青 |
| 3 | 紫 | `#9B5DE5` | 紫→浅紫 |
| 4 | 绿 | `#4CAF50` | 绿→浅绿 |
| 5 | 橙 | `#FF9500` | 橙→浅橙 |

颜色通过 `trackColorIndex` 循环分配（与选中顺序无关，按轨道创建顺序）。

### 3.3 轨道高度等分算法

```swift
/// 计算每条轨道的高度
/// - Parameter trackCount: 当前轨道数量 (1~5)
/// - Returns: 每条轨道的高度
func calculateTrackHeight(trackCount: Int) -> CGFloat {
    let totalHeight = tracksStack.bounds.height
    let spacing = IndustrialSpacing.sm * CGFloat(trackCount - 1)
    let availableHeight = totalHeight - spacing
    return max(availableHeight / CGFloat(trackCount), 80)  // 最小 80px
}
```

### 3.4 轨道选中态

点击轨道后的视觉变化：

```
未选中:
┌──────────────────────────────┐
│ 背景: surfaceContainerLow     │
│ 左边框: 无                   │
└──────────────────────────────┘

选中:
┌║─────────────────────────────┐
│║ 背景: surfaceContainerHigh   │  ← 左侧 3px 蓝色竖条 + 背景高亮
│║ 左边框: 3px primary color   │
└║─────────────────────────────┘
```

与现有 `IndustrialProcessRowView` 的 `indicatorLayer` 保持一致实现。

### 3.5 录制中锁定状态

录制开始后，侧边栏 Checkbox 变为**不可交互**状态：

```
┌─────────────────────┐
│ 录制目标 (录制中)    │  ← 标题变化，提示锁定
│ ┌─────────────────┐ │
│ │☑ 🎤 麦克风输入  │ │  ← Checkbox 灰色，不可点击
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │☑ 📱 Chrome      │ │  ← 选中态保留，但锁定
│ └─────────────────┘ │
│         录制中，不可修改 │  ← 底部提示
└─────────────────────┘
```

视觉信号：
- Checkbox `alphaValue = 0.4`（半透明）
- 整行 `alphaValue = 0.7`（略微变暗）
- 鼠标悬停显示 `NSCursor.operationNotAllowed`（禁止图标）

---

## 4. 断开状态设计（应用退出）

当录制中某个应用退出时，对应轨道显示"已断开"状态：

```
┌────────────────────────────────────────┐
│ ┌──┐ Track 2: Music (已断开)   ⚠️  │  ← 标题变灰 + 警告图标
│ │图标│ system-audio • 已断开     X  │  ← 状态改为"已断开"
│ └──┘                                     │
├──────── ━━━━━━━━━━━━━━━━━━━━━━━━━ |  ← 波形变为虚线样式
│                                        │
│  ┅───╍╍╍──────╍╍───────╍╍─────  │  ← 虚线波形（已录部分）
│   (波形停止滚动，定格在断开时刻)    │
│                                        │
├────────────────────────────────────────┤
│  00:00:00  •  DB: -- │ Mute │ Solo  │  ← 电平显示 "--"
└────────────────────────────────────────┘
```

### 断开态视觉规范

| 元素 | 正常态 | 断开态 |
|------|--------|--------|
| 背景色 | `surfaceContainerLow` | `surfaceContainerLow` + 50% 透明度 |
| 标题颜色 | `onSurface` | `textTertiary` |
| 状态指示 | `● 录制中` (绿色) | `⚠ 已断开` (红色) |
| 波形样式 | 实线滚动波形 | 虚线静态波形（定格） |
| 波形透明度 | 100% | 40% |
| 右侧图标 | 无 | `NSImage(systemSymbolName: "xmark.circle.fill")` 红色 |

---

## 5. 超过 5 个音源提示设计

### 5.1 Toast 提示样式

在侧边栏顶部显示内联 Toast（不阻断流程）：

```
┌──────────────────────────────────┐
│  ⚠️ 最多同时录制 5 个音源        │  ← Toast 横幅
│  ─────────────────────────────  │
│ 录制目标                          │
│ ┌─────────────────────────────┐ │
│ │☑ 🎤 麦克风                   │ │
│ └─────────────────────────────┘ │
│ ...                             │
└──────────────────────────────────┘
```

### 5.2 Toast 视觉规范

```swift
// Toast 容器
- backgroundColor: IndustrialColors.surfaceContainerHigh
- borderColor: IndustrialColors.primaryContainer
- borderWidth: 1px
- cornerRadius: IndustrialCornerRadius.xs
- height: 36px
- padding: 8px 12px

// Toast 文字
- font: IndustrialTypography.small (10px Mono)
- color: IndustrialColors.onSurfaceVariant
- icon: "exclamationmark.triangle" (systemSymbolName)
- icon color: IndustrialColors.primaryContainer
```

### 5.3 Toast 交互

- **触发**: 用户尝试勾选第 6 个音源时
- **显示时长**: 3 秒后自动消失（带 fade-out 动画）
- **手动关闭**: 点击 Toast 右侧的 `×` 按钮立即关闭
- **不阻塞**: 用户可继续操作其他 UI 元素

---

## 6. 空状态设计

### 6.1 0 个应用选中（初始状态）

沿用现有空状态设计，优化文案：

```
┌────────────────────────────────────────┐
│                                      │
│               ◁                      │  ← 箭头图标（指向左侧边栏）
│          请选择音频源                   │  ← 主文案
│       从左侧勾选应用或系统声音            │  ← 辅助提示（更新）
│                                      │
└────────────────────────────────────────┘
```

### 6.2 空状态视觉规范

| 元素 | 规范 |
|------|------|
| 箭头图标 | `IndustrialColors.onSurfaceVariant` @ 50% 透明度，24px |
| 主文案 | `IndustrialTypography.body` (12px Bold)，`onSurfaceVariant` @ 60% |
| 辅助提示 | `IndustrialTypography.small` (10px Mono)，`textTertiary` @ 50% |
| 背景 | 透明（显示 `surfaceContainer.cgColor` 网格纹理） |

---

## 7. 播放控制面板（多轨适配）

### 7.1 现有结构

播放控制面板在窗口底部，现有设计只支持单文件播放。

### 7.2 多轨录制完成后的播放态

录制完成后，播放控制面板显示**当前选中轨道**的文件信息：

```
┌────────────────────────────────────────────────────┐
│  🎵 Track 1 - Chrome_20260530_120000.m4a        │  ← 文件名（截断）
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 45%  │  ← 进度条
│  [播放/暂停] [停止]          00:32 / 01:15      │  ← 控制按钮 + 时间
└────────────────────────────────────────────────────┘
```

- 切换选中轨道时，播放面板内容自动更新
- 如果选中的轨道是"已断开"状态，播放按钮置灰（无可播放文件）

---

## 8. 动画规范

### 8.1 轨道添加动画

用户勾选新应用 → 轨道区新增一条轨道：

```swift
// 新轨道淡入 + 高度动画
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.25
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    newTrackView.animator().alphaValue = 1.0
    // NSStackView 自动处理高度动画
}
```

### 8.2 轨道移除动画

用户取消勾选应用 → 对应轨道移除：

```swift
NSAnimationContext.runAnimationGroup({ context in
    context.duration = 0.2
    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
    trackView.animator().alphaValue = 0
}, completionHandler: {
    tracksStack.removeArrangedSubview(trackView)
    trackView.removeFromSuperview()
})
```

### 8.3 断开状态过渡动画

应用退出 → 轨道从正常态过渡到断开态：

```swift
// 波形从实线变为虚线（CAShapeLayer.lineDashPattern）
// 背景色渐变到断开态颜色（0.3s）
CATransaction.begin()
CATransaction.setAnimationDuration(0.3)
trackLayer.backgroundColor = IndustrialColors.surfaceContainerLow.withAlphaComponent(0.5).cgColor
waveformLayer.lineDashPattern = [4, 2]  // 虚线
CATransaction.commit()
```

---

## 9. 组件改造清单

| 组件 | 文件 | 改造内容 | 优先级 |
|------|------|---------|--------|
| `IndustrialCheckboxView` | 新建 | 自定义方形 Checkbox 组件 | P0 |
| `SidebarView` | `SidebarView.swift` | 进程行添加 Checkbox，支持多选 | P0 |
| `IndustrialProcessRowView` | `SidebarView.swift` | 添加 Checkbox 子视图，onClick 改为 toggle checkbox | P0 |
| `IndustrialMicrophoneRowView` | `SidebarView.swift` | 添加 Checkbox（独立逻辑） | P0 |
| `TracksView` | `TracksView.swift` | 支持 N 条轨道等分显示 | P0 |
| `TrackRowView` | 新建 | 单条轨道卡片视图 | P0 |
| `TrackWaveformView` | 新建 | 轨道波形绘制（支持虚线样式） | P0 |
| `ToastView` | 新建 | 内联提示 Toast 组件 | P1 |
| `SidebarView` 底部状态栏 | `SidebarView.swift` | 添加"已选 N/5"状态栏 | P1 |

---

## 10. 设计验收清单

- [ ] Checkbox 样式符合 Industrial 设计系统
- [ ] 多选逻辑正确（1~5 个，第 6 个拒绝）
- [ ] 轨道等分高度算法正确（1 条铺满，5 条等分）
- [ ] 轨道颜色区分清晰（5 种颜色互不混淆）
- [ ] 选中态视觉信号明确（蓝色竖条 + 背景高亮）
- [ ] 录制中锁定状态清晰（半透明 + 禁止光标）
- [ ] 断开态视觉信号明确（红色 + 虚线波形）
- [ ] Toast 提示不阻断流程，3 秒自动消失
- [ ] 所有动画流畅（≥ 30fps）
- [ ] 空状态引导清晰

---

## 11. 交接块

## 交接块
- **来源**: 设计（绘）
- **目标**: 矩（架构师）
- **产出路径**: `ai-workspace/task-0527-req-2-0-06-多应用同时录音/artifacts/03-design/`
- **摘要**: 已完成多应用同时录音 UI 设计，含 6 个决策点确认、组件改造清单、动画规范
- **建议下游关注**:
  1. `IndustrialCheckboxView` 需要新建，建议矩在技术方案中确认组件架构
  2. 多轨道等分高度需要在 `TracksView` 中用 `NSStackView` 分布实现
  3. 断开态的虚线波形需要在 `TrackWaveformView` 中支持 `lineDashPattern`
  4. 颜色方案已确定，下游直接按表格取值即可
