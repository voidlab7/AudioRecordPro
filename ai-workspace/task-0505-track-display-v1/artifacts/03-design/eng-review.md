# 架构设计: 音轨显示逻辑优化

> 作者: 矩·架构 | 日期: 2026-05-05

---

## 架构评分: 80/100

---

## 1. 核心变更方案

### 1.1 组件拆分

**新增组件**：无需新增文件。在 `TracksView.swift` 内重构 `addTrackRow()` 方法即可。

**修改文件清单**：

| 文件 | 变更 |
|------|------|
| `AudioRecordKit/Sources/API/Types.swift` | TrackInfo 新增 `sourceType: String` |
| `AudioRecordApp/Sources/Views/TracksView.swift` | 重构：动态轨道管理 + fade 动画 + 来源标注 + 混合输出标签 |
| `AudioRecordApp/Sources/Views/MainWindowView.swift` | `updateTracksDisplay()` 传递 sourceType |

### 1.2 TrackInfo 扩展

```swift
public struct TrackInfo: Sendable {
    public let icon: String
    public let title: String
    public let isActive: Bool
    public let appIcon: NSImage?
    public let sourceType: String  // NEW: "SYSTEM MIXDOWN" | "PROCESS TAP · PID xxx" | "MICROPHONE INPUT"
    
    public init(icon: String, title: String, isActive: Bool, appIcon: NSImage? = nil, sourceType: String = "") {
        // ...
    }
}
```

### 1.3 TracksView 重构要点

```
TracksView
├── tracksStack: NSStackView (vertical)
│   └── 动态添加/移除 trackRow views
├── mixOutputLabel: NSTextField (conditional visibility)
└── playbackPanel: NSView (existing, unchanged)
```

**关键逻辑**：

1. `updateTracks(_ tracks:)` → 比较新旧轨道列表
2. 如果新增了麦克风轨 → 创建 view + fade-in 动画
3. 如果移除了麦克风轨 → fade-out 动画 → completion 中 removeFromSuperview
4. mixOutputLabel 根据 `tracks.count > 1` 控制显隐

### 1.4 电平分发策略

```swift
func updateLevel(_ level: Float) {
    // V1: 所有轨道共享同一 level
    for row in tracksStack.arrangedSubviews {
        if let meter = row.viewWithTag(100) as? LevelMeterView {
            meter.updateLevel(level)
        }
    }
}
```

使用 `tag = 100` 或 subview 遍历定位 LevelMeterView 实例。

### 1.5 动画方案

```swift
// 插入动画
func animateTrackIn(_ trackView: NSView) {
    trackView.alphaValue = 0
    trackView.frame.origin.y += 20
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.25
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        trackView.animator().alphaValue = 1.0
        trackView.animator().frame.origin.y -= 20
    })
}

// 移除动画
func animateTrackOut(_ trackView: NSView, completion: @escaping () -> Void) {
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        trackView.animator().alphaValue = 0
        trackView.animator().frame.origin.y += 20
    }, completionHandler: completion)
}
```

---

## 2. 风险评估

| 风险 | 等级 | 缓解 |
|------|------|------|
| 动画与 NSStackView 冲突 | 中 | 动画仅操作 alphaValue，不手动修改 frame（让 stackView 管理布局） |
| 轨道高度溢出 | 低 | 从 120px 减至 100px，两轨总高 208px 在 tracksView 区域内 |
| 单路 level 共享 | 低 | V1 接受，接口预留分轨回调 |

---

## 3. 接口契约

### 3.1 TrackInfo 新增字段
- `sourceType: String` — 描述音频来源的可读字符串

### 3.2 TracksView 公开方法（不变）
- `updateTracks(_ tracks: [TrackInfo])` — 接收新轨道列表，内部做 diff + 动画
- `updateLevel(_ level: Float)` — 分发电平到所有活跃轨道

### 3.3 MainWindowView 修改
- `updateTracksDisplay()` — 构建 TrackInfo 时填充 `sourceType`

---

## 交接块

```
来源: 矩·架构
状态: ✅ 完成
产物文件: ai-workspace/task-0505-track-display-v1/artifacts/03-design/eng-review.md
评分: 80/100
下游建议: 铸·开发 → 按此方案实现，注意动画用 alphaValue 不要手动改 frame.origin
```
