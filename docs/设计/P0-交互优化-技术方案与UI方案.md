# P0 交互优化 — 技术方案 & UI 方案

> 基于竞品对比分析，针对 AudioRecord Mac 编辑器交互体验的三个 P0 差距制定。
> 核心目标：波形从"只读视图"升级为"可操作画布"。

**专项代号**: P0-INTERACTION  
**文档版本**: v1.0  
**创建日期**: 2026-06-28  

---

## 目录

1. [P0-1: 波形渲染升级 — 柱状 → 填充波形](#p0-1)
2. [P0-2: Clip 切分 + 拖拽裁剪](#p0-2)
3. [P0-3: 淡入淡出可视化拖柄](#p0-3)
4. [集成方案 — 三者的协同关系](#集成方案)
5. [风险评估](#风险评估)

---

## 总览

```
当前状态:  柱状波形 + 无 Clip 概念 + 按钮式 Fade
目标状态:  填充波形 + Clip 切分/拖裁 + 可视化拖柄 Fade
```

| P0 项 | 改造范围 | 新增文件 | 修改文件 | 预计工期 |
|-------|---------|---------|---------|---------|
| P0-1 填充波形 | 渲染层 | 1 个 | 3 个 | 1.5 天 |
| P0-2 Clip 编辑 | 数据层+交互层+UI | 3 个 | 4 个 | 3 天 |
| P0-3 Fade 拖柄 | 渲染层+交互层 | 0 个 | 3 个 | 1 天 |
| **合计** | — | **4 个** | **7 个** | **5.5 天** |

---

<a id="p0-1"></a>
## P0-1: 波形渲染升级 — 柱状 → 填充波形（Filled Waveform）

### 一、现状分析

#### 1.1 当前渲染模式

所有波形视图使用**柱状（Bar-style）渲染**：

```swift
// WaveformView.swift:489-531 — drawWaveform(in:)
// EditorWaveformView.swift:560-589 — drawWaveformBars(in:)
// EditorWaveformView.swift:770-812 — drawWaveformTiles(in:)

// 核心逻辑:
let barRect = NSRect(x: x, y: centerY - amplitude, width: barWidth, height: amplitude * 2)
let path = NSBezierPath(roundedRect: barRect, xRadius: 0.8, yRadius: 0.8)
IndustrialColors.waveformCoral.withAlphaComponent(alpha).setFill()
path.fill()
```

**特征**:
- 每个采样点绘制一个独立圆角矩形柱
- 柱宽 1.2px，间距 2.2px（含柱宽），步长 3.4px
- 从中线（centerY）对称向上下扩展 `amplitude`
- 视觉上呈现为**离散柱状条**，采样点之间有间隙

**问题**:
1. 柱间有空隙，视觉密度低，不"专业"
2. 离散柱无法表达波形连续形态
3. 竞品（剪映/DaVinci/Logic Pro）使用**上下对称填充路径**，视觉信息密度高出 3-5 倍

#### 1.2 需要修改的文件

| 文件 | 改动 |
|------|------|
| `WaveformView.swift` | 修改 `drawWaveform(in:)` 和 `drawStaticWaveform(in:)` |
| `EditorWaveformView.swift` | 修改 `drawWaveformBars(in:)` 和 `drawWaveformTiles(in:)` |
| `EditorWaveformView.swift` | 新增 `drawFilledWaveform(in:)` 方法 |

### 二、UI 方案

#### 2.1 视觉目标

```
竞品效果（填充波形）:
┌─────────────────────────────────────────┐
│ ▐███▌        ▐████▌      ▐██▌         │ ← 上包络（upper envelope）
│ ▐████▌  ▐█▌  ▐█████▌ ▐█▌ ▐███▌ ▐▌    │    波形填充区域
│ ▐█████▌▐███▌▐███████▌▐██▌▐████▌▐█▌   │
│ ▐██████████████████████████████████▌   │
│ ▐██████████████████████████████████▌   │    珊瑚红填充
│─────────────────────────────────────   │ ← 中线（极淡参考线）
│ ▐██████████████████████████████████▌   │
│ ▐█████▌▐███▌▐███████▌▐██▌▐████▌▐█▌   │
│ ▐████▌  ▐█▌  ▐█████▌ ▐█▌ ▐███▌ ▐▌    │
│ ▐███▌        ▐████▌      ▐██▌         │ ← 下包络（lower envelope）
└─────────────────────────────────────────┘

当前效果（柱状波形）:
┌─────────────────────────────────────────┐
│   ▐█▌    ▐█▌  ▐█▌    ▐█▌ ▐█▌  ▐▌     │ ← 离散柱，间隙明显
│   ▐█▌  ▐▌▐█▌▐█▌▐█▌  ▐▌▐█▌▐█▌  ▐▌   │
│   ▐██▌▐█▌▐█▌▐█▌▐█▌ ▐█▌▐█▌▐█▌ ▐█▌   │
│─────────────────────────────────────   │
│   ▐██▌▐█▌▐█▌▐█▌▐█▌ ▐█▌▐█▌▐█▌ ▐█▌   │
│   ▐█▌  ▐▌▐█▌▐█▌▐█▌  ▐▌▐█▌▐█▌  ▐▌   │
│   ▐█▌    ▐█▌  ▐█▌    ▐█▌ ▐█▌  ▐▌     │
└─────────────────────────────────────────┘
```

#### 2.2 视觉规范

| 属性 | 值 | 说明 |
|------|-----|------|
| **填充颜色** | `waveformCoral` (#FF6B5F) alpha 0.85 | 主体填充 |
| **包络线颜色** | `waveformCoral` (#FF6B5F) alpha 1.0 | 上下边缘 |
| **包络线宽** | 1.0px | |
| **中线颜色** | `gridMedium` alpha 0.08 | 极淡参考线 |
| **中线样式** | 虚线 `[3, 8]` | |
| **选区外遮罩** | `editorDimOverlay` alpha 0.35 | 非选区区域降低亮度 |
| **选区内填充** | 正常颜色 | 不受 dim 影响 |
| **已播放区域** | `waveformCoral` alpha 0.55 | 播放进度回调 |
| **未播放区域** | `waveformCoral` alpha 0.30 | 预加载波形 |

#### 2.3 缩放级别适配

| 缩放级别 | pixelsPerSecond | 绘制策略 |
|----------|----------------|---------|
| **远距** (zoom < 2x) | < 40 | 降采样填充路径 — 每 bucket 取 min/max 作为上下包络 |
| **中距** (2x ≤ zoom < 50x) | 40~1000 | 逐采样填充路径 — 数据点足够，绘制连续曲线 |
| **近距** (zoom ≥ 50x) | > 1000 | 逐采样精确绘制 — 高精度，可看到样本级细节 |

### 三、技术方案

#### 3.1 核心思想

将原有的"一个采样点 → 一个矩形柱"改为"所有采样点 → 一条上包络路径 + 一条下包络路径 → 两条路径围成的填充区域"。

#### 3.2 新数据结构：`WaveformEnvelope`

不用新增文件，在 `EditorWaveformView.swift` 和 `WaveformView.swift` 中增加辅助方法：

```swift
/// 从采样数据构建上下包络路径
/// - Parameters:
///   - samples: 归一化采样数据 [0~1]
///   - rect: 绘制区域
///   - centerY: 中线 y 坐标
///   - drawHeight: 波形绘制高度
/// - Returns: 上包络路径 + 下包络路径（合并为一个 filled path）
func buildFilledWaveformPath(
    samples: [Float],
    in rect: NSRect,
    centerY: CGFloat,
    drawHeight: CGFloat
) -> NSBezierPath {
    let path = NSBezierPath()
    let pixelsPerSample = rect.width / CGFloat(samples.count)
    
    // Step 1: 构建上包络点数组（从左到右）
    var upperPoints: [CGPoint] = []
    for (i, sample) in samples.enumerated() {
        let x = rect.minX + CGFloat(i) * pixelsPerSample
        let y = centerY + CGFloat(sample) * drawHeight * 0.48
        upperPoints.append(CGPoint(x: x, y: y))
    }
    
    // Step 2: 构建下包络点数组（从右到左，镜像）
    var lowerPoints: [CGPoint] = []
    for (i, sample) in samples.enumerated().reversed() {
        let x = rect.minX + CGFloat(i) * pixelsPerSample
        let y = centerY - CGFloat(sample) * drawHeight * 0.48
        lowerPoints.append(CGPoint(x: x, y: y))
    }
    
    // Step 3: 组合路径：左上 → 右上 → 右下 → 左下 → 闭合
    guard let first = upperPoints.first else { return path }
    path.move(to: first)
    for pt in upperPoints.dropFirst() { path.line(to: pt) }
    for pt in lowerPoints { path.line(to: pt) }
    path.close()
    
    return path
}
```

#### 3.3 降采样填充算法（远距缩放）

当 `sampleCount >> visibleBars` 时，每个像素跨度对应多个采样点。需要为每个像素列提取 min/max 值：

```swift
struct FilledBucket {
    let minAmplitude: Float
    let maxAmplitude: Float
}

func downsampleForFilled(
    samples: [Float],
    bucketCount: Int
) -> [FilledBucket] {
    guard bucketCount > 0, !samples.isEmpty else { return [] }
    let samplesPerBucket = max(1, samples.count / bucketCount)
    var buckets: [FilledBucket] = []
    buckets.reserveCapacity(bucketCount)
    
    for i in 0..<bucketCount {
        let start = i * samplesPerBucket
        let end = min(start + samplesPerBucket, samples.count)
        guard start < end else { break }
        
        var minVal: Float = 1.0
        var maxVal: Float = 0.0
        for j in start..<end {
            let s = samples[j]
            if s < minVal { minVal = s }
            if s > maxVal { maxVal = s }
        }
        buckets.append(FilledBucket(minAmplitude: minVal, maxAmplitude: maxVal))
    }
    return buckets
}
```

降采样后的路径构建同样使用 minAmplitude 作为下包络、maxAmplitude 作为上包络，确保所有采样点都被包络覆盖。

#### 3.4 修改 `drawWaveform(in:)` (WaveformView.swift)

```swift
// 替换原有的 bar-based 绘制逻辑
// WaveformView.swift ~line 489

private func drawWaveform(in rect: NSRect) {
    guard !waveformData.isEmpty else { return }
    
    let timelineInsetX: CGFloat = 84
    let timelineRect = NSRect(
        x: timelineInsetX,
        y: 42,
        width: max(1, rect.width - timelineInsetX * 2),
        height: max(1, rect.height - 88)
    )
    let centerY = rect.midY
    let drawHeight = min(maxBarHeight, timelineRect.height * 0.82)
    let step = barWidth + barSpacing
    let maxVisibleBars = Int(floor(timelineRect.width / step))
    
    let startIndex = max(0, waveformData.count - maxVisibleBars)
    let visibleData = Array(waveformData[startIndex...])
    
    // 新：构建填充波形路径
    let path = buildFilledWaveformPath(
        samples: visibleData,
        in: timelineRect,
        centerY: centerY,
        drawHeight: drawHeight
    )
    
    // 填充主体
    IndustrialColors.waveformCoral.withAlphaComponent(0.85).setFill()
    path.fill()
    
    // 包络线（可选 — 视觉质感）
    IndustrialColors.waveformCoral.withAlphaComponent(1.0).setStroke()
    path.lineWidth = 1.0
    path.stroke()
}
```

#### 3.5 修改 `drawWaveformBars(in:)` (EditorWaveformView.swift)

编辑器使用相同方案。需注意：
- 需要处理视口裁剪（只绘制可见范围内的采样点）
- 选区外需叠加 dim overlay（`drawSelectionOverlay` 已存在，无需改）
- 需支持已播放/未播放两种颜色

```swift
// EditorWaveformView.swift ~line 560

private func drawFilledWaveform(in rect: NSRect) {
    guard !allSamples.isEmpty, visibleDuration > 0 else { return }
    
    let centerY = waveformRect.midY
    let drawHeight = waveformRect.height * 0.82
    
    // 计算可见范围内的采样点索引
    let startIndex = Int(Double(allSamples.count) * visibleStartTime / totalDuration)
    let endIndex = min(allSamples.count,
        Int(Double(allSamples.count) * (visibleStartTime + visibleDuration) / totalDuration))
    let visibleSamples = Array(allSamples[startIndex..<endIndex])
    guard !visibleSamples.isEmpty else { return }
    
    // 降采样适配
    let visibleBars = Int(waveformRect.width / (barWidth + barSpacing))
    let buckets = downsampleForFilled(samples: visibleSamples, bucketCount: visibleBars)
    
    // 构建上下包络路径
    let path = buildFilledWaveformPathFromBuckets(
        buckets: buckets,
        in: waveformRect,
        centerY: centerY,
        drawHeight: drawHeight
    )
    
    // 填充
    IndustrialColors.waveformCoral.withAlphaComponent(0.85).setFill()
    path.fill()
    IndustrialColors.waveformCoral.setStroke()
    path.lineWidth = 1.0
    path.stroke()
}
```

#### 3.6 录制实时波形优化

录制时波形数据从右向左滚动，每帧数据量小（~260 采样点）。可直接逐点构建填充路径，不需要降采样：

```swift
// 录制态特殊处理：数据量小，直接绘制，不需要降采样
// 采样点间隔用 step = barWidth + barSpacing 计算 x 坐标
// buildFilledWaveformPath 中使用 step 而非 pixelsPerSample
```

#### 3.7 Tile 模式兼容

`drawWaveformTiles(in:)` 的改造思路相同 —— 将 tile 内的 peaks 数组转换为填充路径。每个 tile 独立构建路径，但需确保 tile 边界连续：

```swift
// 每个 tile 独立绘制（路径在 tile 范围内），tile 间有微小间隙不影响
// 因为 tiles 的 sourceStartTime 是连续的
for tile in currentTiles {
    // 将 tile.peaks 转换为填充路径
    let tileRect = NSRect(
        x: timeToPixel(tile.sourceStartTime),
        y: waveformRect.minY,
        width: CGFloat(tile.duration / visibleDuration) * waveformRect.width,
        height: waveformRect.height
    )
    let path = buildFilledWaveformPath(samples: tile.peaks.map { $0.amplitude },
                                        in: tileRect, centerY: waveformRect.midY,
                                        drawHeight: waveformRect.height * 0.82)
    // ... fill + stroke
}
```

---

<a id="p0-2"></a>
## P0-2: Clip 切分 + 拖拽裁剪（Clip-based Editing）

### 一、现状分析

#### 1.1 当前模式：选区 + 按钮

编辑流程：
1. 在波形上拖拽创建选区（选区手柄可见）
2. 点击工具栏"裁剪"按钮
3. `TrimCommand` 执行裁剪（保留选区内容，丢弃选区外）
4. 撤销/重做由 `EditHistory` 管理

**问题**:
- 选区只是一个时间范围，没有"片段"的概念
- 无法将音频切分成多个独立片段
- 无法在片段之间分离/移动
- 裁剪后选区消失，无法继续处理其他片段
- 拖拽波形边缘无法直接裁剪（只能先选后按按钮）

#### 1.2 需要创建/修改的文件

| 文件 | 类型 | 说明 |
|------|------|------|
| `AudioClip.swift` | **新增** | Clip 数据模型 |
| `ClipTimeline.swift` | **新增** | Clip 时间线管理器 |
| `SplitCommand.swift` | **新增** | 切分命令 |
| `EditorWaveformView.swift` | 修改 | 新增 Clip 渲染层 + 边缘拖拽交互 |
| `EditorViewController.swift` | 修改 | 集成 ClipTimeline，响应切分/裁剪 |
| `EditToolbarView.swift` | 修改 | 新增加 Split 按钮 |
| `TrimCommand.swift` | 修改 | 支持 Clip 级裁剪 |

### 二、Clip 数据模型设计

#### 2.1 `AudioClip` — 音频片段

```swift
// 新文件: AudioRecordApp/Sources/Editor/AudioClip.swift

/// 音频片段 — 编辑器中的最小可操作单元
struct AudioClip: Identifiable {
    let id: UUID
    
    /// 剪辑在原始音频中的起始时间（秒）
    var sourceStartTime: TimeInterval
    
    /// 剪辑的时长（秒）
    var duration: TimeInterval
    
    /// 原始音频中的结束时间（计算属性）
    var sourceEndTime: TimeInterval { sourceStartTime + duration }
    
    /// 剪辑名称（可选，用于轨道上显示）
    var name: String?
    
    /// 剪辑颜色（用于多片段视觉区分）
    var color: NSColor
    
    init(
        sourceStartTime: TimeInterval,
        duration: TimeInterval,
        name: String? = nil,
        color: NSColor = IndustrialColors.waveformCoral
    ) {
        self.id = UUID()
        self.sourceStartTime = sourceStartTime
        self.duration = duration
        self.name = name
        self.color = color
    }
}

extension AudioClip: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AudioClip, rhs: AudioClip) -> Bool { lhs.id == rhs.id }
}
```

#### 2.2 `ClipTimeline` — 片段时间线

```swift
// 新文件: AudioRecordApp/Sources/Editor/ClipTimeline.swift

/// 片段时间线 — 管理所有 clip 的排列和操作
class ClipTimeline {
    /// 按 sourceStartTime 升序排列的 clip 列表
    private(set) var clips: [AudioClip] = []
    
    /// 原始音频总时长
    let totalDuration: TimeInterval
    
    /// 当 clips 变化时通知 UI
    var onClipsChanged: (() -> Void)?
    
    init(totalDuration: TimeInterval) {
        self.totalDuration = totalDuration
        // 初始状态：整个音频是一个 clip
        self.clips = [AudioClip(sourceStartTime: 0, duration: totalDuration)]
    }
    
    // MARK: - 切分操作
    
    /// 在指定时间点切分 clip
    /// - Returns: 被切分的 clip 索引 + 新 clip，若时间点不在任何 clip 内返回 nil
    func split(at time: TimeInterval) -> (clipIndex: Int, newClip: AudioClip)? {
        guard let index = clipIndex(at: time) else { return nil }
        let clip = clips[index]
        guard time > clip.sourceStartTime && time < clip.sourceEndTime else { return nil }
        
        let firstDuration = time - clip.sourceStartTime
        let secondStart = time
        let secondDuration = clip.sourceEndTime - time
        
        // 更新原 clip 的时长
        clips[index] = AudioClip(
            sourceStartTime: clip.sourceStartTime,
            duration: firstDuration,
            name: clip.name,
            color: clip.color
        )
        
        // 创建新 clip
        let newClip = AudioClip(
            sourceStartTime: secondStart,
            duration: secondDuration,
            name: nil,
            color: clip.color.withAlphaComponent(0.85) // 微调颜色区分
        )
        clips.insert(newClip, at: index + 1)
        
        onClipsChanged?()
        return (index, newClip)
    }
    
    // MARK: - 裁剪操作
    
    /// 裁剪 clip 的起始时间（从左侧拖拽）
    func trimLeft(clipId: UUID, newStartTime: TimeInterval) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == clipId }),
              newStartTime >= 0,
              newStartTime < clips[index].sourceEndTime else { return false }
        
        let clip = clips[index]
        let newDuration = clip.sourceEndTime - newStartTime
        clips[index] = AudioClip(
            sourceStartTime: newStartTime,
            duration: newDuration,
            name: clip.name,
            color: clip.color
        )
        onClipsChanged?()
        return true
    }
    
    /// 裁剪 clip 的结束时间（从右侧拖拽）
    func trimRight(clipId: UUID, newEndTime: TimeInterval) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == clipId }),
              newEndTime > clips[index].sourceStartTime,
              newEndTime <= totalDuration else { return false }
        
        let clip = clips[index]
        clips[index] = AudioClip(
            sourceStartTime: clip.sourceStartTime,
            duration: newEndTime - clip.sourceStartTime,
            name: clip.name,
            color: clip.color
        )
        onClipsChanged?()
        return true
    }
    
    // MARK: - 查询
    
    func clipIndex(at time: TimeInterval) -> Int? {
        clips.firstIndex(where: { $0.sourceStartTime <= time && time < $0.sourceEndTime })
    }
    
    func clip(at time: TimeInterval) -> AudioClip? {
        clips.first(where: { $0.sourceStartTime <= time && time < $0.sourceEndTime })
    }
    
    // MARK: - 导出
    
    /// 将所有 clips 按顺序导出为 PCM buffer（静音区域填充 0）
    func exportToPCMBuffer(from originalBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // 按 sourceStartTime 排序，中间的空隙填充静音
        // 结果 buffer 时长 = totalDuration（若尾部有裁剪则缩短）
        // ... 实现细节见代码
        return nil // TODO
    }
}
```

### 三、UI 方案

#### 3.1 编辑器布局变更

```
当前编辑器布局:
┌────────────────────────────────────────┐
│  EditorNavigationBar (44px)            │
├─────────┬──────────────────────────────┤
│ Sidebar │  EditorWaveformView          │
│ (260px) │  ┌────────────────────────┐  │
│         │  │ Time Ruler             │  │
│         │  ├────────────────────────┤  │
│         │  │ Waveform Area          │  │
│         │  │  (单一选区拖柄)        │  │
│         │  └────────────────────────┘  │
│         │  EditorToolbar (36px)        │
│         │  EditorStatusBar (24px)      │
└─────────┴──────────────────────────────┘

P0-2 后新增:
┌────────────────────────────────────────┐
│  EditorNavigationBar (44px)            │
├─────────┬──────────────────────────────┤
│ Sidebar │  EditorWaveformView          │
│ (260px) │  ┌────────────────────────┐  │
│         │  │ Time Ruler             │  │
│         │  ├────────────────────────┤  │
│         │  │ Waveform + Clip 叠加   │  │
│         │  │  clip0 │ clip1 │ cli2  │ ← Clip 分界线（虚线） │
│         │  │  ◄▬▬▬►  ◄▬▬▬► ◄▬▬►  │ ← Clip 边缘拖柄 │
│         │  └────────────────────────┘  │
│         │  EditorToolbar              │
│         │  [✂ Split] [裁剪] [标准化]  │ ← 新增 Split 按钮 │
│         │  EditorStatusBar            │
└─────────┴──────────────────────────────┘
```

#### 3.2 Clip 分界线渲染

```swift
// 在 draw(in:) 中新增:
// Layer 8 (after playhead, before selection handles): Clip 分界线

func drawClipBoundaries(in rect: NSRect) {
    guard clipTimeline.clips.count > 1 else { return } // 只有一个 clip 时不显示
    
    for clip in clipTimeline.clips {
        // 不需要画 clip 0 的左边界和最后一个 clip 的右边界
        // 只画 clip 间的分界线
        
        if clip.sourceStartTime > 0 {
            let x = timeToPixel(clip.sourceStartTime)
            guard x > waveformRect.minX && x < waveformRect.maxX else { continue }
            
            // 白色虚线，alpha 0.4
            IndustrialColors.gridMedium.withAlphaComponent(0.4).setStroke()
            let line = NSBezierPath()
            line.lineWidth = 1.0
            line.setLineDash([4, 4], count: 2, phase: 0)
            line.move(to: NSPoint(x: x, y: waveformRect.minY + 4))
            line.line(to: NSPoint(x: x, y: waveformRect.maxY - 4))
            line.stroke()
            
            // 分界线下方标签（可选）
            // "✂" 图标或 clip 名称
        }
    }
}
```

#### 3.3 Clip 边缘拖柄

在每个 clip 的左右边缘显示可拖拽的拖柄：

```
◄▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬►
↑                                ↑
左侧拖柄 (cyan)                  右侧拖柄 (cyan)
- 拖拽 = 裁剪 clip 左侧          - 拖拽 = 裁剪 clip 右侧
- cursor: resizeLeftRight        - cursor: resizeLeftRight
- hit zone: ±8px                 - hit zone: ±8px
```

```swift
// 与现有选区拖柄共存的方案:
// 当有多个 clip 时，选区拖柄仍可用（跨 clip 选区）
// clip 边缘拖柄优先级高于选区拖柄（更窄的命中区域）

func drawClipEdgeHandles(in rect: NSRect) {
    guard clipTimeline.clips.count > 1 else { return } // 只有一个 clip 不需要边缘拖柄
    
    let handleColor = IndustrialColors.editorHandle // 复用现有 cyan 色
    let handleWidth: CGFloat = 4.0
    
    for clip in clipTimeline.clips {
        // 左侧拖柄（非 clip[0] 的左边界）
        if clip.sourceStartTime > 0 {
            let x = timeToPixel(clip.sourceStartTime) - handleWidth / 2
            let handleRect = NSRect(x: x, y: waveformRect.minY + 8,
                                     width: handleWidth, height: waveformRect.height - 16)
            handleColor.setFill()
            NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
        }
        
        // 右侧拖柄（非最后一个 clip 的右边界）
        if clip.sourceEndTime < clipTimeline.totalDuration {
            let x = timeToPixel(clip.sourceEndTime) - handleWidth / 2
            let handleRect = NSRect(x: x, y: waveformRect.minY + 8,
                                     width: handleWidth, height: waveformRect.height - 16)
            handleColor.setFill()
            NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
        }
    }
}
```

#### 3.4 Split 按钮

在 `EditToolbarView` 中增加切分按钮：

```
[✂ 切分] ... 会在播放头位置将当前 clip 一分为二
```

按钮状态：
- 无 clip 在播放头位置 → disabled
- 播放头正好在 clip 边界 → disabled
- 正常 → enabled

快捷键：`S`（业界标准）

### 四、交互状态机

#### 4.1 扩展 DragMode 枚举

```swift
// EditorWaveformView.swift ~line 43

enum DragMode {
    case none
    case panScroll          // 平移滚动（现有）
    case leftHandle          // 选区左拖柄（现有）
    case rightHandle         // 选区右拖柄（现有）
    case seeking             // seek 播放头（现有）
    case creating            // 创建选区（现有）
    
    // 新增 P0-2:
    case clipLeftEdge       // 拖拽 clip 左边缘（裁剪起始）
    case clipRightEdge      // 拖拽 clip 右边缘（裁剪结束）
}
```

#### 4.2 鼠标事件优先级

```
mouseDown 命中测试优先级（从高到低）:
1. Clip 边缘拖柄（±5px）        → clipLeftEdge / clipRightEdge
2. 选区拖柄（±8px）             → leftHandle / rightHandle
3. 波形区域                     → seeking（拖拽超阈值后 → creating）
```

```swift
// EditorWaveformView.swift ~line 673

override func mouseDown(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    dragStartX = location.x
    
    // Layer 1: Clip 边缘拖柄检测（新）
    if let clipEdge = hitTestClipEdge(at: location.x) {
        switch clipEdge {
        case .left(let clipId):
            dragMode = .clipLeftEdge
            activeClipId = clipId
            return
        case .right(let clipId):
            dragMode = .clipRightEdge
            activeClipId = clipId
            return
        }
    }
    
    // Layer 2: 选区拖柄检测（现有）
    if let sel = selection { /* ... 现有逻辑 ... */ }
    
    // Layer 3: 波形区域（现有）
    let time = max(0, min(pixelToTime(location.x), totalDuration))
    dragCreateStartTime = time
    dragMode = .seeking
    playbackTime = time
    needsDisplay = true
    delegate?.editorWaveformView(self, didSeekTo: time)
}

// 新增辅助方法
enum ClipEdge { case left(clipId: UUID), right(clipId: UUID) }

func hitTestClipEdge(at x: CGFloat) -> ClipEdge? {
    guard clipTimeline.clips.count > 1 else { return nil }
    let time = pixelToTime(x)
    let hitZone: TimeInterval = 0.05 // 秒
    
    for clip in clipTimeline.clips {
        if clip.sourceStartTime > 0,
           abs(time - clip.sourceStartTime) < hitZone {
            return .left(clipId: clip.id)
        }
        if clip.sourceEndTime < clipTimeline.totalDuration,
           abs(time - clip.sourceEndTime) < hitZone {
            return .right(clipId: clip.id)
        }
    }
    return nil
}
```

### 五、技术实现细节

#### 5.1 `SplitCommand` — 切分命令

```swift
// 新文件: AudioRecordApp/Sources/Editor/SplitCommand.swift

/// 切分命令 — 在指定时间点将当前 clip 一分为二
/// 此命令主要操作的是 ClipTimeline 状态（非 PCM buffer）
/// 因此需要特殊的 undo 机制

class SplitCommand {
    let description: String
    let splitTime: TimeInterval
    let originalClipId: UUID
    
    init(splitTime: TimeInterval, clipId: UUID) {
        self.splitTime = splitTime
        self.originalClipId = clipId
        self.description = "切分 @ \(String(format: "%.2f", splitTime))s"
    }
    
    /// 执行切分（修改 ClipTimeline）
    func execute(on timeline: ClipTimeline) -> Bool {
        return timeline.split(at: splitTime) != nil
    }
    
    /// 撤销切分（合并相邻 clips）
    func undo(on timeline: ClipTimeline, mergingInto clipId: UUID) -> Bool {
        // 找到 splitTime 两侧的 clips
        guard let leftIndex = timeline.clips.firstIndex(where: {
            $0.sourceEndTime == splitTime
        }),
        let rightClip = timeline.clips.first(where: {
            $0.sourceStartTime == splitTime
        }) else { return false }
        
        let leftClip = timeline.clips[leftIndex]
        let mergedDuration = leftClip.duration + rightClip.duration
        
        timeline.clips[leftIndex] = AudioClip(
            sourceStartTime: leftClip.sourceStartTime,
            duration: mergedDuration,
            name: leftClip.name,
            color: leftClip.color
        )
        timeline.clips.removeAll(where: { $0.id == rightClip.id })
        timeline.onClipsChanged?()
        return true
    }
}
```

#### 5.2 拖拽裁剪实时响应

```swift
// mouseDragged 新增 case:

case .clipLeftEdge:
    let time = max(0, min(pixelToTime(location.x), clipTimeline.totalDuration))
    clipTimeline.trimLeft(clipId: activeClipId, newStartTime: time)
    needsDisplay = true
    
case .clipRightEdge:
    let time = max(0, min(pixelToTime(location.x), clipTimeline.totalDuration))
    clipTimeline.trimRight(clipId: activeClipId, newEndTime: time)
    needsDisplay = true
```

#### 5.3 最终导出：从 ClipTimeline 生成 PCM Buffer

```swift
// 所有 clip 操作完成后，导出为连续的 PCM buffer
// ClipTimeline.exportToPCMBuffer(from:)
// 原理: 按 clip.sourceStartTime 顺序拼接各 clip 的音频数据
// clip 间的空隙（即已被裁剪掉的部分）填充 0（静音）
```

---

<a id="p0-3"></a>
## P0-3: 淡入淡出可视化拖柄（Visual Fade Handles）

### 一、现状分析

#### 1.1 当前模式：按钮 + 弹窗 + 曲线选择

```swift
// FadeCommand.swift — 当前实现
class FadeCommand: EditCommand {
    let fadeInDuration: TimeInterval   // 需要用户填写数字
    let fadeOutDuration: TimeInterval
    let curveType: FadeCurveType       // 需要选择曲线类型
    
    func execute(on buffer:) -> AVAudioPCMBuffer? {
        // 逐帧乘以增益因子
        // 计算密集，不适合实时预览
    }
}
```

**问题**:
- 用户不知道淡入淡出的"视觉长度"——必须试错
- 需要打开弹窗、填数字、选曲线 → 4 步操作
- 无法实时看到效果，必须 apply 后才知道
- 竞品直接拖拽 clip 角落的小白点即可调整

#### 1.2 需要修改的文件

| 文件 | 改动 |
|------|------|
| `EditorWaveformView.swift` | 新增 fade 拖柄渲染 + 拖拽交互 |
| `EditorViewController.swift` | 监听 fade 变更，实时预览 |
| `FadeCommand.swift` | 新增快速 apply 方法（无弹窗） |

### 二、UI 方案

#### 2.1 视觉设计

在每个 clip 的角落添加 fade 拖柄：

```
clip 可视化 (选中态):
┌─────────────────────────────────────┐
│ ╱▐███▌        ▐████▌      ▐██▌╲   │
│╱ ▐████▌  ▐█▌  ▐█████▌ ▐█▌ ▐███▌ ╲ │
│  ▐█████▌▐███▌▐███████▌▐██▌▐████▌  │
│  ▐██████████████████████████████▌  │
│  ▐██████████████████████████████▌  │
│╲ ▐█████▌▐███▌▐███████▌▐██▌▐████▌ ╱│
│ ╲▐████▌  ▐█▌  ▐█████▌ ▐█▌ ▐███▌╱  │
└─────────────────────────────────────┘
↑                                   ↑
左上角 ▲ 拖柄 (fade-in)    右上角 ▲ 拖柄 (fade-out)
- 白色小三角 (8x8px)      - 白色小三角 (8x8px)
- hover 时高亮             - hover 时高亮
- 拖拽调整 fade 时长        - 拖拽调整 fade 时长
```

#### 2.2 Fade 拖柄规范

| 属性 | 值 |
|------|-----|
| **形状** | 三角形（△），直角在 clip 角落 |
| **颜色** | `textPrimary` alpha 0.7 (hover: 1.0) |
| **大小** | 8×8 px |
| **位置** | clip 选区的左上角 / 右上角 |
| **hit zone** | 16×16 px（±8px 扩展） |
| **cursor** | `resizeLeftRight` |
| **Fade 可视化** | 波形在 fade 区域渐变透明度（fade-in: 0→1, fade-out: 1→0） |

#### 2.3 波形 Fade 区域渲染

在波形绘制时，需要叠加 fade 遮罩：

```swift
// drawFadeOverlay: 在波形上方绘制半透明渐变遮罩
// fade-in 区域: 从左边缘 → 波形逐渐从透明变到不透明
// fade-out 区域: 从右边缘 ← 波形逐渐从不透明变到透明

func drawFadeOverlay(in rect: NSRect) {
    guard let clip = clipTimeline?.clip(at: playbackTime) else { return }
    
    // Fade-in 遮罩（左边）
    if clip.fadeInDuration > 0 {
        let fadeInEndX = timeToPixel(clip.sourceStartTime + clip.fadeInDuration)
        // 从 waveformRect.minX 到 fadeInEndX 绘制透明度渐变
        let gradient = NSGradient(
            colors: [
                waveformRect背景色.withAlphaComponent(1.0),  // 完全遮罩 = 波形不可见
                waveformRect背景色.withAlphaComponent(0.0)   // 无遮罩 = 波形可见
            ],
            atLocations: [0.0, 1.0]
        )
        gradient?.draw(in: NSRect(x: waveformRect.minX, y: waveformRect.minY,
                                   width: fadeInEndX - waveformRect.minX,
                                   height: waveformRect.height), angle: 0)
    }
    
    // Fade-out 遮罩（右边）
    // 同理，从右向左渐变
}
```

### 三、交互设计

#### 3.1 Fade 拖拽交互

```
用户拖拽 fade-in 三角形（向左/右）:
→ 实时更新 clip.fadeInDuration
→ 实时重绘波形 fade 区域模拟（PCM 数据不变，只改 visual overlay）
→ 松手后调用 FadeCommand.execute() 真正修改 PCM buffer
→ 推入 EditHistory（可撤销）
```

```swift
// 新的 DragMode
case fadeInHandle      // 拖拽 fade-in 拖柄
case fadeOutHandle     // 拖拽 fade-out 拖柄

// mouseDragged 处理:
case .fadeInHandle:
    let time = pixelToTime(location.x)
    let newFadeDuration = max(0, min(time - clip.startTime, clip.duration * 0.5))
    // 限制 fade 不超过 clip 长度的一半
    updateFadePreview(clipId: activeClipId, fadeIn: newFadeDuration)
    needsDisplay = true

case .fadeOutHandle:
    let time = pixelToTime(location.x)
    let newFadeDuration = max(0, min(clip.endTime - time, clip.duration * 0.5))
    updateFadePreview(clipId: activeClipId, fadeOut: newFadeDuration)
    needsDisplay = true
```

#### 3.2 mouseUp 提交

```swift
// mouseUp 时:
// 1. 预览态 → 写入态
// 2. 调用 FadeCommand(fadeIn: previewFadeIn, fadeOut: previewFadeOut, curve: .linear, sampleRate: sampleRate)
// 3. execute → 修改 PCM buffer
// 4. push to EditHistory
// 5. 清除预览状态
// 6. invalidateTiles (fade 区域需要重新生成 tile)
```

### 四、技术实现

#### 4.1 实时预览 vs 正式应用

关键是区分两个状态：

```
预览态 (Preview):
- 用户正在拖拽 fade 拖柄
- 只修改 overlay 渲染（波形透明度渐变）
- PCM buffer 不变
- 性能零开销（纯绘制层）

正式应用态 (Applied):
- 用户松手确认
- 调用 FadeCommand.execute() 修改 PCM buffer
- 推入 EditHistory
- invalidateTiles（重新生成受影响的 tile）
```

#### 4.2 FadeCommand 快速模式

新增不使用弹窗的构造函数：

```swift
// FadeCommand.swift 新增

/// 快速模式：从拖拽手柄直接创建，不需要弹窗
init(fadeIn: TimeInterval, fadeOut: TimeInterval, sampleRate: Double) {
    self.fadeInDuration = fadeIn
    self.fadeOutDuration = fadeOut
    self.curveType = .linear  // 拖拽默认用线性曲线
    self.sampleRate = sampleRate
    self.fadeInFrames = AVAudioFrameCount(fadeIn * sampleRate)
    self.fadeOutFrames = AVAudioFrameCount(fadeOut * sampleRate)
    
    var parts: [String] = []
    if fadeIn > 0 { parts.append("淡入 \(String(format: "%.1f", fadeIn))s") }
    if fadeOut > 0 { parts.append("淡出 \(String(format: "%.1f", fadeOut))s") }
    self.description = parts.joined(separator: " + ")
}
```

#### 4.3 Clip 模型扩展

在 `AudioClip` 中增加 fade 状态：

```swift
struct AudioClip {
    // ... 现有字段 ...
    
    /// 淡入时长（秒），0 = 无淡入
    var fadeInDuration: TimeInterval = 0
    
    /// 淡出时长（秒），0 = 无淡出
    var fadeOutDuration: TimeInterval = 0
    
    /// 淡入淡出曲线类型
    var fadeCurveType: FadeCurveType = .linear
}
```

---

<a id="集成方案"></a>
## 集成方案 — 三者的协同关系

### 渲染层级（最终）

```
编辑器波形区渲染 Layer 顺序（底层→顶层）:

Layer 0: 背景填充 (surfaceContainerLow)
Layer 1: 填充波形 (P0-1 新渲染)
Layer 2: Fade 区域遮罩渐变 (P0-3 新)
Layer 3: 选区外 Dim 遮罩 (现有)
Layer 4: 时间刻度尺 (现有)
Layer 5: Clip 分界线 (P0-2 新 — 虚线)
Layer 6: 播放头 (现有)
Layer 7: Clip 边缘拖柄 (P0-2 新 — cyan 矩形)
Layer 8: Fade 拖柄 (P0-3 新 — 白色三角)
Layer 9: 选区拖柄 (现有 — 向上兼容)
```

### 数据流

```
AudioFile → AVAudioPCMBuffer
              │
              ├──→ WaveformTileProvider (tile 缓存)
              │      └──→ EditorWaveformView (填充波形渲染 P0-1)
              │
              ├──→ ClipTimeline (clip 管理 P0-2)
              │      ├──→ EditorWaveformView (clip 分界线 + 边缘拖柄渲染)
              │      └──→ EditorViewController (split/trim 操作调度)
              │
              └──→ FadeCommand (P0-3)
                     ├──→ EditorWaveformView (fade 拖柄 + 渐变遮罩渲染)
                     └──→ AVAudioPCMBuffer (最终音频修改)
```

### 实施顺序（推荐）

```
第 1 步: P0-1 填充波形渲染
         → 纯渲染层改动，不依赖 Clip/Fade 系统
         → 可以先上线，立即提升视觉质量

第 2 步: P0-2 Clip 模型 + 切分/拖裁
         → 数据模型层 + 交互层
         → 引入 ClipTimeline，为 P0-3 提供基础

第 3 步: P0-3 Fade 拖柄
         → 渲染层 + 交互层
         → 依赖 P0-2 的 Clip 模型（fade 是 clip 属性）
         → 依赖 P0-1 的填充波形渲染（fade 渐变遮罩叠加）
```

---

<a id="风险评估"></a>
## 风险评估

| 风险 | 等级 | 缓解措施 |
|------|------|---------|
| 填充波形的降采样路径在大文件（>500MB）上性能不足 | 中 | 使用 tile 系统已有的 LOD + 缓存机制；对于 <1000 个 bucket，降采样 O(n)；对于 >>1000，使用 tile 预计算 |
| Clip 切分后 PCM buffer 拼接逻辑复杂度 | 中 | ClipTimeline.exportToPCMBuffer 需要仔细处理静音填充和边界对齐；写单元测试覆盖边界条件 |
| Fade 拖拽实时预览与最终应用的差异 | 低 | 预览是纯视觉（overlay alpha gradient），应用后才会改 PCM；用户松手后切换一次性 compute |
| 鼠标命中优先级冲突（选区拖柄 vs clip 边缘拖柄 vs fade 拖柄） | 中 | 设计明确的命中层级（见 §4.2 交互状态机）；hit zone 尺寸递减（clip 边缘 5px < 选区 8px < fade 16px） |
| 多重 clip + fade 拖柄视觉杂乱 | 低 | 仅在 clip 被选中时显示 fade 拖柄；clip 分界线只在多 clip 时显示 |

---

## 附录

### A. 竞品参考图（用户提供）

见对话中上传的竞品截图。

### B. 相关文档

- [录制工作区 Page Spec](./录制工作区-Page-Spec.md)
- [编辑器缩放控件交互规格](./编辑器缩放控件-交互规格.md)
- [Design System](./设计规范.md)
- [V2.0 虚拟时间线波形 UI 设计方案](./V2.0-虚拟时间线波形UI设计方案.md)
- [V1.1 编辑器 UI 设计方案](./V1.1-编辑器UI设计方案.md)
- [REQ-2.0-03 虚拟时间线波形](../需求/REQ-2.0-03.md)
- [REQ-2.0-06 多轨道录制](../需求/REQ-2.0-06.md)

### C. 修改文件清单

| P0 项 | 新增文件 | 修改文件 |
|-------|---------|---------|
| P0-1 | — | `WaveformView.swift`, `EditorWaveformView.swift` |
| P0-2 | `AudioClip.swift`, `ClipTimeline.swift`, `SplitCommand.swift` | `EditorWaveformView.swift`, `EditorViewController.swift`, `EditToolbarView.swift`, `TrimCommand.swift` |
| P0-3 | — | `EditorWaveformView.swift`, `EditorViewController.swift`, `FadeCommand.swift` |
