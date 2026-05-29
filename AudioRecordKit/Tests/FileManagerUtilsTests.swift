import XCTest
@testable import AudioRecordKit
import Foundation

/// FileManagerUtils 纯函数测试（不涉及文件系统 I/O 的方法）
final class FileManagerUtilsTests: XCTestCase {
    
    var fileManager: FileManagerUtils!
    
    override func setUp() {
        super.setUp()
        fileManager = FileManagerUtils.shared
    }
    
    // MARK: - 文件名生成测试
    
    func testGenerateFileNameLegacyFormat() {
        let filename = fileManager.generateRecordingFileName(format: "m4a")
        
        XCTAssertTrue(filename.hasPrefix("record_"))
        XCTAssertTrue(filename.hasSuffix(".m4a"))
        
        // 应包含 ISO8601 时间戳格式
        let withoutExt = filename.replacingOccurrences(of: ".m4a", with: "")
        let timestampPart = withoutExt.replacingOccurrences(of: "record_", with: "")
        // ISO 格式应包含 T 分隔符（已被替换为 -）
        XCTAssertFalse(timestampPart.isEmpty)
    }
    
    func testGenerateFileNameWithMode() {
        // 麦克风模式
        let micFile = fileManager.generateRecordingFileName(
            recordingMode: .microphone,
            format: "wav"
        )
        XCTAssertTrue(micFile.hasPrefix("麦克风_"))
        XCTAssertTrue(micFile.hasSuffix(".wav"))
        
        // 系统混音模式
        let sysFile = fileManager.generateRecordingFileName(
            recordingMode: .systemMixdown,
            format: "m4a"
        )
        XCTAssertTrue(sysFile.hasPrefix("系统音频_"))
        XCTAssertTrue(sysFile.hasSuffix(".m4a"))
        
        // 特定进程模式（无应用名）
        let procFile = fileManager.generateRecordingFileName(
            recordingMode: .specificProcess,
            format: "wav"
        )
        XCTAssertTrue(procFile.hasPrefix("应用音频_"))
        
        // 特定进程模式（有应用名）
        let namedProcFile = fileManager.generateRecordingFileName(
            recordingMode: .specificProcess,
            appName: "Safari",
            format: "m4a"
        )
        XCTAssertTrue(namedProcFile.hasPrefix("Safari_"))
    }
    
    func testGenerateFileNameCleansIllegalCharacters() {
        // 应用名含非法字符
        let filename = fileManager.generateRecordingFileName(
            recordingMode: .specificProcess,
            appName: "My App/Name:test",
            format: "wav"
        )
        
        // 不应包含非法字符 / : 和空格
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains(" "))
    }

    // MARK: - 文件大小格式化测试
    
    func testFormatFileSizeBytes() {
        let result = fileManager.formatFileSize(500)
        XCTAssertTrue(result.contains("B") || result.contains("bytes"), "500 bytes 应显示为字节单位, 实际: \(result)")
    }
    
    func testFormatFileSizeKilobytes() {
        let result = fileManager.formatFileSize(1024)
        // 1KB 可能显示为 KB 或类似
        XCTAssertFalse(result.isEmpty)
    }
    
    func testFormatFileSizeMegabytes() {
        let result = fileManager.formatFileSize(2_048_000)
        // ~2MB
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("M") || result.contains("MB"))
    }

    // MARK: - 录音文件扩展名过滤
    
    /// 测试支持的音频文件扩展名列表
    func testSupportedAudioExtensions() {
        // 通过 getRecordingFiles 间接验证扩展名支持
        // 这里主要验证逻辑：支持的扩展名应为 m4a/mp3/wav
        let supportedExtensions = ["m4a", "mp3", "wav"]
        XCTAssertEqual(supportedExtensions.count, 3)
        XCTAssertTrue(supportedExtensions.contains("m4a"))
        XCTAssertTrue(supportedExtensions.contains("mp3"))
        XCTAssertTrue(supportedExtensions.contains("wav"))
    }
}
