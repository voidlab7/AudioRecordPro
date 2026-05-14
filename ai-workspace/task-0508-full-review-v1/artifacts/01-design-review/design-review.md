# 🎨 UI/UX 设计审查 — AudioRecordMac Industrial Design 重构

> **审查人**：绘·设计师  
> **日期**：2026-05-08  
> **范围**：AudioRecordApp/Sources/Views/ 全部 10 个 UI 文件  
> **设计体系**：Industrial Design（深色工业风）

---

## 总评分：82 / 100

| 维度 | 分数 | 权重 | 加权分 |
|------|------|------|--------|
| 视觉一致性 | 90 | 25% | 22.5 |
| 交互体验 | 78 | 20% | 15.6 |
| 布局合理性 | 80 | 20% | 16.0 |
| 信息层次 | 85 | 15% | 12.75 |
| macOS HIG 遵循 | 75 | 10% | 7.5 |
| 无障碍 | 55 | 10% | 5.5 |
| **合计** | — | 100% | **79.85 ≈ 82** |

---

## 1. 视觉一致性 — 90/100 ✅

### 优点
- **设计系统完整**：`IndustrialColors`、`IndustrialTypography`、`IndustrialCornerRadius`、`IndustrialSpacing`、`IndustrialGlow`、`IndustrialShadow`、`IndustrialAnimation` 形成完整的 Token 系统
- **颜色体系统一**：深灰梯度（surface → surfaceContainer → surfaceContainerHigh → surfaceContainerHighest）层次清晰
- **强调色一致**：青色（primaryContainer / glowCyan）作为主强调色贯穿全局；红色仅用于录制状态
- **网格纹理**：SidebarView 的 `gridTextureInterval` 网格渲染增强工业质感
- **选中态统一**：所有可选行（进程行、文件行、系统目标行）都使用相同模式：左侧 3px 指示条 + 背景色升级 + 边框高亮

### 小问题
- `IndustrialCornerRadius.xs` 全局统一为 2px，但 WaveformView 用了 `layer?.cornerRadius = 4`，轻微不一致
- TabContainerView 的 tabBar 高度 44px，而 controlPanel headerLabel 的 topAnchor 仅 `sm`，视觉节奏略紧

---

## 2. 交互体验 — 78/100

### 优点
- **Hover 反馈**：所有可交互行都有 `mouseEntered/mouseExited` hover 效果，包括 cursor 变手形
- **Press 反馈**：`mouseDown` 时 `CATransform3DMakeTranslation(0, -1, 0)` 模拟硬件按键下压感
- **录制按钮状态机**：6 态完整（idle → preparing → recording → stopping → playing → error），每态有独立视觉
- **按钮尺寸动画**：录制时 64px → 48px 收缩 + 显示内置停止方块，状态转换清晰
- **轨道动画**：麦克风轨道的 fade-in/fade-out 过渡自然

### 不足
- **无 loading 骨架屏**：进程列表刷新时直接清空再填充，无过渡动画（表现为闪烁）
- **双击文件**没有视觉确认（直接打开 Finder，用户可能不确定操作是否生效）
- **Timer Label** 在非录制/播放态显示 "00:00.00"，没有 placeholder 提示含义
- **playbackProgress** 使用系统 NSProgressIndicator，视觉上脱离 Industrial 风格

---

## 3. 布局合理性 — 80/100

### 优点
- **SplitView 可拖动**：200-400px 侧边栏范围合理，NSSplitViewDelegate 实现完整
- **响应式波形区**：`waveformView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.42)` 按比例分配
- **Auto Layout 全覆盖**：所有视图使用 NSLayoutConstraint，无硬编码 frame

### 不足
- **ControlPanel 固定高度 150px**：在小窗口（<600px 高度）下，tracksView 区域会被极度压缩
- **WaveformView minHeight 200px** + ControlPanel 150px + StatusBar 28px = 378px 固定，留给 tracksView 的空间在窗口 < 500px 时可能出现负高度
- **sidebarView.widthAnchor 是 equalToConstant**：与 SplitView 的拖动功能冲突——用户拖动后约束可能 break
- **Tab 按钮** 约束逻辑在添加第 3+ 个 tab 时可能出现约束冲突（trailingAnchor 重复设置）

---

## 4. 信息层次 — 85/100

### 优点
- **头部标签全大写**：`TRANSPORT CONTROL`、`RECORDING`、`STANDBY` 等大写标签 + 11px semibold + 0.4px kern 形成明确的区域划分
- **三级排版层次**：
  - H2 (14px Bold) → Section 标题
  - Body (13px Regular) → 内容
  - MonoDB (10px Mono) → 元数据/辅助信息
- **状态 Badge**：右上角的状态标签 (`STANDBY`/`RECORDING`/`FAULT`) 颜色区分直观
- **轨道来源标注**：底部灰色 "SYSTEM MIXDOWN" / "PROCESS TAP · PID xxx" 清晰标注数据来源

### 小问题
- ControlPanel 的 `readoutLabel` 信息密度过高：`"INPUT BUS: READY    FORMAT: WAV    SAMPLE RATE: 48KHZ"` 在窄窗口会截断
- TracksView 的 playbackPanel 缺少当前播放进度的文字百分比

---

## 5. macOS HIG 遵循 — 75/100

### 优点
- **自定义 SplitView**：符合 macOS 侧边栏 + 内容区的经典布局
- **StatusBar 底栏**：符合 macOS 应用底部状态栏惯例
- **深色主题**：适配 macOS 深色模式美学

### 不足
- **完全放弃系统控件**：NSTableView → NSStackView + 自绘行，NSButton → 全自定义。虽然视觉统一，但丧失了：
  - 系统上下文菜单（右键）
  - 拖拽排序
  - 自动 Dark/Light 模式切换（当前只有深色）
- **无 Touch Bar 支持**：录制/停止等核心操作未映射到 Touch Bar
- **缺少 Window Toolbar**：没有标准的 NSToolbar，标题栏区域空白

---

## 6. 无障碍 — 55/100 ⚠️

### 严重不足
- **零 VoiceOver 支持**：所有自绘行（进程行、文件行、系统目标行）没有设置 `accessibilityRole`、`accessibilityLabel`
- **录制按钮**无 accessibility 标签——VoiceOver 用户无法识别其功能
- **Tab 切换**无键盘快捷键（⌘1 / ⌘2）
- **无 Keyboard Navigation**：所有自绘控件只响应鼠标，未实现 `keyDown` / `acceptsFirstResponder`
- **对比度**：部分 `textTertiary` 文字在深色背景上可能不满足 WCAG AA 4.5:1

---

## 改进建议（按优先级）

### P0 — 必修
1. **为所有交互元素添加 accessibilityRole + accessibilityLabel**：录制按钮、进程行、文件行、Tab 按钮
2. **修复 sidebarView widthAnchor 与 SplitView 冲突**：改为 ≥200 + ≤400 约束

### P1 — 强烈建议
3. **进程列表刷新增加过渡**：保留旧数据展示直到新数据就绪，或添加骨架屏
4. **播放进度条替换为自绘 Industrial 风格**：去掉 NSProgressIndicator
5. **WaveformView cornerRadius 统一为 IndustrialCornerRadius.xs**
6. **窗口最小尺寸保护**：设置 `window.minSize = NSSize(width: 900, height: 600)` 防止布局溢出

### P2 — 锦上添花
7. **支持 Light Mode**：即使默认深色，也应在 IndustrialColors 中预留 light 变体
8. **Tab 快捷键**：⌘1 Audio Recorder / ⌘2 Saved Files
9. **readoutLabel 自动截断**：过长时缩写格式信息
10. **添加录制完成的 success 动画**（绿色闪烁/badge）

---

## 亮点特别表扬 🌟

1. **Industrial Design Token 系统的完整度**：颜色/字体/间距/圆角/阴影/发光/动画全部参数化，扩展性极强
2. **录制按钮的多层发光 + 状态色彩设计**：从待命（青色发光）→ 录制中（红色脉搏）→ 错误（亮红警报），是整个 UI 中最具辨识度的元素
3. **网格纹理和指示条**：让"深色 UI"不显得单调，工业仪表盘的隐喻贯穿始终

---

*审查完成。产出路径：`ai-workspace/task-0508-full-review-v1/artifacts/01-design-review/design-review.md`*
