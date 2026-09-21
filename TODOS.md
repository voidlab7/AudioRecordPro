# 需求队列（TODOS）— Loop v2 启动池

> 2026-09-20 清空重建。旧 backlog 已归档 `docs/归档/TODOS-archive-20260920.md`，待 loop 协议验证后批量补验收标准再捡回。
> 开发方式唯一：`docs/LOOP.md` 循环协议。状态标记：todo / doing / self-verify / ready-for-review / blocked / done。
> 老板只做三件事：签标准（定义）、拍板（裁决）、看证据（签收）。

---

## 🔥 第一轮：跑通 loop 最小闭环（2 张单）

### LOOP-01 单测盘点：搞清楚每个测试用例解决什么问题 | P0 | 0.5天 | [done] ✅ 2026-09-20 老板签收

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

### LOOP-03 BUG-1 计时器与录制管线脱节修复 | P0 | 1天 | [done] ✅ 2026-09-21 老板签收（运行时验证 6/7/8 待人工补测）

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

---

### LOOP-02 修复 String.localized 分层断裂（务实修） | P0 | 0.5天 | [done] ✅ 2026-09-21 老板签收

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

### LOOP-04 SDK 单测执行卡死（xctest hang） | P0 | 0.5天 | [done] ✅ 2026-09-21 老板签收

> 来源：LOOP-02 自验发现。根因已定位并修复：`String(format:"%@", arguments:[数值])` 把 UInt32/OSStatus 当对象指针解引用 → SIGSEGV。修 3 处（AudioUtils.swift:422、AudioToolboxFileManager.swift:58/124 数值转 String）。结果：`test_sdk.sh` 77/77 全 PASS。

**做什么**：定位测试执行卡死根因（可疑：某用例 RunLoop 等待 / 测试进程初始化时权限或音频设备枚举阻塞），修复到 `test_sdk.sh` 完整跑出 PASS/FAIL 结果。

**不做什么**：不改产品功能代码

**验收标准**：
- [ ] `test_sdk.sh` 完整执行出结果（日志含 `Executed N tests` 或等效统计，不再止于 Build complete）
- [ ] 全部测试 PASS，或失败项逐个判定「测试错/产品错」并记录
- [ ] 无残留 xctest 进程（跑完进程自然退出）
- [ ] 日志落盘 `test_logs/sdk_test_*.log` 完整

### LOOP-05 XCUITest 11 个失败修复（mock 注入失效） | P1 | 1天 | [blocked] ⚠️ AX 授权失效，需人工处理

> 代码部分已完成：mock 进程注入（1001-1006 Chrome/Safari/Music/Zoom/Teams/Slack）+ mock 录制状态机（MainViewController，--ui-testing 参数）。
> 阻塞原因：XCUITest runner 的辅助功能授权失效——11 个测试全部报「Not authorized for performing UI testing actions」（昨晚还能正常查询 AX，今天失效）。
> 解除步骤（人工）：① 系统设置 → 隐私与安全性 → 辅助功能，检查 xcodebuild/XCTest 相关条目并重新授权；② 或重启 Mac 后重跑；③ 解除后说「继续跑 loop」验证 mock 修复效果。

> 来源：LOOP-02 自验发现。UI 测试第一次真跑：19 执行 8 过 11 挂，11 个失败全是「ProcessRow-1001 找不到」（V2.0 重构后 mock 进程注入机制/accessibility 标识失效）+ RecordingFlow 停止后按钮断言。

**做什么**：恢复 App 的测试 mock 注入机制（launch arguments）或更新测试适配 V2.0 视图结构，让 `test-ui.sh` 全绿。

**不做什么**：不改产品功能代码

**验收标准**：
- [ ] `test-ui.sh` 19/19 PASS，或逐项判定「测试已无意义」并删除且记录理由
- [ ] 日志落盘 `test_logs/ui_test_*.log` 完整

---

## 未来池

> 旧 backlog（BUG-2~5、REQ-2.0 系列、V1.2/V1.3）见 `docs/归档/TODOS-archive-20260920.md`。
> 捡回规则：loop 协议验证后（第一轮 2 张单跑通），逐条补验收标准回池，按 P0 > P1 > P2 顺序。
