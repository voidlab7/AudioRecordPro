# 设计规格：SplitView 分隔线视觉反馈

> 角色: 绘·设计师 | Task: task-0504-ui-splitview-divider
> 日期: 2026-05-04

---

## 1. 设计概述

为 NSSplitView 分隔线添加三态视觉反馈（默认 → Hover → 拖动），遵循 Industrial Design 设计语言，提供微妙但明确的交互提示。

## 2. 状态定义

### 2.1 默认状态 (Idle)

| 属性 | 值 |
|------|-----|
| 宽度 | 1px |
| 颜色 | `IndustrialColors.outlineVariant` (#3c494c) |
| 不透明度 | 1.0 |
| 拖动指示器 | 隐藏 |
| 光标 | 系统默认 (arrow) |

**设计意图**：默认状态下分隔线不应抢夺注意力，仅作为 Sidebar 与内容区的边界提示。1px outlineVariant 色在深色背景上提供恰到好处的分隔感。

### 2.2 Hover 状态 (Hovered)

| 属性 | 值 |
|------|-----|
| 宽度 | 2px |
| 颜色 | `IndustrialColors.primaryContainer` (#22d3ee) |
| 不透明度 | 1.0 |
| 过渡动画 | 150ms ease-in-out (fade) |
| 拖动指示器 | 显示（可选） |
| 光标 | `resizeLeftRight` (系统自动) |
| 热区 | 分隔线中心 ±4px (总计 9px 交互区域) |

**设计意图**：青色高亮是 Industrial Design 的核心交互色，与按钮 hover、电平表颜色一致。2px 宽度既明确又不夸张。150ms 过渡让变化感觉自然而非突兀。

### 2.3 拖动状态 (Dragging)

| 属性 | 值 |
|------|-----|
| 宽度 | 2px |
| 颜色 | `IndustrialColors.primaryContainer` (#22d3ee) |
| 不透明度 | 1.0 |
| 拖动指示器 | 保持显示 |
| 光标 | `resizeLeftRight` (系统自动) |
| 额外效果 | 无（保持简洁） |

**设计意图**：拖动时保持 hover 状态的高亮，给予用户持续的反馈确认"我正在操作分隔线"。不额外添加 glow 效果，避免分散注意力。

## 3. 过渡动画

```
Idle → Hover:
  - 颜色: outlineVariant → primaryContainer (150ms ease-in-out)
  - 宽度: 1px → 2px (即时，通过 needsDisplay)
  - 指示器: opacity 0 → 1 (150ms ease-in-out)

Hover → Idle:
  - 颜色: primaryContainer → outlineVariant (150ms ease-in-out)
  - 宽度: 2px → 1px (即时)
  - 指示器: opacity 1 → 0 (150ms ease-in-out)

Hover → Dragging:
  - 无视觉变化（已在高亮状态）

Dragging → Idle:
  - 同 Hover → Idle (150ms ease-in-out)
```

### 动画参数

| 参数 | 值 | 来源 |
|------|-----|------|
| 时长 | 150ms | IndustrialAnimation.standard |
| 缓动 | ease-in-out | CAMediaTimingFunction |
| 帧率 | 跟随系统 (ProMotion 适配) | Core Animation |

## 4. 拖动指示器（可选功能）

### 4.1 外观

- 3 个小圆点，垂直排列
- 每个圆点：直径 3px
- 间距：4px（圆点间）
- 总高度：约 17px
- 颜色：与分隔线同色（hover 时 primaryContainer）
- 位置：分隔线垂直居中

### 4.2 视觉示意

```
     ·          ← 3px 圆点
     
     ·          ← 4px 间距
     
     ·
```

### 4.3 显隐逻辑

- 默认隐藏 (opacity: 0)
- Hover 时淡入 (opacity: 1, 150ms)
- 离开 hover 淡出 (opacity: 0, 150ms)
- 拖动时保持显示

## 5. 颜色规格 (来自 IndustrialColors)

| Token | Hex | 用途 |
|-------|-----|------|
| `outlineVariant` | #3c494c | 默认分隔线颜色 |
| `primaryContainer` | #22d3ee | Hover/拖动高亮颜色 |
| `surface` | #0e1416 | 背景参考（对比度计算） |

### 对比度验证

- outlineVariant (#3c494c) on surface (#0e1416): 约 2.5:1 — 微妙但可见
- primaryContainer (#22d3ee) on surface (#0e1416): 约 10:1 — 明确的高亮

## 6. 交互热区

```
                    ← 4px padding (invisible hit area)
  │ Sidebar │ ▎ │ Content │
                    ← 4px padding (invisible hit area)
```

- 视觉宽度：1px (idle) / 2px (hover)
- 交互热区：9px（分隔线中心 ±4px）
- 通过 `effectiveRect:forDrawnRect:` 实现热区扩大

## 7. 响应式考虑

- 窗口最小宽度时：分隔线行为不变
- Sidebar 在 min(200px)/max(400px) 约束内正常拖动
- 分隔线位置跟随 NSSplitView 自动更新

## 8. 无障碍 (Accessibility)

- 光标变化提供了非颜色的交互提示
- 颜色变化足够明显（高对比度）
- 热区足够大（9px）适合各种输入精度
- 如果用户启用了"减少动态效果"，跳过过渡动画直接切换状态

## 9. 设计决策记录

| # | 决策 | 理由 |
|---|------|------|
| D1 | 默认 1px 而非 2px | 不干扰内容阅读 |
| D2 | Hover 用 primaryContainer 而非 primary | primary(#8aebff) 过亮，primaryContainer(#22d3ee) 更内敛 |
| D3 | 不加 glow 效果 | 分隔线是辅助元素，glow 过于抢眼 |
| D4 | 150ms 而非 200ms/300ms | 快速响应感，不拖泥带水 |
| D5 | 圆点指示器可选 | 基础方案已足够，圆点为锦上添花 |
