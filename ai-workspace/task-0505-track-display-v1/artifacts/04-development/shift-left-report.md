# 开发左移检查报告

> 作者: 铸·开发 | 日期: 2026-05-05

---

## 变更清单

| 文件 | 变更类型 | 行数 |
|------|---------|------|
| `AudioRecordKit/Sources/API/Types.swift` | 修改 | +3 行（sourceType 字段 + init 参数） |
| `AudioRecordApp/Sources/Views/TracksView.swift` | 重写 | ~330 行（完整重构） |
| `AudioRecordApp/Sources/Views/MainWindowView.swift` | 修改 | +12 行（sourceType 传参） |

---

## 实现要点

### 1. TrackInfo 扩展
- 新增 `sourceType: String` 字段，默认值 `""`（向后兼容）
- 三种取值：`"SYSTEM MIXDOWN"` / `"PROCESS TAP · PID xxx"` / `"MICROPHONE INPUT"`

### 2. TracksView 重构

#### 核心逻辑变更：
- **新增 trackRowViews 数组**：保持对轨道行的引用，便于动画操作
- **updateTracks() 改为 diff 驱动**：
  - 首次加载 → 直接构建
  - 轨道增加 → 重建 + 最后一条 fade-in
  - 轨道减少 → 最后一条 fade-out → 移除
  - 数量不变 → 刷新内容
- **轨道行高度从 120px 降为 100px**：适配两轨场景
- **新增 sourceLabel**：每条轨道底部灰字标注来源类型
- **新增 mixOutputLabel**：`📤 混合输出为单文件`，仅 2 轨时可见

#### 动画实现：
- 插入：NSAnimationContext, 0.25s easeInEaseOut, alphaValue 0→1
- 移除：NSAnimationContext, 0.2s easeIn, alphaValue 1→0, completion 中 remove

### 3. MainWindowView 适配
- `updateTracksDisplay()` 构建 TrackInfo 时传递 `sourceType`

---

## 左移检查

| 检查项 | 结果 |
|--------|------|
| 编译通过（无 linter error） | ✅ |
| 向后兼容（sourceType 有默认值） | ✅ |
| 不修改 SDK（AudioRecordKit Core 不动） | ✅ |
| 动画使用 NSAnimationContext（非 CAAnimation） | ✅ |
| 所有颜色使用 IndustrialColors token | ✅ |
| 所有字体使用 IndustrialTypography token | ✅ |

---

## 交接块

```
来源: 铸·开发
状态: ✅ 完成
产物文件: ai-workspace/task-0505-track-display-v1/artifacts/04-development/shift-left-report.md
评分: 85/100
下游建议: 鉴·QA → 验证 AC-01 ~ AC-07
```
