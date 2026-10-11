import Foundation
import AVFoundation

// MARK: - 转写引擎协议（FEAT-001 S1）
//
// 双引擎架构的抽象层：
// - AppleSpeechEngine（S1，macOS 26 SpeechAnalyzer）：默认引擎，文件秒转 + 录音实时出字
// - WhisperCppEngine（S4 独立单）：高精模式，词级时间戳
//
// API 用法以 yap CLI（finnvoor/yap）源码为实证基准（S0 已在本机验证通过）。

public protocol TranscriptionEngine: AnyObject {
    /// 引擎显示名（写入 Transcript.engine，供导出 MD 元信息用）
    var engineName: String { get }

    /// 文件转写
    /// - Parameters:
    ///   - url: 音频文件（wav/m4a/mp3 等系统可解码格式）
    ///   - localeID: BCP-47 语言标识（如 "zh-CN"）；nil = 自动选择（系统语言，回退 zh-CN）
    ///   - progress: 进度回调（0~1，基于 resultsFinalizationTime / 音频时长）
    func transcribeFile(
        at url: URL,
        localeID: String?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Transcript
}
