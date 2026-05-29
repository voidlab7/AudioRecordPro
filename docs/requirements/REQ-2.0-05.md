# REQ-2.0-05 录制完成后自动进入编辑器（去除 playbackReview 中间态）

## 版本：V2.0 | 优先级：P0 | 状态：⬜ 待实现

## 背景

当前录制完成后的行为：
1. 显示 `quickActionsBar` 浮层（包含"编辑"/"导出"按钮）
2. 进入 `playbackReview` 中间态
3. 8 秒后浮层自动消失
4. 用户需要手动点击"编辑"按钮才能进入编辑器

**问题**：
- 浮层弹窗视觉突兀，像临时贴片
- 8 秒自动消失，用户可能错过
- 多了一个无意义的中间态，增加认知负担
- 不符合竞品惯例（剪映/GarageBand/Voice Memos 均无此中间步骤）

## 需求描述

录制完成后，**直接通过动画过渡进入完整编辑器视图**（EditorViewController），无需任何用户操作。

### 状态机变更

```
变更前：idle → recording → playbackReview → (用户点击) → editing → idle
变更后：idle → recording → editing → idle
```

- 删除 `playbackReview` 模式
- 删除 `quickActionsBar` 浮层及相关代码
- 录制完成后直接调用 `enterEditor(file:)`

### 过渡动画

复用已有的 `showEditor()` 动画：
- `recordingContentView` 隐藏
- `editorView` 以 cross-dissolve 淡入（200ms easeOut）
- 编辑器加载完整波形（已有 tile 渐进加载 + skeleton 动画）

### 编辑器中的录制入口

进入编辑器后，用户仍可快速开始新录制：
- 编辑器导航栏有「← 返回」按钮 → 回到录制准备态
- `Cmd+R` 快捷键 → 退出编辑器并开始新录制
- 侧边栏切换音源 → 自动退出编辑器

### 导出按钮

- 导出按钮在标题栏右上角**一直存在**
- 进入编辑器后自动激活（已有逻辑：`titleBarView.setExportEnabled(true)`）
- 无需额外 UI 承载导出入口

## 代码变更范围

| 文件 | 变更 |
|------|------|
| `MainWindowView.swift` | 删除 `quickActionsBar` 相关属性和方法；删除 `ViewMode.playbackReview` case；删除 `showRecordingCompleteActions()`/`hideRecordingCompleteActions()` |
| `MainWindowView.swift` | `setupQuickActionsBar()` 方法删除 |
| `MainViewController.swift` | 录制完成回调中直接调用 `enterEditor(file:)` 替代 `showRecordingCompleteActions()` |

## 验收标准

- [ ] 录制停止后，200ms 内自动过渡到编辑器视图
- [ ] 无任何弹窗/浮层/中间态出现
- [ ] 编辑器中波形正确加载并可操作
- [ ] 编辑器导航栏有「← 返回」按钮可回到录制态
- [ ] `Cmd+R` 在编辑器中可退出并开始新录制
- [ ] 导出按钮在编辑器中可用
- [ ] `ViewMode` 枚举中不再有 `playbackReview` case
- [ ] `quickActionsBar` 相关代码完全删除
- [ ] 编译通过，无 warning

## 竞品参考

| App | 录制完成后行为 |
|-----|---------------|
| 剪映 | 素材直接进时间线，无中间步骤 |
| GarageBand | 轨道波形就地固定，直接可编辑 |
| Voice Memos | 波形就地静态化，文件出现在列表中 |
| Audacity | 波形就地保留，直接可编辑 |

## 设计决策记录

| 日期 | 决策 | 理由 |
|------|------|------|
| 2026-05-27 | 去除 playbackReview 中间态 | 多余步骤，增加认知负担，不符合竞品惯例 |
| 2026-05-27 | 录制完成直接进入 EditorViewController | 零决策成本，路径最短，符合"录制+轻编辑"产品定位 |
| 2026-05-27 | 删除 quickActionsBar | 浮层弹窗视觉突兀，8秒消失可能错过，不如直接进编辑器 |
