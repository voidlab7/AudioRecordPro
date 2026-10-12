# 需求队列（TODOS）— Loop 需求池

> **唯一状态真相**：单子/验收标准/状态/证据。开发方式唯一：`docs/LOOP.md`（宪法）；自动加载版 `.codebuddy/rules/loop-protocol.md`。
> 状态六态：todo / doing / self-verify / ready-for-review / blocked / done。
> 老板只做三件事：签标准（定义）、拍板（裁决）、看证据（签收）。
> **签收即归档**（2026-10-12 老板定）：单子签收当天，正文迁 `docs/归档/TODOS-done-YYYY-MM.md`，本池只留索引行——控制每次「重读池」的上下文成本。
> **编号规范**：已移 `docs/LOOP.md §十一`（TYPE-NNN 全局递增、入池查重、历史单不回改）。品牌：**Loocap｜路文**（2026-10-11 起，旧名 Tapture 见 `docs/产品/品牌更名-2026-10-11.md`，历史单不回改）。
> **双会话分工**：入池权归需求台；执行侧状态上限 `ready-for-review`；小粒度精确编辑；写前重读；**单间必重读池**（2026-10-12 增，铁律 4）。

## 池速览（一行一单，签收/入池即更新此表）

| 单号 | 标题 | P | 状态 | 备注 |
|---|---|---|---|---|
| LOOP-05 | XCUITest 11 个失败修复 ≡INFRA-001 | P1 | **blocked** | 等老板在 WorkBuddy 外跑 `scripts/test-ui.sh` |
| LOOP-08 | 录音准备态与实时采集态视觉分离 ≡UI-002 | P1 | **blocked** | 主链路已通，细项留日常观察 |
| UI-008 | DB METER 电平列顶穿底栏 + 删 Not Monitoring 浮层 | P2 | **doing** | 标准 10-12 16:24 老板签（「签收」），实施中 |
| LOOP-01~04 | 测试盘点 / localized 断裂 / 计时器脱节 / 单测卡死 | P0 | done ✅ | 09-20/21 签收 |
| LOOP-06 | localized %@ 残留清理 ≡FIX-001 | P0 | done ✅ | 10-11 签收 |
| LOOP-07 | 待录制界面隐藏时间刻度 ≡UI-001 | P2 | done ✅ | 10-11 签收 |
| FIX-002 | EditorStatusBar 裸 Int 崩溃 | P0 | done ✅ | 10-11 真机签收 |
| FIX-003 | 点击波形选点播放从头开始 | P1 | done ✅ | 10-11 签收 |
| UI-003 | 主界面视觉重构（Stitch v2） | P1 | done ✅ | 10-12 13:15 签收 |
| UI-004 | 侧栏初始化宽度 260pt | P2 | done ✅ | 10-12 13:15 签收 |
| UI-005 | 红钮画布视觉居中 | P2 | done ✅ | 10-12 13:15 签收 |
| FEAT-001 | 语音转文字（双引擎+导出 MD） | P1 | done ✅ | 10-11 16:12 签收 |
| INFRA-002 | 稳定开发签名（LoocapDev 证书） | P1 | done ✅ | 10-12 13:54 签收 |

> done 单正文全部在 `docs/归档/TODOS-done-2026-10.md`；更早 backlog 在 `docs/归档/TODOS-archive-20260920.md`（捡回规则：补验收标准回池，P0 > P1 > P2）。

---

## 活跃单

### LOOP-05 XCUITest 11 个失败修复（mock 注入失效） | P1 | [doing] ≡INFRA-001

**预估**：1天

> 代码部分已完成：mock 进程注入（1001-1006 Chrome/Safari/Music/Zoom/Teams/Slack）+ mock 录制状态机（MainViewController，--ui-testing 参数）。
> 阻塞原因（2026-10-11 更新，两层）：① XCUITest runner 的辅助功能授权存疑（历史报「Not authorized for performing UI testing actions」，今日未能推进到该步）；② **WorkBuddy 沙箱与 xcodebuild 不兼容**——`xcodebuild test` 内部依赖嵌套 `sandbox-exec` + 写 `~/Library/Developer/DerivedData`，在 WorkBuddy 沙箱内必挂 `sandbox_apply: Operation not permitted`（2026-10-11 连跑 3 轮实证：原样跑、沙箱外标志 + workspace 内 derivedDataPath + 禁自动包解析，三种打法同一死法，拦截点分别为 DerivedData 删除 / 包解析 / ~/.swiftpm/security）。按刹车规则 3 次止损。
> 解除路径（人工，二选一）：A. 老板在 WorkBuddy 之外的普通终端跑一次 `bash scripts/test-ui.sh`（验证 AX 授权 + mock 效果）；B. ~~研究给 WorkBuddy 会话放行 xcodebuild 所需路径/权限后重试~~（**2026-10-12 14:24 已证死**：沙箱外直跑 + `env -i` 干净环境两种打法同死 `sandbox-exec: sandbox_apply: Operation not permitted`——WorkBuddy 沙箱在系统层禁止子进程嵌套建 seatbelt 沙箱，会话内无解，只剩路径 A）。解除后说「继续跑 loop」续验。
> 补充证据（2026-09-26）：CUA helper 的**屏幕录制**授权也失效——Tapture/系统授权弹窗截图全黑、曾拍成功的终端重截报「窗口截图失败」，判定 TCC 授权整体损坏（本地 DR 签名 helper 同 bundle id 多拷贝互踩）。人工授权时「辅助功能 + 屏幕录制」一起勾，可同时解锁本单与 CUA 截图；授权后需重启 helper 进程生效。

> 来源：LOOP-02 自验发现。UI 测试第一次真跑：19 执行 8 过 11 挂，11 个失败全是「ProcessRow-1001 找不到」（V2.0 重构后 mock 进程注入机制/accessibility 标识失效）+ RecordingFlow 停止后按钮断言。

**做什么**：恢复 App 的测试 mock 注入机制（launch arguments）或更新测试适配 V2.0 视图结构，让 `test-ui.sh` 全绿。

**不做什么**：不改产品功能代码

**验收标准**：
- [ ] `test-ui.sh` 19/19 PASS，或逐项判定「测试已无意义」并删除且记录理由
- [ ] 日志落盘 `test_logs/ui_test_*.log` 完整

---

### LOOP-08 录音准备态与实时采集态视觉分离 | P1 | [blocked] ≡UI-002

> 2026-10-10 老板确认：未录时用居中波形图标、准备录制标题和所选音源提示替代基线/假波形/时间轴；右侧电平置灰标未监测；底部红色按钮旁标开始录制且计时中性灰；仅真实录制时显示波形、时间轴及收到数据后的实时电平，录制静音时用灰色零位线。
> 2026-10-11 实施并构建；`scripts/test_sdk.sh` 77/77 PASS，`scripts/test-snapshot.sh` 2/2 PASS（基线已更新）；运行实例 PID 51418 的 AX 确认 `Not Monitoring` 和 `Start Recording`。UI test 失败：`Timed out while enabling automation mode`；CUA `get_next_action` 返回 VLM HTTP 403。中央画布为自绘，AX 不提供视觉内容，故不得把 AX 当截图验收。待 UI 测试权限恢复、视觉模型恢复或老板手动验证后再签收；真实录制/静音回归尚未运行。
> 2026-10-11 11:12 屏幕录制授权恢复，`screencapture` 链路打通，截图验收可用。老板追加微调并已实施：待录制态**删掉副标题行**（「已选择…· 点击下方按钮开始」/「请先选择…」），只保留居中波形图标 + "Ready to Record"（`WaveformView.swift` `drawIdlePlaceholder`）。已重建并重启（新实例 PID 63753），截图证据：`docs/证据/2026-10-11-待录制态-仅标题-v2.png`（副标题确认消失）。验收标准第 1 条「能看到标题/来源提示」按老板新口径修订为「只显示标题」。
> 2026-10-11 11:15 老板再砍一刀（简洁大气）：**录制按钮旁的「开始录制」文案也删掉**（`ControlPanelView.swift`，`recordHintLabel` 声明/样式/约束/`isHidden` 四处引用全清）。已重建并重启（PID 71037），截图证据：`docs/证据/2026-10-11-待录制态-无文案-v3.png`（文案确认消失，按钮组仍居中）。验收标准第 3 条同步修订为「底部待录制态只显示计时 + 红色按钮，无文案」。
> 2026-10-12 13:15 随 UI-003/005 签收推进：主链路已真机打通（FIX-002 后录制→编辑器不崩），剩静音零位线灰色、返回待录制态、落盘验证留日常使用观察。

**验收标准**：
- [ ] 初次进入/返回待录制：中央无基线、假波形、时间轴，只显示居中波形图标 + "Ready to Record"（2026-10-11 老板定：无副标题行）
- [ ] 未采集/准备中/停止后：电平置灰并显示「未监测」，红色只用于实际峰值/削波；收到零值音频回调后也算已监测
- [ ] 底部待录制态只显示中性灰 `00:00.00` 计时 + 红色按钮，无「开始录制」文案（2026-10-11 老板定）；录制态文案隐藏，计时高亮
- [ ] 真正进入录制态后出现波形/时间轴；静音时零位线为灰色，选已有录音仍可预览
- [x] `build-app.sh` exit 0；SDK 77/77、控制面板快照 2/2、英文 strings `plutil -lint` 均通过
- [ ] 录音/静音/回待录制态 GUI 与音频落盘验证（UI runner 无 automation 权限，视觉 advisor HTTP 403，需恢复环境后续验）

### UI-008 右侧 DB METER 电平列顶穿底部控制栏 | P2 | S | [doing] ✅ 标准 2026-10-12 16:24 老板签（「签收」）

> 来源（2026-10-12 14:40 老板报障，附截图红框）：右侧 DB METER 电平列（刻度 + L/R 条）一路延伸到**窗口最底缘**，越过底部控制栏区域；设计稿中电平列与画布同高、**止于底部控制栏上缘**，底栏横贯全宽。
> 追加（14:43 老板指令，附截图）：电平列中央的**「Not Monitoring」文字提示浮层不要**——浮在条上不好看，直接删除，不做替代方案。

**做什么**：①电平表列高度约束改为与中央画布等高（bottom 对齐底部控制栏上缘），0→-48 刻度与 L/R 标签整体收进画布区；②**删除「Not Monitoring」浮层文字**（未监测状态用置灰空条表达即可，LOOP-08 的置灰语义不回退）。

**不做什么**：不动电平表视觉样式（渐变/刻度值/UI-003 成果）、不动底部栏内容

**验收标准**（2026-10-12 16:24 老板签）：
- [ ] 电平列底缘 = 底部控制栏上缘（截图量测无重叠穿入，对照 `design-main-ui.png` 老板核对）
- [ ] 「Not Monitoring」文字已删除（待录制态电平列只有刻度 + 置灰空条 + L/R 标签，无任何浮层文字）
- [ ] 窗口缩放时约束保持（不重新顶底）
- [ ] UI-003~007 成果不回退；`build-app.sh` exit 0；截图证据落 `docs/证据/`

---

## done 索引（正文见 `docs/归档/TODOS-done-2026-10.md`）

| 单号 | 标题 | 签收 |
|---|---|---|
| LOOP-01 | 单测盘点：测试用例解决什么问题 | 2026-09-20 |
| LOOP-02 | String.localized 分层断裂修复 | 2026-09-21 |
| LOOP-03 | 计时器与录制管线脱节修复（BUG-1） | 2026-09-21 |
| LOOP-04 | SDK 单测执行卡死修复 | 2026-09-21 |
| LOOP-06 ≡FIX-001 | localized %@ 残留清理（App 层） | 2026-10-11 |
| LOOP-07 ≡UI-001 | 待录制界面隐藏时间刻度 | 2026-10-11 |
| FIX-002 | EditorStatusBar 裸 Int 喂 %@ 崩溃 | 2026-10-11 |
| FIX-003 | 点击波形选点播放总从头开始 | 2026-10-11 |
| UI-003 | 主界面视觉重构（Stitch v2 → Figma 校准） | 2026-10-12 |
| UI-004 | 侧栏初始化宽度 260pt | 2026-10-12 |
| UI-005 | 红钮画布视觉居中 | 2026-10-12 |
| UI-006 | 画布网格线铺满（含 R2 顶部留白） | 2026-10-12 |
| UI-007 | App 图标 LC 字标（含 R2 Dock 生效） | 2026-10-12 |
| FEAT-001 | 语音转文字（SpeechAnalyzer + 导出 MD） | 2026-10-11 |
| INFRA-002 | 稳定开发签名（LoocapDev 证书） | 2026-10-12 |
