import Foundation

// MARK: - DraftCommandSpec
/// 草稿命令规格（FEAT-007）——命令 init 参数的可序列化形态。
/// 设计要点：命令对象（TrimCommand 等）持有 undo 用 PCM buffer，不可序列化；
/// 草稿只存「重放所需的最小参数」，重开时从原始文件重放恢复编辑状态与撤销栈。
public enum DraftCommandSpec: Codable, Equatable {
    /// 裁剪：保留 [start, end]（秒）
    case trim(start: Double, end: Double)
    /// 删除选区 [start, end]（秒）
    case deleteSelection(start: Double, end: Double)
    /// 切分（时间轴不变，clip 级产物）
    case split(time: Double)
    /// 静音裁剪：删除的静音段列表（秒）
    case silenceTrim(segments: [DraftSilenceSegment])
    /// 响度标准化（preset 为 NormalizePreset.rawValue，customLUFS 为自定义目标）
    case normalize(preset: String, customLUFS: Double?)
    /// 淡入淡出（curve 为 FadeCurveType.rawValue）
    case fade(fadeIn: Double, fadeOut: Double, curve: String)
}

// MARK: - DraftSilenceSegment
/// 静音段的可序列化形态（SilenceSegment 含运行时 isSelected 状态，草稿只存已选中段）
public struct DraftSilenceSegment: Codable, Equatable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

// MARK: - EditDraft
/// 编辑草稿（FEAT-007 非破坏编辑模型）。
/// 语义（剪映式）：原始录音永不覆盖；草稿 = 原始文件 + 命令栈重放；导出 = 渲染编辑结果。
/// 自动保存对用户透明：每次编辑/撤销/重做/增益变化即落盘，无「保存」概念。
public struct EditDraft: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    /// 原始录音文件绝对路径（草稿归属的唯一键）
    public var originalPath: String
    /// 草稿创建时的原始文件大小（字节）——原始文件被替换时草稿失效
    public var originalFileSize: Int64
    /// 命令参数栈（按执行顺序）
    public var commands: [DraftCommandSpec]
    /// 撤销指针（0...commands.count-1；-1 = 全部已撤销）
    public var currentIndex: Int
    /// 音量增益（线性倍率，0...2.0；UI-034 音量线，FEAT-007 起随草稿进导出）
    public var clipGain: Float
    public var updatedAt: Date

    public init(originalURL: URL, originalFileSize: Int64) {
        self.version = EditDraft.currentVersion
        self.originalPath = originalURL.path
        self.originalFileSize = originalFileSize
        self.commands = []
        self.currentIndex = -1
        self.clipGain = 1.0
        self.updatedAt = Date()
    }

    /// 有编辑命令（含已撤销的——撤销栈本身也是要恢复的状态）
    public var hasEdits: Bool { !commands.isEmpty }

    /// 导出时是否需要渲染（有命令生效或增益非 1）
    public var hasRenderableEdits: Bool {
        !commands.isEmpty || abs(Double(clipGain) - 1.0) > 0.0001
    }

    /// 以历史栈为准截断 redo 段并对齐指针（executeCommand 后调用）
    public mutating func append(_ spec: DraftCommandSpec, historyPosition: Int) {
        let keep = max(0, historyPosition)  // 截断后的新栈长度 = position+1
        commands = Array(commands.prefix(keep))
        commands.append(spec)
        currentIndex = historyPosition
        updatedAt = Date()
    }

    /// 撤销/重做后同步指针
    public mutating func syncIndex(_ historyPosition: Int) {
        currentIndex = max(-1, min(historyPosition, commands.count - 1))
        updatedAt = Date()
    }

    /// 增益变化
    public mutating func setGain(_ gain: Float) {
        clipGain = max(0, min(gain, 2.0))
        updatedAt = Date()
    }
}
