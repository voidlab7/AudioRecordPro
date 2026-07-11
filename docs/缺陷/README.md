# Bug 追踪

> **更新时间**：2026-05-10  
> **状态说明**：🔴 Open | 🟡 In Progress | 🟢 Fixed | ⚪ Closed | 🔵 Won't Fix

---

## 编号规则

`BUG-{版本}-{序号}`，例如 `BUG-1.0-001`

---

## Open Bugs

| 编号 | 标题 | 优先级 | 模块 | 状态 | 发现日期 | 修复版本 |
|------|------|--------|------|------|----------|----------|
| BUG-1.0-001 | 播放时时间显示闪烁 | P2 | UI / TimerLabel | 🔴 Open | 2026-05-10 | — |

---

## Fixed Bugs

| 编号 | 标题 | 优先级 | 模块 | 修复日期 | 修复版本 |
|------|------|--------|------|----------|----------|
| — | — | — | — | — | — |

---

## Bug 详情

### BUG-1.0-001 播放时时间显示闪烁

| 字段 | 内容 |
|------|------|
| **编号** | BUG-1.0-001 |
| **标题** | 播放时 TRANSPORT CONTROL 时间显示闪烁 |
| **优先级** | P2（体验问题，不影响核心功能） |
| **严重性** | 中 — 视觉干扰，不影响录制/播放功能 |
| **状态** | 🔴 Open |
| **发现日期** | 2026-05-10 |
| **发现人** | 用户手动测试 |
| **发现场景** | REQ-1.0-01 验收测试期间 |
| **引入时间** | 未知（可能是早期 UI 实现时引入） |

#### 复现步骤

1. 录制一段系统音频（如 QQ 音乐）
2. 录制完成后，点击 PLAY/PAUSE 播放录音
3. 观察 TRANSPORT CONTROL 区域的时间显示（`00:00:22` 位置）

#### 预期行为

时间标签平滑更新，无闪烁。

#### 实际行为

播放过程中，时间标签出现闪烁现象。

#### 截图

![播放时间闪烁](https://zhiyan-ai-agent-with-1258344702.cos.ap-guangzhou.tencentcos.cn/copilot/c3c899e0-a6a0-40d4-b07e-8f8fda93230b/image-019e1181223c799382b4be53e6617255.png)

#### 可能原因分析

1. `TimerLabel` 或 `ControlPanelView` 中的定时器更新频率过高或与 UI 刷新冲突
2. 播放状态回调在非主线程更新 UI 导致闪烁
3. 时间格式化时字符串宽度变化导致布局抖动（如 `1` vs `22` 宽度不同）

#### 相关文件

- `AudioRecordApp/Sources/Views/TimerLabel.swift`
- `AudioRecordApp/Sources/Views/ControlPanelView.swift`
- `AudioRecordKit/Sources/Core/Protocols/AudioRecorderProtocol.swift`（播放回调）

#### 修复建议

- 检查 Timer 更新是否在主线程
- 使用等宽字体（monospaced）避免宽度抖动
- 降低刷新频率或使用 `CADisplayLink` 同步帧率
