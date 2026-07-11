import XCTest
@testable import AudioRecordKit
import Foundation

/// PermissionManager 纯逻辑测试（权限状态描述和向导文本）
final class PermissionManagerTests: XCTestCase {
    
    // 注意: PermissionManager 是 internal 类，PermissionStatus 也是 internal 类型
    // 这里只测试可公开访问的描述性和向导方法

    // MARK: - 权限向导测试
    
    func testMicrophonePermissionGuide() {
        let pm = createTestablePermissionManager()
        let guide = pm.getPermissionGuide(for: .microphone)
        
        XCTAssertTrue(guide.contains("麦克风"))
        XCTAssertTrue(guide.contains("系统偏好设置"))
        XCTAssertTrue(guide.contains("隐私"))
    }
    
    func testSystemAudioCapturePermissionGuide() {
        let pm = createTestablePermissionManager()
        let guide = pm.getPermissionGuide(for: .systemAudioCapture)
        
        XCTAssertTrue(guide.contains("系统音频"))
        XCTAssertTrue(guide.contains("允许"))
    }

    // MARK: - Helper
    
    /// 创建一个可用于测试的 PermissionManager 实例
    private func createTestablePermissionManager() -> PermissionManager {
        return .shared // 单例模式，直接使用 shared
    }
}

// MARK: - LogLevel Tests

final class LogLevelTests: XCTestCase {
    
    func testLogLevelAllCases() {
        let levels = LogLevel.allCases
        
        XCTAssertEqual(levels.count, 5)
        XCTAssertTrue(levels.contains(.debug))
        XCTAssertTrue(levels.contains(.info))
        XCTAssertTrue(levels.contains(.warning))
        XCTAssertTrue(levels.contains(.error))
        XCTAssertTrue(levels.contains(.fatal))
    }
    
    func testLogLevelOSLogTypeMapping() {
        XCTAssertEqual(LogLevel.debug.osLogType, .debug)
        XCTAssertEqual(LogLevel.info.osLogType, .info)
        XCTAssertEqual(LogLevel.warning.osLogType, .default)
        XCTAssertEqual(LogLevel.error.osLogType, .error)
        XCTAssertEqual(LogLevel.fatal.osLogType, .fault)
    }
    
    func testLogLevelEmojiMapping() {
        XCTAssertEqual(LogLevel.debug.emoji, "🔍")
        XCTAssertEqual(LogLevel.info.emoji, "ℹ️")
        XCTAssertEqual(LogLevel.warning.emoji, "⚠️")
        XCTAssertEqual(LogLevel.error.emoji, "❌")
        XCTAssertEqual(LogLevel.fatal.emoji, "💥")
    }
    
    func testLogLevelRawValueMapping() {
        XCTAssertEqual(LogLevel.debug.rawValue, "DEBUG")
        XCTAssertEqual(LogLevel.info.rawValue, "INFO")
        XCTAssertEqual(LogLevel.warning.rawValue, "WARNING")
        XCTAssertEqual(LogLevel.error.rawValue, "ERROR")
        XCTAssertEqual(LogLevel.fatal.rawValue, "FATAL")
    }
}

// MARK: - DateFormatter Extension Test

final class DateFormatterExtensionTests: XCTestCase {
    
    func testLogTimestampFormatterIsConsistent() {
        let formatter = DateFormatter.logTimestamp
        
        // 同一时间多次调用应返回相同格式的时间字符串
        let date = Date(timeIntervalSinceReferenceDate: 700000000) // 固定日期
        let result1 = formatter.string(from: date)
        let result2 = formatter.string(from: date)
        
        XCTAssertEqual(result1, result2)
        
        // 格式应包含时间部分 (HH:mm:ss.SSS)
        XCTAssertFalse(result1.isEmpty)
    }
}
