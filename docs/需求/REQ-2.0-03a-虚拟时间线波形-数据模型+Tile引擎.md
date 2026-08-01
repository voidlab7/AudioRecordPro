# REQ-2.0-03a 虚拟时间线波形 — 数据模型 + Tile 引擎

## 版本：V2.0 | 优先级：P0 | 状态：⬜ 待开发

> 父需求：REQ-2.0-03 剪映式虚拟时间线音频轨道波形展示
> 拆分原因：本子需求聚焦基础数据层，可独立验证，不涉及 UI 改动
> 预估工时：1 天

---

## 1. 一句话需求

新增虚拟时间线波形的核心数据模型（`AudioAsset`、`WaveformTile`、`LODConfig`、`TimelineViewport`）和 Tile 引擎（`WaveformTileProvider`），实现按需分段读取音频、后台生成 peak 数据、内存缓存、LOD 选择和请求取消。

---

## 2. 范围

### In Scope

- 新增 `AudioAsset` 数据模型（元数据，不读 PCM）
- 新增 `WaveformTileKey`、`WaveformPeak`、`WaveformTile` 数据模型
- 新增 `LODConfig`（5 级 LOD 定义 + `selectLOD(pixelsPerSecond:)` 选择逻辑）
- 新增 `TimelineViewport` 视口模型（`visibleStartTime`、`visibleDuration`、`viewWidth`、`pixelsPerSecond`、`requiredTileIndices()`）
- 新增 `WaveformTileProvider`：
  - 接收 viewport 请求，返回已缓存 tiles + 调度后台生成缺失 tiles
  - 后台分段读取 `AVAudioFile`（仅读 tile 对应时间段）
  - Peak 提取算法（min/max/rms）
  - 内存缓存（`NSCache`，200 tiles / 100MB 预算）
  - 请求取消（generation 计数器 + operation cancel）
  - Delegate 回调通知 tile 就绪
- 新增 `WaveformTileProviderDelegate` 协议

### Not in Scope

- 不改动 `EditorWaveformView`（视图层改造在 REQ-2.0-03b）
- 不改动 `EditorViewController`（控制器改造在 REQ-2.0-03b）
- 不实现磁盘缓存（在 REQ-2.0-03c）
- 不处理编辑后 tile 失效（在 REQ-2.0-03d）

---

## 3. 新增文件

| 文件路径 | 职责 |
|---------|------|
| `AudioRecordApp/Sources/Editor/WaveformTile.swift` | `AudioAsset`、`WaveformTileKey`、`WaveformPeak`、`WaveformTile`、`LODConfig` |
| `AudioRecordApp/Sources/Editor/TimelineViewport.swift` | `TimelineViewport` struct |
| `AudioRecordApp/Sources/Editor/WaveformTileProvider.swift` | Tile 引擎：请求、生成、缓存、取消、delegate |

---

## 4. 核心模型定义

### 4.1 AudioAsset

```swift
struct AudioAsset {
    let id: String           // 稳定 ID（文件路径+大小+修改时间+算法版本 hash）
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double
    let channelCount: Int
    let fileSize: Int64
    let modifiedAt: Date
}
```

### 4.2 LODConfig

| LOD | pixelsPerSecond 范围 | samplesPerPeak (48kHz) | tileDuration |
|----:|--------------------:|----------------------:|-------------:|
| 0 | < 1 | 240,000 (5s) | 300s |
| 1 | 1 ~ 5 | 48,000 (1s) | 120s |
| 2 | 5 ~ 30 | 4,800 (0.1s) | 60s |
| 3 | 30 ~ 150 | 960 (0.02s) | 30s |
| 4 | > 150 | 480 (0.01s) | 10s |

### 4.3 WaveformTile

```swift
struct WaveformTile {
    let key: WaveformTileKey
    let sourceStartTime: TimeInterval
    let duration: TimeInterval
    let samplesPerPeak: Int
    let peaks: [WaveformPeak]  // min/max/rms per peak
}
```

### 4.4 TimelineViewport

```swift
struct TimelineViewport {
    var visibleStartTime: TimeInterval
    var visibleDuration: TimeInterval
    var viewWidth: CGFloat
    
    var pixelsPerSecond: CGFloat { viewWidth / CGFloat(visibleDuration) }
    func requiredTileIndices(lodConfig:, totalDuration:, prefetchRatio: 0.5) -> [Int]
}
```

---

## 5. Tile 引擎行为

### 5.1 请求流程

```text
requestTiles(viewport, totalDuration)
  ├── selectLOD(pixelsPerSecond)
  ├── requiredTileIndices(lodConfig, totalDuration, prefetch=0.5)
  ├── 遍历 indices:
  │   ├── 命中内存缓存 → 加入 available
  │   └── 未命中 → 加入 missing
  ├── cancelOutdatedOperations(keepKeys)
  ├── 对 missing 调度后台生成
  └── 返回 available
```

### 5.2 后台生成

- 使用 `OperationQueue`（maxConcurrent = 2）
- 每个 operation：
  1. 检查 generation 是否过期
  2. `AVAudioFile` 定位到 tile 起始帧
  3. 读取 tile 时长对应的帧数到临时 buffer
  4. 提取 peaks（遍历 buffer，每 `samplesPerPeak` 帧计算 min/max/rms）
  5. 构建 `WaveformTile`
  6. 存入内存缓存
  7. 主线程回调 delegate

### 5.3 取消策略

- `currentRequestGeneration: UInt64`，每次 `requestTiles()` 递增
- 后台 operation 开始时检查 generation，过期则 return
- `cancelOutdatedOperations(keepKeys:)` 取消不在当前视口的 pending operations

---

## 6. 验收标准

- [ ] `AudioAsset` 可从文件 URL 正确构建，ID 稳定（同文件同 ID，文件变化后 ID 变化）
- [ ] `LODConfig.selectLOD()` 根据 pixelsPerSecond 正确返回对应级别
- [ ] `TimelineViewport.requiredTileIndices()` 正确计算视口 + 预取范围内的 tile 索引
- [ ] `WaveformTileProvider.requestTiles()` 对已缓存 tile 立即返回
- [ ] 未缓存 tile 在后台生成后通过 delegate 回调
- [ ] Peak 提取结果正确：min ≤ 0、max ≥ 0、rms ≥ 0
- [ ] 快速连续调用 `requestTiles()` 时，旧 generation 的 operation 被取消
- [ ] `cancelAll()` 后无残留回调
- [ ] 内存缓存在 tile 数量超限时自动淘汰
- [ ] 后台生成不阻塞主线程
- [ ] 编译通过

---

## 7. 依赖

- REQ-2.0-01（轨道 + 轨道板模式 UI 重构）— 已完成
- REQ-2.0-02（启动默认录制准备态 UI 重构）

---

## 8. 下游

- REQ-2.0-03b 依赖本需求的 `WaveformTileProvider` 和数据模型
- REQ-2.0-03c 依赖本需求的 `WaveformTileKey` 和 provider 接口
