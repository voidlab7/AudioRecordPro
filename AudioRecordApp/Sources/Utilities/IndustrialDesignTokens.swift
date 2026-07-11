import Cocoa

// MARK: - Studio Dark Design Tokens (v3.0)
// 参考剪映专业版设计语言 — 色差分层、无边框、克制表达

/// 颜色系统（Studio Dark v3.0）
struct IndustrialColors {
    
    // MARK: - 背景色（3 级核心阶梯）
    
    /// 最深底色 — 轨道区、时间线背景、窗口底
    static let surface = NSColor(hex: "#1B1B1F")
    
    /// 同 surface（兼容旧接口）
    static let surfaceDim = NSColor(hex: "#1B1B1F")
    
    /// 亮色背景（Tooltip、Popover）
    static let surfaceBright = NSColor(hex: "#424245")
    
    /// 最深底色（兼容旧接口，统一到 surface）
    static let surfaceContainerLowest = NSColor(hex: "#1B1B1F")
    
    /// 轨道区/波形区底色（= surface，最深层）
    static let surfaceContainerLow = NSColor(hex: "#1B1B1F")
    
    /// 面板色 — Sidebar、Toolbar、控制面板、卡片
    static let surfaceContainer = NSColor(hex: "#2A2A2E")
    
    /// Hover 态 / 抬升色
    static let surfaceContainerHigh = NSColor(hex: "#363638")
    
    /// Active / 选中容器（非主选中色，用于非强调区域）
    static let surfaceContainerHighest = NSColor(hex: "#363638")
    
    // MARK: - 文字色
    
    /// 主文字 — 标题、文件名、数值
    static let onSurface = NSColor(hex: "#E8E8EA")
    
    /// 次要文字 — 描述、元数据、分区标题
    static let onSurfaceVariant = NSColor(hex: "#A0A0A5")
    
    /// 三级文字 — 占位符、禁用态、时间刻度
    static let textTertiary = NSColor(hex: "#6B6B70")
    
    /// 反转背景色
    static let inverseSurface = NSColor(hex: "#E8E8EA")
    
    /// 反转文字色
    static let inverseOnSurface = NSColor(hex: "#2A2A2E")
    
    // MARK: - 分割线（极少使用）
    
    /// 主边框（几乎不用，仅高对比场景）
    static let outline = NSColor(white: 1.0, alpha: 0.15)
    
    /// 分割线 — 仅 toolbar 底部、轨道头竖线、面板内分区
    static let outlineVariant = NSColor(white: 1.0, alpha: 0.08)
    
    // MARK: - 主强调色（Accent 青绿）
    
    /// 主强调 — 选中态文字/icon、活跃 tab、交互元素
    static let primary = NSColor(hex: "#3CD5C8")
    
    /// 选中态背景填充（accent 暗化）
    static let primaryContainer = NSColor(hex: "#2A9B91")
    
    /// 主色上的文字
    static let onPrimary = NSColor(hex: "#FFFFFF")
    
    /// 主色容器上的文字
    static let onPrimaryContainer = NSColor(hex: "#FFFFFF")
    
    /// 反转主色
    static let inversePrimary = NSColor(hex: "#006877")
    
    /// 主色固定色（兼容）
    static let primaryFixed = NSColor(hex: "#3CD5C8")
    static let primaryFixedDim = NSColor(hex: "#2A9B91")
    static let onPrimaryFixed = NSColor(hex: "#FFFFFF")
    static let onPrimaryFixedVariant = NSColor(hex: "#FFFFFF")
    
    // MARK: - 次要色（兼容旧接口）
    
    static let secondary = NSColor(hex: "#7bd0ff")
    static let secondaryContainer = NSColor(hex: "#00a6e0")
    static let onSecondary = NSColor(hex: "#00354a")
    static let onSecondaryContainer = NSColor(hex: "#00374d")
    static let secondaryFixed = NSColor(hex: "#c4e7ff")
    static let secondaryFixedDim = NSColor(hex: "#7bd0ff")
    static let onSecondaryFixed = NSColor(hex: "#001e2c")
    static let onSecondaryFixedVariant = NSColor(hex: "#004c69")
    
    // MARK: - 第三色（琥珀 — 警告）
    
    static let tertiary = NSColor(hex: "#FFB74D")
    static let tertiaryContainer = NSColor(hex: "#ffb13b")
    static let onTertiary = NSColor(hex: "#462b00")
    static let onTertiaryContainer = NSColor(hex: "#6e4600")
    static let tertiaryFixed = NSColor(hex: "#ffddb5")
    static let tertiaryFixedDim = NSColor(hex: "#ffb957")
    static let onTertiaryFixed = NSColor(hex: "#2a1800")
    static let onTertiaryFixedVariant = NSColor(hex: "#643f00")
    
    // MARK: - 错误色
    
    static let error = NSColor(hex: "#EF5350")
    static let errorContainer = NSColor(hex: "#93000a")
    static let onError = NSColor(hex: "#FFFFFF")
    static let onErrorContainer = NSColor(hex: "#ffdad6")
    
    // MARK: - 状态色
    
    /// 正常 — 绿色
    static let statusSuccess = NSColor(hex: "#4CAF50")
    
    /// 警告 — 琥珀（高电平 70-90%）
    static let statusWarning = NSColor(hex: "#FFB74D")
    
    /// 危险 — 红色（过载 > 90%）
    static let statusDanger = NSColor(hex: "#EF5350")
    
    /// 录制按钮色
    static let statusCritical = NSColor(hex: "#E85050")
    
    // MARK: - Legacy 兼容（映射到新色值）
    
    static let base1 = NSColor(hex: "#1B1B1F")
    static let base2 = NSColor(hex: "#2A2A2E")
    static let base3 = NSColor(hex: "#363638")
    static let borderMuted = NSColor(white: 1.0, alpha: 0.08)
    static let textPrimary = NSColor(hex: "#E8E8EA")
    static let textSecondary = NSColor(hex: "#A0A0A5")
    static let cyanDim = NSColor(hex: "#2A9B91")
    static let blueDim = NSColor(hex: "#3CD5C8")
    
    // MARK: - 波形色（珊瑚橙系列）
    
    /// 播放头/录制焦点
    static let waveformAccent = NSColor(hex: "#E85050")
    
    /// 主波形条（签名色）
    static let waveformCoral = NSColor(hex: "#E87850")
    
    /// 次级波形/弱电平
    static let waveformSoft = NSColor(hex: "#E87850", alpha: 0.6)
    
    /// 波形静音段
    static let waveformMuted = NSColor(hex: "#E87850", alpha: 0.25)
    
    // MARK: - 网格与纹理
    
    static let gridLight = NSColor(white: 1.0, alpha: 0.03)
    static let gridMedium = NSColor(white: 1.0, alpha: 0.06)
    static let gridHeavy = NSColor(white: 1.0, alpha: 0.12)
    
    // MARK: - 发光效果（仅录制按钮使用）
    
    /// 录制按钮脉冲发光
    static let glowCyan = NSColor(hex: "#E85050", alpha: 0.3)
    
    /// 警告发光
    static let glowWarning = NSColor(hex: "#FFB74D", alpha: 0.3)
    
    /// 危险发光
    static let glowDanger = NSColor(hex: "#EF5350", alpha: 0.35)
    
    // MARK: - 阴影（暗色界面不使用，保留接口）
    
    static let shadowColor = NSColor(white: 0.0, alpha: 0.0)
    
    // MARK: - 编辑器专用色
    
    /// 选区拖柄
    static let editorHandle = IndustrialColors.primary
    
    /// 选区外遮罩
    static let editorDimOverlay = NSColor(hex: "#1B1B1F", alpha: 0.5)
    
    /// 静音段背景
    static let editorSilenceOverlay = NSColor(hex: "#363638", alpha: 0.6)
    
    /// 静音段删除标记线
    static let editorSilenceLine = IndustrialColors.error
    
    /// 编辑中状态徽章色
    static let editorEditingBadge = IndustrialColors.tertiary
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

// MARK: - 间距系统（Studio Dark v3.0）
struct IndustrialSpacing {
    
    /// 基础单位 - 4px
    static let unit: CGFloat = 4
    
    /// 极小间距 - 4px
    static let xs: CGFloat = 4
    
    /// 小间距 - 8px
    static let sm: CGFloat = 8
    
    /// 面板内边距 - 12px（统一）
    static let md: CGFloat = 12
    
    /// 分区间距 - 16px
    static let lg: CGFloat = 16
    
    /// 大分区 - 24px
    static let xl: CGFloat = 24
    
    /// 卡片间距 - 12px（与 md 统一）
    static let gutter: CGFloat = 12
    
    /// Sidebar 宽度 - 220px
    static let sidebarWidth: CGFloat = 220
    
    /// 网格纹理间隔 - 24px
    static let gridTextureInterval: CGFloat = 24
    
    /// 列表行高 - 40px（统一）
    static let listRowHeight: CGFloat = 40
    
    // MARK: - 编辑器尺寸
    
    /// 编辑器导航栏高度
    static let editorNavBarHeight: CGFloat = 44
    
    /// Toolbar 高度
    static let editorToolbarHeight: CGFloat = 44
    
    /// 编辑器状态栏高度
    static let editorStatusBarHeight: CGFloat = 24
    
    /// 控制面板高度
    static let controlPanelHeight: CGFloat = 80
    
    /// 拖柄宽度
    static let editorHandleWidth: CGFloat = 4
    
    /// 拖柄热区（鼠标命中范围）
    static let editorHandleHitZone: CGFloat = 8
}

// MARK: - 圆角半径（3 档统一，参考剪映）
struct IndustrialCornerRadius {
    
    /// 小圆角 - 6px（按钮、badge、列表行 hover、输入框）
    static let xs: CGFloat = 6
    
    /// 小圆角 - 6px（兼容旧接口）
    static let sm: CGFloat = 6
    
    /// 中圆角 - 10px（面板卡片、toolbar、sidebar 分区）
    static let md: CGFloat = 10
    
    /// 大圆角 - 14px（弹窗、设置窗口）
    static let lg: CGFloat = 14
    
    /// 圆形 - 用于录制按钮（动态计算 bounds/2）
    static let xl: CGFloat = 24
}

// MARK: - 阴影系统（暗色界面不使用阴影，保留接口兼容）
struct IndustrialShadow {
    
    /// 小阴影 — 不启用
    static func small(for layer: CALayer) {
        layer.shadowOpacity = 0
    }
    
    /// 中阴影 — 不启用
    static func medium(for layer: CALayer) {
        layer.shadowOpacity = 0
    }
    
    /// 大阴影 — 不启用
    static func large(for layer: CALayer) {
        layer.shadowOpacity = 0
    }
}

// MARK: - 发光效果（仅录制按钮使用单层脉冲）
struct IndustrialGlow {
    
    /// 录制按钮脉冲发光
    static func cyan(for layer: CALayer, radius: CGFloat = 12, opacity: Float = 0.4) {
        layer.shadowColor = IndustrialColors.statusCritical.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = .zero
    }
    
    /// 警告发光
    static func warning(for layer: CALayer, radius: CGFloat = 10, opacity: Float = 0.3) {
        layer.shadowColor = IndustrialColors.glowWarning.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = .zero
    }
    
    /// 过载发光
    static func danger(for layer: CALayer, radius: CGFloat = 12, opacity: Float = 0.4) {
        layer.shadowColor = IndustrialColors.glowDanger.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = .zero
    }
    
    /// 多重发光 — 简化为单层
    static func multiLayer(on targetLayer: CALayer, color: NSColor, configs: [(radius: CGFloat, opacity: Float)]) {
        guard let first = configs.first else { return }
        targetLayer.shadowColor = color.cgColor
        targetLayer.shadowRadius = first.radius
        targetLayer.shadowOpacity = first.opacity
        targetLayer.shadowOffset = .zero
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
