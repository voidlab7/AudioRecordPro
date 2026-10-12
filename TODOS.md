# 需求队列（TODOS）— Loop 需求池

> **唯一状态真相**：单子/验收标准/状态/证据。开发方式唯一：`docs/LOOP.md`（宪法）；自动加载版 `.codebuddy/rules/loop-protocol.md`。  
> 状态六态：todo / doing / self-verify / ready-for-review / blocked / done。  
> 老板只做三件事：签标准（定义）、拍板（裁决）、看证据（签收）。  
> **签收即归档**（2026-10-12 老板定）：单子签收当天，正文迁 `docs/归档/TODOS-done-YYYY-MM.md`，本池只留索引行——控制每次「重读池」的上下文成本。  
> **编号规范**：已移 `docs/LOOP.md §十一`（TYPE-NNN 全局递增、入池查重、历史单不回改）。品牌：**Loocap｜路文**（2026-10-11 起，旧名 Tapture 见 `docs/产品/品牌更名-2026-10-11.md`，历史单不回改）。  
> **双会话分工**：入池权归需求台；执行侧状态上限 `ready-for-review`；小粒度精确编辑；写前重读；**单间必重读池**（2026-10-12 增，铁律 4）。

## 池速览（一行一单，签收/入池即更新此表）

| 单号         | 标题                                 | P  | 状态          | 备注                                     |
| ---------- | ---------------------------------- | -- | ----------- | -------------------------------------- |
| LOOP-05    | XCUITest 11 个失败修复 ≡INFRA-001       | P1 | **blocked** | 等老板在 WorkBuddy 外跑 `scripts/test-ui.sh` |
| LOOP-08    | 录音准备态与实时采集态视觉分离 ≡UI-002            | P1 | **blocked** | 主链路已通，细项留日常观察                          |
| FEAT-002   | 导出 txt（实时翻译砍掉）                      | P1 | todo · 待签  | 10-12 20:04 老板口述入池，标准草案待签               |
| UI-009     | Dock 图标观感偏小——可见边界调大        | P2 | todo · 待签  | 10-12 20:05 老板截图对比入池，标准草案待签 |
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

### INFRA-003 App 更名 Loocap（代码侧 + Bundle ID 迁移） | P1 | M · 半天 | [ready-for-review · 2026-10-12 实施完成待签收]（标准 17:47 老板「跑 Loop」视为签署，先例 INFRA-002）

> 来源（2026-10-12 16:24 老板指令）：App 名字重构为 **Loocap**，Bundle ID 同步改为 **`com.microlab.loocap`**（老板定；microlab.top 为 MicroV 已有域名，反向域名约定成立）。  
> 背景与残留清单：`docs/产品/品牌更名-2026-10-11.md` §四（10-11 已完成对外品牌切换，代码侧本单执行）。实测代码残留 27 处/10 文件 + pbxproj 30 处。

**做什么**：

1. **Bundle ID**：`PRODUCT_BUNDLE_IDENTIFIER` 全 target（App/KitTests/UITests）`com.voidzhang.audio-record-mac` → `com.microlab.loocap`
2. **显示名**：Info.plist ×2（`CFBundleDisplayName`/权限文案）、pbxproj Target/Product 显示名 → Loocap（工程文件名 `AudioRecordMac.xcodeproj` 不动）
3. **L10n**：en `Localizable.strings` + zh `InfoPlist.strings` 中名称改 Loocap；`TranscriptPanelView.swift` 1 处可见文案
4. **内部标识符**：`TaptureTheme.swift` → `LoocapTheme.swift`（3 处）+ `ThemeAndMonitorTests.swift` 同步（14 处）
5. **数据迁移**：提供迁移步骤/脚本——旧容器 `~/Library/Containers/com.voidzhang.audio-record-mac/` 的录音库搬到新容器；**实测 .arlock 在新容器可解密**（确认加密密钥绑机器而非 bundle id，若绑 bundle id 需密钥迁移方案再议）
6. **连锁同步**：e2e/判活脚本按窗口属主名定位的用例（CGWindowList「Tapture」）全部改 `Loocap`；`make_appicon.sh` 等脚本内路径引用核查

**已知代价（老板已拍板接受）**：改 Bundle ID 后**首次需重新授权**录屏/麦克风各一次（此后 INFRA-002 的 LoocapDev 稳定签名继续保证不再重复）。

**不做什么**：历史文档/证据行的 Tapture 不回改（10-11 定：旧名是当时事实）；官网 `/tapture/` 软链不动；不改工程目录名与 git 仓库名

**验收标准**（17:47 老板「跑 Loop」视为签署，先例 INFRA-002）：

- [x] `codesign -dv` 显示 `Identifier=com.microlab.loocap` + LoocapDev 签名（`Authority=LoocapDev`，`codesign --verify --deep --strict` ✓）
- [x] 窗口标题栏/窗口属主显示 **Loocap**（CGWindowList `owner=Loocap` 实证；TitleBarView 硬编码 "AudioRecord" 一并清除）；Dock 显示名走 CFBundleDisplayName=Loocap（CFBundleName 同步）
- [x] **数据迁移验证**：旧容器 3.2G 完整复制（54 条 wav + arlock 库）；硬验证两件：① afinfo 读新容器 wav ✓（206s/2ch/44.1kHz）；② **.arlock 解密 PASS**（临时 XCTest 实证 QQMusic_20260821_205809 257.6s/49.5MB 在新 Bundle ID 下解密成功——密钥绑机器不绑 bundle id）
- [x] 全仓 grep `Tapture`：代码/资源/脚本层清零。豁免清单（历史事实不回改）：docs/归档/*、docs/需求/REQ-i18n、docs/产品/品牌更名-2026-10-11.md、TODOS.md 历史行、CODEBUDDY.md、roles/Tab/AGENT.md、build/ 与 .build/ 产物（重生成）
- [x] `build-app.sh` exit 0；SDK 单测 77/77 PASS（含改名后 LoocapTheme/ThemeAndMonitorTests）
- [x] e2e/判活窗口名同步：`window_shot.py` 按 owner=Loocap 命中（`docs/证据/INFRA-003-标题栏Loocap-2026-10-12.png`）
- [ ] **待老板操作**：重新授权一次（录屏+麦克风，改 Bundle ID 后 TCC 清零）→ 录系统音频落盘成功（权限弹窗将显示 Loocap）
- 附带修复：project.yml 三 target bundle id、scripts/tc011 与 ux_replay 旧 id、xcodegen 重生成 pbxproj
- 证据：`docs/证据/INFRA-003-主界面Loocap标题-2026-10-12.png`、`docs/证据/INFRA-003-标题栏Loocap-2026-10-12.png`

### FEAT-002 转写导出 txt（实时翻译砍掉） | P1 | S | [todo · 待签]

> 来源（2026-10-12 20:04 老板口述）：「实时翻译」这个功能（含其弹窗 UI 设想）**先不带了**；重点是转文字——**转完可以直接看到**，然后**可以导出成 txt**。
> 现状盘点：①代码/资源层无任何翻译功能实现（grep 翻译/translation 零命中）——实时翻译属规划砍单，无删除工作量；②转写结果已内嵌编辑器 TranscriptPanelView 直接可见（FEAT-001 交付）；③当前导出仅 Markdown 格式（FEAT-001），**txt 导出为本单主要工作量**。

**做什么**：①导出格式增加 **.txt**（纯文本：标题 + 逐段时间戳 + 正文，无 Markdown 语法标记），与现有 MD 导出并列可选；②验收确认「转写完成即所见」链路（TranscriptPanelView 转完直接显示，无需打开文件）。

**不做什么**：不做实时翻译（含弹窗/浮窗 UI，老板明确砍掉）；不动 MD 导出；不动转写引擎（SpeechAnalyzer 双引擎）

**验收标准**（待签）：
- [ ] 导出菜单出现 txt 选项，导出的 .txt 可直接打开阅读（标题 + 时间戳分段 + 正文，无 Markdown 标记）
- [ ] MD 导出不回退（原路径回归）
- [ ] 转写完成即所见：录音 → 转写 → 编辑器内直接显示全文（截图证据）
- [ ] `build-app.sh` exit 0；SDK 单测 77/77 PASS

---

### UI-009 Dock 图标观感偏小（可见边界调大） | P2 | S | [todo · 待签]

> 来源（2026-10-12 20:05 老板截图）：Dock 里 LC 图标与其他 App 并排时**明显小一圈**（截图实测：邻居 tile 宽 ~105px，LC ~80px，小 ~24%）。
> **实测排查（20:10）**：icns 各档方框占比 512 档 97% / 128 档 96% / 32 档 91%，四角 alpha=255 无透明边距——**图标文件本身没做小**。观感偏小主因：LC 暗底（#1A1A1C）在深色 Dock 背景上**边缘融合**，可见边界只剩灰描边方框内缩一圈；邻居 App 亮色满铺边缘清晰故显大。

**做什么**：提升图标的**可见边界尺寸与对比**——①灰描边加亮/加粗（如 #C0C0C0、2px→3px）或描边外加一圈微亮晕（低透明度白边），让暗底在深色 Dock 上有清晰外缘；②必要时主体（LC 字母 + 描边方框）再放大 3-5% 满铺画布。改 `scripts/make_appicon.sh`（可复跑管线）实现，不改设计稿正本。

**不做什么**：不改 LC 字标设计本身；不动正本 jpg；不动 Dock 相关代码（纯资源层）

**验收标准**（待签）：
- [ ] Dock 实拍：LC 可见 tile 宽度 ≥ 邻居 App 的 95%（同屏截图对比量测）
- [ ] 深色/浅色背景下图标外缘均清晰可辨（两套截图）
- [ ] 各档 icns（16-1024）方框占比 ≥ 95%，四角不透明
- [ ] `make_appicon.sh` 重跑生效；`build-app.sh` exit 0

---

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
| FEAT-001         | 语音转文字（SpeechAnalyzer + 导出 MD）  | 2026-10-11 |
| INFRA-002        | 稳定开发签名（LoocapDev 证书）           | 2026-10-12 |

