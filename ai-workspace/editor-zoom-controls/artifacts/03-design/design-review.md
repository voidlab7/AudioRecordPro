# 编辑器缩放/滑动控件 — 设计评审报告

> **评审者**: 绘·设计师 | **日期**: 2026-05-25 | **模式**: Check（评审）
> **评审对象**: `artifacts/02-requirement/编辑器缩放控件-交互规格.md`
> **评审基准**: `docs/设计/设计规范.md` + `IndustrialDesignTokens.swift`

---

## 1. 总体评分（0-10 × 7 维度）

| 维度 | 评分 | 说明 |
|------|------|------|
| **功能覆盖** | 9/10 | 缩放按钮+滑块+滚动条+FitAll+键盘快捷键+手势全覆盖，非常完整 |
| **视觉一致性** | 8/10 | 大部分 token 引用正确，有 2 处需修正（见下） |
| **交互合理性** | 9/10 | 对数映射、锚定中心、边界反馈设计合理，竞品对标到位 |
| **层次与信息密度** | 8/10 | 底部工具栏布局合理，但需确认窄窗口下的响应式降级细节 |
| **无障碍** | 7/10 | 键盘快捷键全覆盖，但缺少 VoiceOver 标注和对比度验证 |
| **一致性与设计系统** | 8/10 | Token 使用正确，有 1 处圆角值和设计系统不匹配 |
| **AI 烂俗检测** | 10/10 | 无任何 AI 烂俗反模式，纯功能 UI |

**综合评分：8.4/10** — 优秀，小修后可进入开发

---

## 2. 确认通过的设计决策（SAFE CHOICES）

| 决策 | 原则/竞品依据 |
|------|--------------|
| 缩放控件放底部工具栏右侧 | 与本项目编辑工具在底部的既定布局一致（V1.1 设计方案） |
| 按钮+滑块+手势并行提供 | Logic Pro / GarageBand / 剪映共识，覆盖不同用户习惯 |
| 对数映射缩放滑块 | 正确：人类对缩放的感知是对数的，线性映射会让低级别区域过窄 |
| 滚动条 `zoomLevel > 1.0` 时才显示 | 正确：fitAll 时无需滚动，隐藏减少视觉噪音 |
| 时间标尺密度自适应 | 正确：避免刻度重叠，参考 Logic Pro 和 GarageBand |
| SF Symbol 图标 | 与设计系统「SF Symbols exclusively」规则一致 |
| 150ms/200ms 动画时长 | 与 `IndustrialAnimation.standard`(120ms) / `.long`(200ms) 接近一致 |

---

## 3. 需修正的问题

### 3.1 [LOW] 缩放按钮圆角值偏差

**规格中写的**：`IndustrialCornerRadius.sm` (4px)

**实际 Token 值**：
- `IndustrialCornerRadius.xs` = 4px
- `IndustrialCornerRadius.sm` = 8px

**修正**：缩放按钮作为 24×24 图标按钮，圆角应为 `IndustrialCornerRadius.xs`（4px），与设计系统中 Icon Button 的 `xs`(4px) 规范一致。规格中已经写了 4px，但引用的 token 名字错了（应该是 `.xs` 不是 `.sm`）。

**影响**：纯文档修正，不影响实现。

### 3.2 [MEDIUM] 缩放动画时长与 Token 轻微不一致

**规格中**：点击按钮缩放 = 150ms
**Token 值**：`IndustrialAnimation.standard` = 120ms，`.long` = 200ms

**建议**：采用 120ms（standard）用于点击缩放，200ms（long）用于 FitAll。不建议引入 150ms 这个非标准值。

**修正后映射**：

| 场景 | 时长 | Token |
|------|------|-------|
| 点击按钮缩放 | 120ms | `IndustrialAnimation.standard` |
| 拖动滑块 | 实时 | `IndustrialAnimation.realtime` |
| Fit All | 200ms | `IndustrialAnimation.long` |
| 键盘快捷键 | 120ms | `IndustrialAnimation.standard` |
| 触控板捏合 | 实时 | `IndustrialAnimation.realtime` |

### 3.3 [LOW] 缺少 VoiceOver 无障碍标注

规格覆盖了键盘快捷键（好），但缺少：
- 缩放按钮的 `accessibilityLabel`（"放大" / "缩小" / "适应全部"）
- 滑块的 `accessibilityValue`（当前缩放级别描述）
- 滚动条的 `accessibilityRole` 和 `accessibilityValue`

**建议补充**：

| 控件 | accessibilityLabel | accessibilityValue |
|------|-------------------|-------------------|
| 🔍+ 按钮 | "放大" | — |
| 🔍− 按钮 | "缩小" | — |
| 缩放滑块 | "缩放级别" | "当前可见 {时间范围}" |
| ⊞ Fit All | "适应全部" | — |
| 滚动条 | "时间位置" | "当前位置 {startTime} 至 {endTime}" |

---

## 4. 设计增强建议（非阻塞）

### 4.1 [建议] 滑块 Tooltip 显示可见时间范围

规格 §6.1 提到 Tooltip 显示"当前视图: 0:30 ~ 1:30 (1分钟)"，建议：
- Tooltip 使用 `IndustrialTypography.monoDB`（10px mono）
- 背景使用 `IndustrialColors.surfaceBright`
- 延迟 500ms 后出现，移出 200ms 后消失
- 这与设计系统 Level 6（Floating）一致

### 4.2 [建议] 底部工具栏布局调整

当前规格的底部工具栏：
```
[▶ 预览] [■]                    [🔍−] ━━━━●━━━━━━━ [🔍+] [⊞ Fit]
```

建议增加中间分隔符，与现有 Status Bar 的 `│` 分隔符语言一致：
```
[▶ 预览] [■]        │        [🔍−] ━━━●━━━━━ [🔍+] [⊞]
```

分隔符使用 `IndustrialColors.outlineVariant` @ 0.5 alpha，高度 16px 居中。

### 4.3 [建议] 滚动条与波形区的间距

规格中滚动条在"波形区与底部工具栏之间"，建议精确间距：
- 波形区底部 → 滚动条顶部：4px（`IndustrialSpacing.xs`）
- 滚动条底部 → 工具栏顶部：4px（`IndustrialSpacing.xs`）
- 滚动条总高度含 padding：12px（轨道 4px + 上下各 4px padding）

当 `zoomLevel = 1.0` 时，这 12px 空间收回给波形区（fadeOut 后移除空间，不保留空白）。

### 4.4 [建议] 窄窗口响应式降级补充

规格 §11 提到"窗口 < 800px 时隐藏滑块，只保留按钮"，建议分级：

| 工具栏可用宽度 | 显示内容 |
|--------------|---------|
| > 400px | 完整：🔍− + 滑块(120px) + 🔍+ + ⊞ |
| 300-400px | 压缩：🔍− + 滑块(80px) + 🔍+ + ⊞ |
| 200-300px | 精简：🔍− + 🔍+ + ⊞（隐藏滑块） |
| < 200px | 最小：仅保留 ⊞ Fit All |

注意：这里是"工具栏右侧缩放控件区域的可用宽度"，不是窗口宽度。考虑 Sidebar(260px) + 播放控制区域，实际触发点会在窗口 ~1000px 以下。

---

## 5. AI 烂俗 10 反模式检查

| # | 反模式 | 检查结果 |
|---|--------|---------|
| 1 | 紫色/靛蓝渐变 | ✅ 不涉及，纯功能控件 |
| 2 | 三列特性网格 | ✅ 不涉及 |
| 3 | 彩色圆圈图标 | ✅ 不涉及，使用 SF Symbol |
| 4 | 全部居中 | ✅ 不涉及，左右分区布局 |
| 5 | 统一超大圆角 | ✅ 不涉及，使用 4px xs 圆角 |
| 6 | 装饰性 blob | ✅ 不涉及 |
| 7 | Emoji 作为设计 | ✅ 规格用 emoji 仅做文档说明，实际 UI 用 SF Symbol |
| 8 | 卡片左彩色条 | ✅ 不涉及 |
| 9 | 模板化英雄文案 | ✅ 不涉及 |
| 10 | 千篇一律节奏 | ✅ 不涉及 |

**结论：0 项命中，设计安全。**

---

## 6. Craft 工艺规则检查

| 规则 | 结果 | 备注 |
|------|------|------|
| 色彩四层 | ✅ | Token 引用正确，控件色使用 primary/onSurfaceVariant |
| 排版 | ✅ | 控件无文字标签需求，Tooltip 建议用 monoDB |
| 动效纪律 | ⚠️ | 150ms 非标准值，已在 §3.2 建议修正为 120ms |
| 反 AI slop | ✅ | 全部通过 |
| 无障碍基线 | ⚠️ | 缺 VoiceOver 标注，已在 §3.3 建议补充 |
| 状态覆盖 | ✅ | disabled 状态（极限缩放）+ 正常态 + 隐藏态（fitAll 时滚动条） |
| UX 法则 | ✅ | Fitts 定律：24px 按钮够大；对数映射符合韦伯-费希纳定律 |

---

## 7. 最终视觉规格确认（给铸的精确参数）

### 7.1 缩放按钮

| 属性 | Token / 值 |
|------|-----------|
| 尺寸 | 24×24 px |
| 图标 | SF Symbol: `minus.magnifyingglass` / `plus.magnifyingglass` |
| 图标色（正常） | `IndustrialColors.onSurfaceVariant` (#BBC9CD) |
| 图标色（hover） | `IndustrialColors.onSurface` (#DDE4E5) |
| 图标色（disabled） | `IndustrialColors.onSurfaceVariant` @ alpha 0.35 |
| 背景（正常） | 透明 |
| 背景（hover） | `IndustrialColors.surfaceContainerHigh` (#242B2D) |
| 圆角 | `IndustrialCornerRadius.xs` (4px) ⚠️ 修正：不是 .sm |
| 热区 | 28×28 px（满足无障碍最小触摸目标） |

### 7.2 缩放滑块

| 属性 | Token / 值 |
|------|-----------|
| 轨道宽度 | 80-120px（响应式） |
| 轨道高度 | 3px |
| 轨道色 | `IndustrialColors.outlineVariant` (#3C494C) |
| 已填充轨道色 | `IndustrialColors.primary` @ alpha 0.5 (#8AEBFF @ 0.5) |
| Knob 直径 | 10px |
| Knob 颜色 | `IndustrialColors.primary` (#8AEBFF) |
| Knob hover | 12px + IndustrialShadow.small |
| 映射 | 对数：`position = log(zoom) / log(maxZoom)` |

### 7.3 Fit All 按钮

| 属性 | Token / 值 |
|------|-----------|
| 图标 | SF Symbol: `arrow.left.and.right.square` |
| 尺寸 | 24×24 px |
| Tooltip | "适应全部 (⌘0)" |
| 其他 | 同缩放按钮规格 |

### 7.4 横向滚动条

| 属性 | Token / 值 |
|------|-----------|
| 总高度（含 padding） | 12px |
| 轨道高度 | 4px |
| Thumb 最小宽度 | 40px |
| Thumb 颜色 | `IndustrialColors.primary` @ alpha 0.6 (#8AEBFF @ 0.6) |
| Thumb hover | `IndustrialColors.primary` @ alpha 0.8 |
| Thumb 圆角 | 2px |
| 轨道颜色 | `IndustrialColors.outlineVariant` @ alpha 0.3 (#3C494C @ 0.3) |
| 左右箭头 | 不建议实现（占空间，触控板滑动更自然） |
| 显示条件 | `zoomLevel > 1.0` 时 fadeIn（200ms），`= 1.0` 时 fadeOut |

**关于左右箭头**：规格中有左右箭头设计，但从设计角度建议省略。原因：
1. macOS 原生滚动条已不再使用箭头（自 10.7 起）
2. 用户已习惯触控板横向滑动
3. 节省空间给 Thumb 更大的活动范围
4. 减少视觉复杂度

如果团队坚持保留，则使用 SF Symbol `chevron.left` / `chevron.right`，12×12px，`onSurfaceVariant` 色。

### 7.5 时间标尺

| 属性 | Token / 值 |
|------|-----------|
| 高度 | 24px |
| 背景 | `IndustrialColors.surfaceContainer` (#1A2122) |
| 主刻度线颜色 | `IndustrialColors.outlineVariant` (#3C494C) |
| 副刻度线颜色 | `IndustrialColors.outlineVariant` @ alpha 0.5 |
| 时间文字 | `IndustrialTypography.monoDB` (10px mono), `IndustrialColors.onSurfaceVariant` |
| 播放头三角标 | `IndustrialColors.waveformAccent` (#FF453A), 宽 8px 高 6px |
| 底部分隔线 | 1px `IndustrialColors.outlineVariant` |

---

## 8. 评审结论

### 判定：✅ 通过（有条件）

**条件**：
1. 修正圆角 token 引用（`.xs` 不是 `.sm`）— 文档级修正
2. 统一动画时长为 Token 标准值（120ms / 200ms）— 影响实现

**非阻塞建议**（铸实现时参考即可）：
- 补充 VoiceOver 标注
- 滚动条省略左右箭头
- 底部工具栏增加分隔符
- 响应式降级分级细化

---

## 📤 交接块（Handoff）

- **来源**: 绘·设计师
- **阶段**: 设计（03-design）
- **产出类型**: 设计评审报告
- **产物文件**: `ai-workspace/editor-zoom-controls/artifacts/03-design/design-review.md`
- **状态**: 有条件通过
- **关键决策**:
  1. 圆角 token 修正：xs(4px) 不是 sm(8px)
  2. 动画时长统一：120ms(standard) + 200ms(long)，不引入 150ms
  3. 建议省略滚动条左右箭头
  4. 整体设计方案 8.4/10，高质量可执行
- **开放问题**:
  1. 是否接受省略滚动条左右箭头的建议？
- **下游建议**: 矩·架构师（工程审查：技术方案 + 组件拆分）
- **阻塞项**: 无
