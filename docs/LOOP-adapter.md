# Loocap（audio_record_mac）· Loop 适配层

> 内核：loop-engine 技能（正本 `AIAgent/SKILL仓库/工程与运维/loop-engine/SKILL.md`，唯一一份，改协议只改那里）。本文件只写**本工程与内核不同的地方**；与内核冲突时以本文件为准，但不得放宽四条铁律。
> 接入日期：2026-10-13（由试点期完整版 docs/LOOP.md 瘦身回接入形态）

## 1. 路径

| 项 | 路径 |
|---|---|
| 需求池 | `TODOS.md` |
| 归档目录 | `docs/归档/`（`TODOS-done-YYYY-MM.md`；`TODOS-archive-20260920.md` 为更早 backlog，捡回规则见池头） |
| 规格文档 | `docs/需求/<单号>-*.md` |
| 证据落盘 | `docs/证据/`、`test_logs/` |

## 2. 构建（成功判据）

| 命令 | 判据 |
|---|---|
| `bash build-app.sh` | exit 0 + 编译零错误；产物 `build/Loocap.app` |
| `xcodegen generate --spec project.yml` | 仅在 project.yml 变更或 worktree 首次构建时；pbxproj 是生成物 |

## 3. 测试 / 静态检查

| 命令 | 判据 / 基线 | 豁免 |
|---|---|---|
| `bash scripts/test_sdk.sh` | 89/89 PASS（基线 2026-10-25）。**2026-10-25 起系统层 `sandbox_apply: Operation not permitted`（任何目录、沙箱内外均同，与 LOOP-05 同族）→ 统一用 `cd AudioRecordKit && swift test --disable-sandbox` 直跑** | |
| selftest（App 内置触发器） | 按单声明（如 `N mix` 开麦混录 / `N mixmid` 录音中切麦）；波形自验：容器 tmp 放 `fix008_trigger` 文件后冷启（见 WaveformView 钩子） | |
| ~~`scripts/test-snapshot.sh`~~ | **已停用**（2026-10-13 LOOP-05：SnapshotTesting 包引擎沙箱死点，包已摘除；源码保留 `AudioRecordMacSnapshotTests/`） | 整层豁免 |
| ~~`scripts/test-ui.sh`（XCUITest）~~ | **blocked**（LOOP-05：runner bootstrap 死点，等外部终端验证） | 整层豁免，禁试 |

## 4. 硬验证（怎么证明它真能用）

| 场景 | 手段 |
|---|---|
| 音频落盘 | `afinfo` 字段 + 逐秒峰值解析（Python wave 不认 float32 wav，先 `afconvert -f WAVE -d LEI16` 再析） |
| 录音文件加密产物 | `/tmp/arlock_decrypt/arlock_decrypt` 解密后验（注意它是目录，二进制在其中） |
| selftest 链路打点 | 日志 grep 关键行（如「麦克风首帧 peak=」） |
| 窗口/截图 | Quartz onscreen 列举 + `screencapture -l`（TCC 辅助功能缺，AX/System Events 不可用，不得用 AX 当截图验收） |
| **App 存活/冒烟**（R4 反哺） | **只认 App 自身日志尾部时间戳推进**（`~/Library/Containers/com.microlab.loocap/.../Logs/audiorecord_*.log`）；**沙箱内 pgrep/ps 判进程不可信**（2026-10-26 R4 实证：App 活着写日志，pgrep -x 两连 DEAD 假信号） |

## 5. 执行者

- 角色：**Tab**（录音 App 专属 PM+测试+研发，`roles/Tab/AGENT.md`，含其铁律）

## 6. 环境约束

- 平台：macOS 26.2 / Xcode 26.x / swiftc 直编（build-app.sh 不走 pbxproj）
- **WorkBuddy 执行容器内不可用**（2026-10-13 实证，禁试）：`xcodebuild test`（包解析与 runner 双死点）、`log show/stream`（Cannot run while sandboxed）、`ps`、`crontab`、`launchctl submit`、osascript 发 Apple Events；`dangerouslyDisableSandbox` ≠ 无沙箱
- **沙箱内 pgrep/log show 同样不可信**（2026-10-26 R4 实证）：pgrep 对 open 拉起的 App 返回空（假 DEAD）、log show 报「did not refer to a valid log archive」——进程存活判定见 §4 App 存活行
- **并发轮约束**（2026-10-26 R4 实证，机制化方案待 INFRA-008 审）：同一时刻只允许一个 LoopBuddy 轮；后到会话发现他轮痕迹（目标单 worktree 已占用/他轮构建或单测进程在跑）应**让路换下一张已审核单**，不得同单双执行；lite/selftest 拉起的 App 同 bundle id，两轮同时跑观察步会互踩独占资源
- **并发停摆接手**（2026-10-26 R5 实证）：发现他轮实现已落盘（worktree 有提交）但停在交付步前（无进程、工作区干净、池状态未更新）时，接手动作=**独立复测后交付**——不重写已落盘实现、不采信对方自述的测试数字（上下文分离），复测全绿才置 rfr；证据文档若已在 worktree，随 merge 进 master
- 沙箱外拉起通道（Terminal/launchctl/cron/LaunchAgent）全会话内被拒 → 需真实终端的验证一律置 blocked 留老板
- 防休眠：班次内任务短，无需专门处理

## 7. 禁区（命中即 blocked）

1. `docs/归档/` 内历史单正文不回改（历史事实记录）
2. 禁 `git push --force` / `git reset --hard`（Git 安全铁律）
3. `xcodebuild test` 链路禁试（见 §6）
4. 当天已有完整快照的数据采集链路禁手动重跑（业界教训，见 MicroLab 同族）

## 8. Git 约定

- worktree 目录 / 分支前缀：`.worktrees/<单号>` + `loop/<单号>`（引擎默认，未改）
- 主分支名：`master`
- 提交格式：`type(<单号>): ...`（type = feat/fix/ui/infra/chore/revert）
- 需求池入库：是（TODOS.md 随 git 跟踪；worktree 内禁改，见引擎 §八.2）
- **池状态列书写纪律**（R6 反哺）：速览表「状态」列必须用规范六态词或其规范变体（`todo` / `doing` / `self-verify` / `rfr · 待验收` / `blocked` / `done ✅` / `待需求审核` / `已审核`）——`health.py norm_status` 按 startswith 匹配，复合前缀（如 `todo · 待需求审核`）会漏统计（误报「全卡审核关卡」）；需两段信息时写「`todo`（待需求审核）」圆括号补充而非斜杠拼前缀
- push 由老板确认
- 独占资源：selftest 拉起的 App 实例同 bundle id（com.microlab.loocap），多班次并行须错峰（现班次 10:30/14:30 串行，天然错峰）

## 9. 本工程的历史教训（通用教训见内核 references/反面案例.md）

- 2026-10-11：当天 6 张单全部堆在工作树未提交，事后补拆 4 个提交——催生 Git 纪律与 worktree 隔离
- **沙箱 App 取证铁律（2026-10-13 FIX-008 实证）**：Loocap 是 App Sandbox 应用——①直启二进制必 SIGTRAP，只能 `open` 拉起；②WorkBuddy 会话内 `open --args` / `open --env` **双双不透传**；③App 写绝对 `/tmp` 被沙箱拒绝或容器化，落盘一律用 `NSTemporaryDirectory()`（= 宿主 `~/Library/Containers/com.microlab.loocap/Data/tmp/`，宿主可读写）；④TCC 辅助功能表为空 → 合成键盘/点击（CGEventPost/AX）全失效，UI 交互驱动只能走「文件触发钩子 + 冷启」模式
- FIX-006：报障场景没复现就定性 = 坑（曾误定性「场景 B」返工一轮）；先复现再定性
- BUG-1 遗留：录制器层修复要查三处同构接线（MicrophoneRecorder / CoreAudioProcessTapRecorder / MixedAudioRecorder），当年只改两处漏一处
- UI-014：速度/观感类主观需求，先做最保守档位试探，不一步到位
- **macOS 26 App Management TCC 拦 rm 已签名 bundle（2026-10-25 R3 轮实证）**：`rm -rf build/` 遇已签名 Loocap.app 报 Operation not permitted（沙箱内外一致），`set -e` 下直接断链；`mv` 不在其列。构建/清理脚本一律 **mv 优先、rm 兜底**（build-app.sh 已修，loop/INFRA-005-r3 0a011ff）；残留 `build.trash-*` 无害
- FEAT-004：绑定 API 时序坑（installTap 后 AUHAL 拒换设备）与 HALOutput 回调配方（SetInputCallback 而非 SetRenderCallback）——改动音频引擎前先查 `docs/需求/FEAT-004*` 实验记录
