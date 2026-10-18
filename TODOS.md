# 需求队列（TODOS）— Loop 需求池

> **唯一状态真相**：单子/验收标准/状态/证据。开发方式唯一：Loop 协议——内核正本 `SKILL仓库/工程与运维/loop-engine/SKILL.md` + 本工程适配层 `docs/LOOP-adapter.md`；薄桩 `.codebuddy/rules/loop-protocol.md`。  
> 状态六态：todo / doing / self-verify / ready-for-review / blocked / done。  
> 老板只做三件事：**确定需求审核**（定义）、拍板（裁决）、**交付验收**（看证据）。  
> **两道关卡术语（2026-10-14 老板定，「签收」「签」「待签」一词废止，防与交付验收混淆）**：
> - **确定需求审核**：发生在**入库时**——需求台起草标准，老板确认「这个需求可以做」。通过即「需求已审」，**Loop 直接做，无二次开工确认**；未通过/未审的单不开工。状态词：`待需求审核` → `已审核`。
> - **交付验收**：发生在 **Loop 结束后**——老板验证成果（ready-for-review → done 的那次）。状态词：`待验收` → `done ✅ 已验收`。
> - **对老板提问必须带前缀** `【需求审核·还没开发】` / `【交付验收·已做完】`，不得单独说「签/要签吗」（loop-engine 内核 §六，2026-10-15）。
> - 两道关卡在一张单上先后各一次，**不得互相借用词汇**：说「审核」只指需求，说「验收」只指交付。历史记录里的旧词「签收/已签」按其时点自行对应（入库前=需求审核，done 时=交付验收），**不回改**。  
> **验收即归档**（2026-10-12 老板定，原名「签收即归档」）：单子交付验收当天，正文迁 `docs/归档/TODOS-done-YYYY-MM.md`，本池只留索引行——控制每次「重读池」的上下文成本。  
> **编号规范**：已移内核 `loop-engine/SKILL.md §十一`（TYPE-NNN 全局递增、入池查重、历史单不回改）。品牌：**Loocap｜路文**（2026-10-11 起，旧名 Tapture 见 `docs/产品/品牌更名-2026-10-11.md`，历史单不回改）。  
> **双会话分工**：入池权归需求台；执行侧状态上限 `ready-for-review`；小粒度精确编辑；写前重读；**单间必重读池**（2026-10-12 增，铁律 4）。

## 池速览（一行一单，签收/入池即更新此表）

| 单号         | 标题                                 | P  | 状态          | 备注                                     |
| ---------- | ---------------------------------- | -- | ----------- | -------------------------------------- |
| UI-018     | 编辑页整体重设计：调研+两套设计稿（只出设计，不改代码） | P2 | done ✅ | **老板已拍板方案 B（轨道主导）**；设计稿+8 状态 PNG 进 git（be73879，10-17） |
| UI-019     | 编辑页重设计 R1：布局骨架（三段式 + 轨道头 88 + 转写分栏可拖拽） | P1 | done ✅ | 10-17 老板交付验收（merge a49d925）；真机拖拽/折叠留日常观察 |
| UI-020     | 编辑页重设计 R2：Clip 上下文工具条 + 选区读数可键入 + Trim 柄 | P2 | done ✅ | 10-17 老板交付验收（merge a53d5d1）；删除/切分缺口已拆 UI-022/UI-023 |
| UI-021     | 编辑页重设计 R3：转写联动（点句跳转 / 逐词高亮 / 搜索定位） | P2 | done ✅ | 10-18 老板交付验收（merge 053709d）；点句/搜索键入等交互留日常观察；正文迁归档 |
| FIX-009    | 录音态波形：按时间聚合+单源喂入（条间空隙根治，兼 UI-014 真根因） | P1 | done ✅ | 10-17 老板交付验收（merge 261d4a5）；临时探针拆除归 FIX-011 |
| FIX-010    | 两态波形幅度映射统一为全局线性（老板选 B；头部杂音不再强调可见） | P2 | done ✅ | 10-17 老板交付验收（merge 0e6d5ae）；running max 只增不减为 B 方案固有特性 |
| FIX-011    | 拆除 FIX009Probe 临时探针（Kit/Utils 4 打点）        | P3 | done ✅ | 10-17 老板交付验收（merge 0e6d5ae）；全仓零残留 |
| UI-022     | 删除选区命令 DeleteSelectionCommand（含 undo）+ 工具条删除按钮解除置灰 | P3 | **rfr · 待验收** | worktree loop/UI-022 0050b41；harness 12 断言 ALL PASS，删 0.5–1.5s afinfo 1.000000s、undo 逐位还原、全选空态不崩；顺带抓修逆向区间 Range 崩溃 |
| UI-023     | SplitAudioClipCommand WIP 桩转正（真 clip 拆分，P0 编辑器遗留） | P2 | **rfr · 待验收** | worktree loop/UI-023 d485683；口径 A（剪映语义切分不动时间轴），样本级 23 断言 ALL PASS + afinfo 两段各 1.000000s；clip 级独立裁剪降级回池 UI-024 |
| UI-024     | clip 级编辑迁移：区间视图模型（多段各自选中/拖动/裁剪） | P3 | todo · 待需求审核 | UI-023 降级回池（渲染/播放/导出单 buffer，AudioClip 模型零接线）；L 档，调研先行 |
| FIX-012    | 实时转写落盘竞态：finishAndCollect 完成晚于加密管线读 collectedTranscript，live 文稿经常丢 | P1 | done ✅ | 10-18 老板交付验收（merge 2509ffc）；双向握手（管线登记落点+finish 后到触发）；硬验证 79ms 竞态救回（via=handshake），证据 docs/证据/2026-10-17-FIX012-握手落盘硬验证.md |
| FEAT-005   | 转写词级时间戳（逐词高亮前置）——引擎升级或自定义对齐 | P3 | todo · 待需求审核 | UI-021 限制回池（TranscriptSegment 仅 start/end，Apple audioTimeRange 粒度不够逐词）；L 档，涉及转写引擎 |
| UI-017     | 麦克风选择器下拉箭头不明显                         | P3 | done ✅ | 10-17 老板交付验收（merge 7cdec2f）；hover/展开留日常观察 |
| LOOP-05    | XCUITest 11 个失败修复 ≡INFRA-001       | P1 | **blocked** | 等老板在 WorkBuddy 外跑 `scripts/test-ui.sh` |
| FIX-008    | 录音态波形动画卡顿（连续平移+右端冒头 R2）      | P2 | done ✅ | 10-17 老板交付验收（merge 409993b）；真实速度重核归 FIX-009 |
| LOOP-08    | 录音准备态与实时采集态视觉分离 ≡UI-002            | P1 | done ✅ | 10-17 老板交付验收；细项留日常观察                          |
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

### LOOP-05 XCUITest 11 个失败修复（mock 注入失效） | P1 | [blocked] ≡INFRA-001

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

### FIX-008 录音态波形动画卡顿（20Hz 步进顿挫 + 全量重绘开销） | P2 | M | [done ✅ 2026-10-17 老板交付验收]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`（merge 409993b）。

---

### LOOP-08 录音准备态与实时采集态视觉分离 | P1 | [done ✅ 2026-10-17 老板交付验收] ≡UI-002

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`。

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

---

### UI-017 麦克风选择器下拉箭头不明显 | P3 | S | [done ✅ 2026-10-17 老板交付验收（merge 7cdec2f）]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`（merge 7cdec2f）。

---

### FIX-009 录音态波形：按时间聚合 + 单源喂入（条间空隙根治，兼 UI-014 / FIX-008 真根因） | P1 | M | [done ✅ 2026-10-17 老板交付验收（merge 261d4a5）]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`（merge 261d4a5）。

---

### UI-019 编辑页重设计 R1：布局骨架（三段式 + 轨道头 88 + 转写分栏可拖拽） | P1 | L | [done ✅ 2026-10-17 老板交付验收（merge a49d925）]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`（merge a49d925）。

---

### FIX-010 录音态 / 编辑态波形幅度映射统一为全局线性（老板选 B） | P2 | M | [done ✅ 2026-10-17 老板交付验收（merge 0e6d5ae）]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`（merge 0e6d5ae）。
---

### UI-020 编辑页重设计 R2：Clip 上下文工具条 + 选区读数可键入 + Trim 柄 | P2 | M | [done ✅ 2026-10-17 老板交付验收（merge a53d5d1）]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`（merge a53d5d1）。
---

### UI-021 编辑页重设计 R3：转写联动（点句跳转 / 逐词高亮 / 搜索定位） | P2 | M | [done ✅ 2026-10-18 老板交付验收（merge 053709d）]

> 正文已迁 `docs/归档/TODOS-done-2026-10.md`（merge 053709d）。
---

---

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

---

### UI-022 删除选区命令 DeleteSelectionCommand（含 undo） | P3 | S | [ready-for-review · 2026-10-18 16:5x worktree 0050b41，待老板交付验收]

> 来源：UI-020 交付验收（merge a53d5d1）发现——工具条「删除」按钮**已置灰**，因命令层空缺：`EditorViewController.swift:1417` 原样 `break`，注释写「UI-020: 现状无删除命令，按钮已置灰；待新单补 DeleteSelectionCommand」。
> 同组：UI-023（切分桩转正），二者都是 UI-020「不新增编辑能力」条款下的回池项。

**做什么**：
1. 新增 `DeleteSelectionCommand: EditCommand`，落 `Views/`（与 `SplitAudioClipCommand.swift` 同目录同风格）：`execute` 删掉选区 `[start, end)` 样本后拼接（前段+后段）；`undo` 还原原 buffer（与 `TrimCommand` undo 语义一致，走现有 `EditHistory` 不改）；`description` 本地化「删除 @ %@s - %@s」
2. 接线 `EditorViewController:1417`：把 `break` 换成真建命令并入 undo 栈；删除后**播放头夹到选区起点**、选区清空、总时长/时间尺/波形立即刷新
3. **解除工具条删除按钮置灰**（`ClipContextToolbarView` 红字恢复可点）
4. 边界：无选区时按钮保持置灰；选区覆盖整段时删除后进入空态（波形空、时长 0），不得崩溃

**不做什么**：不做剪切/复制/粘贴；不做跨 clip 删除；不改 `EditHistory` 机制；不动转写面板

**验收标准**（待需求审核）：
- [x] 硬验证：2s 48kHz 正弦，删 0.5–1.5s → 落盘 `afinfo` 实测 **1.000000s**（UI-020 trim 同款脚本口径）✅（harness 12 断言 ALL PASS；前段+后段 48000 样本逐位保真零漂移）
- [x] undo → `afinfo` **2.000000s**；redo 再删 → 1.000000s ✅（undo 96000 帧逐位还原；redo 重放 48000 帧）
- [ ] 删除后播放头在选区起点、选区清空、时间尺与总时长同步（实拍）⏳（链路已接：performDelete → clearSelection → didSeekTo(删除点)（含 statusBar/转写联动/播放中无缝跳播）；AX 交互拦实拍，留真机验收）
- [x] 无选区按钮仍置灰；全选删除进空态不崩溃（实拍）✅（didChangeSelection 动态置灰/解除；全选产 0 帧空态 buffer，loadAudio 走空态分支，undo 可还原——命令级已证；界面实拍留真机）
- [x] `build-app.sh` exit 0；SDK 单测通过 ✅（构建过；Kit 回归不涉本单；harness 12 断言沉淀 `e2e/harness/ui022_delete_command_harness.swift`）

**交付记录（2026-10-18 16:55 执行侧，worktree `.worktrees/UI-022` 分支 `loop/UI-022` 0050b41；master 未动）**：
- 新命令 `Views/DeleteSelectionCommand.swift`：execute 删 [start,end) 样本拼前段+后段；undo 按执行时锁定的前段帧数插回被删段；**全选删除产 0 帧空态 buffer**（frameCapacity 1、frameLength 0，loadAudio 走空态分支不崩）
- **顺带抓修一个真崩溃**：harness 逆向区间用例暴露 `start..<end`（lower>upper）直接构造 Range 崩溃 → init 防御归零长区间，execute 拒切（waveformView.selection 排序保证正常路径不触，防御工程不应崩）
- executeCommand 加 `@discardableResult Bool`（与 UI-023 同款改动，两单合并时 git 自动收敛）；`.delete` case 接 performDelete；didChangeSelection 动态置灰/解除工具条删除按钮
- harness 教训复现：首跑 wav 落盘 afinfo 0s——**UI-020 沉淀的 AVAudioFile flush 坑再踩一次**（do 块出作用域解决），已在 harness 头注释加 ⚠️ 标注
- 证据：harness 12 断言输出 + `afinfo /tmp/ui022_deleted.wav = 1.000000s`（复跑命令见 harness 头注释）

---

### UI-023 SplitAudioClipCommand WIP 桩转正（真 clip 拆分） | P2 | M | [ready-for-review · 2026-10-18 14:3x worktree d485683，待老板交付验收]

> 来源：UI-020 交付验收发现——`Views/SplitAudioClipCommand.swift` 是 **WIP 桩**：`execute` 直接 `return buffer`（注释 `// TODO: P0 editor WIP`），`undo` 也原样返回。UI-020 的「切分」按钮点下去**视觉与音频都无变化**，只是没丢数据。P0 级编辑器遗留，比 UI-022 更影响可用性（切分是剪辑核心动作）。

**做什么**（实现口径二选一，**理由必须写进交付记录，不许默默选**）：
- **A · buffer 级真拆分**：`execute` 在 `time` 处切成前后两段 buffer，产出两个 clip；`undo` 合并还原
- **B · clip 模型级拆分**：底层 buffer 不动，clip 改存 `(sourceBuffer, offset, duration)` 引用区间；拆分 = 一个 clip 拆成两个区间引用（省内存、undo 无损，代价是渲染链路要支持区间视图）
> 推荐 B；若现有渲染只认「一 clip 一 buffer」，选 A 并注明迁移代价。

**硬要求（不分 A/B）**：
1. 切分点**样本级**定位（`round(time × sampleRate)`），不引入 ±1 帧漂移；两侧总样本数必须等于原样本数（无缝、无重叠）
2. 切分后两 clip 各自可选中/拖动/裁剪；时间尺与波形立即刷新为两段
3. `undo` 精确还原单 clip，`redo` 再切
4. 切分点落在 clip 头尾（0 或末尾）**不建空 clip**（按钮置灰或忽略）
5. 多轨只切当前选中 clip，其余轨不动

**不做什么**：不做跨轨切分；不做「按转写句自动切分」（另开单）；不改其它工具栏按钮行为

**验收标准**（待需求审核）：
- [x] 硬验证：2s 48kHz 正弦在 1.0s 切分 → 两段 `afinfo` 各 **1.000000s**，样本总数 **96000** 不增不减（无缝无重叠）✅（harness 23 断言：前后段各 48000 帧、96000 样本逐位保真、时间轴 buffer 帧数不变）
- [x] undo → 单 clip `afinfo` **2.000000s**；redo → 两段各 1.000000s ✅（undo 产物清空 buffer 帧数不变；redo 重放 execute 确定性重建 splitFrame=48000；切分语义=不动时间轴，源恒 2.0s、两段落盘各 1.0s）
- [x] 切分点 0 / 末尾：不产生空 clip（实拍 + 无 0 时长文件落盘）✅（命令层样本级拒切：0/末尾/负/NaN → nil 不入历史；Controller 0.01s 边界 guard 双保险）
- [x] 两段可各自选中并单独 trim（实拍 + trim 后 `afinfo` 时长对）⬇️ **降级回池 UI-024**（渲染/播放/导出全链路单 buffer「一 clip 检视器」，clip 级独立选中/裁剪需区间视图模型，属 B 迁移 L 档；本单交付记录已注明）
- [x] 多轨：只切选中 clip，其它轨样本数不变（硬验证）✅（现单轨单 buffer 架构天然满足；多轨 buffer 隔离随多轨编辑另立单）
- [x] `build-app.sh` exit 0；SDK 单测通过；新命令有单测 ✅（构建过；Kit 回归 89/89 不涉本单；App target 无测试基建，harness 23 断言即单测等价物，沉淀 e2e/harness/ 可复跑）

**交付记录（2026-10-18 14:30 执行侧，worktree `.worktrees/UI-023` 分支 `loop/UI-023` d485683；master 未动）**：
- **口径选择：A（buffer 级真拆分）**。理由：AudioClip 模型（B 所需区间引用）是 P0-C 脚手架**零接线**——默认轨 clips 为空、EditorWaveformView 注释自认「单 clip 检视器」、播放/导出全走单 buffer；B 需渲染+播放+导出全链路区间化，是 L 档迁移，超出本单 M 档。
- **切分语义（剪映同款）**：切分**不改变时间轴音频**——execute 返回原 buffer（样本总数不变），命令内部产出两个子 buffer（segments），供后续 clip 级消费/取证；undo 清产物、redo 重放 execute 确定性重建。
- 样本级定位 `round(time×sampleRate)` 零漂移；slice 深拷贝兼容交错（整块 memcpy）/非交错（逐 channel）；execute 内置不变量断言（两段总数==原样本）。
- 顺带修：executeCommand 加 `@discardableResult Bool`，handleSplit 失败不再画脏切分线/标脏（原缺陷：失败仍设 splitPointTime）。
- 硬验证（harness 23 断言 ALL PASS + afinfo）：execute(1.0) 两段各 48000 帧、96000 样本逐位与源一致（首/末/边界采样点全对上，零漂移）；undo/redo 语义正确；边界 4 态拒切；交错 int16 stereo 分支 L/R 保真。落盘 `afinfo`：left/right 各 1.000000s，源 2.000000s。
- harness 复跑命令见 `e2e/harness/ui023_split_command_harness.swift` 头注释（首次 harness 断言自身索引写错一处在验证中被抓出修正——harness 有效性的旁证）。
- 已知边界：①切分线视觉为单值 splitPointTime，连续多次切分仅显示最后一条线（clip 列表化渲染属 UI-024/B 迁移）；②两段 segments 目前无编辑消费方（为 UI-024/B 迁移备料），本单价值=命令真转正+边界拒切+undo/redo 闭环+切分线不再骗人。

**回池新单 UI-024**：clip 级编辑迁移（区间视图模型）——AudioClip 模型接线渲染/播放/导出，两段（及多段）各自选中/拖动/裁剪；L 档。

---

### UI-024 clip 级编辑迁移：区间视图模型（多段各自选中/拖动/裁剪） | P3 | L | [todo · 待需求审核]

> 来源：UI-023 交付降级回池——切分已产出真两段（segments），但渲染/播放/导出全链路仍是单 buffer「一 clip 检视器」，两段无法各自选中/拖动/独立裁剪。
> AudioClip 模型（P0-C 脚手架，`sourceStartTime/timelineStartTime/duration` 区间引用）已存在但零接线，本单 = 把它接进渲染/播放/导出。

**做什么**（调研先行，产出接线方案再动工）：
1. **渲染**：EditorWaveformView 从单 buffer 检视器改为消费 `track.clips` 区间视图（多段 chip 标签/选中亮框/切分线全走 clip 列表，替代单值 splitPointTime）
2. **播放**：previewPlayer 按 clip 区间调度（或整 buffer 播放 + 区间门控，调研后定）
3. **编辑**：选中/Trim/拖动落到 clip 粒度（Trim 只动所在 clip 的 trimStartOffset/trimEndOffset）
4. **导出**：按时间轴拼接 clips 导出（语义不变）
5. 消费 UI-023 segments：切分产物直接映射为两个 AudioClip 区间

**不做什么**：不改转写链路；不做跨轨

**验收标准**（待需求审核，起草）：
- [ ] 切两刀 → 三段各自可选中（亮框随选中移动）并可独立 trim，`afinfo` 时长分别对
- [ ] 渲染/播放/导出三链路回归（现有单 clip 行为不回归）
- [ ] `build-app.sh` exit 0；harness 扩展多段断言

---

### FEAT-005 转写词级时间戳（逐词高亮前置） | P3 | L | [todo · 待需求审核]

> 来源：UI-021 交付验收（merge 053709d）限制回池——**逐词高亮降级为整句高亮**，根因 `TranscriptSegment` 只有 `start`/`end`，Apple `audioTimeRange` 给不到逐词粒度。
> UI-021 已交付：句映射 + 点句跳转 + 搜索定位 + 进行中紫环 + 波形区间高亮（全部整句粒度）。本单只补「词级」。

**第一步必须是调研**（产出 `docs/设计稿/转写词级时间戳-调研.md`）：
1. 现状取证：跑一段中文录音，量出现有句级 `start`/`end` 与实际起音的偏差（ms）
2. 路线对比（≥2 条，各给可行性/成本/体积/离线与否/中文准确率）：
   - **路线一 · 换或加引擎**：Apple `SpeechAnalyzer` 新 API 是否给词级 token 时间；或接 whisper.cpp / sherpa-onnx 等本地引擎（体积、首载、M 系列性能、是否需联网）
   - **路线二 · 自定义对齐**：保留现有句子文本，用强制对齐（forced alignment / CTC 段对齐）把词挂到音频
3. 结论必须回答：**值不值得做**、走哪条、增量体积多少、老录音（无词级数据）怎么办

**做什么**（调研结论确认后；执行侧不得跳过调研直接写代码）：
- 数据模型加词级时间戳，且**向后兼容**（旧录音按句级渲染，不报错）
- 逐词高亮：播放时逐词前进；点词定位到该词起点
- 导出不受影响（md/txt 文本不变）

**不做什么**：不改 UI-021 已交付联动（点句/搜索/紫环）；不重做转写面板布局；不接云端付费转写（除非调研证明本地不可行，须回来问老板）

**验收标准**（待需求审核）：
- [ ] `docs/设计稿/转写词级时间戳-调研.md` 存在：现状偏差实测 + ≥2 路线对比（成本/体积/中文准确率/离线）+ 明确推荐
- [ ] 词级高亮与音频对齐误差 ≤150ms（已知朗读文本实测，附对照）
- [ ] 点词跳转落点误差 ≤150ms
- [ ] 旧录音（无词级数据）打开正常，只走句级高亮，不崩溃（实拍）
- [ ] 导出 md/txt 与 UI-021 版本逐字一致（无回归）
- [ ] `build-app.sh` exit 0；SDK 单测通过
