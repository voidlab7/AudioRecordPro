# 流程总结 — REQ-2.0-02

> 任务编号：REQ-2.0-02
> 任务标题：启动默认录制准备态 UI 重构
> 完成时间：2026-05-19
> 负责人：枢（需求）→ 绘（设计）→ 铸（开发）→ 鉴（测试）→ 枢（总结）

---

## 一、任务概述

**背景**：用户反馈启动 App 后的首屏 UI 不符合需求，整体布局偏"空编辑器"而非"录音机"。

**目标**：重构首屏 UI，使其符合"录音优先，编辑是第二工作区"的设计理念。

**核心决策**：
> 默认进入录制准备态，不是编辑器。录完先回看，再按需进入编辑器。

---

## 二、各阶段产出

### 2.1 02-需求阶段（枢）

**产出文件**：`docs/requirements/REQ-2.0-02.md`（软链接到 `ai-workspace/REQ-2.0-02/artifacts/02-requirement/PRD.md`）

**核心内容**：
1. 现状问题：首屏像空编辑器、状态文字矛盾、编辑能力过早暴露
2. 正确首屏定义：打开即进入"录制准备态"，只服务"开始录音"
3. UI 重设计：首屏结构、三种状态、按钮显示规则、左侧面板层级
4. 验收标准：5 条功能验收 + 4 条设计验收

### 2.2 03-设计阶段（绘）

**产出文件**：`ai-workspace/REQ-2.0-02/artifacts/03-design/design-spec.md`（软链接 `eng-review.md`）

**核心内容**：
1. 设计背景与问题定义
2. 设计目标与原则（引用 `设计_绘/SOUL.md`）
3. 信息架构重设计：三种工作区模型（RecordingIdle / RecordingActive / PlaybackReview）
4. 具体 UI 组件设计：左侧面板、中间区域、底部控制栏、顶部状态栏
5. 交互设计：核心用户旅程、边界情况处理
6. 与当前实现的差异分析
7. 验收标准

### 2.3 04-开发阶段（铸）

**产出文件**：`ai-workspace/REQ-2.0-02/artifacts/04-development/shift-left-report.md`

**修改文件**：
| 文件 | 修改内容 |
|------|----------|
| `StatusBarView.swift` | 新增 `updateRecordingState(_:)` 方法，精确显示状态文字 |
| `ControlPanelView.swift` | 修改 `updateRecordingState(_:)` 方法，按状态隐藏/显示按钮 |
| `MainWindowView.swift` | `ViewMode` 枚举新增 `.playbackReview`；修改 `switchToMode()` / `updateRecordingState()` / `showRecordingCompleteActions()` / `loadWaveform()` |

**实现要点**：
1. 状态栏根据 `RecordingState` 精确显示状态文字和圆点颜色
2. 控制面板在 `.idle` 状态时只显示 REC 按钮（播放/停止隐藏）
3. 工作区模型从三态（idle/recording/editing）扩展为四态（idle/recording/playbackReview/editing）
4. 录制完成后自动进入 `.playbackReview`（回看态），不自动进入 `.editing`

### 2.4 05-测试阶段（鉴）

**产出文件**：`ai-workspace/REQ-2.0-02/artifacts/05-testing/qa-report.md`

**测试用例**：19 个测试用例，覆盖：
1. 状态栏显示（TC-01 ~ TC-07）
2. 控制面板按钮显示（TC-08 ~ TC-13）
3. 工作区切换（TC-14 ~ TC-19）

**状态**：⏳ 待 Xcode 环境执行手动测试

### 2.5 06-总结阶段（枢）

**产出文件**：本文档

---

## 三、文件变更清单

### 3.1 新增文件

| 文件 | 用途 |
|------|------|
| `docs/requirements/REQ-2.0-02.md` | 需求文档（软链接） |
| `ai-workspace/REQ-2.0-02/artifacts/02-requirement/PRD.md` | 需求文档正本 |
| `ai-workspace/REQ-2.0-02/artifacts/03-design/design-spec.md` | 设计文档正本 |
| `ai-workspace/REQ-2.0-02/artifacts/03-design/eng-review.md` | 设计文档软链接（门禁期望） |
| `ai-workspace/REQ-2.0-02/artifacts/04-development/shift-left-report.md` | 左移检查报告 |
| `ai-workspace/REQ-2.0-02/artifacts/05-testing/qa-report.md` | QA 测试报告 |
| `ai-workspace/REQ-2.0-02/artifacts/06-summary/workflow-summary.md` | 流程总结（本文档） |

### 3.2 修改文件

| 文件 | 修改内容 |
|------|----------|
| `docs/requirements/README.md` | 新增 V2.0 需求列表，包含 REQ-2.0-02 |
| `docs/AudioRecordApp知识库.md` | TASK-UI-01 指向新需求单 |
| `AudioRecordApp/Sources/Views/StatusBarView.swift` | 新增 `updateRecordingState(_:)` 方法 |
| `AudioRecordApp/Sources/Views/ControlPanelView.swift` | 修改 `updateRecordingState(_:)` 方法，增加按钮 `isHidden` 控制 |
| `AudioRecordApp/Sources/Views/MainWindowView.swift` | `ViewMode` 枚举新增 `.playbackReview`；修改多处模式切换逻辑 |

---

## 四、已知风险与待办

### 4.1 已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| `.playbackReview` 是新状态，与旧代码可能不兼容 | 切换逻辑错误 | 已修改所有 `switch currentMode` 处，添加 `.playbackReview` 分支 |
| `ControlPanelView` 按钮 `isHidden` 在约束动画中表现 | UI 闪烁 | 需在 Xcode 中实际测试 |
| `quickActionsBar` 的 [编辑] 按钮可能未绑定正确动作 | 点击无反应 | 需验证 `quickEditButton.onClick` 是否正确切换到 `.editing` |

### 4.2 待办事项

| 编号 | 内容 | 优先级 | 负责人 |
|------|------|--------|----------|
| OPEN-01 | 在 Xcode 中执行手动测试（19 个测试用例） | P0 | 鉴 |
| OPEN-02 | 修复测试中发现的问题 | P0 | 铸 |
| OPEN-03 | 编译检查（`xcodebuild`） | P1 | 铸 |
| OPEN-04 | SwiftLint 检查 | P1 | 铸 |
| OPEN-05 | 更新 `docs/requirements/REQ-2.0-02.md` 实现状态 | P2 | 枢 |

---

## 五、经验总结

### 5.1 做得好的

1. **第一性原理思考**：从"用户打开 App 的第一意图是什么"出发，推导出"首屏必须是录音机，不是编辑器"
2. **竞品分析精准**：`Audio Capture Pro` 证明录制产品要极简；`剪映` 证明编辑器可以是时间线；不盲目照搬
3. **门禁驱动开发**：每个阶段结束都运行 `weiyige-cli gate` 检查，确保产物合格才进入下一阶段
4. **文档软链接**：`docs/requirements/REQ-2.0-02.md` 软链接到正本，避免两份不同步

### 5.2 可以改进的

1. **Swift 代码修改前应该先编译检查**：当前环境无 `xcodebuild`，无法在修改后立即编译检查，只能依赖后续手动测试
2. **`ViewMode` 枚举应该更早重构**：在需求阶段就应该明确"三态（idle/recording/editing）不符合设计"，应该更早引入 `.playbackReview`
3. **QA 测试用例应该更早编写**：在开发阶段就应该编写测试用例，而不是等到测试阶段才写

---

## 六、下一步建议

1. **立即**：在 Xcode 中打开项目，执行 `qa-report.md` 中的 19 个测试用例
2. **短期**：修复测试中发现的问题，然后编译打包测试
3. **中期**：继续推进其他 V2.0 UI 重构需求（REQ-2.0-01 等）
4. **长期**：建立自动化 UI 测试（XCTest + XCUI），减少手动测试成本

---

**总结版本**：v1.0
**下一步**：等待 Xcode 环境手动测试结果
