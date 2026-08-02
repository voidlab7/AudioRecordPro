# PRD · AudioRecord 编辑器 UI 还原

> **文档版本**：v1.0  
> **创建日期**：2026-08-01  
> **作者**：PM_枢（产品顾问模式，对话驱动）  
> **状态**：待评审  
> **目标**：将 AudioRecord 编辑器 UI 从「嵌入态单轨道回看」还原到「专业多轨道编辑器」

---

## 目录

- [1. 背景与目标](#1-背景与目标)
- [2. 差距总结](#2-差距总结)
- [3. Phase 1 · 核心视觉 + 结构升级（合并）](#3-phase-1--核心视觉--结构升级合并)
  - [REQ-UI-01 · 编辑器顶部工具栏扩展（6 → 12+ 按钮）](#req-ui-01--编辑器顶部工具栏扩展6--12-按钮)
  - [REQ-UI-02 · 多轨道与空轨道占位](#req-ui-02--多轨道与空轨道占位)
  - [REQ-UI-03 · Clip 卡片化与信息密度](#req-ui-03--clip-卡片化与信息密度)
  - [REQ-UI-04 · 播放头与选区视觉强化](#req-ui-04--播放头与选区视觉强化)
  - [REQ-UI-05 · 中央大型时间码 + 播放控件重布局](#req-ui-05--中央大型时间码--播放控件重布局)
  - [REQ-UI-08 · 设计令牌细化 + 默认窗口尺寸](#req-ui-08--设计令牌细化--默认窗口尺寸)
- [4. Phase 2 · 功能完善](#4-phase-2--功能完善)
  - [REQ-UI-06 · 状态栏信息扩展（4 段 → 8 段）](#req-ui-06--状态栏信息扩展4-段--8-段)
  - [REQ-UI-07 · 吸附系统与 Marker / 节拍标记](#req-ui-07--吸附系统与-marker--节拍标记)
- [5. 里程碑与交付物](#5-里程碑与交付物)
- [6. 风险与假设](#6-风险与假设)
- [7. 附录](#7-附录)

---

## 1. 背景与目标

### 1.1 项目背景

AudioRecord 是 macOS 原生音频录制+轻编辑工具（Swift + AppKit）。当前编辑器 UI 为 **嵌入模式**（`isEmbedded = true`），部署在 `MainWindowView` 内，使用其 `EditToolbarView` / `StatusBarView` / `ControlPanelView` 作为 chrome。视觉风格接近录音回看面板，而非专业编辑器。

### 1.2 目标

将编辑器 UI 还原到 **独⽴标准编辑器视图**，对齐参考设计稿（`assets/stitch_audio_record_pc/screen.png`）中展示的专业音频编辑器风格——多轨道、Clip 卡片化、大型时间码、吸附与标记系统。

### 1.3 用户故事总览

> **作为** AudioRecord 用户（需要处理录音的创作者/技术人员），  
> **我希望** 编辑器能像专业 DAW 一样提供多轨道、清晰的时间码、直观的 Clip 边界和选区反馈，  
> **以便** 高效完成剪辑，不需要打开 Audacity 或 Logic Pro。

---

## 2. 差距总结

| 维度 | 现状 | 目标 | 差距等级 | 对应需求 |
|------|------|------|---------|----------|
| 工具栏按钮数 | 6 按钮（切/裁/静/标/淡/淡） | 12+ 按钮（返/撤/重/剪/删/标/节拍/工具/撤销缩放） | 🔴 大 | REQ-UI-01 |
| 默认轨道数 | 1 个 | 2 个（1 主 + 1 空轨） | 🔴 大 | REQ-UI-02 |
| 空轨道占位 | 无 | "拖拽音频文件到此轨道" | 🔴 大 | REQ-UI-02 |
| Clip 表示 | 连续波形块 | 文件名 + 起止三角 + 时长的圆角卡片 | 🔴 大 | REQ-UI-03 |
| 播放头样式 | 1px 灰线 | 2px 红色竖线 + 顶部三角 | 🟡 中 | REQ-UI-04 |
| 选区可视化 | 微弱高亮 | 半透明背景 + 边框 + 把手 | 🟡 中 | REQ-UI-04 |
| 中央时间码 | 无（小 timer 在底部） | 48pt+ 居中时间码 | 🔴 大 | REQ-UI-05 |
| 播放控件 | 录制 + ▶ + ■（3 按钮） | ⏮ / ▶ / ■ / ⏭（4 按钮） | 🟡 中 | REQ-UI-05 |
| 状态栏段数 | 4 段 | 8 段（编辑中/选区/拖拽提示/S吸附/T吸附） | 🟡 中 | REQ-UI-06 |
| 缩放控件 | 底部 -/+/滑块 | 顶部右侧 + 42% 百分比 | 🟢 小 | REQ-UI-01 |
| 窗口尺寸 | 默认 1024×768 | 1280×800 | 🟢 小 | REQ-UI-08 |
| 设计令牌 | IndustrialColors 通用 | #232327 / #2A2A2E / #1B1B1F / #363638 / white@15% | 🟡 中 | REQ-UI-08 |
| 吸附 | 无 | S 零交叉 / T 时间吸附 | 🟡 中 | REQ-UI-07 |
| Marker | 无 | 自定义标记 + 节拍/小节 | 🟡 中 | REQ-UI-07 |
| 拖拽导入 | 无 | 拖拽 wav/mp3 到轨道 | 🟡 中 | REQ-UI-02 |

---

## 3. Phase 1 · 核心视觉 + 结构升级（合并）

> **Phase 1 目标**：出单一「视觉接近 + 结构正确」的编辑器版本，用户打开即有明显感知。  
> **包含需求**：REQ-UI-01 / 02 / 03 / 04 / 05 / 08  
> **估计工作量**：9-12 工作日（1 人全栈）或 5-7 日（2 人并行）

---

### REQ-UI-01 · 编辑器顶部工具栏扩展（6 → 12+ 按钮）

#### 用户故事

> **作为** 编辑者，  
> **我希望** 编辑器顶部有一行完整的工具栏，包含常用的标记/删除/节拍操作，  
> **以便** 不用菜单即可快速操作音频内容。

#### 现状问题

- `EditorNavigationBar`（独立模式）：◀ 返回 | ↩ 撤销 ↪ 重做 | ✂剪 ⫿静 📊标 🔉淡 | [保存]（共 8 槽位）
- `EditToolbarView`（嵌入模式）：切分 | 裁剪 | 静音 | 标准化 | 淡入 | 淡出（共 6 按钮）
- 两套不同的 chrome，维护成本高，按钮不一致
- 缺少：删除（🗑）、Marker（M）、节拍（♩♪）、缩放撤销、工具切换

#### 目标描述

工具栏一行 12+ 按钮（从左到右）：

| # | 按钮 | 图标 | 功能 | 快捷键 |
|---|------|------|------|--------|
| 1 | 返回 | ◀ | 退出编辑器，回主窗口 | Esc |
| 2 | 撤销 | ↶ | 撤销上次编辑 | ⌘Z |
| 3 | 重做 | ↷ | 重做已撤销编辑 | ⌘⇧Z |
| — | 分隔线 | `|` | | |
| 4 | 剪切 | ✂ | 裁剪选区 | ⌘T |
| 5 | 删除 | 🗑 | 删除选区 | Delete |
| — | 分隔线 | `|` | | |
| 6 | 添加标记 | M | 在播放头位置添加 marker | M |
| 7 | 撤销标记 | ↶M | 撤销最后添加的 marker | ⌘M |
| 8 | 节拍标记 | ♩ | 自动检测 BPM 并添加小节线 | ⌘B |
| 9 | 撤销节拍 | ↶♩ | 清除所有节拍标记 | ⌘⇧B |
| — | 分隔线 | `|` | | |
| 10 | 撤销缩放 | ↶🔍 | 缩放到适应全部 | ⌘0 |
| 11 | 工具 | 🔧 | 工具切换弹窗（鼠标/选区/移动） | F1-F3 |
| — | 弹性空间 | `————————————————` | | |
| 12 | 缩放- | − | 缩小 | ⌘− |
| 13 | 缩放% | 42% | 当前缩放级别（标签，不可点击） | |
| 14 | 缩放+ | + | 放大 | ⌘= |
| — | 右对齐 | | | |
| 15 | 导出 | ↑ 导出 | 导出音频文件 | ⌘E |
| 16 | 保存 | 💾 保存（高亮按钮） | 保存编辑到原文件 | ⌘S |

**实现策略**：保留 `EditorNavigationBar` 作为唯一来源，废弃 `EditToolbarView`（或改造为 `EditorNavigationBar` 的简化版）。独立模式和嵌入模式共享同一套工具栏代码。

#### 边界情况

| # | 边界 | 处理方式 |
|---|------|----------|
| BC-01 | 窗口极窄（<600px） | 按钮自动换到 overflow menu（"…" 更多），最少保留 4 个核心按钮 |
| BC-02 | 无撤销历史 | 撤销/重做按钮 disabled（35% 透明度） |
| BC-03 | 无选区 | 剪切/删除按钮 disabled |
| BC-04 | 节拍检测中 | 按钮转菊花 spinner |
| BC-05 | 缩放到极限 | 缩放+/− 按钮 disabled |

#### 验收用例

| ID | 场景 | 预期 |
|----|------|------|
| AC-01-01 | 进入编辑器 | 工具栏显示 12+ 按钮，缩放显示当前百分比 |
| AC-01-02 | 无文件编辑历史 | 撤销/重做 disabled |
| AC-01-03 | 执行一次编辑后 | 撤销 enabled，重做 disabled |
| AC-01-04 | 拖拽创建选区后 | 剪切/删除 enabled |
| AC-01-05 | 点击缩放− | 波形缩小，百分比更新 |
| AC-01-06 | 点击缩放+ | 波形放大，百分比更新 |
| AC-01-07 | 点击返回 | 弹窗提示"有未保存编辑"（如有），退出编辑器 |
| AC-01-08 | 点击保存按钮 | 高亮（青色填充）显示有未保存更改 |
| AC-01-09 | 窗口缩窄到 500px | 按钮折叠到 overflow "…"，核心 4 按钮保留 |
| AC-01-10 | 快捷键 ⌘Z | 触发撤销，按钮状态同步更新 |

#### 涉及文件

```
AudioRecordApp/Sources/Views/Editor/EditorNavigationBar.swift  ← 重构为主工具栏
AudioRecordApp/Sources/Views/EditToolbarView.swift              ← 废弃/迁到 EditorNavigationBar
AudioRecordApp/Sources/Views/Editor/ZoomControlsView.swift      ← 集成到工具栏右侧
AudioRecordApp/Sources/Views/Editor/EditorToolbar.swift         ← 保留（播放控件行）
AudioRecordApp/Sources/Editor/EditorViewController.swift        ← updateUndoRedoState 扩展
```

#### 技术建议

1. 按钮用 `IndustrialCompactIconButton` 统一组件（当前 `EditToolbarButton` 是私有类，建议提出来公用）
2. 工具栏用 `NSStackView` 流式布局，`overflowMenuButton` 用 `spacing >= 0` 触发自动隐藏
3. 缩放控件 `ZoomControlsView` 从 `EditorToolbar` 移到 `EditorNavigationBar` 右侧
4. 向右对齐的「导出」「保存」用 leading spacer 推过去

---

### REQ-UI-02 · 多轨道与空轨道占位

#### 用户故事

> **作为** 编辑者，  
> **我希望** 编辑器默认显示 2 个轨道（主轨道 + 备用空轨道），并能拖拽音频文件到空轨道，  
> **以便** 可以处理多轨混音场景。

#### 现状问题

- `EditorViewController.setupEditorView()` 只创建 **1 个** `EditorAudioTrack`
- `TrackContainerView.tracks` 默认 1 元素
- 无空轨道 UI、无拖拽导入能力

#### 目标描述

- 默认创建 **2 个轨道**：
  - 轨道 1（主音轨）—— 打开文件时自动加载
  - 轨道 2（空轨道）—— 始终存在，显示占位文案
- 空轨道 UI：
  - 轨道头部：轨道编号 "2" + M（静音）/ S（独奏）按钮（disabled）
  - 轨道体：`#232327` 背景，居中显示 "拖拽音频文件到此轨道"（`IndustrialColors.textTertiary`，12pt）
  - 无波形区域，灰色虚线边框
- 拖拽交互：
  - 支持 `.wav` / `.mp3` / `.m4a` / `.aiff` 从 Finder 拖入
  - 拖入时轨道高亮（青色边框 `IndustrialColors.primary`，半透明背景 `IndustrialColors.primaryContainer`）
  - 释放后在拖入位置创建 `AudioClip`
  - 校验失败弹出 alert

#### 边界情况

| # | 边界 | 处理方式 |
|---|------|----------|
| BC-01 | 拖入非音频文件（.txt/.png） | 拒绝+显示 toast "不支持的文件格式" |
| BC-02 | 拖入超大文件（>100MB） | 进度条 + 异步加载（波形用 tile 模式） |
| BC-03 | 拖入损坏的音频文件 | alert "文件无法读取，可能已损坏" |
| BC-04 | 轨道 2 已有 clip，再拖入 | 在现有 clip 右侧追加（不替换） |
| BC-05 | 窗口全屏 | 空轨道高度按比例缩放（最小 60px） |
| BC-06 | 用户删除轨道 2 的 clip | 轨道回到空占位态 |

#### 验收用例

| ID | 场景 | 预期 |
|----|------|------|
| AC-02-01 | 打开编辑器 | 显示 2 个轨道（1 = 已加载波形，2 = 空占位） |
| AC-02-02 | 空轨道内容 | 居中显示"拖拽音频文件到此轨道"，灰色虚线边框 |
| AC-02-03 | 拖拽 .wav 到轨道 2 | 轨道高亮 → 释放 → 创建 clip → 波形显示 |
| AC-02-04 | 拖拽 .pdf 到轨道 2 | 显示 toast "不支持的文件格式" |
| AC-02-05 | 拖拽 150MB .wav | 进度条 → 波形 tile 加载 → 成功显示 |
| AC-02-06 | 拖拽损坏 .mp3 | alert "文件无法读取，可能已损坏" |

#### 涉及文件

```
AudioRecordApp/Sources/Editor/EditorViewController.swift    ← 默认 2 轨道 + 拖拽注册
AudioRecordApp/Sources/Views/Editor/TrackContainerView.swift ← tracks = [main, empty]
AudioRecordApp/Sources/Views/Editor/TrackRowView.swift      ← isEmpty 状态 (新增空轨道占位 UI)
AudioRecordApp/Sources/Editor/AudioClip.swift               ← 已有，可能需要扩展拖入路径
新增：AudioRecordApp/Sources/Editor/DragDropController.swift ← 拖拽逻辑
新增：AudioRecordApp/Sources/Editor/AudioFileValidator.swift ← 文件格式/大小校验
```

#### 技术建议

1. 轨道容器用 `NSStackView`（垂直，spacing = 0），每个轨道行是一个 `TrackRowView`
2. 拖拽注册在 `TrackRowView` 或 `TrackContainerView` 上：`registerForDraggedTypes([.fileURL])`
3. 拖拽进入用 `draggingEntered` 高亮边框，`performDragOperation` 处理释放
4. 校验用 `AVURLAsset.isPlayable` + 文件头魔数检查（wav/RIFF、mp3/ID3、m4a/ftyp）
5. 空轨道占位用 `NSView` 子类 `EmptyTrackPlaceholderView` —— `draw(_:)` 绘制虚线边框 + 居中文字

---

### REQ-UI-03 · Clip 卡片化与信息密度

#### 用户故事

> **作为** 编辑者，  
> **我希望** 每个音频片段以卡片形式显示，包含文件名、时长和边界标识，  
> **以便** 快速理解波形区的内容结构，无需查看文件列表。

#### 现状问题

- `EditorWaveformView` 绘制连续波形，无 clip 边界
- 没有文件名、时长等卡片级信息
- 选中 clip 无视觉区分

#### 目标描述

- 波形渲染从连续模式改为 **按 clip 分段**：
  - 每个 `AudioClip` 渲染为独立圆角矩形卡片
  - 卡片背景：`#2A2A2E`（`cardFrame`）
  - 卡片边框：`white@15%`（`cardStroke`），宽度 1px
  - 卡片圆角：6px
  - 卡片间距：2-4px
  - 波形在卡片内渲染
- 卡片信息：
  - 左上角：文件名（截断 >10 字符，`monospacedDigitSystemFont 9pt medium`，`textSecondary`）
  - 右上角：时长（`cardDurationOverlay`，`03:52` 格式，`monospacedDigitSystemFont 9pt`，`textTertiary`）
  - 左边缘：起止三角（▶ 小三角，通过 `draw(_:)` 的 `NSBezierPath` 绘制）
- 选中状态：
  - 边框变青色（`IndustrialColors.primary`），1.5px
  - 背景微亮（`cardSurfaceMid` = `#363638`）

#### 边界情况

| # | 边界 | 处理方式 |
|---|------|----------|
| BC-01 | clip 很窄（<30px，时长很短） | 隐藏文件名和时长标签，只显示波形 |
| BC-02 | 多个 clip 在同一轨道 | 卡片间距 2px，按时间顺序排列 |
| BC-03 | clip 跨度超出可见区域 | 正常裁剪渲染，不溢出 |
| BC-04 | 无选中 clip | 所有卡片使用默认边框色 |
| BC-05 | 缩放后卡片极宽 | 文件名始终左对齐，时长右对齐，不随缩放变形 |

#### 验收用例

| ID | 场景 | 预期 |
|----|------|------|
| AC-03-01 | 加载单个文件 | 一个 card，有文件名+时长+起止三角 |
| AC-03-02 | 点击卡片 | 边框变青色 1.5px，背景变 #363638 |
| AC-03-03 | clip 宽度 <30px | 文件名和时长隐藏，只显示波形 |
| AC-03-04 | 有多个 audio clip | 卡片间距 2-4px，按时间排列 |
| AC-03-05 | (boundary) 只有一个 clip | 仍然有卡片边框、文件名和三角标识 |
| AC-03-06 | (boundary) 全选 | 所有卡片同时高亮 |

#### 涉及文件

```
AudioRecordApp/Sources/Views/Editor/EditorWaveformView.swift  ← 重构 draw(_:) 按 clip 分段
AudioRecordApp/Sources/Views/IndustrialControls.swift         ← 新增 ClipCardColorPalette
新增：AudioRecordApp/Sources/Views/Editor/ClipCardRenderer.swift ← clip 卡片渲染器
新增：AudioRecordApp/Sources/Views/Editor/ClipLabelView.swift    ← 文件名+时长标签视图
```

#### 技术建议

1. 拆分 `EditorWaveformView.draw(_:)`：提取 `renderClipCard(clip:in:context:)` 方法
2. 卡片矩形 = `clip.timeRange` 映射到像素坐标 × `zoomLevel`
3. 文件名截断：测量字符串宽度（`NSAttributedString.size()`），超过 clip 宽的 60% 则省略号
4. 选中态用 `NSView` 级别的 `mouseDown` → `isSelected` toggle，配合 `needsDisplay` 重绘
5. `ClipCardRenderer` 是纯数据驱动的渲染器（无 `NSView`），在 `draw(_:)` 中调用

---

### REQ-UI-04 · 播放头与选区视觉强化

#### 用户故事

> **作为** 编辑者，  
> **我希望** 播放头是一条醒目的红色竖线，选区有清晰的半透明高亮和可拖动的边界把手，  
> **以便** 一眼看清当前播放位置和选区范围。

#### 现状问题

- 播放头：1px 细灰线（`IndustrialColors.outline`），与波形底色对比度低
- 选区：微弱的半透明高亮，无边框、无把手
- 无法单独拖动选区边界

#### 目标描述

- **播放头**：
  - 2px 红色竖线（`IndustrialColors.statusCritical` = `#FF4444`）
  - 贯穿整个轨道区域（含轨道头部对齐线）
  - 顶部三角指示（`draw(_:)` 画 10px 高小三角）
  - 拖动播放头可 seek（现有功能保留，强化视觉）

- **选区**：
  - 背景：半透明青色（`IndustrialColors.primary.withAlphaComponent(0.15)`）
  - 上下边框：1px 青色（`IndustrialColors.primary`，opacity 0.6）
  - 可拖动的边界把手：
    - 左边界：6×20px 半透明矩形（`IndustrialColors.primary`）
    - 右边界：6×20px 半透明矩形
    - hover 状态：把手青色，cursor 变为 `resizeLeftRight`

#### 边界情况

| # | 边界 | 处理方式 |
|---|------|----------|
| BC-01 | 选区两端极近（<10px 像素间距） | 把手重叠，显示为单把手 |
| BC-02 | 选区超出波形右边界 | 选区只绘制可见部分 |
| BC-03 | 选区+播放头重叠 | 播放头在最上层 |
| BC-04 | 缩放后把手太细 | 把手始终 6×20px（屏幕坐标，不随 zoom） |

#### 验收用例

| ID | 场景 | 预期 |
|----|------|------|
| AC-04-01 | 打开编辑器 | 播放头在 0:00 位置，红色竖线+三角 |
| AC-04-02 | 拖动波形 | 选区（半透明青背景+青色边框+把手）出现 |
| AC-04-03 | hover 选区把手 | cursor 变 resizeLeftRight，把手变亮 |
| AC-04-04 | 拖动左把手 | 选区左边界移动，背景实时更新 |
| AC-04-05 | 拖动右把手 | 选区右边界移动，背景实时更新 |
| AC-04-06 | 播放 | 播放头按时间推进 |
| AC-04-07 | 点击波形空白区 | 取消选区，把手消失 |

#### 涉及文件

```
AudioRecordApp/Sources/Views/Editor/EditorWaveformView.swift  ← 重构播放头+选区绘制
新增：AudioRecordApp/Sources/Views/Editor/PlayheadView.swift    ← 播放头统一绘制
新增：AudioRecordApp/Sources/Views/Editor/SelectionOverlay.swift ← 选区覆盖层
```

#### 技术建议

1. 播放头用独立 `CAShapeLayer`（底层 `CGMutablePath`），避免 `draw(_:)` 中混合绘制导致性能问题
2. 选区用 `SelectionOverlay`（`NSView` 子类，带 `CALayer` 蒙版），覆盖在 `EditorWaveformView` 上方
3. 把手 hit-test 用 `NSPoint` 坐标映射（`convertPoint:fromView:`），判断是否落入手把矩形
4. 拖动把手用 `mouseDragged` 事件链映射到 `TimeInterval`，回调 `delegate?.editorWaveformView(_:didChangeSelection:)`

---

### REQ-UI-05 · 中央大型时间码 + 播放控件重布局

#### 用户故事

> **作为** 编辑者，  
> **我希望** 看到中心位置有一个 48pt 的大型时间码，以及 4 个播放/跳转控件，  
> **以便** 在远近都能看清当前时间，快速操控播放。

#### 现状问题

- 计时器 `TimerLabel` 在 `ControlPanelView` 底部，13pt 字体 + 青色发光
- `EditorStatusBar.timeLabel` 13pt 字体（状态栏内）
- 播放控件：录制 + ▶ + ■（3 按钮），布局紧凑
- 无上一首/下一首

#### 目标描述

- **大型时间码**（`LargeTimeCodeLabel`）：
  - 字体：`monospacedDigitSystemFont 48pt weight(.semibold)`
  - 文字颜色：青色（`IndustrialColors.primary`，编辑态）/ 红色（`IndustrialColors.statusCritical`，播放中）
  - 位置：编辑器中部偏下（播放控件上方），水平左对齐（`leadingAnchor` 靠左 24px）
  - 字间距：1-2px（`NSAttributedString` + `kern` 属性）
  - 格式：`mm:ss.SSS`（如 `00:07.020`）

- **播放控件**（`TransportControlsView`）：
  - 4 按钮水平排列：⏮（上一首） ▶（播放/暂停） ■（停止） ⏭（下一首）
  - 每个按钮 28×28px，间距 8px
  - 位于大型时间码右侧或下方一行
  - 播放中：▶ 变 Ⅱ，时间码变红

#### 边界情况

| # | 边界 | 处理方式 |
|---|------|----------|
| BC-01 | 只有 1 个 clip（最简场景） | ⏮/⏭ disabled（灰 35%） |
| BC-02 | 在第一个 clip 播放 | ⏮ disabled |
| BC-03 | 在最后一个 clip 播放 | ⏭ disabled |
| BC-04 | 窗口缩放，时间码宽度变化 | 时间码自适应（`setContentCompressionResistancePriority`） |
| BC-05 | 时间码被长文件名遮挡 | 时间码始终在最上层（`subviews.last` 或 `layer.zPosition`） |

#### 验收用例

| ID | 场景 | 预期 |
|----|------|------|
| AC-05-01 | 打开编辑器 | 大型时间码显示 `00:00.000`，青色 |
| AC-05-02 | 点击播放 | 时间码实时更新，变红，▶ 变 Ⅱ |
| AC-05-03 | 点击停止 | 时间码停在当前位置，变青色 |
| AC-05-04 | 点击下一首 | 跳转到下个 clip 起点，自动播放 |
| AC-05-05 | 只有 1 个 clip | ⏮/⏭ disabled |
| AC-05-06 | (boundary) 点击时间码文字 | 不可交互（当前只显示），鼠标不能拖动 seek |

#### 涉及文件

```
新增：AudioRecordApp/Sources/Views/Editor/LargeTimeCodeLabel.swift  ← 大型时间码视图
新增：AudioRecordApp/Sources/Views/Editor/TransportControlsView.swift ← 4 按钮播放控件
AudioRecordApp/Sources/Views/Editor/EditorToolbar.swift            ← 重构或移到新位置
AudioRecordApp/Sources/Views/Editor/EditorStatusBar.swift          ← 移除 timeLabel 重复
AudioRecordApp/Sources/Editor/EditorViewController.swift           ← 连接播放状态
AudioRecordApp/Sources/Views/IndustrialControls.swift             ← 新增 LargeTimeCodeLabel 样式
```

#### 技术建议

1. `LargeTimeCodeLabel` 继承 `NSTextField`，使用 `monospacedDigitSystemFont` — 关键是用 `monospacedDigitSystemFont` 而非 `monospacedFont`，确保数字等宽
2. 时间码刷新用 `CADisplayLink` 或 `Timer.scheduledTimer(0.016)`
3. `TransportControlsView` 用 `NSStackView(horizontal)` 包装 4 个 `IndustrialCompactIconButton`
4. 上一首/下一首逻辑：查找 `clip.startTime` 中最近的前一个/后一个 clip，seek 到其起点

---

### REQ-UI-08 · 设计令牌细化 + 默认窗口尺寸

#### 用户故事

> **作为** 开发者，  
> **我希望** 设计令牌对齐设计稿的精确色值，窗口默认尺寸能让所有 UI 元素舒适呈现，  
> **以便** 后续开发有一致的视觉语言，不需要猜测色值。

#### 现状问题

- `IndustrialColors` 使用 Material 风格令牌（surface / surfaceContainer / surfaceContainerLow / outlineVariant 等），与设计稿的层次色值不完全对齐
- 窗口默认 1024×768（来自编译或 Info.plist），偏小

#### 目标描述

- 在 `IndustrialColors` 新增 5 个层次色值：
  ```
  trackBackground    = #232327  (轨道背景板 L1)
  cardFrame          = #2A2A2E  (L 型框架 L2)
  cardSurfaceLow     = #1B1B1F  (面级 1 — 最深背景层)
  cardSurfaceMid     = #363638  (面级 3 — 选中/高亮面)
  cardStroke         = NSColor(white: 1.0, alpha: 0.15)  (Clip 卡片边框)
  ```

- 层次自检规则（参考设计稿注意例）：
  - 面级 3 级：`#1B1B1F` → `#2A2A2E` → `#363638`（由深到浅）
  - 内容层 2 级：白字（`onSurface`）+ 灰色文字（`textSecondary`）
  - `ClipCard`：`#2A2A2E` 面 + `white@15%` 边框
  - `L 型框架`：`#2A2A2E`（轨道头部面板背景）

- 默认窗口尺寸改为 **1280×800**：
  - `AppDelegate.applicationDidFinishLaunching` 中 `window.setFrame(NSRect(x:0, y:0, width:1280, height:800), display: true)`
  - `window.minSize = NSSize(width: 1024, height: 600)`

#### 边界情况

| # | 边界 | 处理方式 |
|---|------|----------|
| BC-01 | 用户在比 1280 小的屏幕上 | 使用 `NSScreen.main?.visibleFrame` 确保不超出屏幕 |
| BC-02 | 用户自定义窗口尺寸后重启 | 用 `NSWindowFrameAutosaveName` 记住上次尺寸 |
| BC-03 | 新旧色值混用 | 禁用旧的 `IndustrialColors.surfaceContainer`，标记 deprecated |

#### 验收用例

| ID | 场景 | 预期 |
|----|------|------|
| AC-08-01 | 编译运行 | 新令牌 `trackBackground` / `cardFrame` / `cardStroke` 可访问 |
| AC-08-02 | 打开编辑器 | 轨道背景为 `#232327`，轨道头部面板为 `#2A2A2E` |
| AC-08-03 | 加载 clip | clip 卡片背景 `#2A2A2E`，边框 `white@15%` |
| AC-08-04 | 选中 clip | 卡片背景 `#363638`，边框变青 |
| AC-08-05 | 第一次启动 | 窗口尺寸 1280×800 |
| AC-08-06 | 窗口缩放后重启 | 恢复上次尺寸（AutosaveName） |
| AC-08-07 | 将窗口拖到 900×500 | 不触发崩溃/异常 |
| AC-08-08 | 窗口最小化 | 最小限制 1024×600 |

#### 涉及文件

```
AudioRecordApp/Sources/Views/IndustrialControls.swift   ← 新增 5 个令牌 + 层次文档注释
AudioRecordApp/Sources/App/AppDelegate.swift            ← 默认窗口尺寸
AudioRecordApp/Info.plist                                ← update `NSWinFrame...`
AudioRecordApp/Sources/Views/Editor/TrackRowView.swift   ← 使用 trackBackground
AudioRecordApp/Sources/Views/Editor/EditorWaveformView.swift ← 使用 cardSurface
新增：AudioRecordApp/Sources/Views/Editor/ClipCardRenderer.swift ← 使用 cardStroke
```

#### 技术建议

1. 令牌用 `static let` + 闭包计算（保持 lazy init，避免 `NSColor` 初始化时序问题）
2. 旧 token 不删除，添加 `@available(*, deprecated, message: "Use cardFrame / cardStroke instead")` 注解
3. 窗口尺寸设置最好在 `NSWindowController` 初始化时设置，而非 `AppDelegate`（便于测试）
4. 使用 `String(describing: type(of: self))` 作为 AutosaveName

---

## 4. Phase 2 · 功能完善

> **Phase 2 目标**：在 Phase 1 视觉/结构到位的基础上，完善信息展示和操作辅助。  
> **包含需求**：REQ-UI-06 / 07  
> **估计工作量**：4-5 工作日（1 人全栈）

---

### REQ-UI-06 · 状态栏信息扩展（4 段 → 8 段）

#### 用户故事

> **作为** 编辑者，  
> **我希望** 底部状态栏显示完整的上下文信息（编辑状态、选区范围、拖拽提示、吸附模式），  
> **以便** 随时了解当前编辑的上下文，做准确操作。

#### 现状问题

- `EditorStatusBar`：3 段（当前时间 + 总时长 + 采样率/声道/编辑步数）
- `StatusBarView`（主窗口）：4 段（状态点 + 状态 + 采样率 + 格式）
- 缺少：选区范围、拖拽引导、吸附状态

#### 目标描述

状态栏一行 8 段（从左到右，用 `·` 分隔）：

| # | 字段 | 内容示例 | 行为 |
|---|------|----------|------|
| 1 | 状态点 | ●（绿色 #4CD964） | 编辑中/就绪/错误三色 |
| 2 | 状态文字 | **编辑中** | 与状态点颜色一致，粗体 |
| 3 | 采样率 | 44kHz | 静态，来自音频 format |
| 4 | 声道 | 立体声 | 静态 |
| 5 | 编辑步数 | 编辑 2/20 | 跟随 `editHistory.stepCount` 更新 |
| 6 | 选区 | 选区 0:02.00-0:05.50 (3.50s) | 仅在有选区时显示，格式 mm:ss.SS |
| 7 | 拖拽提示 | 拖拽波形创建选区 | 始终显示（灰色提示文字） |
| 8 | 吸附 | S 吸附 · T 吸附 | 可点击切换开/关，青色 = 开 |

- 吸附开关：
  - 用 `NSButton` 实现 toggle 视觉（`bezelStyle = .inline` / `state = .on/.off`）
  - 默认状态：S 开 / T 开

#### 边界情况

| # | 边界 | 处理方式 |
|---|------|----------|
| BC-01 | 无选区 | 选区字段隐藏 |
| BC-02 | 状态栏宽度不足显示全部 | 优先隐藏拖拽提示 → 吸附 → 选区（按优先级） |
| BC-03 | 用户手动关闭吸附 | S/T 文字变灰，按钮变 `.off` |
| BC-04 | 音频没有零交叉（纯正弦波） | S 吸附仍然可用（只看符号变化） |

#### 验收用例

| ID | 场景 | 预期 |
|----|------|------|
| AC-06-01 | 打开编辑器 | 状态栏 8 段全显示（选区段隐藏），吸附 S/T 开 |
| AC-06-02 | 拖拽选区 | 选区字段显示 "选区 0:02.00-0:05.50 (3.50s)" |
| AC-06-03 | 清除选区 | 选区字段隐藏 |
| AC-06-04 | 点击 S 吸附 | 文字变灰，按钮 `.off` |
| AC-06-05 | 再次点击 S | 文字变青，按钮 `.on` |
| AC-06-06 | 编辑 2 次 | 编辑字段显示 "编辑 2/20" |
| AC-06-07 | 窗口缩到 900px | 拖拽提示/吸附先被隐藏，选区仍显示（如果有） |

#### 涉及文件

```
AudioRecordApp/Sources/Views/Editor/EditorStatusBar.swift ← 重构为 8 段
AudioRecordApp/Sources/Views/StatusBarView.swift          ← 与主窗口共用 statusIndicator
```

#### 技术建议

1. 8 段用 `NSStackView` + `NSTextField` + 分隔 `NSView(竖线)` 组装
2. 吸附按钮用 `NSButton` 子类 `SnapToggleButton`（复用逻辑）
3. 响应式：用 `layout()` 钩子中的 `stackView.arrangedSubviews.forEach` 控制 `.isHidden`
4. 优先隐藏顺序：拖拽提示 > S 吸附 > T 吸附 > 选区（选区即使很小也要显示）

---

### REQ-UI-07 · 吸附系统与 Marker / 节拍标记

#### 用户故事

> **作为** 编辑者，  
> **我希望** 拖动选区/播放头时能自动吸附到波形零交叉点，并在时间轴上添加自定义标记和节拍线，  
> **以便** 精确剪辑，不引入爆音。

#### 现状问题

- 无吸附逻辑
- 无 marker 系统
- 无节拍检测

#### 目标描述

##### 7a. S 吸附（Snap to Zero Crossing）

- 当 S 吸附开启：
  - 用户拖动选区边界（把手或新拖拽选区）
  - 松开鼠标时，在 ±0.05s 范围内查找最近零交叉点
  - 如果找到，选区边界自动吸附到该点（无声爆边界）
- 零交叉检测算法：
  - 帧级：`signal[i-1] * signal[i] <= 0`（符号变化）
  - 采样点级：`min(|signal[i-1:j]|)` 从 frame-level 向 ±16 采样点找最接近 0 的点
  - 缓存整个 buffer 的零交叉点位置列表（一次性扫描 O(n)，避免每次选区都重新查找）

##### 7b. T 吸附（Snap to Time Grid）

- 当 T 吸附开启：
  - 默认网格：0.1s（可切换 0.05s / 0.5s / 1s）
  - 拖动时，选区边界/播放头在释放时吸附到最近网格点
  - 视觉反馈：吸附线（浅青色虚线，200ms 临时显示）

##### 7c. Marker 标记

- 按 M 键在当前播放头位置添加 marker
- Marker 渲染：时间刻度上一个带颜色小圆点 + 标签文字
- 右键 marker → 编辑/删除
- 数据结构：

```json
{
  "id": "marker-001",
  "time": 7.02,
  "label": "intro end",
  "color": "#FF4444",
  "type": "user"
}
```

- 持久化：存 `~/.audio_record_mac/markers/<file-hash>.json`

##### 7d. 节拍/小节标记

- ⌘B 触发 BPM 检测
- 使用自相关函数（ACF）或 FFT 频谱峰值法
- 输出 `bpm` + `beatPositions: [TimeInterval]`
- 渲染为垂直灰色虚线（60% opacity gray），`beatPositions` 对应的时间刻度位置
- 主拍（第 1 拍）：稍粗 + 稍亮
- 检测结果缓存：同一文件不重复检测

#### 边界情况

| # | 边界 | 处理方式 |
|---|------|----------|
| BC-01 | 静音区（全 0 信号）无零交叉 | 不吸附，保持原始选区边界 |
| BC-02 | 极快 tempo（>200 BPM） | 不显示节拍标记（提示"无法准确检测节拍"） |
| BC-03 | 无节奏内容（环境音、语音） | 取消节拍检测，不崩溃 |
| BC-04 | 用户删除最后一个 clip，marker 移到何处 | 隐藏所有 marker |
| BC-05 | Marker + 节拍线重叠 | marker 在最上层（z-order > 节拍线） |
| BC-06 | 文件 >10 分钟 | BPM 只分析前 60 秒（避免耗时过长） |

#### 验收用例

| ID | 场景 | 预期 |
|----|------|------|
| AC-07-01 | S 开，拖拽选区边界放手 | 自动吸附到最近零交叉点 |
| AC-07-02 | S 关，拖拽选区边界放手 | 停留在放手位置，不吸附 |
| AC-07-03 | T 开（0.1s 网格），拖拽到 0:02.07 | 放手后吸附到 0:02.10 |
| AC-07-04 | T 开，拖动播放头 | 吸附线临时显示，放手后消失 |
| AC-07-05 | 按 M 键 | marker 出现在时间刻度 + 显示颜色标签 |
| AC-07-06 | 右键 marker → 编辑 | 弹出 `NSTextField` 编辑标签文字 |
| AC-07-07 | 右键 marker → 删除 | marker 从时间轴移除 |
| AC-07-08 | ⌘B 检测节拍 | 节拍线出现在时间轴上 |
| AC-07-09 | 关闭节拍（⌘⇧B） | 所有节拍线消失 |

#### 涉及文件

```
新增：AudioRecordApp/Sources/Editor/SnapController.swift       ← 吸附逻辑
新增：AudioRecordApp/Sources/Editor/MarkerManager.swift       ← marker 数据+持久化
新增：AudioRecordApp/Sources/Editor/BeatDetector.swift        ← BPM 检测
新增：AudioRecordApp/Sources/Views/Editor/MarkerOverlay.swift ← marker/节拍线渲染
AudioRecordApp/Sources/Views/Editor/EditorWaveformView.swift  ← 集成吸附反馈
AudioRecordApp/Sources/Views/Editor/EditorStatusBar.swift     ← S/T 状态显示
AudioRecordApp/Sources/Editor/EditorViewController.swift      ← 快捷键+联动
```

#### 技术建议

1. 零交叉缓存：在 `EditorViewController.loadAudio()` 加载完成后，在 `dispatch_async` 线程扫描整个 buffer，存为 `[TimeInterval: [Int]]` 数据结构（采样率映射到 position→index 搜索表）
2. BPM 检测用自相关函数 AC（不用 FFT，更简单可靠）：
   ```swift
   func detectBPM(samples: [Float], sampleRate: Double) -> Double? {
       // 1. 下采样到 500Hz
       // 2. envelope (full-wave rect + low-pass)
       // 3. ACF with window 0.5-3s (20-120 BPM)
       // 4. peak pick
   }
   ```
   - 支持 BPM 到 `beatPositions`：`beats = Array(stride(from: 0, to: totalDuration, by: 60.0 / bpm))`
3. Marker 持久化用 JSON 文件（`Codable`），路径：`~/.audio_record_mac/markers/\(file.url.sha256).json`
4. Marker/节拍线渲染：用 `CAShapeLayer` 子层添加在 `EditorWaveformView.layer`，zPosition > waveform > background

---

## 5. 里程碑与交付物

### Phase 1 · 核心视觉 + 结构升级（9-12 工作日）

| 里程碑 | 交付物 | 验收方式 |
|--------|--------|----------|
| M1 · 工具栏到位 | REQ-UI-01 完成，12+ 按钮功能可用 | 视觉对比 + 每个按钮可点击+功能连线 |
| M2 · 轨道到位 | REQ-UI-02 完成，2 轨道 + 空轨道占位 + 拖拽导入 | 拖入文件/音频 → 新 clip |
| M3 · 波形到位 | REQ-UI-03 完成，clip 卡片化渲染 | 文件名+时长+起止三角可见 |
| M4 · 播放头/选区到位 | REQ-UI-04 完成，红竖线+选区强化 | 拖拽选区 → 把手+半透明高亮 |
| M5 · 时间码/控件到位 | REQ-UI-05 完成，大时间码 + 4 播放按钮 | 时间码刷新 + 播放/停止联动 |
| M6 · 设计令牌到位 | REQ-UI-08 完成，颜色+窗口尺寸 | 令牌可引用 + 窗口 1280×800 |

**Phase 1 验收**：打开编辑器 → 一眼看到 **大时间码 + 2 轨道 + Clip 卡片 + 红播放头 + 完整工具栏**。与目标图 80% 视觉一致。

### Phase 2 · 功能完善（4-5 工作日）

| 里程碑 | 交付物 | 验收方式 |
|--------|--------|----------|
| M7 · 状态栏到位 | REQ-UI-06 完成，8 段信息栏 | 拖动选区 → 选区字段出现 |
| M8 · 吸附/标记到位 | REQ-UI-07 完成，S/T 吸附 + Marker + 节拍线 | M 键添加标记 + ⌘B 检测节拍 |

**Phase 2 验收**：完整工作流——打开文件 → 拖入另一轨道 → 创建选区 → S 吸附边界 → 添加标记 → 状态栏完全展示上下文。

---

## 6. 风险与假设

| # | 风险/假设 | 影响 | 缓解措施 |
|---|----------|------|----------|
| R1 | `EditorNavigationBar` 重构影响现有 `EditToolbarView` 的 delegate 通路 | Phase 1 M1 延迟 | 先实现新 `EditorNavigationBar`，再 `@available(deprecated)` 标记旧类，保持向后兼容 |
| R2 | Clip 卡片渲染可能导致 `draw(_:)` 性能下降（200+ clips 时） | Phase 1 M3 | 用 `CAShapeLayer` + displaysAsynchronously，只渲染可见区域 |
| R3 | 拖拽导入超大文件（>500MB）阻塞主线程 | Phase 1 M2 | 强制异步加载 + 进度条反馈 |
| R4 | BPM 检测在非音乐类音频（语音/环境音）准确率低 | Phase 2 M8 | 提供 manual BPM 设置入口 + 进度条期间允许取消 |
| R5 | 设计令牌变更导致现有 UI 颜色不一致 | Phase 1 M6 | 新令牌用独立命名空间，不删除旧令牌 |
| A1 | 现有 `AudioClip` / `SplitAudioClipCommand` 模型可以直接复用于 clip 卡片化 | 不改变后端 | 已在 Editor 中验证 |
| A2 | macOS 10.15+ 的 `AVAudioEngine` / `AVAudioFile` API 支持所有功能 | 不降级 | 当前项目已在 macOS 13+ 运行 |
| A3 | 设计稿的最上端 L1/L2/L3 视觉规范注释是文档参考，代码层不实现 | 不影响交付 | 仅提取色值 |

---

## 7. 附录

### 7a. 设计令牌完整清单

```swift
// 新增
extension IndustrialColors {
    static let trackBackground: NSColor = .rgb(0x232327)        // 轨道背景板
    static let cardFrame: NSColor      = .rgb(0x2A2A2E)         // L 型框架
    static let cardSurfaceLow: NSColor = .rgb(0x1B1B1F)         // 面级 1 (最深)
    static let cardSurfaceMid: NSColor = .rgb(0x363638)         // 面级 3 (选中态)
    static let cardStroke: NSColor     = .rgba(255,255,255,0.15) // Clip 边框
}

// 已存在的核心令牌（无损）
// IndustrialColors.surface     = main window bg
// IndustrialColors.surfaceContainerLow = control panel bg
// IndustrialColors.surfaceContainer    = sidebar bg
// IndustrialColors.primary     = accent/active (青色)
// IndustrialColors.statusCritical     = red (录制/播放头)
```

### 7b. 典型用户工作流（对标需求单）

```
1. 打开 AudioRecord
2. 选择录制源 → 录制 → 自动进入编辑器 [Phase 1]
3. 看到大时间码 + 完整工具栏 [REQ-UI-01, REQ-UI-05]
4. 看到 2 个轨道 [REQ-UI-02]
5. 拖入另一段音频到轨道 2 [REQ-UI-02]
6. 波形以 clip 卡片显示 [REQ-UI-03]
7. 拖拽创建选区（0:02-0:05）[REQ-UI-04]
8. 选区边界自动吸附零交叉 [REQ-UI-07]
9. 状态栏显示选区信息 + S/T 状态 [REQ-UI-06]
10. 按 M 添加标记，⌘B 添加节拍线 [REQ-UI-07]
11. 导出 [REQ-UI-01]
```

### 7c. 相关文件参考

```
assets/stitch_audio_record_pc/screen.png     ← 目标设计稿
assets/screenshot-main.png                   ← 现状截图
docs/AudioRecordApp_Visual_Design_Spec.md    ← 旧版视觉规范
docs/归档/old-designs/AudioRecordApp_Industrial_Design_UI_Prompt.md ← 旧版 UI Prompt
AUDIO_EDITOR_CODE_MAP.md                     ← 代码导图
```

### 7d. 分支建议

```
feature/editor-ui-还原-phase1  ← 从 main 切出，对应 REQ-UI-01/02/03/04/05/08
feature/editor-ui-还原-phase2  ← 从 phase1 merge 后切出，对应 REQ-UI-06/07
```

---

> **文档结束**。本文档由 PM_枢 在顾问模式下生成（对话 → 文档），进入任务池后由 启·执事 调度执行。
