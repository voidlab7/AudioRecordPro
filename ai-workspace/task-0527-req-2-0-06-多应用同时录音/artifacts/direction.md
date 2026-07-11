# Direction — REQ-2.0-06 多应用同时录音 + 多轨道显示

**Task**: task-0527-req-2-0-06-多应用同时录音
**Phase**: 01-ideation | **Agent**: 启·执事
**Created**: 2026-05-30

---

## 1. 需求一句话描述

支持用户在侧边栏同时勾选多个应用，每个应用独立录制为一条轨道，录制过程中主区域显示所有轨道的实时滚动波形。

## 2. 核心价值主张

| 维度 | 现状 | 目标 |
|------|------|------|
| 录制源 | 单选（仅 1 个应用或全部系统声音） | 多选（最多 5 个音源同时录制） |
| 输出 | 1 个混录文件 | N 个独立音频文件（同组时间戳） |
| 波形 | 单轨道显示 | 多轨道等分实时波形 |
| 竞品差距 | 无法同时录制多应用 | 补齐 Audio Capture Pro 的核心能力 |

## 3. 技术可行性快速评估

### 3.1 已有能力（可直接复用）

| 能力 | 代码位置 | 状态 |
|------|----------|------|
| 进程枚举 & 列表 | `AudioProcessEnumerator` | ✅ 成熟 |
| 单进程 Process Tap 录制 | `CoreAudioProcessTapRecorder` | ✅ 成熟 |
| 多 PID 列表传入 | `setTargetPIDs(_ pids: [pid_t])` | ✅ 已有接口 |
| 轨道信息模型 | `TrackInfo` 结构体 | ✅ 已有 |
| 轨道面板多行显示 | `TrackPanelView.updateTracks()` | ✅ 已有 |
| 工业深色 UI 体系 | `IndustrialDesignTokens` | ✅ 完整 |
| 侧边栏应用行 | `IndustrialProcessRowView` | ⚠️ 需改造（单选→多选） |

### 3.2 关键技术风险

| # | 风险 | 严重度 | 验证方式 | 缓解 |
|---|------|--------|---------|------|
| R1 | macOS ScreenCaptureKit/ProcessTap 是否支持同时多 PID 独立 tap | **高** | 技术 Spike：同时为 3 个 PID 创建独立 ProcessTap | 如不支持：退化为系统混音 + 应用内分离（降级方案） |
| R2 | 3-5 路 48kHz 音频同时写入的 I/O 压力 | **中** | Spike 中监控 CPU/磁盘 | 异步 I/O + 独立写入队列 |
| R3 | 多路电平回调的 UI 刷新压力 | **中** | 性能测试 | 节流合并 + 只刷新选中轨道电平 |

### 3.3 架构决策建议

**录制引擎 key 改造（方案 A — 推荐）**：

```swift
// 改造前: activeRecorders: [AudioSourceType: AudioRecorderProtocol]
// 改造后: activeRecorders: [String: AudioRecorderProtocol]
// key 格式: "process_{pid}" | "microphone" | "system"
```

理由：
- `AudioSourceType` 枚举无法表达多个 `.specificProcess` 实例
- 字符串 key 简单直观，支持任意数量的进程实例
- 不需要新建复杂的数据结构

## 4. 改造范围识别

### 4.1 必须改动

| 文件 | 改动类型 | 描述 |
|------|---------|------|
| `SidebarView.swift` | **UI 改造** | 工业进程行增加 Checkbox；onClick 逻辑从 `selectedPIDs = [pid]` 改为 toggle 逻辑 |
| `IndustrialProcessRowView` | **UI 改造** | 增加 Checkbox 子视图 + isChecked 属性 |
| `AudioRecorderController.swift` | **核心改造** | `activeRecorders` key 改为 String；新增 `startMultiSourceRecording` 多实例并行 |
| `CoreAudioProcessTapRecorder.swift` | **扩展** | 每个进程创建独立实例（非共享） |
| `TracksView.swift` | **UI 改造** | 多轨道等分高度布局；每轨道独立波形 + 应用名 + 状态指示 |
| `MainViewController.swift` | **流程改造** | `selectedPIDs` 保持多选；录制时传全部 PID；轨道数据联动 |
| `TrackInfo` | **模型扩展** | 增加 `pid` / `sourceIdentifier` 字段 |
| `MainWindowView.swift` | **布局协调** | 轨道区域随选中数量动态分屏 |

### 4.2 可选改动（V2.0 MVP 可暂缓）

- `TrackPanelView.swift` — Mute/Solo 功能可预留但 disabled
- 多轨编辑器 — V2.1 负责
- 轨道断连恢复 — MVP 仅标记"已断开"

## 5. 阶段建议

| 阶段 | 产出 | 预估 |
|------|------|------|
| 技术 Spike | 多 Process Tap 可行性验证报告 | 1 天 |
| PRD | 枢产出标准化 PRD | 0.5 天 |
| 设计 | 绘产出 UI 设计稿 | 1 天 |
| 开发 | 侧边栏多选 + 录制引擎 + 多轨波形 + 联动 | 4 天 |
| 测试 | 鉴产出 QA 报告 | 1 天 |
| **总计** | | **7.5 天** |

## 6. 交棒方向

→ **Phase 02-requirement**: 交由 PM_枢 产出 PRD
→ 枢需要关注：技术 Spike 结果决定 MVP 范围
→ 如果多 Tap 不可行，PRD 需要包含降级方案