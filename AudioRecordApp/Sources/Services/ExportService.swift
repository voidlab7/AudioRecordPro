import Foundation
import AVFoundation
import AudioToolbox
import AppKit
import UniformTypeIdentifiers

/// 导出服务 (V2.0 → FEAT-007)
/// 导出 = 解密 .arlock → 临时 .m4a → 转码为目标格式 → NSSavePanel 写入
/// FEAT-007: 草稿存在时，导出 = 「原始文件 + 草稿」渲染编辑结果（剪映模型）——
/// 裁剪后导出的就是裁剪后的时长，增益默认计入产物；无草稿走原快速链路。
class ExportService {
    
    static let shared = ExportService()
    private let logger = Logger.shared
    private let fileManager = FileManagerUtils.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// 导出录音文件到指定路径（不弹面板——路径由导出卡片决定）
    /// 修复 BUG：旧版 export() 内部自带 NSSavePanel，与导出卡片的「选择…」面板重复，导致两次弹窗。
    /// - Parameters:
    ///   - arlockURL: .arlock 文件路径
    ///   - outputURL: 目标完整路径（含文件名与扩展名）
    ///   - targetFormat: 目标导出格式
    ///   - completion: (成功: Bool, 输出路径: URL?, 错误: Error?)
    func exportToFile(arlockURL: URL, outputURL: URL, targetFormat: AudioExportFormat, completion: @escaping (Bool, URL?, Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 1. 解密 .arlock → AAC Data
                self.logger.info("导出: 解密 \(arlockURL.lastPathComponent)")
                let (audioData, _) = try AudioFileEncryptor.shared.decrypt(from: arlockURL)

                // 2. 写临时 .m4a（AAC 数据）
                let tempDir = FileManager.default.temporaryDirectory
                let tempUUID = UUID().uuidString
                let tempM4A = tempDir.appendingPathComponent("\(AudioCryptoConfig.TempFilePattern.exportPrefix)\(tempUUID).\(AudioCryptoConfig.TempFilePattern.m4aExtension)")
                try audioData.write(to: tempM4A, options: .atomic)

                // 3. 转码/复制到目标路径
                do {
                    let finalOutputURL = self.normalizeOutputURL(selected: outputURL, format: targetFormat)

                    // FEAT-007: 草稿渲染——有编辑结果时导出「原始+草稿」的渲染产物
                    let draft = EditDraftStore.shared.draft(for: arlockURL)
                    let draftValid = draft.map { self.fileManagerEditDraftValid($0, originalURL: arlockURL) } ?? false

                    if let draft, draftValid, draft.hasRenderableEdits {
                        self.logger.info("导出: 应用草稿渲染 (\(draft.commands.count) 条命令 @\(draft.currentIndex), gain=\(draft.clipGain))")
                        UXEventLog.shared.module("Export", "draft_applied", ok: true,
                                                 detail: ["commands": draft.commands.count,
                                                          "index": draft.currentIndex])
                        // 渲染产物是 PCM WAV；渲染后 M4A 不能再走「已编码直接复制」，统一转码
                        let renderedWav = try Self.renderDraftedAudio(tempM4A: tempM4A, draft: draft)
                        defer { SecureDelete.deleteFile(at: renderedWav) }
                        try self.transcode(inputURL: renderedWav, outputURL: finalOutputURL, format: targetFormat)
                    } else if targetFormat == .m4a {
                        // AAC → M4A 直接复制（已编码，无草稿快速链路）
                        try self.fileManager.copyFile(from: tempM4A, to: finalOutputURL)
                    } else {
                        // 转码
                        try self.transcode(inputURL: tempM4A, outputURL: finalOutputURL, format: targetFormat)
                    }
                    
                    // 清理临时文件
                    SecureDelete.deleteFile(at: tempM4A)
                    
                    self.logger.info("导出成功: \(finalOutputURL.lastPathComponent)")
                    
                    DispatchQueue.main.async {
                        NSWorkspace.shared.selectFile(finalOutputURL.path, inFileViewerRootedAtPath: finalOutputURL.deletingLastPathComponent().path)
                        completion(true, finalOutputURL, nil)
                    }
                } catch {
                    // 清理临时文件
                    SecureDelete.deleteFile(at: tempM4A)
                    self.logger.error("导出失败: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false, nil, error)
                    }
                }
            } catch {
                self.logger.error("导出解密失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, nil, error)
                }
            }
        }
    }
    
    // MARK: - FEAT-007 草稿渲染

    /// 原始文件 + 草稿 → 渲染后临时 WAV。
    /// 解密出的临时 m4a → 全量 PCM → 命令栈重放 → 增益限幅 → float32 WAV 落盘。
    static func renderDraftedAudio(tempM4A: URL, draft: EditDraft) throws -> URL {
        let inputFile = try AVAudioFile(forReading: tempM4A)
        let format = inputFile.processingFormat
        let frameCount = AVAudioFrameCount(inputFile.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ExportError.transcodeFailed("无法读取音频数据（草稿渲染）".localized)
        }
        try inputFile.read(into: buffer)

        guard let rendered = DraftRenderEngine.render(
            input: buffer,
            commands: draft.commands,
            currentIndex: draft.currentIndex,
            clipGain: draft.clipGain,
            factory: { DraftSpecFactory.command(from: $0, buffer: $1) }
        ) else {
            throw ExportError.transcodeFailed("草稿渲染失败（编辑命令无法重放）".localized)
        }

        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("render_\(UUID().uuidString).wav")
        // float32 WAV 保精度（后续转码再按目标格式压）
        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rendered.format.sampleRate,
            AVNumberOfChannelsKey: rendered.format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let wavFile = try AVAudioFile(forWriting: wavURL, settings: wavSettings,
                                      commonFormat: rendered.format.commonFormat,
                                      interleaved: rendered.format.isInterleaved)
        try wavFile.write(from: rendered)
        return wavURL
    }

    private func fileManagerEditDraftValid(_ draft: EditDraft, originalURL: URL) -> Bool {
        EditDraftStore.shared.isDraftValid(draft, originalURL: originalURL)
    }

    // MARK: - Private

    private func normalizeOutputURL(selected url: URL, format: AudioExportFormat) -> URL {
        if url.pathExtension.lowercased() == format.fileExtension {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension(format.fileExtension)
    }
    
    /// 音频转码（AVAudioFile 解码 + 重编码 / ffmpeg MP3/FLAC/OGG）
    private func transcode(inputURL: URL, outputURL: URL, format: AudioExportFormat) throws {
        ensureParentDirectory(outputURL)
        removeIfExists(outputURL)
        
        // MP3/FLAC/OGG: 走 ffmpeg 路径（App 内置 ffmpeg，含 libmp3lame MP3 编码器）
        // 注：系统 ExtAudioFile 的 Apple MP3 编码器在 macOS 26 已不可用（'fmt?'），
        // 统一由 ffmpeg 负责这三种格式。
        if format == .mp3 || format == .flac || format == .ogg {
            try transcodeWithFFmpeg(inputURL: inputURL, outputURL: outputURL, format: format)
            return
        }

        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat
        
        // M4A/WAV/AIFF: 走 AVAudioFile 路径
        let outputSettings: [String: Any]
        switch format {
        case .m4a:
            outputSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVEncoderBitRateKey: 128000
            ]
        case .wav:
            outputSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        case .aiff:
            outputSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: true
            ]
        default:
            throw ExportError.transcodeFailed("不支持的导出格式: %@".localized(format.displayName))
        }
        
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings, commonFormat: inputFormat.commonFormat, interleaved: inputFormat.isInterleaved)
        
        let frameCapacity = AVAudioFrameCount(inputFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity) else {
            throw ExportError.transcodeFailed("无法创建 PCM buffer".localized)
        }
        
        try inputFile.read(into: buffer)
        try outputFile.write(from: buffer)
        
        logComplete(outputURL, format: format)
    }
    
    private func ensureParentDirectory(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }
    
    private func removeIfExists(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func logComplete(_ url: URL, format: AudioExportFormat) {
        let sizeStr = ByteCountFormatter.string(
            fromByteCount: Int64((try? Data(contentsOf: url).count) ?? 0),
            countStyle: .file
        )
        logger.info("转码完成: \(format.displayName) → \(sizeStr)")
    }
    
    // MARK: - ffmpeg
    
    /// 检查 ffmpeg 是否可用（公开方法，供 UI 层用）
    static func hasFFmpeg() -> Bool {
#if DEBUG
        return _privateHasFFmpeg()
#else
        return _privateHasFFmpeg()
#endif
    }
    
    private static func _privateHasFFmpeg() -> Bool {
        // 1. App Bundle Resources
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: ""),
           FileManager.default.isExecutableFile(atPath: bundled.path) { return true }
        // 2. 系统路径
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
    
    /// 查找 ffmpeg 路径：App Bundle Resources → 系统路径
    private func findFFmpegPath() -> String? {
        // 1. App Bundle Resources（内置 ffmpeg）
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: ""),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            logger.info("使用内置 ffmpeg: \(bundled.path)")
            return bundled.path
        }
        // 2. Homebrew (Apple Silicon)
        let hb = "/opt/homebrew/bin/ffmpeg"
        if FileManager.default.isExecutableFile(atPath: hb) { return hb }
        // 3. Homebrew (Intel)
        let hb2 = "/usr/local/bin/ffmpeg"
        if FileManager.default.isExecutableFile(atPath: hb2) { return hb2 }
        // 4. 系统默认
        let sys = "/usr/bin/ffmpeg"
        if FileManager.default.isExecutableFile(atPath: sys) { return sys }
        return nil
    }
    
    /// ffmpeg 转码（MP3/FLAC/OGG）
    private func transcodeWithFFmpeg(inputURL: URL, outputURL: URL, format: AudioExportFormat) throws {
        guard let ffmpeg = findFFmpegPath() else {
            throw ExportError.transcodeFailed("""
                %@ 导出需要 ffmpeg。
                方式一: brew install ffmpeg
                方式二: 将 ffmpeg 二进制放入 App/Contents/Resources/
                """.localized(format.displayName))
        }
        
        ensureParentDirectory(outputURL)
        removeIfExists(outputURL)
        
        let codec: String
        switch format {
        case .mp3:  codec = "libmp3lame"
        case .flac: codec = "flac"
        case .ogg:  codec = "libvorbis"
        default:    throw ExportError.transcodeFailed("不支持的 ffmpeg 格式".localized)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-i", inputURL.path,
            "-vn",            // no video
            "-codec:a", codec,
            "-y",             // overwrite
            outputURL.path
        ]
        
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "未知错误".localized
            // ffmpeg 错误关键信息在 stderr 末尾（开头是版本头），取末尾 500 字符
            throw ExportError.transcodeFailed("ffmpeg 转码失败: %@".localized(String(errMsg.suffix(500))))
        }
        
        logComplete(outputURL, format: format)
    }
}

// MARK: - ExportError

enum ExportError: Error, LocalizedError {
    case transcodeFailed(String)
    case exportCancelled
    
    var errorDescription: String? {
        switch self {
        case .transcodeFailed(let msg): return "转码失败: %@".localized(msg)
        case .exportCancelled: return "导出已取消".localized
        }
    }
}
