# 架构评审：首次启动引导 & 权限状态可视化

> 角色: 矩·架构师 | Task: task-0504-ui-onboarding
> 日期: 2026-05-04

---

## 1. 架构概览

本次改动涉及 **3 个核心模块**：

```
┌───────────────────────────────────────────────────────────────┐
│                        MainViewController                      │
│  ┌──────────────────┐  ┌──────────────────┐                   │
│  │ OnboardingManager │  │ PermissionManager │ (已有，需恢复)    │
│  │     (新增)        │  │                  │                   │
│  └────────┬─────────┘  └────────┬─────────┘                   │
│           │                     │                              │
│           ▼                     ▼                              │
│  ┌──────────────────┐  ┌──────────────────┐                   │
│  │CoachMarkOverlay  │  │  StatusBarView    │                   │
│  │   View (新增)     │  │  (修改：+权限区)  │                   │
│  └──────────────────┘  └──────────────────┘                   │
└───────────────────────────────────────────────────────────────┘
```

---

## 2. 首次启动检测

### 2.1 方案：UserDefaults Flag

```swift
// OnboardingManager.swift
class OnboardingManager {
    static let shared = OnboardingManager()
    
    private let hasCompletedKey = "hasCompletedOnboarding"
    
    var shouldShowOnboarding: Bool {
        return !UserDefaults.standard.bool(forKey: hasCompletedKey)
    }
    
    func markOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: hasCompletedKey)
    }
    
    func resetOnboarding() { // Debug 用
        UserDefaults.standard.removeObject(forKey: hasCompletedKey)
    }
}
```

**决策理由**：
- UserDefaults 是最轻量的持久化方案，适合 boolean flag
- 不需要额外数据库或文件 I/O
- 用户清除 App 数据会重置引导（符合预期）

### 2.2 触发时机

在 `MainViewController.setupInitialState()` 末尾追加：

```swift
private func setupInitialState() {
    // ... 现有代码 ...
    
    // 首次启动引导检测
    if OnboardingManager.shared.shouldShowOnboarding {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showOnboarding()
        }
    }
}
```

**设计决策**：延迟 0.5s 再显示引导，确保 UI 完全渲染、进程列表已加载。

---

## 3. Coach Mark 实现方案

### 3.1 方案对比

| 方案 | 实现方式 | 优点 | 缺点 | 推荐 |
|------|---------|------|------|------|
| NSPopover | 系统原生 Popover | 简单、自带箭头 | 样式受限、难自定义暗色主题 | 否 |
| **自定义 Overlay NSView** | 叠加在 window.contentView 上 | 完全可控、匹配 Industrial 主题 | 需自绘箭头和定位逻辑 | **是** |

**采用方案**：自定义 Overlay NSView

**理由**：NSPopover 的默认样式（vibrancy 背景、系统圆角）与 Industrial Design 暗色主题冲突，且无法自定义指向三角样式。自定义 View 可精确控制所有视觉参数。

### 3.2 CoachMarkOverlayView 设计

```swift
// CoachMarkOverlayView.swift (新文件)

/// Coach Mark 单步数据模型
struct CoachMarkStep {
    let targetView: NSView          // 高亮目标
    let message: String             // 主文案
    let subtitle: String            // 副文案
    let arrowDirection: ArrowDirection // 箭头方向
    
    enum ArrowDirection {
        case up, down, left, right
    }
}

/// Coach Mark 覆盖层 - 管理多步引导
class CoachMarkOverlayView: NSView {
    
    // MARK: - Properties
    private var steps: [CoachMarkStep] = []
    private var currentStepIndex: Int = 0
    private var tooltipView: CoachMarkTooltipView?
    private var highlightLayer: CAShapeLayer?
    
    weak var delegate: CoachMarkOverlayDelegate?
    
    // MARK: - Public API
    func configure(steps: [CoachMarkStep]) { ... }
    func start() { ... }
    func nextStep() { ... }
    func skip() { ... }
    
    // MARK: - Private
    private func showStep(at index: Int) { ... }
    private func animateTransition(from: Int, to: Int) { ... }
    private func positionTooltip(for step: CoachMarkStep) { ... }
    private func updateHighlight(for targetView: NSView) { ... }
}

protocol CoachMarkOverlayDelegate: AnyObject {
    func coachMarkDidComplete(_ overlay: CoachMarkOverlayView)
    func coachMarkDidSkip(_ overlay: CoachMarkOverlayView)
}
```

### 3.3 Overlay 层级

```
window.contentView
 └── MainWindowView (现有)
      ├── SidebarView
      ├── ContentView  
      ├── StatusBarView
      └── CoachMarkOverlayView (新增，addSubview 在最上层)
           └── CoachMarkTooltipView (浮动提示气泡)
```

- Overlay 覆盖整个 `MainWindowView`
- 背景 **无遮罩**（Coach Mark 方案），完全透明
- 仅在目标区域添加高亮边框效果
- `hitTest` 透传：除了 tooltip 按钮区域外，所有点击穿透到底层

### 3.4 点击穿透实现

```swift
override func hitTest(_ point: NSPoint) -> NSView? {
    // 只拦截 tooltip 区域的点击
    if let tooltip = tooltipView, tooltip.frame.contains(point) {
        return tooltip.hitTest(convert(point, to: tooltip))
    }
    // 其他区域穿透
    return nil
}
```

---

## 4. 恢复 checkAudioPermissionsSilently()

### 4.1 当前状态

`MainViewController.swift` 第 49 行：
```swift
// 关闭启动时的权限监控与静默检查，避免任何权限链路阻塞 UI
// checkAudioPermissionsSilently()
```

### 4.2 恢复方案

**不直接恢复原注释行**，而是改造为安全的非阻塞版本：

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    logger.info("主视图控制器开始加载")
    setupInitialState()
    
    // 恢复权限静默检查（非阻塞，仅读取状态并同步到 StatusBar）
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.checkAudioPermissionsSilently()
    }
    
    logger.info("主视图控制器已加载")
}
```

**关键设计**：
1. **延迟 1.0s**：确保 UI 已完成布局，避免阻塞启动
2. **仅读取状态**：`checkAllPermissions()` 是纯读操作，不触发系统弹窗
3. **同步到 UI**：读取后立即更新 StatusBar 图标

### 4.3 改造 checkAudioPermissionsSilently()

```swift
/// 静默权限检查 - 非阻塞，不触发系统权限弹窗
/// 仅读取当前状态并同步到 StatusBar
private func checkAudioPermissionsSilently() {
    let permissions = PermissionManager.shared.checkAllPermissions()
    
    // 同步状态到 StatusBar
    mainWindowView.updatePermissionStatus(
        microphone: permissions.microphone,
        systemAudio: permissions.systemAudioCapture ?? .notDetermined
    )
    
    // 只记录日志，不显示弹窗或状态文字
    logger.info("权限静默检查 - 麦克风:\(permissions.microphone), 系统音频:\(permissions.systemAudioCapture ?? .notDetermined)")
    
    // 启动权限状态轮询（替代之前的 startPermissionMonitoring）
    startPermissionPolling()
}
```

### 4.4 权限监听方案

**方案选择**：定时轮询（Polling）而非 Notification

**原因**：
- macOS 没有原生的权限状态变更通知 API
- `PermissionManager.startPermissionMonitoring` 之前被注释是因为"后台持续触发权限检查"
- 改为 **低频轮询**（每 5 秒一次），仅在 App 处于前台时执行

```swift
private var permissionPollingTimer: Timer?
private var lastMicStatus: PermissionManager.PermissionStatus = .notDetermined
private var lastSystemAudioStatus: PermissionManager.PermissionStatus = .notDetermined

private func startPermissionPolling() {
    permissionPollingTimer = Timer.scheduledTimer(
        withTimeInterval: 5.0,  // 5秒轮询
        repeats: true
    ) { [weak self] _ in
        guard let self = self,
              NSApp.isActive else { return }  // 仅前台轮询
        
        let permissions = PermissionManager.shared.checkAllPermissions()
        let newMic = permissions.microphone
        let newAudio = permissions.systemAudioCapture ?? .notDetermined
        
        // 仅在状态变化时更新 UI（避免不必要的渲染）
        if newMic != self.lastMicStatus || newAudio != self.lastSystemAudioStatus {
            self.lastMicStatus = newMic
            self.lastSystemAudioStatus = newAudio
            
            DispatchQueue.main.async {
                self.mainWindowView.updatePermissionStatus(
                    microphone: newMic,
                    systemAudio: newAudio
                )
            }
        }
    }
}

private func stopPermissionPolling() {
    permissionPollingTimer?.invalidate()
    permissionPollingTimer = nil
}
```

**性能影响**：
- `AVCaptureDevice.authorizationStatus(for:)` 是纯内存读取，无磁盘 I/O
- 5 秒间隔 + 状态比较，仅变化时触发 UI 更新
- **满足验收标准**：权限变更后 ≤5s 内 StatusBar 更新

---

## 5. StatusBarView 权限图标区 Auto Layout

### 5.1 新布局结构

```
StatusBarView (28px height)
├── permissionStackView (NSStackView, horizontal)
│   ├── micPermissionIcon (NSImageView, 14x14)
│   └── systemAudioPermissionIcon (NSImageView, 14x14)
└── statusLabel (NSTextField, 居中)
```

### 5.2 约束方案

```swift
// StatusBarView.swift - 新增权限图标组件

private let permissionStackView = NSStackView()
private let micPermissionIcon = NSImageView()
private let systemAudioPermissionIcon = NSImageView()

private func setupPermissionIcons() {
    // 配置图标
    micPermissionIcon.image = NSImage(systemSymbolName: "mic.fill",
                                      accessibilityDescription: "麦克风权限")
    micPermissionIcon.contentTintColor = IndustrialColors.statusWarning  // 默认黄色
    micPermissionIcon.imageScaling = .scaleProportionallyUpOrDown
    micPermissionIcon.translatesAutoresizingMaskIntoConstraints = false
    
    systemAudioPermissionIcon.image = NSImage(systemSymbolName: "speaker.wave.3.fill",
                                              accessibilityDescription: "系统音频权限")
    systemAudioPermissionIcon.contentTintColor = IndustrialColors.statusWarning
    systemAudioPermissionIcon.imageScaling = .scaleProportionallyUpOrDown
    systemAudioPermissionIcon.translatesAutoresizingMaskIntoConstraints = false
    
    // Stack 容器配置
    permissionStackView.orientation = .horizontal
    permissionStackView.spacing = 8
    permissionStackView.alignment = .centerY
    permissionStackView.translatesAutoresizingMaskIntoConstraints = false
    permissionStackView.addArrangedSubview(micPermissionIcon)
    permissionStackView.addArrangedSubview(systemAudioPermissionIcon)
    
    addSubview(permissionStackView)
    
    // 点击手势
    let clickGesture = NSClickGestureRecognizer(target: self,
                                                action: #selector(permissionIconClicked))
    permissionStackView.addGestureRecognizer(clickGesture)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        // 权限图标区
        permissionStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
        permissionStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        permissionStackView.widthAnchor.constraint(lessThanOrEqualToConstant: 80),
        
        // 图标尺寸约束
        micPermissionIcon.widthAnchor.constraint(equalToConstant: 14),
        micPermissionIcon.heightAnchor.constraint(equalToConstant: 14),
        systemAudioPermissionIcon.widthAnchor.constraint(equalToConstant: 14),
        systemAudioPermissionIcon.heightAnchor.constraint(equalToConstant: 14),
        
        // statusLabel: 紧跟权限图标区右侧
        statusLabel.leadingAnchor.constraint(equalTo: permissionStackView.trailingAnchor, constant: 12),
        statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
    ])
}
```

### 5.3 权限状态更新方法

```swift
/// 更新权限图标颜色（带动画）
func updatePermissionStatus(microphone: PermissionManager.PermissionStatus,
                            systemAudio: PermissionManager.PermissionStatus) {
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.3
        micPermissionIcon.animator().contentTintColor = colorForStatus(microphone)
        systemAudioPermissionIcon.animator().contentTintColor = colorForStatus(systemAudio)
    })
    
    // 更新 accessibility
    micPermissionIcon.setAccessibilityValue(descriptionForStatus("麦克风", microphone))
    systemAudioPermissionIcon.setAccessibilityValue(descriptionForStatus("系统音频", systemAudio))
    
    // 更新 tooltip
    permissionStackView.toolTip = "麦克风: \(statusText(microphone)) | 系统音频: \(statusText(systemAudio))"
}

private func colorForStatus(_ status: PermissionManager.PermissionStatus) -> NSColor {
    switch status {
    case .granted:              return IndustrialColors.primaryContainer  // 青色
    case .notDetermined:        return IndustrialColors.statusWarning     // 黄色
    case .denied, .restricted:  return IndustrialColors.statusDanger      // 红色
    }
}
```

---

## 6. 代码修改清单

### 6.1 修改现有文件

| 文件 | 行号 | 修改内容 | 优先级 |
|------|------|---------|--------|
| `MainViewController.swift` | L49 | 恢复 `checkAudioPermissionsSilently()` 调用（延迟 1.0s） | P0 |
| `MainViewController.swift` | L116 `setupInitialState()` | 末尾追加 onboarding 检测逻辑 | P1 |
| `MainViewController.swift` | L138 `checkAudioPermissionsSilently()` | 改造为同步状态到 StatusBar 的非阻塞版本 | P0 |
| `MainViewController.swift` | L201 `startPermissionMonitoring()` | 替换为 `startPermissionPolling()` 低频轮询 | P0 |
| `StatusBarView.swift` | 全文 | 新增权限图标区（NSStackView + 2x NSImageView） | P0 |
| `StatusBarView.swift` | `setupConstraints()` | 调整 statusLabel 的 leading 约束 | P0 |
| `MainWindowView.swift` | (待确认) | 新增 `updatePermissionStatus()` 方法透传到 StatusBarView | P0 |

### 6.2 新增文件

| 文件路径 | 职责 | 行数估计 |
|---------|------|---------|
| `Sources/Onboarding/OnboardingManager.swift` | 首次启动检测、状态管理 | ~30 行 |
| `Sources/Onboarding/CoachMarkOverlayView.swift` | Coach Mark 覆盖层（步骤管理 + 定位） | ~200 行 |
| `Sources/Onboarding/CoachMarkTooltipView.swift` | 单个 tooltip 气泡视图（文字 + 按钮 + 三角） | ~150 行 |
| `Sources/Onboarding/CoachMarkStep.swift` | 步骤数据模型 | ~20 行 |

### 6.3 文件结构

```
AudioRecordApp/Sources/
├── Controllers/
│   └── MainViewController.swift  (修改)
├── Views/
│   ├── StatusBarView.swift       (修改)
│   ├── SidebarView.swift         (不变)
│   └── MainWindowView.swift      (小改：透传方法)
└── Onboarding/                   (新增目录)
    ├── OnboardingManager.swift
    ├── CoachMarkOverlayView.swift
    ├── CoachMarkTooltipView.swift
    └── CoachMarkStep.swift
```

---

## 7. 数据流

### 7.1 首次启动引导流程

```
App Launch
  │
  ▼
MainViewController.viewDidLoad()
  │
  ▼
setupInitialState()
  │
  ├── loadLastRecordingMode()
  ├── updateMode / updateRecordingState / updateStatus
  ├── loadAvailableProcesses()
  ├── loadRecordedFilesOnStartup()
  ├── cleanupOldLogs / cleanupTempFiles
  │
  └── if OnboardingManager.shared.shouldShowOnboarding
        │
        ▼ (delay 0.5s)
      showOnboarding()
        │
        ▼
      CoachMarkOverlayView.configure(steps)
      CoachMarkOverlayView.start()
        │
        ▼ (user completes or skips)
      OnboardingManager.shared.markOnboardingCompleted()
      CoachMarkOverlayView.removeFromSuperview()
```

### 7.2 权限状态数据流

```
Timer (5s polling, only when app is active)
  │
  ▼
PermissionManager.shared.checkAllPermissions()
  │
  ▼ (returns PermissionStatus for mic & systemAudio)
MainViewController
  │  compare with lastMicStatus / lastSystemAudioStatus
  │  (only update if changed)
  ▼
mainWindowView.updatePermissionStatus(mic, systemAudio)
  │
  ▼
StatusBarView.updatePermissionStatus(mic, systemAudio)
  │
  ▼ (animated tintColor change, 300ms)
micPermissionIcon.contentTintColor = ...
systemAudioPermissionIcon.contentTintColor = ...
```

---

## 8. 风险评估

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| 权限轮询影响性能 | 低 | 低 | 5s 间隔 + 仅前台 + 状态比较；checkAllPermissions() 是纯读操作 |
| Coach Mark 定位不准确 | 中 | 中 | 使用 `convert(_:to:)` 坐标转换；监听 frameDidChange 重新定位 |
| 引导与用户操作冲突 | 低 | 低 | hitTest 穿透；用户操作触发自动跳步 |
| UserDefaults 被清除 | 低 | 极低 | 仅导致引导重复显示，无数据丢失 |
| PermissionManager API 不可用 | 中 | 低 | guard / fallback，图标默认显示 notDetermined 黄色 |
| macOS 14.4 前 systemAudioCapture 不可用 | 中 | 中 | `if #available(macOS 14.4, *)` 条件隐藏系统音频图标 |

---

## 9. 测试要点

| # | 测试场景 | 验证点 |
|---|---------|--------|
| 1 | 清除 UserDefaults → 启动 | 引导自动显示 |
| 2 | 完成引导 → 重启 | 引导不再显示 |
| 3 | 引导中点击"跳过" | 引导立即消失，hasCompletedOnboarding=true |
| 4 | 引导中直接操作 UI | 引导自动跳步/消失，操作正常执行 |
| 5 | 麦克风权限 granted → 图标青色 | StatusBar 正确 |
| 6 | 系统设置中撤销麦克风权限 | ≤5s 后图标变红 |
| 7 | 窗口缩小到 < 400px | 图标区不溢出，状态文字截断 |
| 8 | 点击权限图标 | 打开系统偏好设置 |
| 9 | macOS 14.3 运行 | 系统音频图标隐藏，麦克风图标正常 |
| 10 | 编译通过 | 无 error/warning |

---

## 10. 实现优先级

| 优先级 | 模块 | 估时 |
|--------|------|------|
| P0 | 恢复 `checkAudioPermissionsSilently()` + 权限轮询 | 15min |
| P0 | StatusBarView 权限图标区 | 30min |
| P1 | OnboardingManager + CoachMarkOverlayView | 45min |
| P1 | CoachMarkTooltipView 样式实现 | 30min |
| P2 | 高亮动画 + pulse 效果 | 20min |
| P2 | 录制按钮 warning badge | 15min |

**总预估**: ~2.5h 开发 + 0.5h 测试
