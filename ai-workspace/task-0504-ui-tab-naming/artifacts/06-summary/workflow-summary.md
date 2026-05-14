# Workflow Summary: task-0504-ui-tab-naming

> Task: 优化 Sidebar Tab 命名与录制完成后自动切换
> 执行时间: 2026-05-04
> 角色: 绘·设计师 + 矩·架构师 (Design Review)

---

## 1. 任务概要

对 AudioRecord Mac 应用的 Sidebar Tab 进行命名优化，并设计录制完成后自动切换到文件列表 Tab 的交互方案，包含新文件高亮引导动画。

## 2. 交付产物

| # | 文件 | 角色 | 内容 |
|---|------|------|------|
| 1 | `02-requirement/requirement.md` | — | 需求文档（从 queue 复制） |
| 2 | `03-design/design-spec.md` | 绘·设计师 | 设计规格：命名方案、动画设计、分栏评估 |
| 3 | `03-design/architecture-review.md` | 矩·架构师 | 架构评审：API 设计、时序、代码修改清单 |
| 4 | `06-summary/workflow-summary.md` | — | 本文件 |

## 3. 核心设计决策

### 3.1 Tab 命名
- **决策**: "Audio Recorder" → "INPUT", "Saved Files" → "FILES"
- **理由**: 简洁大写英文符合 Industrial Design 风格，语义清晰，宽度友好（各 5 字符以内）
- **图标**: 保持现有 `waveform` / `folder`

### 3.2 自动切换
- **决策**: 录制完成后立即触发，250ms crossfade 过渡到 FILES Tab
- **理由**: 250ms 从容不生硬，总计 ≤350ms 到达 FILES Tab（满足 ≤500ms 要求）
- **智能判断**: 如已在 FILES Tab 则跳过切换，仅高亮

### 3.3 高亮动画
- **决策**: primaryContainer (#22d3ee) 青色背景脉冲 2.5 秒
- **三阶段**: 渐现(250ms) → 脉冲呼吸(1250ms) → 渐隐(1000ms)
- **最大 opacity**: 0.25~0.30（明显但不刺眼）
- **实现**: CAAnimationGroup + 独立 highlightLayer，不干扰现有 UI 逻辑

### 3.4 分栏方案
- **决策**: 不采用，维持 Tab 方案
- **理由**: 240px 宽度下垂直空间不足（需 ≥530px 最小高度），Tab 模式配合自动切换已解决核心痛点

## 4. 代码影响范围

| 文件 | 修改量级 | 说明 |
|------|---------|------|
| `SidebarView.swift` | 小 | 2 处 title 修改 + 1 新方法(switchToFilesTabAndHighlight) |
| `TabContainerView.swift` | 中 | 新增 selectTab(_:animated:) + animateContentTransition |
| `MainWindowView.swift` | 小 | 1 新透传方法 |
| `MainViewController.swift` | 小 | 1 行调用新增 |
| `RecordedFilesView.swift` | 中 | highlightNewestFile + playHighlightAnimation + cancelHighlightAnimation |
| `IndustrialDesignTokens.swift` | 可选 | 新增 `tabTransition = 0.25` 常量 |

**总计**: ~6 文件, ~130 行新增, ~4 行修改

## 5. 风险与缓解

| 风险 | 等级 | 缓解措施 |
|------|------|---------|
| Tab 切换重复触发 | 低 | `guard tabId != selectedTabId` 守卫 |
| 高亮与选中态冲突 | 低 | 独立 `highlightLayer` 隔离 |
| 快速连续录制叠加 | 中 | `playHighlightAnimation` 首行清理旧动画 |
| asyncAfter 精度 | 极低 | 350ms 延迟已留足余量 |

## 6. 后续开发建议

1. **Phase 1** (5 min): Tab 命名修改 — 修改 2 处 title 字符串，立即可编译验证
2. **Phase 2** (15 min): TabContainerView 动画方法 — 独立可测试
3. **Phase 3** (10 min): SidebarView 链路 + MainViewController 集成
4. **Phase 4** (15 min): RecordedFilesView 高亮动画实现 + 中断处理
5. **Phase 5** (5 min): 端到端测试（录制→停止→观察切换和高亮）

预计开发工时: ~50 分钟

## 7. 状态

- [x] 需求文档归档
- [x] 设计方案完成 (design-spec.md)
- [x] 架构评审完成 (architecture-review.md)
- [x] 产物归档
- [ ] 开发实现（下一阶段）
- [ ] 测试验证（下一阶段）

---

*Design Review 完成时间: 2026-05-04 | 用时: ~25 分钟*
