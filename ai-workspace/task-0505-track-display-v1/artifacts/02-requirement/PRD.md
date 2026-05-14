# PRD: 音轨显示逻辑优化 — 动态 1~2 条轨道显示

> 版本: v1.0 | 作者: 枢·PM | 日期: 2026-05-05

---

## 1. 背景与目标

### 1.1 背景

当前 TracksView 始终根据侧边栏选择静态构建轨道列表，但用户视角需要更直观地理解"正在录什么"。核心 SDK 只支持单文件混音输出（MixedAudioRecorder），因此需要在 UI 层做视觉分离，让用户清楚看到每个输入源的实时状态。

### 1.2 目标

- **直觉可感知**：用户一眼看出当前录制了几路输入
- **动态响应**：开/关麦克风时轨道数量实时变化，有 fade 动画
- **信息完整**：每条轨道独立显示实时电平 + 来源类型标注
- **混音透明**：底部说明当前输出模式（单文件混音）

---

## 2. 功能需求

### FR-01: 动态轨道数量

| 条件 | 显示轨道数 | 轨道内容 |
|------|-----------|---------|
| 不开麦（默认） | 1 | 音源轨（全部系统声音 / 某进程） |
| 开麦 | 2 | 音源轨 + 麦克风轨 |

### FR-02: 音源轨（Track 1）

- 标题显示应用名称或"全部系统声音"
- 左侧图标：应用 icon（进程选中）或 🔊（系统声音）
- 实时电平表：独立 LevelMeterView，接收 SDK 回调 level
- 底部灰字来源标注：
  - "SYSTEM MIXDOWN" — 全部系统声音
  - "PROCESS TAP · PID {pid}" — 特定进程

### FR-03: 麦克风轨（Track 2，可选）

- 标题："麦克风"
- 左侧图标：🎤
- 实时电平表：独立 LevelMeterView（当前 SDK 只有一路 level 回调，V1 先共享同一 level 值，后续 SDK 升级后独立）
- 底部灰字来源标注："MICROPHONE INPUT"

### FR-04: 轨道插入/移除动画

- 麦克风轨插入：从下方 fade-in + slide-up，时长 0.25s，曲线 easeInOut
- 麦克风轨移除：fade-out + slide-down，时长 0.2s
- 音源轨始终存在，不做动画

### FR-05: 混合输出说明

- 当显示 2 条轨道时，底部追加一行说明：
  - 文案：`📤 混合输出为单文件`
  - 字体：IndustrialTypography.small
  - 颜色：IndustrialColors.textTertiary
  - 仅在 2 轨模式下可见

### FR-06: 独立电平显示

- 每条轨道拥有独立的 LevelMeterView 实例
- V1 限制：当前 SDK 只有一路 level 回调 → 两条轨道暂时共享同一 level 值
- 预留接口：未来 SDK 支持分轨 level 时可独立驱动

---

## 3. 非功能需求

| 项目 | 要求 |
|------|------|
| 性能 | 动画不卡顿，电平刷新不掉帧（保持 60fps） |
| 兼容 | macOS 14.4+（与当前项目一致） |
| 可维护 | 轨道行复用 TrackRowView 组件，不复制粘贴代码 |

---

## 4. 技术约束

1. **SDK 限制**：MixedAudioRecorder 只输出单文件混音，UI 层分轨仅为视觉呈现
2. **单路 level**：`audioRecorderController.onLevel` 目前只有一个 Float 值，无法区分音源/麦克风
3. **不修改 SDK**：本次仅修改 App 层（AudioRecordApp），不动 AudioRecordKit

---

## 5. 影响范围

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `AudioRecordApp/Sources/Views/TracksView.swift` | **重构** | 核心：动态轨道逻辑 + 动画 + 来源标注 |
| `AudioRecordKit/Sources/API/Types.swift` | **小改** | TrackInfo 新增 `sourceType` 字段 |
| `AudioRecordApp/Sources/Views/MainWindowView.swift` | **适配** | updateTracksDisplay() 传递来源类型 |
| `AudioRecordApp/Sources/Views/LevelMeterView.swift` | **不改** | 复用现有组件 |

---

## 6. 验收标准（AC）

- [ ] AC-01: 默认状态（不开麦）TracksView 仅显示 1 条轨道
- [ ] AC-02: 开启麦克风后，TracksView 显示 2 条轨道，带 fade 动画
- [ ] AC-03: 关闭麦克风后，第 2 条轨道 fade-out 移除
- [ ] AC-04: 每条轨道独立显示 LevelMeterView（视觉独立，V1 数据共享）
- [ ] AC-05: 音源轨下方显示灰字来源标注
- [ ] AC-06: 2 轨模式下底部显示"📤 混合输出为单文件"
- [ ] AC-07: 切换音源（系统声音 ↔ 进程）时，轨道标题/图标实时更新

---

## 7. 排期估算

| 阶段 | 预估 | 说明 |
|------|------|------|
| 设计审查 | 10min | 确认 UI 规范 |
| 架构设计 | 10min | 组件拆分方案 |
| 开发实现 | 30min | TracksView 重构 + 动画 |
| QA 测试 | 10min | 验收标准覆盖 |
| **合计** | **60min** | — |

---

## 交接块

```
来源: 枢·PM
状态: ✅ 完成
产物文件: ai-workspace/task-0505-track-display-v1/artifacts/02-requirement/PRD.md
评分: 自评 82/100
下游建议: 绘·设计审查 → 确认轨道行高度、间距、动画曲线是否符合 Industrial Design 规范
```
