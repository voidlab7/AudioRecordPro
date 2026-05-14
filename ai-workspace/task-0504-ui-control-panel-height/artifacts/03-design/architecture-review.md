# Architecture Review: 压缩 ControlPanel 高度

> 角色: 矩·架构师 | Task ID: task-0504-ui-control-panel-height
> 日期: 2026-05-04

---

## 1. 约束修改点清单

基于设计师方案 A（150px → 120px），需修改以下约束常量：

| # | 文件 | 行号 | 当前代码 | 修改为 | 说明 |
|---|------|------|---------|--------|------|
| C1 | `MainWindowView.swift` | L118 | `heightAnchor.constraint(equalToConstant: 150)` | `equalToConstant: 120` | 主高度约束 |
| C2 | `ControlPanelView.swift` | L212 | `widthAnchor.constraint(equalToConstant: 84)` | `equalToConstant: 74` | 容器宽度 |
| C3 | `ControlPanelView.swift` | L213 | `heightAnchor.constraint(equalToConstant: 84)` | `equalToConstant: 74` | 容器高度 |
| C4 | `ControlPanelView.swift` | L222 | `topAnchor.constraint(equalTo: topAnchor, constant: IndustrialSpacing.sm)` | `constant: IndustrialSpacing.xs` | Header top: 8→4 |
| C5 | `ControlPanelView.swift` | L230 | `centerYAnchor.constraint(equalTo: centerYAnchor, constant: 10)` | `constant: 4` | 按钮区域居中偏移 |
| C6 | `ControlPanelView.swift` | L251 | `bottomAnchor.constraint(equalTo: bottomAnchor, constant: -IndustrialSpacing.sm)` | `constant: -IndustrialSpacing.xs` | Readout bottom: -8→-4 |

**总修改量**: 6 处约束常量，涉及 2 个文件，无逻辑变更。

---

## 2. 对按钮动画 (64→48) 的影响评估

### 2.1 动画机制分析

```swift
// ControlPanelView.swift - setRecordButtonSize(_:animated:)
private func setRecordButtonSize(_ size: CGFloat, animated: Bool) {
    guard let w = buttonWidthConstraint, let h = buttonHeightConstraint else { return }
    w.constant = size   // 修改宽度约束
    h.constant = size   // 修改高度约束
    if animated {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            layoutSubtreeIfNeeded()
            layoutStopSquareLayer()
        }
    }
}
```

### 2.2 容器变化对动画的影响

| 场景 | 当前 (容器84px) | 优化后 (容器74px) | 影响 |
|------|----------------|------------------|------|
| idle: 按钮64px | 余量: (84-64)/2 = 10px | 余量: (74-64)/2 = 5px | 外环更贴合，视觉更紧凑 |
| recording: 按钮48px | 余量: (84-48)/2 = 18px | 余量: (74-48)/2 = 13px | 依然充足 |
| 动画路径 | 缩小16px在84px容器内 | 缩小16px在74px容器内 | **无影响**，按钮居中缩放 |

### 2.3 外环路径重算

```swift
// layout() 中外环路径计算：
let radius = min(bounds.width, bounds.height) / 2 - outerRingLayer.lineWidth / 2 - 1
// 当前: (84/2) - 4 - 1 = 37px radius
// 优化后: (74/2) - 4 - 1 = 32px radius
```

外环半径从 37px → 32px，恰好等于按钮半径 32px（idle 态 normalButtonSize/2）。外环描边 lineWidth=8，实际绘制范围为 radius±4（即 28~36px），而按钮边缘在 32px。这意味着：
- 外环的内侧边界(28px) < 按钮边缘(32px)
- 外环的外侧边界(36px) > 按钮边缘(32px)
- **视觉效果**: 外环恰好"环绕"按钮边缘，形成金属环效果 — 这是 Industrial Design 的理想表现

### 2.4 结论

- **动画机制完全兼容**：`setRecordButtonSize` 仅修改按钮自身约束，不涉及容器约束
- **外环/底座自动适应**：`layout()` 方法基于 `buttonContainer.bounds` 重新计算，容器变化后自动适配
- **innerSquareLayer 位置**：`layoutStopSquareLayer()` 基于 `recordButton.bounds` 计算，与容器尺寸无关
- **cornerRadius**: idle 态 32px、recording 态 24px 不受影响

---

## 3. TracksView 释放空间计算

### 3.1 当前窗口垂直空间分配

```
contentView.top
  ↓ IndustrialSpacing.md (16px)
waveformView [42% height, min 200px → 实际 ~210px @500px窗口]
  ↓ IndustrialSpacing.gutter (12px)
tracksView [flexible — 填充剩余]
  ↓ IndustrialSpacing.gutter (12px)
controlPanelView [150px fixed]
  ↓ 0px (直接邻接 statusBarView.top)
statusBarView [28px fixed]
contentView.bottom
```

### 3.2 当前 TracksView 高度计算

```
窗口 500px:
固定占用 = 16 + 210 + 12 + 12 + 150 + 28 = 428px
TracksView = 500 - 428 = 72px
```

若 waveformView 取 min(200px):
```
固定占用 = 16 + 200 + 12 + 12 + 150 + 28 = 418px
TracksView = 500 - 418 = 82px
```

### 3.3 优化后空间分配

```
controlPanel: 150 → 120 (释放 30px)
固定占用 = 16 + 200 + 12 + 12 + 120 + 28 = 388px
TracksView = 500 - 388 = 112px (+30px)
```

### 3.4 多窗口尺寸对比

| 窗口高度 | waveform (42%) | 当前 TracksView | 优化后 TracksView | 增益 |
|----------|---------------|----------------|------------------|------|
| 500px | 200px (min) | 82px | 112px | +30px |
| 600px | 252px | 130px | 160px | +30px |
| 700px | 294px | 178px | 208px | +30px |

### 3.5 TracksView 内容适配分析

当前内部布局元素：
- `tracksStack.topAnchor`: +24px
- 单个 TrackRow 固定高度: 120px
- `playbackPanel` 固定高度: 78px + bottom padding 16px = 94px

| 场景 | 优化后可用(112px) | 能否显示 | 改善描述 |
|------|-------------------|---------|---------|
| 仅轨道信息 | 24(top) + 120(track) = 144px 需求 | 不完整但可显示 ~88px 内容 | 当前仅显示 ~58px |
| 仅播放面板 | 24(top) + 94(panel) = 118px 需求 | 几乎完整 | 当前被截断 |
| 轨道+播放 | 需求 > 200px | 需滚动 | 改善有限，但总体体验好于当前 |

**核心收益**: 释放 30px 后，播放面板可以基本完整展示，这是用户最常用的交互区域。

---

## 4. 风险评估

| # | 风险 | 概率 | 影响 | 缓解措施 |
|---|------|------|------|---------|
| R1 | 外环与按钮边缘重叠 | 确定 | 低（正面视觉效果） | 半径32px恰好匹配按钮，形成金属环 |
| R2 | header 与按钮区域视觉拥挤 | 低 | 中 | header→button 间距仍有 ~18px |
| R3 | readout 被截断或不可见 | 极低 | 低 | readout 仅垂直 padding 减少 4px |
| R4 | Auto Layout 约束冲突 | 极低 | 中 | 纯常量修改，无优先级冲突 |
| R5 | 窗口极端缩小时 TracksView 负高度 | 低 | 中 | 应确认 Window minSize ≥ 400px |
| R6 | Glow 效果被容器裁剪 | 无 | — | `masksToBounds = false` 已设置 |

### 4.1 风险 R5 深入分析

TracksView 变为 0 或负值的窗口临界高度:
```
临界高度 = 16 + 200(min waveform) + 12 + 0(tracksView=0) + 12 + 120 + 28 = 388px
```
只要窗口 minHeight ≥ 400px，TracksView 至少有 12px。建议后续确认 WindowController 的 `window?.minSize`。

---

## 5. 测试方案

### 5.1 编译验证

```bash
cd /Users/voidzhang/Documents/workspace/audio_record_mac && ./build-app.sh
```
- 期望: 编译成功，控制台无 Auto Layout 约束冲突警告

### 5.2 功能测试矩阵

| # | 操作 | 预期结果 | 验证方法 |
|---|------|---------|---------|
| T1 | 启动应用 | ControlPanel 120px，UI 正常 | View Hierarchy |
| T2 | 点击录制 | 按钮 64→48 平滑缩小 | 视觉观察 |
| T3 | 停止录制 | 按钮 48→64 平滑恢复 | 视觉观察 |
| T4 | 播放文件 | PlaybackPanel 在 TracksView 中可见 | 视觉观察 |
| T5 | 缩小窗口 | 无约束冲突日志 | Console |
| T6 | 放大窗口 | TracksView 正确扩展 | View Hierarchy |

### 5.3 视觉回归清单

- [ ] 录制按钮青色发光 + 深红色正常
- [ ] 外环灰色描边正常环绕按钮
- [ ] 底座阴影正常渲染
- [ ] innerSquare（录制中白色方块）居中正确
- [ ] Play/Stop 按钮垂直居中于容器
- [ ] 计时器与按钮 centerY 对齐
- [ ] Header + StatusBadge 水平排列正常
- [ ] Readout 底部完整可见

---

## 6. 实施清单（供开发阶段使用）

```
文件: MainWindowView.swift
  L118: 150 → 120

文件: ControlPanelView.swift
  L212: 84 → 74 (containerW)
  L213: 84 → 74 (containerH)
  L222: IndustrialSpacing.sm → IndustrialSpacing.xs (headerLabel top)
  L230: 10 → 4 (buttonContainer centerY offset)
  L251: -IndustrialSpacing.sm → -IndustrialSpacing.xs (readoutLabel bottom)
```

**回滚方案**: 纯数值还原，无代码逻辑回滚需求。
