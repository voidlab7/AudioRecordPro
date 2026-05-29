import Cocoa

// MARK: - Tapture Theme
/// Tapture 全局设计系统 — 颜色、字体、圆角常量
enum TaptureTheme {

    // MARK: - Colors
    enum Color {
        /// 主背景色 — 深海军蓝 #0F172A
        static let bgPrimary = NSColor(hex: "#0F172A")
        /// 次级背景色 — 侧栏/卡片 #1E293B
        static let bgSecondary = NSColor(hex: "#1E293B")
        /// 强调色 — 冰蓝 #38BDF8
        static let accent = NSColor(hex: "#38BDF8")
        /// 强调色暗态（hover）#0284C7
        static let accentHover = NSColor(hex: "#0284C7")
        /// 错误色 #F87171
        static let error = NSColor(hex: "#F87171")
        /// 成功色 #34D399
        static let success = NSColor(hex: "#34D399")

        // MARK: - Text Colors
        /// 文字主色 #F1F5F9
        static let textPrimary = NSColor(hex: "#F1F5F9")
        /// 文字次色 #94A3B8
        static let textSecondary = NSColor(hex: "#94A3B8")
        /// 文字弱化 #64748B
        static let textTertiary = NSColor(hex: "#64748B")

        // MARK: - Waveform / Level Meter
        /// 波形活跃色（录制中）
        static let waveActive = NSColor(hex: "#38BDF8")
        /// 波形静止色
        static let waveInactive = NSColor(hex: "#475569")
    }

    // MARK: - Fonts
    enum Font {
        /// 数字/计时器字体 — SF Mono Bold 28px
        static let timer = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        /// 标题字体 — SF Pro Semibold 13px
        static let title = NSFont.systemFont(ofSize: 13, weight: .semibold)
        /// 正文字体 — SF Pro Regular 13px
        static let body = NSFont.systemFont(ofSize: 13, weight: .regular)
        /// 状态文字 — SF Pro Regular 12px
        static let status = NSFont.systemFont(ofSize: 12, weight: .regular)
    }

    // MARK: - Radii
    enum Radius {
        /// 按钮 / Chip 圆角
        static let button: CGFloat = 10
        /// 卡片圆角
        static let card: CGFloat = 14
        /// 录制按钮全圆
        static let recordButton: CGFloat = 32
    }
}

// MARK: - NSColor Hex Extension
extension NSColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            self.init(red: 0, green: 0, blue: 0, alpha: 1.0)
            return
        }

        let red   = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue  = CGFloat(rgb & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
