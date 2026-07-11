# AudioRecordApp 视觉设计规范
# Visual Design Specification

> **版本**: v1.1  
> **创建日期**: 2026-05-01  
> **更新日期**: 2026-05-03  
> **状态**: 当前生效 UI 规范  
> **设计师**: 绘·视觉设计  
> **设计风格**: Industrial Design（工业设计）  
> **参考**: Stitch Desktop Application Project  
> **实现形态**: AppKit 左右分栏；`SidebarView` 负责录制目标，`MainWindowView` 负责波形/轨道/控制面板布局

---

## 📋 目录

1. [设计系统总览](#1-设计系统总览)
   - [配色方案](#11-配色方案)
   - [字体排版](#12-字体排版)
   - [间距系统](#13-间距系统)
2. [组件视觉规范](#2-组件视觉规范)
3. [视觉特效规范](#3-视觉特效规范)
4. [界面布局示意](#4-界面布局示意)
5. [设计 Token（Swift 代码）](#5-设计-token)
6. [实现指南](#6-实现指南)

---

## 1. 设计系统总览

### 1.1 配色方案

AudioRecordApp 采用 **Industrial Design 配色系统**，强调深色金属质感、冷色高光和工业警示色。

#### 1.1.1 核心背景色（Surface）

| Token | 色值 | 用途 | 应用场景 |
|-------|------|------|----------|
| `surface` | `#0e1416` | 最深背景 | 主窗口背景、StatusBarView |
| `surface-container-low` | `#161d1e` | 深灰面板 | WaveformView 背景、TracksView 轨道项 |
| `surface-container` | `#1a2122` | 中灰容器 | Sidebar 背景、TracksView 背景 |
| `surface-container-high` | `#242b2d` | 深灰高光 | Sidebar hover 态 |
| `surface-container-highest` | `#2f3638` | 浅灰高光 | Sidebar 选中态 |

#### 1.1.2 文字色（Text）

| Token | 色值 | 用途 | 应用场景 |
|-------|------|------|----------|
| `on-surface` | `#dde4e5` | 主文字 | 标题、主要标签 |
| `on-surface-variant` | `#bbc9cd` | 次要文字 | 描述、非活跃标签 |
| `text-secondary` | `#D1D5DB` | 三级文字 | 状态栏、dB 数值 |

#### 1.1.3 主色（Primary Accent）

| Token | 色值 | 用途 | 应用场景 |
|-------|------|------|----------|
| `primary` | `#8aebff` | 主青色（高亮） | 计时器文字、声道标签 |
| `primary-container` | `#22d3ee` | 青色容器 | 波形渐变、电平表正常态、Sidebar 指示条 |
| `secondary-container` | `#00a6e0` | 深青色 | 波形渐变底色 |
| `cyan-dim` | `#06B6D4` | 暗青色 | 波形空闲态起始色 |
| `blue-dim` | `#0EA5E9` | 暗蓝色 | 波形空闲态终止色 |

#### 1.1.4 警示色（Status）

| Token | 色值 | 用途 | 应用场景 |
|-------|------|------|----------|
| `status-success` | `#22C55E` | 绿色 | 正常状态指示 |
| `status-warning` | `#F59E0B` | 琥珀色 | 高电平警告（70-90%） |
| `status-danger` | `#EF4444` | 红色 | 过载（> 90%） |
| `status-critical` | `#DC2626` | 深红色 | 录制按钮空闲态背景 |

#### 1.1.5 边框与网格（Outline & Grid）

| Token | 色值 | 用途 | 应用场景 |
|-------|------|------|----------|
| `outline` | `#859397` | 标准边框 | StatusBarView 顶部边框 |
| `outline-variant` | `#3c494c` | 深色边框 | Sidebar 右侧边框、WaveformView 边框 |
| `grid-light` | `rgba(255,255,255,0.03)` | 极淡网格 | Sidebar 背景网格 |
| `grid-medium` | `rgba(255,255,255,0.06)` | 淡网格 | WaveformView 水平刻度线 |

#### 1.1.6 发光效果（Glow）

| Token | 色值 | 用途 | 应用场景 |
|-------|------|------|----------|
| `glow-cyan` | `rgba(34,211,238,0.25)` | 青色发光 | 录制按钮空闲态、计时器 |
| `glow-warning` | `rgba(245,158,11,0.3)` | 琥珀发光 | 电平表警告态 |
| `glow-danger` | `rgba(239,68,68,0.35)` | 红色发光 | 电平表过载态、录制态按钮 |

---

### 1.2 字体排版

#### 1.2.1 字体族（Font Family）

| 字体 | 用途 | macOS 映射 |
|------|------|-----------|
| **Inter** | 主字体（界面文本） | SF Pro Display / SF Pro Text |
| **Space Grotesk** | 数字/标签字体 | SF Mono（等宽数字） |

#### 1.2.2 字号系统（Font Size Scale）

| 层级 | 字号 | 字重 | 行高 | 字距 | 用途 | 代码示例 |
|------|------|------|------|------|------|----------|
| **H1** | 18px | Bold | 1.3 | -0.01em | 主标题 | `NSFont.systemFont(ofSize: 18, weight: .bold)` |
| **H2** | 14px | Bold | 1.4 | 0.05em | 区块标题（大写） | `NSFont.systemFont(ofSize: 14, weight: .bold)` |
| **Body** | 13px | Regular | 1.6 | 0.3px | 正文 | `NSFont.systemFont(ofSize: 13, weight: .regular)` |
| **Small** | 12px | Regular | 1.5 | 0.3px | 小文本 | `NSFont.systemFont(ofSize: 12, weight: .regular)` |
| **Label** | 11px | Semibold | 1.4 | 0.4px | 标签（大写） | `NSFont.systemFont(ofSize: 11, weight: .semibold)` |
| **Timer** | 28px | Bold | 1.2 | 0.1em | 计时器 | `NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)` |
| **Mono-dB** | 10px | Regular | 1.4 | 0.1em | dB 数值 | `NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)` |

#### 1.2.3 排版规则

1. **标题全大写**（H1, H2, Label）
   ```swift
   label.stringValue = "AUDIO SOURCE".uppercased()
   ```

2. **数字采用等宽字体**（计时器、dB 值）
   ```swift
   timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
   ```

3. **增加字距强化工程感**
   ```swift
   let paragraphStyle = NSMutableParagraphStyle()
   paragraphStyle.lineSpacing = 1.6
   let attributes: [NSAttributedString.Key: Any] = [
       .kern: 0.3 // 字距 0.3px
   ]
   ```

---

### 1.3 间距系统

| Token | 值 | 用途 |
|-------|---|------|
| `unit` | 4px | 基础单位 |
| `xs` | 4px | 极小间距（图标与文字） |
| `sm` | 8px | 小间距（列表项内边距） |
| `md` | 16px | 中等间距（区块内边距） |
| `lg` | 24px | 大间距（区块外边距、网格间隔） |
| `xl` | 32px | 超大间距（大型面板内边距） |
| `gutter` | 12px | 边缘留白 |
| `sidebar-width` | 240px | Sidebar 固定宽度 |

---

## 2. 组件视觉规范

### 2.1 Sidebar（侧边栏）

#### 2.1.1 基础样式

| 属性 | 值 | 说明 |
|------|---|------|
| **宽度** | 240px | 固定宽度 |
| **背景色** | `surface-container` (#1a2122) | 深灰基底 |
| **背景纹理** | 24px 网格 | 极淡白色线条（`grid-light`） |
| **右侧边框** | 1px `outline-variant` (#3c494c) | 分割线 |
| **顶部内边距** | 16px (`md`) | 标题区域留白 |
| **底部内边距** | 16px (`md`) | 底部留白 |

#### 2.1.2 信息架构更新：录制目标选择器（v1.2）

侧边栏不再作为“音频源配置器”，而是作为**录制目标选择器**。用户首先决定“录谁”，再决定“要不要把麦克风混进去”。

```text
┌─────────────────────────┐
│ RECORD TARGET            │
│ 先选要录的声音；麦克风作为附加输入 │
│                         │
│  ● 全部系统声音           │
│                         │
│ SELECT APP AUDIO         │
│  [刷新]                  │
│                         │
│  ○ IMA                   │
│  ○ Chrome                │
│  ○ 微信                  │
│                         │
├─────────────────────────┤
│ ADD MICROPHONE           │
│  [ ] 同时录入麦克风        │
│      MIX INTO SELECTED TARGET │
└─────────────────────────┘
```

**产品规则：**

| 层级 | 控件 | 行为 |
|------|------|------|
| 主目标 | `全部系统声音` / 某个应用进程 | 单选、互斥；默认选中 `全部系统声音` |
| 附加输入 | `同时录入麦克风` | 独立开关，混入当前主目标 |
| 禁止模式 | `系统音频输出` checkbox + `麦克风` checkbox 并列 | 会制造“到底录哪个”的认知负担 |

**文案规则：**
- `系统音频输出` → `全部系统声音`
- `已打开的应用` → `选择应用声音`
- `麦克风` → `同时录入麦克风`
- `包含麦克风声音` → 删除；用底部 ADD MICROPHONE 面板承载

**视觉规则：**
- `全部系统声音` 使用和进程行一致的工业卡片样式，固定在应用列表上方。
- 进程列表占据侧边栏主体区域，是本产品差异化能力的视觉主角。
- 麦克风面板固定在底部，使用 `surface-container-low` 背景、1px 工业边框、青色激活态。
- 麦克风不是主目标，不应与进程列表抢视觉权重。

#### 2.1.3 音频源选择项（Audio Source Item）

##### 默认态（Default）
```swift
// 背景：透明
itemView.wantsLayer = true
itemView.layer?.backgroundColor = NSColor.clear.cgColor

// 文字：on-surface-variant
label.textColor = NSColor(hex: "#bbc9cd")
label.font = NSFont.systemFont(ofSize: 13, weight: .regular)

// 高度：40px
itemView.heightAnchor.constraint(equalToConstant: 40).isActive = true
```

##### Hover 态
```swift
override func mouseEntered(with event: NSEvent) {
    layer?.backgroundColor = NSColor(hex: "#242b2d").cgColor // surface-container-high
}

override func mouseExited(with event: NSEvent) {
    if !isSelected {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
```

##### 选中态（Selected）
```swift
// 背景：surface-container-highest
itemView.layer?.backgroundColor = NSColor(hex: "#2f3638").cgColor

// 左侧青色指示条（3px 宽）
let indicator = NSView()
indicator.wantsLayer = true
indicator.layer?.backgroundColor = NSColor(hex: "#22d3ee").cgColor // primary-container
indicator.translatesAutoresizingMaskIntoConstraints = false
itemView.addSubview(indicator)

NSLayoutConstraint.activate([
    indicator.leadingAnchor.constraint(equalTo: itemView.leadingAnchor),
    indicator.topAnchor.constraint(equalTo: itemView.topAnchor),
    indicator.bottomAnchor.constraint(equalTo: itemView.bottomAnchor),
    indicator.widthAnchor.constraint(equalToConstant: 3)
])

// 文字：on-surface（亮白）
label.textColor = NSColor(hex: "#dde4e5")
```

#### 2.1.4 标题样式（Section Title）

```swift
// "AUDIO SOURCE" 大写标题
titleLabel.stringValue = "AUDIO SOURCE".uppercased()
titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
titleLabel.textColor = NSColor(hex: "#dde4e5") // on-surface
titleLabel.alignment = .left

// 字距增强工程感
let attributes: [NSAttributedString.Key: Any] = [
    .kern: 0.05 * 14 // 0.05em
]
titleLabel.attributedStringValue = NSAttributedString(string: titleLabel.stringValue, attributes: attributes)
```

#### 2.1.5 网格纹理实现

```swift
func addGridTexture(to view: NSView, spacing: CGFloat = 24) {
    let gridLayer = CAShapeLayer()
    let path = CGMutablePath()
    
    // 垂直线
    for x in stride(from: 0, to: view.bounds.width, by: spacing) {
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: view.bounds.height))
    }
    
    // 水平线
    for y in stride(from: 0, to: view.bounds.height, by: spacing) {
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: view.bounds.width, y: y))
    }
    
    gridLayer.path = path
    gridLayer.strokeColor = NSColor(white: 1.0, alpha: 0.03).cgColor // grid-light
    gridLayer.lineWidth = 1
    gridLayer.fillColor = nil
    
    view.layer?.insertSublayer(gridLayer, at: 0)
}

// 使用
sidebarView.wantsLayer = true
addGridTexture(to: sidebarView, spacing: 24)
```

---

### 2.2 WaveformView（波形视图）

#### 2.2.1 基础样式

| 属性 | 值 | 说明 |
|------|---|------|
| **背景色** | `surface-container-low` (#161d1e) | 深灰基底 |
| **圆角** | 4px | 轻微圆角 |
| **边框** | 1px `outline-variant` (#3c494c) | 深色边框 |
| **最小高度** | 200px | 确保波形可读性 |

```swift
waveformView.wantsLayer = true
waveformView.layer?.backgroundColor = NSColor(hex: "#161d1e").cgColor
waveformView.layer?.cornerRadius = 4
waveformView.layer?.borderWidth = 1
waveformView.layer?.borderColor = NSColor(hex: "#3c494c").cgColor
```

#### 2.2.2 网格线（Grid Lines）

##### 水平虚线（6条）
```swift
func addHorizontalGridLines() {
    let lineCount = 6
    let spacing = bounds.height / CGFloat(lineCount + 1)
    
    for i in 1...lineCount {
        let y = spacing * CGFloat(i)
        
        let gridLine = CAShapeLayer()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: bounds.width, y: y))
        
        gridLine.path = path
        gridLine.strokeColor = NSColor(white: 1.0, alpha: 0.06).cgColor // grid-medium
        gridLine.lineWidth = 1
        gridLine.lineDashPattern = [4, 4] // 虚线：4px 线段，4px 间隙
        
        layer?.insertSublayer(gridLine, at: 0)
    }
}
```

#### 2.2.3 波形颜色（Waveform Color）

##### 空闲态（Idle）
```swift
// 青色 → 蓝色渐变（alpha 0.3）
let idleGradient = CAGradientLayer()
idleGradient.colors = [
    NSColor(hex: "#06B6D4").withAlphaComponent(0.3).cgColor, // cyan-dim
    NSColor(hex: "#0EA5E9").withAlphaComponent(0.3).cgColor  // blue-dim
]
idleGradient.startPoint = CGPoint(x: 0, y: 0)
idleGradient.endPoint = CGPoint(x: 0, y: 1)
idleGradient.frame = waveformLayer.bounds

waveformLayer.mask = idleGradient
```

##### 录制态（Recording）
```swift
// 青色 → 蓝色渐变（不透明）
let recordingGradient = CAGradientLayer()
recordingGradient.colors = [
    NSColor(hex: "#22d3ee").cgColor, // primary-container
    NSColor(hex: "#00a6e0").cgColor  // secondary-container
]
recordingGradient.startPoint = CGPoint(x: 0, y: 0)
recordingGradient.endPoint = CGPoint(x: 0, y: 1)

waveformLayer.mask = recordingGradient

// 添加 8px 青色发光
waveformLayer.shadowColor = NSColor(hex: "#22d3ee").withAlphaComponent(0.25).cgColor
waveformLayer.shadowRadius = 8
waveformLayer.shadowOpacity = 1.0
waveformLayer.shadowOffset = .zero
```

#### 2.2.4 波形路径绘制（Waveform Path）

```swift
func updateWaveformPath(data: [Float]) {
    let path = CGMutablePath()
    let centerY = bounds.height / 2
    let scale = bounds.height / 2
    
    path.move(to: CGPoint(x: 0, y: centerY))
    
    for (index, value) in data.enumerated() {
        let x = CGFloat(index) * (bounds.width / CGFloat(data.count))
        let y = centerY + CGFloat(value) * scale
        
        path.addLine(to: CGPoint(x: x, y: y))
    }
    
    // 闭合路径（底部）
    path.addLine(to: CGPoint(x: bounds.width, y: centerY))
    path.addLine(to: CGPoint(x: 0, y: centerY))
    path.closeSubpath()
    
    waveformShapeLayer.path = path
}
```

---

### 2.3 LevelMetersOverlay（电平表）

#### 2.3.1 布局

| 属性 | 值 | 说明 |
|------|---|------|
| **位置** | 叠加在 WaveformView 右上角 | 绝对定位 |
| **外边距** | 上：12px，右：12px | `gutter` 间距 |
| **尺寸** | 宽：120px，高：80px（双声道） | 固定尺寸 |
| **背景** | 半透明 `surface-container` + 4px 圆角 | 背景色：rgba(26,33,34,0.8) |

```swift
// 容器样式
levelMetersView.wantsLayer = true
levelMetersView.layer?.backgroundColor = NSColor(hex: "#1a2122").withAlphaComponent(0.8).cgColor
levelMetersView.layer?.cornerRadius = 4
levelMetersView.layer?.borderWidth = 1
levelMetersView.layer?.borderColor = NSColor(hex: "#3c494c").cgColor

// 定位（右上角）
NSLayoutConstraint.activate([
    levelMetersView.topAnchor.constraint(equalTo: waveformView.topAnchor, constant: 12),
    levelMetersView.trailingAnchor.constraint(equalTo: waveformView.trailingAnchor, constant: -12),
    levelMetersView.widthAnchor.constraint(equalToConstant: 120),
    levelMetersView.heightAnchor.constraint(equalToConstant: 80)
])
```

#### 2.3.2 单声道电平条（Single Channel Bar）

##### 进度条背景
```swift
barBackground.wantsLayer = true
barBackground.layer?.backgroundColor = NSColor(hex: "#1a2122").cgColor // surface-container
barBackground.layer?.cornerRadius = 2
barBackground.layer?.borderWidth = 1
barBackground.layer?.borderColor = NSColor(hex: "#3c494c").cgColor // outline-variant

// 尺寸：宽 100px，高 12px
barBackground.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    barBackground.widthAnchor.constraint(equalToConstant: 100),
    barBackground.heightAnchor.constraint(equalToConstant: 12)
])
```

##### 进度条填充（动态颜色）
```swift
func updateLevelFill(level: Float) {
    // 计算宽度
    let fillWidth = CGFloat(level) * barBackground.bounds.width
    fillWidthConstraint?.constant = fillWidth
    
    // 根据电平动态变色
    let color: NSColor
    let glowColor: NSColor?
    let glowRadius: CGFloat
    
    if level > 0.9 {
        // 过载（> 90%）：红色 + 红色发光
        color = NSColor(hex: "#EF4444") // status-danger
        glowColor = NSColor(hex: "#EF4444").withAlphaComponent(0.35) // glow-danger
        glowRadius = 6
    } else if level > 0.7 {
        // 警告（70-90%）：琥珀色 + 琥珀发光
        color = NSColor(hex: "#F59E0B") // status-warning
        glowColor = NSColor(hex: "#F59E0B").withAlphaComponent(0.3) // glow-warning
        glowRadius = 6
    } else {
        // 正常（< 70%）：青色，无发光
        color = NSColor(hex: "#22d3ee") // primary-container
        glowColor = nil
        glowRadius = 0
    }
    
    fillView.layer?.backgroundColor = color.cgColor
    
    // 应用发光
    if let glowColor = glowColor {
        fillView.layer?.shadowColor = glowColor.cgColor
        fillView.layer?.shadowRadius = glowRadius
        fillView.layer?.shadowOpacity = 1.0
        fillView.layer?.shadowOffset = .zero
    } else {
        fillView.layer?.shadowColor = nil
    }
}
```

#### 2.3.3 声道标签（Channel Label）

```swift
// L/R 标签
channelLabel.stringValue = "L" // 或 "R"
channelLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
channelLabel.textColor = NSColor(hex: "#8aebff") // primary
channelLabel.alignment = .left
```

#### 2.3.4 dB 数值（dB Value）

```swift
// 等宽字体，右对齐
dbLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
dbLabel.textColor = NSColor(hex: "#D1D5DB") // text-secondary
dbLabel.alignment = .right
dbLabel.stringValue = String(format: "%.1f dB", db)
```

#### 2.3.5 更新速度（60fps）

```swift
func updateLevels(left: Float, right: Float) {
    CATransaction.begin()
    CATransaction.setAnimationDuration(0.016) // 16.7ms，60fps
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
    
    leftFillWidthConstraint?.constant = CGFloat(left) * barWidth
    rightFillWidthConstraint?.constant = CGFloat(right) * barWidth
    
    updateLevelFill(level: left) // 左声道
    updateLevelFill(level: right) // 右声道
    
    CATransaction.commit()
}
```

---

### 2.4 ControlPanelView（控制面板）

#### 2.4.1 基础样式

| 属性 | 值 | 说明 |
|------|---|------|
| **背景色** | `surface-container-low` (#161d1e) | 深灰基底 |
| **高度** | 120px | 固定高度 |
| **内边距** | 左右：32px，上下：24px | `xl` 和 `lg` 间距 |
| **布局** | 水平居中 | 录制按钮 + 计时器居中排列 |

```swift
controlPanelView.wantsLayer = true
controlPanelView.layer?.backgroundColor = NSColor(hex: "#161d1e").cgColor

NSLayoutConstraint.activate([
    controlPanelView.heightAnchor.constraint(equalToConstant: 120)
])
```

#### 2.4.2 录制按钮（Record Button）

##### 空闲态（Idle）
```swift
// 深红色圆形按钮（64px）
recordButton.wantsLayer = true
recordButton.layer?.backgroundColor = NSColor(hex: "#DC2626").cgColor // status-critical
recordButton.layer?.cornerRadius = 32
recordButton.layer?.masksToBounds = false

// 多重青色发光（3层叠加）
let glowConfigs: [(radius: CGFloat, opacity: Float)] = [
    (40, 0.4),
    (20, 0.6),
    (10, 0.8)
]

glowConfigs.forEach { config in
    let glowLayer = CALayer()
    glowLayer.shadowColor = NSColor(hex: "#22d3ee").withAlphaComponent(0.25).cgColor
    glowLayer.shadowRadius = config.radius
    glowLayer.shadowOpacity = config.opacity
    glowLayer.shadowOffset = .zero
    glowLayer.backgroundColor = NSColor.clear.cgColor
    glowLayer.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
    recordButton.layer?.insertSublayer(glowLayer, at: 0)
}

// 硬边阴影（工业感）
recordButton.layer?.shadowColor = NSColor(white: 0, alpha: 0.45).cgColor
recordButton.layer?.shadowRadius = 6
recordButton.layer?.shadowOpacity = 0.45
recordButton.layer?.shadowOffset = CGSize(width: 0, height: 2)

// 尺寸约束
recordButton.translatesAutoresizingMaskIntoConstraints = false
buttonWidthConstraint = recordButton.widthAnchor.constraint(equalToConstant: 64)
buttonHeightConstraint = recordButton.heightAnchor.constraint(equalToConstant: 64)
NSLayoutConstraint.activate([buttonWidthConstraint!, buttonHeightConstraint!])
```

##### 录制态（Recording）
```swift
// 缩小至 48px
buttonWidthConstraint?.constant = 48
buttonHeightConstraint?.constant = 48
recordButton.layer?.cornerRadius = 24

// 显示内部白色方块（停止图标）
innerSquare.isHidden = false
innerSquare.wantsLayer = true
innerSquare.layer?.backgroundColor = NSColor.white.cgColor
innerSquare.layer?.cornerRadius = 4

innerSquare.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    innerSquare.centerXAnchor.constraint(equalTo: recordButton.centerXAnchor),
    innerSquare.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
    innerSquare.widthAnchor.constraint(equalToConstant: 20),
    innerSquare.heightAnchor.constraint(equalToConstant: 20)
])

// 切换为红色发光
recordButton.layer?.shadowColor = NSColor(hex: "#EF4444").withAlphaComponent(0.35).cgColor
recordButton.layer?.shadowRadius = 16
recordButton.layer?.shadowOpacity = 1.0

// 动画（200ms ease-out）
NSAnimationContext.runAnimationGroup({ context in
    context.duration = 0.2
    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
    recordButton.animator().alphaValue = 1.0
})
```

##### Hover 态
```swift
override func mouseEntered(with event: NSEvent) {
    // 发光增强至 24px
    recordButton.layer?.shadowRadius = 24
    recordButton.layer?.shadowOpacity = 1.0
    
    // 轻微上浮（2px）
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.12
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        recordButton.layer?.transform = CATransform3DMakeTranslation(0, 2, 0)
    })
}

override func mouseExited(with event: NSEvent) {
    recordButton.layer?.shadowRadius = 20
    recordButton.layer?.shadowOpacity = 0.8
    recordButton.layer?.transform = CATransform3DIdentity
}
```

##### Press 态
```swift
override func mouseDown(with event: NSEvent) {
    // 下沉 3px
    recordButton.layer?.transform = CATransform3DMakeTranslation(0, -3, 0)
    recordButton.layer?.shadowRadius = 12
    recordButton.layer?.shadowOpacity = 0.6
}

override func mouseUp(with event: NSEvent) {
    // 50ms 后反弹
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.recordButton.layer?.transform = CATransform3DIdentity
            self.recordButton.layer?.shadowRadius = 20
            self.recordButton.layer?.shadowOpacity = 0.8
        })
        
        // 触发录制状态切换
        self.toggleRecordingState()
    }
}
```

#### 2.4.3 计时器（Timer）

```swift
// 等宽字体，28px，加粗
timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
timerLabel.textColor = NSColor(hex: "#8aebff") // primary
timerLabel.alignment = .center
timerLabel.stringValue = "00:00.00"

// 字距增强可读性
let attributes: [NSAttributedString.Key: Any] = [
    .kern: 0.1 * 28 // 0.1em
]
timerLabel.attributedStringValue = NSAttributedString(string: timerLabel.stringValue, attributes: attributes)

// 8px 青色发光（增强可读性）
timerLabel.wantsLayer = true
timerLabel.layer?.shadowColor = NSColor(hex: "#22d3ee").withAlphaComponent(0.25).cgColor
timerLabel.layer?.shadowRadius = 8
timerLabel.layer?.shadowOpacity = 0.3
timerLabel.layer?.shadowOffset = .zero
```

#### 2.4.4 布局（Layout）

```swift
// 水平堆叠（录制按钮 + 计时器）
let stackView = NSStackView(views: [recordButton, timerLabel])
stackView.orientation = .horizontal
stackView.spacing = 24 // lg 间距
stackView.alignment = .centerY
stackView.translatesAutoresizingMaskIntoConstraints = false

controlPanelView.addSubview(stackView)

NSLayoutConstraint.activate([
    stackView.centerXAnchor.constraint(equalTo: controlPanelView.centerXAnchor),
    stackView.centerYAnchor.constraint(equalTo: controlPanelView.centerYAnchor)
])
```

---

### 2.5 TracksView（轨道视图）

#### 2.5.1 基础样式

| 属性 | 值 | 说明 |
|------|---|------|
| **背景色** | `surface-container` (#1a2122) | 中灰基底 |
| **边框** | 1px `outline-variant` (#3c494c) | 深色边框 |
| **内边距** | 16px (`md`) | 统一内边距 |
| **最小高度** | 120px | 容纳至少 2 条轨道 |

```swift
tracksView.wantsLayer = true
tracksView.layer?.backgroundColor = NSColor(hex: "#1a2122").cgColor
tracksView.layer?.borderWidth = 1
tracksView.layer?.borderColor = NSColor(hex: "#3c494c").cgColor
```

#### 2.5.2 轨道项（Track Item）

```swift
// 轨道项容器
trackItemView.wantsLayer = true
trackItemView.layer?.backgroundColor = NSColor(hex: "#161d1e").cgColor // surface-container-low
trackItemView.layer?.cornerRadius = 2
trackItemView.layer?.borderWidth = 1
trackItemView.layer?.borderColor = NSColor(hex: "#3c494c").cgColor

// 高度：40px
trackItemView.translatesAutoresizingMaskIntoConstraints = false
trackItemView.heightAnchor.constraint(equalToConstant: 40).isActive = true

// 轨道标题（大写）
trackTitleLabel.stringValue = "TRACK 01 - MICROPHONE".uppercased()
trackTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
trackTitleLabel.textColor = NSColor(hex: "#dde4e5") // on-surface
trackTitleLabel.alignment = .left

// 字距
let attributes: [NSAttributedString.Key: Any] = [
    .kern: 0.4 // 0.4px
]
trackTitleLabel.attributedStringValue = NSAttributedString(string: trackTitleLabel.stringValue, attributes: attributes)
```

#### 2.5.3 轨道列表（Track List）

```swift
// 垂直堆叠
let stackView = NSStackView()
stackView.orientation = .vertical
stackView.spacing = 8 // sm 间距
stackView.alignment = .leading
stackView.translatesAutoresizingMaskIntoConstraints = false

tracksView.addSubview(stackView)

NSLayoutConstraint.activate([
    stackView.leadingAnchor.constraint(equalTo: tracksView.leadingAnchor, constant: 16),
    stackView.trailingAnchor.constraint(equalTo: tracksView.trailingAnchor, constant: -16),
    stackView.topAnchor.constraint(equalTo: tracksView.topAnchor, constant: 16),
    stackView.bottomAnchor.constraint(equalTo: tracksView.bottomAnchor, constant: -16)
])

// 添加轨道项
tracks.forEach { track in
    let trackItemView = createTrackItem(for: track)
    stackView.addArrangedSubview(trackItemView)
}
```

---

### 2.6 StatusBarView（状态栏）

#### 2.6.1 基础样式

| 属性 | 值 | 说明 |
|------|---|------|
| **背景色** | `surface` (#0e1416) | 最深黑 |
| **高度** | 28px | 固定高度 |
| **顶部边框** | 1px `outline` (#859397) | 分割线 |
| **内边距** | 左右：12px (`gutter`) | 边缘留白 |

```swift
statusBarView.wantsLayer = true
statusBarView.layer?.backgroundColor = NSColor(hex: "#0e1416").cgColor

// 顶部边框
let borderLayer = CALayer()
borderLayer.frame = CGRect(x: 0, y: statusBarView.bounds.height - 1, width: statusBarView.bounds.width, height: 1)
borderLayer.backgroundColor = NSColor(hex: "#859397").cgColor
statusBarView.layer?.addSublayer(borderLayer)

NSLayoutConstraint.activate([
    statusBarView.heightAnchor.constraint(equalToConstant: 28)
])
```

#### 2.6.2 状态文字（Status Text）

```swift
statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
statusLabel.textColor = NSColor(hex: "#bbc9cd") // on-surface-variant
statusLabel.alignment = .left
statusLabel.stringValue = "READY" // 默认状态

// 不同状态文字
enum AppState {
    case ready
    case recording
    case paused
    case error(String)
    
    var displayText: String {
        switch self {
        case .ready: return "READY"
        case .recording: return "RECORDING..."
        case .paused: return "PAUSED"
        case .error(let message): return "ERROR: \(message)".uppercased()
        }
    }
}

func updateStatus(_ state: AppState) {
    statusLabel.stringValue = state.displayText
}
```

---

## 3. 视觉特效规范

### 3.1 阴影系统（Shadow）

Industrial Design 使用**短而锐利的阴影**，模拟物理硬件的质感。

| 层级 | 半径 | 不透明度 | Y 偏移 | 用途 |
|------|------|----------|--------|------|
| **小阴影** | 6px | 0.35 | 2px | 小按钮、图标 |
| **中阴影** | 12px | 0.45 | 4px | 面板、卡片 |
| **大阴影** | 18px | 0.55 | 6px | 浮动面板、模态窗口 |

```swift
// 阴影颜色（统一）
let shadowColor = NSColor(white: 0, alpha: 0.45).cgColor

// 小阴影
layer?.shadowColor = shadowColor
layer?.shadowRadius = 6
layer?.shadowOpacity = 0.35
layer?.shadowOffset = CGSize(width: 0, height: 2)

// 中阴影
layer?.shadowRadius = 12
layer?.shadowOpacity = 0.45
layer?.shadowOffset = CGSize(width: 0, height: 4)

// 大阴影
layer?.shadowRadius = 18
layer?.shadowOpacity = 0.55
layer?.shadowOffset = CGSize(width: 0, height: 6)
```

---

### 3.2 发光效果（Glow）

发光仅在**必要时**使用，避免过度视觉干扰。

| 颜色 | 半径 | 不透明度 | 用途 |
|------|------|----------|------|
| **青色发光** | 8px | 0.3 | 计时器、波形、录制按钮（空闲态） |
| **琥珀发光** | 6px | 0.6 | 电平表警告（70-90%） |
| **红色发光** | 6px | 1.0 | 电平表过载（> 90%）、录制态按钮 |

```swift
// 青色发光（计时器、录制按钮）
layer?.shadowColor = NSColor(hex: "#22d3ee").withAlphaComponent(0.25).cgColor
layer?.shadowRadius = 8
layer?.shadowOpacity = 0.3
layer?.shadowOffset = .zero

// 琥珀发光（电平表警告）
layer?.shadowColor = NSColor(hex: "#F59E0B").withAlphaComponent(0.3).cgColor
layer?.shadowRadius = 6
layer?.shadowOpacity = 0.6
layer?.shadowOffset = .zero

// 红色发光（电平表过载）
layer?.shadowColor = NSColor(hex: "#EF4444").withAlphaComponent(0.35).cgColor
layer?.shadowRadius = 6
layer?.shadowOpacity = 1.0
layer?.shadowOffset = .zero
```

#### 3.2.1 多重发光叠加（录制按钮）

```swift
// 3 层青色发光（40px / 20px / 10px）
let glowConfigs: [(radius: CGFloat, opacity: Float)] = [
    (40, 0.4),
    (20, 0.6),
    (10, 0.8)
]

glowConfigs.forEach { config in
    let glowLayer = CALayer()
    glowLayer.shadowColor = NSColor(hex: "#22d3ee").withAlphaComponent(0.25).cgColor
    glowLayer.shadowRadius = config.radius
    glowLayer.shadowOpacity = config.opacity
    glowLayer.shadowOffset = .zero
    glowLayer.backgroundColor = NSColor.clear.cgColor
    glowLayer.frame = recordButton.bounds
    recordButton.layer?.insertSublayer(glowLayer, at: 0)
}
```

---

### 3.3 渐变（Gradient）

#### 3.3.1 波形渐变（上→下）

```swift
// 青色 → 蓝色
let waveformGradient = CAGradientLayer()
waveformGradient.colors = [
    NSColor(hex: "#22d3ee").cgColor, // primary-container
    NSColor(hex: "#00a6e0").cgColor  // secondary-container
]
waveformGradient.startPoint = CGPoint(x: 0, y: 0) // 顶部
waveformGradient.endPoint = CGPoint(x: 0, y: 1)   // 底部
waveformGradient.frame = bounds

waveformShapeLayer.mask = waveformGradient
```

#### 3.3.2 拉丝金属纹理（水平渐变）

```swift
func addBrushedMetal(to layer: CALayer) {
    let brushLayer = CAGradientLayer()
    brushLayer.colors = [
        NSColor(white: 1.0, alpha: 0.02).cgColor,
        NSColor(white: 0.0, alpha: 0.02).cgColor,
        NSColor(white: 1.0, alpha: 0.02).cgColor
    ]
    brushLayer.startPoint = CGPoint(x: 0, y: 0.5) // 左
    brushLayer.endPoint = CGPoint(x: 1, y: 0.5)   // 右
    brushLayer.frame = layer.bounds
    layer.insertSublayer(brushLayer, at: 0)
}
```

---

### 3.4 网格纹理（Grid Texture）

#### 3.4.1 24px 正方形网格（Sidebar 背景）

```swift
func addGridTexture(to view: NSView, spacing: CGFloat = 24) {
    let gridLayer = CAShapeLayer()
    let path = CGMutablePath()
    
    // 垂直线
    for x in stride(from: 0, to: view.bounds.width, by: spacing) {
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: view.bounds.height))
    }
    
    // 水平线
    for y in stride(from: 0, to: view.bounds.height, by: spacing) {
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: view.bounds.width, y: y))
    }
    
    gridLayer.path = path
    gridLayer.strokeColor = NSColor(white: 1.0, alpha: 0.03).cgColor // grid-light
    gridLayer.lineWidth = 1
    gridLayer.fillColor = nil
    
    view.layer?.insertSublayer(gridLayer, at: 0)
}

// 使用
sidebarView.wantsLayer = true
addGridTexture(to: sidebarView, spacing: 24)
```

---

### 3.5 动画参数（Animation）

| 用途 | 时长 | 缓动函数 | 说明 |
|------|------|----------|------|
| **标准交互** | 120ms | ease-out | hover、press、focus |
| **状态切换** | 200ms | ease-out | 录制开始/停止、模式切换 |
| **实时反馈** | 16.7ms | linear | 电平表、波形更新（60fps） |

```swift
// 标准动画
NSAnimationContext.runAnimationGroup({ context in
    context.duration = 0.12 // 120ms
    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
    view.animator().alphaValue = 1.0
})

// 长动画（状态切换）
NSAnimationContext.runAnimationGroup({ context in
    context.duration = 0.2 // 200ms
    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
    recordButton.animator().frame = newFrame
})

// 实时反馈（60fps）
CATransaction.begin()
CATransaction.setAnimationDuration(0.016) // 16.7ms
CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
levelMeterLayer.bounds = newBounds
CATransaction.commit()
```

---

## 4. 界面布局示意

### 4.1 完整界面布局（ASCII Art）

```
┌────────────────────────────────────────────────────────────────────────┐
│  AudioRecordApp                                             [●][◐][○]  │ ← Title Bar (macOS)
├─────────────┬──────────────────────────────────────────────────────────┤
│             │                                                          │
│  AUDIO      │                                                          │
│  SOURCE     │                 WaveformView                             │ ← Waveform + Level Meters
│             │          ┌─────────────────────────┐                     │
│  ┌─────────┐│          │ ┌─────────────────────┐ │                     │
│  │●Mic     ││          │ │ L: ████████░░ -12dB │ │ ← LevelMetersOverlay│
│  └─────────┘│          │ │ R: ██████░░░░ -18dB │ │    (Overlays WaveformView)
│             │          │ └─────────────────────┘ │                     │
│  ┌─────────┐│          │                         │                     │
│  │ System  ││          │  ～～～～～～～～～～～  │ ← Waveform Path    │
│  └─────────┘│          │ ————————————————————    │                     │
│             │          │  ～～～～～～～～～～～  │                     │
│             │          │ ————————————————————    │                     │
│             │          │  ～～～～～～～～～～～  │                     │
│             │          └─────────────────────────┘                     │
│             │                                                          │
│             │                                                          │
├─────────────┼──────────────────────────────────────────────────────────┤
│             │                                                          │
│             │               ┌──────────┐                               │
│             │               │    ●     │  00:12.45  ← Timer            │ ← ControlPanelView
│             │               └──────────┘                               │
│             │               ↑ Record Button                            │
│             │                                                          │
├─────────────┴──────────────────────────────────────────────────────────┤
│  TracksView                                                            │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ TRACK 01 - MICROPHONE                                   [▶][■]   │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ TRACK 02 - SYSTEM AUDIO                                 [▶][■]   │ │
│  └──────────────────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────────────────────┤
│  READY                                                  Sample Rate: 48kHz │ ← StatusBarView
└────────────────────────────────────────────────────────────────────────┘
```

### 4.2 尺寸标注（Dimensions）

```
┌─────────────────────────────────────────────────────────────────────┐
│  Title Bar (macOS 原生)                                     22px H  │
├────────────┬────────────────────────────────────────────────────────┤
│            │                                                        │
│  Sidebar   │                  Main Content Area                    │
│  240px W   │                  (动态宽度)                            │
│            │                                                        │
│            │  WaveformView:                                         │
│            │  - 高度: 200px（最小）                                 │
│            │  - 圆角: 4px                                           │
│            │  - 边距: 上下 16px，左 16px，右 16px                   │
│            │                                                        │
│            │  LevelMetersOverlay:                                   │
│            │  - 尺寸: 120px W × 80px H                              │
│            │  - 位置: 右上角，边距 12px                             │
│            │                                                        │
├────────────┼────────────────────────────────────────────────────────┤
│            │                                                        │
│            │  ControlPanelView: 120px H                             │
│            │  - 录制按钮: 64px（空闲）→ 48px（录制）                │
│            │  - 计时器: 28px 字体                                   │
│            │                                                        │
├────────────┴────────────────────────────────────────────────────────┤
│  TracksView:                                                        │
│  - 最小高度: 120px                                                  │
│  - 轨道项高度: 40px                                                 │
│  - 间距: 8px（轨道间）                                              │
├─────────────────────────────────────────────────────────────────────┤
│  StatusBarView: 28px H                                              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. 设计 Token

### 5.1 完整 Swift 代码（Design Tokens）

```swift
//
//  IndustrialDesignTokens.swift
//  AudioRecordApp
//
//  Created by 绘·视觉设计
//  Date: 2026-05-01
//

import Cocoa

// MARK: - Color Palette

struct IndustrialColors {
    
    // MARK: 背景色（Surface）
    
    static let surface = NSColor(hex: "#0e1416")
    static let surfaceContainerLow = NSColor(hex: "#161d1e")
    static let surfaceContainer = NSColor(hex: "#1a2122")
    static let surfaceContainerHigh = NSColor(hex: "#242b2d")
    static let surfaceContainerHighest = NSColor(hex: "#2f3638")
    
    // MARK: 文字色（Text）
    
    static let onSurface = NSColor(hex: "#dde4e5")
    static let onSurfaceVariant = NSColor(hex: "#bbc9cd")
    static let textSecondary = NSColor(hex: "#D1D5DB")
    static let textTertiary = NSColor(hex: "#9CA3AF")
    
    // MARK: 主色（Primary）
    
    static let primary = NSColor(hex: "#8aebff")
    static let primaryContainer = NSColor(hex: "#22d3ee")
    static let secondaryContainer = NSColor(hex: "#00a6e0")
    static let cyanDim = NSColor(hex: "#06B6D4")
    static let blueDim = NSColor(hex: "#0EA5E9")
    
    // MARK: 警示色（Status）
    
    static let statusSuccess = NSColor(hex: "#22C55E")
    static let statusWarning = NSColor(hex: "#F59E0B")
    static let statusDanger = NSColor(hex: "#EF4444")
    static let statusCritical = NSColor(hex: "#DC2626")
    
    // MARK: 边框与网格（Outline & Grid）
    
    static let outline = NSColor(hex: "#859397")
    static let outlineVariant = NSColor(hex: "#3c494c")
    static let gridLight = NSColor(white: 1.0, alpha: 0.03)
    static let gridMedium = NSColor(white: 1.0, alpha: 0.06)
    static let gridHeavy = NSColor(white: 1.0, alpha: 0.12)
    
    // MARK: 发光效果（Glow）
    
    static let glowCyan = NSColor(hex: "#22d3ee").withAlphaComponent(0.25)
    static let glowWarning = NSColor(hex: "#F59E0B").withAlphaComponent(0.3)
    static let glowDanger = NSColor(hex: "#EF4444").withAlphaComponent(0.35)
    
    // MARK: 阴影（Shadow）
    
    static let shadowColor = NSColor(white: 0, alpha: 0.45)
}

// MARK: - Typography

struct IndustrialTypography {
    
    // MARK: 字体族
    
    static func primaryFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
    
    static func monoFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
    
    // MARK: 预设字体样式
    
    /// 主标题（18px Bold）
    static let h1 = NSFont.systemFont(ofSize: 18, weight: .bold)
    
    /// 区块标题（14px Bold，大写）
    static let h2 = NSFont.systemFont(ofSize: 14, weight: .bold)
    
    /// 正文（13px Regular）
    static let body = NSFont.systemFont(ofSize: 13, weight: .regular)
    
    /// 小文本（12px Regular）
    static let small = NSFont.systemFont(ofSize: 12, weight: .regular)
    
    /// 标签（11px Semibold，大写）
    static let label = NSFont.systemFont(ofSize: 11, weight: .semibold)
    
    /// 计时器（28px Bold Mono）
    static let timer = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
    
    /// dB 数值（10px Regular Mono）
    static let monoDB = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
}

// MARK: - Spacing

struct IndustrialSpacing {
    static let unit: CGFloat = 4
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let gutter: CGFloat = 12
    static let sidebarWidth: CGFloat = 240
    static let gridTextureInterval: CGFloat = 24
}

// MARK: - Corner Radius

struct IndustrialCornerRadius {
    static let xs: CGFloat = 2  // 轨道项、小按钮
    static let sm: CGFloat = 4  // 面板、卡片
    static let md: CGFloat = 8  // 对话框
    static let lg: CGFloat = 12 // 大面板
    static let xl: CGFloat = 32 // 圆形按钮
}

// MARK: - Shadow

struct IndustrialShadow {
    
    /// 小阴影（按钮、小卡片）
    static func small(layer: CALayer) {
        layer.shadowColor = IndustrialColors.shadowColor.cgColor
        layer.shadowRadius = 6
        layer.shadowOpacity = 0.35
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }
    
    /// 中阴影（面板、对话框）
    static func medium(layer: CALayer) {
        layer.shadowColor = IndustrialColors.shadowColor.cgColor
        layer.shadowRadius = 12
        layer.shadowOpacity = 0.45
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }
    
    /// 大阴影（浮动面板、模态窗口）
    static func large(layer: CALayer) {
        layer.shadowColor = IndustrialColors.shadowColor.cgColor
        layer.shadowRadius = 18
        layer.shadowOpacity = 0.55
        layer.shadowOffset = CGSize(width: 0, height: 6)
    }
}

// MARK: - Glow

struct IndustrialGlow {
    
    /// 青色发光（8px）
    static func cyan(layer: CALayer) {
        layer.shadowColor = IndustrialColors.glowCyan.cgColor
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.3
        layer.shadowOffset = .zero
    }
    
    /// 琥珀色发光（6px）
    static func warning(layer: CALayer) {
        layer.shadowColor = IndustrialColors.glowWarning.cgColor
        layer.shadowRadius = 6
        layer.shadowOpacity = 0.6
        layer.shadowOffset = .zero
    }
    
    /// 红色发光（6px）
    static func danger(layer: CALayer) {
        layer.shadowColor = IndustrialColors.glowDanger.cgColor
        layer.shadowRadius = 6
        layer.shadowOpacity = 1.0
        layer.shadowOffset = .zero
    }
    
    /// 多重青色发光（录制按钮）
    static func multilayerCyan(to layer: CALayer, bounds: CGRect) {
        let glowConfigs: [(radius: CGFloat, opacity: Float)] = [
            (40, 0.4),
            (20, 0.6),
            (10, 0.8)
        ]
        
        glowConfigs.forEach { config in
            let glowLayer = CALayer()
            glowLayer.shadowColor = IndustrialColors.glowCyan.cgColor
            glowLayer.shadowRadius = config.radius
            glowLayer.shadowOpacity = config.opacity
            glowLayer.shadowOffset = .zero
            glowLayer.backgroundColor = NSColor.clear.cgColor
            glowLayer.frame = bounds
            layer.insertSublayer(glowLayer, at: 0)
        }
    }
}

// MARK: - Animation

struct IndustrialAnimation {
    
    /// 标准动画时长（120ms）
    static let standard: TimeInterval = 0.12
    
    /// 长动画时长（200ms，状态切换）
    static let long: TimeInterval = 0.2
    
    /// 实时反馈时长（16.7ms，60fps）
    static let realtime: TimeInterval = 0.016
    
    /// 缓动函数（ease-out）
    static let easeOut = CAMediaTimingFunction(name: .easeOut)
    
    /// 缓动函数（linear）
    static let linear = CAMediaTimingFunction(name: .linear)
}

// MARK: - NSColor Hex Extension

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }
        
        var rgb: UInt64 = 0
        Scanner(string: hexStr).scanHexInt64(&rgb)
        
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >>  8) & 0xFF) / 255.0,
            blue:  CGFloat( rgb        & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

// MARK: - Grid Texture Utility

extension NSView {
    
    /// 添加 24px 网格纹理（Sidebar 背景）
    func addGridTexture(spacing: CGFloat = IndustrialSpacing.gridTextureInterval) {
        guard let layer = self.layer else {
            print("⚠️ Warning: view.wantsLayer must be true before adding grid texture")
            return
        }
        
        let gridLayer = CAShapeLayer()
        let path = CGMutablePath()
        
        // 垂直线
        var x: CGFloat = 0
        while x <= bounds.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
            x += spacing
        }
        
        // 水平线
        var y: CGFloat = 0
        while y <= bounds.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }
        
        gridLayer.path = path
        gridLayer.strokeColor = IndustrialColors.gridLight.cgColor
        gridLayer.lineWidth = 1
        gridLayer.fillColor = nil
        
        layer.insertSublayer(gridLayer, at: 0)
    }
}
```

---

## 6. 实现指南

### 6.1 快速上手步骤

#### Step 1: 导入设计 Token
将 `IndustrialDesignTokens.swift` 添加到项目中，替换所有硬编码的颜色/字体/间距。

#### Step 2: 应用 Sidebar 样式
```swift
import Cocoa

class SidebarView: NSView {
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surfaceContainer.cgColor
        
        // 添加网格纹理
        addGridTexture()
        
        // 右侧边框
        layer?.borderWidth = 1
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
    }
}
```

#### Step 3: 创建录制按钮
```swift
class RecordButton: NSButton {
    
    private var isRecording = false
    private var buttonWidthConstraint: NSLayoutConstraint?
    private var buttonHeightConstraint: NSLayoutConstraint?
    private let innerSquare = NSView()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButton()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }
    
    private func setupButton() {
        wantsLayer = true
        isBordered = false
        
        // 空闲态样式
        layer?.backgroundColor = IndustrialColors.statusCritical.cgColor
        layer?.cornerRadius = 32
        layer?.masksToBounds = false
        
        // 多重发光
        IndustrialGlow.multilayerCyan(to: layer!, bounds: CGRect(x: 0, y: 0, width: 64, height: 64))
        
        // 硬边阴影
        IndustrialShadow.small(layer: layer!)
        
        // 内部白色方块（初始隐藏）
        innerSquare.wantsLayer = true
        innerSquare.layer?.backgroundColor = NSColor.white.cgColor
        innerSquare.layer?.cornerRadius = 4
        innerSquare.isHidden = true
        addSubview(innerSquare)
        
        // 约束
        translatesAutoresizingMaskIntoConstraints = false
        buttonWidthConstraint = widthAnchor.constraint(equalToConstant: 64)
        buttonHeightConstraint = heightAnchor.constraint(equalToConstant: 64)
        NSLayoutConstraint.activate([buttonWidthConstraint!, buttonHeightConstraint!])
        
        // 内部方块约束
        innerSquare.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            innerSquare.centerXAnchor.constraint(equalTo: centerXAnchor),
            innerSquare.centerYAnchor.constraint(equalTo: centerYAnchor),
            innerSquare.widthAnchor.constraint(equalToConstant: 20),
            innerSquare.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    override func mouseDown(with event: NSEvent) {
        // 下沉效果
        layer?.transform = CATransform3DMakeTranslation(0, -3, 0)
        layer?.shadowRadius = 12
    }
    
    override func mouseUp(with event: NSEvent) {
        // 反弹 + 切换状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = IndustrialAnimation.standard
                context.timingFunction = IndustrialAnimation.easeOut
                self.layer?.transform = CATransform3DIdentity
                self.layer?.shadowRadius = 20
            })
            
            self.toggleRecordingState()
        }
    }
    
    private func toggleRecordingState() {
        isRecording.toggle()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = IndustrialAnimation.long
            context.timingFunction = IndustrialAnimation.easeOut
            
            if self.isRecording {
                // 空闲 → 录制
                self.buttonWidthConstraint?.animator().constant = 48
                self.buttonHeightConstraint?.animator().constant = 48
                self.layer?.cornerRadius = 24
                self.innerSquare.isHidden = false
                self.layer?.shadowColor = IndustrialColors.glowDanger.cgColor
                self.layer?.shadowRadius = 16
            } else {
                // 录制 → 空闲
                self.buttonWidthConstraint?.animator().constant = 64
                self.buttonHeightConstraint?.animator().constant = 64
                self.layer?.cornerRadius = 32
                self.innerSquare.isHidden = true
                self.layer?.shadowColor = IndustrialColors.glowCyan.cgColor
                self.layer?.shadowRadius = 20
            }
        })
    }
}
```

#### Step 4: 创建电平表
```swift
class LevelMeterView: NSView {
    
    private let leftBar = NSView()
    private let rightBar = NSView()
    private var leftWidthConstraint: NSLayoutConstraint?
    private var rightWidthConstraint: NSLayoutConstraint?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = IndustrialColors.surfaceContainer.withAlphaComponent(0.8).cgColor
        layer?.cornerRadius = IndustrialCornerRadius.sm
        layer?.borderWidth = 1
        layer?.borderColor = IndustrialColors.outlineVariant.cgColor
        
        // 添加左右声道条
        [leftBar, rightBar].forEach { bar in
            bar.wantsLayer = true
            bar.layer?.backgroundColor = IndustrialColors.primaryContainer.cgColor
            addSubview(bar)
        }
        
        // 约束（省略详细布局代码）
    }
    
    func updateLevels(left: Float, right: Float) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(IndustrialAnimation.realtime)
        CATransaction.setAnimationTimingFunction(IndustrialAnimation.linear)
        
        leftWidthConstraint?.constant = CGFloat(left) * 100
        rightWidthConstraint?.constant = CGFloat(right) * 100
        
        updateBarColor(bar: leftBar, level: left)
        updateBarColor(bar: rightBar, level: right)
        
        CATransaction.commit()
    }
    
    private func updateBarColor(bar: NSView, level: Float) {
        let color: NSColor
        let glowColor: NSColor?
        
        if level > 0.9 {
            color = IndustrialColors.statusDanger
            glowColor = IndustrialColors.glowDanger
            IndustrialGlow.danger(layer: bar.layer!)
        } else if level > 0.7 {
            color = IndustrialColors.statusWarning
            glowColor = IndustrialColors.glowWarning
            IndustrialGlow.warning(layer: bar.layer!)
        } else {
            color = IndustrialColors.primaryContainer
            glowColor = nil
            bar.layer?.shadowColor = nil
        }
        
        bar.layer?.backgroundColor = color.cgColor
    }
}
```

---

### 6.2 调试工具

#### 显示所有颜色（调试面板）
```swift
class ColorDebugView: NSView {
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let colors: [(name: String, color: NSColor)] = [
            ("surface", IndustrialColors.surface),
            ("surfaceContainerLow", IndustrialColors.surfaceContainerLow),
            ("surfaceContainer", IndustrialColors.surfaceContainer),
            ("primary", IndustrialColors.primary),
            ("statusWarning", IndustrialColors.statusWarning),
            ("statusDanger", IndustrialColors.statusDanger)
        ]
        
        var y: CGFloat = 20
        for (name, color) in colors {
            // 绘制色块
            color.setFill()
            NSBezierPath(rect: CGRect(x: 20, y: y, width: 100, height: 30)).fill()
            
            // 绘制名称
            let attributes: [NSAttributedString.Key: Any] = [
                .font: IndustrialTypography.small,
                .foregroundColor: IndustrialColors.onSurface
            ]
            name.draw(at: CGPoint(x: 130, y: y + 8), withAttributes: attributes)
            
            y += 40
        }
    }
}
```

---

### 6.3 性能优化建议

1. **波形绘制**：使用 `CAShapeLayer` + `CADisplayLink` 实现 60fps 更新，避免阻塞主线程。
2. **电平表更新**：使用 `CATransaction` 关闭隐式动画，确保线性更新。
3. **发光效果**：仅在需要时启用，录制时关闭网格纹理以减少 GPU 负载。
4. **网格纹理**：使用单一 `CAShapeLayer`，避免为每条线创建独立图层。

---

## 7. 设计验收清单（Checklist）

在完成实现后，使用此清单验证设计一致性：

### 7.1 配色验收

- [ ] 所有背景色使用 `IndustrialColors` 定义的 surface 系列
- [ ] 文字色使用 `onSurface` / `onSurfaceVariant` / `textSecondary`
- [ ] 主色（青色）仅用于活跃状态（选中项、电平表、计时器）
- [ ] 警示色（琥珀、红色）仅用于必要提示（高电平、过载、录制中）
- [ ] 无自定义颜色（所有颜色来自 Design Tokens）

### 7.2 字体验收

- [ ] 标题全大写（H1, H2, Label）
- [ ] 数字采用等宽字体（计时器、dB 值）
- [ ] 字号符合设计系统（18px, 14px, 13px, 12px, 11px, 28px, 10px）
- [ ] 字距增强（标题 0.05em，标签 0.4px，计时器 0.1em）

### 7.3 间距验收

- [ ] Sidebar 宽度固定 240px
- [ ] 内边距使用 `xs/sm/md/lg/xl` 系列（4px, 8px, 16px, 24px, 32px）
- [ ] 网格间隔 24px（Sidebar 背景纹理）
- [ ] 边缘留白 12px（`gutter`）

### 7.4 视觉特效验收

- [ ] 阴影短而锐利（6px / 12px / 18px，Y 偏移 2px / 4px / 6px）
- [ ] 发光仅在必要时使用（青色、琥珀、红色）
- [ ] 网格纹理清晰可见（`grid-light` alpha 0.03）
- [ ] 波形渐变方向正确（上→下）

### 7.5 交互动效验收

- [ ] 标准动画 120ms（hover, press, focus）
- [ ] 状态切换 200ms（录制开始/停止）
- [ ] 电平表 60fps 更新（16.7ms linear）
- [ ] 录制按钮下沉 3px（press），反弹动画流畅

### 7.6 工业风格验收

- [ ] 界面传达"硬朗、可靠、专业"的感觉
- [ ] 无柔和圆角（仅 2px / 4px 圆角）
- [ ] 无浮华装饰（避免 glassmorphism、neomorphism）
- [ ] 网格纹理和锐利阴影强化工业感

---

## 8. 附录

### 8.1 工具推荐

| 工具 | 用途 |
|------|------|
| **Figma/Sketch** | 原型设计、组件预览 |
| **SF Symbols** | macOS 原生图标库 |
| **ColorSlurp** | 色值提取工具（验证实现是否匹配设计） |
| **Xcode Instruments** | 性能分析（波形绘制、发光效果） |

### 8.2 参考资源

- **Stitch DESIGN.md**: `/Users/voidzhang/Documents/workspace/audio_record_mac/docs/designs/stitch_desktop_application_project/DESIGN.md`
- **Material Design 3**: 工业警示色参考
- **macOS Human Interface Guidelines**: 原生组件规范

---

## 📄 文档变更日志

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|---------|------|
| v1.0 | 2026-05-01 | 初始版本，完整 Industrial Design 规范 | 绘·视觉设计 |

---

**设计目标**：打造一款"坚固、工程化、可信赖"的专业音频录制工具，让用户感到正在操作可靠的工业设备。

**下一步**：应用本规范到代码实现，逐组件验证视觉效果。

---

## 9. v1.1 首席设计师更新：控制台骨架升级

### 9.1 设计判断

当前实现已经具备 Industrial Design 的配色基础，但要达到「耐用、可维护、专业硬核」的控制台气质，不能只做深色皮肤。界面必须形成明确的系统设备结构：主仪表区、传输控制区、输入总线区、轨道监控区、告警/状态栏。

新的 UI 原则：

1. **WaveformView 是主仪表区**：它不是装饰，而是实时信号监控面板。必须位于主内容顶部，包含网格、刻度、LIVE SIGNAL 状态和右上角 L/R 电平叠加层。
2. **ControlPanelView 是硬件控制面板**：录制按钮应嵌入面板，旁边显示状态铭牌（STANDBY / RECORDING / FAULT）、格式、采样率、输入源等设备读数。
3. **减少漂浮感**：Glow 只表达状态，不作为装饰。Hover 增亮描边，Press 下沉并收敛光晕。
4. **信息密度提升但保持秩序**：所有关键状态以小号等宽/大写标签展示，像 DevOps/工控台一样可长期运行。

### 9.2 新主布局

```text
┌──────────────┬──────────────────────────────────────────────┐
│ INPUT BUS    │ LIVE SIGNAL / WAVEFORM                       │
│ PROCESS TAP  │ ┌──────────────────────────────────────────┐ │
│ FILES        │ │ GRID + WAVEFORM + L/R METERS             │ │
│              │ └──────────────────────────────────────────┘ │
│              │ TRACK MONITOR                                │
│              │ ┌──────────────────────────────────────────┐ │
│              │ │ TRACK 01 - SYSTEM AUDIO                  │ │
│              │ └──────────────────────────────────────────┘ │
├──────────────┴──────────────────────────────────────────────┤
│ TRANSPORT CONTROL | STATUS | FORMAT | SAMPLE RATE | INPUT   │
└──────────────────────────────────────────────────────────────┘
```

### 9.3 组件升级要求

| 组件 | v1.1 要求 |
|------|----------|
| `MainWindowView` | 主内容区必须包含 `WaveformView` + `LevelMetersOverlay`，Tracks 退为监控列表 |
| `ControlPanelView` | 添加标题、状态铭牌、输入/格式/采样率读数，录制按钮保持硬件按键语义 |
| `SidebarView` | 继续去系统控件；选中态、hover、列表行全部自绘 |
| `RecordedFilesView` | 文件列表最终迁移到 `NSScrollView + NSStackView + 自绘 Row`，避免 `NSTableView` 系统味 |
| 告警 | 权限错误/录制错误/过载应进入统一告警条，低频闪烁且可关闭 |

---

🎨 **End of Document**
