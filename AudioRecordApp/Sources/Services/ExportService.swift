import Foundation
import AVFoundation
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
    
    /// 音频转码（使用 AVAudioFile 直接解码+重编码）
    private func transcode(inputURL: URL, outputURL: URL, format: AudioExportFormat) throws {
        // 确保输出目录存在
        let parent = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        // 删除已存在的文件
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat
        
        // 构建输出格式设置
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
        case .mp3:
            throw ExportError.transcodeFailed("MP3 导出需要 ffmpeg。请安装: brew install ffmpeg")
        case .flac, .ogg:
            throw ExportError.transcodeFailed("\(format.displayName) 导出需要 ffmpeg。请安装: brew install ffmpeg")
        }
        
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings, commonFormat: inputFormat.commonFormat, interleaved: inputFormat.isInterleaved)
        
        let frameCapacity = AVAudioFrameCount(inputFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity) else {
            throw ExportError.transcodeFailed("无法创建 PCM buffer")
        }
        
        try inputFile.read(into: buffer)
        try outputFile.write(from: buffer)
        
        logger.info("转码完成: \(format.displayName) → \(ByteCountFormatter.string(fromByteCount: Int64(try Data(contentsOf: outputURL).count), countStyle: .file))")
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
