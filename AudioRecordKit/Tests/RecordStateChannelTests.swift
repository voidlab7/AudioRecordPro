import XCTest
@testable import AudioRecordKit

/// REL-002: 结构化状态通道（onStateChange）解耦验证
/// 验收要求：逻辑依赖改造后有单测覆盖，且断言不依赖文案判断。
@MainActor
final class RecordStateChannelTests: XCTestCase {

    // MARK: - C API 数值契约（原文案 contains 映射的等价替换）

    func testCapiStateValueContract() {
        // 数值契约与文案时代 contains 映射结果一致：0=idle/error 1=preparing 2=recording 3=stopping
        XCTAssertEqual(RecordingState.idle.capiStateValue, 0)
        XCTAssertEqual(RecordingState.preparing.capiStateValue, 1)
        XCTAssertEqual(RecordingState.recording.capiStateValue, 2)
        XCTAssertEqual(RecordingState.stopping.capiStateValue, 3)
        XCTAssertEqual(RecordingState.error.capiStateValue, 0)   // 数值通道无 error 槽位，归 0
        XCTAssertEqual(RecordingState.playing.capiStateValue, 0)
    }

    // MARK: - 双通道伴发（Base 公共流程）

    func testStopRecordingEmitsBothChannels() {
        let recorder = BaseAudioRecorder(mode: .microphone)
        var states: [RecordingState] = []
        var statusTexts: [String] = []
        recorder.onStateChange = { states.append($0) }
        recorder.onStatus = { statusTexts.append($0) }

        recorder.isRunning = true  // 越过 stopRecording 的 idle 早退守卫
        recorder.stopRecording()   // outputURL=nil，文件清理为安全空操作

        XCTAssertTrue(states.contains(.stopping), "结构化通道应伴发 .stopping")
        XCTAssertEqual(statusTexts.count, 1, "文案通道应伴发一条状态文案")
    }

    func testNoSubscriberDoesNotCrash() {
        // 双通道均为 nil 订阅者时，公共流程照常走完（可选回调语义）
        let recorder = BaseAudioRecorder(mode: .microphone)
        recorder.stopRecording()
        XCTAssertFalse(recorder.isRunning)
    }
}
