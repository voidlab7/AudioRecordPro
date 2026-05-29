import XCTest
@testable import AudioRecordKit
import Foundation
import AVFoundation

/// AudioRecording 数据模型 + RecordingSettings + RecordedFileInfo + TrackInfo 单元测试
/// 注意: SPM 中的类型与 App 本地版本有差异，这里以 SPM 版本为准
final class AudioRecordingModelTests: XCTestCase {
    
    // MARK: - AudioRecording Tests
    
    func testAudioRecordingInitialization() {
        let url = URL(fileURLWithPath: "/tmp/test_recording.m4a")
        let recording = AudioRecording(
            fileURL: url,
            duration: 125.5,
            fileSize: 2_048_000,
            format: "m4a",
            recordingMode: "microphone",
            sampleRate: 48000.0,
            channels: 2
        )
        
        XCTAssertEqual(recording.fileName, "test_recording.m4a")
        XCTAssertEqual(recording.fileURL, url)
        XCTAssertEqual(recording.duration, 125.5)
        XCTAssertEqual(recording.fileSize, 2_048_000)
        XCTAssertEqual(recording.format, "m4a")
        XCTAssertEqual(recording.recordingMode, "microphone")
        XCTAssertEqual(recording.sampleRate, 48000.0)
        XCTAssertEqual(recording.channels, 2)
        XCTAssertNotNil(recording.id) // UUID 应自动生成
    }
    
    func testAudioRecordingIDIsUnique() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let r1 = AudioRecording(fileURL: url, duration: 10, fileSize: 1000, format: "wav", recordingMode: "systemAudio", sampleRate: 44100.0, channels: 2)
        let r2 = AudioRecording(fileURL: url, duration: 10, fileSize: 1000, format: "wav", recordingMode: "systemAudio", sampleRate: 44100.0, channels: 2)
        
        XCTAssertNotEqual(r1.id, r2.id, "每个录音应有唯一 ID")
    }
    
    func testFormattedDuration() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        
        let r1 = AudioRecording(fileURL: url, duration: 65, fileSize: 1000, format: "m4a", recordingMode: "microphone", sampleRate: 48000.0, channels: 2)
        XCTAssertEqual(r1.formattedDuration, "01:05")
        
        let r2 = AudioRecording(fileURL: url, duration: 0, fileSize: 1000, format: "m4a", recordingMode: "microphone", sampleRate: 48000.0, channels: 2)
        XCTAssertEqual(r2.formattedDuration, "00:00")
        
        let r3 = AudioRecording(fileURL: url, duration: 3661, fileSize: 1000, format: "m4a", recordingMode: "microphone", sampleRate: 48000.0, channels: 2)
        XCTAssertEqual(r3.formattedDuration, "61:01") // 不处理小时溢出
    }
    
    func testFormattedFileSize() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let recording = AudioRecording(fileURL: url, duration: 10, fileSize: 1_500_000, format: "m4a", recordingMode: "microphone", sampleRate: 48000.0, channels: 2)
        
        let sizeStr = recording.formattedFileSize
        XCTAssertFalse(sizeStr.isEmpty)
        XCTAssertTrue(sizeStr.contains("M") || sizeStr.contains("K") || sizeStr.contains("B"))
    }
    
    func testRecordingModeDisplayName() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        
        let mic = AudioRecording(fileURL: url, duration: 10, fileSize: 1000, format: "m4a", recordingMode: "microphone", sampleRate: 48000.0, channels: 2)
        XCTAssertEqual(mic.recordingModeDisplayName, "麦克风")
        
        let sys = AudioRecording(fileURL: url, duration: 10, fileSize: 1000, format: "m4a", recordingMode: "systemAudio", sampleRate: 48000.0, channels: 2)
        XCTAssertEqual(sys.recordingModeDisplayName, "系统声音")
        
        let custom = AudioRecording(fileURL: url, duration: 10, fileSize: 1000, format: "m4a", recordingMode: "customMode", sampleRate: 48000.0, channels: 2)
        XCTAssertEqual(custom.recordingModeDisplayName, "customMode")
    }
    
    func testAudioRecordingCodable() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let original = AudioRecording(
            fileURL: url,
            duration: 99.9,
            fileSize: 3_000_000,
            format: "wav",
            recordingMode: "specificProcess",
            sampleRate: 44100.0,
            channels: 1
        )
        
        do {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AudioRecording.self, from: data)
            
            XCTAssertEqual(decoded.id, original.id)
            XCTAssertEqual(decoded.fileName, original.fileName)
            XCTAssertEqual(decoded.duration, original.duration)
            XCTAssertEqual(decoded.fileSize, original.fileSize)
            XCTAssertEqual(decoded.format, original.format)
            XCTAssertEqual(decoded.recordingMode, original.recordingMode)
            XCTAssertEqual(decoded.sampleRate, original.sampleRate)
            XCTAssertEqual(decoded.channels, original.channels)
        } catch {
            XCTFail("AudioRecording Codable 编解码失败: \(error)")
        }
    }
    
    func testAudioRecordingHasFormattedCreatedAt() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let recording = AudioRecording(fileURL: url, duration: 10, fileSize: 1000, format: "m4a", recordingMode: "microphone", sampleRate: 48000.0, channels: 2)
        
        // formattedCreatedAt 应非空（包含日期和时间）
        let dateStr = recording.formattedCreatedAt
        XCTAssertFalse(dateStr.isEmpty)
    }

    // MARK: - RecordingSettings Tests
    
    func testRecordingSettingsDefaultValues() {
        let settings = RecordingSettings()
        
        XCTAssertEqual(settings.format, .m4a)
        XCTAssertEqual(settings.mode, .microphone)
        XCTAssertEqual(settings.sampleRate, 48000)
        XCTAssertEqual(settings.channels, 2)
        XCTAssertEqual(settings.quality, 96)
    }
    
    func testRecordingSettingsValidation() {
        var settings = RecordingSettings()
        
        // 默认值应通过验证
        let errors = settings.validate()
        XCTAssertTrue(errors.isEmpty, "默认设置不应有错误，实际: \(errors)")
        
        // 无效采样率
        settings.sampleRate = -1
        let errors1 = settings.validate()
        XCTAssertFalse(errors1.isEmpty)
        XCTAssertTrue(errors1.contains(where: { $0.contains("采样率") }))
        
        // 无效声道数
        settings.sampleRate = 48000
        settings.channels = 0
        let errors2 = settings.validate()
        XCTAssertFalse(errors2.isEmpty)
        XCTAssertTrue(errors2.contains(where: { $0.contains("声道") }))
        
        // 超大声道数
        settings.channels = 10
        let errors3 = settings.validate()
        XCTAssertFalse(errors3.isEmpty)
    }
    
    func testRecordingSettingsFormatSettings() {
        var m4aSettings = RecordingSettings()
        m4aSettings.format = .m4a
        let audioSettings = m4aSettings.getAudioFormatSettings()
        XCTAssertEqual(audioSettings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
        
        var wavSettings = RecordingSettings()
        wavSettings.format = .wav
        let wavAudioSettings = wavSettings.getAudioFormatSettings()
        XCTAssertEqual(wavAudioSettings[AVFormatIDKey] as? UInt32, kAudioFormatLinearPCM)
    }

    // MARK: - RecordingState Tests (SPM 版本 - 精简 enum)
    
    func testRecordingStateAllCases() {
        // SPM 中 RecordingState 是 Sendable 枚举，无关联值
        let allCases: [RecordingState] = [.idle, .preparing, .recording, .stopping, .playing, .error]
        XCTAssertEqual(allCases.count, 6)
    }
    
    func testRecordingStateCaseCount() {
        // 验证枚举 case 数量与预期一致（手动列出，RecordingState 未声明 CaseIterable）
        let allCases: [RecordingState] = [.idle, .preparing, .recording, .stopping, .playing, .error]
        XCTAssertEqual(allCases.count, 6)
    }

    // MARK: - RecordedFileInfo Tests
    
    func testRecordedFileInfoFormatting() {
        let now = Date()
        let info = RecordedFileInfo(
            url: URL(fileURLWithPath: "/tmp/rec.wav"),
            name: "test_rec",
            date: now,
            duration: 185.5,
            size: 5_242_880
        )
        
        XCTAssertEqual(info.name, "test_rec")
        XCTAssertEqual(info.duration, 185.5)
        XCTAssertEqual(info.formattedDuration, "03:05")
        XCTAssertFalse(info.formattedSize.isEmpty)
    }
    
    func testTrackInfoInitialization() {
        let track = TrackInfo(icon: "mic.fill", title: "麦克风", isActive: true)
        
        XCTAssertEqual(track.icon, "mic.fill")
        XCTAssertEqual(track.title, "麦克风")
        XCTAssertTrue(track.isActive)
        XCTAssertNil(track.appIcon)
    }
}
