# 需求文档：优化默认窗口尺寸适配 Sidebar 布局

> Task ID: task-0504-ui-window-size
> 优先级: P1 | 类型: design | 路由: 绘·设计 → 矩·架构

---

## 1. 背景

当前窗口配置（`AppDelegate.swift` 第 122 行）：
- 初始尺寸：800×500
- 最小尺寸：800×500
- Sidebar 宽度：240px（固定）
- 内容区可用：560px

内容区的空间分配：
- WaveformView: 42% 高度 ≈ 210px
- TracksView: 弹性（约 84px）
- ControlPanel: 固定 150px
- StatusBar: 固定 28px

**问题**：
- 内容区 560px 宽度对于波形显示偏窄，尤其在长时间录制时
- TracksView 仅 84px 高度，只能显示 1-2 个轨道信息
- 13 寸 MacBook（分辨率 2560×1600 逻辑 1440×900）上 800×500 显得小
- 对比：Logic Pro 默认 1280×800，Audacity 默认 960×640

## 2. 目标

调整窗口默认尺寸和内部比例，使各功能区域获得合理的展示空间。

## 3. 功能需求

### 3.1 窗口尺寸
- [ ] 评估新的默认尺寸方案（候选：960×600 / 1024×600 / 1024×640）
- [ ] 评估新的最小尺寸（候选：800×500 保持 / 调整为 860×520）
- [ ] 确保在 13 寸 MacBook 上默认尺寸不超过可用屏幕 80%

### 3.2 Sidebar 宽度
- [ ] 评估是否从 240px 调整到 260px 或 280px
- [ ] 确保调整后进程列表行不会文字截断

### 3.3 内容区比例
- [ ] 评估 WaveformView 高度比例（当前 42%，是否改为 38% 或固定最大值）
- [ ] 评估 ControlPanel 高度（当前 150px，是否可压缩，见另一任务）
- [ ] TracksView 至少保证 120px 可用高度

### 3.4 响应式行为（可选增强）
- [ ] 窗口宽度 < 900px 时是否自动折叠 Sidebar（依赖 sidebar-collapse 任务）
- [ ] 窗口缩放时各区域按什么规则重新分配空间

## 4. 设计约束

- 保持 Industrial Design 风格的紧凑专业感
- 不能让窗口看起来"空旷"
- 默认尺寸应在未全屏时看起来协调（非全屏使用场景占多数）

## 5. 技术约束

| 文件 | 修改点 |
|------|--------|
| `AppDelegate.swift:122` | `windowSize = NSMakeRect(0, 0, ?, ?)` |
| `AppDelegate.swift:171` | `window.minSize = NSSize(width: ?, height: ?)` |
| `IndustrialDesignTokens.swift:287` | `sidebarWidth: CGFloat = ?` |
| `MainWindowView.swift:93` | sidebar width 约束 |
| `MainWindowView.swift:100` | waveformView multiplier 0.42 |
| `MainWindowView.swift:118` | controlPanelView height 150 |

## 6. 验收标准

| # | 条件 | 通过标准 |
|---|------|---------|
| 1 | 默认显示 | 启动后各区域内容无截断、无拥挤 |
| 2 | 13寸兼容 | 在 1440×900 屏幕上窗口居中，不超出屏幕 |
| 3 | 16寸显示 | 在 1728×1117 屏幕上比例协调 |
| 4 | 最小尺寸 | 缩小到最小时所有功能仍可操作 |
| 5 | TracksView | 至少可显示 2 个轨道行 |
| 6 | 构建通过 | `build-app.sh` 编译无错误 |

## 7. 参考对比

| 应用 | 默认尺寸 | Sidebar 宽度 |
|------|---------|-------------|
| Logic Pro X | ~1280×800 | 250px |
| GarageBand | ~1024×640 | 200px |
| Audacity | ~960×640 | 无固定sidebar |
| AudioRecord（当前） | 800×500 | 240px |
