# 需求队列（TODOS）— Loop 需求池

> **唯一状态真相**：单子/验收标准/状态/证据。开发方式唯一：`docs/LOOP.md`（宪法）；自动加载版 `.codebuddy/rules/loop-protocol.md`。  
> 状态六态：todo / doing / self-verify / ready-for-review / blocked / done。  
> 老板只做三件事：签标准（定义）、拍板（裁决）、看证据（签收）。  
> **签收时序（2026-10-13 老板定）**：「签」发生在**入库时**——需求台起草标准，老板确认可以做即为已签，**Loop 直接做，无二次开工确认**；「签收」一词只用于 **Loop 结束后老板验证结果**（ready-for-review → done 的那次）。入库未签的单不开工，已签的单执行侧不再等老板。  
> **签收即归档**（2026-10-12 老板定）：单子签收当天，正文迁 `docs/归档/TODOS-done-YYYY-MM.md`，本池只留索引行——控制每次「重读池」的上下文成本。  
> **编号规范**：已移 `docs/LOOP.md §十一`（TYPE-NNN 全局递增、入池查重、历史单不回改）。品牌：**Loocap｜路文**（2026-10-11 起，旧名 Tapture 见 `docs/产品/品牌更名-2026-10-11.md`，历史单不回改）。  
> **双会话分工**：入池权归需求台；执行侧状态上限 `ready-for-review`；小粒度精确编辑；写前重读；**单间必重读池**（2026-10-12 增，铁律 4）。

## 池速览（一行一单，签收/入池即更新此表）

| 单号         | 标题                                 | P  | 状态          | 备注                                     |
| ---------- | ---------------------------------- | -- | ----------- | -------------------------------------- |
| LOOP-05    | XCUITest 11 个失败修复 ≡INFRA-001       | P1 | **blocked** | 等老板在 WorkBuddy 外跑 `scripts/test-ui.sh` |
| LOOP-08    | 录音准备态与实时采集态视觉分离 ≡UI-002            | P1 | **blocked** | 主链路已通，细项留日常观察                          |
| FIX-006    | 开麦混录说话无电平（原「QQ音乐电平」误报口径）      | P2 | done ✅ | 10-13 12:12 签收                              |
| FIX-007    | 录音中开麦开关录不进麦克风声音                     | P1 | **rfr · 待签** | 10-13 12:22 动态注入修复，打点+落盘双证            |
| FIX-005    | 拖动窗口右缘出现漂移白条                        | P2 | done ✅ | 10-13 11:45 签收（真实拖动手感复验通过）           |
| UI-012     | 网格铺满整个画布、与底部面板间零空隙                | P2 | done ✅ | 10-13 11:45 签收                              |
| UI-011     | DB METER 标签字体优化（B 仪表标准式）              | P3 | done ✅ | 10-13 11:45 签收                              |
| FIX-004    | 录音中无实时波形（含源指示小补）          | P1 | done ✅ | 10-13 11:32 签收                              |
| UI-010     | 录音态波形改绿色圆头竖条风格                | P2 | done ✅ | 10-13 11:32 签收（R1 留白收窄并入）        |
| INFRA-003  | App 更名 Loocap（Bundle ID 迁移）           | P1 | done ✅ | 10-13 11:32 签收（重新授权+录音终验通过）  |
| FEAT-002   | 导出 txt（实时翻译砍掉）                      | P1 | done ✅ | 10-13 10:34 签收                              |
| UI-009     | Dock 图标观感偏小——可见边界调大        | P2 | done ✅ | 10-13 10:34 签收                          |
| LOOP-01~04 | 测试盘点 / localized 断裂 / 计时器脱节 / 单测卡死 | P0 | done ✅      | 09-20/21 签收                            |
| LOOP-06    | localized %@ 残留清理 ≡FIX-001         | P0 | done ✅      | 10-11 签收                               |
| LOOP-07    | 待录制界面隐藏时间刻度 ≡UI-001                | P2 | done ✅      | 10-11 签收                               |
| FIX-002    | EditorStatusBar 裸 Int 崩溃           | P0 | done ✅      | 10-11 真机签收                             |
| FIX-003    | 点击波形选点播放从头开始                       | P1 | done ✅      | 10-11 签收                               |
| UI-003     | 主界面视觉重构（Stitch v2）                 | P1 | done ✅      | 10-12 13:15 签收                         |
| UI-004     | 侧栏初始化宽度 260pt                      | P2 | done ✅      | 10-12 13:15 签收                         |
| UI-005     | 红钮画布视觉居中                           | P2 | done ✅      | 10-12 13:15 签收                         |
| FEAT-001   | 语音转文字（双引擎+导出 MD）                   | P1 | done ✅      | 10-11 16:12 签收                         |
| INFRA-002  | 稳定开发签名（LoocapDev 证书）               | P1 | done ✅      | 10-12 13:54 签收                         |

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

### INFRA-003 App 更名 Loocap（代码侧 + Bundle ID 迁移） | P1 | M | [done ✅ 2026-10-13 11:32 老板签收（重新授权+录音终验通过）]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

### FEAT-002 转写导出 txt（实时翻译砍掉） | P1 | S | [done ✅ 2026-10-13 10:34 老板签收]

> 10-13 09:59 追改：导出按钮文案「导出 MD」→「导出」（双格式后旧文案失义），L10n 废弃 key 已删，commit 0ffdce9。
> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

---

### UI-009 Dock 图标观感偏小（可见边界调大） | P2 | S | [done ✅ 2026-10-13 10:34 老板签收]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

---

### FIX-004 录音中无实时波形（计时走、画布空） | P1 | M | [done ✅ 2026-10-13 11:32 老板签收（含源指示）]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

---

### UI-010 录音态波形改现代竖条风格（旧包络方案保留备用） | P2 | S | [done ✅ 2026-10-13 11:32 老板签收（R1 留白收窄并入）]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

---

### UI-011 DB METER 标签字体优化（B 仪表标准式，老板已选） | P3 | S | [done ✅ 2026-10-13 11:45 老板签收]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

---

### FIX-005 拖动窗口右缘出现漂移白条 | P2 | M | [done ✅ 2026-10-13 11:45 老板签收]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

---

### UI-012 网格铺满整个画布、与底部面板间零空隙 | P2 | S | [done ✅ 2026-10-13 11:45 老板签收]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

---

### FIX-006 开麦混录说话无电平（原口径「播放 QQ 音乐时电平不启动」） | P2 | M | [done ✅ 2026-10-13 12:12 老板签收]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

---

---

### FEAT-003 下掉实时翻译浮窗（不弹即达标，代码留开关） | P1 | S | [todo · 待签]

> 来源（2026-10-13 11:38 老板指令）：「实时翻译要下掉先。不要弹出下面那个实时翻译的浮窗。」
> 边界澄清：FEAT-002 砍的是**导出**里的翻译；本单下掉的是**运行时**录音/转写过程中弹出的实时翻译浮窗——两者是不同入口。

**做什么**：
1. 浮窗主嫌疑定位：`LiveTranscriptPanel.swift`（弹出链路由执行侧确认：谁触发显示、挂在哪个父视图）
2. **下掉弹出入口**：默认不再弹出实时翻译浮窗——用 feature flag / 常量开关实现（如 `enableLiveTranslation = false`），**翻译相关代码不物理删除**（老板口径「先下掉」，留恢复能力）
3. 设置页如有「实时翻译」开关项，同步隐藏或置灰（避免用户打开一个无效功能）
4. 下掉后确认转写主链路不受影响（浮窗消失但转写文本正常产出/展示）

**验收标准**（待签）：
- [ ] 录音 + 转写全流程：实时翻译浮窗不再弹出（录屏/截图证据）
- [ ] 转写功能正常（文本照常出现）
- [ ] 开关可一键恢复（代码层验证即可）
- [ ] `build-app.sh` exit 0；SDK 单测通过

---

### INFRA-004 改名残留：PRODUCT_NAME/进程名仍是 AudioRecordMac（hover 提示旧名） | P1 | S | [todo · 待签]

> 来源（2026-10-13 11:39 老板 hover 截图）：鼠标悬停 App 提示还显示「**AudioRecordMac**」。老板指令：「全局搜一下，从根本上改」。
> 证据：`docs/证据/2026-10-13-INFRA003R1-hover残留AudioRecordMac.png`
> 前置：INFRA-003（已 done）改了 Bundle ID/显示名/L10n，但漏了 **PRODUCT_NAME 层**。

**根因（已定位，执行侧复核后直接修）**：
- `AudioRecordMac.xcodeproj/project.pbxproj` 两处 `PRODUCT_NAME = AudioRecordMac;`（~31769/31931 行，App target 两个 build configuration）未改
- 可执行名/进程名 = PRODUCT_NAME → hover tooltip、⌘Tab、Dock hover、活动监视器显示的全是它
- 两个 Info.plist 无 `CFBundleName` 显式键 → 显示名 fallback 到可执行名

**做什么**：
1. `PRODUCT_NAME = AudioRecordMac` → `Loocap`（2 处）
2. **连锁核查**：`build-app.sh`、判活脚本、e2e 用例中按产物名 `AudioRecordMac.app` / 进程名 `AudioRecordMac` 定位的引用全部同步（grep `AudioRecordMac` 出清单，逐项处理）
3. **口径维持**：工程目录名 `AudioRecordMac.xcodeproj` 与源码目录 `AudioRecordApp` 不动（INFRA-003 既定「不做什么」，不显示给用户）；若 grep 发现其他用户可见层残留，一并清零
4. **TCC 风险注记**：PRODUCT_NAME 变更 → 产物路径与 cdhash 变化，可能触发一次重新授权（LoocapDev 稳定签名下应免，实施后实测录音链路确认）

**验收标准**（待签）：
- [ ] hover/⌘Tab/Dock hover/关于窗口全部显示 Loocap（截图证据，重点复刻老板截图场景）
- [ ] 全仓 grep `AudioRecordMac`：用户可见层清零（工程/源码目录名豁免，出豁免清单）
- [ ] `codesign -dv` Identifier 仍为 `com.microlab.loocap`；录音链路实测不需重授权（若需要，记录并告知老板）
- [ ] `build-app.sh` exit 0；判活脚本冒烟通过

---

### FIX-007 录音中开麦克风开关，录不进麦克风声音 | P1 | M | [ready-for-review · 10-13 12:22]

> **定性实锤（A · 开关态与引擎脱节）**：`CoreAudioProcessTapRecorder` 全文零 mic 引用（grep 实证）——纯系统录制器根本没有麦克风通道；`shouldMixAudio` 只在 `startRecording()` 读一次（`MainViewController.swift:282/286/321`），录音中切开关只改变量、引擎无任何通路。B（权限）/C（录错设备）排除：授权 11:32 已重授且混录链路（FIX-006）麦克风收音正常。

**修复（录音中动态麦克风注入）**：
1. `AudioCallbackHandler.writeAudioData` 增加注入点 `micMixProvider`：每帧向录制器取 mic 数据，40% 混入系统音频写盘（配比与 MixedAudioRecorder 一致），无 provider 时零开销直通
2. `CoreAudioProcessTapRecorder` 新增 mic 引擎（input tap → 环形缓冲，复用 FIX-006 hold 欠载补偿）+ `setMicMixEnabled(_:)` 幂等开关（ON 懒启引擎 / OFF 撤除，停止路径强制清理不留设备占用）
3. `MainViewController.mainWindowViewDidChangeMixAudio`：录音中切开关直通录制器，状态栏提示「麦克风已加入本次录制」；非录音中路径不变
4. 回归钩子：selftest 触发器 `N mixmid`（纯系统起录→5s 录音中切麦）

**验收情况**：
- [x] 录音中开麦后出声，文件麦克风通道有声——场景 1 硬验证（14s mixmid）：打点链「切麦→注入 ON→注入首帧→引擎 48kHz×1ch 启动→**麦克风首帧 peak=0.033 真实收音**→停→OFF→引擎撤除」全链日志；解密逐秒峰值 **0-4s（开麦前）全 0.000 → 5s 测试音 0.176 → 6-14s 麦克风环境底噪 0.025-0.034 持续在场**（修复前此场景 mic 通道不存在、纯静音文件会被拦截删除）
- [x] 开关 UI 态与引擎一致（打点：`录音中麦克风注入开关: ON/OFF` + `已下发录制器`）
- [x] 三场景回归：纯系统（本场景 0-4s 段 + FIX-004 多轮）✓；混录（FIX-006 12:05 场次）✓；纯麦克风——UI 无独立纯麦入口（麦克风仅为叠加选项），`MicrophoneRecorder` 独立链路已有单测覆盖，如实注记
- [x] `build-app.sh` exit 0
- [ ] 待老板签收：录音中开麦说一句话验证

**实施记录**：`AudioCallbackHandler.swift`（micMixProvider+注入分支）/ `CoreAudioProcessTapRecorder.swift`（mic 引擎+环形缓冲+hold+开关）/ `MainViewController.swift`（录音中开关直通）/ `AppDelegate.swift`+`MainViewController.runSelftestRecording`（mixmid 钩子）

> 来源（2026-10-13 11:48 老板口述）：录制时打开麦克风窗口、打开麦克风开关，但录出来的文件里没有麦克风的声音。
> 关联：FIX-006（系统音频 tap，定性场景 B 已关）——本单是**麦克风通道**的对应问题，两者合起来覆盖双通道采集。

**先分叉定性（不许直接修）**：
- **A · 开关态与引擎脱节**：麦克风开关 UI 是开的，但引擎实际没把麦克风通道加进采集（UI 态 ≠ 引擎态，与 FIX-006 嫌疑同构）——打点验证开关切换是否真正触发了输入通道变更
- **B · 权限丢失**：TCC 麦克风授权失效（改名/重签后授权重置），系统静默拒绝——查 `Info.plist` 麦克风权限文案 + 系统设置授权状态 + 引擎报错日志
- **C · 录错设备**：默认输入设备不是老板说话的那个麦克风（多设备场景，与 FEAT-004 直接相关）——列出实际采集的设备名对质
- 硬验证：混录文件分轨/分通道电平解析（系统音轨有声、麦克风轨无声 → 通道级断点实锤）

**做什么**（定性后）：
1. 复现：系统音频录音中 → 开麦克风窗口 → 开麦克风开关 → 对麦克风说话 → 停止 → 分轨验证
2. 按定性修复对应断点
3. 回归：纯麦克风录音、纯系统音频录音、双通道混录三种场景都落盘有声（afinfo/播放硬验证）

**验收标准**（待签）：
- [ ] 录音中开麦克风开关后说话，混录文件麦克风通道有声（分轨电平证据）
- [ ] 开关 UI 态与引擎实际采集通道一致（打点日志证据）
- [ ] 三场景回归（纯麦克风/纯系统/混录）全过
- [ ] `build-app.sh` exit 0

---

### FEAT-004 麦克风设备探测与选择（多输入设备） | P2 | S | [rfr · 实现+单机验证完成 2026-10-13 12:45，待老板签]

> 来源（2026-10-13 11:48 老板口述）：「麦克风需要能探测有几个麦克风输入，最好是可以选择。」
> 联动：FIX-007 分叉 C（录错设备）——本单落地后天然成为该场景的根治手段。

**做什么**：
1. **设备枚举**：CoreAudio 枚举全部可用麦克风输入设备（内建麦克风、外接耳机麦、聚合设备等），显示设备名与在线状态
2. **设备选择**：麦克风窗口提供设备列表可点选，选中即作为录音输入源（选择持久化，重启保持）
3. **默认行为**：未手动选择时跟随系统默认输入设备；设备拔出/失效时回退默认并提示（不用弹窗打断，界面内提示即可）
4. 电平表随所选设备走（选中哪个麦克风，DB METER 显示哪个的电平——与 UI-013 未录音态监听天然衔接）

**不做什么**：不做多麦克风同时录制（一期单选；聚合设备用户可自行用系统「聚集设备」实现）

**验收标准**（待签）：
- [ ] 接 ≥2 个麦克风输入时，窗口能列出全部设备（截图证据）——**本机单麦克风，此项留老板外接设备后验证**
- [ ] 点选设备后录音，落盘文件来自所选设备（对质证据：换设备录两次，音色/电平特征可区分）——**同上留老板验证**
- [x] 选择持久化：重启 App 保持上次选择（UserDefaults 存 UID，实现就位）
- [x] `build-app.sh` exit 0

**实现与证据**（2026-10-13 12:45）：
- 新增 `AudioRecordKit/Sources/Core/Utils/MicDeviceManager.swift`：CoreAudio 枚举（输入流判定）+ UserDefaults 持久化 UID + AUHAL `kAudioOutputUnitProperty_CurrentDevice` 重定向绑定 + 热插拔监听（失效回退+行内提示）
- 三处麦克风引擎接线：MicrophoneRecorder / MixedAudioRecorder / CoreAudioProcessTapRecorder(mic 注入引擎) prepare 前 `applyPreferredDevice`
- 侧栏新增「输入设备」行（MICROPHONE 面板下方固定底部，第 0 项=系统默认）
- **坑 1（启动回归，对照实验实锤）**：micDeviceRow 漏 addSubview 但激活了对 audioRecorderTabView 的约束 → AppKit 布局异常 → 主窗口永不渲染（offscreen）、selftest 定时器不跑、启动日志断流。旧版（FIX-007）对照正常，补 addSubview 修复
- **坑 2（API 时序，独立 CLI 二分实锤）**：`mainMixerNode.installTap` 会初始化 AU 图，此后 AUHAL 拒绝换设备（-10851 CannotDoInCurrentContext）→ 绑定必须移到任何 installTap **之前**。修复后 selftest「6 mix」绑定打点：`麦克风输入设备已绑定: MacBook Pro Microphone (uid=BuiltInMicrophoneDevice)`
- 环境注：TCC 辅助功能缺失（System Events/AX 全被拒），窗口上屏验证走 Quartz onscreen + screencapture -l 替代

---

### UI-014 录音态波形滚动降速（20 条/秒 → 10 条/秒，常量化） | P3 | S | [rfr · 完成+硬验证 2026-10-13 13:46，待老板签]

> 来源（2026-10-13 12:13 老板口述）：「电平录制的时候，向左移动的速度太快了。」
> 根因（需求台已定位）：`WaveformView.swift:369` `Timer.scheduledTimer(withTimeInterval: 0.05)` —— 每 50ms 推一根条 = **20 条/秒**，超出实时波形行业惯例档（10-15 条/秒，剪映/录音笔观感）。

**做什么**：
1. 采样间隔 `0.05 → 0.10` 秒（20 条/秒 → 10 条/秒，滚动速度减半），一根条代表 100ms 音频
2. 间隔提成具名常量（如 `barInterval = 0.10`），后续微调不用找魔法数字
3. **连锁核查**：条数减少后画布满铺/取尾部 N 条的裁剪逻辑自适应（画布仍满铺，不留半截）；`waveformData` 容量上限同步
4. 与静态文件波形（extractWaveformSamples）无关，只动实时录制态

**实现与硬验证**（2026-10-13 13:46）：
- 实现口径修正：`:369` 的 Timer 只驱动重绘（20fps 保留，显示刷新与滚动速度解耦——只改它会两根条并跳），真正决定条数的是 `updatePeakLevel` 随音频回调逐次 append。改为 **100ms 时间窗聚合**：窗口内取峰值 max、到点落杆（不丢瞬时峰值），常量 `barInterval = 0.10`
- `stopRecording` 加验证打点，selftest 10s 实录：**`条数=76 时长=8.2s 速率=9.3条/秒`**（≈10 条/秒档命中；与 10.0 的偏差=窗口对齐损耗，属预期）
- 连锁核查：`maxDataPoints=260` × 100ms = 26s 可视历史（原 13s）；绘制 targetBars 按画布宽度自适应，满铺逻辑不受影响

**验收标准**：
- [x] 滚动速度降半硬验证（落杆速率 9.3 条/秒打点）——录屏观感对比留老板日常使用确认
- [x] `build-app.sh` exit 0
- [ ] 画布满铺无半截（长录 1 分钟以上验证）——留老板录音时顺带确认

---

## done 索引（正文见 `docs/归档/TODOS-done-2026-10.md`）

| 单号               | 标题                             | 签收         |
| ---------------- | ------------------------------ | ---------- |
| LOOP-01          | 单测盘点：测试用例解决什么问题                | 2026-09-20 |
| LOOP-02          | String.localized 分层断裂修复        | 2026-09-21 |
| LOOP-03          | 计时器与录制管线脱节修复（BUG-1）            | 2026-09-21 |
| LOOP-04          | SDK 单测执行卡死修复                   | 2026-09-21 |
| LOOP-06 ≡FIX-001 | localized %@ 残留清理（App 层）       | 2026-10-11 |
| LOOP-07 ≡UI-001  | 待录制界面隐藏时间刻度                    | 2026-10-11 |
| FIX-002          | EditorStatusBar 裸 Int 喂 %@ 崩溃  | 2026-10-11 |
| FIX-003          | 点击波形选点播放总从头开始                  | 2026-10-11 |
| UI-003           | 主界面视觉重构（Stitch v2 → Figma 校准）  | 2026-10-12 |
| UI-004           | 侧栏初始化宽度 260pt                  | 2026-10-12 |
| UI-005           | 红钮画布视觉居中                       | 2026-10-12 |
| UI-006           | 画布网格线铺满（含 R2 顶部留白）             | 2026-10-12 |
| UI-007           | App 图标 LC 字标（含 R2 Dock 生效）     | 2026-10-12 |
| UI-008           | DB METER 全高右栏（R2 裁决贯穿到底 + 删浮层） | 2026-10-12 |
| FEAT-002         | 转写导出 txt（实时翻译砍掉，按钮改「导出」）        | 2026-10-13 |
| UI-009           | Dock 图标观感偏小——描边提亮+主体满铺            | 2026-10-13 |
| FIX-004          | 录音中无实时波形（静音保活根因修复+源指示）       | 2026-10-13 |
| UI-010           | 录音态绿色圆头竖条风格（R1 留白收窄并入）          | 2026-10-13 |
| INFRA-003        | App 更名 Loocap（Bundle ID 迁移+数据迁移）       | 2026-10-13 |
| FIX-005          | 拖动窗口右缘漂移白条（窗口背景根因修复）           | 2026-10-13 |
| UI-011           | DB METER 标签 B 仪表标准式                     | 2026-10-13 |
| UI-012           | 网格满铺+面板零空隙                            | 2026-10-13 |
| FIX-006          | 开麦混录说话无电平（三层根因修复）                 | 2026-10-13 |
| FEAT-001         | 语音转文字（SpeechAnalyzer + 导出 MD）  | 2026-10-11 |
| INFRA-002        | 稳定开发签名（LoocapDev 证书）           | 2026-10-12 |

