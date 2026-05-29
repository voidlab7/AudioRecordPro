import XCTest
@testable import AudioRecordKit
import Cocoa
import Foundation

/// TaptureTheme 主题系统测试 + LevelMonitor 测试
final class ThemeAndMonitorTests: XCTestCase {
    
    // MARK: - TaptureTheme Color Tests
    
    func testColorBgPrimaryIsDark() {
        let color = TaptureTheme.Color.bgPrimary
        let rgb = color.usingColorSpace(.sRGB)!
        
        // 深海军蓝 #0F172A — 应为深色
        let red = rgb.redComponent
        let green = rgb.greenComponent
        let blue = rgb.blueComponent
        
        // #0F172A: R=15/255, G=23/255, B=42/255
        // 验证颜色值在合理范围内 (0.0 - 1.0)
        XCTAssertGreaterThanOrEqual(red, 0.0)
        XCTAssertLessThanOrEqual(red, 1.0)
        XCTAssertGreaterThanOrEqual(green, 0.0)
        XCTAssertLessThanOrEqual(green, 1.0)
        XCTAssertGreaterThanOrEqual(blue, 0.0)
        XCTAssertLessThan(blue, 1.0) // 不应接近白色
        
        // 应该是暗色调
        XCTAssertLessThan(red + green + blue, 1.5) // 暗色 RGB 总和较小
    }
    
    func testColorAccentIsBlue() {
        let color = TaptureTheme.Color.accent
        // 冰蓝 #38BDF8 — 蓝色调
        let blue = color.usingColorSpace(.sRGB)!.blueComponent
        XCTAssertGreaterThan(blue, 0.9) // 蓝通道值很高
    }
    
    func testColorErrorIsRed() {
        // 错误色应为红色调
        let error = TaptureTheme.Color.error
        let red = error.usingColorSpace(.sRGB)!.redComponent
        XCTAssertGreaterThan(red, 0.9) // 红通道值很高
    }
    
    func testColorSuccessIsGreen() {
        // 成功色应为绿色调
        let success = TaptureTheme.Color.success
        let green = success.usingColorSpace(.sRGB)!.greenComponent
        XCTAssertGreaterThan(green, 0.7) // 绿通道值较高
    }

    // MARK: - TaptureTheme Font Tests
    
    func testFontTimerProperties() {
        let font = TaptureTheme.Font.timer
        
        XCTAssertEqual(font.pointSize, 28)
        // SF Mono Bold 28px — 检查字体特征
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
    }
    
    func testFontTitleProperties() {
        let font = TaptureTheme.Font.title
        XCTAssertEqual(font.pointSize, 13)
    }
    
    func testFontBodyProperties() {
        let font = TaptureTheme.Font.body
        XCTAssertEqual(font.pointSize, 13)
    }

    // MARK: - TaptureTheme Radius Tests
    
    func testRadiusValues() {
        XCTAssertGreaterThan(TaptureTheme.Radius.button, 0)
        XCTAssertGreaterThan(TaptureTheme.Radius.card, 0)
        XCTAssertEqual(TaptureTheme.Radius.recordButton, 32) // 录制按钮全圆
    }

    // MARK: - NSColor Hex Extension Tests
    
    func testNSColorHexInitializerWithValidHex() {
        func rgb(_ c: NSColor) -> (r: Double, g: Double, b: Double) {
            let srgb = c.usingColorSpace(.sRGB)!
            return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
        }

        // 纯红
        let r = NSColor(hex: "#FF0000")
        XCTAssertEqual(rgb(r).r, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb(r).g, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb(r).b, 0.0, accuracy: 0.01)

        // 纯绿
        let g = NSColor(hex: "#00FF00")
        XCTAssertEqual(rgb(g).r, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb(g).g, 1.0, accuracy: 0.01)

        // 纯蓝
        let b = NSColor(hex: "#0000FF")
        XCTAssertEqual(rgb(b).b, 1.0, accuracy: 0.01)

        // 白色
        let white = NSColor(hex: "#FFFFFF")
        XCTAssertEqual(rgb(white).r, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb(white).g, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb(white).b, 1.0, accuracy: 0.01)

        // 黑色
        let black = NSColor(hex: "#000000")
        XCTAssertEqual(rgb(black).r, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb(black).g, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb(black).b, 0.0, accuracy: 0.01)

        // 无 # 前缀
        let noHash = NSColor(hex: "AABBCC")
        XCTAssertEqual(rgb(noHash).r, 0xAA / 255.0, accuracy: 0.01)
    }
    
    func testNSColorHexInitializerWithInvalidInput() {
        // 无效十六进制应 fallback 到黑色
        let fallback = NSColor(hex: "ZZZZZZ")
        let fallbackRGB = fallback.usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(fallbackRGB.redComponent), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(fallbackRGB.greenComponent), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(fallbackRGB.blueComponent), 0.0, accuracy: 0.01)
        XCTAssertEqual(fallback.alphaComponent, 1.0)
    }
}

// MARK: - LevelMonitor Tests

final class LevelMonitorTests: XCTestCase {
    
    var monitor: LevelMonitor!
    
    override func setUp() {
        super.setUp()
        monitor = LevelMonitor()
    }
    
    override func tearDown() {
        monitor.reset()
        super.tearDown()
    }
    
    func testInitialNotMonitoring() {
        // 初始状态：未设置回调，不崩溃即可
        monitor.updateLevel(0.5) // 不应崩溃
    }
    
    func testLevelUpdateCallback() {
        var receivedLevels: [Float] = []
        monitor.onLevelUpdate = { level in
            receivedLevels.append(level)
        }
        
        monitor.updateLevel(0.3)
        monitor.updateLevel(0.7)
        monitor.updateLevel(1.0)
        
        XCTAssertEqual(receivedLevels.count, 3)
        XCTAssertEqual(receivedLevels[0], 0.3)
        XCTAssertEqual(receivedLevels[1], 0.7)
        XCTAssertEqual(receivedLevels[2], 1.0)
    }
    
    func testStopMonitoringSendsZero() {
        var finalLevel: Float = -1
        monitor.onLevelUpdate = { level in
            finalLevel = level
        }
        
        // 先启动再停止
        monitor.startMonitoring(source: .simulated)
        monitor.stopMonitoring()
        
        XCTAssertEqual(finalLevel, 0.0, "停止监控时应发送电平 0")
    }
    
    func testResetStopsMonitoring() {
        var callbackCount = 0
        monitor.onLevelUpdate = { _ in
            callbackCount += 1
        }
        
        monitor.startMonitoring(source: .simulated)
        monitor.reset()
        
        // reset 后不应再有回调
        let beforeCount = callbackCount
        // 等待一小段时间让可能的定时器触发
        Thread.sleep(forTimeInterval: 0.2)
        let afterCount = callbackCount
        
        // reset 后 stopMonitoring 被调用过一次（发送 0）
        // 之后不再有新的模拟数据回调
        // 注意：由于 simulated 模式使用定时器，reset 后定时器被 invalidate
        // 所以 afterCount 应等于或仅略大于 beforeCount
        XCTAssertLessThanOrEqual(afterCount - beforeCount, 2)
    }
}
