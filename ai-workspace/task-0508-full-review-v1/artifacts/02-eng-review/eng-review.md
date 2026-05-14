# 🏗️ 工程架构审查 — AudioRecordMac Kit+App 分层重构

> **审查人**：矩·架构师  
> **日期**：2026-05-08  
> **范围**：AudioRecordKit（SDK）+ AudioRecordApp（UI 层）+ 构建系统  
> **变更量**：79 文件，+2278/-16049 行

---

## 总评分：85 / 100

| 维度 | 分数 | 权重 | 加权分 |
|------|------|------|--------|
| 分层清晰度 | 90 | 20% | 18.0 |
| 依赖方向 | 92 | 15% | 13.8 |
| 代码质量 | 82 | 20% | 16.4 |
| 并发安全 | 78 | 15% | 11.7 |
| 内存管理 | 80 | 10% | 8.0 |
| 可扩展性 | 88 | 10% | 8.8 |
| 构建系统 | 85 | 10% | 8.5 |
| **合计** | — | 100% | **85.2 ≈ 85** |

---

## 1. 分层清晰度 — 90/100 ✅

### 架构拓扑

```
AudioRecordKit/Sources/
├── API/               ← 公开接口层（Types, AudioConstraints, AudioRecordSDK_C）
├── Core/              ← 核心业务逻辑
│   ├── ProcessTap/    ← CoreAudio Process Tap 录制
│   ├── Recording/     ← 录制管理
│   └── Playback/      ← 播放管理
├── CAPI/              ← C 桥接层
└── Utils/             ← 工具类（Logger, FileManager, Config）

AudioRecordApp/Sources/
├── App/               ← AppDelegate, 启动入口
├── Controllers/       ← MainViewController（唯一控制器）
└── Views/             ← 纯 UI 组件（10 个文件）
```

### 评价
- **三层分离清晰**：API 定义公开类型 → Core 实现业务 → CAPI 暴露 C 接口
- **App 层薄**：只有 1 个控制器 + 10 个纯视图，职责明确
- **Types.swift 是好设计**：所有共享类型（RecordingMode, RecordingState, AudioProcessInfo, RecordedFileInfo, TrackInfo）集中定义在 API 层

### 小问题
- `IndustrialDesignSystem` 相关定义（IndustrialColors, IndustrialTypography 等）未在读取范围内，但应确保它们在 App 层而非 Kit 层——设计 Token 属于 UI 关注点

---

## 2. 依赖方向 — 92/100 ✅

### 依赖关系图

```
AudioRecordApp ──depends on──▶ AudioRecordKit
     │                              │
     │ Views → Controllers          │ API → Core → Utils
     └── uses public types ─────────┘
```

### 评价
- ✅ **单向依赖**：App → Kit，Kit 不引用 App 任何内容
- ✅ **Types 共享正确**：TrackInfo、RecordedFileInfo 等在 Kit/API 定义，App 层引用
- ✅ **Controller 不直接引用 Core**：通过 AudioRecorderController 中间层交互

### 小问题
- `MainViewController` 直接实例化 `CoreAudioProcessTapRecorder`（第 961, 1108 行），违反了 Kit 封装——应该通过 AudioRecorderController 提供进程列表接口
- TrackInfo 包含 `NSImage?`（AppKit 类型），导致 Kit 层依赖 AppKit——如果未来要支持 SwiftUI 或跨平台，这是耦合点

---

## 3. 代码质量 — 82/100

### 优点
- **命名规范**：方法名清晰描述行为（`updateRecordingState`, `rebuildProcessRows`, `handleRecordingComplete`）
- **MARK 分区**：所有文件使用 `// MARK: -` 区分逻辑块
- **Delegate 模式统一**：Views 通过 delegate 向上通信，不直接操作业务

### 问题列表

| 级别 | 文件 | 行 | 问题 |
|------|------|-----|------|
| P1 | MainViewController.swift | 961, 1108 | 绕过 SDK 封装直接使用 CoreAudioProcessTapRecorder |
| P1 | RecordedFilesView.swift | 159-194 | 私有 `loadRecordedFiles()` 重复了 Controller 层的文件加载逻辑 |
| P1 | SidebarView.swift | 213 | `addSubview(refreshButton)` 加到 self 而非 audioRecorderTabView——可能导致约束冲突 |
| P2 | ControlPanelView.swift | 109-111 | 类型强转 `statusBadge.cell as? NSTextFieldCell` 后又设置 `lineBreakMode`，逻辑冗余 |
| P2 | MainViewController.swift | 1036-1063 | `convertWAVToMP3` 使用 `Process.waitUntilExit()` 在后台线程——如果 afconvert 挂起会永久阻塞 |
| P2 | WaveformView.swift | 81 | `DispatchQueue.main.async { self.needsDisplay = true }` — `updateLevel` 本身可能已在主线程，多余派发 |
| P2 | LevelMeterView.swift | 165 | 手动数组移位 `for i in 0..<(bars.count-1) { bars[i] = bars[i+1] }` — 性能可优化为环形缓冲区 |

---

## 4. 并发安全 — 78/100 ⚠️

### 优点
- **UI 更新全在主线程**：所有 `onLevel`/`onStatus` 回调内使用 `DispatchQueue.main.async`
- **[weak self] 统一**：闭包全部捕获弱引用

### 风险点

| 级别 | 问题 | 文件 | 描述 |
|------|------|------|------|
| P1 | 竞态条件 | SidebarView.swift:395-413 | `preloadIcons` 在后台线程写 `iconCache`，`getCachedIcon` 在主线程读——无锁保护 |
| P1 | 线程安全 | MainViewController.swift:314 | `isRecording = true` 后立即异步操作，若权限回调慢于用户再次点击，可能双重触发 |
| P2 | Timer 泄漏 | WaveformView.swift:115 | `Timer.scheduledTimer` 如果在 deinit 前未 invalidate，会保持视图存活 |

### 建议
- `iconCache` 应使用 `NSCache` 或加 `DispatchQueue(label: "icon-cache")` 串行队列保护
- 录制开始应设置 `recordButton.isEnabled = false` 在权限检查期间（已部分实现但时序不严格）

---

## 5. 内存管理 — 80/100

### 优点
- 所有 delegate 为 `weak`
- 闭包全部 `[weak self]`
- Timer 在 `deinit` 和 `stop` 时 invalidate

### 风险点
- `SidebarView.iconCache: [String: NSImage]` 无上限——如果用户长时间运行且进程频繁变化，图标缓存会无限增长
- `LevelMeterView.bars` 固定 180 项，但 `recentRawLevels` 无 hard cap（只有 softcap 96 项），理论安全
- `rebuildFileRows()` 每次全部移除再重建视图——频繁调用时大量临时 View 分配/释放

---

## 6. 可扩展性 — 88/100 ✅

### 优点
- **新录制模式易接入**：`RecordingMode` 枚举 + `startMultiSourceRecording` 参数化设计
- **新 Tab 易添加**：`TabContainerView.addTab()` 接口化
- **设计系统扩展**：新增 Industrial 组件只需遵循 Token 系统
- **Delegate 隔离**：更换/添加视图不影响其他组件

### 可改进
- TracksView 的 `createTrackRow` 返回 `NSView`，未封装为独立组件——如果轨道行需要独立交互（如单独静音/Solo）需要重构
- `AudioFormat` 目前只有 m4a/wav，添加 mp3/flac 需同步修改 `settings` 计算属性和 `convertWAVToMP3` 逻辑

---

## 7. 构建系统 — 85/100

### build.sh 评价
- ✅ 编译成功，签名完成
- ✅ 资源拷贝完整
- ✅ 输出路径清晰 (`build/AudioRecordMac.app`)

### 可改进
- 未看到增量编译支持——每次全量重新编译
- 未集成 SwiftLint / SwiftFormat
- 未生成 dSYM 用于 crash 分析

---

## 总结：P0/P1/P2 问题汇总

### P0 — 无

### P1 — 需修复（3 项）
1. **SidebarView.iconCache 竞态**：后台写 + 主线程读无保护
2. **MainViewController 绕过 SDK 封装**：直接使用 CoreAudioProcessTapRecorder
3. **SidebarView refreshButton addSubview 错误**：应 add 到 audioRecorderTabView

### P2 — 建议修复（5 项）
4. convertWAVToMP3 添加超时机制
5. LevelMeterView bars 改为环形缓冲区
6. RecordedFilesView 去除重复的文件加载逻辑
7. WaveformView 去除多余主线程派发
8. 对 TrackInfo.appIcon 考虑用 Data 替代 NSImage 减少跨层耦合

---

## 架构亮点 🌟

1. **Kit/App 分离做得干净**：Types.swift 集中定义、API 层接口简洁、Core 层实现独立
2. **Delegate 模式一致**：从 View → MainWindowView → MainViewController → AudioRecorderController 的消息链清晰
3. **Industrial Design System 参数化**：所有视觉参数通过 Token 系统管理，更换主题只需改 Token 值

---

*审查完成。产出路径：`ai-workspace/task-0508-full-review-v1/artifacts/02-eng-review/eng-review.md`*
