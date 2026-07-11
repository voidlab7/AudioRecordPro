# REQ-2.0-03d 编辑回归保护 + 编辑模型预留

## 版本：V2.0 | 优先级：P2 | 状态：⬜ 待开发

> 父需求：REQ-2.0-03 剪映式虚拟时间线音频轨道波形展示
> 依赖：REQ-2.0-03b（视图改造 + 绘制迁移）
> 预估工时：0.5 天

---

## 1. 一句话需求

确保 tile 模式下所有现有编辑操作（裁剪、静音、标准化、淡入淡出）后波形正确刷新，overlay（播放头、选区、标记）不受 tile 状态影响，并为后续非破坏式编辑预留 `AudioClip` / `TimelineModel` 接口。

---

## 2. 问题定义

| 问题 | 风险 |
|------|------|
| 编辑操作修改了 audioBuffer 但 tile 缓存仍是旧数据 | 波形显示与实际音频不一致 |
| 裁剪改变了总时长但 tile 索引未更新 | 绘制越界或显示空白 |
| 标准化/淡入淡出改变振幅但 tile 未 invalidate | 波形形状与实际音频不匹配 |
| 撤销/重做后 tile 状态不同步 | 用户看到错误的波形 |
| overlay 绘制依赖 tile 加载状态 | tile 未就绪时播放头/选区消失 |
| 后续多轨/clip 扩展无接口预留 | 架构需要大改才能支持 |

---

## 3. 目标用户故事

### US-01：编辑后波形同步

> 作为执行了裁剪/标准化等操作的用户，我希望波形立即反映编辑结果，不会看到旧的波形形状。

### US-02：撤销后波形恢复

> 作为执行了撤销操作的用户，我希望波形恢复到编辑前的状态，不会残留编辑后的波形。

### US-03：overlay 始终可见

> 作为正在定位剪辑点的用户，我希望播放头和选区始终可见，即使波形 tile 还在加载中。

---

## 4. 功能范围

### In Scope

- 编辑操作后正确 invalidate 受影响的 tiles
- 短文件编辑后走 `loadAudio(from:)` 全量刷新（保持现有行为）
- 大文件编辑后重新生成受影响时间范围的 tiles
- 裁剪后更新 `AudioAsset.duration` 和 `TimelineViewport`
- 撤销/重做后同步 tile 状态
- 播放头、选区、静音段标记作为独立 overlay 层绘制，不依赖 tile 状态
- 为 `AudioClip` / `TimelineModel` 预留协议接口（不实现具体功能）

### Not in Scope

- 实现非破坏式编辑引擎
- 实现多轨混音
- 实现 clip 级别的独立缓存
- 重构导出渲染管线

---

## 5. 技术方案

### 5.1 编辑后 Tile Invalidation

```swift
// WaveformTileProvider 新增方法
protocol WaveformTileInvalidation {
    /// Invalidate all tiles (e.g., normalize affects entire file)
    func invalidateAll()
    
    /// Invalidate tiles covering a specific time range
    func invalidateRange(start: TimeInterval, end: TimeInterval)
    
    /// Update asset duration after trim
    func updateDuration(_ newDuration: TimeInterval)
}
```

### 5.2 编辑操作与 Invalidation 映射

| 编辑操作 | Invalidation 策略 |
|---------|------------------|
| 裁剪 (Trim) | `invalidateAll()` + `updateDuration()` + 重置 viewport |
| 标准化 (Normalize) | `invalidateAll()`（全局振幅变化） |
| 淡入 (Fade In) | `invalidateRange(start: 0, end: fadeDuration)` |
| 淡出 (Fade Out) | `invalidateRange(start: totalDuration - fadeDuration, end: totalDuration)` |
| 静音 (Silence) | `invalidateRange(start: selectionStart, end: selectionEnd)` |
| 撤销 / 重做 | 根据操作类型调用对应 invalidation |

### 5.3 Overlay 独立绘制

```swift
// EditorWaveformView draw 顺序
override func draw(_ dirtyRect: NSRect) {
    drawBackground()
    drawRuler()
    
    // Waveform layer — may have loading gaps
    if useTileMode {
        drawWaveformTiles()
        drawFallbackForMissingTiles()
    } else {
        drawWaveformBars()
    }
    
    // Overlay layer — ALWAYS drawn, independent of tile state
    drawSelectionOverlay()
    drawSilenceMarkers()
    drawPlayhead()
}
```

### 5.4 编辑模型预留接口

```swift
/// Protocol for future non-destructive editing model
protocol TimelineItem {
    var id: String { get }
    var startTime: TimeInterval { get }
    var duration: TimeInterval { get }
}

/// Future: represents a clip on the timeline
protocol AudioClipProtocol: TimelineItem {
    var sourceAsset: AudioAsset { get }
    var sourceOffset: TimeInterval { get }  // offset within source file
    var gain: Float { get }
    var fadeInDuration: TimeInterval { get }
    var fadeOutDuration: TimeInterval { get }
}

/// Future: represents the full timeline model
protocol TimelineModelProtocol {
    var clips: [AudioClipProtocol] { get }
    var totalDuration: TimeInterval { get }
    var markers: [TimelineMarker] { get }
}

struct TimelineMarker: TimelineItem {
    let id: String
    let startTime: TimeInterval
    let duration: TimeInterval = 0
    let type: MarkerType
    
    enum MarkerType {
        case silence
        case bookmark
        case editPoint
    }
}
```

---

## 6. 受影响文件

| 文件 | 预期改动 |
|------|---------|
| `WaveformTileProvider.swift` | 新增 `invalidateRange()` / `updateDuration()` 方法 |
| `EditorWaveformView.swift` | overlay 绘制独立于 tile 状态；编辑后调用 invalidation |
| `EditorViewController.swift` | 编辑命令执行后触发对应 invalidation |
| `EditCommand.swift` | 各命令 execute/undo 后通知 provider invalidate |
| `AudioClipProtocol.swift` | 新增：预留接口定义（仅协议，不实现） |

---

## 7. 验收标准

### 7.1 编辑后波形刷新

- [ ] 裁剪后波形正确更新，总时长变化反映在视口中
- [ ] 标准化后波形振幅变化正确反映
- [ ] 淡入/淡出后对应区域波形渐变正确
- [ ] 静音后对应区域波形归零

### 7.2 撤销/重做

- [ ] 编辑后撤销，波形恢复到编辑前状态
- [ ] 撤销后重做，波形恢复到编辑后状态
- [ ] 连续多次撤销/重做，波形始终与音频一致

### 7.3 Overlay 独立性

- [ ] tile 加载中时，播放头仍正常显示和移动
- [ ] tile 加载中时，选区拖拽仍正常
- [ ] tile 加载中时，静音段标记仍可见
- [ ] tile 生成失败时，overlay 不受影响

### 7.4 回归

- [ ] 短录音（≤60s）所有编辑功能不回退
- [ ] 播放头显示和 seek 正常
- [ ] 选区拖拽仍正常
- [ ] 导出链路不受影响
- [ ] 编译通过

### 7.5 预留接口

- [ ] `AudioClipProtocol` / `TimelineModelProtocol` 协议已定义
- [ ] 协议不引入编译错误
- [ ] 现有代码不依赖这些协议（仅预留）

---

## 8. 下游建议

### 给铸（开发）

- 短文件编辑后继续走 `loadAudio(from:)` 全量刷新，不需要走 tile invalidation
- 大文件编辑后，先 invalidate 再 requestVisibleTiles，让 provider 重新生成
- 预留接口只定义协议文件，不要在现有代码中引入依赖

### 给鉴（QA）

- 重点测试：编辑 → 撤销 → 重做 的波形一致性
- 重点测试：大文件编辑后 tile 是否正确刷新
- 验证 overlay 在各种 tile 状态下的独立性
