import XCTest
@testable import AudioRecordKit
import Foundation

/// FileManagerUtils 测试（V2.0：UUID 制文件名 + .arlock 加密 + 临时文件模式）
/// 2026-09-20 现代化：原 V1 测试（generateRecordingFileName 模式前缀）随 V2 重构删除，已更新为 V2 API
final class FileManagerUtilsTests: XCTestCase {

    var fileManager: FileManagerUtils!

    override func setUp() {
        super.setUp()
        fileManager = FileManagerUtils.shared
    }

    // MARK: - V2 录音 UUID 生成

    func testGenerateRecordingUUIDIsUnique() {
        let uuid1 = fileManager.generateRecordingUUID()
        let uuid2 = fileManager.generateRecordingUUID()
        XCTAssertNotEqual(uuid1, uuid2, "每次生成的录音 UUID 必须唯一，防录音文件互相覆盖")
    }

    // MARK: - V2 临时文件路径生成

    func testTempRecordingFileURLUsesRecordingPrefix() {
        let url = fileManager.getTempRecordingFileURL(prefix: "system", format: "m4a")
        XCTAssertTrue(
            url.lastPathComponent.hasPrefix(AudioCryptoConfig.TempFilePattern.recordingPrefix),
            "临时录音文件名必须以 \(AudioCryptoConfig.TempFilePattern.recordingPrefix) 前缀开头，防被清理逻辑误判"
        )
    }

    func testTempRecordingFileURLContainsSourcePrefixAndFormat() {
        let url = fileManager.getTempRecordingFileURL(prefix: "system", format: "m4a")
        XCTAssertTrue(url.lastPathComponent.contains("system"), "文件名应含音源前缀")
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".m4a"), "扩展名必须正确")
    }

    func testTempRecordingFileURLIsInTempDirectory() {
        let url = fileManager.getTempRecordingFileURL(prefix: "mic", format: "wav")
        XCTAssertTrue(url.path.hasPrefix(NSTemporaryDirectory()), "临时文件必须在系统临时目录")
    }

    // MARK: - 加密配置（.arlock 容器）

    func testArlockFileExtensionConfig() {
        let ext = AudioCryptoConfig.fileExtension
        XCTAssertFalse(ext.isEmpty, ".arlock 扩展名配置不能为空")
        XCTAssertFalse(ext.hasPrefix("."), "fileExtension 不含前导点（拼路径时手动加）")
    }

    func testTempFilePatternsConfigured() {
        XCTAssertFalse(AudioCryptoConfig.TempFilePattern.recordingPrefix.isEmpty)
        XCTAssertFalse(AudioCryptoConfig.TempFilePattern.playbackPrefix.isEmpty)
        XCTAssertFalse(AudioCryptoConfig.TempFilePattern.exportPrefix.isEmpty)
    }

    // MARK: - 文件大小格式化（V1 沿用，产品未变）

    func testFormatFileSizeBytes() {
        let result = fileManager.formatFileSize(500)
        XCTAssertTrue(result.contains("B") || result.contains("bytes"), "500 bytes 应显示为字节单位, 实际: \(result)")
    }

    func testFormatFileSizeKilobytes() {
        let result = fileManager.formatFileSize(1024)
        XCTAssertFalse(result.isEmpty)
    }

    func testFormatFileSizeMegabytes() {
        let result = fileManager.formatFileSize(2_048_000)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("M") || result.contains("MB"))
    }
}
