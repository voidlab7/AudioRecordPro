# 设计审查报告: 音轨显示逻辑优化

> 审查人: 绘·设计 | 日期: 2026-05-05 | 依据: Industrial Design System

---

## 审查结论: ✅ 通过（85/100）

PRD 定义的交互和视觉方向完全符合 Industrial Design 规范，补充以下设计规格。

---

## 1. 轨道行（TrackRowView）设计规格

### 1.1 尺寸

| 属性 | 值 | 说明 |
|------|-----|------|
| 行高 | 100px | 缩减原 120px，两轨时不溢出 |
| 内边距 | 12px 上下, 12px 左右 | 保持 Industrial 紧凑间距 |
| 轨道间距 | IndustrialSpacing.sm (8px) | stack spacing |
| 电平表高度 | 占据行内剩余空间（约 50px） | 自适应 |

### 1.2 色彩

| 元素 | Token | 说明 |
|------|-------|------|
| 行背景 | IndustrialColors.surfaceContainerLow | 深色底板 |
| 行边框 | IndustrialColors.outlineVariant, 1px | 硬边 |
| 标题文字 | IndustrialColors.onSurface | 亮灰大写 |
| 来源标注 | IndustrialColors.textTertiary | 灰字 10px mono |
| 圆角 | IndustrialCornerRadius.xs (2px) | 硬边工业风 |

### 1.3 排版

- 标题：IndustrialTypography.label (11px semibold, kern 0.4, uppercase)
- 来源标注：IndustrialTypography.monoDB (10px mono)
- 混合输出说明：IndustrialTypography.small + textTertiary

---

## 2. 动画规格

| 动画 | 时长 | 曲线 | 属性 |
|------|------|------|------|
| 麦克风轨插入 | 0.25s | easeInOut | alphaValue 0→1, frame.origin.y +20→0 |
| 麦克风轨移除 | 0.2s | easeIn | alphaValue 1→0, frame.origin.y 0→+20 |

**注意**：使用 NSAnimationContext.runAnimationGroup，不使用 CAAnimation（保持 AppKit 原生一致性）。

---

## 3. 布局策略

```
TracksView
├── tracksStack (NSStackView, vertical, spacing=8)
│   ├── TrackRowView — 音源轨 (always visible)
│   │   ├── headerView (icon + title)
│   │   ├── levelMeter (LevelMeterView)
│   │   └── sourceLabel (来源标注)
│   └── TrackRowView — 麦克风轨 (conditional, animated)
│       ├── headerView (🎤 + "麦克风")
│       ├── levelMeter (LevelMeterView)
│       └── sourceLabel ("MICROPHONE INPUT")
├── mixOutputLabel (📤 混合输出为单文件, conditional)
└── playbackPanel (existing, unchanged)
```

---

## 4. 关注点

1. **两轨高度适配**：tracksStack 在两轨时总高约 208px (100+8+100)，需确认不会挤压 playbackPanel
2. **电平表复用**：LevelMeterView 实例独立创建，bars 数据不共享（各自维护内部状态）
3. **暗色主题**：所有新增元素必须使用 IndustrialColors token，禁止硬编码颜色值

---

## 交接块

```
来源: 绘·设计
状态: ✅ 完成
产物文件: ai-workspace/task-0505-track-display-v1/artifacts/03-design/design-review.md
评分: 85/100
下游建议: 矩·架构 → 据此设计规格制定组件拆分方案
```
