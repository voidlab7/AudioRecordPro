import Foundation
import AVFoundation
// Kit 与 App 由 build-app.sh 平铺同模块编译，Kit 类型直接可见（勿 import AudioRecordKit）

// MARK: - 转写服务（FEAT-001 S1）
//
// 职责：
// 1. 文件转写（.arlock 感知：解密 → 临时 m4a → 引擎 → 清理）
// 2. 转写文稿持久化（.arlock 旁 <uuid>.atranscript.json）
// 3. 录音实时转写协调（LiveTranscriptionCoordinator）

final class TranscriptionService {

    static let shared = TranscriptionService()
    private let logger = Logger.shared

    private init() {}

    // MARK: - 文件转写

    /// 转写一条录音（.arlock 自动解密；普通音频直接转）
    /// - Parameter progress: 0~1 进度（后台线程回调）
    func transcribeRecording(
        at url: URL,
        localeID: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Transcript {
        var workingURL = url
        var tempURL: URL?

        if url.pathExtension.lowercased() == AudioCryptoConfig.fileExtension {
            let (audioData, _) = try AudioFileEncryptor.shared.decrypt(from: url)
            let tmp = FileManager.default.temporaryDirectory
                .appending(path: "transcribe-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            try audioData.write(to: tmp, options: .atomic)
            tempURL = tmp
            workingURL = tmp
            logger.info("转写前置：解密 \(url.lastPathComponent) → 临时 m4a")
        }
        defer { if let t = tempURL { try? FileManager.default.removeItem(at: t) } }

        guard #available(macOS 26.0, *) else {
            throw TranscriptionError.engineUnavailable
        }
        let engine = AppleSpeechEngine()
        let transcript = try await engine.transcribeFile(at: workingURL, localeID: localeID, progress: progress)

        // 转写完成即持久化到录音旁
        try? save(transcript, for: url)
        return transcript
    }

    // MARK: - 文稿持久化

    /// 转写文稿的落盘位置（与录音同目录同名，扩展 .atranscript.json）
    func transcriptURL(for recordingURL: URL) -> URL {
        recordingURL.deletingPathExtension().appendingPathExtension("atranscript.json")
    }

    func save(_ transcript: Transcript, for recordingURL: URL) throws {
        let url = transcriptURL(for: recordingURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        try data.write(to: url, options: .atomic)
        logger.info("转写文稿已保存: \(url.lastPathComponent)")
    }

    func loadTranscript(for recordingURL: URL) -> Transcript? {
        let url = transcriptURL(for: recordingURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Transcript.self, from: Data(contentsOf: url))
    }
}

// MARK: - 实时转写协调器（录音中 buffer → Apple 引擎 → live 文本）
// @MainActor：onAudioBuffer 等 recorder 回调属性是主线程隔离的，绑定/解绑必须回主线程

@available(macOS 26.0, *)
@MainActor
final class LiveTranscriptionCoordinator {

    static let shared = LiveTranscriptionCoordinator()
    private let logger = Logger.shared

    private init() {}

    // MARK: 状态

    private var session: AppleSpeechEngine.LiveTranscriptionSession?
    private var boundRecorder: AudioRecorderProtocol?
    /// finish 后暂存的文稿（FIX-012 双向握手：与 transcriptDestination 谁后到谁触发落盘）
    private(set) var collectedTranscript: Transcript?
    /// 加密管线登记的 .arlock 落点（生成 UUID 后立即登记，FIX-012）
    private var transcriptDestination: URL?
    private var isFinishing = false

    // MARK: 对外回调（主线程）

    /// (finalized, volatile) — volatile 为引擎中间结果（灰显），定稿后并入 finalized
    var onLiveText: ((String, String) -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - 生命周期

    /// 预热会话（点开始录制时调用；资产就绪前的 buffer 由 AsyncStream 缓冲，不丢）
    /// locale 跟随文稿面板的语言偏好（FEAT-001 S2.5：录英文演讲等场景）
    func start() {
        // FIX-012：新一录先清旧落点——上一次管线失败可能残留旧 UUID 落点，
        // 不清会让本次文稿错写进旧录音旁（guard 前清，快速重录也覆盖）
        transcriptDestination = nil
        guard session == nil, !isFinishing else { return }
        collectedTranscript = nil
        let preferred = TranscriptPanelView.preferredLocaleID
        Task {
            do {
                let newSession = try await AppleSpeechEngine.LiveTranscriptionSession.start(localeID: preferred)
                newSession.onUpdate = { [weak self] update in
                    DispatchQueue.main.async {
                        self?.onLiveText?(update.finalized, update.volatileText)
                    }
                }
                session = newSession
                // 若录制器已先绑定，补挂 buffer 旁路
                if let recorder = boundRecorder {
                    attach(session: newSession, to: recorder)
                }
                logger.info("实时转写会话已就绪 locale=\(newSession.localeID)")
            } catch {
                logger.error("实时转写会话启动失败: \(error.localizedDescription)")
                DispatchQueue.main.async { self.onError?(error.localizedDescription) }
            }
        }
    }

    /// 绑定录制器的 PCM 旁路（onRecordingStarted 时调用；多录制器只取第一个）
    func bind(recorder: AudioRecorderProtocol) {
        boundRecorder = recorder
        if let session {
            attach(session: session, to: recorder)
        }
    }

    private func attach(session: AppleSpeechEngine.LiveTranscriptionSession, to recorder: AudioRecorderProtocol) {
        recorder.onAudioBuffer = { [weak session] buffer in
            session?.append(buffer)
        }
    }

    /// 结束并收集文稿（点停止时调用）；结果暂存 collectedTranscript，等加密管线落盘
    func finishAndCollect() {
        guard let session = session else {
            boundRecorder?.onAudioBuffer = nil
            boundRecorder = nil
            return
        }
        isFinishing = true
        Task {
            defer {
                self.isFinishing = false
                self.session = nil
            }
            boundRecorder?.onAudioBuffer = nil
            boundRecorder = nil
            do {
                let transcript = try await session.finish()
                await MainActor.run {
                    self.collectedTranscript = transcript
                    self.onLiveText?(transcript.fullText, "")
                    self.flushTranscriptIfReady()
                }
                logger.info("实时转写收集完成：\(transcript.fullText.count) 字")
            } catch {
                logger.error("实时转写收集失败: \(error.localizedDescription)")
                await MainActor.run { self.onError?(error.localizedDescription) }
            }
        }
    }

    // MARK: FIX-012 双向握手（消除"管线先读、finish 后写"的落盘竞态）

    /// 加密管线在生成 .arlock 后立即登记落点；与 finish 谁后完成谁触发落盘
    func registerTranscriptDestination(_ url: URL) {
        transcriptDestination = url
        flushTranscriptIfReady()
    }

    /// 文稿与落点齐备才落盘；两侧幂等调用，先到先存、后到触发
    private func flushTranscriptIfReady() {
        guard let transcript = collectedTranscript, let url = transcriptDestination else { return }
        transcriptDestination = nil
        let chars = transcript.fullText.count
        let locale = transcript.locale
        // 文件 IO 挪出主线程；落盘成败只影响旁车文稿，不拦录音主流程
        Task.detached(priority: .utility) {
            try? TranscriptionService.shared.save(transcript, for: url)
            UXEventLog.shared.module("Transcription", "saved", detail: [
                "chars": chars, "locale": locale, "via": "handshake",
            ])
        }
    }

    /// 放弃当前会话（录制失败/空录音拦截时调用）
    func cancel() {
        boundRecorder?.onAudioBuffer = nil
        boundRecorder = nil
        session = nil
        collectedTranscript = nil
        transcriptDestination = nil
    }
}
