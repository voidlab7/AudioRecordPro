import Cocoa

/// 自定义计时器标签 - 强制使用青色文字
class TimerLabel: NSView {
    
    var stringValue: String = "00:00.00" {
        didSet {
            needsDisplay = true
        }
    }
    
    private let font = IndustrialTypography.timer
    private let textColor = IndustrialColors.primary
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // 绘制文字
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: font,
            .kern: 2.0
        ]
        
        let attrString = NSAttributedString(string: stringValue, attributes: attrs)
        let textSize = attrString.size()
        
        // 居左对齐，垂直居中
        let textRect = NSRect(
            x: 0,
            y: (bounds.height - textSize.height) / 2,
            width: bounds.width,
            height: textSize.height
        )
        
        attrString.draw(in: textRect)
    }
    
    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let size = (stringValue as NSString).size(withAttributes: attrs)
        return NSSize(width: size.width + 20, height: size.height)
    }
}
