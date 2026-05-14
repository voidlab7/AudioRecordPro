# Workflow Summary

> Task: task-0504-ui-onboarding
> Roles: 绘·设计师 + 矩·架构师
> Date: 2026-05-04
> Duration: ~35 min (within 45 min limit)

---

## 1. 任务执行概览

| 阶段 | 产出 | 耗时 |
|------|------|------|
| 需求分析 | 阅读需求文档、源码（3 文件） | ~8 min |
| 设计规格 | `design-spec.md` — Coach Mark + StatusBar 权限 UI 设计 | ~12 min |
| 架构评审 | `architecture-review.md` — 实现方案 + 代码修改清单 | ~12 min |
| 文档归档 | 需求复制 + 目录结构 + summary + state.json | ~3 min |

---

## 2. 关键设计决策

### 决策 1: Coach Mark vs 全屏遮罩
- **选择**: Coach Mark（浮动提示气泡）
- **理由**: 需求明确"引导不应阻塞操作"，Coach Mark 允许用户随时与 UI 交互

### 决策 2: 自定义 NSView vs NSPopover
- **选择**: 自定义 Overlay NSView
- **理由**: NSPopover 默认 vibrancy 样式与 Industrial Design 暗色主题冲突，无法自定义三角箭头

### 决策 3: 权限监听用 Polling vs Notification
- **选择**: 轻量 Timer Polling（3 秒间隔）
- **理由**: macOS 没有官方权限变更通知 API；3s 轮询满足"≤5s 更新"验收标准且 CPU 开销极低

### 决策 4: 恢复 checkAudioPermissionsSilently() 的策略
- **选择**: 延迟 1.0s 异步执行 + 结果同步到 StatusBar
- **理由**: 原注释提到"避免权限链路阻塞 UI"，延迟执行规避此问题

---

## 3. 产出物清单

```
ai-workspace/task-0504-ui-onboarding/
├── artifacts/
│   ├── 01-ideation/          (empty - design review 无需 ideation)
│   ├── 02-requirement/
│   │   └── requirement.md    (需求文档副本)
│   ├── 03-design/
│   │   ├── design-spec.md    (设计师产出：UI/UX 设计规格)
│   │   └── architecture-review.md  (架构师产出：技术方案)
│   ├── 04-development/       (empty - 本任务为 design review)
│   ├── 05-testing/           (empty - 测试要点包含在架构文档中)
│   └── 06-summary/
│       └── workflow-summary.md  (本文件)
└── state.json
```

---

## 4. 代码影响摘要

| 类型 | 文件 | 改动规模 |
|------|------|----------|
| 修改 | `MainViewController.swift` | ~50 行（恢复权限检查 + 引导检测 + 轮询监听） |
| 修改 | `StatusBarView.swift` | ~80 行（新增权限图标区 + 约束 + 点击事件） |
| 新增 | `OnboardingOverlayView.swift` | ~200 行 |
| 新增 | `OnboardingBubbleView.swift` | ~150 行 |
| 可选 | `MainWindowView.swift` | ~10 行（代理转发） |

总估计改动量：**~490 行**（中等规模 UI feature）

---

## 5. 后续建议

1. **开发阶段**优先实现 StatusBar 权限图标（最小可用，不依赖引导逻辑）
2. 引导 Coach Mark 可独立开发，与权限可视化并行
3. 建议增加 `UserDefaults.removeObject(forKey: "hasCompletedOnboarding")` 的 Debug 入口，方便测试引导流程
4. 若后续需要国际化，Coach Mark 文案应迁移到 Localizable.strings

---

## 6. 风险提醒

- **macOS 版本兼容**：系统音频权限 API 在 macOS 14.4 前不可用，需版本检测
- **窗口 resize**：Coach Mark 锚点需要随布局变化更新，建议监听 frame 变更
- **性能**：轮询 Timer 需在 App 进入后台时暂停（节省资源）
