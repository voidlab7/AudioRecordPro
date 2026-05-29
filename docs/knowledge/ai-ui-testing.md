# AI UI 测试知识库：XCTest、XCUITest、Snapshot 与 AI 视觉巡检

> 更新时间：2026-05-22
> 状态：执行中
> 适用范围：AudioRecordMac 的桌面 App UI 自动化、截图回归、AI 视觉审查与发布前质量门禁

---

## 1. 总体结论

AudioRecordMac 当前最适合采用四层测试体系：

| 层级 | 框架/方式 | 主要目标 | 是否启动真实 App | 稳定性 |
|---|---|---|---:|---:|
| SDK 单元测试 | XCTest / SwiftPM | `AudioRecordKit` 业务逻辑、文件、音频工具 | 否 | 高 |
| App UI 自动化 | XCTest + XCUITest | 启动、主窗口、录制/停止、设置、布局存在性 | 是 | 中高 |
| 截图回归 | swift-snapshot-testing | AppKit 组件视觉状态、尺寸、主题一致性 | 否/局部 | 中高 |
| AI 视觉巡检 | `scripts/ai-ui-test.sh` | 真实窗口截图、视觉还原、交互巡检 | 是 | 中 |

关键策略：

- XCUITest 只验证真实用户路径和 accessibility 抓手，不做像素级视觉判断。
- swift-snapshot-testing 负责组件级视觉回归，先从核心组件开始。
- 现有 `scripts/ai-ui-test.sh` 保留为 AI 视觉审查层，用于真实 App 截图和设计规范检查。
- 为了让 UI 自动化稳定，App 需要支持 `--ui-testing` 启动参数，尽量使用 mock recorder / mock permission / 固定数据源。

---

## 2. 当前工程状态

### 2.1 已有基础

- `AudioRecordKit` 是 Swift Package，已有 `Tests` 目录，可继续使用 `swift test`。
- `AudioRecordApp` 是 AppKit 桌面应用源码，目前通过 `build-app.sh` 使用 `swiftc` 直接构建 `.app`。
- 仓库已 vendored `swift-snapshot-testing`，可作为本地 Swift Package 依赖接入。
- 已有 AI UI 脚本：`scripts/ai-ui-test.sh`。
- 主界面已有一批 accessibility 标识，可作为首批 XCUITest locator：
  - `MainWindowView`
  - `Sidebar`
  - `WaveformView`
  - `LevelMeter`
  - `StatusBar`
  - `ControlPanel`
  - `EditToolbar`
  - `TitleBar`
  - `RecordButton`
  - `StopButton`
  - `PlayButton`

### 2.2 当前短板

- 根目录暂无 `.xcodeproj` / `.xcworkspace`，标准 XCUITest target 需要补工程入口。
- App 层源码目前不是独立 Swift Package target，snapshot target 需要通过 Xcode 工程引用 App 源码。
- UI 自动化仍可能受到系统权限、音频设备、录制目录和首次启动状态影响。
- 部分历史文档中的“零 accessibility 标识符”已过期，应以本知识库为准。

---

## 3. 目标目录结构

推荐落地结构：

```text
audio_record_mac
├── project.yml
├── AudioRecordMac.xcodeproj          # 由 XcodeGen 生成，不手写维护
├── AudioRecordApp
│   ├── Sources
│   └── Resources
├── AudioRecordKit
│   ├── Sources
│   └── Tests
├── AudioRecordMacTests
├── AudioRecordMacUITests
├── AudioRecordMacSnapshotTests
├── scripts
│   ├── test_sdk.sh
│   ├── test-ui.sh
│   ├── test-snapshot.sh
│   └── ai-ui-test.sh
└── docs
    └── knowledge
        └── ai-ui-testing.md
```

---

## 4. XCUITest 方案

### 4.1 首批测试目标

首批 UI 自动化只做稳定、高价值路径：

1. App 能启动并显示主窗口。
2. 主窗口核心区域存在。
3. 录制按钮存在并可点击。
4. 点击录制后出现停止按钮。
5. 点击停止后恢复可录制状态。
6. 最小窗口尺寸下核心区域仍存在。
7. 设置窗口可通过快捷键或入口打开。
8. 关键 accessibility 标识没有丢失。

### 4.2 推荐测试文件

```text
AudioRecordMacUITests
├── AppLaunchUITests.swift
├── RecordingFlowUITests.swift
├── LayoutUITests.swift
├── SettingsUITests.swift
└── AccessibilitySmokeTests.swift
```

### 4.3 UI Testing Mode

XCUITest 启动时统一带参数：

```swift
let app = XCUIApplication()
app.launchArguments = ["--ui-testing"]
app.launch()
```

App 侧推荐统一环境判断：

```swift
enum AppEnvironment {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    static var isSnapshotTesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--snapshot-testing")
    }
}
```

在 `--ui-testing` 下优先使用：

- mock recorder
- mock permission service
- 固定录音目录
- 固定窗口尺寸
- 禁用首次启动引导
- 禁用真实音频捕获或把真实捕获包在可替换接口后

---

## 5. swift-snapshot-testing 方案

### 5.1 首批组件

优先覆盖最影响视觉质量和最容易回归的组件：

1. `ControlPanelView`
2. `MainWindowView`
3. `SidebarView`
4. `WaveformView`
5. `StatusBarView`

### 5.2 推荐测试文件

```text
AudioRecordMacSnapshotTests
├── ControlPanelSnapshotTests.swift
├── MainWindowSnapshotTests.swift
├── SidebarSnapshotTests.swift
├── WaveformSnapshotTests.swift
└── StatusBarSnapshotTests.swift
```

### 5.3 首批截图状态

| 组件 | 状态 |
|---|---|
| `ControlPanelView` | idle、recording、stopping、playing、error |
| `MainWindowView` | 1200×750、960×600、1400×900 |
| `SidebarView` | 空文件列表、有录音文件、进程加载中 |
| `WaveformView` | 空波形、录制中波形、静态文件波形 |
| `StatusBarView` | ready、recording、completed、permission error |

### 5.4 稳定性要求

- 波形、时间、文件列表、进程列表必须使用固定 fixture。
- 截图测试中不要依赖真实系统进程、真实录音文件、当前时间或随机数。
- 如果需要随机数据，必须使用固定 seed。

---

## 6. AI 视觉巡检继续保留

现有脚本继续作为真实 App 视觉巡检入口：

```bash
./scripts/ai-ui-test.sh
./scripts/ai-ui-test.sh --screenshot
./scripts/ai-ui-test.sh --interact
./scripts/ai-ui-test.sh --static
```

它主要发现：

- 暗色工业设计是否偏离。
- 真实窗口截图是否错位。
- 最小窗口、默认窗口、大窗口下布局是否稳定。
- AppleScript 模拟交互是否能触发关键路径。
- AI 对截图进行设计还原审查时的主观问题。

XCUITest、snapshot 与 AI 巡检的分工：

```text
XCUITest        验证用户路径可用
Snapshot        验证组件视觉不回归
AI UI script    验证真实 App 截图与设计审美
```

---

## 7. 命令入口

### 7.1 SDK 单元测试

```bash
./scripts/test_sdk.sh
```

或：

```bash
cd AudioRecordKit && swift test
```

### 7.2 生成 Xcode 工程

```bash
xcodegen generate
```

### 7.3 UI 测试

```bash
./scripts/test-ui.sh
```

内部目标命令：

```bash
xcodebuild test \
  -project AudioRecordMac.xcodeproj \
  -scheme AudioRecordMac \
  -destination 'platform=macOS' \
  -only-testing:AudioRecordMacUITests
```

### 7.4 Snapshot 测试

```bash
./scripts/test-snapshot.sh
```

内部目标命令：

```bash
xcodebuild test \
  -project AudioRecordMac.xcodeproj \
  -scheme AudioRecordMac \
  -destination 'platform=macOS' \
  -only-testing:AudioRecordMacSnapshotTests
```

更新基准图时使用：

```bash
SNAPSHOT_TESTING_RECORD=1 ./scripts/test-snapshot.sh
```

---

## 8. 执行路线

### Phase 1：工程入口

- 添加 `project.yml`。
- 使用 XcodeGen 生成 `AudioRecordMac.xcodeproj`。
- 新增 `AudioRecordMacUITests` 与 `AudioRecordMacSnapshotTests` 目录。
- 新增 `scripts/test-ui.sh` 与 `scripts/test-snapshot.sh`。

### Phase 2：首批 XCUITest

- `AppLaunchUITests`
- `AccessibilitySmokeTests`
- `RecordingFlowUITests`
- `LayoutUITests`

### Phase 3：首批 Snapshot

- `ControlPanelSnapshotTests`
- `MainWindowSnapshotTests`
- 必要时先添加轻量 fixture 或测试专用初始化能力。

### Phase 4：稳定化

- 引入 `--ui-testing` mock 模式。
- 对系统权限、真实录音、真实进程列表进行隔离。
- 将测试纳入发布前检查。

---

## 9. 质量门禁

每次 UI 相关需求合并前，至少执行：

```bash
./scripts/test_sdk.sh
./scripts/test-ui.sh
./scripts/test-snapshot.sh
./scripts/ai-ui-test.sh --static
```

若修改了核心视觉组件，额外执行：

```bash
./scripts/ai-ui-test.sh --screenshot
```

若修改了录制流程，额外执行：

```bash
./scripts/ai-ui-test.sh --interact
```

---

## 10. 维护规则

- 新增可交互控件时，必须同步添加 accessibility identifier。
- 新增核心视觉状态时，优先补 snapshot fixture。
- XCUITest 中不要依赖元素标题文案，优先使用 identifier。
- snapshot 中不要依赖当前时间、随机数、真实文件系统和真实系统进程。
- `AudioRecordMac.xcodeproj` 建议由 `project.yml` 生成，不建议手工维护。
- 本文档是 UI 自动化方案的知识库入口，旧截图巡检规则如有冲突，以本文档为准。

---

## 11. AI 自动运行方案（Claude Code / AI Agent 专用）

### 11.1 单命令入口

```bash
# 快速模式：SDK 单元测试 + 静态审计 + 架构检查（~5 秒，无需构建）
./scripts/test-all-ai.sh --quick

# 完整模式：含构建 + App 启动冒烟测试（~30 秒）
./scripts/test-all-ai.sh --full
```

### 11.2 AI 判定流程

```text
1. AI 执行: bash ./scripts/test-all-ai.sh --quick
2. AI 读取: test_logs/ai-test-<timestamp>/report.json
3. AI 判定:
   - overall_status == "pass" → 安全，可继续开发
   - overall_status == "fail" → 读取 results 中 status=="fail" 的条目
   - 根据失败项修复后重新运行
4. 重要变更后: bash ./scripts/test-all-ai.sh --full
```

### 11.3 报告格式（report.json）

```json
{
  "overall_status": "pass|fail",
  "summary": { "total": N, "passed": N, "failed": N, "skipped": N },
  "results": [
    { "suite": "SDK|Build|Static|Arch|Smoke",
      "name": "test_name",
      "status": "pass|fail|skip",
      "duration_ms": 0,
      "message": "..." }
  ]
}
```

### 11.4 测试覆盖范围

| Suite | 测试内容 | 依赖条件 | 耗时 |
|-------|---------|---------|------|
| SDK | 76 个 SwiftPM 单元测试 | Swift 编译器 | ~3s |
| Build | App 能否编译出 .app | build.sh | ~20s |
| Static | 代码规范、accessibility、设计 token | 无 | <1s |
| Arch | 目录结构、脚本存在性、测试文件完整性 | 无 | <1s |
| Smoke | App 能否启动、窗口显示 | 构建产物 | ~5s |

### 11.5 触发时机建议

| 场景 | 建议命令 |
|------|---------|
| 修改 AudioRecordKit 源码后 | `--quick` |
| 修改 UI 视图代码后 | `--quick`（确认 identifier 未丢失） |
| 提交 PR / 合并前 | `--full` |
| 重大架构变更后 | `--full` + `./scripts/ai-ui-test.sh --static` |
| 发布版本前 | `--full` + `./scripts/ai-ui-test.sh --screenshot` |

### 11.6 与 AI 视觉巡检的分工

```text
test-all-ai.sh --quick    → 代码质量 + 逻辑正确性（机器可判定）
test-all-ai.sh --full     → 含构建验证 + 启动冒烟（机器可判定）
ai-ui-test.sh --static    → 设计规范审计（AI 主观判定）
ai-ui-test.sh --screenshot→ 真实截图视觉审查（AI 主观判定）
ai-ui-test.sh --interact  → 交互流程截图（AI 主观判定）
```

### 11.7 失败时的自动修复指引

| 失败 Suite | 常见原因 | AI 修复策略 |
|-----------|---------|-----------|
| SDK | 类型不匹配、缺失协议方法 | 读取 sdk-test-output.txt 中的编译错误并修复 |
| Build | swiftc 编译错误 | 读取 build-output.txt 定位错误文件 |
| Static/accessibility | 新增控件未添加 identifier | 在对应 View 文件中添加 setAccessibilityIdentifier |
| Static/required_identifiers | 核心 identifier 被重命名或删除 | 恢复或更新 identifier 映射 |
| Arch | 文件被误删 | 从 git 恢复或重新创建 |
| Smoke | App 启动崩溃 | 检查 Console.app 日志或 build-output.txt |

---

## 12. 后续改进 Backlog

- 将 identifier 统一迁移到层级命名，例如 `record.button`、`layout.sidebar`、`settings.window`。
- 给 `SidebarView`、`WaveformView` 增加测试 fixture 注入接口。
- 给录制控制器抽象 `RecordingServiceProtocol`，方便 `--ui-testing` mock。
- 在 CI 中安装 XcodeGen 并运行 UI/snapshot smoke test。
- 对 snapshot diff 图片引入 AI 自动审查流程。
- 将 `test-all-ai.sh` 接入 Git pre-push hook 或 GitHub Actions。

---

*文档维护者：AI 测试系统*
*关联文档：`docs/design/design-system.md`、`docs/knowledge/tech.md`、`scripts/ai-ui-test.sh`、`scripts/test-all-ai.sh`*
