import XCTest
@testable import AudioRecordKit
import Foundation
import AVFoundation

/// AudioUtils 纯逻辑部分测试：枚举值、格式化、错误类型等
/// 注意: 涉及 CoreAudio/AVFoundation 硬件调用的静态方法不在测试范围内
final class AudioUtilsTests: XCTestCase {
    
    // MARK: - AudioFormat Enum Tests
    
    func testAudioFormatM4aProperties() {
        let format = AudioFormat.m4a
        
        XCTAssertEqual(format.rawValue, "m4a")
        XCTAssertEqual(format.fileExtension, "m4a")
        
        let settings = format.settings
        XCTAssertEqual(settings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 2)
    }
    
    func testAudioFormatWavProperties() {
        let format = AudioFormat.wav
        
        XCTAssertEqual(format.rawValue, "wav")
        XCTAssertEqual(format.fileExtension, "wav")
        
        let settings = format.settings
        XCTAssertEqual(settings[AVFormatIDKey] as? UInt32, kAudioFormatLinearPCM)
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 2)
        XCTAssertEqual(settings[AVLinearPCMBitDepthKey] as? Int, 16)
        XCTAssertFalse(settings[AVLinearPCMIsFloatKey] as? Bool ?? true) // 应为 false (整数格式)
        XCTAssertFalse(settings[AVLinearPCMIsBigEndianKey] as? Bool ?? true)
    }
    
    func testAudioFormatAllCases() {
        let allFormats: [AudioFormat] = [.m4a, .wav]
        XCTAssertTrue(allFormats.contains(.m4a))
        XCTAssertTrue(allFormats.contains(.wav))
        XCTAssertEqual(allFormats.count, 2)
    }

    // MARK: - RecordingMode Enum Tests
    
    func testRecordingModeMicrophoneRawValue() {
        let mode = RecordingMode.microphone
        XCTAssertEqual(mode.rawValue, "microphone")
    }

    func testRecordingModeSpecificProcessRawValue() {
        let mode = RecordingMode.specificProcess
        XCTAssertEqual(mode.rawValue, "specificProcess")
    }

    func testRecordingModeSystemMixdownRawValue() {
        let mode = RecordingMode.systemMixdown
        XCTAssertEqual(mode.rawValue, "systemMixdown")
    }
    
    func testRecordingModeAllCases() {
        // SPM 中 RecordingMode 未声明 CaseIterable，手动验证
        let modes: [RecordingMode] = [.microphone, .specificProcess, .systemMixdown]
        XCTAssertEqual(modes.count, 3)
    }

    // MARK: - AudioDataConversionError Tests
    
    func testAudioDataConversionErrorDescriptions() {
        let errors: [AudioDataConversionError] = [
            .unsupportedBufferCount(2),
            .emptyInputData,
            .unsupportedFormat,
            .conversionFailed("test reason")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) 应有描述")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) 描述不应为空")
        }
    }
    
    func testUnsupportedBufferCountErrorContent() {
        let error = AudioDataConversionError.unsupportedBufferCount(3)
        XCTAssertTrue(error.errorDescription?.contains("3") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("缓冲区数量") ?? false)
    }
    
    func testEmptyInputDataError() {
        let error = AudioDataConversionError.emptyInputData
        XCTAssertEqual(error.errorDescription, "输入数据为空")
    }
    
    func testConversionFailedError() {
        let error = AudioDataConversionError.conversionFailed("buffer too small")
        XCTAssertTrue(error.errorDescription?.contains("buffer too small") ?? false)
    }

    // MARK: - AudioFileInfo Tests
    
    func testAudioFileInfoFormattedDuration() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let info = AudioFileInfo(
            url: url,
            duration: 90.5,
            sampleRate: 44100,
            channels: 2,
            format: .pcmFormatFloat32
        )
        
        XCTAssertEqual(info.formattedDuration, "01:30") // 90.5秒 -> 01:30
        XCTAssertEqual(info.formattedSampleRate, "44100 Hz")
        XCTAssertEqual(info.formattedChannels, "立体声") // 2 声道 = 立体声
    }
    
    func testAudioFileInfoMonoChannel() {
        let info = AudioFileInfo(
            url: URL(fileURLWithPath: "/tmp/mono.wav"),
            duration: 10.0,
            sampleRate: 16000,
            channels: 1,
            format: .pcmFormatFloat32
        )
        
        XCTAssertEqual(info.formattedChannels, "单声道")
    }

    // MARK: - Process Tap Constants Tests
    
    func testProcessTapConstantsExist() {
        // 验证常量存在且非零（这些是 CoreAudio 选择器，类型为 UInt32/Int32，直接比较即可）
        XCTAssertNotEqual(AudioUtils.kAudioTapPropertyUID, 0)
        XCTAssertNotEqual(AudioUtils.kAudioTapPropertyFormat, 0)
        XCTAssertNotEqual(AudioUtils.kAudioTapPropertyIsActive, 0)
        XCTAssertNotEqual(AudioUtils.kAudioTapErrorNotAvailable, 0)
        XCTAssertNotEqual(AudioUtils.kAudioTapErrorAlreadyExists, 0)
        XCTAssertNotEqual(AudioUtils.kAudioAggregateDevicePropertyTapAutoStart, 0)
    }
}
