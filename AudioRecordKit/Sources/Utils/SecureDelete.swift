import Foundation

/// 安全删除工具
/// 覆写文件内容后删除，防止数据恢复工具恢复
/// SSD 下 TRIM 会自动擦除，但仍执行覆写作纵深防御
struct SecureDelete {
    
    private static let logger = Logger.shared
    private static let fileManager = FileManager.default
    
    /// 安全删除文件
    /// - Parameter url: 要删除的文件路径
    /// - Parameter passes: 覆写次数（默认 1 次，SSD 下足够；机械硬盘建议 3 次）
    static func deleteFile(at url: URL, passes: Int = 1) {
        guard fileManager.fileExists(atPath: url.path) else {
            logger.debug("安全删除：文件不存在 \(url.lastPathComponent)")
            return
        }
        
        do {
            // 获取文件大小
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
                // 空文件或无法获取大小，直接删除
                try fileManager.removeItem(at: url)
                return
            }
            
            let handle = try FileHandle(forUpdating: url)
            defer { try? handle.close() }
            
            // 多次覆写
            for pass in 0..<passes {
                let fillByte: UInt8
                switch pass % 3 {
                case 0: fillByte = 0x00
                case 1: fillByte = 0xFF
                default: fillByte = 0x00
                }
                
                let chunkSize = min(Int(fileSize), 1024 * 1024) // 1MB per chunk
                let fillData = Data(repeating: fillByte, count: chunkSize)
                
                var remaining = fileSize
                try handle.seek(toOffset: 0)
                
                while remaining > 0 {
                    let writeSize = min(Int64(chunkSize), remaining)
                    let chunk = fillData.prefix(Int(writeSize))
                    try handle.write(contentsOf: chunk)
                    remaining -= writeSize
                }
                
                try handle.synchronize()
            }
            
            try handle.close()
            
            // 删除文件
            try fileManager.removeItem(at: url)
            logger.debug("已安全删除: \(url.lastPathComponent)")
            
        } catch {
            logger.error("安全删除失败 \(url.lastPathComponent): \(error.localizedDescription)")
            // 回退：直接删除
            try? fileManager.removeItem(at: url)
        }
    }
    
    /// 安全删除目录下匹配模式的文件
    /// - Parameters:
    ///   - directory: 目录路径
    ///   - prefix: 文件名前缀匹配
    ///   - suffix: 文件名后缀匹配
    static func deleteFiles(in directory: URL, prefix: String? = nil, suffix: String? = nil) {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files {
                let name = file.lastPathComponent
                var matches = true
                if let prefix = prefix { matches = matches && name.hasPrefix(prefix) }
                if let suffix = suffix { matches = matches && name.hasSuffix(suffix) }
                if matches {
                    deleteFile(at: file)
                }
            }
        } catch {
            logger.error("扫描临时文件失败 \(directory.path): \(error.localizedDescription)")
        }
    }
    
    /// 扫描并清理临时录制文件（crash 恢复用）
    /// - Returns: 找到的临时文件列表
    static func findTemporaryRecordings(in directory: URL) -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            let fiveMinutesAgo = Date().addingTimeInterval(-300)
            
            let tempRecordings = files
                .filter { url in
                    let name = url.lastPathComponent
                    return name.hasPrefix(AudioCryptoConfig.TempFilePattern.recordingPrefix)
                        && name.hasSuffix(".\(AudioCryptoConfig.TempFilePattern.cafExtension)")
                }
                .filter { url in
                    guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                          let created = values.creationDate else { return false }
                    // 只保留最近 5 分钟内创建的（避免恢复太旧的文件）
                    return created > fiveMinutesAgo
                }
                .sorted { url1, url2 in
                    let d1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let d2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return d1 > d2
                }
            
            return tempRecordings
        } catch {
            logger.error("扫描临时录制文件失败: \(error.localizedDescription)")
            return []
        }
    }
    
    /// 清理遗留的播放/导出临时文件（App 启动时调用）
    static func cleanupLegacyTempFiles() {
        let tempDir = fileManager.temporaryDirectory
        
        // 清理播放临时文件
        deleteFiles(in: tempDir, prefix: AudioCryptoConfig.TempFilePattern.playbackPrefix)
        
        // 清理导出临时文件
        deleteFiles(in: tempDir, prefix: AudioCryptoConfig.TempFilePattern.exportPrefix)
        
        // 清理录制临时文件（超过 1 小时的，肯定不是 crash 恢复场景）
        guard fileManager.fileExists(atPath: tempDir.path) else { return }
        do {
            let oneHourAgo = Date().addingTimeInterval(-3600)
            let files = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey])
            for file in files {
                let name = file.lastPathComponent
                if name.hasPrefix(AudioCryptoConfig.TempFilePattern.recordingPrefix) {
                    if let values = try? file.resourceValues(forKeys: [.creationDateKey]),
                       let created = values.creationDate,
                       created < oneHourAgo {
                        deleteFile(at: file)
                    }
                }
            }
        } catch {
            logger.error("清理旧临时文件失败: \(error.localizedDescription)")
        }
    }
}
