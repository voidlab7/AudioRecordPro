# Design Spec: 首次启动引导 & 权限状态可视化

> Task: task-0504-ui-onboarding
> Role: 绘·设计师
> Date: 2026-05-04
> Status: Completed

---

## 1. 设计目标

- 新用户首次启动后 **10 秒内** 理解核心操作流程
- 权限状态 **持续可见**，无需等到录制失败才获知
- 符合 Industrial Design 暗色工业主题，不引入新的视觉语言

---

## 2. 首次启动引导（Coach Mark 方案）

### 2.1 方案选择

| 方案 | 优点 | 缺点 | 决策 |
|------|------|------|------|
| 全屏遮罩 + Spotlight | 视觉冲击力强 | 阻塞操作，实现复杂 | 否 |
| Welcome 窗口 | 独立空间 | 与主界面脱节 | 否 |
| **Coach Mark（推荐）** | 轻量、非阻塞、可随时跳过 | 需精确锚定 | **是** |

### 2.2 引导步骤设计

共 **3 步**，逐步引导，用户可随时点击「跳过」关闭全部引导。

#### Step 1: 选择音源
- **锚定区域**: Sidebar → "录制目标" 区域（`systemTargetRow` + 进程列表顶部）
- **提示位置**: 锚定区域右侧，向左指向（箭头朝左）
- **提示文案**: 
  - 主文字: "选择要录制的声音来源"
  - 副文字: "系统全部声音，或选择特定应用"
- **高亮方式**: 目标区域边框变为 `primaryContainer` 青色 + 轻微 glow（2px spread, 20% opacity）

#### Step 2: 开始录制
- **锚定区域**: 主内容区录制按钮（红色圆形按钮）
- **提示位置**: 按钮下方，箭头朝上指向按钮
- **提示文案**:
  - 主文字: "点击开始录制"
  - 副文字: "再次点击停止，录音将自动保存"
- **高亮方式**: 按钮外圈添加 pulse 动画环（`primaryContainer` 青色，1.5s 周期）

#### Step 3: 查看文件
- **锚定区域**: Sidebar → "Saved Files" Tab 标签
- **提示位置**: Tab 标签下方偏右，箭头朝上
- **提示文案**:
  - 主文字: "录制完成后在这里管理文件"
  - 副文字: "支持播放、导出 MP3"
- **高亮方式**: Tab 标签底部添加青色下划线动画（左→右滑入）

### 2.3 Coach Mark 样式规格

```
┌─────────────────────────────────────────┐
│  ▲ (三角箭头指向目标)                      │
│                                         │
│  [主文字 - 14px Bold, onSurface 白色]      │
│  [副文字 - 12px Regular, onSurfaceVariant] │
│                                         │
│  ● ● ○  步骤指示器       [跳过] [下一步]   │
└─────────────────────────────────────────┘
```

| 属性 | 值 |
|------|-----|
| 背景色 | `surfaceContainerHighest` (#2A2A2A) |
| 圆角 | `IndustrialCornerRadius.sm` (6px) |
| 边框 | 1px `outlineVariant` |
| 阴影 | 0 4px 12px rgba(0,0,0,0.4) |
| 最大宽度 | 260px |
| 内边距 | 16px |
| 三角箭头 | 8x6px, 与背景色一致 |
| 步骤指示器 | 实心圆 6px `primaryContainer`，空心圆 6px `outlineVariant` |
| "跳过" 按钮 | 12px, `onSurfaceVariant`, 无边框 |
| "下一步" 按钮 | 12px Bold, `primaryContainer` 青色文字, 无边框 |

### 2.4 引导交互规则

- Coach Mark 出现时带 fade-in 动画（200ms ease-out）
- 步骤切换时旧 mark fade-out → 新 mark fade-in（总 300ms）
- 点击「下一步」进入下一步；最后一步按钮文字变为「完成」
- 点击「跳过」立即 fade-out 关闭全部引导
- 引导不阻塞操作：用户可直接与 UI 交互，Coach Mark 会自动消失
- 若用户在引导过程中执行了对应操作（如选了音源），自动跳到下一步

---

## 3. 权限状态可视化（StatusBar）

### 3.1 布局方案

当前 StatusBar 高度 28px，内部仅有 `statusLabel` 左对齐。

新布局：

```
┌────────────────────────────────────────────────────────────────┐
│ [🎤][🔊]  状态文字...                                           │
│ ← 80px →  ← 剩余空间 →                                        │
└────────────────────────────────────────────────────────────────┘
```

- 权限图标区位于 StatusBar **左侧**
- 图标区最大宽度 **≤ 80px**
- 状态文字 `statusLabel` 向右偏移，leading 从 12px → 92px（12 + 80）

### 3.2 权限图标设计

| 权限类型 | SF Symbol | 尺寸 | 说明 |
|----------|-----------|------|------|
| 麦克风 | `mic.fill` | 14x14pt | 麦克风录制权限 |
| 系统音频 | `speaker.wave.3.fill` | 14x14pt | 系统音频捕获权限 |

### 3.3 颜色编码

| 状态 | 颜色 Token | 色值参考 | 含义 |
|------|-----------|---------|------|
| 已授权 (granted) | `primaryContainer` | 青色 #4DD0E1 | 正常可用 |
| 未确定 (notDetermined) | `statusWarning` | 黄色 #FFB74D | 需要用户确认 |
| 被拒绝 (denied/restricted) | `statusDanger` | 红色 #EF5350 | 不可用，需修改设置 |

### 3.4 图标区详细尺寸

```
|-- 12px --|-- 14px --|-- 8px --|-- 14px --|-- 12px --|
   左边距     麦克风      间距     系统音频     右边距
             图标                  图标
                                              
总宽度 = 12 + 14 + 8 + 14 + 12 = 60px (≤ 80px 约束)
```

- 图标垂直居中于 StatusBar（28px 高）
- 图标 NSImageView 尺寸: 14x14pt
- 图标间距: 8px
- 图标区左右 padding: 12px

### 3.5 交互设计

- **Hover**: 图标区整体显示 tooltip，文案如 "麦克风: 已授权 | 系统音频: 未确定"
- **单击**: 跳转系统设置（复用现有 `openSystemPreferences()` 方法）
- **状态更新动画**: 颜色变化时使用 300ms fade 过渡

### 3.6 权限异常时的额外提示

- 当任一权限处于 `denied` 状态时，在录制按钮右上角显示 **红色警告 badge**
  - Badge 尺寸: 8x8px 红色实心圆
  - 位置: 录制按钮右上角偏移 (-2, -2)
  - 目的: 在用户尚未注意 StatusBar 时提供视觉警告

---

## 4. 视觉参考

### 4.1 配色使用（Industrial Design 暗色主题）

| 用途 | Token | 说明 |
|------|-------|------|
| Coach Mark 背景 | `surfaceContainerHighest` | 最亮的容器灰 |
| Coach Mark 文字 | `onSurface` / `onSurfaceVariant` | 白/浅灰 |
| 高亮边框/指示 | `primaryContainer` | 品牌青色 |
| 步骤圆点（非活跃） | `outlineVariant` | 暗灰 |
| 跳过按钮 | `onSurfaceVariant` | 低对比度，次要操作 |

### 4.2 动画规格

| 动画 | 时长 | 曲线 | 说明 |
|------|------|------|------|
| Coach Mark 出现 | 200ms | ease-out | fade + translateY(4→0) |
| Coach Mark 消失 | 150ms | ease-in | fade + translateY(0→-4) |
| 高亮 glow 脉冲 | 1.5s | ease-in-out | opacity 0.2↔0.6 循环 |
| 权限图标颜色变化 | 300ms | linear | tintColor fade |

---

## 5. 响应式考虑

- 窗口最小宽度 < 600px 时，Coach Mark 改为居中弹出（非锚定）
- StatusBar 权限图标区在极窄窗口（< 400px）时可折叠为单个综合图标 `checkmark.shield.fill`

---

## 6. 无障碍 (Accessibility)

- Coach Mark 文字需设置 `accessibilityLabel`
- 权限图标需设置 `accessibilityValue`（如 "麦克风权限已授权"）
- 步骤切换时通过 `NSAccessibility.post(.layoutChanged)` 通知
- Coach Mark 按钮需支持键盘焦点（Tab 导航）
