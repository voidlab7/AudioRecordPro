# 需求文档：设计首次启动引导和权限状态可视化

> Task ID: task-0504-ui-onboarding
> 优先级: P2 | 类型: design | 路由: 绘·设计 → 矩·架构

---

## 1. 背景

当前启动流程（`MainViewController.swift` 第 116 行 `setupInitialState()`）：
1. 加载上次录制模式（但实际每次都重置为默认）
2. 设置 UI 为 idle 状态，状态栏显示"准备就绪"
3. 加载可用进程列表
4. 加载已录制文件列表
5. 清理旧日志和临时文件

**问题**：
- 新用户不知道操作流程（先选择音源？先看设置？直接点录制？）
- 权限状态（麦克风 / 系统音频捕获）没有在 UI 上可视化
- `checkAudioPermissionsSilently()` 被注释掉（第 49 行），用户直到录制失败才知道权限问题
- StatusBar 28px 高度目前只显示文字状态，缺少结构化信息

## 2. 目标

为新用户提供简明引导，让用户在启动后 10 秒内理解操作流程；持续展示权限状态，减少录制失败的困惑。

## 3. 功能需求

### 3.1 首次启动引导（Onboarding）
- [ ] 检测首次启动（UserDefaults key: `hasCompletedOnboarding`）
- [ ] 展示 3 步引导：
  1. **选择音源**：高亮 Sidebar 的"录制目标"区域，提示"选择要录制的声音来源"
  2. **开始录制**：高亮录制按钮，提示"点击红色按钮开始录制"
  3. **查看文件**：指向 Saved Files Tab，提示"录制完成后在这里管理文件"
- [ ] 引导可通过点击"跳过"或完成最后一步关闭
- [ ] 引导关闭后设置 `hasCompletedOnboarding = true`

### 3.2 引导样式
- [ ] 使用半透明遮罩 + 高亮区域（spotlight 效果）
- [ ] 提示文字使用 Industrial Design 的 tooltip 风格（深色背景+浅色文字+小三角指向）
- [ ] 或使用更轻量的 Coach Mark（只高亮边框+浮动提示，无全屏遮罩）

### 3.3 权限状态可视化
- [ ] 在 StatusBar 左侧显示权限图标：
  - 🎤 麦克风：✅ 已授权 / ⚠️ 未确定 / ❌ 被拒绝
  - 🔊 系统音频：✅ 已授权 / ⚠️ 未确定 / ❌ 被拒绝
- [ ] 图标使用 Industrial Design 的颜色编码：
  - ✅ → `primaryContainer` 青色
  - ⚠️ → `statusWarning` 黄色
  - ❌ → `statusDanger` 红色
- [ ] 点击权限图标可跳转系统设置（复用 `openSystemPreferences()`）

### 3.4 权限状态实时更新
- [ ] 启动时静默检查权限（恢复 `checkAudioPermissionsSilently()`）
- [ ] 权限变化时更新 StatusBar 图标（无需弹窗）
- [ ] 首次录制前如果权限被拒绝，在录制按钮旁显示警告 badge

## 4. 设计约束

- 引导不应阻塞操作超过 3 秒（可随时跳过）
- 引导内容使用中英双语或仅中文（与现有 UI 一致）
- StatusBar 图标区宽度 ≤ 80px（不能挤占状态文字显示）
- 权限图标使用 SF Symbols（`mic.fill` / `speaker.wave.3.fill`）

## 5. 技术约束

| 文件 | 修改点 |
|------|--------|
| `MainViewController.swift:116` | `setupInitialState()` 中增加 onboarding 检测 |
| `MainViewController.swift:49` | 恢复 `checkAudioPermissionsSilently()` |
| `StatusBarView.swift` | 新增权限图标区域 |
| 新文件 `OnboardingOverlayView.swift` | 引导覆盖层实现 |
| `AppDelegate.swift` | 可选：在 window 配置后检查是否需要显示引导 |

## 6. 验收标准

| # | 条件 | 通过标准 |
|---|------|---------|
| 1 | 首次引导 | 全新安装首次打开时自动显示 3 步引导 |
| 2 | 不重复 | 完成引导后再次启动不再显示 |
| 3 | 可跳过 | 点击"跳过"立即关闭引导 |
| 4 | 权限展示 | StatusBar 正确显示当前权限状态 |
| 5 | 实时更新 | 在系统设置中更改权限后，StatusBar 图标 ≤5s 内更新 |
| 6 | 不阻塞 | 引导显示时仍可操作应用（引导自动消失或被覆盖） |
| 7 | 构建通过 | 编译无错误 |

## 7. 竞品引导参考

| 应用 | 引导方式 |
|------|---------|
| Logic Pro | 首次打开弹出 Welcome 窗口 + 教程项目 |
| GarageBand | 全屏 Onboarding 卡片（3页） |
| CleanMyMac | Coach Mark 逐步高亮 |
| 1Password | 半透明遮罩 + Spotlight 高亮 |
