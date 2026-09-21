# 需求队列（TODOS）

> 按开发优先级排列，当前聚焦 V2.0 插队需求  
> ⚠️ 2026-06-28 校准：V1.1 全部 6 项已代码完成，从待办移除。REQ-2.0-05 也已实现。
> 🔄 2026-09-20 起启用开发循环协议：`docs/LOOP.md`——每条单带验收标准、做完必自验、问题必回池。状态标记：todo / doing / self-verify / ready-for-review / blocked / done。

---

## 🐛 Bug 追踪（2026-09-17 E2E 测试发现）

- [todo] **BUG-1 计时器与录制管线脱节（P0）**：UI 显示「录制中」+ 计时器走动（实测走了 ~7 分钟），但录制管线实际未启动（日志 00:36:47–00:45:14 之间无任何 `startMultiSourceRecording` 记录）。00:45:14.483 管线才真正启动，0.76s 后停止 → 产出 **0 秒文件**，且未被拦截走完加密管线，编辑器加载报「无法分配音频缓冲区」（EditorViewController.swift:857）。日志证据：`沙盒 Documents/AudioRecordings/Logs/audiorecord_2026-09-17.log` 行 53921–77747。修复方向：① 录制态以 recorder 启动回调为准，禁止 0.3s 定时器假装进入 recording（MainViewController.swift:248-250）；② 停止按钮无条件可达（不受 `guard isRecording` 拦截）；③ 0 秒/静音录音落盘前拦截；④ 编辑器对 0 buffer 容错。**复现路径待 Tab 定位**（怀疑与权限检查回调时机有关，MainViewController.swift:215-251）
  > **验收标准（草案，待老板签字后开工）**：
  > - [ ] 构建：`build-app.sh` exit 0，编译零错误
  > - [ ] 代码：录制态切换由 recorder 启动回调驱动，删除 0.3s 定时器假装进入 recording 的逻辑（MainViewController.swift:248-250）
  > - [ ] 代码：停止按钮不受 `isRecording` guard 拦截，任何状态可达
  > - [ ] 落盘：0 秒/静音录音在落盘前被拦截（沙盒目录无新文件断言）
  > - [ ] 编辑器：加载 0 buffer 文件不再报「无法分配音频缓冲区」
  > - [ ] E2E：复现原 BUG-1 路径（权限检查延迟场景）→ UI 不显示「录制中」、计时器不走
  > - [ ] 回归：TC-001 主链路（QQMusic 录制→导出 WAV）仍 PASS
  > - [ ] 证据：新日志中录制态切换与 `startMultiSourceRecording` 时间戳一致
- [ ] **BUG-2 右侧电平表不跟随视图切换（交互，P2）**：录制/文件/编辑器视图来回切换时，右侧区域没有跟随当前进程/上下文刷新展示。待 Tab 出交互方案后修复
- [ ] **BUG-3 未录制时状态栏显示「录制中」（P3 文案）**：初始态应为「● 准备录制」，仅切换标签页就变成「●● 录制中 48kHz」但计时器 00:00.00。纯文案层，updateRecordingState 状态映射问题
- [ ] **BUG-4 录制时间线偏差 ~21s（P2，2026-09-19 TC-001 复测发现）**：日志 ProcessTap startRecording(19:36:19)→stopRecording(19:38:33) 全程 ≈2:14，但导出 WAV 实际时长 112.576s≈1:52.6（与 UI 计时 01:52.57 一致）。怀疑 Tap/AggregateDevice 建立完成→首帧写入存在启动延迟，UI 计时从就绪起算。修复方向：startRecording 成功回调打点 vs 首帧时间戳，量化延迟来源；文件时长断言以此校准。证据：`audiorecord_2026-09-19.log` + `~/Desktop/QQMusic_20260919_193833.wav`(afinfo)
- [ ] **BUG-5 QQMusic 后台窗口暂停按钮点击不生效（P3 测试环境侧）**：computer-use task 面点击 QQMusic 播放按钮正常，点暂停按钮两次无效（图标不变、进度推进），疑 QQMusic 自绘控件热区偏移。影响依赖 QQMusic 可控暂停的用例（TC-005 录制中途退出源 App 的容错），届时先排查；不影响 TC-001 主链路

## 🔥 当前聚焦：V2.0 UI 信息架构修正（插队 P0）

- [ ] REQ-2.0-02 启动默认录制准备态 UI 重构 | P0 | 1天 | [需求文档](docs/需求/REQ-2.0-02.md)
- [ ] REQ-2.0-03 剪映式虚拟时间线音频轨道波形展示 | P0 | 2-3天 | [需求文档](docs/需求/REQ-2.0-03.md)
- [ ] REQ-2.0-04 LevelMeterCard 电平表卡片 UI 优化 | P1 | 1天 | [需求文档](docs/需求/REQ-2.0-04.md)
- [ ] REQ-2.0-06 多应用同时录音 + 多轨道显示 | P0 | 8天 | [需求文档](docs/需求/REQ-2.0-06.md)

## V1.0 收尾

- [ ] REQ-1.0-13 App Store 提交准备 | P0 | 1天 | [需求文档](docs/需求/REQ-1.0-13.md)

## ✅ V1.1 轻编辑（已全部完成）

- [x] REQ-1.1-01 编辑器 UI 框架
- [x] REQ-1.1-02 裁剪首尾
- [x] REQ-1.1-03 静音裁剪
- [x] REQ-1.1-04 音量标准化
- [x] REQ-1.1-05 淡入淡出
- [x] REQ-1.1-06 撤销/重做系统

## V1.2 格式转换 + 导入导出

> 📌 **2026-09-17 技术决议（ffmpeg 路线）**：淘汰现有 80MB GPL CLI 二进制（evermeet.cx 8.1.2，License 与 MAS 冲突、超标 4 倍），改集 **LGPL 裁剪静态库**（libavcodec/avformat/swresample + lame/vorbis/flac/opus，砍 GPL 组件与网络模块，预估 8-15MB）。MP3 已走 Apple 编码器不依赖 ffmpeg；**OGG 保留**（唯一真依赖项）；编辑器 DSP 线（裁剪/EQ/淡入淡出/实时监听）不碰 ffmpeg，继续 vDSP/AudioUnit。待写 ADR 落 `docs/决策/`。

- [ ] REQ-1.2-01 FFmpeg 静态库集成 | P0 | 2.5天 | **方案已升级为 LGPL 裁剪静态库**（编译裁剪 1天 + Swift 封装 1天 + 回归 0.5天），[需求文档](docs/需求/REQ-1.2-01.md)
- [ ] REQ-1.2-02 格式转换核心 | P0 | 2天 | 实测完成度约 70%：六格式全通（MP3 走 Apple 编码器），**缺参数配置**，[需求文档](docs/需求/REQ-1.2-02.md)
- [ ] REQ-1.2-03 音频导入 | P0 | 1天 | 任意格式→内部编码，依赖 1.2-01 新静态库，[需求文档](docs/需求/REQ-1.2-03.md)
- [ ] REQ-1.2-04 批量转换 | P1 | 1.5天 | [需求文档](docs/需求/REQ-1.2-04.md)
- [ ] REQ-1.2-05 导入导出异常处理 | P1 | 0.5天 | [需求文档](docs/需求/REQ-1.2-05.md)
- [ ] REQ-1.2-06 导出参数配置（质量预设） | P1 | 1天 | 低/中/高/无损四档预设（剪映式，不暴露原始比特率/采样率参数）；顺带解除 M4A 写死 128kbps（ExportService.swift:145）
- [ ] REQ-1.2-07 响度归一化 loudnorm | P2 | 1天 | 用 ffmpeg loudnorm（EBU R128）升级现有 peak/rms 音量标准化（REQ-1.1-04）

## V1.3 付费 + 商业化

- [ ] REQ-1.3-01 StoreKit 2 集成 | P0 | 2.5天 | [需求文档](docs/需求/REQ-1.3-01.md)
- [ ] REQ-1.3-02 免费版限制逻辑 | P0 | 1.5天 | [需求文档](docs/需求/REQ-1.3-02.md)
- [ ] REQ-1.3-03 付费墙 UI | P0 | 1.5天 | [需求文档](docs/需求/REQ-1.3-03.md)
- [ ] REQ-1.3-04 恢复购买 + 过期降级 | P0 | 1天 | [需求文档](docs/需求/REQ-1.3-04.md)
- [ ] REQ-1.3-05 定价配置 | P1 | 含在1.3-01 | [需求文档](docs/需求/REQ-1.3-05.md)
- [ ] REQ-1.3-06 购买异常处理 | P1 | 含在1.3-01 | [需求文档](docs/需求/REQ-1.3-06.md)

---

## ✅ 已完成

- [x] REQ-2.0-01 轨道+轨道板模式 UI 重构（录编一体化）
- [x] REQ-2.0-05 录制完成后自动进入编辑器（已实现在 handleRecordingComplete → enterEditor）
- [x] V1.1 全部 6 项需求（编辑器完整实现）
- [x] [BUG] 初始化时波形区域显示红白相间虚线（WaveformView.swift, LevelMeterView.swift）
