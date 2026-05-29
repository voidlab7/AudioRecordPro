# QA（鉴） — 领域知识

> 最后更新: 2026-05-17

## 知识条目

### K-001 本项目是 macOS 原生 App（Swift/AppKit），不是 Web
- 无法用 Playwright 浏览器测试
- QA 方法：编译验证 + 代码逻辑追踪 + 运行时测试
- 自绘控件体系：`IndustrialButtonView`、`IndustrialIconButtonView`、`IndustrialToggleView` 等，全部自定义 NSView
- 不走 Interface Builder / Storyboard，纯代码布局

### K-002 IndustrialIconButtonView 硬编码 64×64
- 路径：`AudioRecordApp/Sources/Views/IndustrialControls.swift:395-396`
- `widthAnchor.constraint(equalToConstant: 64)` + `heightAnchor.constraint(equalToConstant: 64)`
- 不适合放在 <64px 高度的容器中（导航栏 44px / 操作栏 44px / 工具栏 48px）
- 使用场景：录制页的大按钮（录制/停止/播放）。编辑器内不应复用

### K-003 编辑器架构概览
- `EditorViewController`：非 NSViewController 子类，纯 Swift class，管理 editorView（NSView）
- 4 个子视图：EditorNavigationBar(44px) → EditorWaveformView(flex) → EditorToolbar(48px) → EditorStatusBar(24px)
- 撤销栈：EditHistory（Command 模式，max 20 步）
- 4 个 Command：TrimCommand / SilenceTrimCommand / NormalizeCommand / FadeCommand
- 入口：RecordedFilesView hover 编辑按钮 → delegate 链 → MainViewController.enterEditor
- 页面切换：MainWindowView.showEditor（isHidden 方案，不 remove/add）

### K-004 波形视图交互模型
- EditorWaveformView 的 DragMode 枚举：`none / panScroll / leftHandle / rightHandle / seeking`
- **缺失**：没有 `.creating`（创建新选区）模式 — 这是 BUG-001 的根因
- 选区存储：`selectionStart: TimeInterval?` + `selectionEnd: TimeInterval?`
- 坐标变换：`timeToPixel()` / `pixelToTime()` 基于 visibleStartTime + visibleDuration

### K-005 音频数据流
- 加载：AVAudioFile → AVAudioPCMBuffer（全量到内存）
- 编辑：Command.execute(buffer) → 返回新 buffer → 替换 audioBuffer
- 渲染：loadAudio(buffer) → 降采样到 peaks 数组 → drawWaveformBars
- 保存：AVAudioFile(forWriting) → write(buffer) → 覆盖原文件（保存前有 .backup 备份）
