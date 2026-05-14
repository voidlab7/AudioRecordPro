# Design Spec: 压缩 ControlPanel 高度释放 TracksView 空间

> 角色: 绘·设计师 | Task ID: task-0504-ui-control-panel-height
> 日期: 2026-05-04

---

## 1. 设计目标

在保持 Industrial Design "硬件感"视觉语言的前提下，将 ControlPanelView 从 150px 压缩至 120px，释放 30px 给 TracksView，使其从约 84px 增至约 114px，从而能够更完整地展示轨道信息和播放面板。

---

## 2. 方案评估

### 方案 A（推荐）：150px → 120px，保持按钮 64px 不变，缩减间距

| 维度 | 调整内容 | 影响 |
|------|---------|------|
| 按钮容器 | 84×84 → 74×74 | 外环和底座视觉略紧凑，但按钮本身不变 |
| Header 区域 | topAnchor 从 sm(8px) → xs(4px) | 减少 4px |
| 按钮居中偏移 | centerY offset 从 +10 → +4 | 减少 6px |
| Readout 底部 | bottomAnchor 从 -sm(-8px) → -xs(-4px) | 减少 4px |
| **总压缩** | | **≈30px** |

**优势**：
- 录制按钮 64×64 可点击区域不变（远超 44pt HIG 最低要求）
- 动画目标 48×48 仍在 74×74 容器内有充分空间
- 最小改动量，3-5 处 constant 即可完成

### 方案 B：150px → 100px，按钮缩到 52px

| 维度 | 风险 |
|------|------|
| 按钮尺寸 | 52×52 仍满足 44pt，但录制中 48→38 可能过小 |
| 视觉权重 | CTA 按钮失去视觉主导地位 |
| 动画空间 | 容器 68px，动画缩放余量仅 10px |

**结论**：风险偏高，不推荐。

### 方案 C：合并 Header+Readout 为一行，90px

| 维度 | 风险 |
|------|------|
| 信息密度 | 一行内容过多，可读性下降 |
| Industrial 风格 | 失去"分层面板"的硬件感 |
| 重构量 | 需重写 header 布局逻辑 |

**结论**：改动过大、风格不匹配，不推荐。

---

## 3. 推荐方案详细设计（方案 A）

### 3.1 按钮区域布局优化

```
当前容器 84×84:
┌──────────────────┐
│   ┌──────────┐   │  padding: 10px each side
│   │  64×64   │   │
│   │  Button  │   │
│   └──────────┘   │
└──────────────────┘

优化容器 74×74:
┌────────────────┐
│  ┌──────────┐  │  padding: 5px each side
│  │  64×64   │  │
│  │  Button  │  │
│  └──────────┘  │
└────────────────┘
```

- 容器从 84×84 缩到 74×74（减少 10px）
- 按钮 64×64 不变，上下左右留白从 10px → 5px
- 外环 (`outerRingLayer`) 线宽保持 8px，半径自动适应容器
- 底座 (`buttonBaseLayer`) 仍使用 `bounds.insetBy(dx:3, dy:3)` 自适应
- 录制态按钮缩至 48×48 时，容器内留白为 13px，充裕

### 3.2 间距压缩详情

| 元素 | 当前值 | 新值 | 差值 |
|------|--------|------|------|
| headerLabel.topAnchor | `IndustrialSpacing.sm` (8px) | `IndustrialSpacing.xs` (4px) | -4px |
| buttonContainer.centerYAnchor offset | +10 | +4 | -6px |
| buttonContainer size | 84×84 | 74×74 | -10px (高度方向) |
| readoutLabel.bottomAnchor | `-IndustrialSpacing.sm` (-8px) | `-IndustrialSpacing.xs` (-4px) | -4px |
| **总计垂直压缩** | | | **≈30px** |

> 注意：buttonContainer 的 centerY 从中心 +10 变为 +4，这使得按钮区域整体上移 6px，结合容器缩小 10px（上下各减 5px），实际上按钮区域上方空间减少约 11px，下方减少约 9px。

### 3.3 视觉对比

```
当前（150px）:
┌─────────────────────────────────────┐
│                                     │ ← 1px separator
│  TRANSPORT CONTROL    [STANDBY]     │ ← 8px top + 24px header
│                                     │
│                                     │ ← ~20px gap
│  00:12:34  [▶]   [● 64px]   [■]    │ ← 84px button zone
│                                     │
│                                     │
│  INPUT BUS: READY  FORMAT: WAV      │ ← 20px readout + 8px bottom
└─────────────────────────────────────┘

优化后（120px）:
┌─────────────────────────────────────┐
│                                     │ ← 1px separator
│  TRANSPORT CONTROL    [STANDBY]     │ ← 4px top + 24px header
│                                     │ ← ~10px gap (reduced)
│  00:12:34  [▶]   [● 64px]   [■]    │ ← 74px button zone
│                                     │
│  INPUT BUS: READY  FORMAT: WAV      │ ← 20px readout + 4px bottom
└─────────────────────────────────────┘
```

### 3.4 录制态对比

```
录制态（当前 150px → 按钮从 64 缩到 48）:
┌─────────────────────────────────────┐
│  TRANSPORT CONTROL    [RECORDING]   │
│                                     │
│  01:23:45  [▶]   [■48px]   [■]     │ ← 容器84px中48px按钮
│                                     │
│  INPUT BUS: LIVE   FORMAT: WAV      │
└─────────────────────────────────────┘

录制态（优化 120px → 按钮从 64 缩到 48）:
┌─────────────────────────────────────┐
│  TRANSPORT CONTROL    [RECORDING]   │
│  01:23:45  [▶]   [■48px]   [■]     │ ← 容器74px中48px按钮
│  INPUT BUS: LIVE   FORMAT: WAV      │
└─────────────────────────────────────┘
```

容器 74px 中放 48px 按钮，留白 13px/侧，视觉仍然宽松。

---

## 4. TracksView 收益分析

| 指标 | 当前 | 优化后 | 增益 |
|------|------|--------|------|
| ControlPanel 高度 | 150px | 120px | -30px |
| TracksView 可用高度 | ~84px | ~114px | +30px |
| 可显示内容 | 1行轨道标题 + 部分播放面板 | 1行轨道(120px) 或 紧凑轨道+播放面板 | 显著改善 |

TracksView 从 84px 增至 114px 后：
- 单轨道行高 120px 刚好完整显示（含 levelMeter）
- 若有播放面板(78px)，剩余空间可显示轨道标题区域

---

## 5. 触控/点击安全验证

| 元素 | 尺寸 | macOS HIG 最低(44pt) | 状态 |
|------|------|--------------------|------|
| Record Button (idle) | 64×64 | 44×44 | PASS |
| Record Button (recording) | 48×48 | 44×44 | PASS |
| Button Container (hit area) | 74×74 | 44×44 | PASS |
| Play Button | 32×32 | 44×44 | WARN* |
| Stop Button | 32×32 | 44×44 | WARN* |

> *Play/Stop 按钮 32×32 未满足 44pt，但这是既有设计，本次需求不涉及修改。后续可通过扩展 hit area 改善。

---

## 6. 设计决策记录

| # | 决策 | 理由 |
|---|------|------|
| D1 | 选择方案 A（120px） | 最小改动量 + 零功能回归风险 |
| D2 | 按钮保持 64×64 | CTA 视觉权重不可削弱 |
| D3 | 容器缩至 74×74 | 最小化外环/底座调整，自适应逻辑无需修改 |
| D4 | header top 从 8→4 | 1px separator 已提供视觉分隔，无需额外间距 |
| D5 | readout bottom 从 8→4 | 与 statusBar 的 gutter 间距(12px)已提供分离感 |
