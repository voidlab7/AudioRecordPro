---
name: test-runner
description: AudioRecordMac 项目自动化测试技能。当用户请求运行测试、编写测试、查看测试报告、验证 UI 或检查代码质量时使用。支持 UI 测试（XCUITest）、快照测试（SnapshotTesting）、SDK 单元测试、静态代码审计和 AI 视觉审查。触发关键词：运行测试、跑测试、test、测试报告、快照测试、UI测试、snapshot test、写测试、添加测试。
---

# AudioRecordMac 自动化测试 Skill

## 概述

此 Skill 为 AudioRecordMac 项目提供完整的自动化测试能力，涵盖从单元测试到 UI 自动化测试的全链路。AI 可以运行测试、分析报告、编写新测试用例、诊断失败原因。

## 触发条件

当用户请求以下内容时触发此 Skill：

### 运行测试
- "跑一下测试" / "运行测试" / "run tests"
- "跑 UI 测试" / "运行快照测试"
- "全量测试" / "完整测试"
- "快速检查" / "smoke test"

### 编写测试
- "写一个测试" / "添加测试用例"
- "给 XXX 写个 UI 测试"
- "添加快照测试"
- "增加测试覆盖"

### 查看报告
- "测试报告" / "看看测试结果"
- "上次测试怎么样"
- "测试通过了吗"

### 诊断问题
- "测试失败了" / "为什么测试挂了"
- "帮我修复测试"

## 项目测试架构

```
AudioRecordMac/
├── AudioRecordMacUITests/          # XCUITest UI 自动化测试
│   ├── AppLaunchUITests.swift      # App 启动和基础布局验证
│   ├── LayoutUITests.swift         # 窗口尺寸和布局响应式测试
│   └── RecordingFlowUITests.swift  # 录音交互流程测试
├── AudioRecordMacSnapshotTests/    # 快照测试（PointFree SnapshotTesting）
│   ├── ControlPanelSnapshotTests.swift
│   └── __Snapshots__/              # 基准快照图片
├── AudioRecordKit/                 # SDK 单元测试（SwiftPM）
│   └── Tests/
├── scripts/                        # 测试脚本
│   ├── test-ui.sh                  # 运行 UI 测试
│   ├── test-snapshot.sh            # 运行快照测试
│   ├── test-all-ai.sh              # AI 综合测试（SDK + 静态审计 + 架构检查）
│   └── ai-ui-test.sh              # AI 视觉测试（截图 + 交互 + 静态审计）
└── test_logs/                      # 测试输出日志
```

## 测试类型详解

### 1. UI 自动化测试（XCUITest）

**运行命令：**
```bash
./scripts/test-ui.sh
```

**底层命令：**
```bash
xcodebuild test \
  -project AudioRecordMac.xcodeproj \
  -scheme AudioRecordMac \
  -destination 'platform=macOS' \
  -only-testing:AudioRecordMacUITests
```

**前置条件：**
- 需要 `xcodegen` 已安装（`brew install xcodegen`）
- 如果 `project.yml` 比 `.xcodeproj` 新，会自动重新生成项目

**当前测试用例：**

| 测试类 | 用例 | 验证内容 |
|--------|------|---------|
| AppLaunchUITests | testAppLaunchesAndShowsMainWindow | App 启动后主窗口出现 |
| AppLaunchUITests | testMainLayoutHasCoreRegions | 核心区域存在（Sidebar/ControlPanel/WaveformView/StatusBar） |
| AppLaunchUITests | testPrimaryControlsHaveStableIdentifiers | RecordButton 有稳定的 accessibilityIdentifier |
| LayoutUITests | testDefaultWindowHasMinimumDimensions | 默认窗口 ≥ 900×550 |
| LayoutUITests | testCoreLayoutSurvivesMinimumWindowSize | 最小窗口下布局不崩溃 |
| LayoutUITests | testCoreLayoutAtLargeWindowSize | 大窗口下布局不崩溃 |
| LayoutUITests | testNoGapBetweenSidebarAndContent | Sidebar 和内容区无间隙 |
| RecordingFlowUITests | testRecordButtonExistsAndIsEnabled | 录音按钮可用 |
| RecordingFlowUITests | testRecordButtonCanBeClicked | 录音按钮可点击 |

**编写 UI 测试的模式：**
```swift
import XCTest

final class MyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSomething() throws {
        // Use accessibility identifiers to find elements
        let element = app.buttons["RecordButton"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        
        // Interact
        element.click()
        
        // Verify state change
        let stopButton = app.buttons["StopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 3))
    }
}
```

**关键 Accessibility Identifiers：**
- `MainWindowView` — 主窗口容器（group）
- `Sidebar` — 侧边栏（group）
- `ControlPanel` — 控制面板（group）
- `WaveformView` — 波形显示区（group）
- `StatusBar` — 状态栏（group）
- `RecordButton` — 录音按钮（button）
- `StopButton` — 停止按钮（button）
- `PlayButton` — 播放按钮（button）

---

### 2. 快照测试（SnapshotTesting）

**运行命令：**
```bash
./scripts/test-snapshot.sh
```

**底层命令：**
```bash
xcodebuild test \
  -project AudioRecordMac.xcodeproj \
  -scheme AudioRecordMac \
  -destination 'platform=macOS' \
  -only-testing:AudioRecordMacSnapshotTests
```

**首次运行（录制基准）：**
```bash
SNAPSHOT_TESTING_RECORD=1 ./scripts/test-snapshot.sh
```
首次运行会自动录制快照到 `__Snapshots__/` 目录，第二次运行才会进行对比断言。

**编写快照测试的模式：**
```swift
import Cocoa
import SnapshotTesting
import XCTest

final class MySnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Enable recording mode via environment variable
        isRecording = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] == "1"
    }

    func testMyViewIdle() {
        let view = makeMyView()
        view.updateState(.idle)
        view.layoutSubtreeIfNeeded()
        assertSnapshot(of: view, as: .image)
    }

    private func makeMyView() -> MyView {
        let view = MyView(frame: NSRect(x: 0, y: 0, width: 900, height: 96))
        view.wantsLayer = true
        view.layoutSubtreeIfNeeded()
        return view
    }
}
```

**注意事项：**
- 快照测试不启动 App，直接实例化 View 进行渲染
- 需要在 `project.yml` 的 `AudioRecordMacSnapshotTests` target 中添加被测 View 的源文件
- 基准快照存储在 `__Snapshots__/<TestClassName>/` 目录

---

### 3. SDK 单元测试（SwiftPM）

**运行命令：**
```bash
cd AudioRecordKit && swift test
```

**或使用脚本：**
```bash
./scripts/test_sdk.sh
```

**适用场景：** 测试 AudioRecordKit 中的纯逻辑代码（音频处理、文件管理等）。

---

### 4. AI 综合测试（test-all-ai.sh）

**运行命令：**
```bash
./scripts/test-all-ai.sh              # 默认 quick 模式
./scripts/test-all-ai.sh --quick      # SDK + 静态审计 + 架构检查
./scripts/test-all-ai.sh --full       # 全量：SDK + 构建 + 静态审计 + 架构 + 冒烟
```

**输出：**
- `test_logs/ai-test-<timestamp>/report.json` — 机器可读结果
- `test_logs/ai-test-<timestamp>/report.md` — 人类可读摘要

**包含的检查套件：**

| Suite | 内容 |
|-------|------|
| SDK | SwiftPM 单元测试 |
| Build | App 编译验证 |
| Static | 代码静态审计（accessibility、TODO、hex colors、核心文件） |
| Arch | 架构结构检查（目录、脚本、测试文件） |
| Smoke | App 启动冒烟测试（需要 --full） |

---

### 5. AI 视觉测试（ai-ui-test.sh）

**运行命令：**
```bash
./scripts/ai-ui-test.sh               # 全量（构建 + 截图 + 交互 + 静态）
./scripts/ai-ui-test.sh --screenshot  # 仅截图
./scripts/ai-ui-test.sh --interact    # 仅交互测试
./scripts/ai-ui-test.sh --static      # 仅静态审计
```

**输出：**
- `test_logs/ui-test-<timestamp>/` 目录下的截图和报告
- AI 可通过 `read_image` 工具审查截图

---

## 测试执行流程

### 快速验证（推荐日常使用）

```
1. 运行 ./scripts/test-all-ai.sh --quick
2. 读取 report.json 判断 pass/fail
3. 如有失败，定位具体 suite 和 test name
4. 修复后重新运行验证
```

### 完整验证（发布前）

```
1. 运行 ./scripts/test-ui.sh          → UI 自动化测试
2. 运行 ./scripts/test-snapshot.sh     → 快照回归测试
3. 运行 ./scripts/test-all-ai.sh --full → 综合检查
4. 查看 xcresult 报告确认全部通过
```

### 查看测试报告

**xcresult 报告（UI 测试和快照测试）：**
```bash
# 找到最新的测试结果
ls -t ~/Library/Developer/Xcode/DerivedData/AudioRecordMac-*/Logs/Test/*.xcresult | head -1

# 查看摘要
xcrun xcresulttool get test-results summary --path <xcresult_path>

# 查看详细测试列表
xcrun xcresulttool get test-results tests --path <xcresult_path>
```

**AI 测试报告：**
```bash
# 找到最新报告
ls -t test_logs/ai-test-*/report.json | head -1

# 读取 JSON 报告
cat test_logs/ai-test-<timestamp>/report.json
```

---

## 编写新测试的指南

### 添加 UI 测试

1. 在 `AudioRecordMacUITests/` 目录创建新的 `.swift` 文件
2. 遵循现有模式：`setUpWithError` 中启动 app，`tearDownWithError` 中清理
3. 使用 `app.launchArguments = ["--ui-testing"]` 启动参数
4. 通过 accessibility identifier 定位元素
5. 使用 `waitForExistence(timeout:)` 等待元素出现
6. 文件会被 XcodeGen 自动包含（`sources: - path: AudioRecordMacUITests`）

### 添加快照测试

1. 在 `AudioRecordMacSnapshotTests/` 目录创建新的 `.swift` 文件
2. 如果测试新的 View，需要在 `project.yml` 的 `AudioRecordMacSnapshotTests.sources` 中添加该 View 的源文件路径
3. 首次运行设置 `SNAPSHOT_TESTING_RECORD=1` 录制基准
4. 后续运行自动对比

### 添加 SDK 单元测试

1. 在 `AudioRecordKit/Tests/` 目录创建测试文件
2. 使用标准 `XCTest` 框架
3. 通过 `swift test` 运行

---

## 测试失败诊断

### UI 测试失败

1. **元素未找到** — 检查 accessibility identifier 是否正确设置
2. **超时** — 增加 `waitForExistence` 的 timeout，或检查 App 启动是否正常
3. **布局断言失败** — 检查窗口约束是否被修改
4. **Runtime Warnings** — 通常是 Auto Layout 约束冲突，不影响功能但需关注

### 快照测试失败

1. **首次运行失败** — 正常行为，需要先录制基准（设置 `SNAPSHOT_TESTING_RECORD=1`）
2. **对比失败** — View 的渲染发生了变化，检查是否是预期变更
3. **如果是预期变更** — 删除旧快照或设置 `isRecording = true` 重新录制

### 静态审计失败

1. **accessibility_coverage** — 确保 Views 中有足够的 accessibility 标注（≥10）
2. **required_identifiers** — 确保 8 个核心 identifier 都存在
3. **core_views_exist** — 确保 5 个核心 View 文件存在

---

## 项目配置参考

### project.yml 测试 Target 配置

```yaml
# UI 测试 Target
AudioRecordMacUITests:
  type: bundle.ui-testing
  platform: macOS
  sources:
    - path: AudioRecordMacUITests
  settings:
    base:
      TEST_TARGET_NAME: AudioRecordMac
      GENERATE_INFOPLIST_FILE: true
  dependencies:
    - target: AudioRecordMac

# 快照测试 Target
AudioRecordMacSnapshotTests:
  type: bundle.unit-test
  platform: macOS
  sources:
    - path: AudioRecordMacSnapshotTests
    - path: AudioRecordApp/Sources/Views/ControlPanelView.swift  # 被测 View
    # ... 添加更多被测 View
  settings:
    base:
      SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG SNAPSHOT_TESTING
  dependencies:
    - package: SnapshotTesting
```

### Scheme 配置

```yaml
schemes:
  AudioRecordMac:
    test:
      targets:
        - name: AudioRecordMacUITests
        - name: AudioRecordMacSnapshotTests
```

---

## 注意事项

1. **UI 测试会启动 App** — 运行时会看到 App 窗口弹出，这是正常行为
2. **快照测试不启动 App** — 直接实例化 View，速度更快
3. **xcodegen 是前置依赖** — 所有 xcodebuild 测试都需要先生成 `.xcodeproj`
4. **测试日志目录** — `test_logs/` 已在 `.gitignore` 中，不会提交
5. **DerivedData** — xcresult 存储在 `~/Library/Developer/Xcode/DerivedData/` 中
6. **并行运行** — UI 测试和快照测试可以分别运行，互不干扰
