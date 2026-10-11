# macOS 原生音频录制与播放器 (AudioRecord Pro) - Swift/SwiftUI 架构与交互实现规范

> 本文档用于直接交付给 AI Agent、Cursor / Claude Code 或 iOS/macOS 客户端工程师，指导如何使用 **Swift + SwiftUI + AppKit + CoreAudio / AVFoundation** 完整实现此界面的视觉质感、底层逻辑与交互效果。

---

## 一、 产品概述与界面设计规范

### 1.1 视觉风格定位
- **平台规范**：macOS 14+ (Sonoma / Sequoia) 原生设计规范。
- **背景材质**：窗口采用暗黑毛玻璃（`NSVisualEffectView`，材质推荐 `.hudWindow` 或 `.underWindowBackground`，暗黑模式固定 `dark` appearance）。
- **色彩体系**：
  - **主背景 (Background)**：`#0F1115`（深碳黑，叠加轻微径向渐变或高斯模糊）。
  - **边框与分割线 (Borders)**：`rgba(255, 255, 255, 0.08)` 1px hairline。
  - **强调主色 (Accent Green)**：`#10B981` (Emerald) 到 `#00F5A0` (Neon Mint)，带发光阴影效果（Glow: `color.opacity(0.4)`, radius: 8）。
  - **录制警告色 (Record Red)**：`#EF4444` / `#FF3B30`，待机与录制中带微呼吸光晕。
  - **次级文本与未激活波形**：`rgba(255, 255, 255, 0.35)`。

### 1.2 布局架构 (Layout Architecture)
整体窗口采用标准 **macOS 三栏 / 双栏结构**：
1. **Window Toolbar / Titlebar**：
   - 左侧：标准交通灯按键（Red, Yellow, Green）。
   - 居中：当前应用标题或当前录制/播放源状态（Capsule Pill 标签，如 `● 企业微信 • 00:14.32 (Active Playback)`）。
   - 右侧：导出操作按钮（`Export`）。
2. **左侧边栏 (Sidebar - 宽度 260px)**：
   - 顶部：Segmented 切换器（`[Record] [Files]`）。
   - 系统音频源列表（`Record All System Audio`）。
   - 应用级音频捕获列表（`App Audio`，展示各个运行中 App 图标、名称、选定高亮态）。
   - 底部：麦克风混音选项开关（`Also Record Microphone` Toggle）。
3. **主舞台 (Main Stage / Canvas)**：
   - **顶部信息条**：当前音频流元数据（`CH 1/2 STEREO`, 文件名, 采样率 `48 kHz`, 缩放倍率 `Zoom: 100%`, 选区范围）。
   - **中央示波器区域 (Waveform Canvas)**：网格背景、时间刻度尺（Ruler）、音频波形（已播放发光绿 vs 未播放灰阶）、高亮时间选区框（Selection Overlay）、垂直播放光标（Playhead 带时间悬浮标签）。
   - **右侧电平表 (VU Meter - 宽度 40px)**：双通道（L / R）立体声跳动表，-48 dBFS 到 0 dBFS 渐变刻度。
4. **底部控制栏 (Bottom Playback / Record Bar - 高度 72px)**：
   - **绝对几何居中（Dead Center）**：主操作大圆按键（录制红圆 48x48 / 播放翠绿圆 48x48，带 `shadow` 光晕）。
   - **左侧停靠**：时间码显示器（高对比等宽数字字体，如 `00:14.32 / 01:45.00`），状态指示器（`Ready` / `Playing` / `Recording`）。
   - **右侧停靠**：快进/快退按键、循环模式（`Loop`）、监听音量滑块（Volume Slider）。

---

## 二、 技术选型与依赖库建议

| 模块 | 推荐技术方案 | 作用说明 |
| :--- | :--- | :--- |
| **UI 视图框架** | **SwiftUI** (macOS 13+) | 声明式构建界面、组件状态绑定、动画 |
| **原生窗口与毛玻璃** | **AppKit** (`NSVisualEffectView`) | 实现沉浸式 macOS 原生暗黑毛玻璃背景 |
| **系统/应用音频捕获** | **ScreenCaptureKit** (`SCStream`) 或 **CoreAudio HAL** (AudioServerPlugIn) | macOS 13+ 官方推荐用 `ScreenCaptureKit` 抓取单个 App 或系统音频 |
| **音频录制与回放** | **AVAudioEngine** (`AVFoundation`) | 负责多声道混音、音频流录制至 FLAC/WAV、音频实时播放 |
| **波形数据提取与缓存** | **Accelerate (vDSP)** | 快速傅里叶变换(FFT)或音频 RMS/Peak 降采样计算波形图顶点 |
| **波形与电平表渲染** | **SwiftUI `Canvas`** 或 **MetalKit (`MTKView`)** | 保证 60fps 丝滑渲染高精度实时示波器与跳动电平表 |

---

## 三、 核心模块实现指导 (供 Agent 实现的代码参考)

### 3.1 窗口与毛玻璃效果 (Window Chrome)
```swift
import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
```

### 3.2 底部控制栏严格几何居中 (Bottom Bar Layout)
为了确保中央录音/播放圆钮在任何窗口拉伸缩放下保持 **绝对物理正中心**：
```swift
struct BottomControlBar: View {
    @ObservedObject var audioVM: AudioPlayerViewModel
    
    var body: some View {
        ZStack {
            // 1. 底层绝对正中心的主控制按钮
            HStack {
                Spacer()
                Button(action: { audioVM.togglePlayPause() }) {
                    Circle()
                        .fill(Color(hex: "#10B981"))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: audioVM.isPlaying ? "pause.fill" : "play.fill")
                                .foregroundColor(.black)
                                .font(.system(size: 20, weight: .bold))
                        )
                        .shadow(color: Color(hex: "#10B981").opacity(0.4), radius: 10)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            
            // 2. 左右两侧的内容通过左右对齐排布，互不挤压
            HStack {
                // 左侧：状态呼吸灯 + 时间码
                HStack(spacing: 12) {
                    Circle()
                        .fill(audioVM.isPlaying ? Color(hex: "#10B981") : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(audioVM.formattedCurrentTime)
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    Text("/ \(audioVM.formattedTotalTime)")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                // 右侧：快进退、Loop 与音量
                HStack(spacing: 16) {
                    Button(action: {}) { Image(systemName: "backward.frame.fill") }
                    Button(action: {}) { Image(systemName: "forward.frame.fill") }
                    Button(action: { audioVM.isLooping.toggle() }) {
                        Label("Loop", systemImage: "repeat")
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(audioVM.isLooping ? Color.white.opacity(0.15) : Color.clear)
                            .cornerRadius(6)
                    }
                    Slider(value: $audioVM.volume, in: 0...1)
                        .frame(width: 80)
                }
                .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 72)
        .background(Color(hex: "#13161C").opacity(0.95))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.06)), alignment: .top)
    }
}
```

### 3.3 波形示波器渲染 (Waveform Canvas + Selection)
```swift
struct WaveformView: View {
    let samples: [Float] // 降采样后的峰值数组 [0.0 ... 1.0]
    let progress: Double // 播放进度 0.0 ... 1.0
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 网格背景
                GridBackground()
                
                // 音频条形波形绘制
                Canvas { context, size in
                    let barWidth: CGFloat = 4
                    let barGap: CGFloat = 4
                    let totalBars = Int(size.width / (barWidth + barGap))
                    let midY = size.height / 2
                    
                    for i in 0..<min(samples.count, totalBars) {
                        let x = CGFloat(i) * (barWidth + barGap)
                        let barHeight = CGFloat(samples[i]) * (size.height * 0.7)
                        let rect = CGRect(x: x, y: midY - barHeight / 2, width: barWidth, height: max(barHeight, 4))
                        
                        // 已播放部分翡翠绿发光，未播放部分深灰色
                        let isPlayed = (x / size.width) <= progress
                        let barColor = isPlayed ? Color(hex: "#10B981") : Color.white.opacity(0.2)
                        
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(barColor))
                    }
                }
                
                // 播放头指针 (Playhead)
                Rectangle()
                    .fill(Color(hex: "#10B981"))
                    .frame(width: 2)
                    .shadow(color: Color(hex: "#10B981").opacity(0.8), radius: 6)
                    .offset(x: geo.size.width * progress)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newProgress = max(0, min(1, value.location.x / geo.size.width))
                        onSeek(newProgress)
                    }
            )
        }
    }
}
```

---

## 四、 给 AI Agent 的实施任务分解指令 (Prompt Template)

可以直接将以下 Prompt 复制并输入给 Cursor、Windsurf 或 Claude Code：

```markdown
### 任务目标
请在我的 macOS SwiftUI 项目中实现一个高保真音频录制与播放器应用界面（参考设计规范 AudioRecord Pro）。

### 核心功能需求
1. **界面结构**：
   - 使用 NavigationSplitView 构建左侧固定 260px 边栏与右侧示波器主舞台。
   - 整体背景使用 NSVisualEffectView 呈现深色毛玻璃 (.hudWindow)。
2. **底部控制栏**：
   - 底部使用 ZStack 布局，确保主操作按钮（录音/播放大圆）严格处于主窗口的水平正几何中心。
   - 左侧展示等宽时间码与状态灯，右侧展示快捷控制与音量滑块。
3. **示波器与交互**：
   - 使用 SwiftUI `Canvas` 绘制带有圆角的波形柱状图。
   - 实现点击/拖动波形任意位置进行跳转（Seek）的交互手势。
   - 渲染高亮发光的垂直播放指针（Playhead）。
4. **右侧立体声 VU 电平表**：
   - 包含 L / R 双通道电平跳动条，支持从 -48 dBFS 到 0 dBFS 的绿黄红渐变。
```
