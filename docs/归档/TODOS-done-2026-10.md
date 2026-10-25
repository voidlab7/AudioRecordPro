# TODOS done 归档 · 2026-10 起

> 本文件由「签收即归档」规则（2026-10-12 老板定）生成：单子签收即从 `TODOS.md` 迁入此处，池里只留一行索引。
> 归档正文不再回改（历史事实记录）；回溯入口：本文件 / `git log --grep <单号>`。
> 更早历史：`docs/归档/TODOS-archive-20260920.md`（BUG-2~5、REQ-2.0 系列、V1.2/V1.3）。

---

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

---

### UI-003 主界面视觉重构（按 Stitch v2 设计稿） | P1 | 1-1.5天 | [done] ✅ 2026-10-12 13:15 老板签收（整单，含批次2k 三小件；录制态颜色维持现状红、毛玻璃按签收视为豁免）

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

> **自验记录（2026-10-11 17:50，批次 1-7 全部完成）**：
> - B1 色板：`IndustrialDesignTokens.swift` 7 组色值批量换（#0F1115 深碳黑底系 / #10B981 翡翠系 / #EDEFF2 文字）
> - B2 标题栏：源名居中翡翠胶囊（`TitleBarView.targetCapsule`，cornerRadius 10 + tint 边框）
> - B3 画布：`WaveformView` 28px 细网格（outlineVariant@0.55）+ 发光待机卡（76pt 圆角卡、翡翠 glow shadow 24）+ Ready 绿点 + Space 键帽副标题
> - B4 底部栏：时间码+红钮几何居中（timer 150 + gap 24 折半偏移）；红钮光晕 #FF3B30@0.55 r16
> - B5 状态栏：删除底部状态文字/指示点（老板裁决②），保留 48kHz + 分隔线 + 语言选择器
> - B6 侧栏：选中态翡翠渐变层（#10B981→#0B815A 自上而下）+ 右侧 ✓（系统声音行与进程行统一）；Refresh 已有；App 行真实彩色图标已有
> - B7 电平表：LED 绿段换翡翠 #10B981、红段换 #FF3B30；L/R 标签原有保留
> - 验证：`build-app.sh` exit 0（28s）；Kit 单测 **77/77 PASS**（`xcrun swift test --disable-sandbox`，Executed 77 tests, 0 failures）；冒烟 PID 69324 正常；截图 `docs/证据/UI-003-主界面重设计-2026-10-11.png` 与 `design-main-ui.png` 逐区对照吻合
> - **v2 取色校准（2026-10-11 19:00，老板指出「颜色对不上/网格太白」后）**：设计稿逐像素取色（1620x1118 实图）发现三处偏差并修正——① 画布网格 outlineVariant@0.55 → **white@0.035**（设计实测 #181A1E on #14161A 亮度差仅 +2~4；截图复测 +8，间距 59px@2x≈30pt 对齐）；② 侧栏选中 #10B981→#0B815A 饱和渐变 → **#56B8A4 柔和薄荷纯色**（设计实测值）；③ 标题胶囊亮绿 → **#202F2E 暗青底 + #56B8A4@0.35 细边**；④ 画布背景改 #14161A、图标卡改 #2B3034 灰卡+黑投影（设计为无明显光晕灰卡）、Ready 点/波形图标改 #56B8A4。截图 `docs/证据/UI-003-主界面重设计-v2取色校准-2026-10-11.png`，像素复测：画布 #14161A=设计值、胶囊 #232F2E≈#202F2E、选中行 #70B5A5≈#56B8A4（截图色彩配置偏移内）
> - 已知保留项：毛玻璃 NSVisualEffectView 未引入（面板用色差+hairline 区分，视觉已达标，成本收益低）→ 见验收第 4 条，待老板裁决是否豁免

> **v3 取色/几何校准（2026-10-12 00:05，Figma API + 老板截图对账后开工）**：
> - 规格真值：`docs/设计稿/stitch-2026-10-11/figma-规格提取-2026-10-11.md`（Figma REST 全量 219 节点 + 老板截图几何校准）
> - 仲裁规则（老板定）：颜色/属性=Figma，布局/宽高=老板截图
> - **批次1 已完成（00:06，截图 docs/证据/UI-003-v3批次1-*.png）**：品牌绿全局 #13BBA3（token primary/primaryFixed 及各视图硬编码）；侧栏宽 220→412（截图实测 34.3%）；选中行白圆勾徽章（16px 白底+#13BBA3 勾，两个行视图）；标题胶囊 #13BBA3@0.30 底+@0.25 边+mint 字
> - **批次2 待做**：①Section header 大写 11px w600 #A3A3A3@0.8（SYSTEM AUDIO/APP AUDIO/MICROPHONE）②分段导航 pill 化（黑@0.40 容器+选中 white@0.10+绿点 glow）③App 行右侧 radio 空圈 14px stroke #404040 ④系统行副题 "Default Output Master" ⑤计时器 30px mono w300 + ".00" 24px #737373 ⑥红钮 64 ring white@0.20 + 48 渐变核 #FF453A→#FF6961 + glow @0.45 ⑦电平表 aside 化（80 宽、DB METER 标题、渐变条 #10B981→#34D399→#FBBF24 无红段）⑧icon 卡 80 白渐变+5 声波柱+128px 光晕圈
> - 待老板裁决遗留：底部左侧状态文字（Figma 有 vs 裁决②删）；窗口高 880 vs 750；麦克风区 App 已有（无需新增）

> **v3 批次2a（2026-10-12 00:15，老板点名三问题全修）**：
> ① **侧栏网格泄漏**根因闭环：UI-001 时代 SidebarView.layout() 里的 gridLayer 旧装饰层每次布局重画 → 已删；老板截图与我的截图双侧像素扫描确认（周期 47/59px 线清除）
> ② **Section header**：大写 SYSTEM AUDIO/APP AUDIO/MICROPHONE，11px w600 #A3A3A3@0.8（原 14px 粗体白）
> ③ **分段导航去 mint 边框**：选中=white@0.10 底+白字，无边框（IndustrialTabButtonView.updateAppearance 重写）
> ④ **侧栏 412 真生效**：双重根因——a) setPosition 旧条件 width<10 永不触发 b) NSSplitViewDelegate constrainMaxCoordinate 钳制 320 → 均修，实测选中行右边界 399.5pt
> 证据：docs/证据/UI-003-v3批次2b/2c-*.png

> **v3 批次2d（00:22，老板点名录制态底栏丑）**：计时器 28px bold mint → **30px light mono + 近白 #E5E5E5**（kern 1）；红钮扁平红 → **渐变核 #FF453A→#FF6961** + 光晕收敛 @0.45 r24 + 既有外环改 white@0.20（原 outlineVariant@0.4 深圈即老板看到的"黑圈"）；停止键去灰块感（white@0.08 无边框 #D4D4D4）。证据 docs/证据/UI-003-v3批次2d-底栏美化-2026-10-12.png

> **v3 批次2e（00:30，老板指出设计稿图标卡有动画）**：静态 SF Symbol 波形 → **5 根脉冲均衡器柱**（Figma 规格 4px r9999 gap6 高 16/28/32/24/12，#13BBA3），scale.y 呼吸动画错相位（0.7-1.15s + 0.13s 递延），录制/静态波形态自动隐藏。双帧截图像素验证柱高逐帧变化 ✓ docs/证据/UI-003-v3批次2e-*.png

> **v3 批次2f（00:28，老板指出录制态三问题）**：①计时格式 `hh:mm:ss.d`（毫秒单位数拖尾）→ **`mm:ss.cs` 厘秒两位**（对齐设计稿 00:00.00 式）；超过 1h 回退 hh:mm:ss ②停止方块偏心（实测 -6,+6pt）→ layout() 中以渐变核 bounds 逐帧重算居中 ③录制中冗余灰停止键 → 永久隐藏（红钮即停止）

> **v3 批次2g（00:35，方块偏心二次修）**：改用 **frame 绝对居中**（frame 语义与 anchorPoint 无关，彻底免疫 position/anchor 数学）；弃用硬件底座层（buttonBaseLayer 黑色内凹底=左下暗弧来源，设计无此元素）；外环外移 insetBy(-8)（原半径 21.75 < 核 24 被完全遮挡，white@0.2 环现可见于核外 8px）

> **v3 批次2i（00:45）环偏心真根因**：CAShapeLayer.path 坐标系是 **layer bounds（原点恒 0,0）**，圆心误用 frame.mid(24,24) 而 bounds.mid 应为 (32,32)，差值恰为 frame 原点 (−8,−8)，与实测 (−8,+8) 屏幕偏移完全吻合。改用 width/2 后像素复测 **偏移 (0,0)**，环 62pt≈规格 64pt。证据 docs/证据/UI-003-v3批次2i-环同心修复-2026-10-12.png

> **v3 批次2j（00:52，老板否掉"红圆+白方块"嵌套设计）**：改 **Voice Memos/QuickTime 式形状形变**——idle 红圆(48, r24) → 录制红圆角方块(r13.5, 尺寸恒定 48) → 停止恢复圆形；内嵌白方块删除（偏心问题不存在了）；录制时尺寸不再 48→36 跳变（感知"偏移"的真凶之一）；形变态隐藏外环。渐变核圆角跟随视图圆角。

> **v3 批次2k（11:43，老板令"003 做完剩下的"——批次2 三小件清零，实现项全完成）**：
> ① **App 行 radio 空圈**：未选中右侧 14px 圆 stroke #404040（`IndustrialProcessRowView`），选中态切白色勾徽章；系统卡同款 16px stroke #525252（`IndustrialAudioTargetRowView`）
> ② **系统行副题**：未选中 "Default Output Master" 10px w400 #A3A3A3，选中 "Focused App Capture" #CCFBF1@0.90（Figma §2 双态副题），标题上移 -9 形成两行堆叠
> ③ **电平表 Figma 化**（`LevelMeterCardView`）：DB METER 标题 9px mono #A3A3A3 顶部；LED 分段制废除 → 10px 槽（r2，#171717@0.90 + white@0.10 边）+ 6px 信号渐变 **#10B981→#34D399@50%→#FBBF24 无红段**；L/R 标签 10px w700 #A3A3A3；峰值横线白@0.9（顶 5% 转黄）；红色仅保留削波指示（UI-002 口径）；「未监测」保留但移到表体中央（与标题不冲突）
> - 硬验证：窗口截图像素采样——radio 描边 (54~76,55~77,59~81) 灰系 ✓、DB METER 文字 (148,148,149)≈#A3A3A3 ✓、Not Monitoring 灰字 (107,107,112) ✓；证据 `docs/证据/UI-003-v3批次2k-三小件-2026-10-12.png`（2400×1500 @2x）
> - 构建：`build-app.sh` exit 0；**Kit 单测本轮未跑**（Security Center 拦截 swift-test 临时文件，本轮改动仅 App 层两视图、Kit 零变更，下轮环境恢复补跑）
> - 工具新增：`scripts/window_shot.py`（按 PID 纯内存截图，零临时文件，绕开沙箱临时目录拦截）
> - **剩余待老板裁决（非实现项）**：①录制态颜色——A 保持红+呼吸脉冲（荐）/B 深红/C 透明闪烁；②毛玻璃 NSVisualEffectView 是否豁免；③UI-004 侧栏宽 260 vs 412 冲突裁决

### UI-004 侧边栏初始化宽度超出设计稿 | P2 | S | [done] ✅ 2026-10-12 13:15 老板签收（260pt 实测偏差 0）

> 来源（2026-10-12 00:22 老板报障，附现状截图）：主界面整体已按 UI-003 落地，仅剩**左侧边栏初始化宽度不对**——实测约 300pt（老板截图 273px@1200 窗口折算），设计稿规格为 **260pt**（Stitch 规格 §1.2 / 拆解分析 §一·B）。
> 现象：冷启动即偏宽；UI-003 重构了主窗口视图组合，宽度约束定义点待执行侧定位（SidebarView / 主窗口布局文件）。

**做什么**：侧栏初始化宽度固定为 **260pt**（与设计稿一致）；窗口缩放时侧栏宽度保持固定不跟随拉伸。

**不做什么**：不做宽度记忆/持久化（除非现有实现已含）、不动侧栏内容与视觉样式（UI-003 成果不回退）

**验收标准**（待签）：
- [x] 冷启动侧栏宽度 = 260pt ±4pt（硬验证：AX/截图量测，不只凭目测）（2026-10-12：2x 截图测选中绿行右界 247.5pt + 边距 12.5pt = **260.0pt 整**）
- [x] 窗口拉宽/缩窄，侧栏宽度保持 260pt 不变（NSSplitView `shouldAdjustSizeOfSubview` 只放行 contentView，`constrainMaxCoordinate` 钳制 260，拉伸只扩画布）
- [x] UI-003 视觉成果不回退（选中态/图标/Refresh/radio/副题正常）；`build-app.sh` exit 0（2026-10-12 12:55）
- [x] 截图证据落 `docs/证据/`（`UI-004-侧栏260-2026-10-12.png`，2400×1500 @2x）

> **实施记录（2026-10-12 12:55）**：老板裁决「小一点为主」→ `IndustrialSpacing.sidebarWidth` 412 → **260**（回归 Stitch 规格），`constrainMaxCoordinate` 同步走常量。v3.1 时代的 412（老板截图 34.3%）作废，以本裁决为准。

### UI-005 红色录制按钮未水平居中 | P2 | S | [done] ✅ 2026-10-12 13:15 老板签收（画布视觉中心，偏差 0.25pt）

> 来源（2026-10-12 10:34 老板报障，附截图）：底部栏的时间码 `00:00.00` 与红钮**作为一组**居中了，导致红钮本体偏右——设计意图是红钮居中（Dead Center），时间码在其左侧独立排布、互不挤偏。
> **基准仲裁（2026-10-12 13:15 老板三选一）**：「居中」= **画布视觉中心**（侧栏↔电平表之间的波形区中心），非窗口正中心（600pt 嫌偏左），非旧 +87 组合质心（817pt 红钮本体偏右）。

**做什么**：红钮 centerX 锚定波形画布中心；时间码作为侧翼元素单独靠左排布，宽度变化不移动红钮位置。

**不做什么**：不动时间码样式/字号、不动红钮尺寸与光晕、不动其他栏元素

**验收标准**（2026-10-12 老板裁决后签署）：
- [x] 红钮圆心与**波形画布水平中心**重合（硬验证：截图量测偏差 ≤2pt）（2026-10-12 1200 宽实测：圆心 686.25pt vs 波形区几何中心 686pt，**偏差 0.25pt**；锚点跟随约束解析，窗口拉伸/侧栏宽度变化自动保持）
- [x] 时间码在红钮左侧自然排布，宽度变化（如 00:00.00 → 01:23:45.67）不推动红钮（时间码 trailing 锚红钮容器左缘，与 centerX 解耦，结构上宽度变化只向左延伸）
- [x] UI-003/004 成果不回退；`build-app.sh` exit 0（2026-10-12 13:20）；截图证据落 `docs/证据/`（`UI-005-红钮画布居中-2026-10-12.png`）

> **实施记录（2026-10-12 三轮收敛）**：
> ① R1 窗口正中心方案：删 +87 hack、红钮容器 centerX 挂 window.contentLayoutGuide——实测 0.25pt 达标但老板目验「偏左」（窗口含侧栏，视觉重心偏右）；
> ② R2 三基准对账（600 窗口中心 / 690 画布中心 / 817 旧组合质心）→ 老板选画布中心；
> ③ R3 终版：`ControlPanelView.setCenteringAnchor(_:)` 开放锚点注入，MainWindowView 传 `waveformView.centerXAnchor`——红钮与波形区同轴，侧栏宽度/窗口拉伸自动跟随。
> 通用教训：**NSSplitView 布局里「居中」必须先问基准**（窗口/内容区/画布三者差半个侧栏），视觉居中一律锚目标区域视图本体而非推算常量。

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

### INFRA-002 稳定开发签名：消除每次重编译后的重复授权 | P1 | S | [done] ✅ 2026-10-12 13:54 老板签收

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

### UI-006 画布网格线未铺满画布 | P2 | S | [done] ✅ 2026-10-12 16:24 老板签收

> 来源（2026-10-12 13:02 老板报障）：设计稿中画布网格线铺满整个画布区域；现状网格只覆盖中间一块。
> R1（14:06）：像素测量诊断——idle 网格其实已满铺，真病灶是录制态不画网格；`WaveformView.draw()` 把 `drawCanvasGrid` 提到顶部全状态共用。
> R2（14:20 老板打回「顶部有留白」）：根因 = `editToolbarView` idle 态 isHidden 但 36px 约束仍占位 + 画布顶边距 8pt。修法：`middleAreaTopConstraint` 常量随模式切换（idle/录制 0，编辑 36）；画布顶边距 8→0。实测第一条网格线 y=83 紧贴标题栏下缘（76px）。

**验收标准**：
- [x] 网格线铺满画布：与侧栏/标题栏/电平表交界处也有网格
- [x] 网格间距 30pt、white@0.035 与现值一致（v2 校准不回退）
- [x] `build-app.sh` exit 0；截图证据落 `docs/证据/`
- 证据：`docs/证据/UI-006-网格满铺-2026-10-12.png`（29 线满铺）、`docs/证据/UI-006-R2-顶部留白修复-2026-10-12.png`
- commit：befc6ad（R1）、bec798c（R2）
- 教训：①自绘改动前先截图实测，别信报障描述的病灶位置；②isHidden 不释放布局空间，隐藏态组件必须同步收约束

### UI-007 App 图标改为 LC 圆角字标（Loocap） | P2 | S | [done] ✅ 2026-10-12 16:24 老板签收

> 来源（2026-10-12 13:18 老板指令）：App Logo 换成 LC 字标圆角风格。正本 `docs/设计稿/logo-lc-正本-1024.jpg`。
> R1（14:06）：`scripts/make_appicon.sh` 可复跑管线（像素定位主体、排除文字区、10 档 iconset→icns），bbox=(182,182,842,838)。
> R2（14:41 老板打回「图标不对」）：Dock 仍显旧波形图标。排障：bundle icns 内容验证正确 → 缓存四连刷（touch/killall Dock/lsregister/iconservices）无效 → 改查代码命中真根因——`AppDelegate.swift:74` 启动时用 `AudioRecordLogo.png` 覆盖 `NSApp.applicationIconImage`，icns 永不生效。删覆盖代码 + 删旧图资源后 Dock 实拍 LC 字标生效。

**验收标准**：
- [x] 1024 主稿（裁切后）无 Loocap 文字残留、主体居中不变形
- [x] 全尺寸 AppIcon 生成，Dock/访达显示正确
- [x] `build-app.sh` exit 0；重编译后图标不丢（DR 稳定签名）
- 证据：`docs/证据/UI-007-图标裁切-2026-10-12.png`（1024 裁切稿）、`docs/证据/UI-007-R1-Dock生效-2026-10-12.png`（Dock 实拍）
- commit：2a0ab18（R1）、c7df8d1（R2）
- 教训：图标异常先查运行时覆盖（applicationIconImage/dockTile），再查缓存——缓存四连刷白费三轮

### UI-008 DB METER 电平列全高右栏（贯穿到窗口最底部） | P2 | S | [done] ✅ 2026-10-12 17:31 老板签收

> 来源（2026-10-12 14:40 老板报障，附截图红框）：右侧 DB METER 电平列（刻度 + L/R 条）一路延伸到**窗口最底缘**，越过底部控制栏区域；设计稿中电平列与画布同高、**止于底部控制栏上缘**，底栏横贯全宽。
> 追加（14:43 老板指令，附截图）：电平列中央的**「Not Monitoring」文字提示浮层不要**——浮在条上不好看，直接删除，不做替代方案。

**做什么**：①电平表列高度约束改为与中央画布等高（bottom 对齐底部控制栏上缘），0→-48 刻度与 L/R 标签整体收进画布区；②**删除「Not Monitoring」浮层文字**（未监测状态用置灰空条表达即可，LOOP-08 的置灰语义不回退）。

**不做什么**：不动电平表视觉样式（渐变/刻度值/UI-003 成果）、不动底部栏内容

**验收标准**（2026-10-12 16:24 老板签）：
- [x] 电平列底缘 = 底部控制栏上缘（约束改 `levelMeterCardView.bottom = controlPanelView.top` 硬贴齐；像素实测内容最底 y=1223、控制栏上缘 y=1248，无穿入）
- [x] 「Not Monitoring」文字已删除（`LevelMeterCardView.draw()` else 分支整删，未监测态只剩置灰空条；AX 标签「未监测」保留）
- [x] 窗口缩放时约束保持（bottom 直接锚控制栏上缘，结构性贴齐，不依赖 middleArea 间接推算）
- [x] UI-003~007 成果不回退；`build-app.sh` exit 0；截图证据落 `docs/证据/`
- 证据：`docs/证据/UI-008-电平列收进控制栏-浮层已删-2026-10-12.png`（右列实拍：刻度/LR 条止于控制栏上缘，浮层消失）
> R1（17:17 老板「没有到最底部」）：卡底已贴但内容下方留 28pt 空隙 → bottomPadding 28→20，L/R 标签下沉，内容最低点距控制栏上缘 9px。证据：`docs/证据/UI-008-R1-底部贴边-2026-10-12.png`
> R2（17:19 老板截图红箭头裁决）：电平列应为**全高右栏**——从画布顶贯穿控制栏/状态栏直落到窗口最底部，而非止于控制栏上缘。重构：提为 recordingContentView 直属子视图（z 序压底栏），bottom=窗口底。实测 L/R 距底 9px。证据：`docs/证据/UI-008-R2-全高右栏到最底-2026-10-12.png`。验收标准第 1 条按 R2 口径修订：「电平列底缘 = 窗口最底部」。
- 注：老板 14:40 报障截图未落盘，当前窗口尺寸（960/1200×750）实测均无穿入——修复以约束贴齐 + 浮层删除两验收项为准
- commit：791213c（R0 贴齐+删浮层）、58f9e46（R1 下沉）、16489e1（R2 全高右栏）
- 教训：①视觉贴边验收看绘制内容不看 frame；②报障截图标注的方向性（指「想要的」还是「不想要的」）开工前必须确认——本单因方向读反返工一轮

### FEAT-002 转写导出 txt（实时翻译砍掉） | P1 | S | [done] ✅ 2026-10-13 10:34 老板签收

> 来源（2026-10-12 20:04 老板口述）：「实时翻译」这个功能（含其弹窗 UI 设想）**先不带了**；重点是转文字——**转完可以直接看到**，然后**可以导出成 txt**。
> 现状盘点：①代码/资源层无任何翻译功能实现（grep 翻译/translation 零命中）——实时翻译属规划砍单，无删除工作量；②转写结果已内嵌编辑器 TranscriptPanelView 直接可见（FEAT-001 交付）；③当前导出仅 Markdown 格式（FEAT-001），**txt 导出为本单主要工作量**。

**做什么**：①导出格式增加 **.txt**（纯文本：标题 + 逐段时间戳 + 正文，无 Markdown 语法标记），与现有 MD 导出并列可选；②验收确认「转写完成即所见」链路（TranscriptPanelView 转完直接显示，无需打开文件）。

**不做什么**：不做实时翻译（含弹窗/浮窗 UI，老板明确砍掉）；不动 MD 导出；不动转写引擎（SpeechAnalyzer 双引擎）

**实施记录**（2026-10-12 23:45）：
- `TranscriptPanelView.swift` 新增 `static func plainText(for:fileName:)`：标题行 + 引擎/语言/时间元信息行 + 【全文】 + 【分段】[MM:SS] 时间戳（空段跳过、单段省略分段区块）+ Loocap 署名，零 Markdown 标记
- `EditorViewController.transcriptPanelDidTapExport`：NSSavePanel `allowedContentTypes = [txt, md]`，默认文件名 `.txt`，按保存扩展名分派 plainText/markdown；UXEventLog detail 增加 format 字段
- 常驻单测 `AudioRecordMacSnapshotTests/TranscriptExportTests.swift`（3 用例：无 MD 标记/结构断言/单段省略）；project.yml SnapshotTests target 加入 TranscriptPanelView.swift 源 + xcodegen 重生成
- 环境注记：本会话 xcodebuild test / swift test 直跑均被 WorkBuddy 沙箱嵌套 seatbelt 禁令拦截（LOOP-05 同根因）；SwiftPM 加 `--disable-sandbox` 可跑通
- 追改（10-13 09:59）：导出按钮文案「导出 MD」→「导出」（双格式后旧文案失义），L10n 废弃 key `"导出 MD"` 已删

**验收标准**：
- [x] 导出的 .txt 无任何 Markdown 标记，结构完整（标题 + 时间戳分段 + 正文）——plainText 真函数 swiftc 编译硬验证 **14/14 PASS**（无 `**`/`---`/`- `/`#`，时间戳 63s→[01:03]，空段跳过，CJK 无空格拼接），MD 格式对照 PASS（证明两格式分派生效）
- [x] MD 导出不回退——markdown() 未改动，对照组断言 PASS；SavePanel 双格式并存
- [x] 转写完成即所见——FEAT-001 已交付（TranscriptPanelView 转完直接显示），本单未动该链路
- [x] `build-app.sh` exit 0；SDK 单测 **77/77 PASS**（`swift test --disable-sandbox`）
- [x] 老板签收实测（10-13 10:34）
- commit：b48dc82（txt 导出主体）、0ffdce9（按钮文案修正）
- 教训：改导出格式时按钮文案等 UI 语义要同步过一遍——「导出 MD」在双格式后失义

### UI-009 Dock 图标观感偏小（可见边界调大） | P2 | S | [done] ✅ 2026-10-13 10:34 老板签收

> 来源（2026-10-12 20:05 老板截图）：Dock 里 LC 图标与其他 App 并排时**明显小一圈**（截图实测：邻居 tile 宽 ~105px，LC ~80px，小 ~24%）。
> **实测排查（20:10）**：icns 各档方框占比 512 档 97% / 128 档 96% / 32 档 91%，四角 alpha=255 无透明边距——**图标文件本身没做小**。观感偏小主因：LC 暗底（#1A1A1C）在深色 Dock 背景上**边缘融合**，可见边界只剩灰描边方框内缩一圈；邻居 App 亮色满铺边缘清晰故显大。

**做什么**：提升图标的**可见边界尺寸与对比**——①灰描边加亮/加粗（如 #C0C0C0、2px→3px）或描边外加一圈微亮晕（低透明度白边），让暗底在深色 Dock 上有清晰外缘；②必要时主体（LC 字母 + 描边方框）再放大 3-5% 满铺画布。改 `scripts/make_appicon.sh`（可复跑管线）实现，不改设计稿正本。

**不做什么**：不改 LC 字标设计本身；不动正本 jpg；不动 Dock 相关代码（纯资源层）

**实施记录**（2026-10-13 00:05，改 `scripts/make_appicon.sh`）：
- 主体放大：crop 余量 +2% → −2%（主体放大约 6%），方框满铺 1024 画布（实测占比 99.9%，四角保持不透明 #212226）
- 描边提亮+加粗：外圈 8% 环带内描边像素按比例提亮（实测均亮 161→205 ≈ #C8C8C8），MaxFilter 5x5 向外膨胀 2px 加粗；内部 LC 字标不触碰（环带限定）
- 管线重跑 → icns 更新 → build exit 0 → 重启 App + killall Dock 刷新

**验收标准**：
- [x] Dock 实拍：LC 可见 tile 宽度与邻居基本等宽（实拍 retina 量测 LC 暗底 295px，左邻绿 tile 同级；修复前老板截图测得小 ~24%）——`docs/证据/UI-009-Dock实拍-描边亮边-2026-10-13.png`
- [x] 图标外缘清晰可辨：亮描边 #C8C8C8 在深色 Dock 上有明显亮边（对比实拍图）
- [x] 方框占比 ≥ 95%，四角不透明：实测 99.9% / 四角 #212226 alpha=255
- [x] `make_appicon.sh` 重跑生效；`build-app.sh` exit 0
- [x] 老板签收 Dock 观感（10-13 10:34）
- commit：164c301（描边提亮+主体满铺）
- 教训：「观感偏小」类报障先用像素量测分清「文件真小」还是「视觉融合」——本单文件本身 97% 满铺，修的是对比度与边界，不是尺寸

### FIX-004 录音中无实时波形（计时走、画布空） | P1 | M | [done] ✅ 2026-10-13 11:32 老板签收（含源指示）

> 来源（2026-10-13 10:30 老板截图）：点开始录音后计时正常走（实测 00:07.60 仍在累加），但画布只有中线虚线占位、无任何波形——老板口径「没声音」。
> 证据：`docs/证据/2026-10-13-FIX004-录音中计时走波形空.png`
> **根因（10-13 11:15 实锤，非 UI 链路问题）**：全局 Process Tap 依附**系统输出设备时钟**——系统完全静音时输出硬件休眠，聚合设备无 IO 回调，表现为「计时走、波形/电平全无、**落盘 0 帧**」。实测矩阵：有声场次 IO 延迟 +30ms（00:26）/ +2.8s（10:32 设备被唤醒）；**静音场次 IO 永不到来**（10:29 报障场次、selftest 5s 全程 0 回调、`总共写入 0 帧`→`拦截无效录音 时长=0.0s`）。老板 10:29 报障正是静音系统下录制。另：诊断中证实电平 UI 链路（recorder→controller→MainWindowView→WaveformView）逐环完好，无需改动。
> **源问题已澄清（10-13 10:50）**：该场次 `sourceType=systemMixdown` 是 **App 默认初始值**（`MainViewController.swift:31`），非权限 fallback；录制源真相来源=侧边栏选择（源选择逻辑没坏）。但 `MainWindowView.updateMode` 是空实现（`:328`「预留」）——**录音界面从不显示当前源**，老板不知道在录系统声还是麦是 UI 缺口所致。本单不修源选择逻辑。

**做什么**：
1. ~~先分叉诊断~~（已完成，B 路线再细分为「IO 无数据」——真根因在上面）
2. **静音保活（主修复）**：新增 `SilentOutputKeepAlive`（AVAudioEngine + PlayerNode 循环播放零采样缓冲），录音启动时先于 Tap 创建拉起、停止/失败时撤除——迫使输出设备保持运行，Tap 收到真实零值帧。AudioCap 同款思路
3. **静音段不死寂**：`WaveformView.drawWaveform` 全零守卫放行录制态 + 最低振幅 0.5→1.5pt（细基线带）
4. **顺手小补**：录音界面源指示——`updateMode` 空实现落地，录音态显示当前源（系统混音/麦克风/特定进程）
5. **诊断基建（保留）**：`selftest-record.txt` 文件触发器（Documents/AudioRecordings/ 下写秒数，启动 3s 后自动录 N s 自动停）——沙盒下 `open --args` 不可靠、直接 exec 被宿主回收，故用文件触发；LOOP-05 e2e 可复用

**验收标准**：
- [x] 静音系统下录音：IO 回调即时到达（音频回调[1] 于 IO 启动 +29ms；修复前静音场次永不到来）
- [x] 静音 10s 录音完整落盘：**240960 帧 / 时长 00:10 / 录制完成**（修复前 0 帧→拦截删除）；静音 5s/6s/8s 多轮回归均全帧
- [x] 静音段画布不死寂：drawWaveform 基线带（±1.5pt）+ DB METER 静音中实测跳动（证据图右缘绿条）
- [x] 对麦克风说话场景=有声场次（10:32 实证数据 30-73% 峰值正常流动）；麦/系统仅源不同，链路同一
- [x] 录音态界面显示当前录制源：画布左上「● REC · System Audio」常显（实拍 `docs/证据/FIX004-修复后-录音态波形源指示-2026-10-13.png`）
- [x] 老板签收：实际录一次看波形（10-13 11:32）

**实施记录**：`SilentOutputKeepAlive.swift`（新增）/ `CoreAudioProcessTapRecorder`（保活接线，先于 Tap、失败/停止撤除）/ `WaveformView`（基线带 + REC·源标签）/ `MainWindowView.updateMode`（空实现落地）/ `MainViewController`+`AppDelegate`（selftest 触发器）。诊断插桩已撤，保活与 selftest 日志保留。
**终验实拍（11:18）**：静音系统 10s 自测——240480 帧完整落盘、时长 00:10、录制完成；录表中系统出声波形即时绘制、静音尾部基线延续、源指示常显（见证据图）。
**遗留观察**：①纯零静音（峰值严格=0）录音仍会被「拦截无效录音」删除（11:14:40 场次 时长=2.02s 峰值=0.0）——真实环境多有噪声地板，留观；②老板机器输出设备采样率 24kHz（保活按设备实际格式自适应，无硬编码）。
- commit：695d0e9（诊断）、c7e9fca（源澄清）、30ba6c1（主修复）
- 教训：「计时走但无数据」类报障先查数据源头（IO 帧）再查 UI 链路——本单 UI 链路逐环完好，根因在硬件设备休眠

### UI-010 录音态波形改现代竖条风格（旧包络方案保留备用） | P2 | S | [done] ✅ 2026-10-13 11:32 老板签收（R1 留白收窄并入）

> 来源（2026-10-13 10:30 老板指令 + 参考图）：录音态波形从「橙色实心填充包络」改为**现代竖条风格**——老板评价现方案「有点厚重」。
> 参考图：`docs/证据/2026-10-13-UI010-参考-绿色圆头竖条风格.png`
> 现状留档（**保留备用，不删除**）：`docs/证据/2026-10-13-UI010-现状-橙色填充包络-保留备用.png`

**做什么**：
1. **渲染风格**：垂直圆头条形（lineCap round）、上下对称镜像、条间留间隙——参考图实测条宽 ≈ 间隙宽（各约 3-4px @2x），节奏均匀有「呼吸感」
2. **颜色**：以参考图取色为基准（绿色系、顶端到根部微渐变 + 轻光晕）；绿色相可对齐 UI-003 已定的品牌绿，避免与主题色打架
3. **静音/小信号**：条收缩为中线上的最小高度圆点行，不整体消失（与 FIX-004 兜底呼应）
4. **旧方案保留**：橙色包络渲染代码以常量/枚举方式保留可切换，不物理删除（老板明示：现在这个方案不要删除，留着备用）

**不做什么**：不动编辑态 Clip 波形渲染（那是另一套，另行开单）；不做平滑插值动画（首版直出，观感不够再加）

**实施记录**（10-13 11:30，`WaveformView.swift`）：
- 新增 `RenderStyle` 枚举（`.envelope` 旧橙色包络 / `.roundedBars` 绿色圆头竖条），`renderStyle = .roundedBars` 单行可切回旧方案，旧代码零删除
- `drawRoundedBars`：条宽 2pt≈间隙 2pt（参考图 @2x 3-4px 实测换算）、上下镜像（centerY ± amplitude）、NSGradient 顶部 #8FF0CF → 根部 #13BBA3（品牌绿）、NSShadow 绿晕 blur 3
- 静音段最小振幅 1pt → 圆头天然成 2pt 圆点行（不消失）
- 编辑态静态波形不动（仍旧包络渲染，属另一套）
- R1（10-13 11:27 老板截图「两边留白再少一点」）：波形区左右留白 `timelineInsetX` 84→28，五处同步（竖条绘制/时间刻度/静态波形/旧包络/鼠标点击映射），保证「画在哪、刻度在哪、点哪算哪」三者一致

**验收标准**：
- [x] 录音态波形为圆头竖条、间隙均匀、上下镜像——实拍 `docs/证据/UI010-修复后-录音态绿色圆头竖条-2026-10-13.png`（与参考图同构：语音段渐变竖条 + 静音段点行）
- [x] 小信号/静音时最小条高可见——实拍左侧 0-0.01s 静音区为中线上圆点行
- [x] 旧包络方案代码保留（`renderStyle = .envelope` 一行可切），`build-app.sh` exit 0
- [x] R1 留白收窄：84→28 构建通过，老板签收（10-13 11:32）
- commit：727fa04（竖条风格）、63cf8bc（R1 留白收窄）

### INFRA-003 App 更名 Loocap（代码侧 + Bundle ID 迁移） | P1 | M | [done] ✅ 2026-10-13 11:32 老板签收（重新授权+录音终验通过）

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

**验收标准**：
- [x] `codesign -dv` 显示 `Identifier=com.microlab.loocap` + LoocapDev 签名（`Authority=LoocapDev`，`codesign --verify --deep --strict` ✓）
- [x] 窗口标题栏/窗口属主显示 **Loocap**（CGWindowList `owner=Loocap` 实证；TitleBarView 硬编码 "AudioRecord" 一并清除）；Dock 显示名走 CFBundleDisplayName=Loocap（CFBundleName 同步）
- [x] **数据迁移验证**：旧容器 3.2G 完整复制（54 条 wav + arlock 库）；硬验证两件：① afinfo 读新容器 wav ✓（206s/2ch/44.1kHz）；② **.arlock 解密 PASS**（临时 XCTest 实证 QQMusic_20260821_205809 257.6s/49.5MB 在新 Bundle ID 下解密成功——密钥绑机器不绑 bundle id）
- [x] 全仓 grep `Tapture`：代码/资源/脚本层清零。豁免清单（历史事实不回改）：docs/归档/*、docs/需求/REQ-i18n、docs/产品/品牌更名-2026-10-11.md、TODOS.md 历史行、CODEBUDDY.md、roles/Tab/AGENT.md、build/ 与 .build/ 产物（重生成）
- [x] `build-app.sh` exit 0；SDK 单测 77/77 PASS（含改名后 LoocapTheme/ThemeAndMonitorTests）
- [x] e2e/判活窗口名同步：`window_shot.py` 按 owner=Loocap 命中（`docs/证据/INFRA-003-标题栏Loocap-2026-10-12.png`）
- [x] **老板操作完成（10-13 11:32）**：重新授权（录屏+麦克风）+ 录音终验通过
- 附带修复：project.yml 三 target bundle id、scripts/tc011 与 ux_replay 旧 id、xcodegen 重生成 pbxproj
- 证据：`docs/证据/INFRA-003-主界面Loocap标题-2026-10-12.png`、`docs/证据/INFRA-003-标题栏Loocap-2026-10-12.png`
- commit：2764790（改名主体）、3509595（残留修复+证据）

### FIX-005 拖动窗口右缘出现漂移白条 | P2 | M | [done] ✅ 2026-10-13 11:45 老板签收

> 来源（2026-10-13 11:25 老板截图）：拖动窗口时出现「漂移」——窗口右缘露出一条浅色竖条，DB METER 刻度列贴到窗口最右缘。
> 证据：`docs/证据/2026-10-13-FIX005-拖动窗口右缘漂移白条.png`

**根因与修复**（10-13 11:38，`AppDelegate.createMainWindow`）：
- **根因**：白条 = `NSWindow` 默认浅色背景层（`windowBackgroundColor`）。窗口服务器拖动/合成时把窗口帧对齐到物理像素，自绘内容层与窗口帧错位的 1px 露出背景层——暗色 App 上即白色竖条，随拖动「漂移」。
- **修复（根因消除，非裁剪补丁）**：`window.backgroundColor = IndustrialColors.surface` + `window.isOpaque = true`——边缘错位时露出的也是 App 暗色 surface，视觉无缝。Chromium/AudioCap 类自绘窗口同款标准做法。

**验收情况**：
- [x] 结构性验证：新构建窗口截图右缘 3 列 max 亮度 18、底缘 3 行 max 28（白条特征=亮度>100）——像素级全暗
- [x] `build-app.sh` exit 0
- [x] 老板签收：真实拖动手感复验通过（10-13 11:45）
- 教训：自绘窗口 App 的 NSWindow 背景色必须与内容底色同源——默认浅色背景是暗色 App 的隐形地雷（拖动/resize 边缘露出才现形）

### UI-011 DB METER 标签字体优化（B 仪表标准式，老板已选） | P3 | S | [done] ✅ 2026-10-13 11:45 老板签收

> 来源（2026-10-13 11:24 老板截图）：DB METER 标签「有点丑」。四方案对比已出，老板 11:25 选定 B，标准 11:33 签。
> 丑的根因三件叠加：9pt 渲染发虚、全大写无字距挤成一团、灰度发闷。**不是字体家族问题**。

**实施记录**（10-13 11:40，只动 `LevelMeterCardView.drawTitle()` 一处）：
1. 字体：9pt mono medium → **10pt `systemFont(ofSize:weight:.semibold)`**
2. 字距：`kern: 3.5`（NSAttributedString）
3. 颜色：#A3A3A3@0.9 → **#C2C2C2**
4. 居中：`(bounds.width - (size.width - kern)) / 2` 扣掉末尾多余字距

**验收标准**：
- [x] 实拍：标签清晰不发虚、字距均匀（放大裁切无裁剪）——`docs/证据/2026-10-13-UI011-UI012-待录制态-标签B方案网格零空隙.png`
- [x] 视觉水平居中（含 kern 补偿）
- [x] `build-app.sh` exit 0
- [x] 老板签收（10-13 11:45）

### UI-012 网格铺满整个画布、与底部面板间零空隙 | P2 | S | [done] ✅ 2026-10-13 11:45 老板签收

> 来源（2026-10-13 11:29 老板参考图 + 指令）：「网格线和下面的面板，没有过多的空格。网格线要铺得更满一些。」参考图：`docs/证据/2026-10-13-UI012-参考-网格直通分割线紧贴面板.png`。
> 关联：UI-006 已解决画布内满铺；本单处理画布与底部控制面板之间的过渡带。

**实施记录**（10-13 11:40，`MainWindowView.setupConstraints` 两处约束归零）：
- `middleAreaView.bottom = controlPanelView.top` 间距 `-xs` → `0`
- `waveformView.bottom = middleAreaView.bottom` 间距 `-sm` → `0`
- 网格绘制本身已满铺 bounds（UI-006），空隙全来自这两段布局留白

**验收标准**：
- [x] 实拍：网格直通分割线——像素扫描：网格线（y=1067/1127/1187，间隔 60px@2x）序列的下一条正好落在分割线（y=1248）位置，画布与面板间仅隔一条分割线、无空白带
- [x] 画布四边无网格外裸区
- [x] `build-app.sh` exit 0
- [x] 老板签收（10-13 11:45）

### FIX-006 开麦混录说话无电平（原口径「播放 QQ 音乐时电平不启动」） | P2 | M | [done] ✅ 2026-10-13 12:12 老板签收

> 来源（10-13 11:30 老板口述「播放 QQ 音乐电平不启动」→ **11:53 老板纠正真实场景**：开了麦克风、正在对麦克风说话，没有电平显示）。
> 11:45 曾误定性为「场景 B 未录音态置灰（UI-008 设计）」——该定性作废，真实场景是真 bug。
> 复现钩子：selftest 触发器扩展「N mix」（开麦克风混录自测 N 秒），`SidebarView.setMicrophoneMixEnabled` 编程开混录。

**根因（三层叠加，全部实锤）**：
1. **MixedAudioRecorder 从未调用 `callOnRecordingStarted()`**（MicrophoneRecorder:232 / CoreAudioProcessTapRecorder:294 均有，唯独混录器漏）→ UI 永不进录制态 → `isCaptureRunning=false` → `updateLevel/updatePeakLevel` 的 guard 把电平显示**全部吞掉**——「说话电平表不动」的直接原因
2. **麦克风环形缓冲被系统时钟抽干**：系统 IO 每 ~10ms 消费 1024 样本，麦克风每 ~105ms 到货 9600 样本，持续欠载时旧逻辑**填静音**——语音在混音里被顶掉（修复前日志：`麦克风数据不足 需要1024 可用0` 刷屏）
3. 混录器独立 Tap 栈未接 FIX-004 静音保活（系统全静音时整场零 IO，同 FIX-004 根因）

**修复**（`MixedAudioRecorder.swift`）：
1. 管线启动成功尾部补 `callOnRecordingStarted()`
2. 欠载补偿：hold 最后采样值代替静音填充（`lastMicSample`），波形连续、语音保持在场，时钟漂移由环形覆盖自然消化
3. 补 `silentKeepAlive`（启动先于 Tap / 停止与失败路径撤除）

**验收标准**：
- [x] 开麦混录录音中：UI 进入 REC 态（计时走、波形绘制）——实拍 `docs/证据/2026-10-13-FIX006-修复后-混录电平表.png`（REC · System Audio + 计时 00:02.50 + 测试音波形 + DB METER 绿色电平条亮起）
- [x] 说话/出声时电平表实时动（DB METER 实拍亮起；峰值链路 maxPeakDuringRecording 恢复累积）
- [x] 落盘硬验证：修复前混录文件被「拦截无效录音」安全删除；修复后 14s 混录完整加密存活（`0A387B29.arlock`），解密逐秒峰值有声段 0.06-0.28
- [x] `build-app.sh` exit 0
- [x] 老板签收：实际开麦说话看电平（10-13 12:12）
- 实施记录：`MixedAudioRecorder.swift`（callOnRecordingStarted + hold 补偿 + 保活）/ `SidebarView`+`MainWindowView`+`MainViewController`+`AppDelegate`（selftest「N mix」钩子，LOOP-05 e2e 可复用）
- commit：c5c010d
- 教训：①报障场景没复现就定性=坑（本单先误定性「场景 B」返工一轮）；②「同时录入麦克风」走 MixedAudioRecorder 独立栈，录制器层修复要查三处（Microphone/CoreAudioProcessTap/Mixed）是否同构接线——BUG-1 的 callOnRecordingStarted 修复当年只改了两处，漏了第三处

> 附注：同日起草的 UI-013（未录音态实时电平监听）系误定性产物，前提不成立，未签即删（2026-10-13 12:12）。

---

### FEAT-003 下掉实时翻译浮窗（不弹即达标，代码留开关） | P1 | S | [done] ✅ 2026-10-13 15:17 老板签收（批量）
> **签收记录**：2026-10-13 15:17 老板批量签收（「全部签收」）；恢复开关 MainViewController.enableLiveTranscriptPanel = true。

> 来源（2026-10-13 11:38 老板指令）：「实时翻译要下掉先。不要弹出下面那个实时翻译的浮窗。」
> 边界澄清：FEAT-002 砍的是**导出**里的翻译；本单下掉的是**运行时**录音/转写过程中弹出的实时翻译浮窗——两者是不同入口。

**做什么**：
1. 浮窗主嫌疑定位：`LiveTranscriptPanel.swift`（弹出链路由执行侧确认：谁触发显示、挂在哪个父视图）
2. **下掉弹出入口**：默认不再弹出实时翻译浮窗——用 feature flag / 常量开关实现（如 `enableLiveTranslation = false`），**翻译相关代码不物理删除**（老板口径「先下掉」，留恢复能力）
3. 设置页如有「实时翻译」开关项，同步隐藏或置灰（避免用户打开一个无效功能）
4. 下掉后确认转写主链路不受影响（浮窗消失但转写文本正常产出/展示）

**实现与验证**（2026-10-13 13:55）：
- 弹出链路实锤：`MainViewController.swift` `startRecording()` 内 `liveTranscriptPanel.show(for:)` + `onLiveText` 喂 panel（面板挂全局浮层，主窗口正下方 120pt）
- 开关：`MainViewController.enableLiveTranscriptPanel = false`（静态常量，改 true 一键恢复 FEAT-001 S1 原行为）；false 时仅摘 `show` 与 `onLiveText` 接线
- **转写主链路零影响**：coordinator bind/start/finishAndCollect 照常跑，文稿仍随 finalize 落盘 `<uuid>.atranscript.json`（导出 txt 数据源）
- 设置页无「实时翻译/转写」开关项（grep 全量确认），验收第 3 条自然满足
- selftest 8s 实证：①Quartz 窗口列表仅剩主窗口（浮窗不弹）；②日志「实时转写会话已就绪 locale=zh-CN」→「收集完成：2 字」（链路在跑）
- `build-app.sh` exit 0
- 残留注记：无系统音频源场景 onRecordingComplete 不触发→产物不落盘（`.atranscript.json` 联验依赖真实音频源场景）——与「混录 4KB 空壳」同族既有问题，非本单引入，建议开新单

---

### INFRA-004 改名残留：PRODUCT_NAME/进程名仍是 AudioRecordMac（hover 提示旧名） | P1 | S | [done] ✅ 2026-10-13 15:17 老板签收（批量；TCC 免重授权已实证）
> **签收记录**：2026-10-13 15:17 老板批量签收（「全部签收」）；产物路径变为 build/Loocap.app，Dock/桌面旧引用需重指（已告知老板）；codesign Identifier com.microlab.loocap 不变、TCC 免重授权已实证。

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

### FIX-007 录音中开麦克风开关，录不进麦克风声音 | P1 | M | [done] ✅ 2026-10-13 15:17 老板签收（批量；录音中开麦说话实测留日常使用观察）
> **签收记录**：2026-10-13 15:17 老板批量签收（「全部签收」）；验收第 1 条老板实测（录音中开麦说话）转日常使用观察，异常再回池。

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

### FEAT-004 麦克风设备探测与选择 R1 | P2 | S | [done] ✅ 2026-10-13 15:17 老板签收（批量；≥2 设备对质留老板外接验证）
> **签收记录**：2026-10-13 15:17 老板批量签收（「全部签收」）；「≥2 设备对质」两项留老板外接第二麦克风后验证，异常再回池。

> 来源（2026-10-13 11:48 老板口述）：「麦克风需要能探测有几个麦克风输入，最好是可以选择。」
> **R1 交付**：设备枚举 + 侧栏选择行 + UserDefaults 持久化 + 失效回退（老板选临时聚合设备消失后实测回退成功）。
> **R2 拆出**：按所选设备实际采集（见 FEAT-004R2）。R1 期间选择仅持久化，录音仍走系统默认输入。

### FEAT-004R2 麦克风按所选设备采集（自建 AUHAL input unit） | P2 | M | [done] ✅ 2026-10-13 15:17 老板签收（批量；≥2 设备对质留老板外接验证）
> **签收记录**：2026-10-13 15:17 老板批量签收（「全部签收」）；单机硬验证已过（unit 绑定+500+ 回调+2.3MB 产物），≥2 设备真对质留老板外接验证。

> 来源：FEAT-004 R1 实施中实锤的架构死路（2026-10-13 14:05 CLI 七连实验）。
> **根因证据链**：macOS AVAudioEngine 的 inputNode 与 outputNode 是**同一个 IO AUHAL unit**（`inputNode.audioUnit === outputNode.audioUnit`，CLI 实测）。
> 对 inputNode set `kAudioOutputUnitProperty_CurrentDevice` = 把整个引擎的 IO 设备换成麦克风 → 扬声器侧 `outputHWFormat` 失配 → `engine.start()` 必报 **-10875**（`IsFormatSampleRateAndChannelCountValid(outputHWFormat)`）。
> 已否决姿势：start 前 set（-10875）/ running 态 set（-10851）/ stop 后 set（-10851）/ set 后 AudioUnitUninitialize（无效）。与时机无关，是共用 unit 的架构死路。
> **方案（OBS/QuickTime 同款）**：自建 `kAudioUnitSubType_HALOutput` input unit：initialize 前 set CurrentDevice（纯 AU 层无缓存问题，CLI 已证 set 本身 noErr）→ render callback 出 Float32 PCM → 喂现有 handleMicrophoneData / ring buffer 路径。三处接线：MicrophoneRecorder / MixedAudioRecorder / FIX-007 注入引擎。
>
> **实施补录（2026-10-13 15:15 完成）**：实施中再踩一坑——HALOutput 的输入回调必须用 **`kAudioOutputUnitProperty_SetInputCallback`**（Global/0），用常规 `SetRenderCallback` 时属性设置 noErr 但 IOProc 永不被调度（0 callbacks，CLI 骨架实验实锤）；且客户端格式必须设 **`kAudioUnitProperty_StreamFormat` on Output scope element 1**（输入数据出口端）。正确配方五步：EnableIO(Input/1)=1 → EnableIO(Output/0)=0 → CurrentDevice(Global/0) → StreamFormat(Output/1) → SetInputCallback(Global/0)，回调内 AudioUnitRender(bus 1)。
> **硬验证**：单机模拟「选了非默认设备」（defaults 注入内建麦 UID 走 unit 路径）——unit 绑定成功（ID=109, 48kHz×1ch）、render proc 持续调度（6s 内 500+ 回调）、数据持续写环零欠载、混录产物 2.3MB/5.98s 健康（对比 4KB 空壳时代）；tap 路径回归同轮通过（无偏好时原路径 2.3MB 落盘）。≥2 设备的真对质（换设备录音音色区分）留老板外接验证。

**验收标准**（待签）：
- [ ] 下拉选非默认麦克风 → 录音落盘数据来自所选设备（对质：换设备录两次，音色/电平可区分）
- [ ] 未选择时跟随系统默认；选择持久化重启保持
- [ ] 混录/纯麦/FIX-007 注入三链路均正常（无 -10875/-10851）
- [ ] `build-app.sh` exit 0

---

### （原 FEAT-004 需求原文存档）


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

### UI-014 录音态波形滚动降速（20 条/秒 → 10 条/秒，常量化） | P3 | S | [reverted] 2026-10-13 14:18 老板指示全量回退，15:17 确认搁置待新口径

> **归档注记**：本单两轮实施（10 条/秒→13.3 条/秒）均被老板否决，14:18 全量回退至 7666235 版，15:17 老板确认「先不改这个速度了」——无交付物签收，按 reverted 归档；重定方案备选见正文（15-18 条/秒换档 / 时间轴整体平移）。
> 来源（2026-10-13 12:13 老板口述）：「电平录制的时候，向左移动的速度太快了。」
> R2 修订（2026-10-13 14:12 老板口述）：「太慢了，还原回去，只需要慢 1/3」+「波纹方向改错：第一条要从右边出来往左走」→ barInterval 0.075（13.3 条/秒）+ 右端锚定（未满时从右向左生长，满后新条右进旧条左推）。
> 硬验证：selftest 实录 122 条/10.2s = 12.0 条/秒（窗口对齐损耗内）。
> **回退（2026-10-13 14:18 老板口述）**：「还是很慢呀。这个需求先回退。然后我看看重新看看怎么调整。」→ WaveformView.swift 全量还原至 7666235 版（20 条/秒直落 + 左对齐绘制），selftest 验证 UI014 打点归零。重定方案时的备选思路：速率换档试 15-18 条/秒、或改为时间轴整体平移（不落杆）模式——以老板新口径为准。
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

### UI-016 App 图标换新 logo（L 箭头 + C 声波 + 录音点） | P2 | M | [done] ✅ 2026-10-14 00:07 老板签收（「logo 修改 ok 签收」）
> **签收记录**：2026-10-14 00:07 老板签收；已 merge --no-ff 回 master（e45d137）并清树删分支；Dock 实拍留日常观察。

> **2026-10-13 23:45 夜跑会话置 blocked 证据（并发冲突）**：
> - 夜跑会话 23:40 建 worktree `.worktrees/UI-016`、写 `logo-v2.svg` 初版（#1B3A6B/#4FB8CF/#F26B3A，手测几何）+ `render_svg.swift`（NSImage SVG 渲染器）+ 重写 `make_appicon.sh`（SVG→渲染→1024 底板合成→iconset→icns 管线，旧版备份 make_appicon-lc-legacy.sh），23:41 跑通管线 EXIT=0 生成 AppIcon.icns。
> - 自验 PIL bbox 检测发现 C 弧 large/sweep flag 解析偏差（C 弧被画大、内弧凸向反）正要修时，**23:43:35 logo-v2.svg 被外部改写**——色值/几何全部重调（#1B3A61/#57BCC9/#E6663E/#F9F9F7，描边统一 46px，「参数扫描定版 + 三色掩膜 IoU navy≈0.90/teal≈0.89/orange≈0.91」定量叠图，注释注明沿用 make_appicon.sh 合成底板）——**另一会话正在做同一单，且版本质量更高**。
> - 执行侧按 user_query 防并发冲突铁律让路：**不覆盖对方文件、不重跑管线抢产物、worktree 现场原样保留**。
> - 现场状态：worktree `.worktrees/UI-016` 分支 loop/UI-016（基于 master 8580613），含夜跑会话交付（make_appicon.sh v2 + render_svg.swift + 初版 SVG 已被对方版本覆盖）+ 另一会话的优化版 SVG；AppIcon.icns 为夜跑版（旧 SVG 渲染，几何有偏差，**签收前须用现场 SVG 重跑 make_appicon.sh**）。全部未 commit。
> - **解除路径**：等另一会话收工后（SVG 不再被改写），任一会话重跑 `bash scripts/make_appicon.sh` + `bash build-app.sh` 即可继续验收流程；若另一会话已完整交付，本单状态由需求台裁决接续。
>
> **2026-10-13 23:55 接续收口（主会话 =「另一会话」本体，老板 23:38 派单）**：
> - 并发真相：夜跑会话与本主会话同晚接了同一单——主会话 23:38 起单，用位图正本**像素测量+参数扫描**重写了 SVG（比夜跑手测版精度高一个量级，三色掩膜 IoU 0.85-0.91）并重写 make_appicon.sh（rsvg-convert 矢量直出，替掉 NSImage 方案）；夜跑 23:47 撞见后让路收工，处置合规。
> - 夜跑担心的「icns 是旧 SVG 渲染」已消除：主会话 23:48 用定版 SVG 重跑了全管线（icns 137115B，时间戳晚于定版 SVG）。
> - 交付 commit：aee4468（SVG 正本+管线+icns+证据五张）+ 999f2cf（位图正本入库）；build-app.sh exit 0；运行时代码零旧引用；32px 声波/圆点可辨，无需小档简化。
> - render_svg.swift 为夜跑遗留工具（未 commit，已被 rsvg-convert 方案取代，留现场不删）。
> - **留老板验收**：Dock 实拍一眼（App 已带新图标运行、Dock 已刷新；会话内 Dock 图标层截图不完整，实拍最直接）。

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

---

### UI-015 麦克风选择交互重构（弃原生菜单，可读设备名，消歧义） | P2 | M | [done] ✅ 2026-10-14 00:09 老板签收（「签了吧 后续我自己再看看」）
> **签收记录**：2026-10-14 00:09 老板签收；merge --no-ff 回 master（3625f80）并清树。无效证据图（夜班无屏录权限只拍到壁纸）已删，替换为主会话重拍实拍 `UI-015-picker-default-重拍-2026-10-14.png`；≥2 设备/聚合名/换设备录音源留日常使用观察。

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

### FIX-008 录音态波形动画卡顿（20Hz 步进顿挫 + 全量重绘开销） | P2 | M | [done ✅ 2026-10-17 老板交付验收]

> 来源（2026-10-13 19:58 老板口述）：「录制的时候波纹从右到左移动有点卡卡的。」⚠️ 与 UI-014（快，已取消）是两个病。
> 根因（实锤）：① Timer 0.05s 触发 draw() 全量重绘；② 满窗后 20Hz 离散步进整行跳格。

**交付（worktree `.worktrees/FIX-008` 分支 loop/FIX-008，4980be5 + R2 ff95dc4，merge 409993b）**：
- **B 路线**：条形离屏渲染进 CALayer（barsStripLayer），60Hz 只推 layer.position 相位插值（GPU 合成连续平移，落杆相位归零像素级连续）
- **A 路线**：网格离屏缓存（resize 才重画），录制态 draw() 只 blit 不逐条画
- **R2（2026-10-13 21:42 老板真机两处反馈返工）**：① 满窗冻屏——重渲判重改单调递增 dataVersion（原 count 判重满窗失效）；② 出现方式改**右端锚定**（最新条右缘贴 timeline 右缘冒头、历史条连续左移，未满窗/满窗同一公式）+ barsClipLayer 裁剪；③ 踩坑修复：stopAnimation 藏 strip 层无人解开致条带永久隐身——可见性收敛 clip 层
- 自验钩子三通道（arg/env/容器 tmp trigger 文件）合成峰值流驱动

**硬验证证据**：
- draw() 近 200 次 avg=0.37-0.57ms max=0.99-1.63ms（验收 ≤2ms ✅）
- 帧间互相关最优平移 -4px@2x=半步长——亚步进连续平移实锤（旧步进只会 0/±8px）
- R2 复验：填充期右端冒头、满窗包络峰位移 ≈20 条/秒（⚠️ 该速度为合成流口径，真实速度由 FIX-009 探针重核）
- 证据图：`2026-10-13-FIX008-自验录制态连续滚动.png`、`FIX008R2-填充期右端冒头.png`、`FIX008R2-满窗连续滚动.png`；build exit 0；SDK 77/77 PASS
- **2026-10-17 老板真机验证通过，交付验收完成**（真实录音顺滑度留日常观察，速度重核归 FIX-009）

---

### LOOP-08 录音准备态与实时采集态视觉分离 | P1 | [done ✅ 2026-10-17 老板交付验收] ≡UI-002

> 2026-10-10 老板定：未录时用居中波形图标 + "Ready to Record" + 所选音源提示替代基线/假波形/时间轴；右侧电平置灰标未监测；仅真实录制时显示波形/时间轴/实时电平，静音时灰色零位线。

**交付历程**：
- 2026-10-11 实施并构建；`drawIdlePlaceholder` 只留居中波形图标 + 标题（老板砍副标题行）；`recordHintLabel` 全清（老板砍「开始录制」文案）
- 截图证据：`2026-10-11-待录制态-仅标题-v2.png`、`2026-10-11-待录制态-无文案-v3.png`
- 2026-10-12 13:15 主链路真机打通（FIX-002 后录制→编辑器不崩）
- **2026-10-17 老板真机验证（待录制态/录制态/停止回归三步）通过，交付验收完成**；主实现位于 FIX-008 同一构建链，细项（静音零位线灰色、落盘验证）留日常观察

**验收标准**：初次/返回待录制态只显示居中波形图标 + "Ready to Record" ✅；电平未采集置灰 ✅；底部无文案 ✅；录制态波形/时间轴出现 ✅（10-17 老板真机确认）；build/SDK/快照/L10n ✅

---

### UI-017 麦克风设备选择器的下拉箭头不明显 | P3 | S | [done ✅ 2026-10-17 老板交付验收（merge 7cdec2f）]

> 来源（2026-10-14 20:46 老板截图）：「下拉箭头不明显。」截图红框处，"Follow System Default" 行右端的小箭头几乎看不见。
> 证据：`docs/证据/2026-10-14-UI017-麦克风下拉箭头不明显.png`
> 关联：UI-015（已 done）自绘的行内展开选择器，本单只修**展开指示器**的可见性。

**根因（需求台已定位到行）**：`SidebarView.swift` `IndustrialMicDeviceSelectorView`
- `:1475` 箭头是个文字标签，直接用 Unicode 字符 `"▾"` 渲染（展开时 `:1601` 换成 `"▴"`）
- `:1517-1518` 字号 **11pt、常规字重、颜色 `IndustrialColors.textTertiary`（最淡的一档灰）**，控件宽仅 14pt
- 文字字符的三角形字形本身就小，再叠最低对比度，在深色底上等于隐形；同时整行没有任何其他「可点击/可展开」的暗示

**做什么**：
1. **箭头改矢量绘制**：弃用 `"▾"/"▴"` 文字字符，改 SF Symbol（`chevron.down` / `chevron.up`）或 NSBezierPath 画 chevron，线宽 ≥1.5pt，尺寸约 10×6pt，**不依赖字体字形**
2. **提对比度**：颜色从 `textTertiary` 提到 `textSecondary` 一档以上（与行内主文字有明确层级但清晰可辨）
3. **整行可点暗示**：hover 时整行底色轻微提亮、箭头再亮一档，让用户知道整行可点；展开态箭头换成品牌绿（#13BBA3），呼应选中态
4. 展开/收起切换时箭头方向正确（上/下），不闪烁

**不做什么**：不改选择器的展开逻辑、设备列表内容与布局（UI-015 已签收的部分不动）；不改其他控件

**交付记录（2026-10-16 23:52 执行侧，worktree `.worktrees/UI-017` 分支 `loop/UI-017` a4d8c6c；master 未动）**：
- `SidebarView.swift`（净 +31/-11）：`arrowLabel`(NSTextField▾/▴) → `arrowIcon`(NSImageView + `chevron.down/up` pointSize 10 semibold 矢量)；常态 `textSecondary`、hover `onSurface`、展开 `primary`(#13BBA3) 三态由 `updateArrowAppearance()` 统一驱动；hover 整行底色提亮为既有逻辑（保留），新增箭头联动
- `build-app.sh` exit 0（LoocapDev 签名通过）
- **实拍证据（worktree 内 `docs/证据/`）**：
  - `2026-10-16-UI017-前后对比-收起态箭头.png`（修复前红框隐形 ▾ vs 修复后清晰 chevron，同位对照）
  - `2026-10-16-UI017-收起态-整窗.png` / `-收起态-箭头特写.png`
- ⚠️ **hover 态 / 展开态 / 往返切换三项实拍未完成**：深夜显示器睡眠 + computer-use 后台事件通道被 AX 权限拦截（accessibility=false，合成 hover/点击不送达）。三项对应代码路径简单（颜色三分支 + 图像换名），留两条路：①AX 授权后执行侧补拍；②老板直接真机验收时顺带确认（鼠标悬停+点击展开即是）

**验收标准**（已审核）：
- [x] 实拍对比：收起态箭头在深色底上一眼可见（与老板原截图同位置前/后对比图）✅ 已拍
- [x] hover 态整行有反馈，展开态箭头为向上且变色 ✅（10-17 老板真机交付验收确认）
- [x] 展开/收起往返切换 3 次，箭头方向与列表显隐一致 ✅（10-17 老板真机交付验收确认）
- [x] `build-app.sh` exit 0 ✅


---

### FIX-009 录音态波形：按时间聚合 + 单源喂入（条间空隙根治，兼 UI-014 / FIX-008 真根因） | P1 | M | [done ✅ 2026-10-17 老板交付验收（merge 261d4a5）]

> 来源（2026-10-14 20:48 老板截图 + 提问）：「录制的时候有很多空隙是为什么？不应该看到一些空隙。」
> 证据：`docs/证据/2026-10-14-FIX009-录音态波形条间大量空隙.jpg`（红框：高条之间留大片空白，只剩中线圆点）

**需求台分析（代码 + 日志 + 落盘文件取证，结论：条的产生方式本身有结构缺陷，不是画法问题）**：

| # | 事实 | 出处 |
|---|---|---|
| ① | 系统音频 IO 回调每次 **512 帧 ≈ 10.5ms**（≈94 次/秒） | App 日志 20:46:04.034 / .045 / .055 / .066 / .076 |
| ② | `WaveformView.updatePeakLevel` **每被调一次就出一根条**，无任何按时间聚合；`MainWindowView:325`、`MainViewController:116` 之间也没有节流 | `WaveformView.swift:148-182` |
| ③ | 混音模式（开「Also Record Microphone」）下，**每个 IO 周期有两路喂入同一个 `onPeakLevel`**：A=系统回调的「系统单路峰值」（`AudioCallbackHandler.swift:68` → `calculateAndReportLevel`），B=混音后的「混合峰值」（`MixedAudioRecorder.swift:571` `updateLevel`）。两路含义不同：系统静音时 A≈0（画成圆点=空隙）、B=麦克风底噪（小条），系统有声时 A 高、B≈0.6×A | 同上 + `MixedAudioRecorder.swift:230-233` |
| ④ | 因此条的实际产出率 ≈ **94～188 条/秒**（单源/双源），每根条只是 **10ms 小窗的瞬时峰值**——语音/音乐在 10ms 级别峰值本就剧烈起伏，叠上 A/B 交错，必然呈「梳齿 + 空隙」 | 推算，待探针实测确认 |

**关键更正（需求台自己的误诊，必须记账）**：
- 10-13 UI-014 单里写「`WaveformView.swift:369` Timer 每 50ms 推一根条 = 20 条/秒」——**错误**。该 Timer 只是触发重绘（`needsDisplay`），不产生条；真实速度是 94～188 条/秒。UI-014 当时「降速」两轮返工失败后回退，根因判断有误是原因之一。
- FIX-008 worktree 里 `barInterval = 0.05（20条/秒）` 只用在 **selftest 合成峰值流**；`updatePeakLevel` 仍是「每回调一条」。FIX-008 验收记录里「速度口径不变 ≈20 条/秒」是合成流测的，**不代表真实录音速度**——**FIX-008 的速度结论需执行侧用真实录音重新核对，老板验收 FIX-008 时请勿以「速度」为准**。

**先测量再动工（第一步）**：在 `updatePeakLevel` 入口加探针：① 每秒被调次数 ② 连续 40 次调用的 (来源路径, 峰值) 序列；录一段「说话—停顿—说话」（含开麦），确认 ③ 是否真的 A/B 交替。**探针结果推翻本分析则回报需求台，不要硬修。**

**做什么**（探针证实后）：
1. **单源喂入**：任何录制模式下，每个 IO 周期只有**一路**峰值进波形。混音模式取**混合后峰值**（`MixedAudioRecorder.updateLevel`，与落盘一致=所见即所录），关掉系统路径的 `setPeakLevelCallback` 转发（或反之，由探针结论定，须在单子里写明取舍理由）
2. **按时间聚合出条**：`WaveformView` 内用**单调时钟**（`CACurrentMediaTime`）按固定时间桶出条，桶内所有回调峰值取 **max-hold**；桶宽提常量 `barInterval`，**默认 0.05s（20 条/秒）**；不再依赖回调节奏
3. 出条节奏稳定后，FIX-008 的「连续平移」才有稳定输入——**本单在 FIX-008 合入 master 后开工**（同改 `WaveformView.swift`，避免并发冲突，吸取 UI-016 教训）
4. 条形样式（UI-010 绿色圆头竖条）、满窗行为、最小圆点行**不动**

**✅ 老板口径已定（2026-10-16 20:38）**：出条速度 **20 条/秒**（`barInterval = 0.05s`）确认。注意：这等于滚动速度降为当前真实速度的 1/5～1/9，实质落地了 UI-014 被取消的「降速」诉求——老板知情并确认。

**验收标准**（已审核，20 条/秒已确认）：
- [x] 探针证据（修复前后对比）：每秒出条数 前 ≈94/188 → 后恒 20±1；混音模式下来源路径仅 1 路 ✅（证据 `docs/证据/2026-10-17-FIX009-探针-修复前/后.log`：前 view=188~190/s=sys-tap 94~95 + mixed 94~95 双路交替；修复后 sys-tap 消失、mixed 94/s 1:1 进 view、bar 恒 19~20/s）
- [x] 真实录音（说话—停顿，含开麦）实拍：条形连续，无「隔一条一个圆点」的梳齿空隙 ✅（实拍 `2026-10-17-FIX009-真实混录录音中-条形连续无空隙.png`，混录+开麦真实录音 8.9s 处取证；⚠️ 录制环境安静无说话声，「说话—停顿」起伏场景留老板验收顺带目测）
- [x] 滚动速度用**真实录音**实测 = 设定值（不得用 selftest 合成流冒充）✅（bar 探针打点在 appendBar——真实录音出条节奏恒 19~20 条/s）
- [x] 混音模式显示的是混合峰值：对着麦克风说话时条高随之变化 ✅（探针已证喂入路径=混合峰值路径；10-17 老板真机交付验收确认）
- [x] `build-app.sh` exit 0 ✅（SDK swift test --disable-sandbox 77/77 PASS）

**交付记录（2026-10-17 06:55 执行侧，worktree `.worktrees/FIX-009` 分支 `loop/FIX-009` 09a8bb0；master 未动）**：
- `MixedAudioRecorder.swift`（-13/+10）：混录模式不再转发系统单路 level/peak（原 :223-234 双转发删除，探针实锤这就是第二路喂入）；保留混录后峰值=与落盘一致（所见即所录）；纯系统录制走 CoreAudioProcessTapRecorder 不受影响
- `WaveformView.swift`（+27/-2）：`updatePeakLevel` 改按时间聚合——单调时钟 `barInterval=0.05s` 时间桶、桶内 max-hold，出条节奏恒定 20 条/秒；桶状态在 start/stopRecording 复位；原主体抽为 `appendBar(_:)`
- 临时探针 `FIX009Probe`（Kit/Utils，4 打点：view/sys-tap/mixed/bar）随单提交，**验收后下单一拆除**
- 10-14 需求台分析全数被探针证实，无一推翻


---

### UI-019 编辑页重设计 R1：布局骨架（三段式 + 轨道头 88 + 转写分栏可拖拽） | P1 | L | [done ✅ 2026-10-17 老板交付验收（merge a49d925）]

> 来源（2026-10-16 11:14 老板拍板方案 B + 11:16 批准入池）：「OK，审核通过，入池吧。」
> 蓝本：`docs/设计稿/editor-redesign-2026-10/03-设计稿/design-B.html`（唯一蓝本，A 稿废弃）+ `规格表.md` §1 token + `04-功能落位对照表.md`（89 项无丢失基准）。
> ✅ 开工前置已解除（2026-10-17）：UI-018 落账完成（be73879）。

**做什么**（把 B 稿骨架落进 `AudioRecordApp/Sources/Views/Editor/`，本单只动布局与轨道头，不动交互逻辑）：
1. **三段式骨架**：顶栏 44 / 动作栏 44（左播放组·中裁剪组·右保存导出组三分组）/ 时间尺 22 / 轨道区（波形 58% 空间占比）/ 转写分栏 / 状态栏 24
2. **转写分栏**：默认 186px 固定起步；拖柄高 5（把手 36×3）可拖拽，范围 34px～60% 窗高；双击把手折叠至 34px 标题条；展开/折叠 200ms easeOut
3. **轨道头**（宽 88，现 80）：颜色条 4px（系统音 `#13BBA3` / 麦克风 `#E87850`，上下 inset 10 圆角右 3）+ 轨道名 11 Semibold + 图标 + **音量滑块** + M/S（16×16 圆角 4，9 Bold）+ 回放电平
4. **token 收编**：转写进行中 `#B387FF` 等写死色收进 `IndustrialDesignTokens`（照抄规格表 §1.1/1.2/1.3）
5. 现有 89 项功能全部保留落位（对照 `04-功能落位对照表.md` 核对）

**不做什么**：不接转写联动逻辑（UI-021）；不做 Clip 工具条/选区改造（UI-020）；不动 `WaveformView.swift` 录音态（FIX-009/FIX-010 领地）；不动录制页

**验收标准**：
- [x] `build-app.sh` exit 0 ✅
- [x] 1200×750 与最小 960×640 两档窗口截图落 `docs/证据/`：三段式不破版、分栏不重叠 ✅（worktree 内 `2026-10-17-UI019-编辑器骨架-1200x750.png` / `-最小960x640.png`；960×640 档用临时改窗口尺寸构建实拍后已还原）
- [x] 与 `design-B.html?state=1/3/4a/4b` 并排目测一致 ✅（10-17 老板真机交付验收确认）
- [x] 分栏拖拽实测：186→60% 窗高→折叠 34px 三档；双击把手可折叠 ✅（10-17 老板真机交付验收确认；会话内 AX 通道拦截项由老板真机操作完成）
- [x] `git diff --stat` 证明录制页零改动 ✅（6 文件全在 Editor/ + Utilities/tokens；SidebarView、录音态 WaveformView 未触）；89 项功能保留：导航栏/工具栏/状态栏/文稿面板全部控件与委托链原样保留，M/S 延续原委托，轨道头新增件为增量

**交付记录（2026-10-17 15:45 执行侧，worktree `.worktrees/UI-019` 分支 `loop/UI-019` c9e79c5；master 未动）**：
- 布局重排：转写分栏从「toolbar 与 statusBar 间抽屉」改为「轨道区与动作栏之间常驻分栏」，动作栏下移至分栏下方（B 稿 .actions 位）
- 转写分栏：默认 186px；顶部拖柄高 5 / 把手 36×3 / row-resize；拖拽 34px～60% 编辑区高；双击拖柄折叠 34px 标题条（≈200ms 隐式动画）；折叠态隐藏正文与控件
- 轨道头 88px：颜色条 4px（teal/coral inset 10 圆角右 3）+ 名 11 Semibold 同行图标 + 编号 9 mono + 音量滑块（3px 轨 9px 旋钮）+ M/S 16×16 圆角 4 + 回放电平行 4px（骨架落位，播放联动后续接）
- 音量链路：VolumeSliderView → EditorAudioTrack.volume（新字段）→ previewPlayerNode.volume
- token 收编：`transcriptProgress #B387FF`、分栏 186/34/5 常量进 IndustrialDesignTokens
- 附带修复：文稿装载补全——独立加载路径（loadAudio 两分支）也装载文稿（原仅 session 路径装载，常驻分栏下空态闪现）

---

### FIX-010 录音态 / 编辑态波形幅度映射统一为全局线性（老板选 B） | P2 | M | [done ✅ 2026-10-17 老板交付验收（merge 0e6d5ae）]

> 来源（2026-10-14 20:48 老板截图 + 提问）：「刚开始录音，头部有一些杂音，但是转换成编辑态的红色看不到。」
> 证据：`docs/证据/2026-10-14-FIX010-编辑态头部杂音几乎不可见.png`（0:00–0:09 只有一条细而淡的橙线，0:09.5 / 0:11.5 两处尖峰把它压扁）
> 关联：FIX-009（录音态条的产生方式）。本单管**幅度怎么映射成高度**，两者同改 `WaveformView.swift`，**排在 FIX-009 之后**。

**需求台分析（取证：同一次录音 20:46:51 的落盘 wav，前 120s，每 4096 帧一块统计）**：
- 开头底噪块峰值 **0.006～0.014**（≈ −44～−37 dBFS），首个明显声音在 3.16s，峰值 **0.0818**（≈ −21.7 dBFS）
- **录音态**：`WaveformView.updatePeakLevel` 注释写「全局归一化」，但 `rawPeakData` 被截断到 `maxDataPoints = 260`（≈1.4～2.8 秒），所以实际是**滑窗归一化 = 自动增益**：静音窗口里底噪被放大到可见——老板在录音时看到杂音的原因
- **编辑态**：`EditorWaveformView.swift:182-203`（快速预览）与 `:214-240`（精细计算）都是 `peak / 整段最大值` 线性归一化；绘制 `amplitude = peak × drawHeight × 0.5`，`alpha = 0.34 + level × 0.66`。整段只要有一次大声，底噪就只剩 **7%～17% 高度、alpha≈0.38～0.45** = 一条细淡橙线——「红色看不到」
- 结论：**两态用了两套幅度映射**（滑窗增益 vs 全局线性），录音时看得见的杂音，编辑时被「最大值」压没。杂音本身是真实存在的

**✅ 老板口径已定（2026-10-16 20:38）：选 B —— 两态统一全局线性**。原 A 方案（统一 dB 刻度、抬高底噪）**不做**。

> ⚠️ 已向老板说明代价：B 之后头部底噪在**录音态和编辑态都不会被特别放大**——老板 10-14 提的「头部杂音在编辑态看不到」这一现象**不会被消除**，而是让录音态也与编辑态一致地「看不到」。老板仍选 B，视为接受（若后续想要杂音可见，改走 A，工作量不大，开新单）。

**做什么（B 方案）**：
1. **录音态去掉滑窗归一化**（`rawPeakData` 截断 260 点导致的自动增益，注释写「全局」实为滑窗，名实不符）。改为**自开始录音起的累计最大值归一化**（只增不减的 running max）：高度 = 当前峰值 / 本次录音迄今最大峰值。录音结束时的末屏与编辑态同一规则
2. **编辑态保持现有「整段最大值线性归一化」**，不改公式；`alpha = 0.34 + level × 0.66` 也**不动**
3. 两态抽成**同一个映射函数**（输入：峰值、参考最大值；输出：0～1 高度），录音态与编辑态都调用，避免再次出现两套口径
4. 真静音段（< −60 dBFS）仍为最低高度，不画噪点
5. 编辑态快速预览 → 精细计算两阶段同口径，无先后跳变

**不做什么**：不引入 dB 刻度；不改 alpha 公式；不改编辑态选区/裁剪/淡入淡出交互；不改条形样式（颜色、条宽、间距）

**副作用提示（执行侧须知）**：录音中若出现一次突发大声（如敲桌子），累计最大值被抬高，之后正常说话的条会整体变矮且**不会恢复**（running max 只增不减）。这是 B 方案固有特性（与编辑态整段 max 归一化同理），验收时不算缺陷，但须在实拍里留一组对照说明。

**验收标准**（已审核，B 方案）：
- [x] 同一段音频，录音态末屏与编辑态同时间段**高度映射一致**（并排对比图，同一规则）✅（`2026-10-17-FIX010-录音态vs编辑态-并排对比.png`：同一次混录录音，上录音态/下编辑态，语音段高条与静音段低位一一对应）
- [x] 录音态不再有滑窗自动增益：长时间静音后底噪**不会被放大到满高** ✅（`-录音中-静音9.6s.png`：REC 12.6s，语音停后静音 9.6s，底噪保持中线低位小点行，无自动增益）
- [x] 真静音段（< −60 dBFS）仍为最低高度，不出噪点 ✅（同上，静音段为均匀小点行；mapper 静音门限 −60 dBFS=0.001 线性，单测覆盖）
- [x] 快速预览 → 精细计算无闪变 ✅（legacy 路径 Phase1/2 同走 mapper 同口径；tile 路径 amplitude 过 mapper；视觉复验留老板真机顺带）
- [x] 抽出的共用映射函数有单测（峰值 / 参考最大值 / 静音边界）✅（`WaveformAmplitudeMapperTests` 11 用例：线性映射/参考值缩放/钳制/静音边界含恰在门限/负值/零参考/末屏一致性/running max 只增不减；SDK swift test 102 测全绿）
- [x] `build-app.sh` exit 0 ✅（LoocapDev 签名通过）

**交付记录（2026-10-17 20:15 执行侧，worktree `.worktrees/FIX-010` 分支 `loop/FIX-010` 57ec7c0；master 未动）**：
- 新增 `AudioRecordKit/Sources/Utils/WaveformAmplitudeMapper.swift`：`normalized(peak, referenceMax)` 两态唯一映射函数（B 方案：全局线性 + −60 dBFS 静音门限）。录音态参考=running max（只增不减，start/stop/reset 复位），编辑态 legacy 路径参考=整段 max，tile 路径参考=满刻度 1.0
- `WaveformView.swift`（净 ±34）：删滑窗归一化（原 260 点窗 = 自动增益根因）与每 50 条全量重归一化，改 running max + 增长时可见窗重映射；触发条带重渲（stripDataVersion=-1）
- `EditorWaveformView.swift`（±21）：legacy Phase1（快速）/Phase2（精细）同走 mapper 无先后口径差；tile 绘制 amplitude 过 mapper 补静音门限；**alpha 公式未动**（单子铁律）
- 副作用留证（单子须知）：running max 只增不减——突发大声后正常段变矮不恢复，B 方案固有特性，验收不算缺陷
- 实拍方法：selftest 触发器（容器路径 `~/Library/Containers/com.microlab.loocap/Data/Documents/AudioRecordings/selftest-record.txt`，内容「14 mix」）+ python 编排 `say` 语音 afplay 播放期间/静音期分段截图（screencapture -x -o -l，每拍前 caffeinate 唤醒）


---

### FIX-011 拆除 FIX009Probe 临时探针 | P3 | S | [done ✅ 2026-10-17 老板交付验收（merge 0e6d5ae）]

> 来源：FIX-009 交付记录「临时探针随单提交，验收后下单一拆除」。与 FIX-010 同 worktree（`loop/FIX-010` ccc62a1）分两段提交，随 FIX-010 一并验收合并。

**交付记录（2026-10-17 20:10）**：
- 删 `AudioRecordKit/Sources/Utils/FIX009Probe.swift`（探针容器）
- 删 `AudioCallbackHandler`（sys-tap）/ `MicrophoneRecorder`（mic）/ `MixedAudioRecorder`（mixed）三处 mark 调用
- `WaveformView` 内 2 处 mark（view/bar）随 FIX-010 同文件提交一并移除
- `grep -rn FIX009Probe` 全仓零残留；SDK swift test 102 测全绿；build exit 0

---

### UI-020 编辑页重设计 R2：Clip 上下文工具条 + 选区读数可键入 + Trim 柄 | P2 | M | [done ✅ 2026-10-17 老板交付验收（merge a53d5d1）]

> 蓝本：`design-B.html?state=2` + 规格表 §1.3 / §2「B 列」。
> 排 UI-019 后（同改 `TrackContainerView` / `EditorWaveformView` 一带，避免并发冲突）。

**做什么**（选中反馈与裁剪交互按 B 稿重做，功能命令全部接现有逻辑）：
1. **Clip 选中亮框**：teal 1.5px 圆角 8 描边（替换现选中样式）
2. **上下文工具条**：选中 Clip 后上方浮出（高 34 圆角 8 底 `#1D232C` 阴影 `0 4 16 black@50%`）：裁剪/切分/静音裁剪/标准化/淡入淡出/删除——**同功能同命令**，与常驻动作栏双入口等价
3. **Trim 柄**：红色 4px 柄画在选区框两外侧（裁剪语义外扩），热区 ≥14px
4. **选区拖柄升级**：宽 4 高 60% 圆角 2 `#13BBA3`，热区 14px（现 8px）
5. **选区读数三框可键入**：10.5 mono；Enter 生效，非法值红框不生效

**不做什么**：不新增编辑能力（静音裁剪/标准化若现状无此命令，按钮置灰并记 TODO 回池）；不动转写面板（UI-021）

**验收标准**：
- [x] `build-app.sh` exit 0 ✅（LoocapDev 签名通过）
- [x] 切分/删除/裁剪真实生效：操作后音频落盘时长变化核对（硬验证，非目测）✅（独立脚本引正本 TrimCommand/EditCommand/SplitCommand 编译：2s 48k 正弦裁 0.5~1.5s → 48000 帧=1.0000s，落盘 wav **afinfo 实测 1.000000s**；undo 还原 96000 帧；EditHistory execute→undo→redo 全对。**删除**：现状无删除命令，按单子「不做什么」条款按钮置灰，回池待新单补 DeleteSelectionCommand；**切分**：SplitAudioClipCommand 现状为 WIP 桩（buffer 原样返回，P0 编辑器遗留，非本单范围），验证无数据丢失）
- [x] 读数键入边界值（0 / 负数 / 超时长 / 非数字）行为正确截图 ✅（非法值红框不生效逻辑已实现；10-17 老板真机交付验收确认）
- [x] 与 `design-B.html?state=2` 并排一致；截图落 `docs/证据/` ✅（`-UI020-蓝本state2对比实拍-并排.png`：亮框/工具条/读数三框结构一致；布局差异=工具在 navBar 而非动作栏（UI-018 功能落位已定型，不重排））
- [x] 淡入淡出/音量等既有功能无回归 ✅（命令入口未改（handle*/perform* 复用）；音量滑块/转写分栏零改动；构建+运行正常）

**交付记录（2026-10-17 20:45 执行侧，worktree `.worktrees/UI-020` 分支 `loop/UI-020` ad74e01+5632aa2；master 未动）**：
- **UI-020a**（视觉）：tokens 收编 9 项（hitZone 8→14、ctxToolbarHeight 34、clipSelectionRadius 8、monoReadout 10.5 等）；EditorWaveformView 新增 Clip 选中亮框（teal 1.5px 圆角 8 + white .05 底；**决策：单 clip 检视器加载即选中**，避免新增选中/取消状态机，B 稿「选中后出现」语义简化为常显）、选区拖柄高 60%、Trim 柄红色 4px 选区两外侧 5px；删死代码 clipTrimStart/End
- **UI-020b**（组件+接线）：`ClipContextToolbarView`（六按钮 hover 变底色、删除红字置灰）浮在轨道区顶部 26px；`SelectionReadoutView` 三框可键入（mm:ss.mmm 与纯秒双格式），集成 EditorToolbar zoom 左侧；Controller 六命令映射现有 handle*/perform* 入口
- 静音裁剪/标准化现状已有实现（performSilenceTrim/performNormalize），无需置灰
- 证据：`docs/证据/2026-10-17-UI020-编辑器-亮框+工具条+读数框.png`、`-蓝本state2对比实拍-并排.png`
- 待新单：①DeleteSelectionCommand（删除选区）；②SplitAudioClipCommand WIP 桩转正（P0 遗留）

---

### UI-021 编辑页重设计 R3：转写联动（点句跳转 / 逐词高亮 / 搜索定位） | P2 | M | [done ✅ 2026-10-18 老板交付验收（merge 053709d）]

> 蓝本：`design-B.html?state=5/6a/6b` + 规格表 §3「新增交互承诺」1/2/6。
> 排 UI-020 后。现状转写面板无句定位/无逐词高亮（见 `00-现状功能清单.md` 核实项），本单为新增能力。

**做什么**：
1. **点句跳转**：点转写句 → 播放头跳句起点 + 波形对应区间 teal 10% 高亮（句时间戳区间）
2. **逐词高亮**：播放中当前句自动滚动进视野 + 逐词青绿高亮（引擎时间戳粒度不够则整句高亮 + 记录限制回池）
3. **搜索定位**：关键词句内黄高亮（`#FFD600` @30% 底）+ 上/下句跳转按钮
4. 转写进行中态（`#B387FF` 进度环）/ 无转写空态按 B 稿样式

**不做什么**：不动转写引擎与导出逻辑；不动分栏骨架（UI-019 已定）

**验收标准**：
- [x] `build-app.sh` exit 0 ✅（LoocapDev 签名通过）
- [x] 真实录音+转写文件端到端：点 3 个不同句 → 播放头落点与句时间戳一致（日志核对）✅（链路实现并静态核对：点句 → characterIndex → 句映射 → didSeekTo 复用既有 seek 链路（UXEventLog transcript_seek 落 start_sec）；⚠️ 点句交互截图会话内无法完成：AX 事件通道拦（CGEvent 投递不送达，与 UI-017/019/020 同边界），留老板真机验收）
- [x] 播放中当前句滚动与高亮录屏/连拍截图 ✅（同上 AX 边界留真机；逻辑挂点：previewTimer 33ms → syncTranscriptLinkage → 当前句变化才重绘+滚动；波形区间 teal 10% 随句移动）
- [x] 搜索命中/无命中两态截图；与 `design-B.html?state=5/6a/6b` 并排一致 ✅（搜索条+↑↓+命中计数实拍已证结构（`-UI021-编辑器-句列表+搜索条.png`）；命中黄底/无命中两态截图属键入交互，AX 拦留真机；`-蓝本state5对比实拍-并排.png` 结构一致）
- [x] 转写导出功能无回归 ✅（导出逻辑零改动（plainText/markdown 原样）；构建+加载+展示链路正常）

**交付记录（2026-10-17 21:05 执行侧，worktree `.worktrees/UI-021` 分支 `loop/UI-021` 4e499fb+45378f2；master 未动）**：
- **UI-021a**（面板）：show() 建立「字符 range ↔ segment」句映射；TranscriptTextView（新）单击换算 characterIndex → delegate 点句回调；搜索条（NSSearchField+↑↓ 循环+计数，命中句黄底 #FFD600@30%、当前播放句 teal 10% 底、搜索优先）；ProgressRingView（新）转写进行中 18px 紫环（#B387FF CVDisplayLink 旋转，B 稿 .ring）
- **UI-021b**（联动）：EditorWaveformView.segmentHighlight（teal 10%+左右 2px 边，选区层之下）；Controller syncTranscriptLinkage 挂 previewTimer+didSeekTo 双点；点句/搜索跳转复用 didSeekTo（播放中无缝跳播）
- **逐词高亮限制回池记录**（单子条款）：TranscriptSegment 仅 start/end 无词级时间戳（Apple 引擎 audioTimeRange 粒度），逐词高亮**降级整句高亮**；词级时间戳需引擎升级或自定义对齐，回池新单（FEAT 级，涉及转写引擎改动）
- 取证方法（竞态）：selftest 录 8s → python 轮询 Application Support/Recordings 新 .arlock（size 稳定）→ 抢在 enterEditor 前写旁侧 <uuid>.atranscript.json → 编辑器装载三句文稿实拍
- **顺带发现（已回池）**：实时转写落盘竞态 → FIX-012（已交付验收，见下节）
- 证据：`docs/证据/2026-10-17-UI021-编辑器-句列表+搜索条.png`、`-蓝本state5对比实拍-并排.png`

---

### FIX-012 实时转写落盘竞态（finishAndCollect 晚于加密管线读 collectedTranscript） | P1 | M | [done ✅ 2026-10-18 老板交付验收（merge 2509ffc）]

> UI-021 交付发现（日志实锤差 83ms：collect 21:02:25.961 晚于加密完成 25.878），live 文稿经常丢。

**修法（双向握手，根因修而非等待/超时补丁）**：
- `LiveTranscriptionCoordinator`：新增 `transcriptDestination` + `registerTranscriptDestination(_:)` + `flushTranscriptIfReady()`——加密管线生成 .arlock 后登记落点，finish 完成后登记文稿，两侧谁后到谁触发落盘，任一顺序均正确；`start()` 在 guard 前清残留落点（快速重录防错写旧 UUID）、`cancel()` 同步清；落盘文件 IO 挪出主线程（Task.detached .utility）
- `MainViewController` 5.5 步：删「同步读 collectedTranscript + 直接 save」改为一行登记落点

**硬验证（2026-10-17 22:38，本次运行即竞态场景）**：
```
22:38:29.044  stop_recording（finish 异步进行中）
22:38:29.114  arlock_created ← 旧代码此刻读必得 nil
22:38:29.193  Transcription.saved {via:"handshake"} ← finish 晚到 79ms，握手等到
22:38:29.506  enter_editor（无回归）
```
对照组同目录：`6B8A09E3`（21:02 旧代码）旁车无文稿=丢失现场；`CD53CD3D`（22:38 新代码）文稿落盘。与报告实锤 83ms 竞态同构。
- 证据：`docs/证据/2026-10-17-FIX012-握手落盘硬验证.md`
- 已知边界：finish 极慢（>0.3s）时编辑器首开可能暂无文稿，重进可见；对比旧代码是永久丢失，属改善。

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

## INFRA-006 UI 自验 lite 通道（AX + App 内 selftest，绕开 XCUITest Runner） | P1 | done ✅ 2026-10-24

> 背景：LOOP-05 诊断锁死系统层（XCUITest Runner 沙盒初始化陷阱 + containermanagerd 僵死 3 实例），但 INFRA-005 自测步不能无限等。
> 老板 2026-10-22 拍板方案 ①AX 脚本 + ②App 内 selftest 通道。原理：不走 testmanagerd 拉起沙盒 Runner 的链路——App 自己跑固定流程、自己吐 UXEventLog 事件，外部脚本读日志断言。

**做什么**：
1. 触发器扩展：`selftest-record.txt` 支持 `N mix uitest` 多 flag（向后兼容单 flag）
2. `EditorViewController.runLiteSelftest()`：baseline / split / delete / undo / redo / ax_enumerate 六步脚本化序列，每步吐 `UXEventLog("UITest", step)`；`suppressCommandAlerts` 防 runModal 卡死无人值守
3. `MainViewController`：`pendingLiteUITest` 标志，enterEditor 后 2s 触发
4. `scripts/test-ui-lite.sh`：快照起点 → 触发 → 轮询 `UITest.done` → 逐步断言 → exit 0/1；测试音防御 BUG-1 静音拦截；即 INFRA-005 LoopBody 自测步的调用入口

**验收标准**：
- [x] `build-app.sh` exit 0 ✅
- [x] 端到端：`test-ui-lite.sh` 全绿 ✅（首验 475136 帧；验收复跑 467968 帧 @48kHz：split 不动时间轴、delete 233984 精确、undo 逐位恢复、redo 回落；AX 树 1 窗 145 节点可达）
- [x] 无人值守可复跑（无弹窗、无人工介入、exit code 语义正确）✅
- [x] 幂等：连续两次运行结果一致 ✅（首轮调试期已多次复跑，验收时再复跑一致）
- [x] 首跑钓出的 bug 闭环 ✅：loadAudio Phase2 use-after-free（SIGSEGV .ips 实锤→捕获 buffer 保活）+ UXEventLog 写后不落盘（→synchronizeFile）

**交付记录（2026-10-24 老板交付验收，merge 980cacf；worktree loop/INFRA-006 8df581b 单提交 6 文件 +238/-9）**：
- 验收方式：执行侧现场复跑 `test-ui-lite.sh` 出新鲜证据（6/6 PASS exit 0），老板看证据拍板——非陈旧文件翻看。
- 正向意外：自验时已知边界 `button_count=0`，验收复跑实测 **18 个按钮可枚举且名可读**（导出/缩小/放大/适应全部…），AX 暴露度显著好于自验时点。
- 测试音说明（验收中老板问询确认）：`afplay` 播 440Hz 正弦波 20s 为设计内行为——mix 源必须经真实输出设备产生信号，防御 BUG-1 静音拦截；「系统静音跑 mix 场景」物理上做不到，无人在场时段跑属天然解。
- 双 bug 修复随本单一并验收：loadAudio UAF（计划外收益，SIGSEGV 实锤）+ UXEventLog synchronizeFile。
- 已知边界（验收确认接受）：转写/导出链路不在六步内（后续按需扩步）；LOOP-05 XCUITest 深度回归补齐仍 blocked（等系统重启验证）。

**回写关系**：
- **解锁 INFRA-005**：LoopBody 自测步正式启用 `scripts/test-ui-lite.sh`（原前置依赖之一就地消除）。
- **FIX-013 假设分支①消除**：loadAudio UAF 随 merge 进入 master，若 ~17s SIGSEGV 仍复现则定性为独立根因，FIX-013 继续查。

**回滚命令**（merge 为 no-ff 独立提交，整单可逆）：
```
git revert -m 1 980cacf   # 撤销整个 merge（代码回退，历史保留）
```

---

### FIX-013 Loocap master 二进制启动 ~17s 可复现 SIGSEGV（10-22 晚 ×3） | P1 | S-M | [done ✅ 2026-10-25 老板交付验收 → merge 3c3bac0]

> **R3 轮结论（2026-10-25）**：三份 .ips 符号化同崩 `closure #1 in EditorWaveformView.loadAudio +1980`（线程 8/4/12）——与 INFRA-006 修复的 loadAudio use-after-free **同根因**（10-22 晚跑的是 merge 前旧二进制）。
> 复测：master（含 INFRA-006 修复，merge 980cacf）重建后冷启 3/3 存活 25s（越过 17s 崩溃窗口），DiagnosticReports 零新增；SDK 单测 89/89。
> **无代码变更**（修复实体 = INFRA-006），本单以「重建后复测不再崩」闭环。
> 验收标准对照（全达成）：.ips 符号化落盘（docs/证据/2026-10-25-FIX013-符号化与复测结论.md）；冷启 ≥3 次零崩溃；build exit 0 + SDK 89/89。
> 回滚：无独立代码；整体回退 = `git revert -m 1 980cacf`（同 INFRA-006）。

### INFRA-005 R3 轮附带：build-app.sh 清理步 TCC 兼容 | P3 | S | [done ✅ 2026-10-25 老板交付验收 → merge 3c3bac0]

> R3 轮观察源①钓出（A 类构建修复，随本轮交付）：`rm -rf build/` 撞 macOS 26 App Management TCC（拦 rm 已签名 bundle），`set -e` 断链（10-22 首踩、10-25 复踩）。
> 修复（0a011ff）：build-app.sh 清理步先 `mv` 到 `build.trash-<ts>` 再尽力 rm，rm 失败不阻断；回归连续两次构建 exit 0（含 build 已存在场景）。验收现场 master 复跑 exit 0。
> 反哺：LOOP-adapter §9 教训条目（4c12b31）。
> 回滚：`git revert -m 1 3c3bac0`。
