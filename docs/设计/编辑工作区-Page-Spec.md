# 编辑工作区 Page Spec

> 作者：绘·设计师 | 日期：2026-05-21
> 关联：[DESIGN.md](../../DESIGN.md) | [V1.1-编辑器UI设计方案](./V1.1-编辑器UI设计方案.md) | [V2.0-虚拟时间线波形UI设计方案](./V2.0-虚拟时间线波形UI设计方案.md)
> 范围：编辑工作区（Editing Workspace）的完整页面设计规范
> 整合：本文档是 V1.1 和 V2.0 设计方案的统一 Page Spec，作为开发实现的唯一参照

---

## 一、页面定位

编辑工作区是 AudioRecord 的**第二工作区**，用户从录制工作区通过编辑入口进入。

**核心任务**：对已录制的音频进行轻量编辑（裁剪、静音裁剪、标准化、淡入淡出），然后保存或导出。

**设计原则**：
1. 轻编辑而非 DAW — 不做复杂多轨混音，只做单轨音频处理
2. 剪映式时间线 — 轨道头 + 波形片段同一行，不是独立左侧轨道板
3. 渐进式加载 — 大文件不阻断，tile 模式渐进加载波形
4. 选区驱动 — 大部分编辑操作基于选区（拖柄交互）

---

## 二、整体布局

### 四区结构

```
┌──────────────────────────────────────────────────────────────────┐
│  ① EditorNavigationBar                                           │  44px
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ② EditorWaveformView                                            │  flex
│  (可缩放 / 可滚动 / 可选区 / 时间标尺 / 播放头)                    │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  ③ EditorToolbar                                                 │  36px
├──────────────────────────────────────────────────────────────────┤
│  ④ EditorStatusBar                                               │  24px
└──────────────────────────────────────────────────────────────────┘
```

### 区域尺寸约束

| 区域 | 高度 | 宽度 | 背景色 |
|------|------|------|--------|
| EditorNavigationBar | 44px fixed | 满宽 | `surfaceContainerLow` (#161D1E) |
| EditorWaveformView | flex (占据所有剩余空间) | 满宽 | `surfaceContainerLow` (#161D1E) |
| EditorToolbar | 36px fixed | 满宽 | `surfaceContainer` (#1A2122) |
| EditorStatusBar | 24px fixed | 满宽 | `surface` (#0E1416) |

### Sidebar 关系

编辑器不占满全屏 — Sidebar (260px) 保持可见：
- 用户可快速切换文件，无需返回
- 当前编辑文件在列表中显示 "EDITING" 琥珀色徽章
- 编辑中的文件行不响应双击播放（文件被锁定）

---

## 三、① EditorNavigationBar 设计

### 布局

```
┌───────────────────────────────────────────────────────────────┐
│  [← 返回]   📄 Recording-2026-05-17.wav   [↩] [↪]  [保存]    │
│   左对齐          居中                       右对齐            │
└───────────────────────────────────────────────────────────────┘
```

### 组件规范

| 组件 | 类型 | 尺寸 | 样式 |
|------|------|------|------|
| 返回按钮 | IconButton | 28×28 | SF Symbol: `chevron.left` + "返回" |
| 文件名 | NSTextField | 自适应 | `h2` (14px Bold), `onSurface`, 居中, truncate middle |
| 撤销按钮 | IconButton | 28×28 | SF Symbol: `arrow.uturn.backward` |
| 重做按钮 | IconButton | 28×28 | SF Symbol: `arrow.uturn.forward` |
| 保存按钮 | IndustrialButton | 64×28 | "保存", 有变更时 `primary` 高亮 |

### 状态变化

| 状态 | 返回 | 撤销/重做 | 保存 |
|------|------|----------|------|
| 刚进入（无编辑） | 可用 | 两个禁用 (0.3 opacity) | 禁用 |
| 有编辑操作 | 可用（退出弹确认） | 撤销可用 | 可用（`primary` 边框高亮） |
| 撤销到初始 | 可用 | 撤销禁用, 重做可用 | 禁用 |
| 保存后 | 可用 | 两个禁用 | 禁用 |

### 未保存退出确认

```
┌─ NSAlert ──────────────────────────────────┐
│                                            │
│  📝 有未保存的编辑                          │
│  当前编辑尚未保存，是否保存后退出？          │
│                                            │
│        [放弃]    [取消]    [保存]            │
└────────────────────────────────────────────┘
```

---

## 四、② EditorWaveformView 设计

### 核心特性

EditorWaveformView 是编辑器的核心区域，支持：
- 波形渲染（双向 min/max 振幅）
- 缩放与滚动（Cmd+滚轮 / 双指）
- 选区拖柄（裁剪用）
- 播放头（seek + 播放跟踪）
- 时间标尺（自适应刻度）
- 渐进式加载（tile 模式，大文件支持）

### 波形渲染规范

| 属性 | 值 | 说明 |
|------|-----|------|
| 柱宽 | 1.2px | `barWidth` |
| 柱间距 | 2.2px (含柱宽) | `barSpacing` |
| 圆角 | 0.6px | 微圆角，工业感 |
| 颜色 | `waveformCoral` (#FF6B5F) | 珊瑚红 |
| 绘制方式 | 中线对称，min/max 上下振幅 | 双向绘制 |
| 绘制高度 | 波形区高度 × 0.82 | 留出标尺和引导文字空间 |

### 振幅映射

```
                    peak.max
                      ↑
         ┃           ┃
         ┃     ┃     ┃  ┃
    ─────┃─────┃─────┃──┃──── 中线 (centerY)
         ┃     ┃     ┃  ┃
         ┃           ┃
                      ↓
                    peak.min
```

### 透明度规则

| 状态 | alpha 计算 | 效果 |
|------|-----------|------|
| 选区内 | `max(0.34, min(1.0, 0.34 + level × 0.66))` | 强调 |
| 选区外 | `max(0.15, min(0.4, 0.15 + level × 0.25))` | 弱化 |
| Fallback (低 LOD) | 上述 × 0.4 | 明显弱化 |

### 时间标尺

位于波形区底部，自适应刻度：

| pixelsPerSecond | 主刻度步长 | 标签格式 |
|---:|---:|---|
| > 200 | 0.1s | `M:SS.mmm` |
| 50~200 | 0.5s | `M:SS` |
| 15~50 | 2s | `M:SS` |
| < 15 | 5s/10s/30s | `M:SS` |

标尺视觉：
- 主刻度线：8px 高, `onSurfaceVariant` @ 0.24
- 子刻度线：4px 高
- 标签：`NSFont.monospacedDigitSystemFont(ofSize: 9)`, `textTertiary` @ 0.68
- 中线：虚线 (3px dash, 3px gap), `gridMedium` @ 0.5

### 播放头

```
        ▼ 三角手柄 (10px)
        │
        │ 垂直线 (1.5px)
        │
        ▲ 底部
```

| 属性 | 值 |
|------|-----|
| 三角手柄 | 10px, `waveformAccent` (#FF453A) |
| 垂直线 | 1.5px, `waveformAccent` |
| 位置 | 从 waveformRect.minY 到底部 |
| 行为 | 始终可见，不受 tile 加载状态影响 |

### 选区交互

```
       左拖柄                    右拖柄
          ▼                        ▼
┌─────┬──╋════════════════════════╋──┬─────┐
│ dim │  ║   选中区域（正常亮度）   ║  │ dim │
│     │  ║                        ║  │     │
└─────┴──╋════════════════════════╋──┴─────┘
```

| 元素 | 样式 |
|------|------|
| 选区内波形 | 正常亮度 |
| 选区外遮罩 | `editorDimOverlay` (#0E1416 @ 0.4) |
| 拖柄 | 4px 宽, `primary` (#8AEBFF), 2px 圆角, 3条水平线纹 |
| 拖柄 hover | `glowCyan` 发光 |
| 命中区域 | 8px (`editorHandleHitZone`) |
| 光标 | `resizeLeftRight` |
| 最小选区 | 100ms |

### 缩放交互

| 操作 | 触发 | 行为 |
|------|------|------|
| 放大 | Cmd + = / Cmd + 滚轮上 | `zoomLevel *= 1.5`, 鼠标位置为锚点 |
| 缩小 | Cmd + - / Cmd + 滚轮下 | `zoomLevel /= 1.5`, 最小到 fitAll |
| 适配全部 | Cmd + 0 | 显示完整波形 |
| 水平滚动 | 双指左右 / 水平滚轮 | 平移 `visibleTimeRange` |

### 静音段标记

```
                静音段
┌──────────┬──────────┬──────────────┐
│ 正常波形  │▓ 灰色  ▓│  正常波形     │
│          │▓ + 红线 ▓│              │
└──────────┴──────────┴──────────────┘
```

| 元素 | 样式 |
|------|------|
| 静音段背景 | `editorSilenceOverlay` (#242B2D @ 0.6) |
| 静音段波形 | `waveformMuted` (#FF6B5F @ 0.32) |
| 删除标记线 | `editorSilenceLine` (#FFB4AB) 1px |
| 段落标签 | "SILENCE 0.8s", `monoDB`, `textTertiary` |

---

## 五、加载状态设计（五态覆盖）

### 状态矩阵

| 状态 | 触发条件 | 视觉表现 |
|------|---------|---------|
| **Loading** | 文件刚打开，tile 未就绪 | Skeleton 条纹动画 (45° 斜线, 1.5s 周期) |
| **Fallback** | 目标 LOD 未加载，低 LOD 有缓存 | 低 LOD 淡化绘制 (alpha 0.4) |
| **Populated** | 目标 LOD tiles 已加载 | 正常波形绘制 |
| **Error** | tile 生成失败 | 该区域 ⚠️ 图标 |
| **Empty** | 文件为空或无法读取 | "无法读取音频数据" 文字 |

### Skeleton 状态

```
┌────────────────────────────────────────────────────────────┐
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
│                    加载波形中...                             │
└────────────────────────────────────────────────────────────┘
```

- 条纹颜色：`surfaceContainer` 与 `surfaceContainerLow` 交替
- 条纹方向：45°
- 条纹宽度：8px
- 动画：左到右平移, 1.5s, ease-in-out
- 提示文字：`body`, `textTertiary`, 居中

### Fallback → Populated 过渡

```
tile 就绪 → 目标 LOD 淡入 (alpha 0→1.0, 150ms ease-out)
         → fallback 同时淡出 (alpha 0.4→0, 150ms)
```

**关键**：不是"替换"，是"叠加淡入"，避免波形跳变。

---

## 六、③ EditorToolbar 设计

### 布局

```
┌───────────────────────────────────────────────────────────┐
│  [✂️ 裁剪]  [🔇 静音裁剪]  [📊 标准化]  [🔈 淡入淡出]      │
│   左对齐                                    [▶ 预览] [■]   │
│                                              右对齐        │
└───────────────────────────────────────────────────────────┘
```

### 工具按钮规范

| 属性 | 值 |
|------|-----|
| 尺寸 | 自适应宽 × 32px 高 |
| 字体 | `label` (11px Semibold) |
| 文字色（常态） | `onSurfaceVariant` |
| 文字色（激活） | `primary` (#8AEBFF) |
| 背景（常态） | `surfaceContainerHigh` |
| 背景（hover） | `surfaceContainerHighest` |
| 背景（激活） | `surfaceContainerHighest` + `primaryContainer` 1px 边框 |
| 圆角 | 8px |
| 间距 | 8px |

### 工具可用性

| 工具 | 图标 | 条件 |
|------|------|------|
| 裁剪 | `scissors` | 需要有选区 |
| 静音裁剪 | `waveform.badge.minus` | 随时可用（自动检测） |
| 标准化 | `chart.bar.fill` | 随时可用 |
| 淡入淡出 | `speaker.wave.2` | 需要有选区 |

### 预览播放控制（右侧）

| 按钮 | 图标 | 行为 |
|------|------|------|
| 预览/暂停 | `▶` / `Ⅱ` | 播放编辑后音频 |
| 停止 | `■` | 停止预览，游标归位 |

---

## 七、④ EditorStatusBar 设计

### 布局

```
┌───────────────────────────────────────────────────────────┐
│  DUR 02:34.50  │  48000 Hz  │  STEREO  │  EDITS: 3/20     │
└───────────────────────────────────────────────────────────┘
```

| 属性 | 值 |
|------|-----|
| 高度 | 24px |
| 背景 | `surface` (#0E1416) |
| 字体 | `monoDB` (10px Mono) |
| 文字色 | `onSurfaceVariant` |
| 分隔符 | `│`, `outlineVariant` |

---

## 八、Overlay 层级规范

从底到顶的绘制顺序：

```
Layer 0: 背景色 (surfaceContainerLow)
Layer 1: 时间标尺 (刻度线 + 标签 + 中线)
Layer 2: 选区外遮罩 (editorDimOverlay)
Layer 3: 波形绘制
         ├── Skeleton (条纹动画)
         ├── Fallback (低 LOD, alpha 0.4)
         └── Normal (目标 LOD)
Layer 4: 播放头 (垂直线 + 三角手柄)
Layer 5: 选区拖柄 (左右拖柄 + 纹理)
Layer 6: 引导文字 (无选区时的操作提示)
Layer 7: Error 占位图标 (仅失败 tile 区域)
```

**规则**：
- 播放头和选区拖柄始终在波形之上
- Skeleton/Fallback/Normal 互斥
- Error 图标在最顶层

---

## 九、大文件首次打开体验

### 时间线

```
t=0ms     用户点击"编辑"
t=0ms     编辑器 UI 立即出现（导航栏 + 空波形区 + 工具栏 + 状态栏）
t=50ms    波形区显示 skeleton 条纹动画
t=100ms   状态栏显示文件元信息
t=200ms~  LOD-0 概览 tiles 开始就绪
t=500ms~  Fit All 视图下 LOD-0 全部就绪 → skeleton 淡出，波形淡入
          用户可以开始操作
```

### 体验指标

| 指标 | 目标 |
|------|------|
| 编辑器 UI 出现 | < 100ms |
| 首屏波形可见 | < 3s |
| 可交互 | < 3s |
| 精细波形就绪 | 按需 (缩放后 1-2s) |

### 短文件 vs 长文件

| 维度 | 短文件 (≤60s) | 长文件 (>60s) |
|------|--------------|--------------|
| 加载方式 | 全量 buffer | tile 模式渐进式 |
| 首屏时间 | < 500ms | < 3s |
| 波形精度 | 固定 | 自适应 LOD |
| 加载提示 | "加载波形..." 文字 | Skeleton 条纹动画 |

---

## 十、快捷键映射

### 编辑器模式快捷键

| 快捷键 | 功能 | 条件 |
|--------|------|------|
| `Cmd+Z` | 撤销 | 有操作可撤销 |
| `Cmd+Shift+Z` | 重做 | 有操作可重做 |
| `Cmd+S` | 保存 | 有未保存编辑 |
| `Cmd+Shift+S` | 另存为 | 始终可用 |
| `Space` | 预览播放/暂停 | 始终可用 |
| `Escape` | 返回录制页 | 未保存时弹确认 |
| `Cmd+=` | 放大波形 | 始终可用 |
| `Cmd+-` | 缩小波形 | 始终可用 |
| `Cmd+0` | 适配全部 | 始终可用 |
| `Cmd+A` | 全选 | 选中整段波形 |
| `Delete` | 删除选区 | 有选区时 |

### 快捷键隔离

编辑器模式下，录制快捷键被禁用：
- `Cmd+R`（录制）→ 不响应
- `Cmd+E`（导出）→ 不响应
- `Cmd+Del`（删除录音）→ 不响应

---

## 十一、页面切换动效

### 录制页 → 编辑器（进入）

```
时间线:  0ms ─────────── 200ms

录制页:  [完整显示] ─→ [向左滑出 + 淡出]
编辑器:  [从右侧偏移 30px + 透明] ─→ [正常位置 + 完全不透明]

缓动:  easeOut
时长:  200ms (IndustrialAnimation.long)
```

### 编辑器 → 录制页（返回）

```
编辑器:  [完整显示] ─→ [向右滑出 30px + 淡出]
录制页:  [从左侧偏移 30px + 透明] ─→ [正常位置 + 完全不透明]
```

---

## 十二、操作引导文字

### 无选区时

```
↔ 在波形上拖拽创建选区，然后使用工具栏操作
```
- 字体：`monoDB` (10px Mono)
- 颜色：`textTertiary` @ 0.5
- 位置：波形区底部 (y = waveformRect.minY + 4)

### 加载中时

```
加载波形中...
```
- 字体：`body` (13px)
- 颜色：`textTertiary`
- 位置：波形区垂直居中

### 大文件查看模式

```
文件较大，当前为查看模式。支持滚动和缩放浏览波形。
```
- 字体：`monoDB` (10px Mono)
- 颜色：`tertiary` (琥珀色)
- 位置：状态栏或波形区底部

---

## 十三、与录制工作区的关系

### 编辑器入口

| 入口方式 | 触发 | 行为 |
|---------|------|------|
| 文件行编辑按钮 | Hover 文件行 → 出现 ✏️ 图标 → 点击 | 进入独立编辑器 |
| 录制停止后 | 自动 | 录制工作区内的轻编辑态（工具栏激活） |
| 双击文件 | 双击 | 播放（不进入编辑器） |

### 编辑中文件标记

文件列表中被编辑的文件显示：
- 徽章：`EDITING`
- 颜色：`tertiary` (#FFD6A3)
- 背景：`surfaceContainerHighest`
- 该行不响应双击播放

---

## 十四、Craft 检查清单

| 规则 | 状态 | 说明 |
|------|------|------|
| 色彩 | ✅ | 延续 Industrial 调色板，无新增强调色 |
| 排版 | ✅ | 标尺字体 monospacedDigit 9pt，其余复用系统 |
| 排版层级 | ✅ | 唯一主导入口（文件名 14px Bold）→ 工具标签 11px → 状态 10px |
| 动效纪律 | ✅ | 页面切换 200ms、tile 淡入 150ms、skeleton 1.5s |
| 反 AI slop | ✅ | 无渐变、无 blob、无装饰性动画 |
| 无障碍 | ⚠️ | 波形区键盘导航后续补充 (MVP-3) |
| 状态覆盖 | ✅ | 五态全覆盖：Loading/Fallback/Populated/Error/Empty |
| UX 法则 | ✅ | Hick (4 工具)、Fitts (8px 拖柄热区)、Gestalt (视觉分组) |

---

## 十五、Design Token 新增清单

编辑器需要在 `IndustrialDesignTokens.swift` 中确保以下 Token 存在：

### 已存在 ✅

```swift
static let editorHandle = IndustrialColors.primary
static let editorDimOverlay = NSColor(hex: "#0E1416", alpha: 0.4)
static let editorSilenceOverlay = NSColor(hex: "#242B2D", alpha: 0.6)
static let editorSilenceLine = IndustrialColors.error
static let editorEditingBadge = IndustrialColors.tertiary
static let editorNavBarHeight: CGFloat = 44
static let editorToolbarHeight: CGFloat = 36
static let editorStatusBarHeight: CGFloat = 24
static let editorHandleWidth: CGFloat = 4
static let editorHandleHitZone: CGFloat = 8
```

### 建议新增（V2.0 tile 模式）

```swift
static let waveformFallback = waveformCoral.withAlphaComponent(0.4)
static let skeletonBase = surfaceContainer
static let skeletonHighlight = surfaceContainerLow
// IndustrialAnimation
static let skeletonDuration: TimeInterval = 1.5
static let tileFadeIn: TimeInterval = 0.15
```

---

*文档结束。本设计规范整合 V1.1 和 V2.0 设计方案，配合 DESIGN.md 设计系统使用。*
