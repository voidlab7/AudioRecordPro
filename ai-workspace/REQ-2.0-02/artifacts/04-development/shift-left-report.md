# REQ-2.0-02 Shift-Left Report

> **开发者**: 铸·开发  
> **日期**: 2026-05-28  
> **编译状态**: ✅ BUILD SUCCEEDED  

---

## 变更清单

| # | 文件 | 变更类型 | 描述 |
|---|------|---------|------|
| 1 | `StatusBarView.swift` | 修改 | idle 态文案从"● 准备就绪"→"准备录制"/"选择录制目标，点击 ● 开始"；新增 `updateIdleGuide(targetName:)` 方法 |
| 2 | `WaveformView.swift` | 修改 | 重构 `draw()` 分支逻辑，新增 `drawIdlePlaceholder()` 方法（SF Symbol + 引导文案） |
| 3 | `ControlPanelView.swift` | 修改 | idle 态调用 `startIdleBreathAnimation()`；preparing 态调用 `stopIdleBreathAnimation()`；新增两个动画方法 |
| 4 | `MainWindowView.swift` | 修改 | idle/recording 态分支添加 accessibility 标签；idle 态调用 `statusBarView.updateIdleGuide()` |
| 5 | `SidebarView.swift` | 修改 | 新增 `getSelectedProcessName()` 便捷方法 |

---

## 自检清单

### Layer 0 — 编译 & 类型安全
- [x] `xcodebuild` BUILD SUCCEEDED
- [x] 无新增编译警告
- [x] 无 force unwrap 新增

### Layer 1 — 逻辑安全
- [x] 无状态机死锁（ViewMode 三态互斥，`switchToMode` 有 guard）
- [x] 无循环引用（CABasicAnimation 不持有 self 引用）
- [x] 呼吸动画在离开 idle 态时正确清理（`stopIdleBreathAnimation` 移除动画）

### Layer 2 — 边界情况
- [x] idle 态 `waveformData` 为空时正确显示占位内容
- [x] 录制停止后回到 idle 态，`waveformData` 不为空时显示旧波形（预期行为）
- [x] `getSelectedProcessName()` 返回 Optional，MainWindowView 处理 nil

### Layer 3 — 一致性
- [x] 所有颜色使用 IndustrialColors token
- [x] 所有字体使用 IndustrialTypography token
- [x] 动画遵循 animation-discipline（shadowOpacity 呼吸 2s easeInEaseOut）

### Layer 4 — 无障碍
- [x] waveformView 设置 accessibilityLabel/Help
- [x] SF Symbol 绘制时提供 accessibilityDescription
- [ ] ⚠️ 录制按钮 VoiceOver 标签待补充（当前使用默认行为）
- [ ] ⚠️ prefers-reduced-motion 检测待补充（呼吸动画应尊重系统偏好）

---

## 已知技术债务

| 优先级 | 描述 | 建议 |
|--------|------|------|
| P2 | 呼吸动画未检测 `NSWorkspace.shared.accessibilityDisplayOptions.reduceMotion` | 下版本在 `startIdleBreathAnimation()` 中添加检测 |
| P2 | 录制按钮 `accessibilityLabel` 未随状态变化更新 | 建议在 `updateRecordingState` 中同步更新 |

---

## 交接块

- **来源**: 铸·开发  
- **目标**: 鉴·QA  
- **产出路径**: `ai-workspace/REQ-2.0-02/artifacts/04-development/shift-left-report.md`  
- **摘要**: REQ-2.0-02 开发完成，5 个文件变更，编译通过，2 个 P2 技术债务待后续版本处理  
- **下游关注**: 三态切换的视觉一致性测试、VoiceOver 可用性验证
