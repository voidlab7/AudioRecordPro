import Foundation

/// 音频源描述 — Phase 0 止血：轻量级包装，不动 AudioRecordKit 的 AudioSourceType enum
/// Phase 1 将引入完整 AudioSource struct 替代 AudioSourceType
struct AudioSource: Hashable {
    /// 音源类型
    enum Kind: Hashable {
        case system          // 全部系统声音
        case microphone      // 麦克风
        case process(pid: pid_t, name: String, bundleID: String?)
    }

    let kind: Kind

    /// 显示名称
    var displayName: String {
        switch kind {
        case .system:     return "全部系统声音"
        case .microphone: return "麦克风"
        case .process(_, let name, _): return name
        }
    }

    /// 选中时传给 AudioRecorderController 的 PID（仅 process 类型有值）
    var pid: pid_t? {
        switch kind {
        case .process(let pid, _, _): return pid
        default: return nil
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        switch kind {
        case .system:            hasher.combine("system")
        case .microphone:        hasher.combine("microphone")
        case .process(let pid, _, _): hasher.combine(pid)
        }
    }

    static func == (lhs: AudioSource, rhs: AudioSource) -> Bool {
        switch (lhs.kind, rhs.kind) {
        case (.system, .system), (.microphone, .microphone): return true
        case (.process(let p1, _, _), .process(let p2, _, _)): return p1 == p2
        default: return false
        }
    }
}
