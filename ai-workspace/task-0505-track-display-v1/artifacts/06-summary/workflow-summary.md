# 维弈阁 — 任务汇总报告

## 任务信息
- **任务ID**: task-0505-track-display-v1
- **任务标题**: 音轨显示逻辑优化 — 动态 1~2 条轨道显示
- **编排模式**: auto
- **总耗时**: ~15 分钟

## 执行链路

| 阶段 | Agent | 评分 | 产物 |
|------|-------|------|------|
| 02-需求 | 枢·PM | 82 | [PRD](../02-requirement/PRD.md) |
| 03-设计 | 绘·设计 | 85 | [设计审查](../03-design/design-review.md) |
| 03-设计 | 矩·架构 | 80 | [架构设计](../03-design/eng-review.md) |
| 04-开发 | 铸·开发 | 85 | [左移报告](../04-development/shift-left-report.md) |
| 05-测试 | 鉴·QA | 78 | [QA报告](../05-testing/qa-report.md) |

## 关键变更

### 文件变更
| 文件 | 变更 |
|------|------|
| `AudioRecordKit/Sources/API/Types.swift` | +3 行：TrackInfo 新增 sourceType 字段 |
| `AudioRecordApp/Sources/Views/TracksView.swift` | 全重构：动态轨道 + fade 动画 + 来源标注 |
| `AudioRecordApp/Sources/Views/MainWindowView.swift` | +12 行：sourceType 传参 |

### 核心功能
1. ✅ 不开麦 → 1 条轨道（音源）
2. ✅ 开麦 → 2 条轨道（音源 + 麦克风）+ fade 动画
3. ✅ 每条轨道独立 LevelMeterView
4. ✅ 底部灰字来源标注
5. ✅ 2 轨时显示"📤 混合输出为单文件"

## 遗留问题
- V1 两条轨道共享同一 level（SDK 限制）
- 快速开关麦克风时动画可能叠加（不崩溃，视觉不完美）

## 下一步建议
- SDK 升级支持分轨 level 回调后，修改 `updateLevel()` 按 index 分发
- 考虑动画 debounce 处理快速切换场景
