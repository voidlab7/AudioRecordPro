# Architecture Review: Sidebar Tab 命名优化与录制完成自动切换

> 角色: 矩·架构师 | Task: task-0504-ui-tab-naming
> 日期: 2026-05-04

---

## 1. 架构概览

### 1.1 当前调用链

```
MainViewController.handleRecordingComplete(recording)
    → mainWindowView.updateRecordingState(.idle)
    → mainWindowView.updateStatus("录制完成: ...")
    → mainWindowView.addRecordedFile(fileInfo)
        → sidebarView.addRecordedFile(file)
            → recordedFilesView.addRecordedFile(file)
                → recordedFiles.insert(file, at: 0)
                → selectedFile = file
                → rebuildFileRows()
    → mainWindowView.updatePlaybackDisplay(...)
```

### 1.2 改造后调用链

```
MainViewController.handleRecordingComplete(recording)
    → mainWindowView.updateRecordingState(.idle)
    → mainWindowView.updateStatus("录制完成: ...")
    → mainWindowView.addRecordedFile(fileInfo)
        → sidebarView.addRecordedFile(file)
            → recordedFilesView.addRecordedFile(file)
    → mainWindowView.updatePlaybackDisplay(...)
    → mainWindowView.switchToFilesTabAndHighlight()          ← [NEW]
        → sidebarView.switchToFilesTabAndHighlight()         ← [NEW]
            → tabContainer.selectTab("recordedFiles", animated: true) ← [NEW overload]
            → DispatchQueue.asyncAfter(0.35s)
                → recordedFilesView.highlightNewestFile()    ← [NEW]
                    → firstRow.playHighlightAnimation()      ← [NEW]
```

---

## 2. TabContainerView 新增 `selectTab(_:animated:)` 实现方案

### 2.1 API 设计

```swift
// TabContainerView.swift - 新增方法

/// 选择 Tab（支持过渡动画）
/// - Parameters:
///   - tabId: 目标 Tab ID
///   - animated: 是否使用 crossfade 过渡动画 (250ms)
func selectTab(_ tabId: String, animated: Bool) {
    guard let tab = tabs.first(where: { $0.id == tabId }) else { return }
    guard tabId != selectedTabId else { return } // 已在目标 Tab，短路返回
    
    // 更新按钮状态（立即生效，不做按钮动画延迟）
    updateTabButtonStates(selectedId: tabId)
    
    if animated {
        animateContentTransition(to: tab)
    } else {
        updateContentView(with: tab)
    }
    
    selectedTabId = tabId
    delegate?.tabContainerViewDidSelectTab(self, tabId: tabId)
}
```

### 2.2 内容过渡动画

```swift
// TabContainerView.swift - 新增 private 方法

private func animateContentTransition(to tab: TabItem) {
    let duration: TimeInterval = 0.25 // 250ms — 页面级切换标准

    // 准备新视图（初始透明）
    tab.view.translatesAutoresizingMaskIntoConstraints = false
    tab.view.alphaValue = 0
    contentView.addSubview(tab.view)

    NSLayoutConstraint.activate([
        tab.view.topAnchor.constraint(equalTo: contentView.topAnchor),
        tab.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        tab.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        tab.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])

    // 获取旧视图
    let oldViews = contentView.subviews.filter { $0 !== tab.view }

    // 交叉淡入淡出
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        context.allowsImplicitAnimation = true
        
        for oldView in oldViews {
            oldView.animator().alphaValue = 0
        }
        tab.view.animator().alphaValue = 1
    }, completionHandler: {
        // 动画完成：清理旧视图
        for oldView in oldViews {
            oldView.removeFromSuperview()
            oldView.alphaValue = 1 // 恢复以备后续复用
        }
    })
}
```

### 2.3 原有 `selectTab(_:)` 保持兼容

```swift
/// 原有无动画版本（保持向后兼容，用户手动点击 Tab 时调用）
func selectTab(_ tabId: String) {
    selectTab(tabId, animated: false)
}
```

**注意**: 现有用户点击 Tab 走的是 `button.onClick → selectTab(tabs[index].id)`，不传 animated 参数，默认无动画——保持当前行为不变。

---

## 3. handleRecordingComplete 中触发自动切换的时序

### 3.1 MainViewController.swift 修改

```swift
// MainViewController.swift - handleRecordingComplete 方法
// 在第 442 行 mainWindowView.addRecordedFile(fileInfo) 之后追加:

private func handleRecordingComplete(_ recording: AudioRecording) {
    lastRecordedFile = recording.fileURL
    mainWindowView.updateRecordingState(.idle)
    mainWindowView.updateStatus("录制完成: \(recording.fileName)")
    
    logger.info("录制完成: \(recording.fileName), 时长: \(recording.formattedDuration), 大小: \(recording.formattedFileSize)")
    
    let fileInfo = RecordedFileInfo(
        url: recording.fileURL,
        name: recording.fileName,
        date: recording.createdAt,
        duration: recording.duration,
        size: recording.fileSize
    )
    selectedPlaybackFile = fileInfo
    mainWindowView.addRecordedFile(fileInfo)
    mainWindowView.updatePlaybackDisplay(
        fileName: fileInfo.name,
        currentTime: 0,
        duration: fileInfo.duration,
        isPlaying: false,
        isPaused: false
    )
    
    // ─── [NEW] 自动切换到 FILES Tab 并高亮新文件 ───
    mainWindowView.switchToFilesTabAndHighlight()
    
    // 自动播放（如果启用）
    if AppConfiguration().autoPlayAfterRecording {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.playRecording()
        }
    }
}
```

### 3.2 MainWindowView.swift 新增

```swift
// MainWindowView.swift - 新增公开方法

/// 切换到 FILES Tab 并高亮最新录音文件
func switchToFilesTabAndHighlight() {
    sidebarView.switchToFilesTabAndHighlight()
}
```

### 3.3 SidebarView.swift 新增

```swift
// SidebarView.swift - MARK: - Public Methods 区域新增

/// 录制完成后，自动切换到 FILES Tab 并高亮最新文件
func switchToFilesTabAndHighlight() {
    let currentTab = tabContainer.getSelectedTabId()
    
    if currentTab == "recordedFiles" {
        // 已在 FILES Tab，直接高亮（无需切换）
        recordedFilesView.highlightNewestFile()
    } else {
        // 切换到 FILES Tab（带 crossfade 动画）
        tabContainer.selectTab("recordedFiles", animated: true)
        
        // 等待切换动画完成后再触发高亮
        // 250ms 动画 + 100ms 布局稳定余量 = 350ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.recordedFilesView.highlightNewestFile()
        }
    }
}
```

### 3.4 完整时序图

```
T+0ms      : handleRecordingComplete() 被调用
             addRecordedFile() 执行 → 数据已在列表中
             switchToFilesTabAndHighlight() 被调用
T+0-250ms  : Tab 切换 crossfade 动画（若需要切换）
T+350ms    : highlightNewestFile() → playHighlightAnimation()
T+350-600ms    : Phase 1 — 高亮渐现 (opacity 0→0.25)
T+600-1850ms   : Phase 2 — 脉冲呼吸 (opacity 0.15↔0.30)
T+1850-2850ms  : Phase 3 — 高亮渐隐 (opacity 0.15→0)
T+2850ms   : 动画完成，恢复正常外观
```

**总时长 < 3秒**，满足 ≤500ms 到达 FILES Tab + 2.5秒高亮。

---

## 4. 新文件高亮动画实现（CALayer + CAAnimationGroup）

### 4.1 RecordedFilesView 新增方法

```swift
// RecordedFilesView.swift - 新增公开方法

/// 高亮列表中最新的文件行（第一行）
func highlightNewestFile() {
    guard !recordedFiles.isEmpty else { return }
    
    // 确保滚动到顶部（新文件在 index 0）
    scrollView.contentView.scroll(to: .zero)
    scrollView.reflectScrolledClipView(scrollView.contentView)
    
    // 获取第一行视图
    guard let firstRow = fileStack.arrangedSubviews.first as? IndustrialRecordedFileRowView else {
        return
    }
    
    firstRow.playHighlightAnimation()
}
```

### 4.2 IndustrialRecordedFileRowView 新增高亮能力

```swift
// RecordedFilesView.swift - IndustrialRecordedFileRowView 内新增

// MARK: - Highlight Animation

/// 高亮动画层（覆盖在背景之上）
private var highlightLayer: CALayer?

/// 播放新文件高亮动画（2.5 秒脉冲）
func playHighlightAnimation() {
    // 清理已有动画
    cancelHighlightAnimation()
    
    guard let parentLayer = layer else { return }
    
    // 创建高亮覆盖层
    let hl = CALayer()
    hl.frame = bounds
    hl.backgroundColor = IndustrialColors.primaryContainer.cgColor
    hl.opacity = 0
    hl.cornerRadius = IndustrialCornerRadius.xs
    parentLayer.insertSublayer(hl, above: indicatorLayer)
    highlightLayer = hl
    
    // 显示左侧指示条
    indicatorLayer.isHidden = false
    
    // --- 构建三阶段动画 ---
    
    // Phase 1: 渐现 (250ms)
    let fadeIn = CABasicAnimation(keyPath: "opacity")
    fadeIn.fromValue = 0.0
    fadeIn.toValue = 0.25
    fadeIn.duration = 0.25
    fadeIn.beginTime = 0
    
    // Phase 2: 脉冲呼吸 (1250ms, 2 次循环)
    let pulse = CAKeyframeAnimation(keyPath: "opacity")
    pulse.values = [0.25, 0.30, 0.15, 0.30, 0.15]
    pulse.keyTimes = [0, 0.25, 0.5, 0.75, 1.0]
    pulse.duration = 1.25
    pulse.beginTime = 0.25
    
    // Phase 3: 渐隐 (1000ms)
    let fadeOut = CABasicAnimation(keyPath: "opacity")
    fadeOut.fromValue = 0.15
    fadeOut.toValue = 0.0
    fadeOut.duration = 1.0
    fadeOut.beginTime = 1.5
    
    // 组合
    let group = CAAnimationGroup()
    group.animations = [fadeIn, pulse, fadeOut]
    group.duration = 2.5
    group.fillMode = .forwards
    group.isRemovedOnCompletion = false
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
    
    // 动画完成后清理
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
        self?.cleanupHighlight()
    }
    hl.add(group, forKey: "newFileHighlight")
    CATransaction.commit()
}

/// 取消高亮动画（用户交互中断时调用）
func cancelHighlightAnimation() {
    highlightLayer?.removeAllAnimations()
    cleanupHighlight()
}

/// 清理高亮层
private func cleanupHighlight() {
    highlightLayer?.removeFromSuperlayer()
    highlightLayer = nil
    if !isSelectedRow {
        indicatorLayer.isHidden = true
    }
}
```

### 4.3 mouseUp 中中断高亮

```swift
// IndustrialRecordedFileRowView - 修改 mouseUp
override func mouseUp(with event: NSEvent) {
    layer?.transform = CATransform3DIdentity
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    cancelHighlightAnimation()  // ← [NEW] 用户点击时中断高亮
    onSelect?()
    if event.clickCount >= 2 {
        onDoubleClick?()
    }
}
```

---

## 5. Tab 命名代码变更

### 5.1 SidebarView.swift 第 138-144 行

```swift
// BEFORE:
let audioRecorderTab = TabItem(
    id: "audioRecorder",
    title: "Audio Recorder",
    icon: "waveform",
    view: audioRecorderTabView
)

// AFTER:
let audioRecorderTab = TabItem(
    id: "audioRecorder",
    title: "INPUT",
    icon: "waveform",
    view: audioRecorderTabView
)
```

### 5.2 SidebarView.swift 第 163-169 行

```swift
// BEFORE:
let recordedFilesTab = TabItem(
    id: "recordedFiles",
    title: "Saved Files",
    icon: "folder",
    view: recordedFilesTabView
)

// AFTER:
let recordedFilesTab = TabItem(
    id: "recordedFiles",
    title: "FILES",
    icon: "folder",
    view: recordedFilesTabView
)
```

> 注: 图标保留 `folder`（设计评估后认为无需更换）。

---

## 6. 完整修改清单

| # | 文件 | 行号 | 类型 | 描述 |
|---|------|------|------|------|
| 1 | `SidebarView.swift` | 140 | MODIFY | title: "Audio Recorder" → "INPUT" |
| 2 | `SidebarView.swift` | 165 | MODIFY | title: "Saved Files" → "FILES" |
| 3 | `SidebarView.swift` | ~576 | ADD | 新增方法 `switchToFilesTabAndHighlight()` |
| 4 | `TabContainerView.swift` | ~105 | ADD | 新增方法 `selectTab(_:animated:)` |
| 5 | `TabContainerView.swift` | ~117 | MODIFY | 原 `selectTab(_:)` 改为调用 `selectTab(_:animated: false)` |
| 6 | `TabContainerView.swift` | ~190 | ADD | 新增 `animateContentTransition(to:)` |
| 7 | `MainWindowView.swift` | ~204 | ADD | 新增方法 `switchToFilesTabAndHighlight()` |
| 8 | `MainViewController.swift` | ~449 | ADD | 在 addRecordedFile 后调用 `switchToFilesTabAndHighlight()` |
| 9 | `RecordedFilesView.swift` | ~108 | ADD | 新增方法 `highlightNewestFile()` |
| 10 | `RecordedFilesView.swift` | ~215 | ADD | IndustrialRecordedFileRowView 新增 `highlightLayer` 属性 |
| 11 | `RecordedFilesView.swift` | ~345 | ADD | 新增 `playHighlightAnimation()` / `cancelHighlightAnimation()` / `cleanupHighlight()` |
| 12 | `RecordedFilesView.swift` | ~339 | MODIFY | mouseUp 中加入 `cancelHighlightAnimation()` |
| 13 | `IndustrialDesignTokens.swift` | ~387 | ADD (可选) | `static let tabTransition: TimeInterval = 0.25` |

---

## 7. 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| Tab 切换动画与用户手动点击冲突 | 低 | Tab 状态不一致 | `guard tabId != selectedTabId` 防重入 |
| 高亮层与 `updateAppearance` 冲突 | 低 | 视觉闪烁 | highlightLayer 独立于背景层，不影响 `layer?.backgroundColor` |
| asyncAfter 在窗口最小化时执行 | 中 | 无可见效果 | 可接受，动画在不可见时执行无副作用 |
| 快速连续录制产生多次高亮 | 中 | 动画叠加 | `playHighlightAnimation()` 首行清理旧动画 |
| macOS 12 以下 NSAnimationContext 差异 | 极低 | 动画异常 | 项目 target 已是 macOS 13+ |

---

## 8. 测试场景

| # | 场景 | 操作 | 预期结果 |
|---|------|------|---------|
| 1 | INPUT Tab 录完 | 在 INPUT Tab 开始录制并停止 | 自动切换到 FILES，新文件高亮 2.5s |
| 2 | FILES Tab 录完 | 在 FILES Tab 开始录制并停止 | 不切换，新文件高亮 2.5s |
| 3 | 高亮中断 | 高亮期间点击其他文件 | 高亮立即消失，点击的文件被选中 |
| 4 | 快速连续录制 | 连续两次短录制 | 第二次高亮取代第一次 |
| 5 | Tab 标题 | 启动应用 | Tab 显示 "INPUT" / "FILES" |
| 6 | Tab 手动切换 | 用户手动点击 Tab | 无动画，行为与现有一致 |
| 7 | 编译验证 | `build-app.sh` | 编译通过，无 warning |

---

## 9. 性能影响

- **内存**: 新增 1 个 CALayer（highlightLayer），约 4KB，动画结束后释放
- **CPU**: CAAnimationGroup 由 Core Animation 在 render server 执行，不占主线程
- **帧率**: 单层 opacity 动画 = GPU compositing，对 60fps 无影响

---

*签字: 矩·架构师 / 2026-05-04*
