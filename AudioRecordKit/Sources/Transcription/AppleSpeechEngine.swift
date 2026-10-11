import Foundation
import AVFoundation
import Speech
import CoreMedia

// MARK: - Apple SpeechAnalyzer 引擎（FEAT-001 S1，macOS 26+）
//
// API 用法逐行对照 yap CLI（finnvoor/yap，S0 实测 12.5min→6.97s、中文 CER≈1%）：
// - 文件转写：reserve(locale) → assetInstallationRequest → SpeechAnalyzer.start(inputAudioFile:finishAfterFile:)
// - 实时流：AsyncStream<AnalyzerInput> + AVAudioConverter 转 bestAvailableAudioFormat
// - 注：yap 实测不显式调 transcriber.allocate()，reserve + install 即可（与方案 §4.2 初稿顺序有出入，以实测为准）

@available(macOS 26.0, *)
public final class AppleSpeechEngine: TranscriptionEngine {

    public let engineName = "AppleSpeechTranscriber"

    public static func isSupported() -> Bool {
        if #available(macOS 26.0, *) {
            return SpeechTranscriber.isAvailable
        }
        return false
    }

    // MARK: - Locale 解析

    /// 自动选语言：preferred → 系统语言 → zh-CN → 首个支持语言
    public static func resolveLocale(preferred: String?) async throws -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        guard !supported.isEmpty else {
            throw TranscriptionError.engineUnavailable
        }

        func matches(_ locale: Locale, _ id: String) -> Bool {
            locale.identifier(.bcp47).lowercased() == id.lowercased()
                || locale.identifier.lowercased() == id.lowercased()
        }

        if let preferred = preferred,
           let hit = supported.first(where: { matches($0, preferred) }) {
            return hit
        }
        let current = Locale.current
        if let hit = supported.first(where: { matches($0, current.identifier) }) {
            return hit
        }
        if let hit = supported.first(where: { matches($0, "zh-CN") }) {
            return hit
        }
        return supported[0]
    }

    // MARK: - 资产准备（reserve + 按需安装，yap 同款）

    private static func prepareAssets(for locale: Locale, modules: [any SpeechModule]) async throws {
        // 释放残留的保留位（yap 实测：不释放可能卡 AssetInventory 配额）
        for reserved in await AssetInventory.reservedLocales {
            await AssetInventory.release(reservedLocale: reserved)
        }
        try await AssetInventory.reserve(locale: locale)

        let installed = await SpeechTranscriber.installedLocales
        let installedIDs = installed.map { $0.identifier(.bcp47).lowercased() }
        if !installedIDs.contains(locale.identifier(.bcp47).lowercased()) {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
        }
    }

    // MARK: - 文件转写

    public func transcribeFile(
        at url: URL,
        localeID: String?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Transcript {
        guard Self.isSupported() else { throw TranscriptionError.engineUnavailable }

        let locale = try await Self.resolveLocale(preferred: localeID)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        let modules: [any SpeechModule] = [transcriber]
        try await Self.prepareAssets(for: locale, modules: modules)

        let analyzer = SpeechAnalyzer(modules: modules)
        let audioFile = try AVAudioFile(forReading: url)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        // MP3 缺帧坑不处理：App 内输入只会是 .arlock 解出的 m4a 或 wav（yap 仅对畸形 MP3 转装）
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

        var allSegments: [TranscriptSegment] = []
        for try await result in transcriber.results {
            // 时间戳在 AttributedString 的 run 属性上（yap 同款取法），按 >1.5s 停顿分段
            allSegments.append(contentsOf: Self.makeSegments(from: result.text, cjk: Self.isCJK(locale)))
            if let progress {
                let done = result.resultsFinalizationTime.seconds
                let progressValue = duration > 0 ? min(max(done / duration, 0), 1) : 1
                progress(progressValue)
            }
        }

        return Transcript(
            locale: locale.identifier(.bcp47),
            engine: engineName,
            segments: allSegments
        )
    }

    // MARK: - 分段辅助

    /// CJK 语言（拼接不加空格）；其他语言 run 之间补空格
    private static func isCJK(_ locale: Locale) -> Bool {
        let lang = locale.language.languageCode?.identifier ?? ""
        return ["zh", "ja", "ko"].contains(lang)
    }

    /// AttributedString → 分段：run 的 audioTimeRange 按停顿 >1.5s 切段（yap splitAtTimeGaps 简化版）
    private static func makeSegments(from attributed: AttributedString, cjk: Bool) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var current: TranscriptSegment?
        let joiner = cjk ? "" : " "

        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            guard let range = run.audioTimeRange else {
                // 无时间戳文本并入当前段
                current?.text += joiner + text
                continue
            }
            let start = range.start.seconds
            let end = range.end.seconds

            if var cur = current, start - cur.end <= 1.5 {
                cur.end = end
                cur.text += joiner + text
                current = cur
            } else {
                if let cur = current { segments.append(cur) }
                current = TranscriptSegment(start: start, end: end, text: text)
            }
        }
        if let cur = current { segments.append(cur) }
        return segments
    }

    // MARK: - 实时转写会话

    /// 录音实时出字会话：recorder 的音频 buffer 逐个 append，volatile/final 通过 onUpdate 回调
    public final class LiveTranscriptionSession: @unchecked Sendable {

        public let localeID: String
        /// (finalized, volatile) 回调，可能在内部结果线程触发，消费方自行 hop 主线程
        public var onUpdate: (@Sendable (LiveTranscriptUpdate) -> Void)?

        private let transcriber: SpeechTranscriber
        private let analyzer: SpeechAnalyzer
        private let continuation: AsyncStream<AnalyzerInput>.Continuation
        private let targetFormat: AVAudioFormat
        private var converter: AVAudioConverter?
        private var converterLock = NSLock()
        private var stateLock = NSLock()
        private var finalizedText = ""
        private var volatileText = ""
        private var resultsTask: Task<Void, Error>?

        private init(
            transcriber: SpeechTranscriber,
            analyzer: SpeechAnalyzer,
            continuation: AsyncStream<AnalyzerInput>.Continuation,
            targetFormat: AVAudioFormat,
            locale: Locale
        ) {
            self.transcriber = transcriber
            self.analyzer = analyzer
            self.continuation = continuation
            self.targetFormat = targetFormat
            self.localeID = locale.identifier(.bcp47)
        }

        /// 启动会话（含资产准备，首次可能拉语言资产下载）
        public static func start(localeID: String?) async throws -> LiveTranscriptionSession {
            let locale = try await AppleSpeechEngine.resolveLocale(preferred: localeID)
            // volatileResults：录音中出中间结果；audioTimeRange：段落时间戳
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
            let modules: [any SpeechModule] = [transcriber]
            try await AppleSpeechEngine.prepareAssets(for: locale, modules: modules)

            let analyzer = SpeechAnalyzer(modules: modules)
            guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
                throw TranscriptionError.noCompatibleAudioFormat
            }

            let (inputStream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            try await analyzer.start(inputSequence: inputStream)

            let session = LiveTranscriptionSession(
                transcriber: transcriber,
                analyzer: analyzer,
                continuation: continuation,
                targetFormat: targetFormat,
                locale: locale
            )

            // 结果消费循环：volatile（analyzer.volatileRange 内的预览）替换预览区，final 累积
            // 注：SDK 无 Result.isVolatile——判定 = result.range 与 analyzer.volatileRange 相交（actor 属性，需 await）
            // 强捕获 session：task 运行期短暂自持，finish() await 其结束后释放
            session.resultsTask = Task {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let vr = await session.analyzer.volatileRange
                    let isVolatile: Bool = {
                        guard let vr, vr.isValid, vr.duration.seconds > 0 else { return false }
                        let inter = CMTimeRangeGetIntersection(result.range, otherRange: vr)
                        return inter.isValid && inter.duration.seconds > 0
                    }()
                    let update = session.storeResult(text: text, isVolatile: isVolatile)
                    session.onUpdate?(update)
                }
            }
            return session
        }

        /// 追加一段录音 buffer（音频回调线程调用，线程安全）
        /// - Note: 内部 AVAudioConverter 把录音格式转到引擎目标格式
        public func append(_ buffer: AVAudioPCMBuffer) {
            guard buffer.frameLength > 0 else { return }

            converterLock.lock()
            if converter == nil || converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            }
            let converter = self.converter
            converterLock.unlock()

            guard let converter else { return }

            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 1024
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var error: NSError?
            nonisolated(unsafe) var consumed = false
            nonisolated(unsafe) let source = buffer
            converter.convert(to: converted, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return source
            }

            guard error == nil, converted.frameLength > 0 else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }

        /// 结束转写（停止录音时调用）；等待剩余结果定稿后返回完整文稿
        public func finish() async throws -> Transcript {
            continuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try? await resultsTask?.value

            let final = snapshotFullText()
            return Transcript(
                locale: localeID,
                engine: "AppleSpeechTranscriber(live)",
                segments: [TranscriptSegment(start: 0, end: 0, text: final)],
                fullText: final
            )
        }

        /// 同步读取当前全文（NSLock 不可在 async 上下文直接调用，收敛到同步方法）
        private func snapshotFullText() -> String {
            stateLock.lock()
            defer { stateLock.unlock() }
            return finalizedText + (volatileText.isEmpty ? "" : volatileText)
        }

        /// 存入一条结果并返回当前快照（同步方法，规避 NSLock-in-async 警告）
        func storeResult(text: String, isVolatile: Bool) -> LiveTranscriptUpdate {
            stateLock.lock()
            defer { stateLock.unlock() }
            if isVolatile {
                volatileText = text
            } else if !text.isEmpty {
                finalizedText += text
                volatileText = ""
            }
            return LiveTranscriptUpdate(finalized: finalizedText, volatileText: volatileText)
        }
    }
}
