# MultiTrack 架构设计 — 多应用独立录制与多轨道显示

> 作者：矩·架构师 | 日期：2026-07-11 | 模式：顾问模式
> 输入：用户截图（多选进程 → 单轨道显示 bug）+ REQ-2.0-06 + 录制工作区 Page Spec + P0 交互优化方案
> 范围：录制工作区从「单源单选」到「多源多轨」的完整架构方案
>
> **关联文档**: `../需求/REQ-2.0-06.md` | `../设计/录制工作区-Page-Spec.md` | `../知识库/tech.md` | `V1.1-编辑器技术方案评估.md`
>
> **状态**: 架构设计完成，待 PM·枢 排期 / 铸·开发 执行
> **决策点**: 需先执行 Spike（多 Process Tap 并行可行性验证），再启动 8 天完整实施

---

## 一、背景与动机

### 1.1 用户看到的 bug

```
截图场景:
  - 左侧 App 列表已有 Checkbox（旧 UI），选中了 10+ 个应用
  - TitleBar 显示 "录制目标: TickTick"（单选行为）
  - 波形区只显示 1 条轨道，TickTick 波形几乎为平线
  - 用户期望: 选 N 个 = 显示 N 条独立轨道
```

**根本原因**：四个层都假设 N=1——
1. **SidebarView**: 状态是 `var selectedSource: AudioSourceType?`（单选）
2. **AudioRecorderController**: `activeRecorders` 字典 key 用 `AudioSourceType` 枚举（同一 case 只能存一个 recorder）
3. **WaveformView**: 渲染 `singleLevel` 单 buffer，矩形直接取 `self.bounds`
4. **文件输出**: `outputFileURL: URL?`（单文件）

整条链路从 UI 状态 → 录制引擎 → 渲染 → 落盘全是单数物理结构。不做架构重构，UI 层面加多少层都改不了。

### 1.2 竞品对标

| 维度 | Audio Capture Pro | 剪映 Mac | 我们要做到 |
|------|------------------|---------|-----------|
| 多选方式 | 左侧 Checkbox | — | 边框高亮多选（无 Checkbox） |
| 轨道显示 | App 名 + 迷你电平条 | 轨道头+波形同一行 | **App 名 + 实时填充波形** |
| 录制后 | 仅保存文件 | 直接时间线编辑 | **直接进编辑器（已有）+ 可切多轨** |
| 最大轨道数 | 无限制 | — | **5 轨**（性能硬上限） |

### 1.3 设计方案已存在

REQ-2.0-06（`docs/需求/REQ-2.0-06.md`）已经写好了完整的 Sidebar 多选、轨道等分、录制引擎方案。本文档在此之外新增：
- **RecordingTrack 分层数据模型**（UI 与引擎解耦）
- **MultiTrackRecorderController 引擎重构**（独立于 Recorder 的 Track 管理器）
- **状态机合并设计**（避免单轨/多轨 UI 分裂）
- **Spike 任务清单**（验证最大技术风险）

---

## 二、现状架构诊断

### 2.1 当前录制数据流

```
                        SidebarView
              selectedSource: AudioSourceType?   ← 单值
                            │
                            ▼
                  MainViewController.startRecording()
                            │
                            ▼
              AudioRecorderController
                            │
            activeRecorders: [AudioSourceType: AudioRecorderProtocol]
                            │                    ← 枚举 key，同 case 覆盖
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
   MicrophoneRecorder  SystemRecorder  ProcessTapRecorder(pid)
                            │                    ← 只有一个 PID
                            ▼
              onLevel(singleLevel)                ← 单回调
                            │
                            ▼
              WaveformView → appendLevel()        ← 单 buffer
              LevelMeterCard → updateLevel()      ← 单通道
                            │
                            ▼
              outputFileURL: URL?                 ← 单文件
```

### 2.2 AudioSourceType 枚举的致命限制

```swift
// AudioRecordKit/Sources/API/Types.swift
enum AudioSourceType: Hashable {
    case microphone
    case systemAudio
    case specificProcess       // ← 没有关联值！
}
```

当用户选 Chrome (PID 1234) + WeChat (PID 5678)，两次 `activeRecorders[.specificProcess] = recorder` 的结果是**第二次赋值覆盖第一次**。不是 bug——是架构上本就只能存一个。

### 2.3 四个层的改造范围

| 层 | 当前假设 | 目标假设 | 改造文件数 |
|----|---------|---------|-----------|
| UI 状态 | `AudioSourceType?` | `Set<AudioSource>` | 3 个 |
| 枚举 | `case specificProcess`（无关联值） | `case specificProcess(pid:, name:, bundleID:)` 或字符串 key | 2 个 |
| 引擎 | `[AudioSourceType: Recorder]` | `[Track.ID: Track]`（Track 包装 Recorder） | 3 个 |
| 渲染 | 单 buffer → 全 rect 绘制 | 多 Track × 独立 rect 绘制 | 2 个 |
| 落盘 | `URL?` | `[Track.ID: URL]` + `recording_group.json` | 1 个 |

---

## 三、核心架构设计

### 3.1 架构总览

```
┌─ MultiTrack Architecture ─────────────────────────────────────────────┐
│                                                                        │
│  SidebarView (多选)                                                    │
│    selectedSources: Set<AudioSource>                                   │
│          │                                                             │
│          ▼                                                             │
│  MainViewController                                                    │
│    trackIDs: [UUID]   ← 按选中顺序排列的 Track ID                      │
│          │                                                             │
│          ▼                                                             │
│  MultiTrackRecorderController (NEW)                                    │
│    tracks: [UUID: RecordingTrack]                                      │
│    ┌──────────────────────────────────────────────┐                    │
│    │ RecordingTrack (NEW 核心数据结构)             │                    │
│    │  ├── id: UUID                                  │                    │
│    │  ├── source: AudioSource                       │                    │
│    │  ├── state: TrackState                         │                    │
│    │  ├── fileURL: URL?                             │                    │
│    │  ├── levelBuffer: RingBuffer<Float>             │                    │
│    │  ├── waveformBuffer: RingBuffer<Float>          │                    │
│    │  └── recorder: AudioRecorderProtocol? (内部)    │                    │
│    └──────────────────────────────────────────────┘                    │
│          │                                                             │
│          │ 每个 Track 持有一个 Recorder                                │
│          │                                                             │
│    ┌─────┼─────┬──────────────┬──────────────┐                        │
│    ▼     ▼     ▼              ▼              ▼                        │
│  PTR-1 PTR-2 PTR-3     MicRecorder   SystemRecorder                   │
│  (pid) (pid) (pid)                                                     │
│          │                                                             │
│          │ onLevel(trackID, level)                                      │
│          │ onWaveform(trackID, samples)                                 │
│          │ onTrackStateChange(trackID, newState)                       │
│          ▼                                                             │
│  MultiTrackWaveformView (NEW)                                          │
│    ┌─────────────────────────────────────┐                             │
│    │ Track 0: Chrome            ●        │                             │
│    │ ┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃   │                             │
│    ├─────────────────────────────────────┤                             │
│    │ Track 1: WeChat            ●        │                             │
│    │ ┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃   │                             │
│    ├─────────────────────────────────────┤                             │
│    │ Track 2: 腾讯会议          ●        │                             │
│    │ ┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃   │                             │
│    └─────────────────────────────────────┘                             │
│                                                                        │
│  LevelMeterCard (联动选中轨道)                                          │
│    → 显示 selectedTrackID 对应 Track 的 L/R 电平                       │
│                                                                        │
│  文件输出:                                                              │
│    ~/Documents/AudioRecordings/                                        │
│    ├── 2026-07-11_14-30-00_Chrome.m4a                                  │
│    ├── 2026-07-11_14-30-00_WeChat.m4a                                  │
│    ├── 2026-07-11_14-30-00_腾讯会议.m4a                                │
│    └── 2026-07-11_14-30-00_recording_group.json                       │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### 3.2 RecordingTrack — 核心数据模型（NEW FILE）

**设计原则**：UI 层只认识 `RecordingTrack`，不知道 `AudioRecorderProtocol` 的存在。这是**依赖倒置**——引擎和渲染之间通过 Track 通信，不直接耦合。

```swift
// 新文件: AudioRecordApp/Sources/Recording/RecordingTrack.swift

import Foundation

/// 录制轨道 — 多轨道录制的核心抽象
/// - UI 层持有 track 引用，不直接接触 Recorder
/// - 引擎层通过 track.id 查找对应的 Recorder 操作
/// - 所有跨层通信通过 track 的观察者模式进行
struct RecordingTrack: Identifiable, Hashable {
    let id: UUID
    let source: AudioSource
    var state: TrackState = .pending
    var fileURL: URL?

    // 实时数据缓冲（引擎写入、渲染读取）
    var levelBuffer: RingBuffer<Float>
    var waveformBuffer: RingBuffer<Float>

    // ---- 以下为引擎内部使用，UI 不访问 ----
    var recorder: (any AudioRecorderProtocol)?

    init(source: AudioSource, levelBufferSize: Int = 256, waveformBufferSize: Int = 8192) {
        self.id = UUID()
        self.source = source
        self.levelBuffer = RingBuffer(capacity: levelBufferSize)
        self.waveformBuffer = RingBuffer(capacity: waveformBufferSize)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: RecordingTrack, rhs: RecordingTrack) -> Bool { lhs.id == rhs.id }
}

enum TrackState {
    case pending        // 准备中（Source 已选，Recorder 未创建）
    case recording      // 录制中
    case paused         // 录制暂停（P0 不做，预留）
    case stopping       // 正在停止
    case stopped        // 已停止（文件已落盘）
    case disconnected   // 录制中进程退出 / tap 断连
    case error(String)  // 错误（含描述）
}

// MARK: - RingBuffer

struct RingBuffer<T> {
    private var buffer: [T]
    private var writeIndex: Int = 0
    let capacity: Int
    var count: Int { min(writeIndex, capacity) }

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
    }

    mutating func append(_ value: T) {
        if buffer.count < capacity {
            buffer.append(value)
        } else {
            buffer[writeIndex % capacity] = value
        }
        writeIndex += 1
    }

    func snapshot() -> [T] {
        if buffer.count < capacity { return buffer }
        let pivot = writeIndex % capacity
        return Array(buffer[pivot..<capacity] + buffer[0..<pivot])
    }
}
```

### 3.3 AudioSource — 源描述（改造）

```swift
// 改造: AudioRecordKit/Sources/API/Types.swift
// 从 enum 改为 struct，解除"同 case 只能一个"的限制

struct AudioSource: Hashable {
    enum Kind: Hashable {
        case system
        case microphone
        case process(pid: pid_t, name: String, bundleID: String?)
    }

    let kind: Kind
    var displayName: String {
        switch kind {
        case .system:        return "全部系统声音"
        case .microphone:    return "麦克风"
        case .process(_, let name, _): return name
        }
    }

    var iconName: String {
        switch kind {
        case .system:     return "speaker.wave.3"
        case .microphone: return "mic.fill"
        case .process:    return "app.fill"
        }
    }

    /// 用于 recorder key / 文件命名
    var identifier: String {
        switch kind {
        case .system:     return "system"
        case .microphone: return "microphone"
        case .process(let pid, let name, _): return "process_\(pid)_\(name)"
        }
    }

    /// 验证两个 source 是否是"同一个录制目标"
    func isSameTarget(as other: AudioSource) -> Bool {
        switch (self.kind, other.kind) {
        case (.system, .system), (.microphone, .microphone): return true
        case (.process(let p1, _, _), .process(let p2, _, _)): return p1 == p2
        default: return false
        }
    }
}
```

**关键决策**：`AudioSource` 从 `enum` 改为 `struct`（保留内部 `Kind` 枚举用于匹配）：
- `struct` 可以唯一标识不同 PID 的 process（`isSameTarget` 比较 PID），解决多进程同名问题
- `identifier` 字符串可用作 recorder key 和文件名 sanitize 后的前缀
- 旧代码中用 `switch on AudioSourceType` 的地方需要更新为 `switch on AudioSource.Kind`

**向后兼容策略**：
```swift
// 提供兼容初始化器，旧代码逐步迁移
extension AudioSource {
    static var system: AudioSource {
        AudioSource(kind: .system)
    }
    static var microphone: AudioSource {
        AudioSource(kind: .microphone)
    }
}
```

### 3.4 MultiTrackRecorderController — 录制引擎（NEW FILE）

```swift
// 新文件: AudioRecordApp/Sources/Controllers/MultiTrackRecorderController.swift

/// 多轨道录制控制器 — 管理 N 条独立录制轨道
/// 替代旧 AudioRecorderController 的 [AudioSourceType: Recorder] 字典模式
class MultiTrackRecorderController {
    // MARK: - Track 管理
    private(set) var tracks: [UUID: RecordingTrack] = [:]
    private(set) var trackOrder: [UUID] = []  // 保持选中顺序

    // MARK: - 回调（广播给 UI）
    var onTrackLevel: ((UUID, Float) -> Void)?
    var onTrackWaveform: ((UUID, [Float]) -> Void)?
    var onTrackStateChange: ((UUID, TrackState) -> Void)?

    // MARK: - Track 操作

    func addTrack(source: AudioSource) -> UUID {
        var track = RecordingTrack(source: source)
        tracks[track.id] = track
        trackOrder.append(track.id)
        return track.id
    }

    func removeTrack(id: UUID) {
        stopTrack(id: id)
        tracks.removeValue(forKey: id)
        trackOrder.removeAll(where: { $0 == id })
    }

    func startRecording(trackIDs: [UUID]) throws {
        for id in trackIDs {
            guard var track = tracks[id] else { continue }
            let recorder = try createRecorder(for: track.source)
            track.recorder = recorder
            track.state = .recording
            recorder.start { [weak self] level, samples in
                self?.handleRecorderCallback(trackID: id, level: level, samples: samples)
            }
        }
    }

    func stopAll() {
        for id in trackOrder {
            stopTrack(id: id)
        }
    }

    func stopTrack(id: UUID) {
        guard var track = tracks[id] else { return }
        track.recorder?.stop()
        track.state = .stopped
        track.recorder = nil
    }

    // MARK: - 回调分发

    private func handleRecorderCallback(trackID: UUID, level: Float, samples: [Float]) {
        guard var track = tracks[trackID] else { return }
        track.levelBuffer.append(level)
        for s in samples { track.waveformBuffer.append(s) }

        // 节流到 30fps 分发（避免 60fps 回调全打 UI）
        // 用简单的帧计数，每两帧分发一次
        onTrackLevel?(trackID, level)

        // 波形数据不每帧分发，30fps 汇总
        if frameCount % 2 == 0 {
            onTrackWaveform?(trackID, track.waveformBuffer.snapshot())
        }
    }

    // MARK: - Recorder 工厂

    private func createRecorder(for source: AudioSource) throws -> any AudioRecorderProtocol {
        switch source.kind {
        case .system:
            return SystemAudioRecorder()  // 现有实现
        case .microphone:
            return MicrophoneRecorder()   // 现有实现
        case .process(let pid, _, _):
            // 需要现有 ProcessTapManager 是否支持多实例
            return ProcessTapRecorder(targetPID: pid)
        }
    }
}
```

### 3.5 文件输出

```swift
// 录制停止时，每个 Track 生成独立文件

struct RecordingGroup: Codable {
    let groupID: UUID
    let startedAt: Date
    let endedAt: Date
    let tracks: [TrackFileInfo]
}

struct TrackFileInfo: Codable {
    let trackID: UUID
    let sourceDisplayName: String
    let sourceIdentifier: String
    let fileName: String
    let duration: TimeInterval
    let format: String  // "m4a"
    let sampleRate: Double
}

// 落盘路径
// ~/Documents/AudioRecordings/2026-07-11_14-30-00/
// ├── Chrome.m4a
// ├── WeChat.m4a
// ├── 腾讯会议.m4a
// └── recording_group.json
```

**文件命名 sanitize**：
```swift
extension String {
    var safeFileName: String {
        self.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }
}
```

---

## 四、数据流设计

### 4.1 完整数据流（从选择到落盘）

```
用户操作                      数据流                         文件系统
────────                    ──────────                      ────────

[1] 在 Sidebar 点击 App
    SidebarView.onSourcesChanged([source1, source2])
            │
            ▼
    MainViewController.updateSelectedSources(sources)
            │
            │ 创建 RecordingTrack for each source
            ▼
    MultiTrackRecorderController.addTrack(source1)  → track_1
    MultiTrackRecorderController.addTrack(source2)  → track_2
            │
            │ 更新 UI
            ▼
    MultiTrackWaveformView.reloadTracks([track_1, track_2])
            │
            │ 等分 rects
            ▼
    track_1.rect = (0%..50%, height)  ← 轨道 0
    track_2.rect = (50%..100%, height) ← 轨道 1

[2] 点击 Record ●
    MultiTrackRecorderController.startRecording([track_1.id, track_2.id])
            │
            │ 创建 2 个独立 Recorder
            ▼
    ProcessTapRecorder(pid: 1234) → 写 Chrome.m4a
    ProcessTapRecorder(pid: 5678) → 写 WeChat.m4a
            │
            │ 每帧回调
            ▼
    handleRecorderCallback(track_1, level, samples)
    handleRecorderCallback(track_2, level, samples)
            │
            │ 节流到 30fps 分发 UI
            ▼
    MultiTrackWaveformView:
      updateLevel(trackID: track_1.id, level: 0.45)
      updateLevel(trackID: track_2.id, level: 0.32)
      setNeedsDisplay(track_1.rect)
      setNeedsDisplay(track_2.rect)
            │
            │ 选中 track_1 → 电平表联动
            ▼
    LevelMeterCard.updateLevel(
        L: track_1.levelBuffer.snapshot().left,
        R: track_1.levelBuffer.snapshot().right
    )

[3] 点击 Stop ■
    MultiTrackRecorderController.stopAll()
            │
            │ 每个 Recorder.stop() → flush 文件 → 关闭
            ▼
    ~/Documents/AudioRecordings/2026-07-11_14-30-00/
    ├── Chrome.m4a          ← 完整文件
    ├── WeChat.m4a          ← 完整文件
    └── recording_group.json

[4] 录制完成 → 进入编辑器
    MainViewController.handleRecordingComplete(trackIDs)
            │
            │ 读取 recording_group.json
            │ 加载第一条轨道进编辑器（V2.0 MVP）
            ▼
    enterEditor(file: Chrome.m4a)
    // V2.1: enterMultiTrackEditor(groupID: ...)
```

### 4.2 回调节流策略

```
Recorder 回调频率: 60fps (16.7ms/帧)
  │
  ├──→ Level 数据: 每帧写入 RingBuffer → 30fps 分发 UI 更新
  │    原因: 60fps 电平刷新在人眼看来毫无收益，30fps 足够流畅
  │
  ├──→ Waveform 数据: 每帧写入 RingBuffer → 30fps 汇总一次 snapshot 给渲染
  │    原因: Rendering 用波形 buffer snapshot 独立绘制，不阻塞 Recorder 回调
  │
  └──→ 文件写入: 异步 I/O 队列，主线程零接触
       原因: 5 路 @ 48kHz/32bit 同时写盘，同步 I/O 会导致回调堆积
```

### 4.3 四条路径覆盖

| 路径 | 场景 | 处理 |
|------|------|------|
| 正常 | 3 路正常录制 5 分钟 | 所有 Track 正常走完 → recording_group.json 生成 |
| nil | 选中 1 个进程但该进程无音频输出 | Track 录制正常，波形为平线（静音数据），不报错 |
| 空 | 选中 0 个音源 | 退化为"全部系统声音"（现有默认行为） |
| 错误 | 录制中某进程退出 | `TrackState.disconnected` + 其他 Track 继续 + 文件保留已录部分 |

### 4.4 边界情况数据流

```
场景 1: 录制中进程退出
  ProcessTapRecorder 收到 kAudioProcessPropertyIsRunning = false
    → track.state = .disconnected
    → MultiTrackRecorderController.onTrackStateChange(track.id, .disconnected)
    → MultiTrackWaveformView: 该轨道变灰 + "已断开" 标签
    → 其他轨道继续录制无影响
    → 该轨道文件落盘（已录部分保留）

场景 2: 磁盘空间不足
  Recorder 写入失败
    → track.state = .error("磁盘空间不足")
    → MultiTrackRecorderController.stopAll()  ← 全部停止，不全损
    → 已有文件保留

场景 3: 单个 Track 写入失败
  → 该 track 停止（.error）
    → 其他 Track 继续
    → 提示用户 xxx.m4a 写入失败，但其他文件正常

场景 4: 录制中超 5 轨
  → addTrack() 前检查 tracks.count < 5
    → 拒绝添加: "最多同时录制 5 个音源"
    → 如果已有 5 个，新的点击不生效
```

---

## 五、状态机设计

### 5.1 录制工作区状态机（扩展）

```
                          ┌─────────────────────────────┐
                          │        Idle（空闲）           │
                          │  selectedSources: Set<Source> │
                          │  可以自由增减选择             │
                          └──────────┬──────────────────┘
                                     │ 点击 Record ●
                                     │ 检查 tracks.count
                                     ├── 1 个 → 单轨 recording
                                     ├── 2-5 个 → 多轨 recording
                                     └── 0 个 → 退化为 system recording
                                     ▼
                          ┌─────────────────────────────┐
                          │     Recording（录制中）       │
                          │  - 侧边栏锁定（不可增减选择） │
                          │  - TitleBar 显示 N 轨图标    │
                          │  - MultiTrackWaveformView    │
                          │  - 所有 Track 独立录制       │
                          │  - 点击 Stop ■ → Stopping    │
                          └──────────┬──────────────────┘
                                     │ Stop ■ 或 Error
                                     ▼
                          ┌─────────────────────────────┐
                          │     Stopping（停止中）        │
                          │  - 所有 Recorder.stop()     │
                          │  - flush 文件               │
                          │  - 写 recording_group.json  │
                          └──────────┬──────────────────┘
                                     │ 完成
                                     ▼
                          ┌─────────────────────────────┐
                          │  Complete（录制完成）         │
                          │  → 自动进入编辑器（existing） │
                          │  → Sidebar 恢复可编辑        │
                          └─────────────────────────────┘
```

### 5.2 关键设计决策：不区分单轨/多轨 UI

**不要**这样做：
```
if tracks.count == 1 {
    showSingleTrackUI()    ← 旧 WaveformView 代码
} else {
    showMultiTrackUI()     ← 新 MultiTrackWaveformView 代码
}
```

**原因**：
- 两条代码路径 = 两套维护 = 两套 bug
- 加到第 2 轨时 UI 剧烈切换（波形区域从铺满变成等分），视觉上不连贯
- 未来 V2.1 多轨编辑器依赖 Track 模型，不区分单/多

**替代方案**：统一走 `MultiTrackWaveformView`，1 轨时铺满。

```swift
class MultiTrackWaveformView: NSView {
    func layoutTracks(_ trackIDs: [UUID]) {
        let count = trackIDs.count
        let trackHeight = bounds.height / CGFloat(count)

        for (index, id) in trackIDs.enumerated() {
            let y = CGFloat(index) * trackHeight
            let trackRect = NSRect(x: 0, y: y, width: bounds.width, height: trackHeight)
            trackRects[id] = trackRect
            // 1 轨: trackRect = (0, 0, fullWidth, fullHeight) ← 自然铺满
            // 2 轨: trackRect[0] = 上半, trackRect[1] = 下半
            // 3 轨: 各 1/3 高度
        }
    }
}
```

### 5.3 Sidebar 选择状态机

```
         ┌──────────────────────────────────┐
         │  SidebarView（录制 Tab）           │
         │  selectedSources: Set<AudioSource> │
         │  maxSelection: 5                  │
         └──────────────┬───────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   单击 App       Cmd+单击 App      单击"全部系统声音"
   (替换选中)     (追加选中)         (切换)
        │               │               │
        ▼               ▼               ▼
   selectedSources   选中 > 5?       Toggle
   = [app]           → Toast 提示       .system
                        .isContained?
                        ├─ No → 加
                        └─ Yes → 减

   录制中: 所有选择操作 disabled
   空闲: 自由切换
```

### 5.4 Track 级状态机（单条轨道生命周期）

```
                    ┌──┐
                    │  │ addTrack(source)
                    └┬─┘
                     ▼
              ┌──────────────┐
              │   pending     │
              └──────┬───────┘
                     │ startRecording
                     ▼
              ┌──────────────┐     进程退出
              │  recording    │────────────────────┐
              └──────┬───────┘                    │
                     │ stop                       ▼
                     ▼                   ┌────────────────┐
              ┌──────────────┐           │  disconnected  │  ← 文件保留
              │  stopping     │           └────────────────┘
              └──────┬───────┘
                     │ flush complete
                     ▼
              ┌──────────────┐
              │  stopped      │  ← 文件完整
              └──────────────┘

    任何状态都有可能转入
              ┌──────────────┐
              │  error(msg)  │  ← 磁盘满 / 写入失败 / 权限不足
              └──────────────┘
```

---

## 六、UI 层设计

### 6.1 MultiTrackWaveformView — 等分布局

```
1 轨（铺满）:
┌───────────────────────────────────────────────────┐
│ [AppIcon] Chrome                    ● REC          │ ← 轨道头
│ ┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃  │
│ ─────────────── 中线 ────────────────────────────   │
│ ┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃  │
└───────────────────────────────────────────────────┘

3 轨（各 1/3）:
┌───────────────────────────────────────────────────┐
│ [Chrome]  ● REC                                    │
│ ┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃  │
├───────────────────────────────────────────────────┤
│ [WeChat]  ● REC                                    │
│ ┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃  │
├───────────────────────────────────────────────────┤
│ [腾讯会议] ● REC                                   │
│ ┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃┃  │
└───────────────────────────────────────────────────┘
```

### 6.2 轨道头规范

| 属性 | 值 |
|------|-----|
| 高度 | 20px（录制态波形上方） |
| 内容 | 应用图标（16px SF Symbol）+ 应用名（11px `label`）+ 录制状态圆点（4px 红色） |
| 背景 | `surfaceContainerLow` + 底部分隔线 `outlineVariant` |
| 选中态 | 左边缘 3px `primary` 竖条 |
| 断裂态 | 灰色图标 + "已断开" 文字 (`textTertiary`) |

### 6.3 每条轨道波形渲染

```swift
// 每条轨道独立的 draw 流程
func drawTrack(_ trackID: UUID, in rect: NSRect) {
    guard let track = controller.tracks[trackID] else { return }

    let samples = track.waveformBuffer.snapshot()
    let centerY = rect.midY
    let drawHeight = rect.height * 0.82

    // 使用 P0-1 的填充波形渲染（已有技术方案）
    // 降采样: 采样点数 / 像素宽度 → bucketCount
    let bucketCount = Int(rect.width / (barWidth + barSpacing))
    let buckets = downsampleForFilled(samples: samples, bucketCount: bucketCount)

    let path = buildFilledWaveformPathFromBuckets(
        buckets: buckets,
        in: rect,
        centerY: centerY,
        drawHeight: drawHeight
    )

    // 轨道断开时波形变灰
    let alpha: CGFloat = track.state == .disconnected ? 0.3 : 0.85
    IndustrialColors.waveformCoral.withAlphaComponent(alpha).setFill()
    path.fill()
}
```

### 6.4 Sidebar 多选改造

**从现有 Checkbox UI → 边框高亮多选**

```swift
// SidebarView.swift 改造要点

// 改造前
var selectedSource: AudioSourceType?

// 改造后
var selectedSources: Set<AudioSource> = []
let maxSelection = 5

func toggleSource(_ source: AudioSource, isCommandClick: Bool) {
    guard !isRecording else { return }  // 录制中锁定

    if isCommandClick {
        // Cmd+点击 = 追加/取消
        if selectedSources.contains(where: { $0.isSameTarget(as: source) }) {
            selectedSources.remove(where: { $0.isSameTarget(as: source) })
        } else if selectedSources.count < maxSelection {
            selectedSources.insert(source)
        } else {
            showToast("最多同时录制 5 个音源")
        }
    } else {
        // 单击 = 替换为单选
        selectedSources = [source]
    }
    onSelectionChanged?(Array(selectedSources))
}
```

**App 行渲染变化**：
```swift
// 选中: surfaceContainerHighest 背景 + 2px primaryContainer 边框
// 未选中: surfaceContainerLow 背景 + 1px outlineVariant 边框
// 无 Checkbox 图标
```

### 6.5 TitleBar 录制目标文字

```swift
func updateTitleBarTarget(sources: [AudioSource]) {
    switch sources.count {
    case 0:
        titleLabel.stringValue = "全部系统声音"
    case 1:
        titleLabel.stringValue = sources[0].displayName
    case 2:
        titleLabel.stringValue = "\(sources[0].displayName), \(sources[1].displayName)"
    default:
        titleLabel.stringValue = "\(sources[0].displayName), \(sources[1].displayName) +\(sources.count - 2)"
    }
}
```

---

## 七、分层实施计划

### 实施概览

```
Phase 0: P0 短期止血（1 天）
  │
  ├─→ 去掉 Checkbox，边框高亮多选
  ├─→ TitleBar 多选文字
  └─→ 波形区 hint "V2.0 即将支持"

Phase 1: P1 完整多轨道（8 天）
  │
  ├─→ Day 1: 技术 Spike
  ├─→ Day 2-3: Sidebar + TitleBar 完整多选
  ├─→ Day 4-5: MultiTrackRecorderController + Track 模型
  ├─→ Day 6-7: MultiTrackWaveformView + 电平联动
  └─→ Day 8: 边界情况测试

Phase 2: P2 长期（V2.1+）
  │
  ├─→ MultiTrack Editor（多轨编辑器）
  ├─→ recording_group.json 加载
  └─→ Track 颜色系统（每轨不同颜色）
```

### Phase 0: P0 短期止血（1 天）

| 步骤 | 文件 | 工作量 |
|------|------|--------|
| 去掉 SidebarView Checkbox，边框高亮多选 | `SidebarView.swift` | 3h |
| TitleBar 多选目标文字 | `TitleBarView.swift` | 1h |
| 选中校验（最多 5 个） | `SidebarView.swift` | 0.5h |
| 波形区 hint 文字 "已选 N 个音源，点击录制将同时录 N 轨" | `MainWindowView.swift` | 1h |
| 录制行为退化为"录第一个选中" | `AudioRecorderController.swift` | 1h |
| UI 测试 | — | 1.5h |

### Phase 1: P1 完整多轨道实现（8 天）

| 天数 | 任务 | 产出 |
|------|------|------|
| **Day 1** | **Spike**：多 Process Tap 并行可行性 | Spike 报告（yes/no + 限制 + 性能数据） |
| Day 2 | RecordingTrack + AudioSource 数据模型 | `RecordingTrack.swift`、`Types.swift` 改造 |
| Day 3 | SidebarView 完整多选 + TitleBar 联动 | 多选交互完整实现 |
| Day 4 | MultiTrackRecorderController 引擎 | 引擎层：多 Recorder 管理 + 回调分发 |
| Day 5 | 文件输出（独立文件 + recording_group.json） | 文件管理引入 Track 维度 |
| Day 6 | MultiTrackWaveformView + 等分布局 | 渲染层：多轨并行绘制 |
| Day 7 | 轨道选中 + 电平表联动 + 边界情况 UI | 交互层完善 |
| Day 8 | 集成测试 + 编译验证 + 6 条边界情况覆盖 | quality gate green |

### Phase 2: P2 长期（V2.1+）

- 多轨编辑器（加载 recording_group.json → 每条 Track 独立 Clip 时间线）
- Track 颜色系统（每条 Track 分配不同颜色可视化区分）
- Mute / Solo 接入真实数据流

---

## 八、技术风险评估

| # | 风险 | 等级 | 爆炸半径 | 缓解 | 验证方式 |
|---|------|------|---------|------|---------|
| R1 | **多 Process Tap 并行不支持** | 🔴 高 | 整个 P1 不可行 | Day 1 Spike；不通过则退化为"1 进程 + 1 系统 + 1 Mic = 最多 3 轨" | `ProcessTapManager.createProcessTap` 对 3 个不同 PID 创建，验证 `AudioUnitInitialize` 成功 |
| R2 | 进程退出导致 tap 断连 | 🟡 中 | 单轨断流 | 监听 `kAudioProcessPropertyIsRunning`；其他轨继续 | 模拟 App 退出，验证 TrackState → .disconnected |
| R3 | 5 路 48kHz/32bit 同时写盘 | 🟡 中 | I/O 成为瓶颈 | 独立异步队列；普通 SSD 25MB/s 足够；上 `DispatchIO` | 5 路同时写 1 分钟，观察 write 延迟 |
| R4 | 5 路波形 30fps 渲染 CPU | 🟢 低 | 丢帧 | 每条轨道独立 ring buffer，节流 30fps；总 CPU < 15% | Instruments Time Profiler 录制 5 分钟 |
| R5 | 旧代码 `switch on AudioSourceType` 编译错误 | 🟡 中 | 编译不过 | `AudioSource.Kind` 替代方案；提供兼容 extension | 全量编译，检查所有 switch |
| R6 | 单轨行为回归 | 🟢 低 | 用户体验 | Phase 0 保留旧行为；Phase 1 统一走 MultiTrackWaveformView | QA 回归测试 |

### R1 详细：多 Process Tap 并行 Spike

**要验证的问题**：
1. `AVAudioEngine` 能否对多个不同 PID 创建独立的 `AVAudioMixerNode` tap？
2. 多 tap 之间是否存在优先级冲突或共享 AudioUnit 竞态？
3. 5 路并行时系统资源（AudioUnit 句柄、内存、回调线程数）是否超限？

**Spike 代码骨架**：
```swift
// Spike: 验证多 Process Tap 并行可行性
// 文件: AudioRecordApp/Sources/Debug/MultiTapSpike.swift

func testMultiTapParallel() {
    let pids: [pid_t] = getRandomAudioProcesses(count: 3) // 选 3 个活跃的音频进程
    var taps: [ProcessTapRecorder] = []

    for pid in pids {
        let tap = ProcessTapRecorder(targetPID: pid)
        tap.onError = { error in
            print("[SPIKE] PID \(pid): error = \(error)")
        }
        tap.onLevel = { level in
            print("[SPIKE] PID \(pid): level = \(level)")
        }
        tap.start()
        taps.append(tap)
    }

    // 并行录制 30 秒
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        for tap in taps { tap.stop() }
        print("[SPIKE] 所有 tap 已停止，检查输出文件")
    }
}
```

**Spike 通过标准**：
- [ ] 3 个不同 PID 同时录制 30 秒，无 crash / 无 AudioUnit 错误
- [ ] 输出文件各自独立、可播放、无交叉串扰
- [ ] Instrument Profile：线程数 < 10、内存 < 50MB、CPU < 20%

---

## 九、新旧代码过渡策略

### 9.1 不改旧代码的 Phase 0

Phase 0 只做 Sidebar + TitleBar UI 改造，**AudioRecorderController 不动**：
- 录制时取 `selectedSources.first`（单轨旧行为）
- 剩下选中的应用只是"标记为已选"
- Phase 1 才把录制引擎切到 MultiTrackRecorderController

### 9.2 Phase 1 引入 MultiTrackRecorderController

```swift
// MainViewController.swift 过渡策略

#if MULTITRACK_ENABLED  // 编译标志，Phase 1 统一打开
var recorderController = MultiTrackRecorderController()
#else
var recorderController = AudioRecorderController()  // 旧实现
#endif
```

或更优雅的协议抽象：
```swift
protocol RecordingControllerProtocol {
    func addTrack(source: AudioSource) -> UUID
    func startRecording(trackIDs: [UUID]) throws
    func stopAll()
    var onTrackLevel: ((UUID, Float) -> Void)? { get set }
    var onTrackStateChange: ((UUID, TrackState) -> Void)? { get set }
}

// AudioRecorderController 实现单向适配器
extension AudioRecorderController: RecordingControllerProtocol { ... }
```

### 9.3 废弃路径

| 旧 API | 废弃时间 | 替代 |
|--------|---------|------|
| `AudioSourceType` enum | Phase 1 | `AudioSource` struct |
| `activeRecorders: [AudioSourceType: ...]` | Phase 1 | `tracks: [UUID: RecordingTrack]` |
| `outputFileURL: URL?` | Phase 1 | `RecordingTrack.fileURL` |
| `onLevel(Float)` 单回调 | Phase 1 | `onTrackLevel(UUID, Float)` |

---

## 十、Spike 任务清单（Day 1 必做）

> ⚠️ **不通过 Spike，P1 不启动。这是架构纪律，不是建议。**

| # | 任务 | 预计时间 | 产出 |
|---|------|---------|------|
| S-1 | 编写 `MultiTapSpike.swift`（3 个 PID 并行 Process Tap） | 2h | 可行/不可行 结论 |
| S-2 | Profile：CPU / 内存 / AudioUnit 句柄数 | 1.5h | 性能基线 |
| S-3 | 模拟进程退出（kill 一个 PID 30s 后）→ 验证回调 | 1h | `.disconnected` 是否能触发 |
| S-4 | 验证文件输出独立性（3 个文件无串扰） | 1h | 音频无损交叉 |
| S-5 | 极限测试：5 路并行 60s（最大轨道数） | 1.5h | 5 路可行性 |
| S-6 | 写 Spike 报告（结论 + 限制 + 推荐） | 1h | `docs/架构/multitrack-spike-report.md` |

**总计：1 天（8 工作小时）**

### Spike 出口门禁

- [ ] 多 Process Tap 可行（yes/no + 限制条件明确） → **通过则 P1 启动**
- [ ] 性能基线已记录（CPU < 20%，内存 < 50MB）
- [ ] 进程退出回调已验证（disconnected 可触发）
- [ ] 极限条件已知（最多几路？是否受系统限制？）
- [ ] Spike 报告已写（含代码、数据、结论）

---

## 十一、集成点说明

### 11.1 与已有架构的关系

| 已有系统 | MultiTrack 影响 | 改造方式 |
|---------|----------------|---------|
| V1.0 AudioRecorderController | **废弃**（P1 替换） | MultiTrackRecorderController 接管 |
| V1.0 WaveformView | **保留但不再用于多轨** | 单轨时复用，Phase 1 新增 MultiTrackWaveformView |
| V2.0 TracksView / TrackPanelView | **复用 + 扩展** | 轨道行数 = 选中数，每行显示 Track 信息 |
| V2.0 LevelMeterCard | **改造为可联动** | `selectedTrackID` → LevelMeter 显示对应 Track 电平 |
| V2.0 ViewMode 三态 | **新增 `multiSelecting`** | idle/recording/editing 三态不变，多选是 idle 的子状态 |
| V1.1 EditorViewController | **不改造（V2.0 MVP）** | 录制完成后加载第一轨进编辑器；V2.1 多轨编辑器 |
| MicrophoneRecorder / SystemRecorder | **不改造** | 通过 Recorder 工厂创建 |
| ProcessTapRecorder | **扩展** | 支持多实例 + 进程退出监听 |

### 11.2 与 P0 交互优化文档的关系

`P0-交互优化-技术方案与UI方案.md` 是**编辑器** P0（填充波形、Clip 切分、Fade 拖柄），本文档是**录制工作区** P0。两者**并行，互不阻塞**。

P0-1 的填充波形渲染方法 `buildFilledWaveformPath` 被 MultiTrackWaveformView 直接复用。

---

## 十二、附录

### A. 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| **新增** | `AudioRecordApp/Sources/Recording/RecordingTrack.swift` | Track 数据模型 |
| **新增** | `AudioRecordApp/Sources/Recording/RingBuffer.swift` | 环形缓冲 |
| **新增** | `AudioRecordApp/Sources/Controllers/MultiTrackRecorderController.swift` | 多轨录制引擎 |
| **新增** | `AudioRecordApp/Sources/Views/MultiTrackWaveformView.swift` | 多轨波形视图 |
| **新增** | `AudioRecordApp/Sources/Debug/MultiTapSpike.swift` | Spike 代码 |
| **修改** | `AudioRecordKit/Sources/API/Types.swift` | AudioSourceType → AudioSource struct |
| **修改** | `AudioRecordApp/Sources/Views/SidebarView.swift` | 多选改造 |
| **修改** | `AudioRecordApp/Sources/Views/TitleBarView.swift` | 多源标题 |
| **修改** | `AudioRecordApp/Sources/Controllers/MainViewController.swift` | 集成 MultiTrackRecorderController |
| **修改** | `AudioRecordApp/Sources/Views/MainWindowView.swift` | 替换 WaveformView 为 MultiTrackWaveformView |
| **修改** | `AudioRecordApp/Sources/Views/LevelMeterCard.swift` | 联动 selectedTrackID |

### B. 相关文档索引

- [REQ-2.0-06 多应用同时录音 + 多轨道显示](../需求/REQ-2.0-06.md)
- [录制工作区 Page Spec](../设计/录制工作区-Page-Spec.md)
- [P0 交互优化技术方案](../设计/P0-交互优化-技术方案与UI方案.md)
- [技术知识库](../知识库/tech.md)
- [UX/UI 知识库](../设计/设计规范.md)
- [V1.1 编辑器技术方案评估](V1.1-编辑器技术方案评估.md)

### C. 决策记录（供 MEMORY.md 引用）

| # | 决策 | 理由 | 日期 |
|---|------|------|------|
| D-1 | 不区分单轨/多轨 UI（统一 MultiTrackWaveformView） | 避免两套代码路径分裂，1 轨自然铺满 | 2026-07-11 |
| D-2 | AudioSourceType enum → AudioSource struct（内部保留 Kind enum） | 支持同名进程多实例，struct 可唯一标识不同 PID | 2026-07-11 |
| D-3 | Track 抽象层与 Recorder 解耦（UI 不直接持有 Recorder） | 依赖倒置；V2.1 多轨编辑器直接复用 | 2026-07-11 |
| D-4 | 最大 5 轨硬上限 | 性能/资源/UX 甜区 | 2026-07-11 |
| D-5 | Phase 0 前不启动完整 P1（必须 Spike 先通过） | 多 Process Tap 可行性未验证，不冒 5 天无效开发风险 | 2026-07-11 |

---

> 📐 矩·架构师 | 2026-07-11 | 顾问模式 | 待 PM·枢 排期 & 铸·开发 执行
>
> **下一步**：建议先排 Day 1 Spike（验证多 Process Tap 可行性），通过后再启动 8 天 P1。
> 同时可并行排 Phase 0 短期止血（1 天，不依赖 Spike），解决截图中的 UI bug。
