import Foundation

// MARK: - GainScale
/// 增益标尺单一来源（FIX-020）：±dB 量程、dB↔线性换算、线性钳制、回放增益映射。
/// 语义（剪映同款）：0dB = 1.0 原声；+20dB = 10.0 放大上限；−24dB 贴底；0（静音）= 无声。
/// 消费方：EditorWaveformView（音量线拖拽/渲染）、EditDraft（草稿存储钳制）、
/// EditorViewController（回放链 EQ globalGain）。预览与导出共用同一线性增益定义，
/// 严禁在别处再写硬编码 2.0/10.0/±dB 口径。
public enum GainScale {

    /// 量程下限（dB）——UI-036 R15g 拍板标尺
    public static let minDB: Double = -24.0
    /// 量程上限（dB）——UI-036 R15g 拍板标尺（0dB 水位 38% 的正区间顶）
    public static let maxDB: Double = 20.0
    /// gain=0（贴底静音）在回放链上的等效 dB（EQ globalGain 量程下限，足够 −∞ 听感）
    public static let muteDB: Double = -96.0

    /// dB → 线性倍率（10^(dB/20)）
    public static func linear(fromDB db: Double) -> Float {
        Float(pow(10.0, db / 20.0))
    }

    /// 量程上限的线性倍率（+20dB → 10.0）
    public static var maxLinear: Float { linear(fromDB: maxDB) }

    /// 线性倍率钳制到标尺量程 [0, maxLinear]（0 = 静音合法值）
    public static func clampLinear(_ gain: Float) -> Float {
        max(0, min(gain, maxLinear))
    }

    /// 线性倍率 → dB（20·log10；0/极小值收敛到 −80dB 仅供显示，静音映射请用 playbackDB）
    public static func db(fromLinear gain: Float) -> Double {
        20 * log10(Double(max(gain, 0.0001)))
    }

    /// 回放增益映射：线性倍率 → 回放链节点增益（dB）。
    /// 单一路径：预览链路唯一经由此把 clipGain 换算成 EQ globalGain；
    /// gain≤0 直接给 muteDB（真静音，不受 log 底数收敛影响）。
    public static func playbackDB(for linearGain: Float) -> Double {
        guard linearGain > 0 else { return muteDB }
        return min(db(fromLinear: linearGain), maxDB)
    }
}
