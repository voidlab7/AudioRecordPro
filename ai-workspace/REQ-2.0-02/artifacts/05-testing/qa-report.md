# QA 测试报告 — REQ-2.0-02

> 任务编号：REQ-2.0-02
> 阶段：05-testing
> 测试时间：2026-05-19
> 测试人：鉴（QA_鉴）
> 关联设计：[design-spec.md](../03-design/design-spec.md)
> 关联实现：[shift-left-report.md](../04-development/shift-left-report.md)

---

## 一、测试范围

本次修改涉及 3 个 Swift 文件：

| 文件 | 修改内容 | 影响范围 |
|------|----------|----------|
| `StatusBarView.swift` | 新增 `updateRecordingState(_:)` 方法；修改 `updateStatus(_:)` 调用新方法 | 状态栏文字显示 |
| `ControlPanelView.swift` | 修改 `updateRecordingState(_:)` 方法，增加按钮 `isHidden` 控制 | 底部控制面板按钮显示 |
| `MainWindowView.swift` | `ViewMode` 枚举新增 `.playbackReview`；修改 `switchToMode()` / `updateRecordingState()` / `showRecordingCompleteActions()` / `loadWaveform()` | 主窗口工作区切换逻辑 |

---

## 二、测试用例

### 2.1 状态栏显示（StatusBarView）

| 编号 | 前置状态 | 操作 | 期望结果 | 实际结果 | 状态 |
|------|----------|------|----------|----------|------|
| TC-01 | 启动 App | 无操作 | 状态栏显示 `● 准备就绪`；圆点绿色 | ⏳ 待测试 | |
| TC-02 | 启动 App | 点击 REC | 状态栏显示 `● 录制中`；圆点红色 | ⏳ 待测试 | |
| TC-03 | 录制中 | 点击停止 | 状态栏显示 `● 回看态`；圆点青色 | ⏳ 待测试 | |
| TC-04 | 回看态 | 点击播放 | 状态栏显示 `● 播放中`；圆点青色 | ⏳ 待测试 | |
| TC-05 | 任意状态 | 触发错误 | 状态栏显示 `● 错误`；圆点红色 | ⏳ 待测试 | |
| TC-06 | `.preparing` 状态 | 触发准备中 | 状态栏显示 `● 准备中`；圆点黄色 | ⏳ 待测试 | |
| TC-07 | `.stopping` 状态 | 触发停止中 | 状态栏显示 `● 停止中`；圆点黄色 | ⏳ 待测试 | |

### 2.2 控制面板按钮显示（ControlPanelView）

| 编号 | 当前 RecordingState | 期望按钮显示 | 实际结果 | 状态 |
|------|----------------------|----------------|----------|------|
| TC-08 | `.idle` | 只显示 REC 按钮；播放/停止隐藏 | ⏳ 待测试 | |
| TC-09 | `.preparing` | 显示停止按钮；REC 按钮禁用 | ⏳ 待测试 | |
| TC-10 | `.recording` | 显示停止按钮；REC 内方块可见 | ⏳ 待测试 | |
| TC-11 | `.stopping` | 停止按钮禁用；REC 内方块可见 | ⏳ 待测试 | |
| TC-12 | `.playing` | 显示播放/暂停 + 停止；REC 隐藏 | ⏳ 待测试 | |
| TC-13 | `.error` | 显示 REC 按钮；播放启用；停止禁用 | ⏳ 待测试 | |

### 2.3 工作区切换（MainWindowView）

| 编号 | 操作 | 期望工作区 | 实际结果 | 状态 |
|------|------|------------|----------|------|
| TC-14 | 启动 App | `.idle`（准备态）| ⏳ 待测试 | |
| TC-15 | 点击 REC | `.recording`（录制态）| ⏳ 待测试 | |
| TC-16 | 点击停止 | `.playbackReview`（回看态）| ⏳ 待测试 | |
| TC-17 | 回看态点击"编辑" | `.editing`（编辑态）| ⏳ 待测试 | |
| TC-18 | 加载已录文件 | `.playbackReview`（回看态）| ⏳ 待测试 | |
| TC-19 | 录制错误 | `.idle`（回到准备态）| ⏳ 待测试 | |

---

## 三、手动测试步骤

### 3.1 环境准备

1. 打开 Xcode
2. 打开 `AudioRecordApp.xcodeproj`
3. 选择 `AudioRecordApp` scheme
4. 点击 Build & Run

### 3.2 测试流程

#### 流程 1：首次录制全流程

```
1. 启动 App
   → 验证：状态栏显示 "● 准备就绪"
   → 验证：只显示 REC 按钮

2. 点击 REC 按钮
   → 验证：状态栏显示 "● 录制中"
   → 验证：REC 按钮内方块可见（停止样式）
   → 验证：播放按钮隐藏

3. 录制 5 秒后点击停止
   → 验证：状态栏显示 "● 回看态"
   → 验证：显示播放/暂停 + 停止按钮
   → 验证：显示 [编辑] [导出] [转文字] 快捷栏

4. 点击 [编辑]
   → 验证：进入编辑态（editToolbarView 可见）

5. 点击已录文件
   → 验证：进入回看态（不是直接编辑态）
```

#### 流程 2：按钮显示验证

```
1. 启动 App（.idle）
   → 截图：只显示 REC 按钮

2. 点击 REC（.recording）
   → 截图：显示停止按钮；REC 内方块可见

3. 点击停止（.playing）
   → 截图：显示播放/暂停 + 停止按钮

4. 触发错误（.error）
   → 截图：显示 REC 按钮；播放启用
```

---

## 四、已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| `ViewMode` 枚举新增 `.playbackReview`，但旧代码可能假设只有 3 种状态 | 切换逻辑错误 | 已修改所有 `switch currentMode` 处，添加 `.playbackReview` 分支 |
| `ControlPanelView` 按钮 `isHidden` 可能在约束动画中表现异常 | UI 闪烁 | 需在 Xcode 中实际测试 |
| `quickActionsBar` 在 `.playbackReview` 时显示，但 [编辑] 按钮可能未绑定动作 | 点击 [编辑] 无反应 | 需验证 `quickEditButton` 的 `onClick` 是否正确切换到 `.editing` |

---

## 五、测试结论

> ⏳ **待 Xcode 环境执行手动测试后填写**

### 5.1 功能通过情况

- [ ] 状态栏显示正确
- [ ] 控制面板按钮显示正确
- [ ] 工作区切换逻辑正确

### 5.2 发现 Bug 列表

> 待测试后填写

### 5.3 建议

> 待测试后填写

---

**报告版本**：v0.1（测试前模板）
**下一步**：在 Xcode 环境中执行手动测试，填写实际结果
