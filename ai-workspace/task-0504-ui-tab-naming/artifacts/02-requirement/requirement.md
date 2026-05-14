# 需求文档：优化 Sidebar Tab 命名与录制完成后自动切换

> Task ID: task-0504-ui-tab-naming
> 优先级: P1 | 类型: design | 路由: 绘·设计 → 矩·架构

---

## 1. 背景

SidebarView 内含两个 Tab 页（`SidebarView.swift` 第 138-169 行）：
- Tab1: **"Audio Recorder"** — 包含录制目标选择（系统声音/进程）和麦克风面板
- Tab2: **"Saved Files"** — 已录制文件列表

**当前问题**：
- "Audio Recorder" 与应用本身名称重复，用户无法从 Tab 名理解其功能
- 用户录制完成后（`handleRecordingComplete`），新文件添加到 Tab2 但用户可能还停留在 Tab1
- 用户需要手动切换 Tab 才能看到刚录完的文件，缺少视觉引导
- Tab 切换无过渡动画，显得生硬

## 2. 目标

优化 Tab 命名使语义清晰，并在录制完成后自动引导用户关注新文件。

## 3. 功能需求

### 3.1 Tab 命名优化
- [ ] 评估命名方案：
  - 方案 A: "INPUT" / "FILES"（简洁英文，符合 Industrial Design 大写标题风格）
  - 方案 B: "录制源" / "录音"（中文直观）
  - 方案 C: "SOURCE" / "RECORDINGS"（专业音频术语）
- [ ] 图标是否需要同步更换（当前: waveform / folder）

### 3.2 录制完成后自动切换
- [ ] 录制完成时（`handleRecordingComplete` 回调后），自动切换到文件 Tab
- [ ] 切换后新文件行高亮闪烁 2-3 秒（引导注意力）
- [ ] 如果用户正在查看文件 Tab（已在 Tab2），则只高亮，不做 Tab 切换

### 3.3 新文件视觉引导
- [ ] 新增文件时，文件行使用 primaryContainer 青色背景渐现 → 渐隐动画
- [ ] 或使用左侧指示条脉冲动画（复用 IndustrialProcessRowView 的 indicatorLayer）
- [ ] 动画持续 2-3 秒后恢复正常样式

### 3.4 可选：取消 Tab 改为分栏
- [ ] 评估是否将 Sidebar 拆为上下两部分（上部录制源固定、下部文件列表可滚动）
- [ ] 如果采用此方案，需要评估 240px 宽度下的垂直空间分配

## 4. 设计约束

- Tab 标题必须使用大写（Industrial Design 的 `IndustrialTypography.label` 风格）
- 动画时长遵循 `IndustrialAnimation.standard`（当前未定义则使用 250ms）
- 高亮颜色使用 `IndustrialColors.primaryContainer`（#22d3ee 青色）

## 5. 技术约束

| 文件 | 修改点 |
|------|--------|
| `SidebarView.swift:138-144` | Tab1 的 title 和 icon |
| `SidebarView.swift:163-169` | Tab2 的 title 和 icon |
| `TabContainerView.swift` | 可能需要新增 `selectTab(id:animated:)` 方法 |
| `MainWindowView.swift:202-204` | `addRecordedFile` 后触发 Tab 切换 |
| `MainViewController.swift:427-457` | `handleRecordingComplete` 中调用自动切换 |
| `RecordedFilesView.swift` | 新增文件高亮动画方法 |

## 6. 验收标准

| # | 条件 | 通过标准 |
|---|------|---------|
| 1 | Tab 命名 | 用户一眼可理解每个 Tab 的用途 |
| 2 | 自动切换 | 录制完成后 ≤500ms 自动跳到文件 Tab |
| 3 | 高亮动画 | 新文件有明显但不刺眼的引导动画 |
| 4 | 不强制中断 | 如用户在 Tab2 操作中（如选中某文件），不打断用户 |
| 5 | 构建通过 | 编译无错误 |

## 7. 参考

- macOS Finder 的"最近使用"文件高亮行为
- Slack 新消息到达时的 unread badge 动画
- GarageBand 录制完成后的轨道闪烁
