# AudioRecordKit

macOS 音频录制 SDK(Loocap 路文 App 的录制内核),同时承载转写引擎与加密存储工具。

> 架构全貌见 [`docs/架构/技术架构图.html`](../docs/架构/技术架构图.html),现状评审见 [`docs/架构/架构评审-2026-10-29.md`](../docs/架构/架构评审-2026-10-29.md)。
> **重要现状**:App 目前通过 `build-app.sh` 把本目录源码与 App 源码平铺进同一个 module 编译,并直接使用下文标注为 *internal* 的类型;`AudioRecordAPI` 公开面尚未被 App 使用(评审 A1)。本 README 描述的是代码实际状态,而非理想状态。

## 功能

| 能力 | 入口 | 系统要求 |
|---|---|---|
| 麦克风录制(含设备选择、AUHAL 采集) | `MicrophoneRecorder`(internal);`AudioRecordAPI`(public) | macOS 13+ |
| 系统音频录制(全局 Process Tap) | `CoreAudioProcessTapRecorder(.systemMixdown)` | macOS 14.4+ |
| 指定进程录制 / 多进程独立录制 | `CoreAudioProcessTapRecorder(.specificProcess)`(internal) | macOS 14.4+ |
| 系统 + 麦克风混录(录音中可动态开关麦克风) | `MixedAudioRecorder` / `setMicMixEnabled` | macOS 14.4+ |
| 电平 / 峰值回调、结构化状态回调 | `onLevel` / `onPeakLevel` / `onStateChange` | — |
| 实时 PCM 旁路(供实时转写) | `onAudioBuffer`(音频线程回调) | — |
| 语音转文字(文件 + 实时) | `AppleSpeechEngine`(`TranscriptionEngine` 协议) | **macOS 26+** |
| 加密容器 `.arlock`(AES-256-GCM) | `AudioFileEncryptor` / `AudioCryptoConfig` | macOS 13+ |
| 安全删除、设备指纹 | `SecureDelete` / `DeviceFingerprint` | macOS 13+ |
| C API(句柄式,29 个导出函数) | `Sources/CAPI/AudioRecordSDK.h` | macOS 13+ |

默认输出格式 AAC(M4A,48kHz 立体声)/ WAV(16bit PCM)。导出到 MP3 / FLAC / OGG 在 App 层经 ffmpeg 完成,不属于本 SDK。

## 目录结构

```
AudioRecordKit/
├── Package.swift                 SwiftPM(仅用于独立编译与跑单测)
├── Sources/
│   ├── API/                      公开 Swift API(public):AudioRecordAPI · MediaStream · AudioConstraints · Types · AudioRecordError
│   ├── CAPI/                     C 接口:AudioRecordSDK.h + AudioRecordSDK_C.swift(@_cdecl,句柄式)
│   ├── Transcription/            TranscriptionEngine 协议 · AppleSpeechEngine · Transcript 模型
│   ├── Core/                     内部实现(internal)
│   │   ├── Protocols/            AudioRecorderProtocol · BaseAudioRecorder
│   │   ├── Recorders/            MicrophoneRecorder · MixedAudioRecorder · (ScreenCaptureAudioRecorder 空桩)
│   │   ├── ProcessTap/           CoreAudioProcessTapRecorder · AudioProcessEnumerator · ProcessTapManager
│   │   │                         SwiftProcessTapManager · AggregateDeviceManager · AudioCallbackHandler
│   │   │                         AudioToolboxFileManager · SilentOutputKeepAlive
│   │   ├── Utils/                MicCaptureUnit(AUHAL) · MicDeviceManager
│   │   └── Models/               AudioRecording · RecordingSettings
│   └── Utils/                    Logger · PermissionManager · LevelMonitor · AudioUtils · FileManagerUtils
│                                 AudioFileEncryptor · AudioCryptoConfig · DeviceFingerprint · SecureDelete
│                                 WaveformAmplitudeMapper · L10n · (LoocapTheme)
└── Tests/                        8 个测试文件,约 1.1k 行(模型 / 格式 / 权限 / 日志 / 电平映射 / 错误与约束)
```

链接框架:AVFoundation · CoreAudio · AudioToolbox · IOKit · Speech(CryptoKit 随系统)。

## 分层与调用关系

```
App ──(现状:直连 internal)──▶ Recorders ──▶ ProcessTap 子系统 ──▶ CoreAudio
 │                                 ▲
 └──(设计:public API)──▶ AudioRecordAPI ─┘   (目前仅支持 麦克风 / 系统混音)
```

录制器统一遵循 `AudioRecorderProtocol`(`@MainActor`):

| 回调 | 线程 | 用途 |
|---|---|---|
| `onLevel` / `onPeakLevel` | 主线程 | 电平表 |
| `onStatus` | 主线程 | 仅用于显示的文案,**禁止据此做逻辑判断** |
| `onStateChange(RecordingState)` | 主线程 | 结构化状态(idle/preparing/recording/stopping/playing/error);C API 数值契约 0–3 |
| `onRecordingComplete(AudioRecording)` | 主线程 | 产出临时文件信息 |
| `onAudioBuffer(AVAudioPCMBuffer)` | **音频线程** | 实时转写旁路;消费方自保线程安全,回调内禁止重活 |

## 快速开始(Swift 公开 API)

```swift
import AudioRecordKit

// 仅支持:麦克风 或 系统混音(includeSystemAudio)。指定进程 / 多源请见上文「现状」。
let constraints = AudioConstraints(echoCancellation: true,
                                   noiseSuppression: true,
                                   includeSystemAudio: false)

let api = AudioRecordAPI.shared             // @MainActor, macOS 14.4+
api.onStateChange = { state in print(state) }
api.onRecordingComplete = { recording in print(recording.url) }

let stream = try await api.getUserMedia(constraints: constraints)   // 内部检查并申请麦克风权限
try api.startRecording(stream: stream)
// ...
api.stopRecording()
```

## 权限与沙盒

| 需求 | 配置 |
|---|---|
| 麦克风 | `NSMicrophoneUsageDescription` + `com.apple.security.device.audio-input` |
| 系统 / 进程音频 | `NSAudioCaptureUsageDescription`(TCC「系统音频录制」,首次启动 Tap 时弹窗) |
| 转写 | 首次使用需下载系统语音资产(`AssetInventory`) |

## 构建与测试

```bash
# SDK 单测(SwiftPM,仅 Kit)
cd AudioRecordKit && swift test        # 或在工程根执行 scripts/test_sdk.sh

# 整个 App(Kit + App 平铺编译,主线构建方式)
./build-app.sh
```

## 已知限制 / 注意事项

- `.arlock` 主密钥为编译期常量 + 设备指纹派生:定位为「版权保护层」,**不是 DRM**,对外文案不得宣称「军工级 / 不可破解」。
- 转写仅 macOS 26+;`WhisperCppEngine`(高精模式)尚未实现。
- `ScreenCaptureAudioRecorder` 为废弃空桩;`ProcessTapManager` 与 `SwiftProcessTapManager` 为新旧两套实现并存。
- 部分 Kit 文件仍 `import AppKit`(Types / Logger / FileManagerUtils / PermissionManager / AudioProcessEnumerator / C API),暂不支持无头使用。
- 音频回调热路径中存在调试用 `static var` 计数器(评审 A10)。

## License

MIT
