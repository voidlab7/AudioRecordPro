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
