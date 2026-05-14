# Design Spec: Sidebar Tab 命名优化与录制完成自动切换

> 角色: 绘·设计师 | Task: task-0504-ui-tab-naming
> 日期: 2026-05-04

---

## 1. Tab 命名方案评估

### 1.1 方案对比

| 方案 | Tab1 | Tab2 | 优点 | 缺点 | 推荐度 |
|------|------|------|------|------|--------|
| A | **INPUT** | **FILES** | 极简、4/5字符、工业感强 | "FILES" 偏通用，不能区分音频文件和其他 | ★★★★☆ |
| B | **SOURCE** | **RECORDINGS** | 音频专业术语、语义精确 | "RECORDINGS" 10字符，Tab按钮内拥挤 | ★★★☆☆ |
| C | **录制源** | **录音** | 中文直观 | 与 Industrial Design 全大写英文风格冲突 | ★★☆☆☆ |
| D | **CAPTURE** | **LIBRARY** | 动词+集合 | "LIBRARY" 暗示管理功能超出实际 | ★★★☆☆ |
| **E (推荐)** | **INPUT** | **FILES** | 最简洁、与图标语义互补、宽度友好 | — | ★★★★★ |

### 1.2 最终推荐: **INPUT / FILES**

**理由:**
1. **语义清晰**: "INPUT" 直观表达「选择录入源」功能，"FILES" 明确表达「已保存的录制文件」
2. **Industrial Design 一致性**: 全大写短单词，与 UI 中 "NO AUDIO PROCESSES DETECTED"、"CAPTURE FULL MAC OUTPUT"、"ADD MICROPHONE" 等标签风格统一
3. **宽度友好**: INPUT(5字) + FILES(5字)，在 240px Sidebar 的 Tab Bar 内均匀排列无压力
4. **去重**: 不再用 "Audio Recorder"（与应用名重复），不再用 "Saved Files"（冗余动词 "Saved"）

### 1.3 图标方案

| Tab | 当前图标 | 建议 | 理由 |
|-----|---------|------|------|
| INPUT | `waveform` | **保留** `waveform` | 波形图标 = 音频输入信号，语义准确 |
| FILES | `folder` | **保留** `folder` | 文件夹图标已被广泛认知，无需变更 |

---

## 2. 录制完成后自动切换动画方案

### 2.1 交互时序

```
[录制停止] → [handleRecordingComplete 回调]
    ↓ 立即 (≤50ms)
    addRecordedFile() — 将新文件插入列表
    ↓ 300ms 延迟（让用户看到状态栏 "录制完成" 反馈）
    ↓
判断当前 Tab 状态
    ├── 已在 FILES Tab → 跳过切换，直接执行新文件高亮（§3）
    └── 在 INPUT Tab → 执行 Tab 切换动画
            ↓ (250ms crossfade 过渡)
        [FILES Tab 完全可见]
            ↓ (50ms 等待布局稳定)
        [新文件高亮动画开始]（§3）
```

### 2.2 Tab 切换动画细节

| 属性 | 值 | 说明 |
|------|----|------|
| 触发时机 | 录制完成后 300ms | 给用户时间看状态反馈 |
| 动画时长 | 250ms | 页面级切换使用 250ms（比 120ms standard 更从容） |
| 缓动函数 | `easeOut` | `CAMediaTimingFunction(name: .easeOut)` |
| 内容过渡 | crossfade | 旧内容 opacity 1→0 (150ms)，新内容 opacity 0→1 (250ms) |
| Tab 按钮 | 即时切换选中态 | 按钮底部指示条滑动 + 文字颜色渐变 |

### 2.3 Tab 按钮视觉反馈

- 选中 Tab 底部 2px 高指示条，颜色 `primaryContainer` (#22d3ee)
- 切换时指示条位移动画 250ms easeOut
- 旧 Tab 文字: `primary` → `onSurfaceVariant` 渐变
- 新 Tab 文字: `onSurfaceVariant` → `primary` 渐变

### 2.4 防打断策略

| 场景 | 处理 |
|------|------|
| 用户已在 FILES Tab | 不切换，仅高亮新文件 |
| 用户已选中某文件 | 不取消选中，新文件高亮不影响现有选择 |
| 用户正在播放 | 仅高亮，不改变播放状态 |
| 切换动画中用户点击 | 立即完成动画，响应用户点击 |

---

## 3. 新文件高亮动画设计

### 3.1 动画时间线

```
t=0ms        : 文件行出现，背景为默认 surfaceContainerLow
t=0-250ms    : Phase 1 — 渐现，背景色 → primaryContainer @ 25% opacity
t=250-1750ms : Phase 2 — 脉冲呼吸，opacity 在 0.15 ~ 0.30 之间循环 2 次
t=1750-2500ms: Phase 3 — 渐隐，opacity 0.15 → 0
t=2500ms     : 恢复默认背景 surfaceContainerLow
```

**总时长: 2.5 秒**（在 2-3 秒需求范围内）

### 3.2 颜色规格

| 属性 | 值 | Token |
|------|-----|-------|
| 高亮背景色 | `#22d3ee` @ 0.25 alpha | `IndustrialColors.primaryContainer` |
| 脉冲范围 | alpha 0.15 ~ 0.30 | — |
| 背景基底 | `#161d1e` | `IndustrialColors.surfaceContainerLow` |
| 高亮期文字色 | `#8aebff` | `IndustrialColors.primary` |
| 恢复后文字色 | `#dde4e5` | `IndustrialColors.onSurface` |

### 3.3 左侧指示条联动

- 新文件行的 `indicatorLayer`（3px 宽）同步显示
- 颜色: `IndustrialColors.primaryContainer` (#22d3ee) solid
- 入场: 从底部向上 "reveal"（height 0 → full，200ms）
- 高亮期间保持可见，高亮结束后保留（标记"最新文件"）

### 3.4 交互中断

- 动画期间用户可点击任何文件
- 用户点击后高亮动画立即中断，被点击行进入 selected 态
- 不阻塞任何用户操作

---

## 4. 取消 Tab 改为上下分栏评估

### 4.1 分栏方案示意

```
┌─────── Sidebar 240px ───────┐
│  INPUT 区 (固定/可拖)        │
│  ├ 录制目标 56px             │
│  ├ 应用列表 ~112px           │
│  └ 麦克风面板 92px           │
│  最小高度 ~330px             │
├─────────────────────────────┤ ← 分割线
│  FILES 区 (弹性)             │
│  ├ 文件列表 ~136px           │
│  └ 导出按钮 28px             │
│  最小高度 ~194px             │
└─────────────────────────────┘
  总计最小 ~530px
```

### 4.2 评估结论: **不推荐，维持 Tab 方案**

| 维度 | Tab 方案 | 分栏方案 |
|------|---------|---------|
| 垂直空间 | 各 Tab 独享全高(~550px) | 两区分割，各自 ~275px |
| INPUT 可用性 | 进程列表可显示 5-6 个 | 仅 2-3 个 |
| FILES 可用性 | 文件列表可显示 6-8 个 | 仅 3-4 个 |
| 最小窗高需求 | 600px 充足 | 需 ≥650px |
| 实现复杂度 | 低（已有 TabContainerView） | 高（NSSplitView + 约束重写） |
| 认知负荷 | 聚焦单一上下文 | 信息过载 |

**结论**: Tab 方案 + 自动切换 + 高亮动画 = 最优解。两个 Tab 互斥使用场景（录制时看 INPUT，录完看 FILES）天然适合 Tab 模式。

---

## 5. 交互状态示意

```
录制中:
┌──────────────────────────────────┐
│   [INPUT ●]  [FILES]             │ ← INPUT 选中
├──────────────────────────────────┤
│   录制目标选择                     │
│   应用列表                        │
│   麦克风面板                      │
└──────────────────────────────────┘

录制完成后 (300ms 后自动切换):
┌──────────────────────────────────┐
│   [INPUT]  [FILES ●]             │ ← FILES 选中
├──────────────────────────────────┤
│  ▌████████████████████████████   │ ← 青色高亮脉冲
│  ▌ recording_2026-05-04.m4a      │
│  ▌ DUR 00:32    SIZE 1.2MB [M4A] │
│  ├────────────────────────────── │
│    older_file.wav                 │
│    DUR 01:05    SIZE 3.8MB [WAV]  │
└──────────────────────────────────┘
```

---

## 6. Design Token 汇总

| Token | 值 | 状态 | 用途 |
|-------|-----|------|------|
| `IndustrialAnimation.standard` | 120ms | 已存在 | 微交互基准 |
| Tab 切换时长 | 250ms | 新增常量建议 | 页面级切换 |
| 高亮总时长 | 2500ms | 新增常量建议 | 新文件脉冲 |
| `IndustrialColors.primaryContainer` | #22d3ee | 已存在 | 高亮背景色 |
| 高亮最大 opacity | 0.25 ~ 0.30 | 新增 | 脉冲峰值 |

---

*签字: 绘·设计师 / 2026-05-04*
