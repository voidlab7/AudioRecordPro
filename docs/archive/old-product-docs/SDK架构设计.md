# AudioRecordKit 架构设计

> 更新时间：2026-05-03
> 状态：当前有效。本文描述当前 `AudioRecordKit/` 的真实架构，不再使用旧 `src/` 结构和未完成 C API 口径。

## 1. 目标

`AudioRecordKit` 的目标是把 macOS 音频录制能力封装为可复用 SDK，供三类调用方使用：

- `AudioRecordApp`：当前原生 App。
- Swift / Objective-C macOS 应用：通过 Swift Package 使用。
- C / C++ / Electron / Chromium 类宿主：通过 C API 或后续绑定使用。

## 2. 当前目录结构

```text
AudioRecordKit/
├── Package.swift
├── README.md
├── Sources/
│   ├── API/
│   │   ├── AudioConstraints.swift
│   │   ├── AudioRecordAPI.swift
│   │   ├── AudioRecordError.swift
│   │   ├── MediaStream.swift
│   │   ├── MediaStreamTrack.swift
│   │   └── Types.swift
│   ├── CAPI/
│   │   ├── AudioRecordSDK.h
│   │   └── AudioRecordSDK_C.swift
│   ├── Core/
│   │   ├── Models/
│   │   ├── ProcessTap/
│   │   ├── Protocols/
│   │   └── Recorders/
│   └── Utils/
└── Tests/
```

## 3. 分层架构

```text
调用方
  ├─ AudioRecordApp
  ├─ Swift/ObjC App
  └─ C/C++/Electron/Chromium 宿主
        │
        ▼
API 层
  ├─ Swift API: AudioRecordAPI / AudioConstraints / MediaStream
  └─ C API: AudioRecordSDK.h / AudioRecordSDK_C.swift
        │
        ▼
Core 层
  ├─ MicrophoneRecorder
  ├─ ScreenCaptureAudioRecorder
  ├─ CoreAudioProcessTapRecorder
  ├─ MixedAudioRecorder
  ├─ ProcessTapManager
  ├─ AggregateDeviceManager
  └─ AudioToolboxFileManager
        │
        ▼
系统框架
  ├─ AVFoundation
  ├─ CoreAudio
  ├─ AudioToolbox
  └─ ScreenCaptureKit
```

## 4. API 层

### 4.1 Swift API

当前 Swift API 是 MVP 接口，核心使用方式：

```swift
let constraints = AudioConstraints(
    echoCancellation: true,
    noiseSuppression: true,
    includeSystemAudio: false
)

let stream = try await AudioRecordAPI.shared.getUserMedia(constraints: constraints)
try AudioRecordAPI.shared.startRecording(stream: stream)
AudioRecordAPI.shared.stopRecording()
```

当前能力边界：

| 能力 | 状态 |
|---|---|
| 麦克风录制 | 支持 |
| 系统音频混入 | 支持 |
| 指定进程录制 | App 控制层支持；Swift MVP API 尚未形成完整公开参数 |
| 多轨动态管理 | 未实现 |
| 完整 Web `MediaDevices` 兼容 | 未实现 |

### 4.2 共享类型

`API/Types.swift` 提供 App 与 SDK 共用的公开类型：

- `RecordingMode`: `.microphone` / `.specificProcess` / `.systemMixdown`
- `AudioFormat`: `.m4a` / `.wav`
- `RecordingState`: idle / preparing / recording / stopping / playing / error
- `AudioProcessInfo`
- `RecordedFileInfo`
- `TrackInfo`

### 4.3 C API

C API 已存在：

- 头文件：`AudioRecordKit/Sources/CAPI/AudioRecordSDK.h`
- 实现：`AudioRecordKit/Sources/CAPI/AudioRecordSDK_C.swift`

接口覆盖：

- 生命周期管理
- 录制控制
- 状态/时长查询
- 格式/采样率/输出目录配置
- 电平/状态/完成/错误回调
- 麦克风与屏幕捕获权限检查
- 可录制进程枚举

需要明确的限制：

- `Pause/Resume` 不应宣传为完整可用能力，除非实现已补齐。
- 指定进程录制需持续验证 PID 是否完整透传到底层录制器。
- 屏幕捕获权限检查需要真实 preflight 和用户引导。
- C API 系统版本要求应区分基础麦克风能力与 Process Tap 能力。

## 5. Core 层

| 组件 | 职责 |
|---|---|
| `MicrophoneRecorder` | 基于 AVAudioEngine 录制麦克风 |
| `ScreenCaptureAudioRecorder` | ScreenCaptureKit fallback 路径 |
| `CoreAudioProcessTapRecorder` | 使用 CoreAudio Process Tap 录制系统/进程音频 |
| `MixedAudioRecorder` | 将系统/进程音频与麦克风混到单文件 |
| `AudioProcessEnumerator` | 枚举可录制音频进程 |
| `ProcessTapManager` | 管理 Process Tap 生命周期 |
| `AggregateDeviceManager` | 管理聚合设备 |
| `AudioToolboxFileManager` | 音频文件写入 |

## 6. 系统要求

| 能力 | 要求 |
|---|---|
| 麦克风录制 | macOS 13.0+ |
| 系统音频/指定进程 Process Tap | macOS 14.4+ |
| ScreenCaptureKit fallback | 依赖系统版本和权限能力 |

权限要求：

- 麦克风权限：`NSMicrophoneUsageDescription`
- 系统音频/屏幕捕获相关权限：需要用户在系统设置中授权

## 7. 当前架构风险

| 风险 | 说明 | 建议 |
|---|---|---|
| App 层能力强于 SDK API | App 已有多音源控制，但 Swift MVP API 未完整暴露 | 后续把 App 中稳定的模型沉淀回 SDK API |
| C API 声明强于实现 | 头文件较完整，部分函数仍是弱实现或未实现 | README 和文档明确标注限制 |
| `@MainActor` 依赖 | 部分 SDK 能力仍绑定主线程模型 | 后续拆分音频核心线程与 UI 回调线程 |
| 测试覆盖不足 | 系统音频能力依赖真实设备/权限 | 单元测试覆盖纯逻辑，集成测试覆盖真实录制路径 |

## 8. 下一步架构任务

1. 梳理 Swift API v1：是否显式支持指定进程、输出目录、格式选择。
2. 补齐或降级 C API 中未完成函数，避免对外误导。
3. 更新 `AudioRecordKit/README.md`，加入能力边界和限制说明。
4. 修复或替换 `scripts/test_sdk.sh` 的旧 `src/` 路径。
5. 为 C API 增加最小可运行示例。
