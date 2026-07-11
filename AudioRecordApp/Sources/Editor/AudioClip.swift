import Foundation

// MARK: - AudioClip 数据模型（P0-C）
/// 音频轨道上的一段连续音频片段
struct AudioClip: Identifiable {
    let id: String
    var name: String
    var color: ClipColor
    
    /// 在父音频 buffer 中的起始时间偏移（秒）
    var sourceStartTime: TimeInterval
    /// 在 edit timeline 上的起始时间（秒）
    var timelineStartTime: TimeInterval
    /// 在 edit timeline 上的持续时间（秒）
    var duration: TimeInterval
    
    /// 属性
    var volumeDB: Float = 0.0
    var fadeInDuration: TimeInterval = 0.0
    var fadeOutDuration: TimeInterval = 0.0
    var isMuted: Bool = false
    var isSolo: Bool = false
    var isSelected: Bool = false
    var isLocked: Bool = false
    
    /// 裁剪左右边界（相对于 sourceStartTime 的偏移）
    var trimStartOffset: TimeInterval = 0.0
    var trimEndOffset: TimeInterval = 0.0
    
    init(
        id: String = UUID().uuidString,
        name: String,
        color: ClipColor = .coral,
        sourceStartTime: TimeInterval = 0,
        timelineStartTime: TimeInterval = 0,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.sourceStartTime = sourceStartTime
        self.timelineStartTime = timelineStartTime
        self.duration = duration
    }
}

// MARK: - Clip 颜色
enum ClipColor: String, CaseIterable {
    case coral = "coral"        // #FF6B5F — 默认
    case cyan = "cyan"          // #8AEBFF
    case gold = "gold"          // #FFD700
    case purple = "purple"      // #B388FF
    case green = "green"        // #81C784
}

// MARK: - Track 数据模型
/// 一条音频轨道，包含多个 AudioClip
class EditorAudioTrack {
    let id: String
    var name: String
    var color: ClipColor
    var clips: [AudioClip]
    var isMuted: Bool = false
    var isSolo: Bool = false
    var isVisible: Bool = true
    
    init(
        id: String = UUID().uuidString,
        name: String,
        color: ClipColor = .coral,
        clips: [AudioClip] = []
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.clips = clips
    }
    
    /// 轨道上所有 clip 的总体持续时间
    var totalDuration: TimeInterval {
        guard !clips.isEmpty else { return 0 }
        return clips.map { $0.timelineStartTime + $0.duration }.max() ?? 0
    }
    
    /// 选中的 clip
    var selectedClip: AudioClip? {
        clips.first { $0.isSelected }
    }
    
    /// 选中或取消选中
    func selectClip(id: String) {
        for i in 0..<clips.count {
            clips[i].isSelected = (clips[i].id == id)
        }
    }
    
    func deselectAll() {
        for i in 0..<clips.count {
            clips[i].isSelected = false
        }
    }
}
