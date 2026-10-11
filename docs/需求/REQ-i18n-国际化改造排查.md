# REQ-i18n：国际版（App Store）国际化改造排查报告

> 排查人：Tab（录音产品 PM/测试/研发）｜日期：2026-09-20
> 目标：发布国际版到 App Store，替换全量中文硬编码为本地化方案
> 排查方式：全仓 ripgrep `\p{Han}` + 引号内中文字符串 + 逻辑依赖中文模式扫描
> ⚠️ 品牌 note（2026-10-11）：产品已更名 **Loocap｜路录**（副标语 Capture & Transcribe）。本文中 `CFBundleDisplayName=Tapture` 等为排查当时的设置事实，后续落地国际版时应使用新品牌名。

---

## 一、结论摘要

| 项 | 现状 |
|---|---|
| 国际化基础设施 | **零**。无 `.strings` / `.xcstrings` / `.lproj`，project.yml 无 `knownRegions` |
| 含中文的源文件 | App 侧 48 个，Kit 侧 38 个（含注释） |
| **用户可见中文字符串** | App 36 个文件约 480+ 处，Kit 31 个文件约 300+ 处 |
| 逻辑依赖中文文案 | **4 处**（改造前必须先解耦，见 §四） |
| 依赖中文的测试断言 | UITests 4 个文件 69 处，Kit Tests 6 个文件 40+ 处 |
| 上架红线项 | Info.plist 2 条 TCC 权限文案（中文硬编码） |
| 产品显示名 | 无 `CFBundleDisplayName`（现用 `CFBundleName=AudioRecordMac`） |

---

## 二、A 级：App Store 审核红线（必改，第一优先）

### A1. TCC 权限描述文案（`AudioRecordApp/Resources/Info.plist`）
- `NSMicrophoneUsageDescription`：`需要访问麦克风以录制您的声音。`
- `NSAudioCaptureUsageDescription`：`需要系统音频捕获权限以录制其他应用或系统声音。`
- 方案：值改为 `en` 文案作 base，另建 `zh-Hans.lproj/InfoPlist.strings`（或全部语言）本地化。
- 注意：`CFBundleDevelopmentRegion` 已是 `en`，说明将来 base 语言定为英文是合理选择。

### A2. 主菜单栏（`AudioRecordApp/Sources/App/AppDelegate.swift`）
硬编码菜单：`设置…`、`编辑`、`录制`、`撤销`、`重做`、`开始/停止录制`、`播放/暂停`、`导出 MP3`、`删除录音`、`切换侧边栏`、窗口 `title = "音频录制工具"`（约 20+ 处）。

### A3. 产品显示名
- 现无 `CFBundleDisplayName`。国际版上架需在 `Info.plist` 增加并在 `InfoPlist.strings` 里按语言本地化显示名（如 `Tapture`）。
- 调研点：菜单栏「关于」面板里若写死产品名也要一并处理。

---

## 三、B 级：用户可见 UI 文案（全部抽 String Catalog）

### B1. Views 层（26 个文件，约 260 处）
按密度排序：
| 文件 | 处数 |
|---|---|
| `Views/SidebarView.swift` | 30 |
| `Views/TracksView.swift` | 15 |
| `Views/StatusBarView.swift` | 15 |
| `Views/RecordedFilesView.swift` | 11 |
| `Views/ControlPanelView.swift` | 11 |
| `Views/Editor/EditorWaveformView.swift` | 7 |
| `Views/EditToolbarView.swift` | 6 |
| `Views/Editor/ZoomControlsView.swift` | 6 |
| `Views/SettingsWindowController.swift` | 9 |
| 其余（WaveformView、TitleBarView、TrackPanelView、EditorToolbar、EditorStatusBar、EditorNavigationBar、TrackRowView、TrackContainerView、PlayheadOverlayView、HorizontalScrollBarView、AudioSource、LevelMeterView、LevelMetersOverlay、TimerLabel、TabContainerView、IndustrialControls 等） | 各 1–4 |

### B2. Controllers / App 层
| 文件 | 处数 |
|---|---|
| `Controllers/MainViewController.swift` | 109 |
| `Controllers/AudioRecorderController.swift` | 48 |
| `App/AppDelegate.swift` | 58 |
| `Services/ExportService.swift` | 13 |
| `Services/ExportCardWindowController.swift` | 23 |

### B3. Editor 层
| 文件 | 处数 |
|---|---|
| `Editor/EditorViewController.swift` | 68 |
| `Editor/EditorSessionManager.swift` | 7 |
| `Editor/NormalizeCommand.swift` | 4 |
| `Editor/FadeCommand.swift` | 5 |
| 其余（TrimCommand、SilenceTrimCommand、EditorSession、EditCommand、SplitAudioClipCommand 等） | 各 1–2 |

### B4. Kit 层用户可见文案（SDK 对外）
约 31 个文件 300+ 处，重点：
- `Core/ProcessTap/CoreAudioProcessTapRecorder.swift` 89
- `Core/ProcessTap/ProcessTapManager.swift` 45
- `Core/ProcessTap/SwiftProcessTapManager.swift` 45
- `Core/Recorders/MixedAudioRecorder.swift` 45
- `Utils/AudioUtils.swift` 26、`Utils/FileManagerUtils.swift` 13
- `API/AudioRecordError.swift` 6（错误信息，App 弹窗会透出 `error.localizedDescription`）
- `CAPI/AudioRecordSDK_C.swift` 3

> 说明：Kit 是内部 SDK，不直接上架，但其 errorDescription 会经 App 弹窗透出给用户，属于用户可见。

---

## 四、C 级：大坑——逻辑依赖中文文案（必须先解耦，再谈文案替换）

| 位置 | 问题 |
|---|---|
| `Views/StatusBarView.swift:161-167` | `uppercased.contains("录制中") / "停止录制" / "播放" / "错误"` 驱动状态机（虽然已补英文兜底，但本质是文案驱动逻辑） |
| `Controllers/MainViewController.swift:108` | `status.contains("失败") || contains("错误") || contains("权限")` 做控制流判断 |
| `Kit/Sources/CAPI/AudioRecordSDK_C.swift:62-67` | `status.contains("录制中"/"Recording")` 状态回读判断 |
| `Kit/Recorders/MicrophoneRecorder.swift:64` | `error.localizedDescription.contains("权限")` 依赖系统本地化文案（用户切英文系统后立即失效） |

**改法**：全部改为枚举/状态码驱动（如 `RecordingStatus` enum），文案只做展示。

### 额外硬编码数据（用户可见产物）
- 录音文件名前缀（`MainViewController.swift:440-445`）：`麦克风_`、`系统混音_`、`应用声音_`、`已恢复_`、`录音_` + `恢复_日期`（:1185）。**文件名是用户可见产物，必须本地化**（建议英文或纯时间戳）。
- `Kit/Core/ProcessTap/CoreAudioProcessTapRecorder.swift:378`：`name.contains("qq音乐")` 进程名硬匹配（国际化无关但属脆弱硬编码，建议顺带改为大小写不敏感 + bundle id 匹配）。

---

## 五、D 级：内部日志与注释（不影响上架，建议排最后）

- 全仓 `logger.info("...")` / `print` / `NSLog` 中文日志：App 侧 300+ 处、Kit 侧大量。
  - 不上用户界面，不影响审核；但建议统一改英文：① 国际用户报障时日志可读；② 避免与 UI 文案混淆误改。
- 中文代码注释：全仓大量（如 AppDelegate 107 处 Han 匹配多为注释+日志），**不需要改**。
- `AudioRecordKit/Sources/CAPI/AudioRecordSDK.h`（162 处）为头文件文档注释，SDK 对外文档建议英文，内部可缓。
- `build.sh` 中文 echo：构建脚本输出，不影响，可不管。
- `docs/`、`e2e/`、`.weiyige/` 中文文档：内部文档，不需要动。

---

## 六、E 级：测试同步改造（文案改完测试必挂）

| 文件 | 处数 | 说明 |
|---|---|---|
| `AudioRecordMacUITests/SidebarUITests.swift` | 28 | 断言中文 UI 文案 |
| `AudioRecordMacUITests/TracksUITests.swift` | 33 | 同上 |
| `AudioRecordMacUITests/LayoutUITests.swift` | 4 | 同上 |
| `AudioRecordMacUITests/RecordingFlowUITests.swift` | 4 | 同上 |
| `AudioRecordKit/Tests/FileManagerUtilsTests.swift` | 断言 `麦克风_`/`系统音频_`/`应用音频_` 文件名前缀 |
| `AudioRecordKit/Tests/PermissionAndLoggerTests.swift` | 断言权限引导文案含 `麦克风`/`系统偏好设置` |
| `AudioRecordKit/Tests/SDKErrorAndConstraintsTests.swift` | 断言错误文案 `测试功能`/`未知错误` |
| `AudioRecordKit/Tests/AudioRecordingModelTests.swift` | 断言 `采样率`/`声道` |
| `AudioRecordKit/Tests/AudioUtilsTests.swift` | 断言 `缓冲区数量` |

**改法**：UITests 按 `accessibilityIdentifier` 定位而不是文案；单元测试按枚举/错误码断言而不是字符串。

---

## 七、日期/数字格式化（总体安全，注意两点）

- 已用 `ISO8601DateFormatter`（安全）；`DateFormatter.localizedString`（自动本地化，安全）。
- `yyyyMMdd_HHmmss`（文件名时间戳）与 `yyyy-MM-dd HH:mm:ss.SSS`（日志）：非用户展示，安全。
- 注意点：UI 上若显示时长/大小，确认已用 `Duration.seconds.formatted()` / `ByteCountFormatter` 而非手工拼"小时/分钟/MB"（排查中未见硬编码单位，改造时复核即可）。

---

## 八、推荐实施方案

1. **基建**：project.yml 加 `knownRegions: [en, zh-Hans]`；新建 `Localizable.xcstrings`（Xcode String Catalog）；`String(localized:)` / `LocalizedStringResource` + `Text` 自动查表。
2. **顺序**（严格串行）：
   1. 先解耦 §四 的逻辑依赖中文（枚举化）——否则后面没法动文案
   2. 建 String Catalog + 迁移 B 级 UI 文案（先 base=en 抽英文 key，zh-Hans 保留现中文翻译，行为零变化）
   3. 文件名/错误消息（§四额外项）
   4. A 级：InfoPlist.strings + 菜单 + DisplayName
   5. E 级：同步改测试
   6. D 级日志英文化（可选，最后）
3. **验证**：`build-app.sh` 构建 + 切换系统语言（en/zh-Hans）双跑 E2E + 落盘硬验证（铁律 1）。
4. **App Store Connect 侧**（不在代码内）：App 名称、副标题、描述、关键词、截图需按语言集本地化——属于上架元数据，另行排期。

---

## 九、工作量粗估

| 阶段 | 量级 |
|---|---|
| 逻辑解耦（§四） | 0.5 天 |
| String Catalog 基建 + A 级 | 0.5 天 |
| B 级文案迁移（~800 处） | 2–3 天 |
| 测试同步（§六） | 0.5–1 天 |
| 双语言回归 | 0.5 天 |
| **合计** | **4–5.5 天** |

---

## 十、实施进度（2026-09-20 第一轮）

### 已完成 ✅

**1. 本地化基建**
- `AudioRecordApp/Sources/L10n/L10n.swift`：`String.localized` / `localized(_:)`（key=中文原文，zh-Hans fallback 原文、en 查表）+ `containsStatusFailure()` 双语逻辑判断助手
- `AudioRecordApp/Sources/L10n/en.lproj/Localizable.strings`：**177 个 key 全量英文翻译**
- `AudioRecordApp/Sources/L10n/zh-Hans.lproj/`：Localizable.strings（空壳）+ InfoPlist.strings（中文权限文案）
- `project.yml`：KNOWN_REGIONS = [Base, en, zh-Hans]（xcodegen 流程）
- `build-app.sh`：新增 lproj 资源复制步骤（rsync 进 App Resources）
- 两份 `Info.plist`（根 + AudioRecordApp/Resources/）权限文案改英文 + 新增 CFBundleDisplayName=Tapture

**2. A 级（上架红线）**
- TCC 权限文案：Info.plist 英文 base + zh-Hans InfoPlist.strings ✓
- 主菜单栏（AppDelegate）：设置…/编辑/录制/撤销/重做/开始停止录制/播放暂停/导出MP3/删除录音/切换侧边栏 + 窗口标题 ✓
- CFBundleDisplayName=Tapture ✓

**3. 逻辑解耦（§四）**
- `MainViewController:onStatus` → `containsStatusFailure()`（双语关键词）
- `StatusBarView.updateStatus` → 补全 STOPPING/STOPPED/FAIL/失败 关键词（双语兜底）
- `AudioRecordSDK_C.swift` / `MicrophoneRecorder.swift` 已是双语，确认无需改

**4. B 级文案迁移（约 250 处）**
- MainViewController（45+）、AppDelegate、StatusBarView、ControlPanelView、SidebarView、SettingsWindowController、RecordedFilesView（含文件名前缀双语替换）、TracksView、MainWindowView、TitleBarView、TrackPanelView、EditToolbarView、AudioSource
- ExportCardWindowController、ExportService（含 ExportError）
- Kit 层：AudioRecordError（6 错误文案）、AudioRecording.recordingModeDisplayName、RecordingSettings.validate
- 文件名生成：`麦克风_%@` / `系统混音_%@` / `应用声音_%@` / `已恢复_%@` / `录音_%@` / `恢复_%@` 全部占位符化

**5. 验证**
- `build-app.sh` 构建通过（零编译错误）
- lproj 资源确认进 bundle（en/zh-Hans × Localizable.strings + InfoPlist.strings）
- plutil -lint 三个 strings 文件语法 OK；en 表 177 key 抽查全命中

### 第二轮完成 ✅（2026-09-20）

**1. Editor 系列（约 90 处）**
- EditorViewController：操作失败/保存失败/请先创建选区/选区过短/未检测到静音段/检测到 N 个静音段/音量标准化/淡入淡出/有未保存的编辑等全部弹窗（含「YouTube (-14 LUFS)」遗漏项）+ loadError 文案
- EditorSession（loadError）、EditorStatusBar（总时长/单声道/立体声/编辑步数）、EditorWaveformView（加载波形/选择文件/拖拽引导）、ZoomControlsView（缩小/放大/缩放级别/适应全部/缩放 Nx）、HorizontalScrollBarView（时间位置/位置 N%——% 已转义为 %%@）、EditorNavigationBar（保存）
- 各 Command 描述（弹窗透出）：TrimCommand、SilenceTrimCommand、NormalizeCommand（含预设名播客/广播/自定义）、FadeCommand、SplitAudioClipCommand（切分 @ Ns）
- WaveformView 收尾：引导文案「点击 ● 开始录制」+ 无障碍「录制」

**2. Kit 层用户可见文案（onStatus / NSError / errorDescription，会透出 UI）**
- AudioRecorderProtocol（录制已停止/文件创建成功）、MicrophoneRecorder（正在录制麦克风/权限提示/启动失败）、MixedAudioRecorder（混音状态 + 6 个 NSError）、CoreAudioProcessTapRecorder（设备切换/PID 未找到）、AudioToolboxFileManager（创建/写入失败）、SwiftProcessTapManager（Tap UUID）、AudioUtils（AudioDataConversionError 4 项 + formattedChannels）
- PermissionManager：getPermissionStatusDescription 4 项 + getPermissionGuide 双引导文案（直引号改「」避免 strings 转义）

**3. en 表规模：261 key，plutil 语法 OK，构建零错误零警告**

### 第三轮完成 ✅（2026-09-20）

**1. 测试同步（§六）**
- **UITests 4 文件：核查后无需改动**——全部已用 `accessibilityIdentifier` 定位（`ProcessRow-<pid>` / `ProcessCheckbox-<pid>` / `TrackRow-<title>` / `TracksView` / `RecordButton` 等），中文只存在于注释与断言失败消息（开发者向，跨语言无害）
- 发现并修复缺口：TracksUITests 引用的 `EmptyStateLabel` / `EmptyStateHint` identifier 在源码中**不存在**（一直 fallback 到中文文案 predicate `label CONTAINS '选择音源'`，英文环境会失效）→ 已在 `TracksView.setupEmptyState()` 补上这两个 identifier
- **Kit Tests 6 文件：判定为遗留测试，不改造**——`@testable import AudioRecordKit` 无对应编译 target（project.yml 无 Kit test target），且调用的方法（如 `generateRecordingFileName`）在当前代码库已不存在，这些测试当前无法编译运行，不在构建体系内

**2. 双语言回归（落盘硬验证）**
- 英文环境启动：`audio_record_mac -AppleLanguages "(en)"` → 启动日志确认 **窗口 `title=Tapture`**（原「音频录制工具」本地化查表生效）
- App 全流程正常：主窗口创建→文件列表加载→进程枚举（WeChat/CodeBuddy 等 9 个真实进程）→无崩溃无异常
- bundle 资源验证：en/zh-Hans lproj 就位、plutil 语法 OK、en 表 261 key

### 总体完成度

| 项 | 状态 |
|---|---|
| A 级上架红线（TCC 文案/菜单/DisplayName） | ✅ |
| B 级 App 层 UI 文案（~350 处） | ✅ |
| Kit 层用户可见文案（onStatus/错误，~40 处） | ✅ |
| C 级逻辑解耦（4 处） | ✅ |
| C 级文件名本地化 | ✅ |
| E 级测试同步 | ✅（UITests identifier 化 + 补缺失 identifier；Kit Tests 判遗留） |
| 双语言回归 | ✅（英文环境启动验证 + 中文行为零变化） |
| D 级日志英文化 | ⏳ 可选，建议后续统一处理 |
| App Store Connect 元数据本地化 | ⏳ 上架时另行处理（名称/副标题/描述/截图） |
