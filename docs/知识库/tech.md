# 技术知识库

> 更新时间：2026-06-28（根据实际代码校准，补充编辑器高级特性）  
> 来源：从 `../AudioRecordApp知识库.md` 的功能模块地图和底层技术方案拆分。  
> 范围：App 模块、SDK / 底层录制、编辑器架构、文件保存与导出。

## App 层模块

| 模块 | 文件 | 职责 |
|---|---|---|
| 应用入口 | `AudioRecordApp/Sources/App/main.swift` | 单实例检测，启动 AppKit |
| 应用生命周期 | `AudioRecordApp/Sources/App/AppDelegate.swift` | 创建窗口、菜单、权限请求、快捷键、退出清理 |
| 主控制器 | `AudioRecordApp/Sources/Controllers/MainViewController.swift` | 录制、播放、文件、进程、设置、编辑器入口总编排 |
| 录制控制器 | `AudioRecordApp/Sources/Controllers/AudioRecorderController.swift` | 根据 UI 选择创建具体录制器，统一回调 |
| 主窗口 | `AudioRecordApp/Sources/Views/MainWindowView.swift` | 根 UI 容器，连接 Sidebar、波形、控制面板、编辑器 |
| 侧边栏 | `AudioRecordApp/Sources/Views/SidebarView.swift` | 音源选择、进程列表、已录文件列表 |
| 录音列表 | `AudioRecordApp/Sources/Views/RecordedFilesView.swift` | 文件展示、选择、重命名、删除、导出、编辑入口 |
| 波形 | `AudioRecordApp/Sources/Views/WaveformView.swift` | 录制 / 播放用实时波形和静态波形 |
| 控制面板 | `AudioRecordApp/Sources/Views/ControlPanelView.swift` | 计时器、录制、播放、停止 |
| 设置 | `AudioRecordApp/Sources/Views/SettingsWindowController.swift` | 录制格式、采样率、目录、开机启动 |

## 编辑器模块

| 模块 | 文件 | 职责 |
|---|---|---|
| 编辑控制器 | `AudioRecordApp/Sources/Editor/EditorViewController.swift` | 加载音频、执行命令、预览、保存、退出 |
| 命令协议 | `AudioRecordApp/Sources/Editor/EditCommand.swift` | Command 模式、撤销重做历史 |
| 裁剪命令 | `AudioRecordApp/Sources/Editor/TrimCommand.swift` | 裁剪选区 |
| 静音裁剪 | `AudioRecordApp/Sources/Editor/SilenceTrimCommand.swift` | 检测并删除静音段 |
| 标准化 | `AudioRecordApp/Sources/Editor/NormalizeCommand.swift` | 归一化响度 / 峰值 |
| 淡入淡出 | `AudioRecordApp/Sources/Editor/FadeCommand.swift` | 对选区或首尾应用渐变 |
| 编辑波形 | `AudioRecordApp/Sources/Views/Editor/EditorWaveformView.swift` | 文件级波形、缩放、滚动、选区、播放游标 |

## SDK / 底层模块

| 模块 | 文件 | 职责 |
|---|---|---|
| 类型定义 | `AudioRecordKit/Sources/API/Types.swift` | `RecordingState`、`RecordingMode`、`AudioFormat` 等 |
| Swift API | `AudioRecordKit/Sources/API/AudioRecordAPI.swift` | SDK Swift 入口 |
| C API | `AudioRecordKit/Sources/CAPI/AudioRecordSDK_C.swift` | C ABI 导出 |
| 麦克风录制 | `AudioRecordKit/Sources/Core/Recorders/MicrophoneRecorder.swift` | `AVAudioEngine` 输入 tap |

| 混录 | `AudioRecordKit/Sources/Core/Recorders/MixedAudioRecorder.swift` | Process Tap + 麦克风 ring buffer 混合 |
| Process Tap | `AudioRecordKit/Sources/Core/ProcessTap/CoreAudioProcessTapRecorder.swift` | macOS 14.4+ 系统 / 进程音频捕获 |
| 进程枚举 | `AudioRecordKit/Sources/Core/ProcessTap/AudioProcessEnumerator.swift` | 枚举可录制音频进程 |
| 文件工具 | `AudioRecordKit/Sources/Utils/FileManagerUtils.swift` | 保存目录、文件名、恢复、完整性、空间检查 |

## 录制数据流

```text
ControlPanelView.recordButtonClicked()
  ↓ delegate
MainWindowView.controlPanelViewDidStartRecording()
  ↓ delegate
MainViewController.startRecording()
  ↓
AudioRecorderController.startMultiSourceRecording(...)
  ↓
具体 Recorder
  ├─ MicrophoneRecorder
  ├─ CoreAudioProcessTapRecorder
  └─ MixedAudioRecorder
  ↓ callbacks
onLevel / onPeakLevel / onStatus / onRecordingComplete
  ↓
MainWindowView.updateLevel / updatePeakLevel / updateRecordingState
  ↓
WaveformView / LevelMeterCardView / RecordedFilesView
```

## 系统音频与进程音频方案

macOS 14.4+ 使用 CoreAudio Process Tap：

```text
AudioProcessEnumerator
  → ProcessTapManager.createProcessTap
  → AggregateDeviceManager.createAggregateDeviceBindingTap
  → AudioCallbackHandler.globalAudioCallback
  → AudioToolboxFileManager.writeAudioData
  → WAV 文件
```

关键能力：

- 系统混音：`.systemMixdown`
- 指定进程：`.specificProcess`
- 多进程 PID：`setTargetPIDs(_)`
- 进程枚举与过滤：`AudioProcessEnumerator`

最低支持 macOS 14.4，使用 CoreAudio Process Tap，不提供低版本 fallback。

## 编辑器方案

```text
进入编辑器
  → AVAudioFile(forReading: url)
  → AVAudioPCMBuffer 全量加载
  → EditorWaveformView.loadAudio
  → 用户执行 EditCommand
  → audioBuffer 更新
  → EditHistory 记录命令
  → 预览播放 / 保存
```

架构决策：

- `EditorViewController` 独立，不继续膨胀 `MainViewController`。
- `EditorWaveformView` 独立，不复用录制用 `WaveformView`。
- 编辑操作基于内存 `AVAudioPCMBuffer`，V1.1 接受 10 分钟内全内存编辑。
- 撤销重做使用 Command 模式，最大 20 步。

### 编辑器高级特性（V2.1 — 2026-06 已实现）

以下特性已在代码中实装，但之前知识库未记录：

| 特性 | 文件 | 说明 |
|------|------|------|
| 会话池 | `EditorSession.swift` / `EditorSessionManager.swift` | 多文件切换时保留视口状态和选区，避免重新加载 |
| Cross-dissolve 过渡 | `EditorViewController` → `MainWindowView.crossDissolveEditor()` | 200ms 渐变切换，不闪烁 |
| 虚拟时间线 | `TimelineViewport.swift` | 视口驱动的缩放/滚动管理 |
| 磁盘缓存波形 | `WaveformDiskCache.swift` / `WaveformTile.swift` / `WaveformTileProvider.swift` | 大文件分 tile 缓存，减少内存压力 |
| 水平滚动条 | `HorizontalScrollBarView` | 编辑器波形区滚动控件 |
| 编辑器导航栏 | `EditorNavigationBar` | 文件名、撤销/重做按钮、保存/取消 |
| 编辑器工具栏 | `EditorToolbar` | 裁剪、标准化、淡入淡出入口 |
| 编辑器状态栏 | `EditorStatusBar` | 时长/采样率/声道/编辑步数 |
| 预览播放 | `EditorViewController`（内部 `AVAudioEngine` + `AVAudioPlayerNode`） | 编辑器中实时预览效果 |
| 文件大小限制 | EditorViewController.maxEditableFileSize/Duration | 500MB / 30分钟 / 1GB PCM，超限提示 |

编辑器大小限制（代码事实）：
```swift
private let maxEditableFileSize: Int64 = 500 * 1024 * 1024    // 500MB
private let maxEditableDuration: TimeInterval = 30 * 60        // 30分钟
private let maxEditablePCMBytes: Int64 = 1_000 * 1024 * 1024  // 1GB PCM
```

编辑器会话池工作流：
```text
enterEditor(file:)
  → saveCurrentEditorState()  // 保存当前视口/选区到 session
  → sessionManager.session(for: file)  // 获取或创建 session
  → EditorViewController(file:session:)  // 复用缓存数据
  → crossDissolveEditor(to:) / showEditor()
```

## 文件与导出

默认录音目录：

```text
~/Documents/AudioRecordings
```

当前导出语义建议：

| 按钮 | 行为 |
|---|---|
| 导出 | 保存当前文件副本到用户选择目录 |
| 转换格式 | 选择目标格式后编码转换 |
| 分享 | 使用系统分享面板 |

注意：如果代码用 `afconvert input.wav output.mp3 -f mp4f -d aac -q 127`，实际更像 AAC / MP4 容器方向，不是真正 MP3。V1.2 前应避免承诺真实 MP3，或改为 `导出 AAC/M4A`。
