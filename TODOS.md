# 需求队列（TODOS）— Loop v2 启动池

> 2026-09-20 清空重建。旧 backlog 已归档 `docs/归档/TODOS-archive-20260920.md`，待 loop 协议验证后批量补验收标准再捡回。
> 开发方式唯一：`docs/LOOP.md` 循环协议。状态标记：todo / doing / self-verify / ready-for-review / blocked / done。
> 老板只做三件事：签标准（定义）、拍板（裁决）、看证据（签收）。
> **品牌更名（2026-10-11）**：产品对外品牌定为 **Loocap｜路文**（副标语：内录 · 转写 · 剪辑 / Capture & Transcribe），不再叫 Tapture。工程内代码标识符（TaptureTheme.swift、Bundle 名、window 属主等）暂未改，见 `docs/产品/品牌更名-2026-10-11.md`；本文档中历史单里的 Tapture 为当时事实记录，不回改。

## 编号规范（2026-10-11 定，Tab 入池必须遵守）

**单号格式：`<TYPE>-<NNN>`**（TYPE 四选一 + 三位数字）

| TYPE | 含义 | 示例 |
|---|---|---|
| `FEAT` | 新功能 | FEAT-001 语音转文字 |
| `FIX` | 缺陷修复 | FIX-001 `%@`+数值崩溃清理 |
| `UI` | 界面/交互调整 | UI-002 待录制态视觉分离 |
| `INFRA` | 测试建设/构建/工程/环境 | INFRA-001 XCUITest mock 修复 |

- **序号全局递增**：下一张单 = 全池（含归档）现有最大数字 + 1，不复用已删单号
- **一单一号**：即使同一需求的后续迭代也开新号，用「来源：FEAT-00x」字段关联，不复活旧号
- **入池前必查重号**：先 grep 目标单号确认全池唯一；多会话并行入池时，以先写入者为准，后来者顺延（2026-10-11 曾发生双会话撞号 FIX-002，教训已入规范）
- **规格文档**：文档文件名仍用描述性命名（如 `docs/需求/FEAT-001-语音转文字技术方案.md`），单号与文档一一对应
- **历史单不回改**：LOOP-01~08、归档的 BUG-x/REQ-x 保留原号（证据与文档已引用），只在标题尾加 `≡新号` 映射
- **标题行格式**：`### <单号> <一句话标题> | <P0-P2> | [状态]`
  - 工作量预估写正文 `**预估**：X天`，不进标题
  - 状态 = 六态（todo / doing / self-verify / ready-for-review / blocked / done）+ 可选修饰：`todo · 待签`、`done · YYYY-MM-DD 签收`、`blocked · 等人工`
  - `≡新号` 映射放行尾（状态之后）；旧编号（BUG-x 等）不进标题，括注在正文
  - 同轮次单子按单号升序排列

### 双会话分工（2026-10-11 定）

TODOS.md 由两个会话共享：**需求台**（WorkBuddy 会话，老板提需求/裁决/签收的地方）与**执行侧**（CodeBuddy Tab，跑 loop 做事）。写权限分区如下：

1. **入池权归需求台**：新单只能由需求台登记。执行侧发现新问题 → 报回需求台入池，不自己开单；唯一例外是执行侧拆自己单子的子单（如 FEAT-001 拆 S4），拆时必须 grep 查重取号。
2. **状态阶梯**：执行侧对已有单子可更新进度/证据/状态，**上限 `ready-for-review`**；`done` 由需求台在老板签收后落账（签收动作发生在需求台对话里，执行侧不得代签）。
3. **小粒度写**：双方一律用单号定位的精确编辑，禁止整段重写本文件——编辑冲突会自然失败重读，不静默覆盖。
4. **写前重读**：取号或改状态前先重读本文件拿最新状态，再动手。

---

## 🔥 第一轮：跑通 loop 最小闭环（2 张单）

### LOOP-01 单测盘点：每个测试用例解决什么问题 | P0 | [done · 2026-09-20 签收]

**预估**：0.5天

**做什么**：盘点全部现有测试载体，提取每个测试用例「解决什么问题」（防什么 bug / 验证什么能力），实测当前状态（能否编译、是否跑过），产出测试全景表。

**不做什么**：不修任何测试/代码（修复是下一张单）、不跑 computer use E2E（TC 系列仅登记）、不新增测试用例

**边缘情况**：某测试文件无法编译 → 记录失败原因（已知：SDK 编译断裂 `String.localized`），不现场修

**验收标准**：
- [ ] 覆盖全部测试载体：SDK 单测 6 文件（AudioRecordKit/Tests/）+ XCUITest 5 文件（AudioRecordMacUITests/）+ Snapshot 1 文件（AudioRecordMacSnapshotTests/）
- [ ] 每个测试文件：提取测试方法清单，每个方法一句话说明「解决什么问题」
- [ ] 实测状态：SDK 单测编译结果、XCUITest / Snapshot 编译结果（跑 `test_sdk.sh` / `test-ui.sh` / `test-snapshot.sh` 记录 PASS/FAIL）
- [ ] 产出 `docs/测试/测试全景表.md`：测试 → 解决的问题 → 当前状态 → 是否纳入自验基线
- [ ] 表中标注「缺失的关键测试」：哪些核心能力（录制/导出/编辑器）还没有测试覆盖
- [ ] 盘点结论给出「下一张单建议」：先修什么、补什么

---

### LOOP-02 修复 String.localized 分层断裂（务实修） | P0 | [done · 2026-09-21 签收]

**预估**：0.5天

> 来源：LOOP-01 实测发现（L3 发现循环产出）。三个测试入口全部编译失败，同根因。
> 裁决（2026-09-20 老板）：不做真内核化（SDK 独立分发非当前优先级）。北极星 = App 上架，测试为质量护航。
> 裁决（2026-09-20 老板）：选 A——LOOP-02 扩展范围，就地更新过时测试到 V2 API（FileManagerUtilsTests 已重写）。

**做什么**：务实修——把 `String.localized` 扩展所在的 `L10n.swift` 从 App 层移到 Kit 层（`AudioRecordKit/Sources/Utils/`），让 SwiftPM 单测和 SnapshotTests target 都能编译到它。当前 App 与 Kit 是同一 target 平铺编译，移动后主 App 编译不受影响。

**不做什么**：不做真内核化（不建独立 Kit module/framework、不改 App 引用方式）、不动测试逻辑本身、不改产品功能代码

**验收标准**：
- [ ] `test_sdk.sh` 编译通过（无 `String has no member 'localized'`）
- [ ] `test-snapshot.sh` 编译通过
- [ ] `test-ui.sh` 构建不再被 SnapshotTests 拖累
- [ ] 主 App 构建仍通过（`build-app.sh` exit 0）
- [ ] 中文文案行为零变化（zh-Hans 环境原样显示）

---

### LOOP-03 计时器与录制管线脱节修复（原 BUG-1） | P0 | [done · 2026-09-21 签收，运行时验证 6/7/8 待人工补测]

**预估**：1天

**做什么**：修复 UI 显示「录制中」但管线未启动的脱节问题（原 BUG-1）。现象：UI 计时器走 ~7 分钟但无 `startMultiSourceRecording` 日志记录，管线 00:45:14.483 才启动、0.76s 后停止 → 产出 0 秒文件，编辑器报「无法分配音频缓冲区」（EditorViewController.swift:857）。证据：`沙盒 Documents/AudioRecordings/Logs/audiorecord_2026-09-17.log` 行 53921–77747。

**不做什么**：不动编辑器裁剪/DSP 逻辑、不动导出管线、不改 UI 布局

**边缘情况**：权限检查回调延迟、录制启动失败、0 秒/静音录音、编辑器加载空文件

**验收标准**：
- [ ] 构建：`build-app.sh` exit 0，编译零错误
- [ ] 代码：录制态切换由 recorder 启动回调驱动，删除 0.3s 定时器假装进入 recording 的逻辑（MainViewController.swift:248-250）
- [ ] 代码：停止按钮不受 `isRecording` guard 拦截，任何状态可达
- [ ] 落盘：0 秒/静音录音在落盘前被拦截（沙盒目录无新文件断言）
- [ ] 编辑器：加载 0 buffer 文件不再报「无法分配音频缓冲区」
- [ ] E2E：复现原 BUG-1 路径（权限检查延迟场景）→ UI 不显示「录制中」、计时器不走
- [ ] 回归：TC-001 主链路（QQMusic 录制→导出 WAV）仍 PASS
- [ ] 证据：新日志中录制态切换与 `startMultiSourceRecording` 时间戳一致

### LOOP-04 SDK 单测执行卡死（xctest hang） | P0 | [done · 2026-09-21 签收]

**预估**：0.5天

> 来源：LOOP-02 自验发现。根因已定位并修复：`String(format:"%@", arguments:[数值])` 把 UInt32/OSStatus 当对象指针解引用 → SIGSEGV。修 3 处（AudioUtils.swift:422、AudioToolboxFileManager.swift:58/124 数值转 String）。结果：`test_sdk.sh` 77/77 全 PASS。

**做什么**：定位测试执行卡死根因（可疑：某用例 RunLoop 等待 / 测试进程初始化时权限或音频设备枚举阻塞），修复到 `test_sdk.sh` 完整跑出 PASS/FAIL 结果。

**不做什么**：不改产品功能代码

**验收标准**：
- [ ] `test_sdk.sh` 完整执行出结果（日志含 `Executed N tests` 或等效统计，不再止于 Build complete）
- [ ] 全部测试 PASS，或失败项逐个判定「测试错/产品错」并记录
- [ ] 无残留 xctest 进程（跑完进程自然退出）
- [ ] 日志落盘 `test_logs/sdk_test_*.log` 完整

### LOOP-05 XCUITest 11 个失败修复（mock 注入失效） | P1 | [doing] ≡INFRA-001

**预估**：1天

> 代码部分已完成：mock 进程注入（1001-1006 Chrome/Safari/Music/Zoom/Teams/Slack）+ mock 录制状态机（MainViewController，--ui-testing 参数）。
> 阻塞原因（2026-10-11 更新，两层）：① XCUITest runner 的辅助功能授权存疑（历史报「Not authorized for performing UI testing actions」，今日未能推进到该步）；② **WorkBuddy 沙箱与 xcodebuild 不兼容**——`xcodebuild test` 内部依赖嵌套 `sandbox-exec` + 写 `~/Library/Developer/DerivedData`，在 WorkBuddy 沙箱内必挂 `sandbox_apply: Operation not permitted`（2026-10-11 连跑 3 轮实证：原样跑、沙箱外标志 + workspace 内 derivedDataPath + 禁自动包解析，三种打法同一死法，拦截点分别为 DerivedData 删除 / 包解析 / ~/.swiftpm/security）。按刹车规则 3 次止损。
> 解除路径（人工，二选一）：A. 老板在 WorkBuddy 之外的普通终端跑一次 `bash scripts/test-ui.sh`（验证 AX 授权 + mock 效果）；B. 研究给 WorkBuddy 会话放行 xcodebuild 所需路径/权限后重试。解除后说「继续跑 loop」续验。
> 补充证据（2026-09-26）：CUA helper 的**屏幕录制**授权也失效——Tapture/系统授权弹窗截图全黑、曾拍成功的终端重截报「窗口截图失败」，判定 TCC 授权整体损坏（本地 DR 签名 helper 同 bundle id 多拷贝互踩）。人工授权时「辅助功能 + 屏幕录制」一起勾，可同时解锁本单与 CUA 截图；授权后需重启 helper 进程生效。

> 来源：LOOP-02 自验发现。UI 测试第一次真跑：19 执行 8 过 11 挂，11 个失败全是「ProcessRow-1001 找不到」（V2.0 重构后 mock 进程注入机制/accessibility 标识失效）+ RecordingFlow 停止后按钮断言。

**做什么**：恢复 App 的测试 mock 注入机制（launch arguments）或更新测试适配 V2.0 视图结构，让 `test-ui.sh` 全绿。

**不做什么**：不改产品功能代码

**验收标准**：
- [ ] `test-ui.sh` 19/19 PASS，或逐项判定「测试已无意义」并删除且记录理由
- [ ] 日志落盘 `test_logs/ui_test_*.log` 完整

---

### LOOP-06 String.localized `%@`+数值 残留清理（App 层） | P0 | [done] ✅ 2026-10-11 老板签收 ≡FIX-001（同家族第 7 处漏网由 FIX-002 闭环）

**预估**：0.5天

> 来源（2026-10-10）：启动恢复录音会话即 SIGSEGV（崩溃报告 `audio_record_mac-2026-10-10-204507.ips`，KERN_INVALID_ADDRESS at 0x1 = `Int(zoomLevel)` 值）。崩溃链：loadAudioWithSession → fitAll → syncControlsToWaveformState → `ZoomControlsView.updateSliderPosition()` → `"缩放 %@x".localized(Int(...))`。与 LOOP-04 同根因（`%@` 期望对象，数值被当对象指针解引用），LOOP-04 只修了 Kit 层 3 处，App 层漏网。
> **已修（2026-10-10，6 处全清）**：`ZoomControlsView.swift:215`（NSNumber）、`EditorViewController.swift:505/516/517`（String）、`SilenceTrimCommand.swift:41`（String）、`HorizontalScrollBarView.swift:185`（String，AX 查询 accessibilityValue 时即触发的隐藏雷）。`TrimCommand.swift:33` 核对为 String 传参，无需改。

**做什么**：审计 App 层全部 `.localized(...)` 带参调用，把传入 `%@` 的数值参数全部改为 String/NSNumber。

**不做什么**：不改文案内容、不改 zh/en strings 表（参数包装而不是改格式符）、不动其余编辑器逻辑

**验收标准**：
- [x] 全仓 grep `\.localized\(` 逐个核对参数类型，`%@` 后无 Int/Double/CGFloat/Float 裸传（2026-10-10 扫描清零）
- [x] `build-app.sh` exit 0（2026-10-11 loop 自验，26s 编译零错误）
- [x] 启动恢复上次会话不再崩溃（连续启动两次，进程存活 > 60s）（2026-10-11：PID1=3395 / PID2=5394，双双存活 >62s）
- [ ] 静音检测空结果/有结果两条路径弹窗文案正常显示（弹窗代码参数已核对为 String 包装；GUI 路径核验需真实录制回归，与 UI-002 的录制回归合并执行）
- [x] 中文文案行为零变化（git diff：zh-Hans.lproj 零变更；en.lproj 仅 LOOP-08 范围新增 5 条英文映射）

---

### LOOP-07 待录制界面隐藏时间刻度 | P2 | [done] ✅ 2026-10-11 老板签收 ≡UI-001（录制后动态刻度项并入 UI-002 观察项）

> 来源（2026-10-10）：老板指出未录音时 `0:00`～`0:05` 的时间刻度没有意义。后续老板确认 LOOP-08，录前连中央基线和静止电平也一起改为空状态。
> 2026-10-11 loop 解封：屏幕录制授权恢复后视觉核对完成。窗口截图（`docs/证据/2026-10-11-LOOP07-待录制态-无刻度.png`，window ID 15139，CGWindowList 定位不受 AX 阻断）：待录制态波形区无刻度线、无时间标签，仅居中波形图标 + "Ready to Record"。坑：进程名 audio_record_mac 但窗口属主名是 Tapture，按 PID 过滤才能命中。

**验收标准**：
- [x] 初次打开及返回待录制态：波形区无刻度线、无时间标签（初次打开已视觉核验 2026-10-11；「返回待录制态」路径依赖真实录制回归，与 UI-002 合并执行）
- [ ] 开始录制后出现动态时间刻度；已有录音预览时按文件实际时长显示（真实录制回归，与 UI-002 合并）
- [x] `build-app.sh` exit 0（2026-10-11，再构建并重启）
- [x] 视觉核对待录制态（2026-10-11 截图链路恢复，screencapture -l 窗口级抓取成功）

---

### LOOP-08 录音准备态与实时采集态视觉分离 | P1 | [blocked] ≡UI-002

> 2026-10-10 老板确认：未录时用居中波形图标、准备录制标题和所选音源提示替代基线/假波形/时间轴；右侧电平置灰标未监测；底部红色按钮旁标开始录制且计时中性灰；仅真实录制时显示波形、时间轴及收到数据后的实时电平，录制静音时用灰色零位线。
> 2026-10-11 实施并构建；`scripts/test_sdk.sh` 77/77 PASS，`scripts/test-snapshot.sh` 2/2 PASS（基线已更新）；运行实例 PID 51418 的 AX 确认 `Not Monitoring` 和 `Start Recording`。UI test 失败：`Timed out while enabling automation mode`；CUA `get_next_action` 返回 VLM HTTP 403。中央画布为自绘，AX 不提供视觉内容，故不得把 AX 当截图验收。待 UI 测试权限恢复、视觉模型恢复或老板手动验证后再签收；真实录制/静音回归尚未运行。
> 2026-10-11 11:12 屏幕录制授权恢复，`screencapture` 链路打通，截图验收可用。老板追加微调并已实施：待录制态**删掉副标题行**（「已选择…· 点击下方按钮开始」/「请先选择…」），只保留居中波形图标 + "Ready to Record"（`WaveformView.swift` `drawIdlePlaceholder`）。已重建并重启（新实例 PID 63753），截图证据：`docs/证据/2026-10-11-待录制态-仅标题-v2.png`（副标题确认消失）。验收标准第 1 条「能看到标题/来源提示」按老板新口径修订为「只显示标题」。
> 2026-10-11 11:15 老板再砍一刀（简洁大气）：**录制按钮旁的「开始录制」文案也删掉**（`ControlPanelView.swift`，`recordHintLabel` 声明/样式/约束/`isHidden` 四处引用全清）。已重建并重启（PID 71037），截图证据：`docs/证据/2026-10-11-待录制态-无文案-v3.png`（文案确认消失，按钮组仍居中）。验收标准第 3 条同步修订为「底部待录制态只显示计时 + 红色按钮，无文案」。

**验收标准**：
- [ ] 初次进入/返回待录制：中央无基线、假波形、时间轴，只显示居中波形图标 + "Ready to Record"（2026-10-11 老板定：无副标题行）
- [ ] 未采集/准备中/停止后：电平置灰并显示「未监测」，红色只用于实际峰值/削波；收到零值音频回调后也算已监测
- [ ] 底部待录制态只显示中性灰 `00:00.00` 计时 + 红色按钮，无「开始录制」文案（2026-10-11 老板定）；录制态文案隐藏，计时高亮
- [ ] 真正进入录制态后出现波形/时间轴；静音时零位线为灰色，选已有录音仍可预览
- [x] `build-app.sh` exit 0；SDK 77/77、控制面板快照 2/2、英文 strings `plutil -lint` 均通过
- [ ] 录音/静音/回待录制态 GUI 与音频落盘验证（UI runner 无 automation 权限，视觉 advisor HTTP 403，需恢复环境后续验）

### FIX-002 EditorStatusBar 编辑步数裸 Int 喂 %@ 崩溃（录音完成即崩） | P0 | [done] ✅ 2026-10-11 老板真机签收

> 来源（2026-10-11 13:00）：老板真机录音实测（UI-002 回归路径）录音完成后编辑器加载即崩。崩溃报告 `audio_record_mac-2026-10-11-130038.ips`：EXC_BAD_ACCESS / KERN_INVALID_ADDRESS at 0x14，主线程 `objc_opt_respondsToSelector` ← `String.localized` ← `EditorStatusBar.update(duration:sampleRate:channels:editSteps:maxSteps:)` ← `EditorViewController.updateStatusBar()` ← `loadAudioWithSession`。与 FIX-001/LOOP-04 同根因家族（`%@` 期望对象，Int 被当对象指针）。
> **为什么 FIX-001 审计漏网**：2026-10-10 用 grep 模式 `Int(...)`/数值字面量扫描，此处的 `editSteps`/`maxSteps` 是**类型为 Int 的参数名**，不匹配旧模式。已升级审计方法：全仓 66 处 `.localized(` 带参调用逐个验型（非字面量参数 16 处查到声明级），EditorStatusBar:93 为唯一漏网点，其余 15 处全 String 确认。
> **已修**：`EditorStatusBar.swift:93` → `String(editSteps), String(maxSteps)`。

**验收标准**：
- [x] 修复落码（EditorStatusBar.swift:93，2026-10-11）
- [x] 全仓类型级审计：66 处带参 localized 无 `%@` + 非 String/NSNumber 参数（16 处非字面量逐一验型，2026-10-11）
- [x] `build-app.sh` exit 0（2026-10-11 13:04，27s 零错误）
- [x] 老板真机重录一次：录音完成 → 编辑器加载不崩（2026-10-11 13:28 老板确认「成功了」）。UI-002 录制态主链路随之打通，剩余细项（静音零位线灰色、返回待录制态）留日常使用观察

### FIX-003 点击波形选点播放总从头开始 | P1 | [done] ｜ 标准 2026-10-11 老板签（「签收 003」）

> 来源（2026-10-11 13:13 老板报障）：播放时点击波形任意位置选点，总是重头开始播。
> **初步定位（Tab，未开工）**：`WaveformView.seekToMouseLocation`（WaveformView.swift:263-273）已通过 `delegate?.waveformView(self, didSeekToProgress:)` 上报点击位置，但 **`MainViewController` 全文没有实现 `didSeekToProgress` 回调**（grep 0 处），播放走 `AVAudioPlayer`（MainViewController.swift:635 起）且从未写入 `currentTime`——点击只挪了视觉 playhead，音频层 seek 链路根本没接。

**做什么**：接通 seek 链路——实现 `didSeekToProgress` 回调，把 progress × duration 写入 `AVAudioPlayer.currentTime`；播放/暂停/停止三态下的选点行为一致；补回调协议的空实现移除（若有）。

**不做什么**：不动解密/临时文件管线、不动录制链路、不改波形绘制

**验收标准**（草案，待签）：
- [x] 播放中点击波形：音频不中断不重头，从点击位置继续播——`player.currentTime = targetTime`（原逻辑已在位，playhead 同步 + UXEventLog seek 事件补齐）
- [x] 暂停/停止态点击：暂停态直写 currentTime 不自动播；**停止/未播/已播完态 = 根因所在**——原 nil 分支调异步 `startPlayback` 后同步取 player 必为 nil（死代码）→ 修复：`initialProgress` 穿透异步解密链，`playDecryptedFile` 在 `play()` 前定位
- [x] 拖拽 scrubbing：新增 `waveformViewDidBegin/EndScrubbing` 协议（默认空实现）——拖动中暂停静音跟手，松手从松手位置恢复
- [x] 点击已播完文件：finishPlayback 置 nil player → 走冷启动分支从点击处重播（同第 2 条修复路径）
- [x] 老板真机验证（第一轮 15:09）：**主窗口通过，编辑器不通过**——老板截图暴露 FIX-003 有第二现场：编辑器 `startPreview`（EditorViewController.swift:772）永远 `scheduleBuffer(buffer)` 从 0 调度全量 buffer，`stopPreview` 还强制把 playhead 归零，`didSeekTo` 回调只更新视觉。编辑器侧修复（同单处理，同一用户诉求）：① startPreview 从 `currentPlayheadPosition` 切片起播（sliceBuffer，float 非交织按声道 memcpy），播到末尾再点回 0；② stopPreview 不归零保留选点；③ 播放中选点 = 重启调度无缝跳播；④ previewGeneration 代际 token 防 stop() 触发的旧 completion 误杀新播放；⑤ UXEventLog 补 `Editor.seek`/`Editor.play`（start_sec）钩子。build 35s 零错误 + 冒烟 PID 24182（2026-10-11 15:11）
- [x] 老板真机第二轮（15:13）：**通过**。UXEventLog 硬验证（uxevents_20261011-151104_42F0B725.jsonl）：两次选点 start_sec 与 target_sec 逐一相等（0.411→0.411、1.400→1.400），老板口头确认「已经没问题了」
- [ ] 回归：TC-001 主链路 PASS；播放自然结束、重复选择文件两行为不变（老板日常使用观察）

### UI-003 主界面视觉重构（按 Stitch v2 设计稿） | P1 | 1-1.5天 | [todo · 待签]

**预估**：1-1.5天

> 来源（2026-10-11 15:15）：老板用 Stitch 完成主界面重设计，要求只重做主界面（编辑器/文件页不动）。设计正本与拆解分析：`docs/设计稿/stitch-2026-10-11/`（design-main-ui.png 老板截图为准；线上链接渲染的是 v1 旧版，勿参考）。
> **老板已裁决（15:15）**：①画布副标题按设计恢复（一行「Press record or hit [Space] to start」含 Space 键帽）；②底部状态文字维持删除——底部只有时间码 + 红钮；③无 Format 下拉。
> **实现约束（需求台意见）**：不换 SwiftUI，AppKit 增量重皮（`NSVisualEffectView` 毛玻璃 / glow shadow / `CGContext` 网格）；规格 md 的 ScreenCaptureKit 采集建议不采纳（现状 ProcessTap 已跑通）。

**做什么**：按设计正本重构主窗口视觉——①全局色板换深碳黑 #0F1115 + 翠绿 #10B981 glow + 红 #FF3B30 光晕（设计系统层）；②标题栏源名改居中 Capsule 药丸 + ⚙Settings；③侧栏加 APP AUDIO Refresh、翠绿渐变选中态+对勾、彩色 App 图标；④画布加细网格背景 + 顶部绿点「Ready」状态 + 发光图标卡片 + 一行副标题（含 Space 键帽）；⑤底部栏三段式重构（几何居中大号等宽时间码 + 红钮光晕，无状态文字）；⑥右缘电平表绿黄渐变 + L/R 标记。

**不做什么**：不动录制/播放/解密管线与交互逻辑、不动编辑器与文件列表页、不引入 SwiftUI、不做 Format 切换功能

**验收标准**（待签）：
- [ ] 视觉对照：重建后窗口截图与 `design-main-ui.png` 逐区对比（标题栏/侧栏/画布/底部栏/电平表），老板肉眼核对通过
- [ ] 待录制态：细网格背景 + 绿点 Ready + 发光图标卡片 + 标题 + 一行副标题（Space 键帽样式）；**无**底部状态文字
- [ ] 底部栏：大号等宽时间码 + 红钮在窗口任意尺寸下保持水平几何居中（拉伸验证）
- [ ] 毛玻璃材质生效（NSVisualEffectView），hairline 分割线 8% 白
- [ ] 侧栏：Refresh 可见、选中态翠绿渐变+对勾、App 行彩色图标（占位色块可接受，真实图标可后续换）
- [ ] 录制态回归：开始录制后波形/时间轴/VU 正常显示（UI-001/002 已验证行为不回退）
- [ ] `build-app.sh` exit 0；SDK 单测 77/77 不回退；截图证据落 `docs/证据/`

### FEAT-001 语音转文字（录音→文字→App 内查看→导出 MD） | P1 | [done] ｜ 标准 2026-10-11 老板批准 · 16:12 老板签收

**预估**：3-4天（S0-S3，见方案 §七）

> 来源（2026-10-11）：老板提出「音频转文字，越快越准，App 内可看，可导出 MD」。小J 完成调研，方案全文：`docs/需求/FEAT-001-语音转文字技术方案.md`（旧号 REQ-TRANSCRIBE，2026-10-11 按新编号规范迁移，文档已同步改名）；全球引擎成本/精度整理版附录：`docs/需求/FEAT-001-附录-全球STT引擎成本与精度对比.md`。
> 方案结论：双引擎——默认 Apple SpeechAnalyzer（macOS 26 原生，实时出字，中文 CER 7.97 与 Whisper Large 打平）；高精模式 whisper.cpp large-v3-turbo（Metal，英文更准）。本机 M4 Pro + macOS 26.2 条件全满足。
> **S0 已完成（2026-10-11 13:45-13:50）**：报告 `docs/需求/FEAT-001-S0-yap实测报告.md`。yap 源码构建（brew/SwiftPM 默认 sandbox 被拦，`--disable-sandbox` 绕行）；TTS 对照客观 CER≈1%（2.0s/41.4s）、真实对话 6min→4.15s、12.5min→6.97s（远超「5min≤30s」标准线 7 倍）。剩余验收：老板主观认可转写准确率（看 `docs/证据/feat001-s0/testC-full-output.txt`）。下一步 S1（AppleSpeechEngine + 实时流）。
> **S1 已完成（2026-10-11 14:00-14:40，老板「001 认可继续」后开工）**：
> - Kit 新模块 `Sources/Transcription/`（models + engine 协议 + AppleSpeechEngine）：文件转写 + 实时会话（AsyncStream<AnalyzerInput> + AVAudioConverter 转引擎目标格式）
> - 录制器 PCM 旁路：协议新增 `onAudioBuffer`（Mic tap / AudioCallbackHandler / Mixed 混音后三处插桩），多录制器只绑第一个（混音模式天然覆盖双源）
> - App 层 `TranscriptionService`（.arlock 解密→临时 m4a→转写→`<uuid>.atranscript.json` 持久化）+ `LiveTranscriptionCoordinator` + LiveTranscriptPanel（主窗口下方浮动条，volatile 灰/定稿黑）
> - 录制链路接线：开始→预热会话+面板；onRecordingStarted→绑定旁路；停止→finishAndCollect；加密管线→文稿落 .arlock 旁；失败/空录音→cancel
> - **SDK 关键事实（实测）**：① `Result` 无 `isVolatile`，volatile 判定 = `result.range` 与 `analyzer.volatileRange`（actor 属性需 await）相交；② `audioTimeRange` 挂在 AttributedString 的 run 属性；③ yap 实测**不显式 allocate**（reserve+install 即可，方案 §4.2 初稿有误已修正）；④ App 是 swiftc 平铺同模块编译，**不能 import AudioRecordKit**
> - 自验：`build-app.sh` exit 0（31s 零错误）；Kit 单测 77/77 PASS（`xcrun swift test --disable-sandbox`，WorkBuddy 沙箱内 SwiftPM 需此开关）；App 冒烟启动正常。**待老板真机录音验收**「说话后 ≤2s 出字 + 停止后 .arlock 旁出现 .atranscript.json」
> 云端验证拆独立单排后（裁决规则见方案 §6.3）；whisper.cpp 高精模式 = S4 拆独立单。
> **S2 落码完成（2026-10-11 15:23-15:28，老板「继续跑 TODO」开工）**：
> - 新组件 `TranscriptPanelView`（编辑器底部抽屉，toolbar 与 statusBar 之间，180pt/0pt 切换）：分段文稿（时间戳+字数标签）+ 元信息行 + 「导出 MD」「生成转写/重新转写」按钮 + 空态引导
> - 入口：编辑器 toolbar 播放组右侧新增「文」切换按钮（`editorToolbarDidToggleTranscript`，高亮态）
> - 加载：`loadAudioWithSession` 成功后自动读 `.atranscript.json`（有→展示，无→空态）
> - 手动转写：`TranscriptionService.transcribeRecording`（旧录音/无文稿兜底），进行中按钮置灰「转写中…」
> - 导出 MD：NSSavePanel → `TranscriptPanelView.markdown`（标题+元信息+全文+带时间戳分段），写入后**读回断言含全文前 20 字**（硬验证）
> - EditorStatusBar 加 `updateStatus`（临时消息 7s 自动清）；UXEventLog：transcript_toggle / transcribe_manual / transcribe_done / transcript_export
> - 自验：build 28s 零错误（UTType.markdown 不存在→filenameExtension("md") 兜底）+ 冒烟 PID 42452。**S2 第一轮真机验证（15:47 老板录 Chrome 英文演讲 48s）打回三点** → S2.5 修复：
>   ① 实时转写「不行」+ ② 英文无分词乱文 = **同根因：语言错配**（Lang: Auto→zh-CN 引擎听英文，UXEventLog live_start locale=auto + 文稿 zh-CN 296 字无空格坐实）→ 修复：**主窗口状态栏新增「文: 自动/English/中文」选择**（录制前可设，UserDefaults 与文稿面板同源，实时会话与手动转写共用）；Transcript.joinsWithSpace——非 CJK 语言段间补空格（init 全文拼接 + LiveSession storeResult 累积两处）。
>   ③ 导出「没反应」：UXEventLog transcript_export ok:true bytes:837——**导出其实成功**，反馈写进了嵌入模式下隐藏的 statusBar → 修复：反馈改显示在文稿面板元信息行（showStatus，主色 8 秒），转写完成/失败同走此处。
> - S2.5 自验：build 通过 + 冒烟 PID 67595 + Kit 77/77。**第二轮真机验收（16:12 老板签收「录完了也导出了」）全绿**：68.7s 英文演讲 → 手动转写 en-US 409 字（0.77s，~90x 实时），**分词标点完美**（桌面 `Google Chrome_20261011_160709.md` 1106 字节实证：`Knowing that I was gonna say that today...` 带空格带标点+时间戳分段），导出读回断言 ok。FEAT-001 全单 done。
> - 遗留观察项（不阻塞）：录制**开始前**选好 English 的实时浮条英文出字链路未单独目击（live_start 显示 auto——老板是录完才切语言；引擎/分词/导出已由手动转写路径全验证）
> - S3 打磨（重转写按钮语义、多语言混说、标点后处理）为可选后续，按需开单

---

## 未来池

> 旧 backlog（BUG-2~5、REQ-2.0 系列、V1.2/V1.3）见 `docs/归档/TODOS-archive-20260920.md`。
> 捡回规则：loop 协议验证后（第一轮 2 张单跑通），逐条补验收标准回池，按 P0 > P1 > P2 顺序。
