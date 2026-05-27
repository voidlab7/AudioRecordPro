# LevelMeterCard 电平表卡片 UI 优化 — 设计方案

**任务**: req-2.0-04-levelmeter-ui
**阶段**: 03-design
**负责**: 设计_绘
**日期**: 2026-05-26

---

## 1. 设计概述

基于 REQ-2.0-04 需求文档，对 `LevelMeterCardView.swift` 进行全面 UI 优化，从当前的连续渐变电平表升级为专业级分段 LED 风格电平表。

## 2. 修改文件清单

| 文件 | 修改内容 |
|------|---------|
| `AudioRecordApp/Sources/Views/LevelMeterCardView.swift` | 主要重构文件（7项优化全部在此） |
| `AudioRecordApp/Sources/Views/MainWindowView.swift` | `levelMeterWidth` 从 64 改为 80 |

## 3. 技术实现方案

### 3.1 布局参数变更

```swift
// 旧值 → 新值
barWidth: 14 → 12
barGap: 3 → 4
labelAreaWidth: 24 → 20
topPadding: 28 → 24
bottomPadding: 8 → 28
peakHoldTime: 1.2 → 1.5
maxDB: 6 → 0
```

### 3.2 分段 LED 实现策略

- 使用循环绘制固定高度（3px）的矩形段，段间 1px 间隔
- 根据段的位置确定颜色区间（绿/黄/橙/红）
- 已填充段使用对应颜色 100% 不透明
- 未填充段使用 `white @ 0.04`

### 3.3 Clip 指示器实现

- 新增属性：`clipTriggered: Bool`、`clipTimestamp: Date?`
- 绘制在电平条顶部（6×6px 方块）
- 使用 `mouseDown` 事件实现点击复位
- 3秒自动熄灭通过 `updateLevels` 中的时间检查实现

### 3.4 峰值数值显示

- 在 `bottomPadding` 区域绘制
- 使用 `monospacedDigitSystemFont` 9px
- 取 L/R 中较高值，格式 `-XX.X`
- 颜色动态变化：正常(onSurfaceVariant) / 偏高(#F59E0B) / 危险(#EF4444)

### 3.5 峰值保持线优化

- 线宽从 1.2px 改为 2px
- 颜色根据峰值位置动态着色（绿区白色/黄区黄色/红区红色）
- 衰减使用 easeOut 缓动（非线性）

## 4. 颜色常量

```swift
static let ledGreen = NSColor(hex: "#22C55E")
static let ledYellow = NSColor(hex: "#F59E0B")
static let ledOrange = NSColor(hex: "#F97316")
static let ledRed = NSColor(hex: "#EF4444")
```

## 5. 性能考虑

- 分段 LED 绘制使用预计算的段数和颜色数组，避免每帧重复计算
- Clip 状态检查集成在 `updateLevels` 中，不额外增加定时器
- 峰值衰减使用 easeOut 曲线：`peak *= 0.92`（指数衰减近似）

## 6. 风险评估

| 风险 | 缓解 |
|------|------|
| 分段绘制性能 | 段数固定，预计算颜色数组 |
| 点击 Clip 复位区域太小 | 扩大点击热区到 12×12 |
| 80px 宽度在最小窗口下溢出 | 验证 800×600 最小窗口布局 |

---

## 交接块
- **来源**: 设计_绘
- **目标**: 开发_铸
- **产出路径**: ai-workspace/req-2.0-04-levelmeter-ui/artifacts/03-design/DESIGN.md
- **摘要**: LevelMeterCard 7项UI优化设计方案，含分段LED、Clip指示器、峰值数值等
- **建议下游关注**: 分段LED绘制性能、Clip点击热区、maxDB从6改为0后的归一化计算
