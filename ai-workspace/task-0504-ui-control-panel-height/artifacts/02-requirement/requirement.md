# 需求文档：压缩 ControlPanel 高度释放 TracksView 空间

> Task ID: task-0504-ui-control-panel-height
> 优先级: P2 | 类型: design | 路由: 绘·设计 → 矩·架构

---

## 1. 背景

ControlPanelView（`ControlPanelView.swift`）固定高度 150px，在 500px 窗口高度中占 30%。

**内容清单**（自上而下）：
1. 顶部分隔线（1px）
2. Header 标签 "TRANSPORT CONTROL" + Status Badge "STANDBY"（~24px）
3. 中部空白区（约 20px 上间距）
4. 按钮区域：Play(32×32) + Record(64×64 含 84×84 容器) + Stop(32×32)（~84px）
5. 计时器标签（左对齐，与按钮同 centerY）
6. 底部 Readout 标签 "INPUT BUS: READY..."（~20px）

**实际布局分析**：按钮容器 84px + header 24px + readout 20px + 间距 ≈ 约 128px 有效，但因为上下间距、底座阴影等设计元素导致需要 150px。

**问题**：TracksView 被挤压到约 84px，只能显示 1 行轨道信息 + 播放面板。

## 2. 目标

在保持 Industrial Design 专业感的前提下，将 ControlPanel 高度压缩到 100-120px，释放 30-50px 给 TracksView。

## 3. 功能需求

### 3.1 高度压缩方案评估
- [ ] 方案 A：将 150px 压缩为 120px（减少间距，按钮尺寸不变）
- [ ] 方案 B：将 150px 压缩为 100px（按钮从 64px 缩到 52px，容器从 84px 缩到 68px）
- [ ] 方案 C：将 header 和 readout 合并为一行，高度压缩到 90px

### 3.2 布局调整
- [ ] 评估计时器是否可以和 header 同行（"TRANSPORT CONTROL  00:12:34  STANDBY"）
- [ ] 评估录制中按钮缩小为 48px 后是否仍需要 150px 空间
- [ ] Play/Stop 按钮 32×32 是否足够清晰

### 3.3 对 TracksView 的收益
- [ ] 释放后 TracksView 高度从 ~84px 增加到 ~114-134px
- [ ] 能否多显示一行轨道信息或更完整的播放面板

## 4. 设计约束

- 录制按钮是核心 CTA（Call To Action），不能太小导致难以点击（最小 44pt macOS 标准）
- Industrial Design 的"硬件感"需要一定的按钮间距和底座空间
- 动画效果（录制时按钮 64→48）在压缩后仍需流畅
- 外环（outerRingLayer）和底座（buttonBaseLayer）的视觉权重需重新评估

## 5. 技术约束

| 文件 | 修改点 |
|------|--------|
| `MainWindowView.swift:118` | `controlPanelView.heightAnchor.constraint(equalToConstant: 150)` → 新值 |
| `ControlPanelView.swift:36-37` | `normalButtonSize: CGFloat = 64` / `recordingButtonSize: CGFloat = 48` |
| `ControlPanelView.swift:211-214` | 容器 84×84 约束 |
| `ControlPanelView.swift:221` | headerLabel topAnchor 间距 |
| `ControlPanelView.swift:250-251` | readout bottomAnchor 间距 |

## 6. 验收标准

| # | 条件 | 通过标准 |
|---|------|---------|
| 1 | 视觉效果 | 压缩后不显得拥挤，保持专业感 |
| 2 | 按钮可点击 | 录制按钮可点区域 ≥ 44×44pt |
| 3 | 动画正常 | 录制状态切换时按钮大小动画流畅 |
| 4 | TracksView 增益 | TracksView 高度增加 ≥ 30px |
| 5 | 无约束冲突 | 控制台无 Auto Layout 警告 |
| 6 | 构建通过 | `build-app.sh` 编译无错误 |

## 7. 当前与目标对比

```
当前（150px）:
┌─────────────────────────────────┐
│ TRANSPORT CONTROL    [STANDBY]  │ 24px
│                                 │ 20px 间距
│ 00:12:34   [▶] [●] [■]         │ 84px (按钮区)
│                                 │
│ INPUT BUS: READY  FORMAT: WAV   │ 22px
└─────────────────────────────────┘

目标（100-120px）:
┌─────────────────────────────────┐
│ TRANSPORT CONTROL    [STANDBY]  │ 20px
│ 00:12:34   [▶] [●] [■]         │ 68px (按钮区)
│ INPUT BUS: READY  FORMAT: WAV   │ 18px
└─────────────────────────────────┘
```
