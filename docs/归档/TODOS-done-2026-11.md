# TODOS done 归档 · 2026-11 起

> 本文件由「验收即归档」规则（2026-10-12 老板定）生成：单子交付验收通过即从 `TODOS.md` 迁入此处，池里只留一行索引。
> 归档正文不再回改（历史事实记录）；回溯入口：本文件 / `git log --grep <单号>`。
> 2026-10 及更早历史：`TODOS-done-2026-10.md`、`TODOS-archive-20260920.md`。

---

### FIX-017 录制中可改源：侧边栏未锁，录制中改选只改 UI 不影响管线 | P1 | S | [done · 2026-11-04 验收]

> 老板 2026-11-04「开工吧」需求审核（仅①锁源）→ CodebuddyBot worktree `loop/FIX-017` → 自验 build 0 / SDK 148/148 → 老板「验收通过」。
> master `32b3562` = merge(FIX-017)（worktree commit `be90171`）。
> 规格：`docs/需求/FIX-017-录制中锁源.md`｜证据：`docs/证据/2026-11-04-FIX017-录制中锁源-交付证据.md`

**做什么**：录音态接通已有 `SidebarView.isRecordingLocked`（preparing/recording/stopping 锁；idle/playing/error 解锁）；不重建 Tap；②③另开单。

**改动**：`MainWindowView.updateRecordingState`（commit `be90171`）。

**验收**：老板 2026-11-04 实机/交付验收通过。

---

### FIX-021 麦克风混录三连缺：mic 不进波形/电平表/无效守卫 + 录音中切麦不生效 + 失效聚合设备可选 | P1 | M | [done · 2026-11-02 验收]

> 来源：老板 2026-10-30 20:21 实录反馈「录制没有声音」（截图：REC 页波形贴中线圆点行、DB 表无动作、计时 15s）。
> **需求审核通过（2026-10-31）**：老板复测仍无声音（截图：选源 QQMusic + 混录开 + AirPods Pro，波形直线，REC 7.8s）并发「这个还是没声音」催修=审核放行。截图新增实锤：**聚合设备泄漏累积**（麦列表躺 #89802 / #81333 两个历史残留，每次崩溃/未清理会话新增一只）。需求台拍板：验收标准 2 的二选一取「**切麦=生效**」（运行时重建注入引擎，非仅提示）。
> 排障定论：**与 FIX-018 无关**（该轮为固定满刻度映射改动，数学上不可能把有信号压成零；本次是峰值回调流里根本没有信号）。

**需求台分析（日志 + 代码双证据，日志 audiorecord_2026-10-30.log 20:21:46–20:22:24）**：

时间线：20:21:46.4 点录制（`开始多音源录制 - 麦克风:false`，此时混录开关未开）→ 20:21:49.1 老板开「同时录入麦克风」→ 注入引擎启动（MacBook Pro 麦克风，unit 首帧 peak=0.016 ≈ 环境底噪，老板戴 AirPods 未对 Mac 说话）→ 20:21:51.7–57.9 老板录音中连切 6 次麦设备（AirPods→默认→AirPods→#376234→MacBook→#60274）→ 20:22:04 停止，守卫按峰值 0.0 判无效删除 → 20:22:24「所选设备失效已回退: CADefaultDeviceAggregate-60274-0」。

三层缺陷：

1. **mic 混入晚于峰值取样（代码 bug，本单主刀）**：`AudioCallbackHandler.swift:68` `calculateAndReportLevel(from: bufferList)` 对**原始系统 buffer** 算峰值/电平，`:71` `writeAudioData` 内部（`:254-283` FIX-007 注入分支）才把 mic 按 40% 混入后写文件。后果：波形（updatePeakLevel）、DB 表（onLevel）、BUG-1 无效录音守卫（maxPeakDuringRecording）**永远只看系统侧**——mic 独响时三者全零，守卫还会把「只有麦克风声音」的正常录音误删（本例实锤：文件 798208 帧被删）。
2. **录音中切麦不生效（FIX-017 同族）**：注入引擎 MicCaptureUnit（AUHAL）启动后不响应设备切换（FEAT-004 已知「installTap 后 AUHAL 拒换设备」），`micDeviceSelected` 6 连点只改 UI 状态与 MicDeviceManager 偏好，跑着的 unit 照旧采启动时设备；UI 无任何「已选设备在本场录音中不生效」提示。
3. **失效聚合设备可选（设备列表卫生）**：历史会话残留聚合设备（#376234 已死、#60274 停止后即失效）出现在麦克风列表可被选中，选中后静默降级（20:22:24 才回退且仅日志）。

**做什么（草案，待需求审核裁剪）**：
1. 峰值/电平取样移到混音之后（或 calculateAndReportLevel 增加混音后 buffer 口径）——波形/DB 表/守卫与用户听到的内容同源；守卫判「无效」前须以写盘内容峰值复核（防误删 mic-only 录音）
2. 录音中麦设备切换：要么运行时重挂（AUHAL 换设备受限则重建 unit，防双开），要么明确提示「本场录音将沿用启动时设备」；与 FIX-017 一并定「锁 vs 提示」口径
3. 麦克风列表过滤失效设备（kAudioDevicePropertyDeviceIsAlive/`isAlive` 探测），选中失效设备时 UI 即时提示并回退

**边缘情况**：mic-only 录音（系统静音+只录麦）是合法场景，守卫不得误杀；聚合设备 #60274 恰为本实例 PID 命名空间产物，列表刷新时序待查（App 自建聚合不应出现在麦列表）。

**验收标准（草案）**：
- [x] 系统静音 + MacBook 麦克风说话：波形实时出条、DB 表动作、录音可保存（不再被守卫误删）——老板 2026-11-02 实机验收通过；SDK 端到端断言 `testLevelSamplingPrefersMixedSamples_FIX021` 固化
- [x] 录音中切麦：生效（拍板口径落地：`restartMicCaptureForDeviceChange`）——老板实机验收通过
- [x] 失效设备不出现在麦列表或选中即提示——过滤 Tap- 聚合 + isAlive；老板实机验收通过
- [x] build 0 / SDK 基线不回退 / lite——build 0 / SDK 111/111（+6）；lite 验收期让路后由老板实机补位通过

**预估**：M（回调链重排 + 守卫复核 + 设备列表探测）｜ **证据**：docs/证据/2026-10-31-FIX021-交付证据.md

**R17 轮交付（2026-10-31，worktree `loop/FIX-021`）**：三因全修——
1. **电平取样同源化**（AudioCallbackHandler）：回调顺序改「先写后取样」；writeAudioData 拆出 `mixMicIfNeeded`，混音结果真实写盘时暂存 `lastMixedSamples`，calculateAndReportLevel 优先消费（一次性清空，无消费者不滞留）；AudioUtils 新增 `calculateAudioLevel(fromSamples:)` 与 AudioBufferList 版口径一致——波形/DB 表/BUG-1 无效守卫看到的即用户听到的，mic-only 录音不再全零、不再被守卫误删
2. **录音中切麦=生效**（CoreAudioProcessTapRecorder + MainViewController + MicDeviceManager）：新增 `restartMicCaptureForDeviceChange()`（停掉在跑 unit→按新偏好重建，未开混录 no-op）；MicDeviceManager.preferredDeviceUID 变更即广播 `onPreferredDeviceChanged`，MainViewController 订阅后录音中重建+状态条提示「麦克风已切换，本次录制即时生效」（i18n en 已补）
3. **设备列表卫生**（MicDeviceManager.listMicrophones）：过滤本 App 自建 Tap 聚合（名字恒 "Tap-<UUID>"，含跨会话泄漏残留——10-31 截图 #89802/#81333 实锤）+ `kAudioDevicePropertyDeviceIsAlive` 探测过滤死设备（查询失败保守放行）

**机器门禁**：build 0（14 条告警全为既有文件行号偏移，零新增）/ SDK 111/111（新增 6 条：混音口径 40%/口径一致性/mic-only 非零/provider 关闭不注入/峰值回调报告混音值/消费后清空）/ lite 真机回归**让路未跑**（老板实例 PID 81333 占用独占资源，验收期补）。⚠️ 已知边界：实时转写旁路仍吃系统侧原始 buffer（mic 人声不进转写），与 FEAT-001 联动另开单。

---

**合入**（master `73d5b3e` = merge `loop/FIX-021` @ `db4aa19`）：
- 代码：AudioCallbackHandler 先写后取样 + lastMixedSamples；CoreAudioProcessTapRecorder 切麦重建；MicDeviceManager 列表卫生 + 偏好广播；MainViewController 订阅提示；AudioUtils/Tests +6
- 证据：`docs/证据/2026-10-31-FIX021-交付证据.md`
- 战报：`docs/LoopBuddy/R17-FIX021-2026-10-31-战报.md`（与 UI-039 同日 R17 文件名撞名，合入时分立保留）
- 老板 2026-11-02 22:46 Asia/Shanghai 口头「验收通过」。

---

### UI-042 拖动窗口边框时轨道与时间标尺不重排（时间-像素映射锁定） | P2 | S | [done · 2026-11-01 验收]

> 来源：老板 2026-10-31「需求入池，拖动边框的时候，轨道不用动。就是 轨道的标尺不用动。」+ 10-31「开始开发」=需求审核通过。
> 现状核实（10-31）：主窗口 `.resizable`（AppDelegate.swift:298），拖边框→宽度变化→①波形按新宽度重排（横向拉伸）②TimeRulerView 每次重绘按 `80px/pps` 自适应重算步长（TimeRulerView.swift:92-94 chooseNiceStep）→ 档位跳变（5s↔10s↔15s）。

**做什么**：锁定时间-像素映射（pixelsPerSecond 恒定），宽度变化只改变可见时间范围；波形不拉伸、标尺档位不跳变；显式缩放入口（Cmd 滚轮/捏合/fitAll/工具栏）行为不变。

**不做什么**：不改标尺/播放头 overlay 绘制（走同一条 viewport 同步链自动稳定）；不改显式缩放路径；不碰录制态实时条带。

**边缘情况**：拉宽越过全音频=全显+右端留白（不强行重铺）；极端窄窗可见时长触底 0.05s；起点越尾 clamp 到 totalDuration-duration；留白态 zoomLevel<1 的 UI 显示层钳制（控制器侧）。

**实现**（loop/UI-042，master 合并 807467d）：
- Kit 纯函数 `ViewportResizeLock.resolve`（锁定 pps/锚左缘保守档/右端 clamp/留白态/触底）+ 单测 9 例
- `EditorWaveformView.applyResizeLock(newWidth:)`（宽度基准 defer 无条件记录）+ `layout()` override 接线；zoomLevel 不变式同步（留白态可 <1）
- 控制器显示层钳制（zoomControls.zoomLevel=max(1,·)、visibleRatio 钳 1）
- lite 第 15 步 `resize_lock`（steps 14→15）：**真实窗口 setFrame 驱动**（完整 Auto Layout → layout() 全真实路径），断言 pps 恒定+锚左缘+niceStep 档位稳定+`header_frozen` 冻结首列+抗干扰重试

**验收期演进**（老板实机验收 3 轮反馈，全部收敛在验收轮内）：
1. R2 剪映轨道头截图 →「不用锁（不要锁定按钮功能），就是轨道头都不动，像是文档的冻结首行」→ 语义已成立（88px 常量约束+全源码零比例约束+虚拟滚动），升级为机器实证（header_frozen 断言，行内波形左缘两轮 resize 恒 88）
2. R3「滚动条超过头部了」→ 横向滚动条 leading 跳过 headerWidth(88) 与轨道内容区左缘对齐
3. R4 剪映参考图「有一个整体的布局块」→ TrackContainerView 加轨道头列整体背景块（标尺左段+带头+行间空隙连续底色，右缘 0.5px 分隔线贯穿全高，z 序最底）

**验收标准**：
- [x] 拖动窗口左/右缘：波形像素形态与标尺刻度间距保持稳定（刻度档位无 5s↔10s 跳变，波形不横向拉伸）——lite resize_lock pps 三轮精确恒等（342.92×3）+ step_stable + Kit 单测 9 例
- [x] 拖动中与松手后一致；多次 resize 后 fitAll / Cmd 缩放仍正常——纯函数即时收敛；锚点三轮恒等（0.993×3）；显式缩放路径零改动
- [x] `build-app.sh` exit 0；SDK 单测基线不回退；lite PASS——build 多轮 exit 0 / SDK 142/142（基线 133+9）/ lite 15/15（attempt=1 一次过）+ space_record + UITest2

**预估**：S ｜ **证据**：`docs/证据/2026-10-31-UI042-resize映射锁定-硬验证.md`（含 R2 轮记录）、`docs/LoopBuddy/R18-2026-10-31-战报.md`

**排障记录**（R1 lastLaidOutWidth 过期基准 = 3/7 分数形状定位；R2 三轮皆测试数学错位：redo 删除态 totalDuration 错位一半 / f0 基准越尾 clamp，App 实现零改动即正确——方法论：lite 断言期望值必须取被测视图实时状态）。

**实机验收项**：老板 10-31/11-01 实机拖边框+滚动条+布局块逐项看毕，「验收通过」（11-01）。合并态回归 build 0 / SDK 142/142；合并态 lite 待 App 空闲补跑（worktree 终版已 15/15）。

---

### REL-006 商店对齐：砍 ffmpeg 导出链（导出面收敛系统原生格式） | P1 | M | [done · 2026-11-04 验收]

> 来源：老板 2026-10-30 会话拍板「导出可以砍掉，不要 ffmpeg 加入需求」。
> 背景：2026-10-30 App Store 对齐审计（逆向对标已上架基准 Audio Capture Pro）：ACP 零内嵌二进制、零三方编解码库，导出面仅 M4A/WAV（系统原生）；Loocap `Contents/Resources/ffmpeg`（77MB 静态二进制，ExportService 探测链 Bundle→homebrew）是三重问题叠加——①「Resources 内可执行文件」常见拒审项 ②静态链接 GPL 组件与 App Store 分发条款冲突 ③体积负担。审计同时确认其余产物面已全部对齐——**唯一硬伤即 ffmpeg**。

**做什么**：
1. `ExportService.swift` 移除 ffmpeg 转码路径（MP3/FLAC/OGG 三格式），导出面收敛：**WAV + M4A**（系统原生）；FLAC 是否以 CoreAudio 原生编码保留由需求审核拍板
2. `ExportCardWindowController` 导出选项 UI 同步收敛
3. `build-app.sh` 移除 ffmpeg 探测与拷贝段（bundle −77MB）
4. i18n 字符串清理：en base / zh-Hans lproj 中 MP3/OGG/ffmpeg 相关条目

**不做什么**：不做「系统/ffmpeg 双后端抽象」（老板 2026-10-30 明确否掉）；不动录制/转写/编辑链路。

**验收标准**（全部实测达成，见证据文档）：
- [x] 全仓 `grep -ri ffmpeg`（源码+脚本+资源）零命中；`find build/Loocap.app -type f -perm +111` 仅主二进制
- [x] 导出 WAV / M4A 实测出文件，`afinfo` 校验格式与时长正确（老板实机四格式验收通过）
- [x] bundle 体积记录（5.6M，无内嵌二进制）
- [x] `build-app.sh` exit 0；SDK 单测基线不回退（148/148）；lite 全 PASS

**交付与验收记录**（2026-11-04）：
- 需求审核：老板「这个需求审核通过，可以开发了」
- 交付：loop/REL-006 49b4b89（7 文件 +55/−177）；FLAC 决策=验证可行即保留——CoreAudio 原生编码（'flac' 四字符码，26 SDK Swift 层缺 `kAudioFormatFlac` 常量自建；finalize 在 AVAudioFile deinit，写块独立作用域），比 ACP 多一项无损格式
- 附带修正：菜单「导出 MP3」→「导出」（行为一直是开导出卡片）；主仓残留 80MB 二进制 + 17MB 源码 7z 已 mv 废纸篓
- 验收：老板实机导出四格式 afinfo 校验通过，「验收通过」；master 51ca9c9 = merge loop/REL-006；worktree 清树
- 证据：`docs/证据/2026-11-04-REL006-砍外部转码器导出链-交付证据.md`

---

### UI-043 麦克风选择器改设备勾选列表：开关/分组头全退役，勾选即开关（R1 去伪行 → R2 checkbox 列表 → R3 去开关 → R4 去分组头） | P2 | S | [done · 2026-11-07 验收]

> 来源：老板 2026-10-31 发侧边栏截图（「同时录入麦克风」展开态：✓跟随系统默认·MacBook Pro 麦克风 / MacBook Pro 麦克风 / 聚合设备 #1405）：「打开的时候直接看到几个麦克风输入设备，默认勾选，不用单独起一行系统默认」。
> 现状（10-31 核实）：`SidebarView.refreshMicDeviceList()` 展开态恒注入第 0 项伪行「跟随系统默认」+ 分隔线；列表含失效聚合设备（FIX-021 另单处理）。
> 语义边界（防误伤，保留有效）：`preferredDeviceUID=nil` 在录音链是动态跟随（`MicDeviceManager.resolvedPreferredDevice()` nil→系统默认，FEAT-004R2 链路），不把系统默认 UID 悄悄写死。

**演进链（11-05 R1 → 11-07 验收期三轮迭代）**：
- **R1（11-05，30e748d）**：去伪行/分隔；勾选/折叠名投影系统默认（nil 不写 UD）；拍板 a（再点已勾选回跟随）；lite 让路。
- **R2（11-07 参考图）**：老板「改成直接探测有多少个麦克风，直接勾选的形式。一个列表搞定」——header 改「设备」分组标题（en Devices）、默认展开、设备行改自绘 checkbox（`MicCheckIndicator`：primary 填充+路径白勾）+ 圆底麦克风图标。
- **R3（11-07 实机）**：老板「只要下面这一个，连上面那个开关都可以不要……省了一个交互逻辑」——「同时录入麦克风」开关行整个退役（`IndustrialMicrophoneRowView` 类删除），设备列表常显，**勾选即开关**：点未勾行=开启混录+钉选该设备（写 preferredDeviceUID）；点已勾行=取消勾选=关闭混录（`selectedIndex=-1` 合法态）。R1 拍板 a 随开关行模型退役；「跟随」收窄为内部投影（micMixEnabled=true 且 preferred=nil 勾落系统默认行，不写 UD）。selftest 钩子 `setMicrophoneMixEnabled` 签名语义保持（lite `mix` 位零改动，FIX-007 录音中切麦链路不受影响）。
- **R4（11-07 实机）**：老板「下拉箭头都可以，不要直接就是选项」——「设备 Devices + ▼」分组头与折叠交互整个退役，MICROPHONE 段标题下**直接平铺设备选项**；异常/空态提示（失效警告/「未检测到」）改列表首行 statusLabel（正常态隐藏不占位）；孤儿 L10n key「设备」清理。

**验收标准**（全部达成）：
- [x] 「MICROPHONE」标题下直接平铺设备行（勾选框+圆底图标+设备名），无开关行/分组头/箭头，列表=实际探测数
- [x] 点未勾行勾上并混录（轨道板出「麦克风」轨道）；再点已勾行取消勾混录关
- [x] 勾选持久化；失效警告/空态提示保持
- [x] `build-app.sh` exit 0；SDK 基线不回退；lite PASS

**交付与验收记录（2026-11-07）**：
- 交付：loop/UI-043 终版 `dfd350e`（R2+R3 7468496 + R4 dfd350e，SidebarView/MainViewController/en/zh-Hans L10n + 证据 5 文件 +387/−435）
- 三关卡（R4）：build 0 / SDK 148/148 / lite 15/15 + UITest2 PASS（mix 勾选→混录落盘全链真实生效）
- 验收：老板实机看 R4 形态「好的，审核通过」；master `ad4e9c3` = merge loop/UI-043；合并态回归 build 12（@ad4e9c3）/ SDK 148/148 / lite PASS
- 证据：`docs/证据/2026-11-07-UI043-R2R3-勾选即开关-交付证据.md`、`docs/证据/2026-11-05-UI043-麦选择器去跟随伪行-交付证据.md`
- 关联：`IndustrialSwitchView` 通用控件保留（IndustrialControls.swift，本期零使用方）；诊断文案同步「请在侧边栏勾选一个麦克风设备」

---

### UI-044 编辑页配色对齐剪映参考图（菜单/轨道头/轨道颜色/电平背景/波纹颜色，除电平波纹形态外） | P2 | S | [done · 2026-11-07 验收]

> 来源：老板 2026-11-04 发剪映风格参考截图（ardot file 741299005174936「剪映风格音频编辑」参考图）：「这里的设计对齐设计稿，除了电平波纹。主要是：菜单，轨道头，轨道颜色，电平背景颜色，波纹颜色。加入需求 Loocap」。设计稿五项颜色已按参考图对齐，波形形状/音量线交互未动。

**颜色映射**（设计稿旧值 → 参考图对齐值）：

| 部位 | 旧值 | 新值 |
| --- | --- | --- |
| 菜单/编辑工具栏底色 | #15171B（描边 #24272C） | #222628（描边 #2E3234） |
| 工具栏图标 + 组分隔线 | #9AA0A6（分隔线 #2E3238） | #C8CCCE（分隔线 #4A4F52） |
| 轨道头（含轨道头列背景） | #16181C（描边 #24272C） | #191C1E（描边 #2A2E30） |
| 轨道颜色（轨道带/时间轴底） | 轨道带 #172629、时间轴 #0F1115 | 统一 #1A1D1F（描边 #2A2E30） |
| 电平背景（clip 底色） | #124045（描边 #409991） | #2E5E59（细描边 #3D6B66） |
| 波纹颜色 | 波形 #45A8A8 + 音量基准线 #C0F2ED@55% | 波形 #50AEA5 + 音量基准线 #BFDAD6@55% |

**R1 交付（2026-11-04，老板「开工」）**：worktree loop/UI-044 49754ce（代码）+ 376ae39（战报/证据），7 文件 +76/−26——token 波形 `#50AEA5/#65C4BA`（明度分层保留）；工具栏/轨道头/轨道带/标尺全对齐；**clip 常显青绿底 #2E5E59 + 细描边**（drawClipSurface 新层）；音量线常态 #BFDAD6@55%（拖拽橙/过载红保留）。波形形态/选中/过载/静音语义色/录制态竖条零改动。三关卡 build 0 / SDK 148/148 / lite 15+2。战报 docs/LoopBuddy/R18-UI044-2026-11-04-战报.md。

**R2 微调（11-04 实机反馈）**：老板「背景色再淡一点」→ clip 底色改半透明 #2E5E59@0.6（c0f4ac1）。

**交付与验收记录（2026-11-07）**：
- 验收：老板实机看配色「颜色OK」（同场提波形归一化需求 → 并入 UI-045 R2，见 FIX-022 池行）
- master `7651bf3` = merge loop/UI-044；合并态回归 build 13（@7651bf3）/ SDK 148/148 / lite PASS
- 证据：`docs/证据/2026-11-04-UI044-编辑页配色对齐-交付证据.md`、`docs/LoopBuddy/R18-UI044-2026-11-04-战报.md`
- 关联：UI-025（波纹配色前作）、UI-026（工具栏剪映风）、UI-029/FIX-019（clip 描边）、UI-034/UI-036（过载红）
