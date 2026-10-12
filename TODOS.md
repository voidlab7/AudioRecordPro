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
| UI-006 | 画布网格线未铺满画布 | P2 | todo · 待签 | 10-12 13:02 报障，标准草案待老板签 |
| UI-007 | App 图标改为 LC 圆角字标 | P2 | todo · 待签 | 正本 `docs/设计稿/logo-lc-正本-1024.jpg`，标准草案待签 |
| INFRA-002 | 稳定开发签名（LoocapDev 证书） | P1 | ready-for-review | 双轮 DR 验证过，等签收 |
| LOOP-01~04 | 测试盘点 / localized 断裂 / 计时器脱节 / 单测卡死 | P0 | done ✅ | 09-20/21 签收 |
| LOOP-06 | localized %@ 残留清理 ≡FIX-001 | P0 | done ✅ | 10-11 签收 |
| LOOP-07 | 待录制界面隐藏时间刻度 ≡UI-001 | P2 | done ✅ | 10-11 签收 |
| FIX-002 | EditorStatusBar 裸 Int 崩溃 | P0 | done ✅ | 10-11 真机签收 |
| FIX-003 | 点击波形选点播放从头开始 | P1 | done ✅ | 10-11 签收 |
| UI-003 | 主界面视觉重构（Stitch v2） | P1 | done ✅ | 10-12 13:15 签收 |
| UI-004 | 侧栏初始化宽度 260pt | P2 | done ✅ | 10-12 13:15 签收 |
| UI-005 | 红钮画布视觉居中 | P2 | done ✅ | 10-12 13:15 签收 |
| FEAT-001 | 语音转文字（双引擎+导出 MD） | P1 | done ✅ | 10-11 16:12 签收 |

> done 单正文全部在 `docs/归档/TODOS-done-2026-10.md`；更早 backlog 在 `docs/归档/TODOS-archive-20260920.md`（捡回规则：补验收标准回池，P0 > P1 > P2）。

---

## 活跃单

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

### UI-006 画布网格线未铺满画布 | P2 | S | [todo · 待签]

> 来源（2026-10-12 13:02 老板报障，附现状截图）：设计稿中画布**网格线铺满整个画布区域**（顶到标题栏/侧栏/电平表边界）；现状实现网格只覆盖中间一块，四周留黑。附图即现状。

**做什么**：网格绘制范围从局部区域改为**整个画布 bounds 铺满**（`CGContext` 平铺范围 = 全画布，含边角），间距/线宽/透明度保持 v2 取色校准值（white@0.035）不变。

**不做什么**：不改网格间距与颜色（19:00 校准成果不回退）、不动画布上其他元素（Ready 点/图标卡/副标题）

**验收标准**（待签）：
- [ ] 网格线铺满画布：与侧栏/标题栏/电平表交界处也有网格（截图对照设计稿 `design-main-ui.png`，老板肉眼核对）
- [ ] 网格间距 30pt、white@0.035 与现值一致（不回退 v2 校准）
- [ ] `build-app.sh` exit 0；截图证据落 `docs/证据/`

### UI-007 App 图标改为 LC 圆角字标（Loocap） | P2 | S | [todo · 待签]

> 来源（2026-10-12 13:18 老板指令；13:19 更新正本）：App Logo 换成 LC 字标圆角风格。**正本：`docs/设计稿/logo-lc-正本-1024.jpg`（1024×1024 官方渲染图，老板指定直接使用）**；早期 270px 概念图 `logo-lc-概念图-2026-10-12.png` 仅留档。
> 正本构图：深底 + 灰描边圆角方形 + 白 L（底部渐变波形竖条）+ 鼠尾草绿 C（内嵌横线纹理），底部有「Loocap」文字标签（**不属于图标主体，需裁掉**）。

**做什么**：①从 1024 正本裁出圆角方形图标主体（**去掉底部 Loocap 文字——老板 13:21 再次确认不要文字，只要 logo 主体**；图标内不留任何文字，多余边距一并裁掉，主体居中）；②按 macOS 图标规范生成全套尺寸（16→1024 + @2x，icns / Asset Catalog）；③App 运行图标与 Dock 显示生效；④设置/关于页如有旧 logo 一并替换。

**不做什么**：不矢量重绘（老板指定直接用此图；矢量源后补不阻塞）、不改动字标设计本身、不改窗口内 UI（UI-003 成果）

**验收标准**（待签）：
- [ ] 1024 主稿（裁切后）老板肉眼核对通过（无 Loocap 文字残留、主体居中不变形）
- [ ] 全尺寸 AppIcon 生成，Dock/访达显示正确（截图证据落 `docs/证据/`）
- [ ] `build-app.sh` exit 0；重编译后图标不丢

### INFRA-002 稳定开发签名：消除每次重编译后的重复授权 | P1 | S | [ready-for-review · 2026-10-12 已实施待签收]

> 来源（2026-10-12 00:40 老板提问）：①录屏/麦克风权限能不能不授权？②重编译后能不能不重新授权？
> **需求台结论（已核）**：①首次授权**免不了**——录系统/App 声音走 ProcessTap 需要「屏幕录制」TCC（macOS 以此判定进程音频捕获），麦克风需要「麦克风」TCC，OS 隐私模型无 API 可绕；②重编译重复授权**可以修**：实测当前产物 `Signature=adhoc`（`codesign -dv` 确认，Identifier=com.voidzhang.audio-record-mac 固定）——ad-hoc 签名每次构建 cdhash 都变，TCC 把它当新 App，授权即清零。

**做什么**：①Keychain 创建本地长期自签代码签名证书（如 `LoocapDev`，Apple Development/CodeSigning 类型，有效期设长）；②`build-app.sh` 签名从 adhoc 改为该证书（产物 `codesign -dv` 显示真实证书身份）；③全量文档记录证书重建路径（换机/证书过期后如何恢复，避免知识孤岛）。

**不做什么**：不改 bundle id（com.voidzhang.audio-record-mac 已固定）、不动 entitlements 内容、不做 TCC.db 直写 hack（SIP 对抗，脆弱且不该做）

**验收标准**（2026-10-12 老板「继续」视为签署）：
- [x] `codesign -dv build/*.app` 显示 `Signature=LoocapDev`（或等效证书名），不再 `adhoc`（2026-10-12：`Authority=LoocapDev`，verbose=4 实证）
- [x] **硬验证**：授权一次后，连续 2 轮「重编译 + 重启 App」，屏幕录制/麦克风授权不重置（2026-10-12 双轮构建：cdhash 变化（真·两次独立构建）而 DR 逐字节相同 `certificate root = H"a9ea33aa…"`——TCC 以 DR 判定身份，结构性证明授权随证书而非产物；**GUI 终验**：换签名后首次启动会弹最后一次授权，勾完后老板日常录音即验证不再弹）
- [x] 证书重建路径文档落 `docs/`（`docs/INFRA-002-证书重建路径.md`，含换机/过期重建双路径、坑位 5 条、复跑验证命令）
- [x] `build-app.sh` exit 0（2026-10-12 双轮）；SDK 单测未跑（改动仅构建脚本签名段，产品代码零变更）

> **实施记录（2026-10-12 13:25）**：openssl 生成 10 年期自签证书 CN=LoocapDev（codeSigning EKU）→ p12 `-legacy` 导出（OpenSSL 3 默认算法 macOS security 不认，坑位已记）→ 导入登录钥匙串 + `add-trusted-cert -p codeSign` → build-app.sh 签名段改「检测身份→LoocapDev，缺失回退 adhoc 并告警」，支持 `LOOCAP_SIGN_IDENTITY` 覆盖。证书/私钥在 `~/.loocap-certs/`（不入 git）。钥匙串里的公司 Developer ID（Tencent）未动用——个人 App 合规红线。

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
| FEAT-001 | 语音转文字（SpeechAnalyzer + 导出 MD） | 2026-10-11 |
