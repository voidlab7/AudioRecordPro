# 需求文档：优化 SplitView 分隔线视觉反馈

> Task ID: task-0504-ui-splitview-divider
> 优先级: P3 | 类型: design | 路由: 绘·设计 → 矩·架构

---

## 1. 背景

当前 MainWindowView 使用 NSSplitView（`.thin` 分隔线样式）分隔 Sidebar 和内容区。分隔线支持拖动（min 200px, max 400px），但：

- 视觉上分隔线几乎不可见（系统默认 1px 灰色线）
- 用户不知道可以拖动调整 Sidebar 宽度
- 缺少 hover/拖动时的视觉反馈
- 与 Industrial Design 风格的其他交互元素（按钮 hover、行 hover）相比，分隔线缺少状态变化

**相关代码**：
- `MainWindowView.swift:45` — `dividerStyle = .thin`
- `MainWindowView.swift:300-305` — min/max 约束
- `MainWindowView.swift:322-324` — `effectiveRect:forDrawnRect:` 委托方法（当前未自定义绘制）

## 2. 目标

为分隔线添加 hover 和拖动时的视觉反馈，让用户知道可以调整宽度。

## 3. 功能需求

### 3.1 Hover 状态
- [ ] 鼠标悬停在分隔线区域（±3px 容差）时，分隔线变宽 + 变亮
- [ ] Hover 时光标变为 `resizeLeftRight`（系统默认已有，确认是否生效）
- [ ] Hover 时分隔线颜色从 `outlineVariant`(#3c494c) 变为 `primaryContainer`(#22d3ee)

### 3.2 拖动状态
- [ ] 拖动时分隔线保持高亮颜色
- [ ] 可选：拖动时分隔线两侧显示微弱的青色发光（Industrial Design glow 效果）

### 3.3 默认状态
- [ ] 默认分隔线使用 `outlineVariant` 颜色，宽度 1px
- [ ] 或可选：使用 2px 宽度 + 虚线纹理提示可交互

### 3.4 可选：拖动指示器
- [ ] 在分隔线中间显示 3 个小点/短横线（···）作为拖动手柄
- [ ] 仅在 hover 时显示，默认隐藏

## 4. 设计约束

- 分隔线默认不应过于醒目（不能分散对内容的注意力）
- Hover 效果使用 `IndustrialAnimation.standard` 时长的淡入淡出
- 颜色必须来自 `IndustrialColors` 体系
- 不能影响现有 SplitView 的拖动功能

## 5. 技术约束

| 文件 | 修改点 |
|------|--------|
| `MainWindowView.swift:45` | 可能需要改为 `.thick` 或自定义 divider |
| `MainWindowView.swift:322-324` | 自定义 `effectiveRect:forDrawnRect:` 扩大热区 |
| `MainWindowView.swift` 或新文件 | 重写 `drawDivider(in:)` 或添加覆盖层 |
| 注意 | NSSplitView 的 divider 绘制需要子类化或使用 overlay view |

**技术方案选择**：
- 方案 A：子类化 NSSplitView，重写 `drawDivider(in:)`
- 方案 B：在分隔线位置添加一个透明 tracking view 作为 overlay
- 方案 C：使用 `effectiveRect` 扩大热区 + NSTrackingArea 检测 hover

## 6. 验收标准

| # | 条件 | 通过标准 |
|---|------|---------|
| 1 | Hover 反馈 | 鼠标悬停分隔线时有明确的视觉变化 |
| 2 | 颜色正确 | 使用 Industrial Design 调色板颜色 |
| 3 | 动画流畅 | 状态过渡无闪烁 |
| 4 | 拖动功能 | 分隔线仍可正常拖动，min/max 约束生效 |
| 5 | 不干扰 | 默认状态不影响阅读和操作 |
| 6 | 构建通过 | 编译无错误 |

## 7. 参考

- Xcode 的 Navigator/Editor 分隔线（hover 变蓝）
- VS Code 的 sidebar resize handle（hover 变亮蓝色）
- Figma 的 panel divider（hover 显示拖动指示器）
