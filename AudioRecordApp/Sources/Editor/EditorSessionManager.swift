import Foundation

// MARK: - EditorSessionManager
/// 编辑器会话池管理器 — LRU 缓存策略，最多保留 maxSessions 个编辑会话
class EditorSessionManager {

    // MARK: - Configuration
    static let shared = EditorSessionManager()

    /// 最大缓存会话数（LRU 淘汰）
    private let maxSessions = 3

    /// 最大总内存使用量（字节），超过则淘汰最旧的
    private let maxTotalMemory: Int = 450 * 1024 * 1024  // 450MB

    // MARK: - State
    private var sessions: [URL: EditorSession] = [:]
    private var accessOrder: [URL] = []  // 最近访问的在末尾

    /// 当前活跃的 session
    private(set) var activeSession: EditorSession?

    private let logger = Logger.shared

    // MARK: - Initialization
    private init() {
        // 监听内存压力通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: NSNotification.Name("NSApplicationDidReceiveMemoryWarningNotification"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// 获取或创建指定文件的编辑会话
    /// - Parameter file: 要编辑的文件信息
    /// - Returns: 编辑会话（可能需要等待 loadAudio 完成）
    func session(for file: RecordedFileInfo) -> EditorSession {
        let url = file.url

        // 命中缓存
        if let existing = sessions[url] {
            existing.touch()
            promoteInAccessOrder(url)
            activeSession = existing
            logger.info("EditorSessionManager: 缓存命中 — \(file.name)")
            return existing
        }

        // 未命中：创建新 session
        let newSession = EditorSession(file: file)
        sessions[url] = newSession
        accessOrder.append(url)
        activeSession = newSession

        // 淘汰检查
        evictIfNeeded()

        logger.info("EditorSessionManager: 创建新 session — \(file.name), 池大小: \(sessions.count)")
        return newSession
    }

    /// 关闭指定 session（释放资源）
    func closeSession(for url: URL) {
        sessions.removeValue(forKey: url)
        accessOrder.removeAll { $0 == url }
        if activeSession?.file.url == url {
            activeSession = nil
        }
        logger.info("EditorSessionManager: 关闭 session — \(url.lastPathComponent)")
    }

    /// 关闭所有 session
    func closeAll() {
        sessions.removeAll()
        accessOrder.removeAll()
        activeSession = nil
        logger.info("EditorSessionManager: 关闭所有 session")
    }

    /// 检查指定文件是否有缓存的 session
    func hasSession(for url: URL) -> Bool {
        return sessions[url] != nil
    }

    /// 获取已有的 session（不创建新的）
    func existingSession(for url: URL) -> EditorSession? {
        return sessions[url]
    }

    /// 当前池大小
    var sessionCount: Int { sessions.count }

    /// 当前总内存使用量
    var totalMemoryUsage: Int {
        sessions.values.reduce(0) { $0 + $1.estimatedMemoryUsage }
    }

    // MARK: - Private

    /// LRU 淘汰策略
    private func evictIfNeeded() {
        // 数量限制
        while sessions.count > maxSessions {
            evictOldest()
        }

        // 内存限制
        while totalMemoryUsage > maxTotalMemory && sessions.count > 1 {
            evictOldest()
        }
    }

    /// 淘汰最久未访问的 session（排除当前活跃的）
    private func evictOldest() {
        guard let oldestURL = accessOrder.first(where: { $0 != activeSession?.file.url }) else {
            return
        }

        if let session = sessions[oldestURL], session.hasUnsavedChanges {
            // 有未保存更改的 session 不淘汰，只释放 buffer
            session.releaseBuffer()
            logger.info("EditorSessionManager: 释放 buffer（有未保存更改）— \(oldestURL.lastPathComponent)")
        } else {
            sessions.removeValue(forKey: oldestURL)
            accessOrder.removeAll { $0 == oldestURL }
            logger.info("EditorSessionManager: 淘汰 session — \(oldestURL.lastPathComponent)")
        }
    }

    /// 将 URL 移到访问顺序末尾（最近访问）
    private func promoteInAccessOrder(_ url: URL) {
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
    }

    // MARK: - Memory Management

    @objc private func handleMemoryWarning() {
        logger.warning("EditorSessionManager: 收到内存警告，释放非活跃 session")

        // 释放所有非活跃 session 的 buffer
        for (url, session) in sessions where url != activeSession?.file.url {
            session.releaseBuffer()
        }
    }
}
