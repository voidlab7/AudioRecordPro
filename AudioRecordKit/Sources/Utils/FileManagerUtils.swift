import Foundation
import AppKit
import AVFoundation

/// 文件管理工具类 (V2.0: 沙盒容器目录 + .arlock 加密格式)
class FileManagerUtils {
    static let shared = FileManagerUtils()
    
    private let fileManager = FileManager.default
    private let logger = Logger.shared
    
    private init() {
        // V2.0: 不再使用安全作用域书签（录音文件全部走沙盒容器目录）
    }
    
    // MARK: - 录音目录 (V2.0: 沙盒容器)
    
    /// 获取录音文件保存目录（沙盒容器内，用户不可见）
    /// 实际路径: ~/Library/Containers/<bundle.id>/Data/Library/Application Support/Recordings/
    func getRecordingsDirectory() -> URL {
        let containerURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = containerURL.appendingPathComponent("Recordings", isDirectory: true)
        createDirectoryIfNeeded(at: dir)
        return dir
    }
    
    /// 创建目录（如果不存在）
    func createDirectoryIfNeeded(at url: URL) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            logger.debug("目录已创建/验证: \(url.lastPathComponent)")
        } catch {
            logger.error("创建目录失败 \(url.path): \(error.localizedDescription)")
        }
    }
    
    // MARK: - 文件名生成 (V2.0: UUID + temp)
    
    /// 生成录音文件 UUID（不再用模式_日期格式）
    func generateRecordingUUID() -> UUID {
        return UUID()
    }
    
    /// 获取 .arlock 文件完整路径（加密后最终存储）
    func getRecordingFileURL(uuid: UUID) -> URL {
        let directory = getRecordingsDirectory()
        return directory.appendingPathComponent("\(uuid.uuidString).\(AudioCryptoConfig.fileExtension)")
    }
    
    /// 获取录制中临时文件路径（录制器写原始音频，录制完成后由 MainVC 加密）
    /// - Parameter prefix: 文件名前缀（如 "system"、"mic"、"process"）
    /// - Parameter format: 文件扩展名（如 "m4a"、"wav"）
    func getTempRecordingFileURL(prefix: String, format: String) -> URL {
        let tempDir = fileManager.temporaryDirectory
        let timestamp = Self.timestampString()
        let fileName = "\(AudioCryptoConfig.TempFilePattern.recordingPrefix)\(prefix)_\(timestamp).\(format)"
        return tempDir.appendingPathComponent(fileName)
    }
    
    /// 时间戳字符串（线程安全）
    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
    
    // MARK: - 文件操作
    
    /// 检查文件是否存在
    func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// 获取文件大小
    func getFileSize(at url: URL) -> Int64? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64
        } catch {
            logger.error("获取文件大小失败 \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 格式化文件大小
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// 复制文件
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        createDirectoryIfNeeded(at: destinationURL.deletingLastPathComponent())
        if fileExists(at: destinationURL) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        logger.info("文件已复制: \(sourceURL.lastPathComponent) → \(destinationURL.lastPathComponent)")
    }
    
    /// 删除文件
    func deleteFile(at url: URL) throws {
        try fileManager.removeItem(at: url)
        logger.info("文件已删除: \(url.lastPathComponent)")
    }
    
    // MARK: - 录音文件列表 (V2.0: .arlock)
    
    /// 获取录音文件列表（只列出 .arlock 文件）
    func getRecordingFiles() -> [URL] {
        let recordingsDir = getRecordingsDirectory()
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: recordingsDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            return files
                .filter { $0.pathExtension == AudioCryptoConfig.fileExtension }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            logger.error("获取录音文件列表失败: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - 临时文件清理
    
    /// 清理临时文件（播放/导出残留）
    func cleanupTempFiles() {
        SecureDelete.cleanupLegacyTempFiles()
    }
    
    /// 清理旧的音频格式临时文件（兼容旧版）
    func cleanupLegacyTempAudioFiles() {
        let tempDir = fileManager.temporaryDirectory
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey])
            let oneHourAgo = Date().addingTimeInterval(-3600)
            for fileURL in tempFiles {
                if fileURL.path.contains("record_") {
                    if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < oneHourAgo {
                        try? fileManager.removeItem(at: fileURL)
                    }
                }
            }
        } catch {
            logger.error("清理旧临时文件失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 磁盘空间监控
    
    private static let minimumDiskSpaceBytes: Int64 = 100 * 1024 * 1024
    
    func getAvailableDiskSpace() -> Int64? {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        guard let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return available
    }
    
    func hasSufficientDiskSpace() -> Bool {
        guard let available = getAvailableDiskSpace() else { return true }
        return available > FileManagerUtils.minimumDiskSpaceBytes
    }
    
    func formatDiskSpace(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Crash 恢复 (V2.0: 临时文件扫描)
    
    /// 录制中标记文件路径
    private var activeRecordingMarkerURL: URL {
        fileManager.temporaryDirectory.appendingPathComponent(".audio_record_active_v2")
    }
    
    /// 标记录制开始
    func markRecordingStarted(fileURL: URL) {
        do {
            try fileURL.path.write(to: activeRecordingMarkerURL, atomically: true, encoding: .utf8)
            logger.info("已标记活跃录制: \(fileURL.lastPathComponent)")
        } catch {
            logger.error("写入录制标记失败: \(error.localizedDescription)")
        }
    }
    
    /// 标记录制结束
    func markRecordingFinished() {
        if fileManager.fileExists(atPath: activeRecordingMarkerURL.path) {
            try? fileManager.removeItem(at: activeRecordingMarkerURL)
            logger.info("已清除活跃录制标记")
        }
    }
    
    /// 检查是否有未完成的临时录制文件（crash 恢复）
    func checkForUnfinishedRecording() -> URL? {
        guard fileManager.fileExists(atPath: activeRecordingMarkerURL.path) else {
            return nil
        }
        
        // 清除标记
        try? fileManager.removeItem(at: activeRecordingMarkerURL)
        
        let tempDir = fileManager.temporaryDirectory
        let tempFiles = SecureDelete.findTemporaryRecordings(in: tempDir)
        
        return tempFiles.first
    }
    
    /// 将临时录制文件恢复
    func recoverTempRecording(from fileURL: URL) -> URL? {
        // V2.0: 临时文件是 .caf，不需要重命名，直接返回
        // 后续由调用方负责加密转为 .arlock
        logger.info("发现待恢复临时录制: \(fileURL.lastPathComponent)")
        return fileURL
    }
    
    // MARK: - 编辑器辅助 (V2.0: 透明 .arlock 解密)
    
    /// 编辑器会话（透明处理 .arlock 加密）
    /// 包含可播放 URL + 清理闭包
    struct EditSession {
        /// AVAudioFile 用于读取/写入的临时 .m4a 路径
        let playableURL: URL
        /// 是否是 .arlock 源（保存时需要重新加密）
        let isArlock: Bool
        /// .arlock 的 recording UUID（用于重新加密）
        let recordingUUID: UUID?
        /// 原始 .arlock URL（保存时用）
        let originalURL: URL
        /// 清理临时文件的闭包
        let cleanup: () -> Void
    }
    
    /// 准备编辑器：透明解密 .arlock 到临时 .m4a
    /// - Parameter url: 文件 URL（.arlock 或标准音频）
    /// - Returns: EditSession
    func prepareForEditing(url: URL) throws -> EditSession {
        if url.pathExtension.lowercased() == AudioCryptoConfig.fileExtension {
            // .arlock: 解密到临时 .m4a
            let (audioData, _) = try AudioFileEncryptor.shared.decrypt(from: url)
            
            let tempDir = fileManager.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("\(AudioCryptoConfig.TempFilePattern.playbackPrefix)edit_\(UUID().uuidString).\(AudioCryptoConfig.TempFilePattern.m4aExtension)")
            try audioData.write(to: tempURL, options: .atomic)
            
            // 从 .arlock 路径提取 UUID (文件名就是 UUID)
            let uuidString = url.deletingPathExtension().lastPathComponent
            let recordingUUID = UUID(uuidString: uuidString)
            
            return EditSession(
                playableURL: tempURL,
                isArlock: true,
                recordingUUID: recordingUUID,
                originalURL: url,
                cleanup: {
                    SecureDelete.deleteFile(at: tempURL)
                }
            )
        } else {
            // 标准音频文件：直接使用
            return EditSession(
                playableURL: url,
                isArlock: false,
                recordingUUID: nil,
                originalURL: url,
                cleanup: {}
            )
        }
    }
    
    /// 提交编辑：如果是 .arlock 源，重新加密
    /// - Parameters:
    ///   - session: 编辑器会话
    ///   - buffer: 编辑后的 PCM buffer
    ///   - format: 音频格式
    /// - Throws: 加密失败
    func finalizeEdit(session: EditSession, buffer: AVAudioPCMBuffer, format: AVAudioFormat) throws {
        // 1. 把编辑后的 buffer 写到 playableURL
        let audioFile = try AVAudioFile(forWriting: session.playableURL, settings: format.settings)
        try audioFile.write(from: buffer)
        
        // 2. 如果是 .arlock 源，重新加密
        if session.isArlock {
            let audioData = try Data(contentsOf: session.playableURL)
            
            // 重新读原 .arlock 的元数据（保持元数据，title 等不变）
            let (_, originalMetadata) = try AudioFileEncryptor.shared.decrypt(from: session.originalURL)
            
            // 用原 UUID 重新加密
            let uuid = session.recordingUUID ?? generateRecordingUUID()
            try AudioFileEncryptor.shared.encryptAndWrite(
                audioData: audioData,
                metadata: originalMetadata,
                recordingUUID: uuid,
                outputURL: session.originalURL
            )
        }
    }
    
    // MARK: - 旧文件迁移 (V2.0)
    
    /// 检查旧版录音目录是否有未迁移的 .m4a/.wav 文件
    func checkLegacyRecordings() -> [URL] {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let legacyDir = documentsPath.appendingPathComponent("AudioRecordings")
        
        guard fileManager.fileExists(atPath: legacyDir.path) else { return [] }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil)
            return files.filter { url in
                let ext = url.pathExtension.lowercased()
                return ["m4a", "wav", "mp3", "caf"].contains(ext)
            }
        } catch {
            logger.error("检查旧版录音失败: \(error.localizedDescription)")
            return []
        }
    }
    
    /// 批量迁移旧版 .m4a/.wav 到 .arlock（P2 功能，暂不实现）
    func migrateLegacyRecording(from url: URL) -> URL? {
        // TODO: V2.1+ 实现批量加密迁移
        logger.info("旧版文件迁移功能将在 V2.1 实现: \(url.lastPathComponent)")
        return nil
    }
}
