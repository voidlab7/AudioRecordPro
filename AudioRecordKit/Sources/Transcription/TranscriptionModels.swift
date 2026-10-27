import Foundation

// MARK: - 转写数据模型（FEAT-001 S1）

/// 转写分段（带时间戳，来源 Apple 引擎 audioTimeRange 属性）
public struct TranscriptSegment: Codable, Equatable {
    /// 段落起始时间（秒）
    public var start: TimeInterval
    /// 段落结束时间（秒）
    public var end: TimeInterval
    /// 段落文本
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// 完整转写文稿
public struct Transcript: Codable, Equatable {
    /// BCP-47 语言标识（如 zh-CN）
    public var locale: String
    /// 引擎名（如 AppleSpeechTranscriber）
    public var engine: String
    /// 转写完成时间
    public var createdAt: Date
    /// 时间轴分段
    public var segments: [TranscriptSegment]
    /// 全文（分段文本拼接；非 CJK 语言段间补空格）
    public var fullText: String

    /// 该语言分段拼接是否需要空格（CJK 无词间空格）
    public static func joinsWithSpace(locale: String) -> Bool {
        let lang = locale.lowercased().prefix(2)
        return !["zh", "ja", "ko", "th"].contains(lang)
    }

    public init(locale: String, engine: String, createdAt: Date = Date(),
                segments: [TranscriptSegment], fullText: String? = nil) {
        self.locale = locale
        self.engine = engine
        self.createdAt = createdAt
        self.segments = segments
        if let fullText {
            self.fullText = fullText
        } else {
            let separator = Self.joinsWithSpace(locale: locale) ? " " : ""
            self.fullText = segments.map(\.text).filter { !$0.isEmpty }.joined(separator: separator)
        }
    }
}

/// 实时转写增量更新（volatile = 引擎中间结果，可能被后续定稿替换）
public struct LiveTranscriptUpdate: Sendable {
    /// 已定稿文本（累积）
    public let finalized: String
    /// 当前未定稿文本（灰显展示，停止说话后被定稿替换）
    public let volatileText: String

    public init(finalized: String, volatileText: String) {
        self.finalized = finalized
        self.volatileText = volatileText
    }
}

// MARK: - 转写错误

public enum TranscriptionError: Error, LocalizedError {
    case engineUnavailable
    case unsupportedLocale(String)
    case noCompatibleAudioFormat
    case notAnArlockFile(URL)
    case decryptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            return "SpeechTranscriber 在此设备不可用（需要 macOS 26+）".localized  // REL-003
        case .unsupportedLocale(let id):
            return "语言 \"%@\" 不被转写引擎支持".localized(id)  // REL-003
        case .noCompatibleAudioFormat:
            return "无兼容音频格式可用".localized  // REL-003
        case .notAnArlockFile(let url):
            return "不是加密录音文件: %@".localized(url.lastPathComponent)  // REL-003
        case .decryptFailed(let why):
            return "解密失败: %@".localized(why)  // REL-003
        }
    }
}
