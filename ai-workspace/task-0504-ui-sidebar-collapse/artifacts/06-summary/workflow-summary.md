# Workflow Summary: Sidebar 折叠/展开能力设计 Review

> Task ID: task-0504-ui-sidebar-collapse
> 类型: design | 优先级: 92 | 路由: 绘·设计 → 矩·架构
> 完成时间: 2026-05-05 11:30

---

## 任务概述

为 AudioRecord Mac 录音应用的 Sidebar 设计折叠/展开能力，输出设计规范和架构方案。

## 执行链路

1. **绘·设计师** — 完成 design-spec.md
   - 确定按钮位置：Toolbar 左侧（SF Symbol `sidebar.leading`）
   - 确定动画方案：250ms ease-in-out，宽度 240→0
   - 确定折叠视觉：完全折叠，无残留元素
   - 补充 Design Token：`IndustrialAnimation.sidebarToggle`

2. **矩·架构师** — 完成 architecture-review.md
   - 确定技术方案：NSSplitView 原生 collapse + animator
   - 确定快捷键：⌘+Shift+S via NSMenuItem（无冲突）
   - 确定持久化：UserDefaults 单 key
   - 确定约束策略：移除固定宽度约束，delegate 控制
   - 风险评估：低风险，预估 2-3 小时实现

## 产出文件

| 文件 | 说明 |
|------|------|
| `artifacts/02-requirement/requirement.md` | 需求文档副本 |
| `artifacts/03-design/design-spec.md` | 设计师产出：视觉规范、动画参数、按钮设计 |
| `artifacts/03-design/architecture-review.md` | 架构师产出：技术方案、代码示例、风险评估 |
| `artifacts/06-summary/workflow-summary.md` | 本文件 |

## 关键决策

| 决策点 | 结论 |
|--------|------|
| 按钮位置 | Toolbar 左侧（macOS 标准） |
| 动画时长 | 250ms |
| 快捷键 | ⌘+Shift+S |
| 实现方式 | NSSplitView 原生 API |
| 持久化 | UserDefaults |
| 首次启动 | Sidebar 默认展开 |

## 下一步

此 review 产出可直接作为 `small_fix` 或 `feature` 类型任务的输入，进入 `铸·开发 → 鉴·QA` 链路实施。

## 验收自查

- [x] artifacts/02-requirement/ 中存在需求文档副本
- [x] artifacts/03-design/design-spec.md 包含折叠动画方案、按钮设计、视觉规范
- [x] artifacts/03-design/architecture-review.md 包含技术方案、快捷键方案、持久化方案
- [x] 明确折叠动画方案、快捷键方案、持久化方案
- [x] 生成 artifacts/06-summary/workflow-summary.md
- [x] 无 push/deploy/delete_data 操作
