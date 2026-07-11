# REQ-1.0-15 UI 布局修复（三项）

> **版本**：V1.0 | **优先级**：P0 | **预估**：0.5天
> **状态**：✅ 已完成
> **关联**：[需求列表](./README.md) | REQ-1.0-14（去除冗余进程详情卡片引入）
> **来源**：用户 UI 验收反馈（2026-05-14）

---

## 问题描述

REQ-1.0-14 去除进程详情卡片后，引入 3 个 UI 布局问题：

### BUG-A：Transport Control readoutLabel 被按钮遮挡
- `TARGET: QQMUSIC · PID 45281  FORMAT...  SAMPLE RATE...` 文字被播放/录制/停止按钮覆盖截断
- 新增的 TARGET 前缀导致文字过长，与按钮布局冲突

### BUG-B：TracksView 区域大面积空白
- 轨道卡片隐藏后，TracksView 容器仍占据大量垂直空间
- 播放面板被钉在 TracksView 底部，中间全是空白

### BUG-C：窗口最小宽度时 SAVED Tab 被截断
- 窗口缩到最小宽度时，Tab 按钮 `SAVED` 文字右侧被截断

---

## 修复方案

| # | 问题 | 方案 |
|---|------|------|
| A | readoutLabel 被遮挡 | readoutLabel 只保留 `TARGET: xxx`，去掉 `FORMAT/SAMPLE RATE`（底部状态栏已有） |
| B | TracksView 大面积空白 | TracksView 无轨道卡片时高度收缩：隐藏时设 heightConstraint = 播放面板高度（~94px），不留空白 |
| C | SAVED Tab 截断 | Tab 最小宽度约束调大，或文字缩短 |

---

## 验收标准

| # | 标准 | 通过条件 |
|---|------|----------|
| 1 | readoutLabel 不被遮挡 | TARGET 信息完整可读，不被按钮覆盖 |
| 2 | 无大面积空白 | 波形区和播放面板/控制面板之间无不合理空白 |
| 3 | Tab 不截断 | 窗口最小宽度时 SAVED Tab 文字完整可见 |
| 4 | 构建通过 | 0 error, 0 warning |
