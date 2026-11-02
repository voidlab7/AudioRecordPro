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

    // MARK: - FIX-021: 混音后样本电平取样

    func testCalculateAudioLevelFromSamplesSilence() {
        let result = AudioUtils.calculateAudioLevel(fromSamples: [Float](repeating: 0, count: 1024))
        XCTAssertEqual(result.maxLevel, 0, accuracy: 1e-6)
        XCTAssertEqual(result.rmsLevel, 0, accuracy: 1e-6)
        XCTAssertEqual(result.normalizedLevel, 0, accuracy: 1e-6)
    }

    func testCalculateAudioLevelFromSamplesMicOnlySignal() {
        // mic-only 场景（老板 10-30/10-31 两轮实测）：系统侧全零 + mic 混入样本有信号
        // → maxLevel/normalizedLevel 必须非零。修复前电平只看系统侧全零，
        // 波形贴中线、DB 表不动、录音还被无效守卫误删
        var samples = [Float](repeating: 0, count: 1024)
        for i in stride(from: 0, to: 1024, by: 2) {
            samples[i] = 0.5
            samples[i + 1] = -0.5
        }
        let result = AudioUtils.calculateAudioLevel(fromSamples: samples)
        XCTAssertEqual(result.maxLevel, 0.5, accuracy: 1e-6)
        XCTAssertGreaterThan(result.normalizedLevel, 0)
    }

    func testCalculateAudioLevelFromSamplesMatchesBufferListVersion() {
        // FIX-021 两个口径必须一致：同一份数据，fromSamples 与 AudioBufferList 版结果相同
        var samples = [Float](repeating: 0, count: 512)
        for i in 0..<512 { samples[i] = sin(Float(i) * 0.1) * 0.3 }
        let fromSamples = AudioUtils.calculateAudioLevel(fromSamples: samples)
        let byteSize = samples.count * MemoryLayout<Float>.size
        let frameCount = samples.count / 2
        samples.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else {
                XCTFail("样本缓冲指针为空")
                return
            }
            let bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(byteSize),
                    mData: base))
            let fromList = AudioUtils.calculateAudioLevel(from: bufferList, frameCount: UInt32(frameCount))
            XCTAssertEqual(fromSamples.maxLevel, fromList.maxLevel, accuracy: 1e-6)
            XCTAssertEqual(fromSamples.normalizedLevel, fromList.normalizedLevel, accuracy: 1e-6)
        }
    }

    func testMixMicIfNeededInjectsAtFortyPercent_FIX021() {
        // 混音口径回归：0 系统 + 0.6 mic → 0.6×0.4=0.24；0.5 系统 + 0 mic → 0.3
        guard #available(macOS 14.4, *) else {
            XCTFail("AudioCallbackHandler 要求 macOS 14.4+")
            return
        }
        let handler = AudioCallbackHandler()
        handler.setMicMixProvider { _ in
            [Float](repeating: 0.6, count: 8)
        }
        var sys = [Float](repeating: 0.5, count: 8)
        let byteSize = sys.count * MemoryLayout<Float>.size
        sys.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else {
                XCTFail("系统缓冲指针为空")
                return
            }
            let bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(byteSize),
                    mData: base))
            guard let mixed = handler.mixMicIfNeeded(from: bufferList, frameCount: 4) else {
                XCTFail("provider 就绪时应产出混音样本")
                return
            }
            XCTAssertEqual(mixed.count, 8)
            XCTAssertEqual(mixed[0], 0.5 * 0.6 + 0.6 * 0.4, accuracy: 1e-6)
            // 混音峰值高于纯系统侧峰值（0.5）——mic-only 守卫误删的根因场景
            XCTAssertGreaterThan(mixed.map { abs($0) }.max() ?? 0, 0.5)
        }
    }

    func testMixMicIfNeededNilWhenProviderOff_FIX021() {
        guard #available(macOS 14.4, *) else {
            XCTFail("AudioCallbackHandler 要求 macOS 14.4+")
            return
        }
        let handler = AudioCallbackHandler()
        // 未设置 provider（开关关/引擎未跑）→ 本帧不注入
        var sys = [Float](repeating: 0.5, count: 8)
        let byteSize = sys.count * MemoryLayout<Float>.size
        sys.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(byteSize),
                    mData: base))
            XCTAssertNil(handler.mixMicIfNeeded(from: bufferList, frameCount: 4))
        }
    }

    func testLevelSamplingPrefersMixedSamples_FIX021() {
        // 端到端：本帧有混音缓存时，峰值回调必须报告混音后峰值（0.8），而非系统侧全零
        guard #available(macOS 14.4, *) else {
            XCTFail("AudioCallbackHandler 要求 macOS 14.4+")
            return
        }
        let handler = AudioCallbackHandler()
        var receivedPeak: Float?
        let reported = expectation(description: "peak reported")
        handler.setPeakLevelCallback { peak in
            receivedPeak = peak
            reported.fulfill()
        }
        var sys = [Float](repeating: 0, count: 8)
        let byteSize = sys.count * MemoryLayout<Float>.size
        sys.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else {
                XCTFail("系统缓冲指针为空")
                return
            }
            let bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(byteSize),
                    mData: base))
            handler.lastMixedSamples = [Float](repeating: 0.8, count: 8)
            handler.calculateAndReportLevel(from: bufferList, frameCount: 4)
            // 一次性消费后清空
            XCTAssertNil(handler.lastMixedSamples)
        }
        waitForExpectations(timeout: 2)
        XCTAssertEqual(receivedPeak ?? 0, 0.8, accuracy: 1e-6)
    }
}
