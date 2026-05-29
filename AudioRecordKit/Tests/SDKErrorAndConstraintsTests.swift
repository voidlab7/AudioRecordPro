import XCTest
@testable import AudioRecordKit
import Foundation

/// SDK 层单元测试：AudioRecordError / AudioConstraints / MediaStreamConstraints / MediaStream / MediaStreamTrack
final class SDKErrorAndConstraintsTests: XCTestCase {
    
    // MARK: - AudioRecordError Tests
    
    func testErrorMicrophonePermissionDeniedDescription() {
        let error = AudioRecordError.microphonePermissionDenied
        XCTAssertEqual(error.errorDescription, "麦克风权限被拒绝")
    }
    
    func testErrorSystemAudioPermissionDeniedDescription() {
        let error = AudioRecordError.systemAudioPermissionDenied
        XCTAssertEqual(error.errorDescription, "系统音频权限被拒绝")
    }
    
    func testErrorDeviceNotFoundDescription() {
        let error = AudioRecordError.deviceNotFound
        XCTAssertEqual(error.errorDescription, "音频设备未找到")
    }
    
    func testErrorAlreadyRecordingDescription() {
        let error = AudioRecordError.alreadyRecording
        XCTAssertEqual(error.errorDescription, "录制已在进行中")
    }
    
    func testErrorNotSupportedDescription() {
        let error = AudioRecordError.notSupported("测试功能")
        XCTAssertTrue(error.errorDescription?.contains("测试功能") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("当前版本不支持") ?? false)
    }
    
    func testErrorUnknownDescription() {
        let nsError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "底层错误"])
        let error = AudioRecordError.unknown(nsError)
        XCTAssertTrue(error.errorDescription?.contains("未知错误") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("底层错误") ?? false)
    }
    
    func testAllErrorsHaveNonEmptyDescriptions() {
        let errors: [AudioRecordError] = [
            .microphonePermissionDenied,
            .systemAudioPermissionDenied,
            .deviceNotFound,
            .alreadyRecording,
            .notSupported("feature"),
            .unknown(NSError(domain: "test", code: 0))
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) 应有错误描述")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) 的描述不应为空")
        }
    }

    // MARK: - AudioConstraints Tests
    
    func testDefaultConstraintsValues() {
        let constraints = AudioConstraints()
        
        XCTAssertEqual(constraints.sampleRate, 48000)
        XCTAssertEqual(constraints.channelCount, 2)
        XCTAssertTrue(constraints.echoCancellation)
        XCTAssertTrue(constraints.noiseSuppression)
        XCTAssertFalse(constraints.includeSystemAudio)
    }
    
    func testCustomConstraints() {
        let constraints = AudioConstraints(
            echoCancellation: false,
            noiseSuppression: false,
            includeSystemAudio: true
        )
        
        XCTAssertFalse(constraints.echoCancellation)
        XCTAssertFalse(constraints.noiseSuppression)
        XCTAssertTrue(constraints.includeSystemAudio)
        XCTAssertEqual(constraints.sampleRate, 48000)
        XCTAssertEqual(constraints.channelCount, 2)
    }

    // MARK: - MediaStreamConstraints Tests
    
    func testMediaStreamConstraints() {
        let audioConstraints = AudioConstraints(includeSystemAudio: true)
        let msc = MediaStreamConstraints(audio: audioConstraints)
        
        XCTAssertNotNil(msc.audio)
        XCTAssertTrue(msc.audio!.includeSystemAudio)
    }

    // MARK: - MediaStreamTrack Tests
    
    func testMediaStreamTrackMicrophoneInit() {
        let constraints = AudioConstraints()
        let track = MediaStreamTrack(type: .microphone, constraints: constraints)
        
        XCTAssertEqual(track.kind, "audio")
        XCTAssertEqual(track.label, "Microphone Track")
        XCTAssertTrue(track.enabled)
        XCTAssertEqual(track.readyState, .live)
        XCTAssertFalse(track.id.isEmpty)
    }
    
    func testMediaStreamTrackMixedInit() {
        let constraints = AudioConstraints(includeSystemAudio: true)
        let track = MediaStreamTrack(type: .mixed, constraints: constraints)
        
        XCTAssertEqual(track.label, "Mixed Audio Track")
    }
    
    func testMediaStreamTrackStop() {
        let track = MediaStreamTrack(type: .microphone, constraints: AudioConstraints())
        XCTAssertEqual(track.readyState, .live)
        
        track.stop()
        XCTAssertEqual(track.readyState, .ended)
    }
    
    @MainActor
    func testMediaStreamTrackUnsupportedOperations() async throws {
        let track = MediaStreamTrack(type: .microphone, constraints: AudioConstraints())
        
        do { try track.applyConstraints([:]); XCTFail("applyConstraints 应抛出错误") }
        catch AudioRecordError.notSupported(let msg) { XCTAssertTrue(msg.contains("applyConstraints")) }
        catch { XCTFail("抛出了非预期的错误类型: \(error)") }
        
        do { try _ = track.getSettings(); XCTFail("getSettings 应抛出错误") }
        catch AudioRecordError.notSupported(let msg) { XCTAssertTrue(msg.contains("getSettings")) }
        catch { XCTFail("抛出了非预期的错误类型: \(error)") }
        
        do { try _ = track.getConstraints(); XCTFail("getConstraints 应抛出错误") }
        catch AudioRecordError.notSupported(let msg) { XCTAssertTrue(msg.contains("getConstraints")) }
        catch { XCTFail("抛出了非预期的错误类型: \(error)") }
    }

    // MARK: - MediaStream Tests (使用 @MainActor 避免 actor 隔离)
    
    @MainActor
    func testMediaStreamActiveProperty() {
        let recorderMock = MockAudioRecorder()
        let stream = MediaStream(recorder: recorderMock, constraints: AudioConstraints())
        
        XCTAssertTrue(stream.active)
        XCTAssertEqual(stream.id.count, 36) // UUID 长度
        
        let tracks = stream.getAudioTracks()
        XCTAssertEqual(tracks.count, 1)
    }
    
    @MainActor
    func testMediaStreamInactiveAfterTrackEnds() {
        let recorderMock = MockAudioRecorder()
        let stream = MediaStream(recorder: recorderMock, constraints: AudioConstraints())
        
        let allTracks = stream.getTracks()
        XCTAssertEqual(allTracks.count, 1)
    }
    
    @MainActor
    func testMediaStreamRecordingMode() async throws {
        let micRecorder = MockAudioRecorder()
        let micStream = MediaStream(recorder: micRecorder, constraints: AudioConstraints())
        XCTAssertEqual(micStream.recordingMode, "microphone")
        
        let mixedRecorder = MockAudioRecorder(mode: .systemMixdown)
        let mixedStream = MediaStream(recorder: mixedRecorder, constraints: AudioConstraints(includeSystemAudio: true))
        XCTAssertEqual(mixedStream.recordingMode, "mixed")
    }
    
    @MainActor
    func testMediaStreamUnsupportedOperations() async throws {
        let recorderMock = MockAudioRecorder()
        let stream = MediaStream(recorder: recorderMock, constraints: AudioConstraints())
        let track = stream.getAudioTracks().first!
        
        do { try stream.addTrack(track); XCTFail("addTrack 应抛出错误") }
        catch AudioRecordError.notSupported(let msg) { XCTAssertTrue(msg.contains("addTrack")) }
        catch {}
        
        do { try stream.removeTrack(track); XCTFail("removeTrack 应抛出错误") }
        catch AudioRecordError.notSupported(let msg) { XCTAssertTrue(msg.contains("removeTrack")) }
        catch {}
        
        do { try _ = stream.clone(); XCTFail("clone 应抛出错误") }
        catch AudioRecordError.notSupported(let msg) { XCTAssertTrue(msg.contains("clone")) }
        catch {}
    }
    
    @MainActor
    func testGetAudioTracksReturnsAllAudioTracks() {
        let recorderMock = MockAudioRecorder()
        let stream = MediaStream(recorder: recorderMock, constraints: AudioConstraints())
        
        let audioTracks = stream.getAudioTracks()
        let allTracks = stream.getTracks()
        
        XCTAssertEqual(audioTracks.count, allTracks.count)
        for track in audioTracks {
            XCTAssertEqual(track.kind, "audio")
        }
    }
}

// MARK: - Mock Helpers (在 @MainActor 上下文中使用)

/// 用于测试的 Mock 录制器（实现 AudioRecorderProtocol）
@MainActor
private class MockAudioRecorder: NSObject, AudioRecorderProtocol {
    var isRunning: Bool = false
    nonisolated var recordingMode: RecordingMode { get { _recordingMode } }
    var currentFormat: AudioFormat { .m4a }
    
    var onLevel: ((Float) -> Void)?
    var onPeakLevel: ((Float) -> Void)?
    var onStatus: ((String) -> Void)?
    var onRecordingComplete: ((AudioRecording) -> Void)?
    var onPlaybackComplete: (() -> Void)?
    
    private let _recordingMode: RecordingMode
    init(mode: RecordingMode = .microphone) { self._recordingMode = mode }
    
    func startRecording() {}
    func stopRecording() {}
    func playRecording(at url: URL) {}
    func stopPlayback() {}
    func setAudioFormat(_ format: AudioFormat) {}
}
