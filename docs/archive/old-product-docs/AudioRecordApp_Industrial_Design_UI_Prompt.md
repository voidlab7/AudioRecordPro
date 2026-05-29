# AudioRecordApp UI Prompt — Industrial Design

> **专业音频录制工具的工业设计规范**  
> 版本: v1.0 | 创建: 2026-05-01 | 目标平台: macOS (AppKit + Swift)

---

## 角色设定（Role）

你是一名精通 **macOS AppKit 开发**的 UI 设计师，擅长 **Industrial Design（工业设计）** 风格，正在为**专业音频录制工具**设计界面。

你的任务是将 **工业控制台的视觉语言** 应用到音频录制器中，让用户感到：
- 这是一款**专业可靠的工作室级工具**
- 界面清晰、功能明确、反馈直接
- 适合长时间音频制作工作
- 视觉上与音频工程师熟悉的**硬件录音机、监听设备**呼应

---

## 1. 设计理念（Design Philosophy）

### 为什么选择 Industrial Design 风格？

**音频录制工具与工业设备的天然契合**：
1. **专业可靠性**：音频工程师需要的是"工具"，不是"玩具"——Industrial 风格的**深色基调、金属质感、清晰警示色**完美传达这种专业感。
2. **长时间使用舒适性**：工作室环境通常暗色灯光，Industrial 的**深色主题**减少视觉疲劳，符合监听环境。
3. **清晰的功能分区**：录制、波形、轨道、控制面板需要**明确区分**，工业风格的**网格布局、边框分隔、层次阴影**天然适合。
4. **硬件感**：物理录音机的按钮、指示灯、表头——Industrial 风格可以将这些物理元素**数字化映射**。

### 核心设计原则

1. **工作室级专业感（Studio-Grade Professionalism）**  
   - 深色背景模拟**监听室环境**
   - 金属质感呼应**硬件录音设备**
   - 清晰的视觉层级，无冗余装饰

2. **高信息密度 + 清晰可读（Dense Yet Readable）**  
   - 等宽字体用于时间码、电平数值
   - 充足的间距与分组，避免拥挤
   - 关键信息用**高对比度**突出

3. **直接明确的反馈（Immediate Feedback）**  
   - 录制状态用**红色发光**清晰标识
   - 电平表实时响应，**渐变色 + 高电平警示**
   - 交互动效短促有力（100-150ms），像按硬件按钮

4. **功能性优先（Function Over Form）**  
   - 每个视觉元素都有功能意义（不做无用装饰）
   - 颜色仅用于**状态指示、数据可视化、警示**
   - 保持克制，避免过度动效

5. **可扩展性（Scalable & Maintainable）**  
   - 组件设计可复用（轨道视图可扩展至多轨）
   - 遵循 Apple HIG，但保持工业风格特征
   - 支持浅色模式切换（可选）

---

## 2. 配色方案（Color Palette）

### 背景与基底色（Backgrounds）

```swift
// 深色基底 - 模拟工作室监听环境
static let baseBlack = NSColor(hex: "#0A0C10")          // 最深黑：主背景
static let baseDark = NSColor(hex: "#0F1419")           // 深灰：Sidebar、面板背景
static let basePanel = NSColor(hex: "#1A1F29")          // 中灰：卡片、悬停态
static let baseBorder = NSColor(hex: "#2D3748")         // 边框：分隔线、描边
```

**为什么这些颜色？**
- `#0A0C10`：接近纯黑但带微弱蓝调，减少纯黑的刺眼感，符合音频监听室的暗色环境。
- `#0F1419`：作为 Sidebar 和主容器背景，与主背景形成微妙层次。
- `#1A1F29`：用于悬停态、卡片，提供足够的视觉分层。
- `#2D3748`：边框色，清晰但不抢眼。

### 文本颜色（Text Colors）

```swift
// 文本 - 高对比，易读
static let textPrimary = NSColor(hex: "#E2E8F0")        // 主文本：标题、标签
static let textSecondary = NSColor(hex: "#CBD5E0")      // 次要文本：描述、提示
static let textTertiary = NSColor(hex: "#A0AEC0")       // 三级文本：占位符、禁用态
static let textMono = NSColor(hex: "#F7FAFC")           // 等宽字体：时间码、数值
```

### 主色调（Primary Accents）- 冷色调科技感

```swift
// 青色 - 主要交互色
static let cyanPrimary = NSColor(hex: "#22D3EE")        // 主青色：按钮、高亮、链接
static let cyanLight = NSColor(hex: "#06B6D4")          // 深青色：悬停态
static let cyanGlow = NSColor(hex: "#22D3EE").withAlphaComponent(0.25) // 发光效果

// 天蓝色 - 次要操作
static let bluePrimary = NSColor(hex: "#38BDF8")        // 次要按钮
static let blueLight = NSColor(hex: "#0EA5E9")          // 深蓝
```

**应用场景**：
- **青色**：录制按钮空闲态、波形高亮、选中状态
- **蓝色**：次要按钮（保存、导出）、文件选中态

### 功能色（Functional Colors）- 音频专业语义

```swift
// 成功 - 绿色（信号正常）
static let successGreen = NSColor(hex: "#10B981")       // 正常电平、录制完成
static let successLight = NSColor(hex: "#34D399")       // 浅绿色

// 警告 - 琥珀色（高电平预警）
static let warningAmber = NSColor(hex: "#F59E0B")       // 接近削峰
static let warningOrange = NSColor(hex: "#FB923C")      // 中度警告

// 危险 - 红色（削峰、错误）
static let dangerRed = NSColor(hex: "#EF4444")          // 削峰、错误
static let criticalRed = NSColor(hex: "#DC2626")        // 严重错误

// 录制状态 - 红色发光
static let recordingRed = NSColor(hex: "#FF3B30")       // 录制按钮激活态
static let recordingGlow = NSColor(hex: "#FF3B30").withAlphaComponent(0.4) // 脉冲光晕
```

**音频语义映射**：
- **绿色（-18 dB ~ -6 dB）**：信号健康，正常工作电平
- **琥珀色（-6 dB ~ -3 dB）**：接近峰值，需注意
- **红色（> -3 dB）**：削峰危险，立即降低增益
- **录制红**：录制状态，模拟硬件录音机的红色指示灯

### 网格与纹理（Grids & Textures）

```swift
// 背景网格 - 工业质感
static let gridLight = NSColor.white.withAlphaComponent(0.02)
static let gridMedium = NSColor.white.withAlphaComponent(0.04)
static let gridHeavy = NSColor.white.withAlphaComponent(0.08)

// 拉丝金属效果（可选渐变）
static let metalGradient = NSGradient(colors: [
    NSColor(hex: "#1A1F29"),
    NSColor(hex: "#0F1419"),
    NSColor(hex: "#1A1F29")
])
```

### 完整 Hex 色卡速查表

| 用途 | 颜色名 | Hex 值 | 场景 |
|-----|--------|--------|------|
| **背景** | Base Black | `#0A0C10` | 主窗口背景 |
| | Base Dark | `#0F1419` | Sidebar、面板背景 |
| | Base Panel | `#1A1F29` | 卡片、悬停态 |
| | Base Border | `#2D3748` | 边框、分隔线 |
| **文本** | Text Primary | `#E2E8F0` | 主标题、标签 |
| | Text Secondary | `#CBD5E0` | 描述文本 |
| | Text Tertiary | `#A0AEC0` | 占位符 |
| | Text Mono | `#F7FAFC` | 时间码、数值 |
| **主色** | Cyan Primary | `#22D3EE` | 主按钮、高亮 |
| | Cyan Light | `#06B6D4` | 悬停态 |
| | Blue Primary | `#38BDF8` | 次要操作 |
| **功能色** | Success Green | `#10B981` | 正常电平 |
| | Warning Amber | `#F59E0B` | 高电平预警 |
| | Danger Red | `#EF4444` | 削峰、错误 |
| | Recording Red | `#FF3B30` | 录制激活态 |

---

## 3. 字体排版（Typography）

### 字体族（Font Family）

```swift
// 主字体 - SF Pro（macOS 系统字体）
static let fontSans = NSFont.systemFont(ofSize: 13, weight: .regular)
static let fontSansBold = NSFont.systemFont(ofSize: 13, weight: .bold)

// 等宽字体 - SF Mono（时间码、电平数值）
static let fontMono = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
static let fontMonoBold = NSFont.monospacedSystemFont(ofSize: 16, weight: .bold)
```

**为什么用 SF Pro + SF Mono？**
- **SF Pro**：macOS 原生字体，清晰、易读，与系统风格一致
- **SF Mono**：等宽字体，数字对齐，适合时间码（`00:00.00`）、电平数值（`-12.3 dB`）

### 字号系统（Font Size Scale）

| 用途 | 字号 | Weight | 场景 |
|-----|------|--------|------|
| **超大标题** | 24pt | Bold | 窗口标题（可选） |
| **大标题** | 18pt | Bold | 主要区块标题（如"波形视图"） |
| **标题** | 14pt | Bold | 组件标题（如"音频源"） |
| **正文** | 13pt | Regular | 标签、描述文本 |
| **小字** | 11pt | Regular | 辅助信息、提示 |
| **超小字** | 10pt | Medium | 状态栏、版本号 |
| **时间码** | 16pt | Bold (Mono) | 录制计时器 |
| **电平数值** | 12pt | Medium (Mono) | 电平表数值 |

### 行高（Line Height）

```swift
// 行高倍数
static let lineHeightTight: CGFloat = 1.2       // 标题
static let lineHeightNormal: CGFloat = 1.5      // 正文
static let lineHeightRelaxed: CGFloat = 1.6     // 长文本
```

### 大写与字距（Uppercase & Letter Spacing）

**工业风格特征：标题全大写 + 增加字距**

```swift
// 标题样式
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .bold),
    .foregroundColor: textPrimary,
    .kern: 1.2,  // 字距增加 1.2pt
]

// 使用示例
let titleString = NSAttributedString(
    string: "AUDIO SOURCE",
    attributes: titleAttributes
)
```

**规则**：
- 所有组件标题、状态标签使用 **全大写 + 增加字距（0.8-1.5pt）**
- 计时器、文件名保持**原始大小写**
- 按钮文本可选全大写（视空间而定）

### 字体示例代码

```swift
// MARK: - Typography System

extension NSFont {
    // Sans-serif family
    static let heading1 = NSFont.systemFont(ofSize: 18, weight: .bold)
    static let heading2 = NSFont.systemFont(ofSize: 14, weight: .bold)
    static let bodyRegular = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let bodySemibold = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let caption = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let overline = NSFont.systemFont(ofSize: 10, weight: .medium)
    
    // Monospace family
    static let timecode = NSFont.monospacedSystemFont(ofSize: 16, weight: .bold)
    static let levelValue = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    static let statusMono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
}

extension NSAttributedString {
    // 标题样式（全大写 + 字距）
    static func uppercaseTitle(_ text: String, size: CGFloat = 14) -> NSAttributedString {
        return NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: NSColor(hex: "#E2E8F0"),
                .kern: 1.2
            ]
        )
    }
}
```

---

## 4. 组件设计规范（Component Specifications）

### 4.1 Sidebar (侧边栏)

**功能**：音频源选择、文件列表

**设计规范**：

```swift
// 尺寸
static let sidebarWidth: CGFloat = 240
static let sidebarPadding: CGFloat = 12

// 背景材质
let sidebar = NSView()
sidebar.wantsLayer = true
sidebar.layer?.backgroundColor = NSColor(hex: "#0F1419").cgColor

// 边框（右侧分隔线）
let border = CALayer()
border.backgroundColor = NSColor(hex: "#2D3748").cgColor
border.frame = CGRect(x: sidebarWidth - 1, y: 0, width: 1, height: height)
sidebar.layer?.addSublayer(border)

// 网格纹理（可选）
let gridLayer = CALayer()
gridLayer.backgroundColor = NSColor.white.withAlphaComponent(0.02).cgColor
gridLayer.frame = sidebar.bounds
sidebar.layer?.insertSublayer(gridLayer, at: 0)
```

**交互状态**：

| 状态 | 背景色 | 边框 | 文本色 |
|-----|--------|------|--------|
| **默认** | `#0F1419` | 无 | `#CBD5E0` |
| **Hover** | `#1A1F29` | 无 | `#E2E8F0` |
| **Selected** | `#22D3EE` (10% opacity) | 左边框 2pt `#22D3EE` | `#22D3EE` |
| **Disabled** | `#0F1419` | 无 | `#A0AEC0` |

**音频源列表项**：

```swift
struct AudioSourceItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? cyanPrimary : textSecondary)
            
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.8)
                .foregroundColor(isSelected ? cyanPrimary : textSecondary)
            
            Spacer()
            
            if isSelected {
                Circle()
                    .fill(cyanPrimary)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? cyanPrimary.opacity(0.1) : Color.clear)
        .overlay(
            Rectangle()
                .fill(isSelected ? cyanPrimary : Color.clear)
                .frame(width: 2)
                .padding(.leading, 0),
            alignment: .leading
        )
    }
}
```

**文件列表**：

```swift
// 文件列表项
struct FileListItem: View {
    let filename: String
    let duration: String
    let size: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(filename)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(textPrimary)
                .lineLimit(1)
            
            HStack(spacing: 8) {
                Text(duration)
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundColor(textTertiary)
                
                Text("·")
                    .foregroundColor(textTertiary)
                
                Text(size)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
```

---

### 4.2 WaveformView (波形视图)

**功能**：实时波形显示 + 双声道电平表

**设计规范**：

#### 波形背景

```swift
// 背景网格
let gridLayer = CAShapeLayer()
let gridPath = CGMutablePath()

// 水平网格线（每 20% 一条）
for i in 1..<5 {
    let y = bounds.height * CGFloat(i) / 5
    gridPath.move(to: CGPoint(x: 0, y: y))
    gridPath.addLine(to: CGPoint(x: bounds.width, y: y))
}

// 垂直网格线（每秒一条，假设 60px/s）
let interval: CGFloat = 60
for x in stride(from: 0, to: bounds.width, by: interval) {
    gridPath.move(to: CGPoint(x: x, y: 0))
    gridPath.addLine(to: CGPoint(x: x, y: bounds.height))
}

gridLayer.path = gridPath
gridLayer.strokeColor = NSColor.white.withAlphaComponent(0.04).cgColor
gridLayer.lineWidth = 1
```

#### 波形颜色（状态驱动）

| 状态 | 颜色 | 发光效果 |
|-----|------|---------|
| **空闲态** | `#22D3EE` (青色，50% opacity) | 无 |
| **录制态** | `#22D3EE` → `#10B981` 渐变 | 轻微外发光 |
| **削峰警告** | `#EF4444` (红色，闪烁) | 强外发光 |

```swift
// 空闲态波形
let idleWaveformColor = NSColor(hex: "#22D3EE").withAlphaComponent(0.5)

// 录制态波形（渐变）
let recordingGradient = NSGradient(colors: [
    NSColor(hex: "#22D3EE"),
    NSColor(hex: "#10B981")
])

// 削峰警告（闪烁动画）
let clippingAnimation = CABasicAnimation(keyPath: "opacity")
clippingAnimation.fromValue = 1.0
clippingAnimation.toValue = 0.3
clippingAnimation.duration = 0.2
clippingAnimation.autoreverses = true
clippingAnimation.repeatCount = .infinity
```

#### 电平表（LevelMetersOverlay）

**设计**：垂直条形图，左右声道，颜色分段

```swift
struct LevelMeter: View {
    let level: CGFloat  // 0.0 ~ 1.0
    
    private func colorForLevel(_ level: CGFloat) -> Color {
        switch level {
        case 0.0..<0.6:   return Color(hex: "#10B981")  // 绿色（正常）
        case 0.6..<0.85:  return Color(hex: "#F59E0B")  // 琥珀色（注意）
        default:          return Color(hex: "#EF4444")  // 红色（削峰）
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 背景槽
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#1A1F29"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color(hex: "#2D3748"), lineWidth: 1)
                    )
                
                // 电平条（渐变）
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#EF4444"),      // 顶部红色
                        Color(hex: "#F59E0B"),      // 中部琥珀色
                        Color(hex: "#10B981")       // 底部绿色
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask(
                    RoundedRectangle(cornerRadius: 2)
                        .frame(height: geometry.size.height * level)
                )
                .shadow(color: colorForLevel(level).opacity(0.5), radius: 4, x: 0, y: 0)
            }
        }
    }
}

// 双声道布局
struct StereoLevelMeters: View {
    let leftLevel: CGFloat
    let rightLevel: CGFloat
    
    var body: some View {
        HStack(spacing: 4) {
            LevelMeter(level: leftLevel)
                .frame(width: 8)
            LevelMeter(level: rightLevel)
                .frame(width: 8)
        }
    }
}
```

**刻度标签**：

```swift
// dB 刻度标签（-60, -40, -20, -10, -6, -3, 0）
struct LevelScale: View {
    let labels = ["0", "-3", "-6", "-10", "-20", "-40", "-60"]
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundColor(Color(hex: "#A0AEC0"))
                Spacer()
            }
        }
    }
}
```

---

### 4.3 ControlPanelView (控制面板)

**功能**：录制按钮 + 计时器

#### 录制按钮

**设计语言**：模拟硬件录音机的物理按钮

```swift
struct RecordButton: View {
    @Binding var isRecording: Bool
    
    var body: some View {
        Button(action: { isRecording.toggle() }) {
            ZStack {
                // 外圈（金属环）
                Circle()
                    .strokeBorder(
                        isRecording ? Color(hex: "#FF3B30") : Color(hex: "#2D3748"),
                        lineWidth: 3
                    )
                    .frame(width: 64, height: 64)
                    .shadow(
                        color: isRecording ? Color(hex: "#FF3B30").opacity(0.4) : Color.clear,
                        radius: isRecording ? 12 : 0,
                        x: 0,
                        y: 0
                    )
                
                // 内圈（填充）
                Circle()
                    .fill(
                        isRecording
                            ? Color(hex: "#FF3B30")
                            : Color(hex: "#22D3EE")
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(
                        color: isRecording ? Color(hex: "#FF3B30").opacity(0.6) : Color(hex: "#22D3EE").opacity(0.3),
                        radius: 8,
                        x: 0,
                        y: 0
                    )
                
                // 图标
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isRecording ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isRecording)
    }
}
```

**状态定义**：

| 状态 | 外圈颜色 | 内圈颜色 | 发光效果 | 图标 |
|-----|---------|---------|---------|------|
| **空闲态** | `#2D3748` (灰) | `#22D3EE` (青) | 轻微青色光晕 | `record.circle` |
| **录制态** | `#FF3B30` (红) | `#FF3B30` (红) | 强红色脉冲光晕 | `stop.fill` |
| **Hover** | 颜色增亮 10% | 颜色增亮 5% | 光晕增强 | 同上 |
| **Pressed** | 缩放至 0.95 | 缩放至 0.95 | 光晕收敛 | 同上 |

**脉冲动画**（录制态）：

```swift
// 脉冲光晕动画
@State private var pulseAnimation = false

.shadow(
    color: Color(hex: "#FF3B30").opacity(pulseAnimation ? 0.6 : 0.3),
    radius: pulseAnimation ? 16 : 8,
    x: 0,
    y: 0
)
.onAppear {
    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
        pulseAnimation = true
    }
}
```

#### 计时器

**设计**：等宽字体 + 大字号 + 微妙金属背景

```swift
struct TimecodeDisplay: View {
    let elapsed: TimeInterval
    
    private var formattedTime: String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let centiseconds = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Text(formattedTime)
                .font(.system(size: 28, weight: .bold).monospacedDigit())
                .foregroundColor(Color(hex: "#F7FAFC"))
                .tracking(2)  // 字距增加
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1A1F29"),
                            Color(hex: "#0F1419"),
                            Color(hex: "#1A1F29")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(hex: "#2D3748"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}
```

**完整控制面板布局**：

```swift
struct ControlPanelView: View {
    @Binding var isRecording: Bool
    @Binding var elapsed: TimeInterval
    
    var body: some View {
        HStack(spacing: 24) {
            // 录制按钮
            RecordButton(isRecording: $isRecording)
            
            // 计时器
            TimecodeDisplay(elapsed: elapsed)
            
            Spacer()
            
            // 次要操作（保存、设置）
            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button(action: {}) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .background(Color(hex: "#0F1419"))
        .overlay(
            Rectangle()
                .fill(Color(hex: "#2D3748"))
                .frame(height: 1),
            alignment: .top
        )
    }
}

// 次要按钮样式
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Color(hex: "#CBD5E0"))
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#1A1F29"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "#2D3748"), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
```

---

### 4.4 TracksView (轨道视图)

**功能**：多音源轨道信息展示

**设计**：类似 DAW（数字音频工作站）的轨道列表

```swift
struct TrackItem: View {
    let track: AudioTrack
    
    var body: some View {
        HStack(spacing: 12) {
            // 轨道编号
            Text("\(track.number)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundColor(Color(hex: "#A0AEC0"))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#1A1F29"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(hex: "#2D3748"), lineWidth: 1)
                )
            
            // 轨道名称
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(Color(hex: "#E2E8F0"))
                
                Text(track.source)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(Color(hex: "#A0AEC0"))
            }
            
            Spacer()
            
            // 电平表（迷你版）
            StereoLevelMeters(leftLevel: track.leftLevel, rightLevel: track.rightLevel)
                .frame(width: 20, height: 32)
            
            // 静音/独奏按钮
            HStack(spacing: 4) {
                TrackControlButton(icon: "speaker.slash.fill", isActive: track.isMuted)
                TrackControlButton(icon: "headphones", isActive: track.isSolo)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "#0F1419"))
        .overlay(
            Rectangle()
                .fill(Color(hex: "#2D3748"))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

struct TrackControlButton: View {
    let icon: String
    let isActive: Bool
    
    var body: some View {
        Button(action: {}) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isActive ? Color(hex: "#22D3EE") : Color(hex: "#A0AEC0"))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? Color(hex: "#22D3EE").opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
```

---

### 4.5 StatusBarView (状态栏)

**功能**：系统状态信息（音频接口、采样率、位深度、CPU 占用率）

```swift
struct StatusBarView: View {
    let audioInterface: String
    let sampleRate: Int
    let bitDepth: Int
    let cpuUsage: Double
    
    var body: some View {
        HStack(spacing: 16) {
            // 音频接口
            StatusItem(
                icon: "waveform.circle.fill",
                label: "INTERFACE",
                value: audioInterface
            )
            
            Divider()
                .frame(height: 16)
                .background(Color(hex: "#2D3748"))
            
            // 采样率
            StatusItem(
                icon: "waveform",
                label: "SAMPLE RATE",
                value: "\(sampleRate / 1000) kHz"
            )
            
            Divider()
                .frame(height: 16)
                .background(Color(hex: "#2D3748"))
            
            // 位深度
            StatusItem(
                icon: "square.stack.3d.up.fill",
                label: "BIT DEPTH",
                value: "\(bitDepth)-bit"
            )
            
            Spacer()
            
            // CPU 占用率
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#A0AEC0"))
                
                Text("CPU")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "#A0AEC0"))
                    .kerning(0.5)
                
                Text(String(format: "%.1f%%", cpuUsage))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundColor(
                        cpuUsage > 80 ? Color(hex: "#EF4444") :
                        cpuUsage > 60 ? Color(hex: "#F59E0B") :
                        Color(hex: "#10B981")
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#1A1F29"))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: "#0F1419"))
        .overlay(
            Rectangle()
                .fill(Color(hex: "#2D3748"))
                .frame(height: 1),
            alignment: .top
        )
    }
}

struct StatusItem: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#22D3EE"))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: "#A0AEC0"))
                    .kerning(0.5)
                
                Text(value)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color(hex: "#E2E8F0"))
            }
        }
    }
}
```

---

## 5. 视觉特效（Visual Effects）

### 阴影系统（Shadow）

**原则**：短而锐利，避免柔和漂浮感

```swift
// 阴影层级
enum IndustrialShadow {
    case none
    case sm      // 浅阴影：卡片、按钮
    case md      // 中等阴影：面板、弹窗
    case lg      // 深阴影：菜单、模态框
    
    var radius: CGFloat {
        switch self {
        case .none: return 0
        case .sm: return 4
        case .md: return 8
        case .lg: return 12
        }
    }
    
    var opacity: Double {
        switch self {
        case .none: return 0
        case .sm: return 0.35
        case .md: return 0.45
        case .lg: return 0.55
        }
    }
    
    var offset: CGSize {
        switch self {
        case .none: return .zero
        case .sm: return CGSize(width: 0, height: 2)
        case .md: return CGSize(width: 0, height: 4)
        case .lg: return CGSize(width: 0, height: 6)
        }
    }
}

// 使用示例
.shadow(
    color: Color.black.opacity(IndustrialShadow.md.opacity),
    radius: IndustrialShadow.md.radius,
    x: IndustrialShadow.md.offset.width,
    y: IndustrialShadow.md.offset.height
)
```

### 发光效果（Glow）

**应用场景**：
1. 录制按钮激活态（红色脉冲）
2. 高电平警告（红色/琥珀色光晕）
3. 悬停态高亮（青色轻微发光）

```swift
// 发光层级
enum IndustrialGlow {
    case none
    case subtle      // 轻微：青色悬停
    case moderate    // 中等：录制按钮空闲态
    case intense     // 强烈：录制按钮录制态、削峰警告
    
    var radius: CGFloat {
        switch self {
        case .none: return 0
        case .subtle: return 4
        case .moderate: return 8
        case .intense: return 16
        }
    }
    
    var opacity: Double {
        switch self {
        case .none: return 0
        case .subtle: return 0.2
        case .moderate: return 0.3
        case .intense: return 0.6
        }
    }
}

// 使用示例：录制按钮发光
.shadow(
    color: Color(hex: "#FF3B30").opacity(IndustrialGlow.intense.opacity),
    radius: IndustrialGlow.intense.radius,
    x: 0,
    y: 0
)
```

### 渐变（Gradient）

**应用场景**：
1. 波形显示（录制态）
2. 电平表（绿-琥珀-红渐变）
3. 按钮背景（轻微金属质感）

```swift
// 金属渐变（面板背景）
let metalGradient = LinearGradient(
    colors: [
        Color(hex: "#1A1F29"),
        Color(hex: "#0F1419"),
        Color(hex: "#1A1F29")
    ],
    startPoint: .top,
    endPoint: .bottom
)

// 电平表渐变
let levelGradient = LinearGradient(
    colors: [
        Color(hex: "#EF4444"),   // 顶部红色
        Color(hex: "#F59E0B"),   // 中部琥珀色
        Color(hex: "#10B981")    // 底部绿色
    ],
    startPoint: .top,
    endPoint: .bottom
)

// 录制态波形渐变
let recordingWaveformGradient = LinearGradient(
    colors: [
        Color(hex: "#22D3EE"),
        Color(hex: "#10B981")
    ],
    startPoint: .leading,
    endPoint: .trailing
)
```

### 纹理（Texture）

**金属拉丝效果**：

```swift
// 方法 1：CALayer 自定义绘制
class BrushedMetalLayer: CALayer {
    override func draw(in ctx: CGContext) {
        let colors = [
            NSColor(hex: "#1A1F29").cgColor,
            NSColor(hex: "#0F1419").cgColor,
            NSColor(hex: "#1A1F29").cgColor
        ]
        let locations: [CGFloat] = [0.0, 0.5, 1.0]
        
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: locations
        )!
        
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: bounds.height),
            options: []
        )
        
        // 横向细纹
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.02).cgColor)
        ctx.setLineWidth(1)
        for y in stride(from: 0, to: bounds.height, by: 2) {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        ctx.strokePath()
    }
}

// 方法 2：NSVisualEffectView（macOS 原生毛玻璃）
let visualEffectView = NSVisualEffectView()
visualEffectView.material = .ultraDark
visualEffectView.blendingMode = .behindWindow
visualEffectView.state = .active
```

**网格纹理**：

```swift
// 背景网格（24px 间距）
struct GridBackground: View {
    let spacing: CGFloat = 24
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // 垂直线
                for x in stride(from: 0, to: geometry.size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
                
                // 水平线
                for y in stride(from: 0, to: geometry.size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.03), lineWidth: 1)
        }
    }
}

// 使用
ZStack {
    Color(hex: "#0A0C10")  // 主背景
    GridBackground()       // 网格覆盖层
    // 其他内容
}
```

---

## 6. 交互动效（Interaction & Animation）

### 动效时长与曲线

**原则**：短促有力，模拟硬件物理反馈

```swift
// 动效时长
enum AnimationDuration {
    static let instant: Double = 0.08      // 极快：按钮按下
    static let fast: Double = 0.12         // 快速：悬停态
    static let normal: Double = 0.15       // 标准：状态切换
    static let slow: Double = 0.25         // 较慢：面板展开
}

// 缓动曲线
enum AnimationCurve {
    static let snap = Animation.easeOut(duration: AnimationDuration.instant)
    static let quick = Animation.easeOut(duration: AnimationDuration.fast)
    static let standard = Animation.easeOut(duration: AnimationDuration.normal)
    static let smooth = Animation.easeInOut(duration: AnimationDuration.slow)
}
```

### 录制按钮点击动效

```swift
struct RecordButton: View {
    @Binding var isRecording: Bool
    @State private var isPressed = false
    
    var body: some View {
        Button(action: { isRecording.toggle() }) {
            // 按钮视觉（省略）
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
```

### 波形滚动动效

```swift
// 波形滚动（从右至左）
class WaveformScrollAnimator {
    func animate(layer: CALayer, duration: TimeInterval = 1.0) {
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = layer.position.x
        animation.toValue = layer.position.x - layer.bounds.width
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "scroll")
    }
}
```

### 电平表更新速度

**原则**：快速响应音频信号，但带轻微阻尼避免抖动

```swift
// 电平表平滑插值
class LevelMeterSmoothing {
    private var currentLevel: CGFloat = 0
    private let smoothingFactor: CGFloat = 0.3  // 0.0（无平滑）~ 1.0（极平滑）
    
    func update(targetLevel: CGFloat) -> CGFloat {
        currentLevel += (targetLevel - currentLevel) * (1 - smoothingFactor)
        return currentLevel
    }
}

// 使用示例
let smoother = LevelMeterSmoothing()
Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
    let rawLevel = audioEngine.getCurrentLevel()
    let smoothLevel = smoother.update(targetLevel: rawLevel)
    levelMeterView.update(level: smoothLevel)
}
```

### 页面过渡动画

```swift
// 视图切换（淡入淡出 + 轻微位移）
struct ViewTransition: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 10)
            .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

// 使用
Text("Hello")
    .modifier(ViewTransition(isActive: isVisible))
```

---

## 7. 适配 macOS 原生设计（macOS Native Adaptation）

### NSVisualEffectView 使用建议

**材质选择**：

```swift
// Sidebar 背景（毛玻璃效果）
let sidebarVisualEffect = NSVisualEffectView()
sidebarVisualEffect.material = .sidebar
sidebarVisualEffect.blendingMode = .behindWindow
sidebarVisualEffect.state = .active

// 控制面板背景（深色半透明）
let panelVisualEffect = NSVisualEffectView()
panelVisualEffect.material = .hudWindow
panelVisualEffect.blendingMode = .withinWindow
panelVisualEffect.state = .active
```

**注意事项**：
- `NSVisualEffectView` 会降低性能，仅在必要时使用（如 Sidebar）
- 波形视图等高频更新组件使用纯色背景
- 可选：通过 `wantsLayer = true` 启用图层加速

### NSColor / CGColor 映射

```swift
extension NSColor {
    // Hex 初始化器
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
    
    // 转换为 CGColor
    var cgColor: CGColor {
        return self.cgColor
    }
}

// 使用
let primaryColor = NSColor(hex: "#22D3EE")
layer.backgroundColor = primaryColor.cgColor
```

### CALayer 动画建议

```swift
// 录制按钮脉冲动画（CALayer 版本）
func addPulseAnimation(to layer: CALayer) {
    let animation = CABasicAnimation(keyPath: "shadowRadius")
    animation.fromValue = 8
    animation.toValue = 16
    animation.duration = 1.0
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "pulse")
}

// 波形闪烁警告（CALayer 版本）
func addClippingFlash(to layer: CALayer) {
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = 1.0
    animation.toValue = 0.3
    animation.duration = 0.15
    animation.autoreverses = true
    animation.repeatCount = 3
    animation.timingFunction = CAMediaTimingFunction(name: .linear)
    layer.add(animation, forKey: "clippingFlash")
}

// 停止动画
layer.removeAnimation(forKey: "pulse")
```

### 圆角半径（Corner Radius）系统

```swift
// 圆角规模
enum CornerRadius {
    static let none: CGFloat = 0
    static let sm: CGFloat = 3       // 小按钮、标签
    static let md: CGFloat = 4       // 次要按钮、输入框
    static let lg: CGFloat = 6       // 主按钮、面板
    static let xl: CGFloat = 8       // 卡片、模态框
    static let full: CGFloat = 9999  // 圆形按钮
}

// 使用
RoundedRectangle(cornerRadius: CornerRadius.md)
```

**建议**：
- 工业风格倾向**小圆角或硬边**（3-6pt）
- 录制按钮等图标按钮使用**圆形**（`cornerRadius: .full`）
- Sidebar、面板使用**硬边**（`cornerRadius: 0`）或极小圆角（2-3pt）

---

## 8. 完整 Prompt 模板（Full Prompt Template）

以下是可直接复制粘贴给 AI 编码助手（Claude、GPT-4、Cursor 等）的完整 Prompt：

---

### 📋 完整 Prompt 模板

```markdown
# 角色设定（Role）

你是一名精通 **macOS AppKit 开发**的 UI 设计师，擅长 **Industrial Design（工业设计）** 风格，正在为**专业音频录制工具 AudioRecordApp** 设计界面。

你的目标是将工业控制台的视觉语言应用到音频录制器中，让用户感到这是一款**可靠的工作室级工具**，适合长时间音频制作。

---

## 设计风格（Industrial Design Style）

### 核心特征
- **深色基调**：炭黑/铁灰背景，模拟工作室监听环境
- **冷色高光**：青色（`#22D3EE`）、天蓝色（`#38BDF8`）作为主交互色
- **工业警示色**：绿色（正常）、琥珀色（警告）、红色（削峰/错误）
- **金属质感**：拉丝金属渐变、微网格纹理、清晰边框
- **粗体大写**：标题全大写 + 增加字距（0.8-1.5pt），强化工程感
- **等宽字体**：时间码、电平数值使用 SF Mono
- **短促动效**：100-150ms 过渡，easeOut 曲线，无弹跳

### 设计原则
1. **功能性优先**：每个视觉元素都有功能意义
2. **高信息密度 + 清晰可读**：充足间距，避免拥挤
3. **直接明确的反馈**：录制态红色发光，电平表实时响应
4. **硬朗质感**：短而锐利的阴影，避免柔和漂浮感
5. **可扩展性**：组件设计可复用，遵循 Apple HIG

---

## 配色方案（Color Palette）

### 背景色
```swift
// 深色基底
static let baseBlack = NSColor(hex: "#0A0C10")     // 主背景
static let baseDark = NSColor(hex: "#0F1419")      // Sidebar、面板
static let basePanel = NSColor(hex: "#1A1F29")     // 卡片、悬停
static let baseBorder = NSColor(hex: "#2D3748")    // 边框
```

### 文本色
```swift
static let textPrimary = NSColor(hex: "#E2E8F0")    // 主文本
static let textSecondary = NSColor(hex: "#CBD5E0")  // 次要文本
static let textTertiary = NSColor(hex: "#A0AEC0")   // 三级文本
static let textMono = NSColor(hex: "#F7FAFC")       // 等宽字体
```

### 主色调（冷色调科技感）
```swift
// 青色 - 主交互色
static let cyanPrimary = NSColor(hex: "#22D3EE")
static let cyanLight = NSColor(hex: "#06B6D4")

// 天蓝色 - 次要操作
static let bluePrimary = NSColor(hex: "#38BDF8")
```

### 功能色（音频专业语义）
```swift
// 电平指示
static let successGreen = NSColor(hex: "#10B981")   // -18dB ~ -6dB
static let warningAmber = NSColor(hex: "#F59E0B")   // -6dB ~ -3dB
static let dangerRed = NSColor(hex: "#EF4444")      // > -3dB（削峰）

// 录制状态
static let recordingRed = NSColor(hex: "#FF3B30")   // 录制激活态
```

---

## 组件设计（Component Design）

### 1. Sidebar（侧边栏）
- **尺寸**：240pt 宽
- **背景**：`#0F1419`，右侧 1pt 边框 `#2D3748`
- **音频源列表项**：
  - 默认：背景透明，文本 `#CBD5E0`
  - 悬停：背景 `#1A1F29`，文本 `#E2E8F0`
  - 选中：背景 `#22D3EE` (10% opacity)，左边框 2pt `#22D3EE`，文本 `#22D3EE`
- **文件列表项**：12pt 字号，显示文件名 + 时长 + 大小

### 2. WaveformView（波形视图）
- **背景网格**：24pt 间距，`rgba(255,255,255,0.04)` 颜色
- **波形颜色**：
  - 空闲态：`#22D3EE` (50% opacity)
  - 录制态：`#22D3EE` → `#10B981` 渐变
  - 削峰警告：`#EF4444` 闪烁（0.2s 持续 3 次）
- **电平表**：
  - 垂直条形图，8pt 宽，2pt 圆角
  - 渐变：底部绿色 → 中部琥珀色 → 顶部红色
  - 实时更新（60fps），带平滑插值（smoothingFactor: 0.3）
  - 发光效果：对应电平颜色，半径 4pt

### 3. ControlPanelView（控制面板）
- **录制按钮**：
  - 空闲态：外圈 `#2D3748`，内圈 `#22D3EE`，直径 64pt，青色轻微光晕
  - 录制态：外圈 `#FF3B30`，内圈 `#FF3B30`，红色脉冲光晕（8-16pt 循环）
  - 悬停：亮度增加 5%
  - 按下：缩放至 0.95，持续 0.08s
- **计时器**：
  - 字体：SF Mono Bold 28pt
  - 格式：`00:00.00`（分:秒.百分秒）
  - 背景：金属渐变（`#1A1F29` → `#0F1419` → `#1A1F29`）
  - 边框：1pt `#2D3748`，6pt 圆角
  - 阴影：`rgba(0,0,0,0.3)` 半径 4pt

### 4. TracksView（轨道视图）
- **轨道项**：
  - 布局：轨道编号（24x24pt 方块）+ 名称 + 电平表 + 静音/独奏按钮
  - 背景：`#0F1419`
  - 底部边框：1pt `#2D3748`
- **轨道编号**：等宽字体 11pt，居中，背景 `#1A1F29`，边框 `#2D3748`
- **轨道名称**：全大写 11pt Bold，字距 0.8pt
- **电平表**：迷你版（20pt 宽，32pt 高）
- **控制按钮**：20x20pt，激活时背景 `#22D3EE` (15% opacity)，文本 `#22D3EE`

### 5. StatusBarView（状态栏）
- **布局**：音频接口 + 采样率 + 位深度 + CPU 占用率
- **分隔符**：1pt `#2D3748` 竖线，16pt 高
- **标签**：9pt Bold，全大写，`#A0AEC0`
- **数值**：11pt Mono Bold，`#E2E8F0`
- **CPU 占用率**：
  - 正常（< 60%）：绿色
  - 警告（60-80%）：琥珀色
  - 危险（> 80%）：红色

---

## 交互动效（Animation）

### 动效时长
```swift
enum AnimationDuration {
    static let instant: Double = 0.08      // 按钮按下
    static let fast: Double = 0.12         // 悬停态
    static let normal: Double = 0.15       // 状态切换
    static let slow: Double = 0.25         // 面板展开
}
```

### 缓动曲线
- **easeOut**：所有标准过渡（颜色、位置、缩放）
- **linear**：波形滚动、电平表更新
- **easeInOut**：录制按钮脉冲、长时间动画

### 关键动效
1. **录制按钮点击**：
   - 按下：缩放至 0.95（0.08s easeOut）
   - 状态切换：颜色过渡（0.15s easeOut）
   - 录制态：红色光晕脉冲（1.0s easeInOut 无限循环）

2. **波形滚动**：
   - 方向：从右至左
   - 速度：线性匀速
   - 持续：录制期间持续

3. **电平表更新**：
   - 频率：60fps
   - 平滑插值：smoothingFactor 0.3（避免抖动）
   - 高电平闪烁：当 > -3dB 时，红色区域闪烁（0.2s 间隔）

4. **削峰警告**：
   - 波形颜色切换为红色
   - 闪烁 3 次（0.15s 持续，0.3-1.0 透明度）
   - 同时在状态栏显示文字警告

---

## 代码实现建议（Implementation）

### 1. Hex 颜色扩展
```swift
extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
```

### 2. 录制按钮（SwiftUI）
```swift
struct RecordButton: View {
    @Binding var isRecording: Bool
    @State private var pulseAnimation = false
    
    var body: some View {
        Button(action: { isRecording.toggle() }) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isRecording ? Color(hex: "#FF3B30") : Color(hex: "#2D3748"),
                        lineWidth: 3
                    )
                    .frame(width: 64, height: 64)
                    .shadow(
                        color: isRecording ? Color(hex: "#FF3B30").opacity(pulseAnimation ? 0.6 : 0.3) : Color.clear,
                        radius: pulseAnimation ? 16 : 8
                    )
                
                Circle()
                    .fill(isRecording ? Color(hex: "#FF3B30") : Color(hex: "#22D3EE"))
                    .frame(width: 48, height: 48)
                
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isRecording ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isRecording)
        .onAppear {
            if isRecording {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
    }
}
```

### 3. 电平表（SwiftUI）
```swift
struct LevelMeter: View {
    let level: CGFloat  // 0.0 ~ 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#1A1F29"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color(hex: "#2D3748"), lineWidth: 1)
                    )
                
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#EF4444"),
                        Color(hex: "#F59E0B"),
                        Color(hex: "#10B981")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask(
                    RoundedRectangle(cornerRadius: 2)
                        .frame(height: geometry.size.height * level)
                )
                .shadow(
                    color: level > 0.85 ? Color(hex: "#EF4444").opacity(0.5) : Color.clear,
                    radius: 4
                )
            }
        }
    }
}
```

### 4. 波形网格背景（AppKit）
```swift
class WaveformBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 背景色
        NSColor(hex: "#0A0C10").setFill()
        context.fill(bounds)
        
        // 网格线
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.04).cgColor)
        context.setLineWidth(1)
        
        let spacing: CGFloat = 24
        
        // 垂直线
        for x in stride(from: 0, to: bounds.width, by: spacing) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))
        }
        
        // 水平线
        for y in stride(from: 0, to: bounds.height, by: spacing) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        
        context.strokePath()
    }
}
```

### 5. 电平表平滑插值
```swift
class LevelMeterSmoothing {
    private var currentLevel: CGFloat = 0
    private let smoothingFactor: CGFloat = 0.3
    
    func update(targetLevel: CGFloat) -> CGFloat {
        currentLevel += (targetLevel - currentLevel) * (1 - smoothingFactor)
        return currentLevel
    }
}

// 使用示例
let smoother = LevelMeterSmoothing()
Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
    let rawLevel = audioEngine.getCurrentLevel()
    let smoothLevel = smoother.update(targetLevel: rawLevel)
    levelMeterView.update(level: smoothLevel)
}
```

---

## 特殊需求

### 音频语义映射
- **电平范围 → 颜色**：
  - -18 dB ~ -6 dB：绿色（安全）
  - -6 dB ~ -3 dB：琥珀色（接近峰值）
  - > -3 dB：红色（削峰危险）

### 削峰警告流程
1. 音频引擎检测到 > -3 dB 峰值
2. 波形颜色立即切换为红色
3. 闪烁 3 次（0.15s 持续，0.3-1.0 透明度）
4. 状态栏显示 "⚠️ CLIPPING DETECTED"
5. 电平表红色区域持续发光，直到电平降低

### 长时间使用优化
- 所有颜色使用深色基调，减少眼睛疲劳
- 录制按钮脉冲动画频率低（1.0s 周期），避免视觉干扰
- 波形滚动速度适中，易于观察
- 状态栏信息密度适中，无冗余元素

---

## 参考资源
- 风格参考：Industrial Design（工业设计风格）
- 平台：macOS（AppKit + Swift）
- 字体：SF Pro、SF Mono
- 圆角系统：3-6pt（小圆角或硬边）
- 阴影系统：短而锐利（2-6pt 偏移，0.35-0.55 透明度）
- 动效时长：0.08-0.25s（easeOut 曲线）

---

## 最终检查清单
- [ ] 所有颜色使用 Hex 值定义
- [ ] 标题全大写 + 增加字距
- [ ] 时间码、电平数值使用等宽字体
- [ ] 录制按钮有明确的空闲/录制态区分
- [ ] 电平表使用渐变色 + 高电平警示
- [ ] 削峰警告有视觉闪烁 + 文字提示
- [ ] 所有动效时长 < 0.25s（除长时间动画）
- [ ] 阴影短而锐利，无柔和漂浮感
- [ ] 背景使用网格纹理（可选）
- [ ] 遵循 Apple HIG，保持工业风格特征
```

---

## 交接块（Handoff Block）

我已完成 **AudioRecordApp Industrial Design 风格 UI Prompt** 的生成。以下是交付物概览：

### ✅ 已完成内容

1. **设计理念（Design Philosophy）**  
   - 明确了为什么选择 Industrial Design：专业可靠性、长时间使用舒适性、清晰的功能分区、硬件感
   - 提炼了 5 条核心设计原则：工作室级专业感、高信息密度 + 清晰可读、直接明确的反馈、功能性优先、可扩展性

2. **配色方案（Color Palette）**  
   - 完整的 Hex 色卡（背景、文本、主色调、功能色、网格/纹理）
   - 音频语义映射（电平范围 → 颜色：绿色正常、琥珀色警告、红色削峰）
   - 速查表格式，方便查阅

3. **字体排版（Typography）**  
   - 推荐 SF Pro（主字体）+ SF Mono（等宽字体）
   - 字号系统（10-28pt）
   - 工业风格特征：标题全大写 + 增加字距
   - 代码示例（NSFont 扩展、NSAttributedString 工具）

4. **组件设计规范（Component Specifications）**  
   逐个组件生成详细设计规范，包括：
   - **Sidebar**：尺寸、背景材质、交互状态（默认/悬停/选中/禁用）、音频源列表、文件列表
   - **WaveformView**：背景网格、波形颜色（空闲/录制/削峰）、电平表（渐变色、刻度标签、发光效果）
   - **ControlPanelView**：录制按钮（空闲/录制/悬停/按下状态）、计时器（等宽字体、金属背景）
   - **TracksView**：轨道列表项布局、轨道编号、名称、迷你电平表、静音/独奏按钮
   - **StatusBarView**：音频接口、采样率、位深度、CPU 占用率

5. **视觉特效（Visual Effects）**  
   - **阴影系统**：3 级（sm/md/lg），短而锐利
   - **发光效果**：3 级（subtle/moderate/intense），应用于录制按钮、高电平警告、悬停态
   - **渐变**：金属渐变、电平表渐变、波形渐变
   - **纹理**：金属拉丝（CALayer 自定义绘制）、网格纹理（24px 间距）、NSVisualEffectView 使用建议

6. **交互动效（Interaction & Animation）**  
   - 动效时长系统（0.08-0.25s）
   - 缓动曲线（easeOut、linear、easeInOut）
   - 录制按钮点击动效（缩放、脉冲光晕）
   - 波形滚动动效（从右至左）
   - 电平表平滑插值（避免抖动）
   - 削峰警告流程（闪烁 3 次 + 状态栏文字）

7. **适配 macOS 原生设计（macOS Native Adaptation）**  
   - NSVisualEffectView 材质选择（sidebar、hudWindow）
   - NSColor / CGColor 映射（Hex 初始化器）
   - CALayer 动画建议（脉冲、闪烁）
   - 圆角半径系统（3-8pt，工业风格偏小圆角或硬边）

8. **完整 Prompt 模板（Full Prompt Template）**  
   生成了一份 **可直接复制粘贴给 AI 编码助手** 的完整 Prompt，包含：
   - 角色设定
   - 设计风格（核心特征 + 设计原则）
   - 配色方案（完整 Hex 值 + Swift 代码）
   - 组件设计（5 个核心组件的详细规范）
   - 交互动效（时长、曲线、关键动效）
   - 代码实现建议（5 个 Swift 代码片段）
   - 特殊需求（音频语义映射、削峰警告流程、长时间使用优化）
   - 参考资源 + 最终检查清单

### 📂 文件位置

完整文档已保存至：  
`/Users/voidzhang/Documents/workspace/weiyige-pavilion/artifacts/AudioRecordApp_Industrial_Design_UI_Prompt.md`

### 🎯 使用方式

1. **快速上手**：直接阅读「完整 Prompt 模板」章节，复制粘贴给 AI 编码助手（Claude、GPT-4、Cursor 等）
2. **深度定制**：参考前 7 章的详细规范，逐个组件调整设计
3. **代码实现**：使用提供的 Swift 代码片段快速搭建原型
4. **视觉调优**：基于「配色方案」和「视觉特效」章节微调颜色、阴影、发光效果

### 🔍 核心设计亮点

1. **音频专业语义**：电平表渐变色（绿-琥珀-红）直观映射音频电平范围
2. **硬件感**：录制按钮模拟物理录音机的红色指示灯 + 脉冲光晕
3. **长时间使用优化**：深色基调 + 克制的动效频率，适合工作室环境
4. **清晰的视觉层级**：工业风格的网格、边框、阴影明确区分各组件
5. **直接明确的反馈**：削峰警告闪烁 3 次 + 状态栏文字提示

### 📊 设计规范覆盖率

| 维度 | 完成度 | 备注 |
|------|--------|------|
| 设计理念 | ✅ 100% | 5 条核心原则 |
| 配色方案 | ✅ 100% | 完整 Hex 值 + 音频语义映射 |
| 字体排版 | ✅ 100% | SF Pro + SF Mono + 字号系统 |
| 组件设计 | ✅ 100% | 5 个核心组件详细规范 |
| 视觉特效 | ✅ 100% | 阴影/发光/渐变/纹理 |
| 交互动效 | ✅ 100% | 时长系统 + 关键动效 |
| macOS 适配 | ✅ 100% | NSVisualEffectView + CALayer |
| Prompt 模板 | ✅ 100% | 可直接使用的完整模板 |

### 🚀 后续建议

1. **原型验证**：基于 Prompt 模板快速生成 SwiftUI 原型，测试视觉效果
2. **用户测试**：邀请音频工程师测试界面，重点验证电平表可读性、削峰警告及时性
3. **性能优化**：波形视图和电平表高频更新，需测试 CPU 占用率，必要时降低更新频率
4. **浅色模式**（可选）：当前规范专注深色主题，如需浅色模式可基于当前配色方案反转
5. **辅助功能**：考虑色盲用户，可在电平表旁增加数值标签（-12.3 dB）

---

**任务完成！** 🎉

所有章节已按要求生成，Prompt 模板已可直接用于 AI 编码助手。如有需要调整的细节，请基于生成的文档进行增量修改。
