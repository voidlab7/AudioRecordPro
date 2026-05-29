# AudioRecordMac 测试计划

> 更新时间：2026-05-03
> 状态：当前有效。旧 `src/` 路径和 `test_sdk.sh unit` 说法已废弃。

## 1. 当前测试现状

| 维度 | 当前状态 | 风险 |
|---|---|---|
| SDK 单元测试 | 已有 6 个 Swift 测试文件 | 需要持续跑通并纳入发布前检查 |
| App UI 测试 | 仅有少量脚本/人工验证 | AppKit 交互和窗口状态仍需人工回归 |
| 真实录制集成测试 | 有脚本雏形，但部分脚本仍引用旧 `src/` 路径 | 需要更新脚本后才能作为可靠测试入口 |
| 权限/系统版本测试 | 不完整 | 系统音频依赖 TCC 权限和 macOS 版本，风险高 |
| 发布包测试 | 有 DMG 脚本，但缺完整验收清单 | Beta/Release 前必须补齐 |

## 2. 现有测试文件

当前 `AudioRecordKit/Tests/` 下已有：

```text
AudioRecordKit/Tests/
├── AudioRecordingModelTests.swift
├── AudioUtilsTests.swift
├── FileManagerUtilsTests.swift
├── PermissionAndLoggerTests.swift
├── SDKErrorAndConstraintsTests.swift
└── ThemeAndMonitorTests.swift
```

这些测试应作为 SDK 纯逻辑回归的基础。

## 3. 推荐运行方式

### SDK 单元测试

```bash
cd AudioRecordKit
swift test
```

### App 构建检查

```bash
./build-app.sh
```

或：

```bash
./AudioRecordApp/build.sh
```

注意：当前存在多个构建脚本，后续应统一一个主入口。

### 现有脚本状态

`scripts/test_sdk.sh` 当前仍引用旧目录：

```text
SRC_DIR="$ROOT_DIR/src"
```

而当前工程已经迁移到 `AudioRecordKit/` + `AudioRecordApp/`。因此该脚本在修复前不应作为正式测试入口。

## 4. P0 回归用例

### 4.1 全部系统声音录制

| 步骤 | 期望 |
|---|---|
| 打开 App | 默认选中“全部系统声音” |
| 播放任意系统声音 | 电平/波形有反馈 |
| 点击录制 | 状态进入 recording，计时开始 |
| 停止录制 | 文件保存到 `~/Documents/AudioRecordings` |
| 双击文件 | Finder 中选中文件 |

### 4.2 指定 App 声音录制

| 步骤 | 期望 |
|---|---|
| 打开有音频输出的 App | 刷新后出现在进程列表 |
| 选择该 App | “全部系统声音”取消选中，轨道显示 App 名称/图标 |
| 开始录制 | 只录目标 App 声音 |
| 停止录制 | 文件生成且可播放 |

### 4.3 混入麦克风

| 步骤 | 期望 |
|---|---|
| 选择系统声音或 App 声音 | 主目标明确 |
| 开启“同时录入麦克风” | 权限不足时触发权限申请/提示 |
| 录制并讲话 | 录音文件同时包含主目标和麦克风 |
| 停止录制 | 只生成一个混音文件 |

### 4.4 权限异常

| 场景 | 期望 |
|---|---|
| 麦克风权限拒绝 | 给出明确原因和修复方式 |
| 屏幕录制/系统音频权限缺失 | 告知需要系统设置授权 |
| macOS < 14.4 选择指定进程 | 明确提示该能力需要 macOS 14.4+ |

### 4.5 文件闭环

| 场景 | 期望 |
|---|---|
| 首次无录音 | 显示清晰空状态 |
| 录音完成 | 文件列表自动出现新文件 |
| 文件很多 | 列表可滚动且不破坏布局 |
| 导出失败 | 给出失败提示，不静默失败 |

## 5. P1 单元测试补齐方向

| 模块 | 建议测试 |
|---|---|
| `AudioConstraints` | 默认值、自定义参数、`includeSystemAudio` 行为 |
| `MediaStream` / `MediaStreamTrack` | 单轨 MVP 行为、不支持操作的错误路径 |
| `AudioFormat` | M4A/WAV settings 和扩展名 |
| `RecordedFileInfo` | 时长/文件大小格式化 |
| `FileManagerUtils` | 输出目录、文件名生成、扩展名过滤 |
| `PermissionManager` | 权限状态描述、拒绝态提示 |
| `AudioProcessInfo` | Hashable/Equatable 行为 |

## 6. P2 自动化脚本任务

1. 修复 `scripts/test_sdk.sh`：从旧 `src/` 路径切换到 `AudioRecordKit/Sources/`。
2. 增加 `scripts/test_app_build.sh`：只做构建和签名检查。
3. 增加 `scripts/test_release_package.sh`：验证 `.app`、DMG、Info.plist、entitlements。
4. 对窗口拖动脚本 `scripts/test_window_drag.sh` 保留为 UI smoke test。

## 7. 发布前验收清单

| 项目 | 必须通过 |
|---|---|
| `cd AudioRecordKit && swift test` | 是 |
| `./build-app.sh` | 是 |
| 首次启动权限流程 | 是 |
| 全部系统声音录制 | 是 |
| 指定 App 声音录制 | 是 |
| 麦克风混入 | 是 |
| 录音文件生成和 Finder 打开 | 是 |
| 导出文案与真实格式一致 | 是 |
| DMG 可安装并启动 | Beta 前必须 |

## 8. 当前测试结论

测试体系已经有 SDK 单元测试基础，但发布级回归还不完整。下一阶段应优先修复旧脚本路径，并把三条核心录制路径固定为手动/半自动回归清单。
