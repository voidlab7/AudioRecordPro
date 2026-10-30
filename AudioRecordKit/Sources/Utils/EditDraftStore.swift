import Foundation

// MARK: - EditDraftStore
/// 编辑草稿仓库（FEAT-007）：草稿 JSON 的落盘/读取/删除。
/// - 存储位置：沙盒 Application Support/Loocap/EditorDrafts/<原文件名>.draft.json
/// - 写入策略：串行队列异步写（草稿体量 = KB 级命令栈，无防抖必要；增益拖拽单独防抖）
/// - 失效策略：原始文件被替换（大小不一致）或路径不匹配时视为失效，由调用方丢弃
public final class EditDraftStore {

    public static let shared = EditDraftStore()

    private let queue = DispatchQueue(label: "com.microlab.loocap.editdraft", qos: .utility)
    private let directory: URL
    private let logger = Logger.shared

    /// 增益防抖：拖拽连续触发时合并写盘
    private var pendingGainWorkItem: DispatchWorkItem?
    private let gainDebounceInterval: TimeInterval = 0.3

    /// - Parameter directory: 草稿目录（测试注入用；nil = 沙盒 Application Support/Loocap/EditorDrafts）
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("Loocap/EditorDrafts", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    // MARK: - 路径

    /// 草稿文件路径（草稿名 = 原文件全名 + .draft.json，UUID 文件名天然唯一）
    public func draftURL(for originalURL: URL) -> URL {
        directory.appendingPathComponent("\(originalURL.lastPathComponent).draft.json")
    }

    // MARK: - 读写

    /// 读取草稿；损坏/不存在返回 nil（损坏时顺带清掉坏文件）
    public func draft(for originalURL: URL) -> EditDraft? {
        let url = draftURL(for: originalURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let draft = try JSONDecoder().decode(EditDraft.self, from: data)
            guard draft.version == EditDraft.currentVersion else {
                logger.info("草稿版本不匹配，丢弃: \(originalURL.lastPathComponent)")
                remove(for: originalURL)
                return nil
            }
            return draft
        } catch {
            logger.error("草稿解析失败，丢弃: \(originalURL.lastPathComponent), \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// 异步落盘草稿
    public func save(_ draft: EditDraft) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                let url = self.draftURL(for: URL(fileURLWithPath: draft.originalPath))
                let data = try JSONEncoder().encode(draft)
                try data.write(to: url, options: .atomic)
                self.logger.info("草稿已自动保存: \(draft.commands.count) 条命令 @\(draft.currentIndex), gain=\(draft.clipGain)")
            } catch {
                self.logger.error("草稿保存失败: \(error.localizedDescription)")
            }
        }
    }

    /// 删除草稿（文件删除联动）
    public func remove(for originalURL: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            let url = self.draftURL(for: originalURL)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                self.logger.info("草稿已删除: \(originalURL.lastPathComponent)")
            }
        }
    }

    /// 同步等待挂起的写任务完成（测试与自验断言用）
    public func flushForTesting() {
        queue.sync {}
        pendingGainWorkItem?.cancel()
        queue.sync {}
    }

    /// 原文件是否有含编辑的草稿
    public func hasEdits(for originalURL: URL) -> Bool {
        draft(for: originalURL)?.hasEdits ?? false
    }

    // MARK: - 便捷更新（读改写组合；调用方在主线程，无并发竞争）

    /// 新命令入栈（historyPosition = EditHistory.position，截断 redo 段）
    public func append(_ spec: DraftCommandSpec, historyPosition: Int, for originalURL: URL) {
        var draft = draft(for: originalURL) ?? EditDraft(originalURL: originalURL,
                                                         originalFileSize: originalFileSize(at: originalURL))
        draft.append(spec, historyPosition: historyPosition)
        save(draft)
    }

    /// 撤销/重做后同步指针
    public func syncIndex(_ historyPosition: Int, for originalURL: URL) {
        guard var draft = draft(for: originalURL), draft.hasEdits else { return }
        draft.syncIndex(historyPosition)
        save(draft)
    }

    /// 增益变化（防抖落盘）
    public func setGain(_ gain: Float, for originalURL: URL) {
        pendingGainWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var draft = self.draft(for: originalURL) ?? EditDraft(originalURL: originalURL,
                                                                  originalFileSize: self.originalFileSize(at: originalURL))
            guard draft.clipGain != gain else { return }
            draft.setGain(gain)
            self.save(draft)
        }
        pendingGainWorkItem = item
        queue.asyncAfter(deadline: .now() + gainDebounceInterval, execute: item)
    }

    // MARK: - 有效性

    /// 草稿与原始文件是否仍然匹配（路径一致 + 文件大小一致）
    public func isDraftValid(_ draft: EditDraft, originalURL: URL) -> Bool {
        guard draft.originalPath == originalURL.path else { return false }
        guard FileManager.default.fileExists(atPath: originalURL.path) else { return false }
        return originalFileSize(at: originalURL) == draft.originalFileSize
    }

    private func originalFileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }
}
