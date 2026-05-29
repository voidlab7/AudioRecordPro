import Cocoa

// MARK: - Industrial Design Tokens
// 基于 Stitch Desktop Application Project 的 Industrial Design 风格

/// 颜色系统
struct IndustrialColors {
    
    // MARK: - 背景色（Surface）
    
    /// 主背景色 - 最深黑
    static let surface = NSColor(hex: "#0e1416")
    
    /// 暗色背景
    static let surfaceDim = NSColor(hex: "#0e1416")
    
    /// 亮色背景
    static let surfaceBright = NSColor(hex: "#343a3c")
    
    /// 容器背景 - 最低层
    static let surfaceContainerLowest = NSColor(hex: "#090f11")
    
    /// 容器背景 - 低层（WaveformView、TracksView）
    static let surfaceContainerLow = NSColor(hex: "#161d1e")
    
    /// 容器背景 - 标准（Sidebar、TracksView 轨道项）
    static let surfaceContainer = NSColor(hex: "#1a2122")
    
    /// 容器背景 - 高层（hover 状态）
    static let surfaceContainerHigh = NSColor(hex: "#242b2d")
    
    /// 容器背景 - 最高层（选中状态）
    static let surfaceContainerHighest = NSColor(hex: "#2f3638")
    
    // MARK: - 文字色（On-Surface）
    
    /// 主文字色 - 亮灰
    static let onSurface = NSColor(hex: "#dde4e5")
    
    /// 次要文字色 - 浅灰
    static let onSurfaceVariant = NSColor(hex: "#bbc9cd")
    
    /// 文字三级色（禁用）
    static let textTertiary = NSColor(hex: "#9CA3AF")
    
    /// 反转背景色（深色主题用）
    static let inverseSurface = NSColor(hex: "#dde4e5")
    
    /// 反转文字色（深色主题用）
    static let inverseOnSurface = NSColor(hex: "#2b3233")
    
    // MARK: - 边框与分割线（Outline）
    
    /// 主边框色
    static let outline = NSColor(hex: "#859397")
    
    /// 次要边框色（组件边框、Sidebar 右侧边框）
    static let outlineVariant = NSColor(hex: "#3c494c")
    
    // MARK: - 主色调（Primary）
    
    /// 主色 - 青色（电平表、计时器、链接）
    static let primary = NSColor(hex: "#8aebff")
    
    /// 主色容器 - 深青色（波形、电平表正常态）
    static let primaryContainer = NSColor(hex: "#22d3ee")
    
    /// 主色上的文字
    static let onPrimary = NSColor(hex: "#00363e")
    
    /// 主色容器上的文字
    static let onPrimaryContainer = NSColor(hex: "#005763")
    
    /// 反转主色
    static let inversePrimary = NSColor(hex: "#006877")
    
    /// 主色固定色（浅色主题用）
    static let primaryFixed = NSColor(hex: "#a2eeff")
    
    /// 主色固定色（暗色）
    static let primaryFixedDim = NSColor(hex: "#2fd9f4")
    
    /// 主色固定色上的文字
    static let onPrimaryFixed = NSColor(hex: "#001f25")
    
    /// 主色固定色上的文字（变体）
    static let onPrimaryFixedVariant = NSColor(hex: "#004e5a")
    
    // MARK: - 次要色（Secondary）
    
    /// 次要色 - 天蓝色
    static let secondary = NSColor(hex: "#7bd0ff")
    
    /// 次要色容器 - 深蓝色（波形渐变下半部分）
    static let secondaryContainer = NSColor(hex: "#00a6e0")
    
    /// 次要色上的文字
    static let onSecondary = NSColor(hex: "#00354a")
    
    /// 次要色容器上的文字
    static let onSecondaryContainer = NSColor(hex: "#00374d")
    
    /// 次要色固定色（浅色主题用）
    static let secondaryFixed = NSColor(hex: "#c4e7ff")
    
    /// 次要色固定色（暗色）
    static let secondaryFixedDim = NSColor(hex: "#7bd0ff")
    
    /// 次要色固定色上的文字
    static let onSecondaryFixed = NSColor(hex: "#001e2c")
    
    /// 次要色固定色上的文字（变体）
    static let onSecondaryFixedVariant = NSColor(hex: "#004c69")
    
    // MARK: - 第三色（Tertiary）
    
    /// 第三色 - 琥珀色（警告、注意）
    static let tertiary = NSColor(hex: "#ffd6a3")
    
    /// 第三色容器 - 深琥珀色
    static let tertiaryContainer = NSColor(hex: "#ffb13b")
    
    /// 第三色上的文字
    static let onTertiary = NSColor(hex: "#462b00")
    
    /// 第三色容器上的文字
    static let onTertiaryContainer = NSColor(hex: "#6e4600")
    
    /// 第三色固定色（浅色主题用）
    static let tertiaryFixed = NSColor(hex: "#ffddb5")
    
    /// 第三色固定色（暗色）
    static let tertiaryFixedDim = NSColor(hex: "#ffb957")
    
    /// 第三色固定色上的文字
    static let onTertiaryFixed = NSColor(hex: "#2a1800")
    
    /// 第三色固定色上的文字（变体）
    static let onTertiaryFixedVariant = NSColor(hex: "#643f00")
    
    // MARK: - 错误色（Error）
    
    /// 错误色 - 红色（过载 > 90%）
    static let error = NSColor(hex: "#ffb4ab")
    
    /// 错误容器色 - 深红色
    static let errorContainer = NSColor(hex: "#93000a")
    
    /// 错误色上的文字
    static let onError = NSColor(hex: "#690005")
    
    /// 错误容器上的文字
    static let onErrorContainer = NSColor(hex: "#ffdad6")
    
    // MARK: - 工业警示色（Status）
    
    /// 成功状态 - 绿色（正常运行）
    static let statusSuccess = NSColor(hex: "#22C55E")
    
    /// 警告状态 - 琥珀色（高电平 70-90%）
    static let statusWarning = NSColor(hex: "#F59E0B")
    
    /// 危险状态 - 红色（过载 > 90%）
    static let statusDanger = NSColor(hex: "#EF4444")
    
    /// 严重状态 - 深红色（录制按钮空闲态）
    static let statusCritical = NSColor(hex: "#DC2626")
    
    // MARK: - 辅助颜色（Legacy）
    
    /// 基础背景 1（与 surface 相同）
    static let base1 = NSColor(hex: "#0B0D11")
    
    /// 基础背景 2（与 surfaceContainer 相似）
    static let base2 = NSColor(hex: "#111827")
    
    /// 基础背景 3（与 surfaceContainerLow 相似）
    static let base3 = NSColor(hex: "#1F2937")
    
    /// 边框色（与 outlineVariant 相似）
    static let borderMuted = NSColor(hex: "#374151")
    
    /// 主文字色（与 onSurface 相同）
    static let textPrimary = NSColor(hex: "#E5E7EB")
    
    /// 次要文字色
    static let textSecondary = NSColor(hex: "#D1D5DB")
    
    /// 青色暗色（hover 状态）
    static let cyanDim = NSColor(hex: "#06B6D4")
    
    /// 蓝色暗色（hover 状态）
    static let blueDim = NSColor(hex: "#0EA5E9")
    
    // MARK: - 原生录音波形色（Apple Native Recording）
    
    /// 原生录音红 - 播放头/录制焦点
    static let waveformAccent = NSColor(hex: "#FF453A")
    
    /// 原生录音珊瑚红 - 主波形
    static let waveformCoral = NSColor(hex: "#FF6B5F")
    
    /// 原生录音柔红 - 次级波形/弱电平
    static let waveformSoft = NSColor(hex: "#FF8A80")
    
    /// 原生录音弱底色 - 波形静音段
    static let waveformMuted = NSColor(hex: "#FF6B5F", alpha: 0.32)
    
    // MARK: - 网格与纹理（Grid & Texture）
    
    /// 极淡网格线（背景网格）
    static let gridLight = NSColor(white: 1.0, alpha: 0.03)
    
    /// 淡网格线（分区网格）
    static let gridMedium = NSColor(white: 1.0, alpha: 0.06)
    
    /// 明显网格线（强调网格）
    static let gridHeavy = NSColor(white: 1.0, alpha: 0.12)
    
    // MARK: - 发光效果（Glow）
    
    /// 青色发光（录制按钮、电平表）
    static let glowCyan = NSColor(hex: "#22D3EE", alpha: 0.25)
    
    /// 琥珀色发光（警告状态）
    static let glowWarning = NSColor(hex: "#F59E0B", alpha: 0.3)
    
    /// 红色发光（过载状态）
    static let glowDanger = NSColor(hex: "#EF4444", alpha: 0.35)
    
    // MARK: - 阴影颜色（Shadow）
    
    /// 短而锐利的阴影（工业感）
    static let shadowColor = NSColor(white: 0.0, alpha: 0.45)
    
    // MARK: - 编辑器专用色（Editor）
    
    /// 选区拖柄色
    static let editorHandle = IndustrialColors.primary  // #8AEBFF
    
    /// 选区外遮罩
    static let editorDimOverlay = NSColor(hex: "#0E1416", alpha: 0.4)
    
    /// 静音段背景
    static let editorSilenceOverlay = NSColor(hex: "#242B2D", alpha: 0.6)
    
    /// 静音段删除标记线
    static let editorSilenceLine = IndustrialColors.error  // #FFB4AB
    
    /// 编辑中状态徽章色（琥珀）
    static let editorEditingBadge = IndustrialColors.tertiary  // #FFD6A3
}

// MARK: - 字体排版
struct IndustrialTypography {
    
    /// H1 标题 - 18px Bold（大写）
    static let h1 = NSFont.systemFont(ofSize: 18, weight: .bold)
    
    /// H2 标题 - 14px Bold（大写）
    static let h2 = NSFont.systemFont(ofSize: 14, weight: .bold)
    
    /// 正文 - 13px Regular
    static let body = NSFont.systemFont(ofSize: 13, weight: .regular)
    
    /// 小文本 - 12px Regular
    static let small = NSFont.systemFont(ofSize: 12, weight: .regular)
    
    /// 标签 - 11px Semibold
    static let label = NSFont.systemFont(ofSize: 11, weight: .semibold)
    
    /// 计时器 - 28px Bold 等宽
    static let timer = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
    
    /// dB 数值 - 10px Regular 等宽
    static let monoDB = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
}

// MARK: - 间距系统
struct IndustrialSpacing {
    
    /// 基础单位 - 4px
    static let unit: CGFloat = 4
    
    /// 极小间距 - 4px
    static let xs: CGFloat = 4
    
    /// 小间距 - 8px
    static let sm: CGFloat = 8
    
    /// 中间距 - 16px
    static let md: CGFloat = 16
    
    /// 大间距 - 24px
    static let lg: CGFloat = 24
    
    /// 超大间距 - 32px
    static let xl: CGFloat = 32
    
    /// 卡片间距 - 12px
    static let gutter: CGFloat = 12
    
    /// Sidebar 宽度 - 260px
    static let sidebarWidth: CGFloat = 260
    
    /// 网格纹理间隔 - 24px
    static let gridTextureInterval: CGFloat = 24
    
    // MARK: - 编辑器尺寸
    
    /// 编辑器导航栏高度
    static let editorNavBarHeight: CGFloat = 44
    
    /// 编辑器播放控制栏高度（工具已移到顶部）
    static let editorToolbarHeight: CGFloat = 36
    
    /// 编辑器状态栏高度
    static let editorStatusBarHeight: CGFloat = 24
    
    /// 拖柄宽度
    static let editorHandleWidth: CGFloat = 4
    
    /// 拖柄热区（鼠标命中范围）
    static let editorHandleHitZone: CGFloat = 8
}

// MARK: - 圆角半径（参考剪映卡片风格，柔和圆角）
struct IndustrialCornerRadius {
    
    /// 极小圆角 - 4px（小按钮、badge）
    static let xs: CGFloat = 4
    
    /// 小圆角 - 8px（按钮、行项）
    static let sm: CGFloat = 8
    
    /// 中圆角 - 12px（面板、卡片）
    static let md: CGFloat = 12
    
    /// 大圆角 - 16px（大面板、弹窗）
    static let lg: CGFloat = 16
    
    /// 超大圆角 - 32px（圆形按钮，录制按钮）
    static let xl: CGFloat = 32
}

// MARK: - 阴影系统
struct IndustrialShadow {
    
    /// 小阴影（按钮、小卡片）
    static func small(for layer: CALayer) {
        layer.shadowColor = IndustrialColors.shadowColor.cgColor
        layer.shadowRadius = 6
        layer.shadowOpacity = 0.35
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }
    
    /// 中阴影（面板、对话框）
    static func medium(for layer: CALayer) {
        layer.shadowColor = IndustrialColors.shadowColor.cgColor
        layer.shadowRadius = 12
        layer.shadowOpacity = 0.45
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }
    
    /// 大阴影（模态窗口、浮动面板）
    static func large(for layer: CALayer) {
        layer.shadowColor = IndustrialColors.shadowColor.cgColor
        layer.shadowRadius = 18
        layer.shadowOpacity = 0.55
        layer.shadowOffset = CGSize(width: 0, height: 6)
    }
}

// MARK: - 发光效果
struct IndustrialGlow {
    
    /// 青色发光（录制按钮、电平表）
    static func cyan(for layer: CALayer, radius: CGFloat = 20, opacity: Float = 0.8) {
        layer.shadowColor = IndustrialColors.glowCyan.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = .zero
    }
    
    /// 琥珀色发光（警告状态）
    static func warning(for layer: CALayer, radius: CGFloat = 12, opacity: Float = 0.6) {
        layer.shadowColor = IndustrialColors.glowWarning.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = .zero
    }
    
    /// 红色发光（过载状态）
    static func danger(for layer: CALayer, radius: CGFloat = 16, opacity: Float = 1.0) {
        layer.shadowColor = IndustrialColors.glowDanger.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = .zero
    }
    
    /// 多重发光叠加（录制按钮）
    static func multiLayer(on targetLayer: CALayer, color: NSColor, configs: [(radius: CGFloat, opacity: Float)]) {
        configs.forEach { config in
            let glowLayer = CALayer()
            glowLayer.shadowColor = color.cgColor
            glowLayer.shadowRadius = config.radius
            glowLayer.shadowOpacity = config.opacity
            glowLayer.shadowOffset = .zero
            glowLayer.frame = targetLayer.bounds
            targetLayer.insertSublayer(glowLayer, at: 0)
        }
    }
}

// MARK: - 动画参数
struct IndustrialAnimation {
    
    /// 标准动画时长 - 120ms
    static let standard: TimeInterval = 0.12
    
    /// 长动画时长 - 200ms（状态切换）
    static let long: TimeInterval = 0.2
    
    /// 实时反馈时长 - 16.7ms（60fps）
    static let realtime: TimeInterval = 0.016
    
    /// 缓动函数（直接、无弹跳）
    static let timingFunction = CAMediaTimingFunction(name: .easeOut)
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

// MARK: - NSView 网格纹理扩展
extension NSView {
    /// 添加网格纹理（24px spacing）
    func addGridTexture(spacing: CGFloat = IndustrialSpacing.gridTextureInterval, color: NSColor = IndustrialColors.gridLight) {
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
        gridLayer.strokeColor = color.cgColor
        gridLayer.lineWidth = 1
        gridLayer.fillColor = nil
        
        // 确保 layer 存在
        wantsLayer = true
        layer?.insertSublayer(gridLayer, at: 0)
    }
}

// MARK: - NSColor 混合扩展
extension NSColor {
    /// 混合两种颜色
    static func blendColors(_ color1: NSColor, _ color2: NSColor, ratio: CGFloat) -> NSColor {
        let ratio = max(0, min(1, ratio))
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        color1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        return NSColor(
            red: r1 + (r2 - r1) * ratio,
            green: g1 + (g2 - g1) * ratio,
            blue: b1 + (b2 - b1) * ratio,
            alpha: a1 + (a2 - a1) * ratio
        )
    }
}

// MARK: - Collection Safe Subscript
extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
