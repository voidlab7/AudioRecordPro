# 架构评审：SplitView 分隔线视觉反馈

> 角色: 矩·架构师 | Task: task-0504-ui-splitview-divider
> 日期: 2026-05-04

---

## 1. 方案评估

### 方案对比

| 方案 | 描述 | 优点 | 缺点 | 推荐 |
|------|------|------|------|------|
| A | 子类化 NSSplitView，重写 `drawDivider(in:)` | 最正统的 AppKit 方式；完全控制绘制；性能好 | 需要替换现有 NSSplitView 实例 | **推荐** |
| B | Overlay tracking view | 不需要子类化；灵活 | 需要手动同步位置；z-order 管理复杂 | 不推荐 |
| C | effectiveRect + TrackingArea | 最小改动 | 无法自定义绘制外观；只能扩大热区 | 不推荐 |

### 推荐方案：方案 A — 子类化 NSSplitView

理由：
1. `drawDivider(in:)` 是 Apple 官方提供的 divider 自定义 API
2. 子类可以内聚所有 hover/拖动逻辑
3. 与现有 `NSSplitViewDelegate` 完全兼容（delegate 不涉及绘制）
4. 性能最优：仅在 divider rect 内重绘

## 2. 架构设计

### 2.1 新增类

```
AudioRecordApp/Sources/Views/
└── IndustrialSplitView.swift    ← 新文件
```

### 2.2 类图

```
┌─────────────────────────────────────────┐
│          IndustrialSplitView            │
│         (extends NSSplitView)           │
├─────────────────────────────────────────┤
│ - trackingArea: NSTrackingArea?         │
│ - isHovering: Bool                      │
│ - isDragging: Bool                      │
│ - hoverAnimationProgress: CGFloat       │
│ - displayLink: CVDisplayLink?           │
├─────────────────────────────────────────┤
│ + override drawDivider(in: NSRect)      │
│ + override mouseEntered(with:)          │
│ + override mouseExited(with:)           │
│ + override mouseDown(with:)             │
│ + override mouseUp(with:)              │
│ - setupTrackingArea()                   │
│ - updateTrackingArea()                  │
│ - animateHover(entering: Bool)          │
│ - drawDots(in: NSRect, alpha: CGFloat)  │
└─────────────────────────────────────────┘
         │
         │ delegate (unchanged)
         ▼
┌─────────────────────────────┐
│  MainWindowView             │
│  (NSSplitViewDelegate)      │
└─────────────────────────────┘
```

### 2.3 状态机

```
         mouseEntered
  IDLE ──────────────→ HOVERED
   ↑                      │
   │ mouseExited           │ mouseDown
   │                      ▼
   ←──────────────── DRAGGING
        mouseUp
```

## 3. 实现细节

### 3.1 IndustrialSplitView.swift 核心代码

```swift
import Cocoa

/// Industrial Design 风格的 SplitView，支持分隔线 hover 视觉反馈
final class IndustrialSplitView: NSSplitView {
    
    // MARK: - State
    
    private enum DividerState {
        case idle
        case hovered
        case dragging
    }
    
    private var dividerState: DividerState = .idle {
        didSet {
            guard dividerState != oldValue else { return }
            animateTransition(from: oldValue, to: dividerState)
        }
    }
    
    /// 动画进度 0.0(idle) ~ 1.0(hovered/dragging)
    private var highlightProgress: CGFloat = 0.0
    
    private var trackingArea: NSTrackingArea?
    private var animationTimer: Timer?
    
    // MARK: - Constants
    
    private let animationDuration: TimeInterval = 0.15  // 150ms
    private let idleDividerWidth: CGFloat = 1.0
    private let hoverDividerWidth: CGFloat = 2.0
    private let trackingPadding: CGFloat = 4.0  // 热区扩展 ±4px
    private let dotRadius: CGFloat = 1.5
    private let dotSpacing: CGFloat = 4.0
    private let dotCount: Int = 3
    
    // MARK: - Lifecycle
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupTrackingArea()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }
    
    // MARK: - Tracking Area
    
    private func setupTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        // 计算 divider 区域 + padding 作为 tracking rect
        let dividerRect = dividerTrackingRect()
        let area = NSTrackingArea(
            rect: dividerRect,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
    
    private func dividerTrackingRect() -> NSRect {
        guard numberOfArrangedSubviews > 1 else { return .zero }
        
        // 获取第一个 divider 的位置
        let dividerThickness = self.dividerThickness
        let subview = arrangedSubviews[0]
        let dividerX = subview.frame.maxX
        
        return NSRect(
            x: dividerX - trackingPadding,
            y: 0,
            width: dividerThickness + trackingPadding * 2,
            height: bounds.height
        )
    }
    
    // MARK: - Mouse Events
    
    override func mouseEntered(with event: NSEvent) {
        if dividerState == .idle {
            dividerState = .hovered
        }
        super.mouseEntered(with: event)
    }
    
    override func mouseExited(with event: NSEvent) {
        if dividerState == .hovered {
            dividerState = .idle
        }
        super.mouseExited(with: event)
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dividerRect = dividerTrackingRect()
        
        if dividerRect.contains(point) {
            dividerState = .dragging
        }
        super.mouseDown(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        if dividerState == .dragging {
            // 检查鼠标是否还在 divider 区域
            let point = convert(event.locationInWindow, from: nil)
            let dividerRect = dividerTrackingRect()
            dividerState = dividerRect.contains(point) ? .hovered : .idle
        }
        super.mouseUp(with: event)
    }
    
    // MARK: - Drawing
    
    override func drawDivider(in rect: NSRect) {
        // 不调用 super，完全自定义绘制
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 计算当前颜色（基于动画进度插值）
        let idleColor = IndustrialColors.outlineVariant
        let activeColor = IndustrialColors.primaryContainer
        
        let currentColor = interpolateColor(
            from: idleColor,
            to: activeColor,
            progress: highlightProgress
        )
        
        // 计算当前宽度
        let currentWidth = idleDividerWidth + (hoverDividerWidth - idleDividerWidth) * highlightProgress
        
        // 绘制分隔线
        let lineRect = NSRect(
            x: rect.midX - currentWidth / 2,
            y: rect.minY,
            width: currentWidth,
            height: rect.height
        )
        
        context.setFillColor(currentColor.cgColor)
        context.fill(lineRect)
        
        // 绘制拖动指示器圆点（仅在 hover/dragging 时）
        if highlightProgress > 0.01 {
            drawDots(in: rect, context: context, alpha: highlightProgress)
        }
    }
    
    // MARK: - Dot Indicator
    
    private func drawDots(in rect: NSRect, context: CGContext, alpha: CGFloat) {
        let totalHeight = CGFloat(dotCount) * (dotRadius * 2) + CGFloat(dotCount - 1) * dotSpacing
        let startY = rect.midY - totalHeight / 2
        
        let dotColor = IndustrialColors.primaryContainer.withAlphaComponent(alpha)
        context.setFillColor(dotColor.cgColor)
        
        for i in 0..<dotCount {
            let y = startY + CGFloat(i) * (dotRadius * 2 + dotSpacing) + dotRadius
            let dotRect = NSRect(
                x: rect.midX - dotRadius,
                y: y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fillEllipse(in: dotRect)
        }
    }
    
    // MARK: - Animation
    
    private func animateTransition(from: DividerState, to: DividerState) {
        let targetProgress: CGFloat = (to == .idle) ? 0.0 : 1.0
        
        // 检查是否需要动画
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            highlightProgress = targetProgress
            needsDisplay = true
            return
        }
        
        // 使用 Timer 驱动简单动画
        animationTimer?.invalidate()
        
        let startProgress = highlightProgress
        let startTime = CACurrentMediaTime()
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            let elapsed = CACurrentMediaTime() - startTime
            let t = min(elapsed / self.animationDuration, 1.0)
            
            // ease-in-out 缓动
            let easedT = t < 0.5
                ? 2 * t * t
                : 1 - pow(-2 * t + 2, 2) / 2
            
            self.highlightProgress = startProgress + (targetProgress - startProgress) * CGFloat(easedT)
            self.needsDisplay = true
            
            if t >= 1.0 {
                timer.invalidate()
                self.animationTimer = nil
            }
        }
    }
    
    // MARK: - Color Interpolation
    
    private func interpolateColor(from: NSColor, to: NSColor, progress: CGFloat) -> NSColor {
        guard let fromRGB = from.usingColorSpace(.sRGB),
              let toRGB = to.usingColorSpace(.sRGB) else { return from }
        
        let r = fromRGB.redComponent + (toRGB.redComponent - fromRGB.redComponent) * progress
        let g = fromRGB.greenComponent + (toRGB.greenComponent - fromRGB.greenComponent) * progress
        let b = fromRGB.blueComponent + (toRGB.blueComponent - fromRGB.blueComponent) * progress
        let a = fromRGB.alphaComponent + (toRGB.alphaComponent - fromRGB.alphaComponent) * progress
        
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    
    // MARK: - effectiveRect (扩大热区)
    
    override var dividerThickness: CGFloat {
        return 1.0  // 保持视觉上的 thin 风格
    }
}
```

### 3.2 MainWindowView.swift 修改

```swift
// 修改 setupSplitView() 方法

private func setupSplitView() {
    splitView = IndustrialSplitView()  // ← 替换为子类
    splitView.isVertical = true
    splitView.dividerStyle = .thin
    splitView.delegate = self
    splitView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(splitView)
}
```

**注意**：需要将 `splitView` 的类型声明从 `NSSplitView` 改为 `IndustrialSplitView`（或保持为 `NSSplitView` 利用多态）。

## 4. 与现有代码的兼容性分析

### 4.1 NSSplitViewDelegate 兼容性

| 现有 Delegate 方法 | 影响 | 说明 |
|-------------------|------|------|
| `constrainMinCoordinate` | 无影响 | 约束逻辑不变 |
| `constrainMaxCoordinate` | 无影响 | 约束逻辑不变 |
| `canCollapseSubview` | 无影响 | 折叠逻辑不变 |
| `shouldAdjustSizeOfSubview` | 无影响 | 调整逻辑不变 |
| `effectiveRect:forDrawnRect:` | **需要协调** | 子类 trackingArea 已扩大热区，delegate 中可移除或配合 |

### 4.2 effectiveRect 协调

当前 delegate 中的 `effectiveRect` 直接返回 `proposedEffectiveRect`（即无自定义）。子类的 `NSTrackingArea` 已独立扩大了交互热区，因此 delegate 的 `effectiveRect` 方法可以保持不变，也可以配合扩大：

```swift
// 推荐：在 delegate 中也扩大 effectiveRect，确保系统拖动手势识别也用扩大的热区
func splitView(_ splitView: NSSplitView, 
               effectiveRect proposedEffectiveRect: NSRect, 
               forDrawnRect drawnRect: NSRect, 
               ofDividerAt dividerIndex: Int) -> NSRect {
    // 扩大热区 ±4px
    return proposedEffectiveRect.insetBy(dx: -4, dy: 0)
}
```

### 4.3 mouseDown 冲突分析

`NSSplitView` 内部通过 `mouseDown` 处理拖动。子类的 `mouseDown` 必须调用 `super.mouseDown(with:)` 以保证拖动功能正常。代码示例中已正确调用 super。

**注意**：`NSSplitView.mouseDown` 是阻塞式的（event tracking loop），这意味着 `mouseDown` 调用 super 后，直到用户松开鼠标才会返回。因此状态机的 `dragging → idle/hovered` 转换实际发生在 super.mouseDown 返回之后。

修正后的实现：

```swift
override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let dividerRect = dividerTrackingRect()
    
    if dividerRect.contains(point) {
        dividerState = .dragging
        
        // super.mouseDown 是阻塞的，直到 mouseUp
        super.mouseDown(with: event)
        
        // mouseUp 后检查鼠标位置
        if let currentEvent = window?.currentEvent {
            let endPoint = convert(currentEvent.locationInWindow, from: nil)
            let newDividerRect = dividerTrackingRect()  // 可能已经移动
            dividerState = newDividerRect.contains(endPoint) ? .hovered : .idle
        } else {
            dividerState = .idle
        }
    } else {
        super.mouseDown(with: event)
    }
}

// mouseUp 不再需要单独 override（因为 super.mouseDown 内部处理了）
```

## 5. 代码修改清单

| # | 文件 | 修改类型 | 描述 |
|---|------|---------|------|
| 1 | `IndustrialSplitView.swift` | **新增** | NSSplitView 子类，含 hover 检测 + 自定义绘制 |
| 2 | `MainWindowView.swift:45-49` | **修改** | `setupSplitView()` 使用 `IndustrialSplitView()` |
| 3 | `MainWindowView.swift:322-324` | **修改** | `effectiveRect` 返回扩大的热区 |
| 4 | `MainWindowView.swift` 属性声明 | **修改** | splitView 类型改为 `IndustrialSplitView`（可选） |

### 文件位置

```
AudioRecordApp/Sources/Views/
├── MainWindowView.swift          ← 修改
├── IndustrialSplitView.swift     ← 新增
├── SidebarView.swift
├── WaveformView.swift
└── ...
```

## 6. 性能考虑

| 方面 | 评估 |
|------|------|
| 绘制频率 | 仅在 divider rect 内重绘（约 1x600px），开销极小 |
| 动画帧率 | 60fps Timer，150ms 约 9 帧，CPU 开销可忽略 |
| 内存 | 无额外位图/layer，纯绘制代码 |
| TrackingArea | 单个区域，系统标准机制 |

## 7. 替代方案：使用 NSAnimationContext

如果想用更 "AppKit 原生" 的动画方式：

```swift
private func animateTransition(from: DividerState, to: DividerState) {
    let targetProgress: CGFloat = (to == .idle) ? 0.0 : 1.0
    
    // 使用 layer-backed 动画
    if let layer = self.layer {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // 由于 highlightProgress 不是 animatable 属性，仍需手动插值
        }
    }
    
    // 实际上，由于 drawDivider 是手动绘制，Timer 方案更可控
}
```

**结论**：Timer 驱动方案更简单直接，因为我们需要精确控制 `highlightProgress` 插值。

## 8. 测试要点

| # | 测试场景 | 验证方法 |
|---|---------|---------|
| 1 | Hover 进入/离开 | 鼠标移入 divider 区域，观察颜色和宽度变化 |
| 2 | 快速进出 | 快速移入移出，确认动画不卡顿不残留 |
| 3 | 拖动 | 拖动 divider，确认约束(200-400px)生效 |
| 4 | 拖动时外观 | 拖动过程中保持青色高亮 |
| 5 | 窗口 resize | 窗口大小改变后 trackingArea 正确更新 |
| 6 | 减少动态效果 | 开启辅助功能设置，确认动画跳过 |
| 7 | 编译检查 | 确认无编译错误和警告 |

## 9. 风险与缓解

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| mouseDown 阻塞导致状态不正确 | 中 | 高 | 在 super.mouseDown 返回后重新评估状态 |
| TrackingArea 在布局变化后失效 | 低 | 中 | 在 `updateTrackingAreas()` 中重建 |
| dividerThickness override 影响布局 | 低 | 高 | 保持返回 1.0，与 .thin 一致 |
| 与未来 macOS 版本不兼容 | 极低 | 中 | drawDivider 是稳定 API (since macOS 10.0) |
