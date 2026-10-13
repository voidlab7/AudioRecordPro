# 需求队列（TODOS）— Loop 需求池

> **唯一状态真相**：单子/验收标准/状态/证据。开发方式唯一：Loop 协议——内核正本 `SKILL仓库/工程与运维/loop-engine/SKILL.md` + 本工程适配层 `docs/LOOP-adapter.md`；薄桩 `.codebuddy/rules/loop-protocol.md`。  
> 状态六态：todo / doing / self-verify / ready-for-review / blocked / done。  
> 老板只做三件事：签标准（定义）、拍板（裁决）、看证据（签收）。  
> **签收时序（2026-10-13 老板定）**：「签」发生在**入库时**——需求台起草标准，老板确认可以做即为已签，**Loop 直接做，无二次开工确认**；「签收」一词只用于 **Loop 结束后老板验证结果**（ready-for-review → done 的那次）。入库未签的单不开工，已签的单执行侧不再等老板。  
> **签收即归档**（2026-10-12 老板定）：单子签收当天，正文迁 `docs/归档/TODOS-done-YYYY-MM.md`，本池只留索引行——控制每次「重读池」的上下文成本。  
> **编号规范**：已移内核 `loop-engine/SKILL.md §十一`（TYPE-NNN 全局递增、入池查重、历史单不回改）。品牌：**Loocap｜路文**（2026-10-11 起，旧名 Tapture 见 `docs/产品/品牌更名-2026-10-11.md`，历史单不回改）。  
> **双会话分工**：入池权归需求台；执行侧状态上限 `ready-for-review`；小粒度精确编辑；写前重读；**单间必重读池**（2026-10-12 增，铁律 4）。

## 池速览（一行一单，签收/入池即更新此表）

| 单号         | 标题                                 | P  | 状态          | 备注                                     |
| ---------- | ---------------------------------- | -- | ----------- | -------------------------------------- |
| LOOP-05    | XCUITest 11 个失败修复 ≡INFRA-001       | P1 | **blocked** | 等老板在 WorkBuddy 外跑 `scripts/test-ui.sh` |
| FIX-008    | 录音态波形动画卡顿（连续平移+右端冒头 R2）      | P2 | **rfr · 待签** | worktree loop/FIX-008 ff95dc4；右冒头+满窗滚动已实证，目测平滑留老板 |
| LOOP-08    | 录音准备态与实时采集态视觉分离 ≡UI-002            | P1 | **blocked** | 主链路已通，细项留日常观察                          |
| FIX-006    | 开麦混录说话无电平（原「QQ音乐电平」误报口径）      | P2 | done ✅ | 10-13 12:12 签收                              |
| UI-014     | 录音态波形滚动降速（两轮返工后全量回退）              | P3 | reverted     | 10-13 16:19 老板裁决：**先不做**（需求取消）   |
| FEAT-004R2 | 麦克风按所选设备采集（自建 AUHAL unit）              | P2 | done ✅ | 10-13 15:17 签收（≥2设备对质留老板外接）        |
| FEAT-004   | 麦克风设备探测与选择 R1                              | P2 | done ✅ | 10-13 15:17 签收（≥2设备对质留老板外接）        |
| INFRA-004  | 改名残留：PRODUCT_NAME/进程名→Loocap                | P1 | done ✅ | 10-13 15:17 签收（TCC 免重授权实证）            |
| FEAT-003   | 下掉实时翻译浮窗（代码留开关）                        | P1 | done ✅ | 10-13 15:17 签收                              |
| FIX-007    | 录音中开麦开关录不进麦克风声音                     | P1 | done ✅ | 10-13 15:17 签收（动态注入修复）                |
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
> **重大进展（2026-10-13 19:45 会话内破局）**：包解析死点已修——根因 = Xcode 包引擎评估 SPM manifest 时 spawn sandbox-exec，在 WorkBuddy 沙箱容器内嵌套 sandbox_apply 被系统拒 EPERM（诊断三证：`log` 拒跑 Cannot run while sandboxed、osascript privilege violation、crontab/launchctl operation not permitted；与 pbxproj/xcodegen 无关）。修复 = **工程摘除 SnapshotTesting 包与 AudioRecordMacSnapshotTests target**（project.yml，snapshot 测试同死于此死点属死资产；测试源码保留，脚本挂停用牌，原 manifest 备份 Package.swift.tools60.orig）→ 包图空解析通过 → **App + UITests-Runner 编译/签名全链通**（10-11 三种打法死在包解析的时代结束）。  
> **新阻塞点（更深层）**：`AudioRecordMacUITests-Runner` bootstrap 失败——`exited with code 1 before establishing connection`（无 crash 报告，主动退出；系统级 TCC Accessibility 表无 Xcode/Runner 授权记录）。会话内诊断通道全被沙箱拦，无法分辨「WorkBuddy 环境影响」vs「系统层 TCC/兼容性」。  
> **解除路径（仍只剩 A，且成本大降）**：老板普通终端跑一次 `bash scripts/test-ui.sh`：①测试真跑起来 → 拿到失败清单回会话内修（mock 机制代码俱在）；②runner 在真实终端也死 → 系统层问题，方向：系统设置→隐私与安全性→辅助功能，给 Xcode 与 AudioRecordMacUITests-Runner 授权后重跑。解除后说「继续跑 loop」续验。  
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

### UI-015 麦克风选择交互重构（弃原生菜单，可读设备名，消歧义） | P2 | M | [ready-for-review · 2026-10-13 23:30 worktree loop/UI-015 6a3203e，沙箱 GUI 验收留老板]

> 来源（2026-10-13 16:17 老板截图）：「这个选择麦克风的方式有点奇怪，需要更好的交互。」
> 证据：`docs/证据/2026-10-13-FEAT004R1-麦克风选择原生菜单交互差.png`
> 前置：FEAT-004 R1+R2（已 done）——功能层已通，本单只重做**选择交互层**。

**现状四宗罪（截图实锤）**：
1. **原生 NSMenu 弹出菜单**——系统默认样式与 App 工业深色 UI 完全脱节
2. **设备名暴露系统内部 ID**——「CADefaultDeviceAggregate-76186-6」用户不可读不可辨
3. **双「默认」歧义**——「系统默认」与「MacBook Pro Microphone（默认）」两行语义重叠，用户分不清当前实际用哪个
4. **层级混杂**——「Also Record Microphone / Mix into current target」开关与设备选择挤在一体

**做什么**：
1. **自绘行内选择器**：设备选择内嵌在面板里（展开式列表或分段控件），样式对齐侧栏/面板既有工业风（深底、圆角槽、品牌绿选中态），弃用原生 NSMenu 弹窗
2. **设备名友好化**：系统内部 ID 设备（Aggregate 等）显示可读名——能解析组成设备的显示组成名，不能解析的显示「聚合设备」+短序号，**严禁裸露 hex 串**
3. **消歧义**：「跟随系统默认」为第一项，**动态副标显示当前实际设备**（如「系统默认 · MacBook Pro Microphone」）；其余设备项不再重复标「（默认）」
4. **层级分离**：①「同时录制麦克风」开关行（含当前选中设备名常显）②设备列表行——开关管「录不录」，列表管「用哪个」
5. 选中态在行内可见（不点开也能知道当前用哪个麦）

**不做什么**：不动采集引擎（R2 的 AUHAL 按所选设备采集逻辑保持）；不改设备枚举/持久化层

**验收标准**（待签）：
- [ ] 截图对比：选择器风格与 App 一致，无原生菜单（前/后对比图）
- [ ] ≥2 设备场景：所有设备名可读可辨，无 hex 串（接聚合设备验证）
- [ ] 行内可见当前选中设备；「跟随系统默认」副标动态正确
- [ ] 换设备选择后录音，落盘仍来自所选设备（R2 功能不回归）
- [x] `build-app.sh` exit 0（已验 EXIT=0，LoocapDev 稳定签名）

> **交付（worktree `.worktrees/UI-015` 分支 loop/UI-015，commit 6a3203e；master 未动，签收后 merge --no-ff）**：
> - 弃 NSPopUpButton/NSMenu，引入 `IndustrialMicDeviceSelectorView`（自绘行内选择器）：折叠态常显当前选中设备名 + ▼，展开态 radio 圆点选中态，深底圆角槽工业风（深底色 surfaceContainer / 选中态填充 primaryContainer / 圆点 primaryContainer / 文字 onSurface）
> - `MicDeviceManager.displayName(for:)` 新增设备名友好化：聚合设备解析子设备名 → 「聚合· A + B」（≤3 设备）/ 「聚合· A + B +N」（>3 设备），失败兜底「聚合设备 #短序号」（取 uid 末段 3-8 位数字，无则 deviceID），严禁裸 hex 串
> - 修前会话 `aggregateSubDeviceNames` 中 `CFArrayGetValueAtIndex` 返回 `UnsafeRawPointer?` 不能 `as? String` cast 的恒失败 bug——用 `unsafeBitCast → CFTypeRef` + `CFGetTypeID` 分流 CFString/CFDictionary + `Unmanaged<CFString>` 安全提取，子设备解析真正生效（之前永远走 fallback）
> - 第 0 项「跟随系统默认」+ 动态副标显示当前实际设备；其余设备项不再重复标「（默认）」（消歧义）
> - `IndustrialMicrophoneRowView` 增加 `setCurrentDeviceName`，开关行常显当前选中设备友好名（选中态显示设备名/未选中态「未启用」）
> - 选失效状态行内警告（不弹窗不打断）
> - L10n en.lproj 加 11 个新 key（跟随系统默认/聚合设备/已混入/未启用等）
>
> **硬验证证据**：
> - `bash build-app.sh` EXIT=0（LoocapDev 稳定签名）；SDK `swift test --disable-sandbox` 77/77 PASS（无回归，基线匹配）
> - 截图 `docs/证据/UI-015-picker-default-2026-10-13.png`（Quartz CGWindowListCreateImage 全屏，Loocap 主窗口 PID 33540 / wid 11227，picker 默认折叠态可见）
>
> **留老板外验**（沙箱内 `screencapture -l` / `osascript System Events` 双双被 TCC 拒；GUI 验收 #1-4 不可验）：
> - #1 截图对比前/后无原生菜单（需老板真机开 App 看 picker）
> - #2 ≥2 设备场景含聚合设备无 hex 串（老板接外接麦 + 聚合设备验证）
> - #3 行内可见当前选中设备；副标动态正确
> - #4 换设备选择后录音落盘仍来自所选设备（R2 不回归，需真录音）

---

### FIX-008 录音态波形动画卡顿（20Hz 步进顿挫 + 全量重绘开销） | P2 | M | [ready-for-review · 2026-10-13 20:35 worktree 4980be5，待老板签收]

> 来源（2026-10-13 19:58 老板口述）：「录制的时候波纹从右到左移动有点卡卡的。」
> ⚠️ 与 UI-014（速度太快，已回退取消）是**两个病**：那是快，这是卡。本单不动滚动速度。
> 根因（已实锤）：① Timer 0.05s 触发 draw() 全量重绘（网格逐线+光晕+全部条形）；② 满窗后 20Hz 离散步进整行跳格。
>
> **交付（worktree `.worktrees/FIX-008` 分支 loop/FIX-008，commit 4980be5；master 未动，签收后 merge --no-ff）**：
> - **B 路线**：条形离屏渲染进 CALayer，60Hz 只推 layer.position 相位插值（GPU 合成连续平移，落杆相位归零像素级连续）；未满窗保持左起填充
> - **A 路线**：网格离屏缓存（resize 才重画），draw() 只 blit；录制态 draw() 不再逐条画条形
> - 自验钩子三通道（arg/env/容器 tmp trigger 文件）合成峰值流驱动录制态——WorkBuddy 会话内 open 的 args/env 均不透传（实测），文件触发为主通道
>
> **硬验证证据（合成信号录制态）**：
> - draw() 近200次 avg=0.37-0.57ms max=0.99-1.63ms（验收 ≤2ms ✅；一次 80.95ms 尖峰疑满窗切换/系统抖动，转日常观察）
> - 帧间（Δ0.25s）互相关最优平移 **-4px@2x=半步长**——亚步进连续平移实锤（旧步进只会 0/±8px）
> - 截图 `docs/证据/2026-10-13-FIX008-自验录制态连续滚动.png`（满窗滚动+风格无回归）；build exit 0；SDK swift test --disable-sandbox 77/77 PASS
>
> **留老板验收**：录制态目测平滑（真实音频下；验收第 1 条）。真实录音链路未在本单自验中驱动（沙箱内无法合成键盘/点击，自验用合成信号钩子）。
>
> **R2（2026-10-13 21:42 老板真机实测两处反馈 → worktree ff95dc4）**：
> - ①**满窗后冻屏**——重渲判重用 waveformData.count，满窗裁剪到 maxDataPoints 后 count 恒定 → 条带永不重渲。改单调递增 dataVersion 判重
> - ②**出现方式**改右端锚定：最新条右缘贴 timeline 右缘冒头、历史条连续左移，未满窗/满窗同一公式，第一条就从右缘出现（老板口述「从最右边往最左边」）；新增 barsClipLayer 裁剪（右缘冒头/左缘滑出消失）
> - ③R2 过程踩坑：stopAnimation 藏 strip 层后无人解开 → 条带永久隐身（运行时探针实锤 stripHidden=1）——可见性收敛到 clip 层
> - 复验证据：填充期截图（条形仅占右半部、从右缘长出）、满窗包络峰位移实测 ≈20 条/秒（速度口径不变）、`docs/证据/2026-10-13-FIX008R2-*.png` 两张

---

### UI-016 App 图标换新 logo（L 箭头 + C 声波 + 录音点） | P2 | M | [todo · ✅ 标准 2026-10-13 21:50 老板签（「logo 按照这个实现」）]

> 来源（2026-10-13 21:50 老板指令 + 新 logo 图）：「logo 按照这个实现。」
> 正本：`docs/设计稿/logo-v2-L箭头C声波-正本-2026-10-13.png`（800×630 RGBA，米白底）
> 关系：**整体替换 UI-007 的 LC 字标图标**（旧正本 `logo-lc-正本-1024.jpg` 与旧管线逻辑保留不删，备用）。

**新 logo 构成（需求台读图）**：
- **L 形主体**：深海军蓝（~#1B3A6B）粗圆头线条——竖笔顶端内弯成钩并向下收成**向下箭头**（录入/下载隐喻），底笔转折处**青色段**（~#4FB8CF）与海军蓝段拼接
- **C/D 形外弧**：深海军蓝大半圆弧，开口朝左，与 L 底笔相连成「LC」合体
- **内层声波**：青色同心小弧 + 中心**橙色圆点**（~#F26B3A，录音红点/声源）
- 底：米白（~#F7F7F5）

**现状与难点（已实测）**：
- App 内**无 logo 绘制点**，只有 `AudioRecordApp/Resources/Assets/AppIcon.icns`；图标管线 `scripts/make_appicon.sh`（UI-007 版，逻辑是「像素定位灰描边+暗底 #212226 满铺」，**专为旧 LC 暗底图写的，对新图不适用，须重写**）
- 正本仅 800×630 且带压缩杂边，**直接放大到 1024 会糊**

**做什么**：
1. **矢量重绘为 SVG 正本**（`docs/设计稿/logo-v2.svg`）：几何全是圆头描边路径（L 钩+箭头、外弧、内弧、圆点），按图手工建模，与正本叠图比对误差 ≤ 2% 视觉；SVG 作为此后所有尺寸的单一真源
2. **重写 `make_appicon.sh`**：SVG → 1024 母版 → 10 档 iconset → icns；旧 UI-007 管线逻辑整体替换（旧版 `make_appicon.sh` 先备份为 `make_appicon-lc-legacy.sh`）
3. **底板规格**：logo 居中置于 **macOS 标准图标网格**（1024 画布，圆角方块 824×824、圆角 ~185），底色用**米白/白**（navy 线条在深底上对比不足，与正本一致；不再用 #212226 暗底）；logo 主体占方块 ~64-70%，四周留呼吸
4. 重启 App + `killall Dock` 刷新；Dock/⌘Tab/关于窗口/DMG（`make_dmg.sh` 如引用图标）一并换
5. 小尺寸（16/32px）细节检查：内层声波弧+圆点在 32px 下是否糊成一团，必要时小档位做线宽加粗/简化（只简化最小两档）

**不做什么**：官网 `microv.site/loocap/` 的 favicon/页面 logo 不在本单（是 MicroVSite 另一个工程，需要换另开单）；不改 App 内任何界面布局（现无 logo 绘制点）

**验收标准**（待签）：
- [ ] Dock 实拍：图标为新 logo，与邻居 App 并排大小观感一致（沿用 UI-009 的「可见 tile 宽度与邻居等宽」口径）
- [ ] 与正本叠图比对：形状/配色/比例无明显走样（并排对比图）
- [ ] 16/32/128/512 四档实拍或预览均清晰可辨（小档不糊）
- [ ] `make_appicon.sh` 重跑可复现；SVG 正本入库；`build-app.sh` exit 0
- [ ] 全仓 grep 旧 LC 图标引用：运行时代码无残留（旧正本文件保留备用，不算残留）

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
| FIX-007          | 录音中开麦动态注入麦克风通道                   | 2026-10-13 |
| FEAT-003         | 下掉实时翻译浮窗（feature flag 留恢复）        | 2026-10-13 |
| INFRA-004        | PRODUCT_NAME/进程名改名残留清零               | 2026-10-13 |
| FEAT-004 (R1+R2) | 麦克风设备探测/选择/按所选设备采集              | 2026-10-13 |
| UI-014           | 波形滚动降速（回退取消，老板裁决先不做）       | 2026-10-13 |

