// ScreenCaptureAudioRecorder stub — 文件已被移除，保留占位避免编译错误
// TODO: 清理 pbxproj 中的引用

import Foundation
import AVFoundation

/// 占位类型 — 功能已移除或重构
@available(macOS 14.4, *)
final class ScreenCaptureAudioRecorder: BaseAudioRecorder {
    override init(mode: RecordingMode) {
        super.init(mode: mode)
    }
    override func startRecording() {
        logger.warning("ScreenCaptureAudioRecorder 已废弃")
    }
    override func stopRecording() {
        super.stopRecording()
    }
}
