import Foundation
import AVFoundation
import AudioToolbox
import AppKit
import UniformTypeIdentifiers

/// 导出服务 (V2.0)
/// 导出 = 解密 .arlock → 临时 .m4a → 转码为目标格式 → NSSavePanel 写入
class ExportService {
    
    static let shared = ExportService()
    private let logger = Logger.shared
    private let fileManager = FileManagerUtils.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// 导出录音文件
    /// - Parameters:
    ///   - arlockURL: .arlock 文件路径
    ///   - targetFormat: 目标导出格式
    ///   - completion: (成功: Bool, 输出路径: URL?, 错误: Error?)
    func export(arlockURL: URL, targetFormat: AudioExportFormat, completion: @escaping (Bool, URL?, Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 1. 解密 .arlock → AAC Data
                self.logger.info("导出: 解密 \(arlockURL.lastPathComponent)")
                let (audioData, metadata) = try AudioFileEncryptor.shared.decrypt(from: arlockURL)
                
                // 2. 写临时 .m4a（AAC 数据）
                let tempDir = FileManager.default.temporaryDirectory
                let tempUUID = UUID().uuidString
                let tempM4A = tempDir.appendingPathComponent("\(AudioCryptoConfig.TempFilePattern.exportPrefix)\(tempUUID).\(AudioCryptoConfig.TempFilePattern.m4aExtension)")
                try audioData.write(to: tempM4A, options: .atomic)
                
                // 3. NSSavePanel（主线程）
                DispatchQueue.main.async {
                    let panel = NSSavePanel()
                    panel.title = "导出录音"
                    panel.prompt = "导出"
                    panel.message = "选择导出位置"
                    panel.nameFieldStringValue = "\(metadata.title).\(targetFormat.fileExtension)"
                    panel.canCreateDirectories = true
                    
                    if let utType = UTType(filenameExtension: targetFormat.fileExtension) {
                        panel.allowedContentTypes = [utType]
                    }
                    
                    panel.begin { response in
                        guard response == .OK, let outputURL = panel.url else {
                            // 用户取消，清理临时文件
                            SecureDelete.deleteFile(at: tempM4A)
                            completion(false, nil, nil)
                            return
                        }
                        
                        // 4. 转码/复制到目标路径
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                let finalOutputURL = self.normalizeOutputURL(selected: outputURL, format: targetFormat)
                                
                                if targetFormat == .m4a {
                                    // AAC → M4A 直接复制（已编码）
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
                        }
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
    
    /// 快速导出为原格式 M4A（不解密时的导出）
    func quickExport(arlockURL: URL, completion: @escaping (Bool, URL?, Error?) -> Void) {
        // 默认导出 M4A（与录制编码一致）
        export(arlockURL: arlockURL, targetFormat: .m4a, completion: completion)
    }
    
    // MARK: - Private
    
    private func normalizeOutputURL(selected url: URL, format: AudioExportFormat) -> URL {
        if url.pathExtension.lowercased() == format.fileExtension {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension(format.fileExtension)
    }
    
    /// 音频转码（AVAudioFile 解码 + 重编码 / ExtAudioFile MP3）
    private func transcode(inputURL: URL, outputURL: URL, format: AudioExportFormat) throws {
        ensureParentDirectory(outputURL)
        removeIfExists(outputURL)
        
        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat
        
        // MP3: 走 ExtAudioFile 路径（AVAudioFile 不支持 MP3 输出）
        if format == .mp3 {
            try transcodeToMP3(inputFile: inputFile, inputFormat: inputFormat, outputURL: outputURL)
            return
        }
        
        // FLAC/OGG: 走 ffmpeg 路径（App 内置或系统安装）
        if format == .flac || format == .ogg {
            try transcodeWithFFmpeg(inputURL: inputURL, outputURL: outputURL, format: format)
            return
        }
        
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
            throw ExportError.transcodeFailed("不支持的导出格式: \(format.displayName)")
        }
        
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings, commonFormat: inputFormat.commonFormat, interleaved: inputFormat.isInterleaved)
        
        let frameCapacity = AVAudioFrameCount(inputFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity) else {
            throw ExportError.transcodeFailed("无法创建 PCM buffer")
        }
        
        try inputFile.read(into: buffer)
        try outputFile.write(from: buffer)
        
        logComplete(outputURL, format: format)
    }
    
    /// MP3 转码：ExtAudioFile 编码 PCM → MP3（零外部依赖，系统内置编码器）
    private func transcodeToMP3(inputFile: AVAudioFile, inputFormat: AVAudioFormat, outputURL: URL) throws {
        var outFile: ExtAudioFileRef?
        
        // 1. 构建 MP3 输出格式描述
        var outputASBD = AudioStreamBasicDescription()
        outputASBD.mFormatID = kAudioFormatMPEGLayer3
        outputASBD.mSampleRate = inputFormat.sampleRate
        outputASBD.mChannelsPerFrame = UInt32(inputFormat.channelCount)
        outputASBD.mFramesPerPacket = 1152  // MPEG Layer 3 fixed
        
        // 2. 创建 MP3 输出文件
        var status = ExtAudioFileCreateWithURL(outputURL as CFURL, kAudioFileMP3Type, &outputASBD, nil, AudioFileFlags.eraseFile.rawValue, &outFile)
        guard status == noErr, let outputExtFile = outFile else {
            throw ExportError.transcodeFailed("无法创建 MP3 文件 (err=\(status))")
        }
        defer { ExtAudioFileDispose(outputExtFile) }
        
        // 3. 设置 Apple 软件编码器
        var codecManufacturer: UInt32 = 0x6170706C  // 'appl' = Apple Software Codec
        status = ExtAudioFileSetProperty(outputExtFile, kExtAudioFileProperty_CodecManufacturer, UInt32(MemoryLayout<UInt32>.size), &codecManufacturer)
        if status != noErr {
            logger.warning("无法设置 MP3 编码器制造商，使用默认编码器 (err=\(status))")
            // 非致命，继续
        }
        
        // 4. 获取 PCM stream description
        var clientFormat = inputFormat.streamDescription.pointee
        
        // 5. 设置输入格式 (PCM)
        status = ExtAudioFileSetProperty(outputExtFile, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat)
        guard status == noErr else {
            throw ExportError.transcodeFailed("无法设置 MP3 客户端格式 (err=\(status))")
        }
        
        // 6. 分配 PCM buffer 并读取
        let totalFrames = inputFile.length
        let chunkSize: AVAudioFrameCount = 8192
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: chunkSize) else {
            throw ExportError.transcodeFailed("无法创建 PCM buffer")
        }
        
        // 7. 逐 chunk 读取 PCM → 写入 MP3
        var framesRemaining = totalFrames
        while framesRemaining > 0 {
            inputFile.framePosition = totalFrames - framesRemaining
            try inputFile.read(into: buffer)
            
            let framesRead = buffer.frameLength
            guard framesRead > 0 else { break }
            
            var audioBufferList = buffer.audioBufferList.pointee
            
            status = ExtAudioFileWrite(outputExtFile, framesRead, &audioBufferList)
            guard status == noErr else {
                throw ExportError.transcodeFailed("MP3 写入失败 (err=\(status))")
            }
            
            framesRemaining -= Int64(framesRead)
            buffer.frameLength = 0
        }
        
        logComplete(outputURL, format: .mp3)
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
    
    /// ffmpeg 转码（FLAC/OGG）
    private func transcodeWithFFmpeg(inputURL: URL, outputURL: URL, format: AudioExportFormat) throws {
        guard let ffmpeg = findFFmpegPath() else {
            throw ExportError.transcodeFailed("""
                \(format.displayName) 导出需要 ffmpeg。
                方式一: brew install ffmpeg
                方式二: 将 ffmpeg 二进制放入 App/Contents/Resources/
                """)
        }
        
        ensureParentDirectory(outputURL)
        removeIfExists(outputURL)
        
        let codec: String
        switch format {
        case .flac: codec = "flac"
        case .ogg:  codec = "libvorbis"
        default:    throw ExportError.transcodeFailed("不支持的 ffmpeg 格式")
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
            let errMsg = String(data: errData, encoding: .utf8) ?? "未知错误"
            throw ExportError.transcodeFailed("ffmpeg 转码失败: \(errMsg.prefix(200))")
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
        case .transcodeFailed(let msg): return "转码失败: \(msg)"
        case .exportCancelled: return "导出已取消"
        }
    }
}
