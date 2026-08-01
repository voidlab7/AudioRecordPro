# AudioRecordMac 初始化调用链分析

## 1. 入口：applicationDidFinishLaunching

```
AppDelegate.applicationDidFinishLaunching (line 43)
├── clearLogFiles()                         — 删旧日志
├── Logger 初始化                            — logger.info("应用程序启动完成") 在 clearLogFiles 前被删
├── NSApp.setActivationPolicy(.regular)     — 设为前台 App
├── requestAudioCapturePermissions()        — 异步请求麦克风+TCC 权限
├── createMainWindow()                      — 主流程
│   ├── NSWindow() 实例化                   — isVisible=false
│   ├── DispatchQueue.main.async { ... }    — 入队异步块(line 301)
│   ├── MainViewController() 创建           — 无自定义 init
│   ├── window.contentViewController = vc   — ⚡ 触发 view 加载
│   │   │
│   │   ├── loadView() (MainViewController:68)
│   │   │   └── MainWindowView()  ← 关键路径
│   │   │       │
│   │   │       ├─ Phase 1: stored property 初始化（声明顺序）
│   │   │       │   1.  logger = Logger.shared
│   │   │       │   2.  splitView = NSSplitView()
│   │   │       │   3.  sidebarView = SidebarView()    → init→setupView→创建 TabContainerView
│   │   │       │   4.  contentView = NSView()
│   │   │       │   5.  titleBarView = TitleBarView()  → init→setupView
│   │   │       │   6.  editToolbarView = EditToolbarView() → init→setupView
│   │   │       │   7.  trackPanelView = TrackPanelView()   → init→setupView
│   │   │       │   8.  levelMeterCardView = LevelMeterCardView() → init→setupView
│   │   │       │   9.  trackPanelWidthConstraint = nil (IUO)
│   │   │       │  10.  recordingContentView = NSView()
│   │   │       │  11.  waveformView = WaveformView()     → init→setupView
│   │   │       │  12.  controlPanelView = ControlPanelView() → init→setupView
│   │   │       │  13.  statusBarView = StatusBarView()   → init→setupView
│   │   │       │  14.  middleAreaView = NSView()
│   │   │       │  15.  lastCompletedFile = nil
│   │   │       │  16.  tracksView = TracksView()         → init→setupView
│   │   │       │  17.  levelMetersOverlay = LevelMetersOverlay() → init(直接设layer)
│   │   │       │  18-24. 标量属性/枚举初始化
│   │   │       │
│   │   │       ├─ Phase 2: super.init(frame:)
│   │   │       │
│   │   │       └─ Phase 3: setupView()
│   │   │            ├── setupTitleBar()       — addSubview
│   │   │            ├── setupSplitView()      — addSubview
│   │   │            ├── setupSidebar()        — sidebarView.delegate = self
│   │   │            │   └── 触发 TabContainerViewDelegate 回调
│   │   │            │       └── sidebarViewDidChangeSourceSelection()
│   │   │            │           └── updateTracksDisplay()
│   │   │            ├── setupContentView()    — 12 步 view 层级组装
│   │   │            │   ├── contentView → recordingContentView (4个约束)
│   │   │            │   ├── editToolbarView → contentView
│   │   │            │   ├── middleAreaView → recordingContentView
│   │   │            │   ├── trackPanelView → middleAreaView
│   │   │            │   ├── waveformView → middleAreaView
│   │   │            │   ├── levelMeterCardView → middleAreaView
│   │   │            │   ├── controlPanelView → recordingContentView
│   │   │            │   ├── statusBarView → recordingContentView
│   │   │            │   └── 旧组件隐藏
│   │   │            ├── setupConstraints()    — 64 行 AutoLayout 约束
│   │   │            └── setupAccessibility()  — 标记 accessibility
│   │   │
│   │   ├── viewDidLoad()                     — 当前未执行到
│   │   │   └── setupInitialState()           — 7 个子调用
│   │   │
│   │   └── （contentViewController 设置完成）
│   │
│   ├── makeKeyAndOrderFront(nil)             — ❌ 从未执行
│   ├── orderFrontRegardless()                — ❌ 从未执行
│
├── 兜底 launch fallback (0.3s after)         — ❌ 从未执行
└── setupSettingsMenu + setupKeyboardShortcuts
```

## 2. 日志证据

当前唯一可靠的标记点：
```
14:38:30.774  loadView().logger.info  — "🔍 [DIAG] loadView 开始"
14:38:31.010  SidebarView.logger.info — "侧边栏切换到Tab: audioRecorder"
14:38:31.044  async(301) block       — "主线程调整完成"
```

## 3. 已知断点

| 应执行 | 已确认？ | 说明 |
|--------|---------|------|
| loadView 开始 | ✅ | Logger 日志可见 |
| MainWindowView() 创建 | ‼️ | 无直接日志，但 Sidebar callbak 说明 setupSidebar 已执行 |
| Phase 1 属性初始化 | ？ | 11 个自定义 View 的 init→setupView，逐一未知 |
| setupView() 入口 | ⚠️ | logger.info 未出现（Logger 从 MWV 调用失效） |
| setupTitleBar | ？ | |
| setupSplitView | ？ | |
| setupSidebar | ✅ | 通过 SidebarView 回调间接确认 |
| setupContentView | ？ | **最可能断点** — 12 步层级组装 |
| setupConstraints | ？ | 64 行 AutoLayout |
| setupAccessibility | ？ | |
| viewDidLoad | ❌ | 确认未到 |
| makeKeyAndOrderFront | ❌ | 确认未执行 |

## 4. 可疑点（优先级排序）

1. **setupContentView 中的 AutoLayout** — `NSLayoutConstraint.activate` 在 view 不在 window 中时可能触发异常
2. **setupConstraints 的交叉引用** — 64 行约束依赖完整 view 层级，setupContentView 后视图可能未完全就绪
3. **Phase 1 属性 init 中的 setupView** — 11 个子 View init 都调用 setupView，可能某个 throw
4. **Logger.shared 在 MWV 属性初始化时访问** — 可能是时序问题
