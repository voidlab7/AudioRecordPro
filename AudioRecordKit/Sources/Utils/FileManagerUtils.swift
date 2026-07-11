import Foundation
import AppKit
import AVFoundation

/// 文件管理工具类
class FileManagerUtils {
    static let shared = FileManagerUtils()
    
    private let fileManager = FileManager.default
    private let logger = Logger.shared
    
    private init() {
        // 尝试恢复之前保存的安全作用域书签
        _ = restoreSecurityScopedBookmark()
    }
    
    /// 获取录音文件保存目录
    func getRecordingsDirectory() -> URL {
        // 优先使用用户自定义目录
        if let customPath = UserDefaults.standard.string(forKey: "recordingsDirectory"),
           !customPath.isEmpty {
            let customURL = URL(fileURLWithPath: customPath)
            createDirectoryIfNeeded(at: customURL)
            return customURL
        }
        
        // 默认使用 Documents 目录
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = documentsPath.appendingPathComponent("AudioRecordings")
        createDirectoryIfNeeded(at: recordingsDir)
        return recordingsDir
    }
    
    /// 创建目录（如果不存在）
    func createDirectoryIfNeeded(at url: URL) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            logger.debug("目录已创建/验证: \(url.path)")
        } catch {
            logger.error("创建目录失败 \(url.path): \(error.localizedDescription)")
        }
    }
    
    /// 生成录音文件名（旧版本，保持兼容性）
    func generateRecordingFileName(format: String) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return "record_\(timestamp).\(format.lowercased())"
    }
    
    /// 生成新的录音文件名（应用名称+时间日期格式）
    func generateRecordingFileName(recordingMode: RecordingMode, appName: String? = nil, format: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss-SSS"  // Include milliseconds to avoid collision in multi-process mode
        let timestamp = dateFormatter.string(from: Date())
        
        let sourceName: String
        switch recordingMode {
        case .microphone:
            sourceName = "麦克风"
        case .systemMixdown:
            sourceName = "系统音频"
        case .specificProcess:
            if let appName = appName, !appName.isEmpty {
                sourceName = appName
            } else {
                sourceName = "应用音频"
            }
        }
        
        // 清理文件名中的非法字符
        let cleanSourceName = sourceName.replacingOccurrences(of: "/", with: "_")
                                      .replacingOccurrences(of: ":", with: "_")
                                      .replacingOccurrences(of: " ", with: "_")
        
        return "\(cleanSourceName)_\(timestamp).\(format.lowercased())"
    }
    
    /// 获取录音文件完整路径（旧版本）
    func getRecordingFileURL(format: String) -> URL {
        let directory = getRecordingsDirectory()
        let filename = generateRecordingFileName(format: format)
        return directory.appendingPathComponent(filename)
    }
    
    /// 获取录音文件完整路径（新版本）
    func getRecordingFileURL(recordingMode: RecordingMode, appName: String? = nil, format: String) -> URL {
        let directory = getRecordingsDirectory()
        let filename = generateRecordingFileName(recordingMode: recordingMode, appName: appName, format: format)
        return directory.appendingPathComponent(filename)
    }
    
    /// 请求 Documents 目录访问权限
    func requestDocumentsAccess(completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "授权访问"
        panel.message = "请选择 Documents 目录以授权应用程序访问"
        panel.title = "授权 Documents 目录访问"
        
        // 默认导航到 Documents 目录
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = documentsURL
        }
        
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                // 检查是否选择了 Documents 目录
                if self.isDocumentsDirectory(selectedURL) {
                    // 保存安全作用域书签
                    self.saveSecurityScopedBookmark(for: selectedURL)
                    completion(true)
                } else {
                    // 用户选择了其他目录，也保存书签
                    self.saveSecurityScopedBookmark(for: selectedURL)
                    completion(true)
                }
            } else {
                completion(false)
            }
        }
    }
    
    /// 检查是否为 Documents 目录
    private func isDocumentsDirectory(_ url: URL) -> Bool {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        return url.path == documentsURL.path
    }
    
    /// 保存安全作用域书签
    private func saveSecurityScopedBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "selectedDirectoryBookmark")
            logger.info("已保存安全作用域书签: \(url.path)")
        } catch {
            logger.error("保存安全作用域书签失败: \(error.localizedDescription)")
        }
    }
    
    /// 恢复安全作用域书签
    func restoreSecurityScopedBookmark() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "selectedDirectoryBookmark") else {
            return nil
        }
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                logger.warning("安全作用域书签已过期，需要重新选择目录")
                return nil
            }
            
            let success = url.startAccessingSecurityScopedResource()
            if success {
                logger.info("已恢复安全作用域书签: \(url.path)")
                return url
            } else {
                logger.error("无法访问安全作用域资源")
                return nil
            }
        } catch {
            logger.error("恢复安全作用域书签失败: \(error.localizedDescription)")
            return nil
        }
    }
    
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
            logger.error("获取文件大小失败 \(url.path): \(error.localizedDescription)")
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
        // 确保目标目录存在
        createDirectoryIfNeeded(at: destinationURL.deletingLastPathComponent())
        
        // 如果目标文件已存在，先删除
        if fileExists(at: destinationURL) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        logger.info("文件已从 \(sourceURL.lastPathComponent) 复制到 \(destinationURL.lastPathComponent)")
    }
    
    /// 删除文件
    func deleteFile(at url: URL) throws {
        try fileManager.removeItem(at: url)
        logger.info("文件已删除: \(url.lastPathComponent)")
    }
    
    /// 获取录音文件列表
    func getRecordingFiles() -> [URL] {
        let recordingsDir = getRecordingsDirectory()
        
        do {
            let files = try fileManager.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey], options: [])
            return files.filter { url in
                let pathExtension = url.pathExtension.lowercased()
                return ["m4a", "mp3", "wav"].contains(pathExtension)
            }.sorted { url1, url2 in
                // 按创建时间降序排列
                let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 ?? Date.distantPast > date2 ?? Date.distantPast
            }
        } catch {
            logger.error("获取录音文件失败: \(error.localizedDescription)")
            return []
        }
    }
    
    /// 清理临时文件
    func cleanupTempFiles() {
        let tempDir = fileManager.temporaryDirectory
        
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey], options: [])
            let oneHourAgo = Date().addingTimeInterval(-3600) // 1小时前
            
            for fileURL in tempFiles {
                if fileURL.path.contains("record_") {
                    if let creationDate = try fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < oneHourAgo {
                        try fileManager.removeItem(at: fileURL)
                        logger.info("已清理临时文件: \(fileURL.lastPathComponent)")
                    }
                }
            }
        } catch {
            logger.error("清理临时文件失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 磁盘空间监控
    
    /// 最小磁盘空间阈值（100MB）
    private static let minimumDiskSpaceBytes: Int64 = 100 * 1024 * 1024
    
    /// 获取可用磁盘空间（字节）
    func getAvailableDiskSpace() -> Int64? {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        guard let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return available
    }
    
    /// 检查磁盘空间是否充足（> 100MB）
    func hasSufficientDiskSpace() -> Bool {
        guard let available = getAvailableDiskSpace() else { return true }
        return available > FileManagerUtils.minimumDiskSpaceBytes
    }
    
    /// 格式化磁盘空间显示
    func formatDiskSpace(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Crash 恢复
    
    /// 录制中标记文件路径（用于 crash 恢复检测）
    private var activeRecordingMarkerURL: URL {
        fileManager.temporaryDirectory.appendingPathComponent(".audio_record_active")
    }
    
    /// 标记录制开始（写入 marker 文件）
    func markRecordingStarted(fileURL: URL) {
        do {
            try fileURL.path.write(to: activeRecordingMarkerURL, atomically: true, encoding: .utf8)
            logger.info("已标记活跃录制: \(fileURL.lastPathComponent)")
        } catch {
            logger.error("写入录制标记失败: \(error.localizedDescription)")
        }
    }
    
    /// 标记录制结束（删除 marker 文件）
    func markRecordingFinished() {
        if fileManager.fileExists(atPath: activeRecordingMarkerURL.path) {
            try? fileManager.removeItem(at: activeRecordingMarkerURL)
            logger.info("已清除活跃录制标记")
        }
    }
    
    /// 检查是否有未完成的录制（crash 恢复）
    /// marker 文件中存储的是录制目录路径，恢复时找该目录中最近 5 分钟内创建的最新音频文件
    func checkForUnfinishedRecording() -> URL? {
        guard fileManager.fileExists(atPath: activeRecordingMarkerURL.path) else {
            return nil
        }
        
        do {
            let directoryPath = try String(contentsOf: activeRecordingMarkerURL, encoding: .utf8)
            let directoryURL = URL(fileURLWithPath: directoryPath)
            
            // 清除标记
            try? fileManager.removeItem(at: activeRecordingMarkerURL)
            
            // 扫描目录中最近 5 分钟内创建的音频文件
            let fiveMinutesAgo = Date().addingTimeInterval(-300)
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            let recentAudio = contents
                .filter { url in
                    let ext = url.pathExtension.lowercased()
                    return ["m4a", "wav", "mp3"].contains(ext)
                }
                .filter { url in
                    guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                          let created = values.creationDate else { return false }
                    return created > fiveMinutesAgo
                }
                .sorted { url1, url2 in
                    let d1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let d2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return d1 > d2
                }
                .first
            
            if let latestFile = recentAudio,
               let size = getFileSize(at: latestFile), size > 0 {
                logger.info("发现未完成的录制文件: \(latestFile.lastPathComponent), 大小: \(formatFileSize(size))")
                return latestFile
            } else {
                logger.info("未发现最近的未完成录制文件，跳过恢复")
                return nil
            }
        } catch {
            logger.error("检查未完成录制失败: \(error.localizedDescription)")
            try? fileManager.removeItem(at: activeRecordingMarkerURL)
            return nil
        }
    }
    
    /// 将录制文件标记为已恢复（重命名加前缀）
    func recoverRecording(from fileURL: URL) -> URL? {
        let directory = fileURL.deletingLastPathComponent()
        let recoveredName = "恢复_\(fileURL.lastPathComponent)"
        let destinationURL = directory.appendingPathComponent(recoveredName)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: fileURL, to: destinationURL)
            logger.info("录制文件已恢复: \(recoveredName)")
            return destinationURL
        } catch {
            // 复制失败时，原文件仍可用，直接返回原路径
            logger.warning("重命名恢复失败，使用原文件: \(error.localizedDescription)")
            return fileURL
        }
    }
    
    // MARK: - File Integrity Check
    
    /// 检查音频文件完整性
    /// 尝试用 AVAudioFile 打开文件，如果能读取长度则文件完整
    func checkFileIntegrity(at url: URL) -> FileIntegrityResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }
        
        guard let size = getFileSize(at: url) else {
            return .corrupted(reason: "无法读取文件大小")
        }
        
        if size == 0 {
            return .corrupted(reason: "文件大小为 0")
        }
        
        // 尝试用 AVAudioFile 打开
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            if duration <= 0 {
                return .corrupted(reason: "音频时长为 0")
            }
            return .valid(duration: duration, size: size)
        } catch {
            return .corrupted(reason: error.localizedDescription)
        }
    }
    
    enum FileIntegrityResult {
        case valid(duration: TimeInterval, size: Int64)
        case corrupted(reason: String)
        case missing
        
        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }
}
