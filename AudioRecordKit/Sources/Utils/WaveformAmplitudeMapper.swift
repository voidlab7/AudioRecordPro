import Foundation

// MARK: - FIX-010: 两态波形幅度映射唯一函数（老板 2026-10-16 选 B：全局线性）
/// 录音态（WaveformView）参考值 = 自开始录音起的累计最大峰值（running max，只增不减）；
/// 编辑态（EditorWaveformView legacy 路径）参考值 = 整段最大峰值；tile 路径参考值 = 满刻度 1.0。
/// 三处必须都走本函数，禁止再出现第二套口径（FIX-010 立单原因即两套口径漂移）。
///
/// 真静音（< −60 dBFS）返回 0，渲染层按各自最小高度画圆点行，不放大底噪。
/// 副作用（B 方案固有，老板已知情接受）：录音中出现一次突发大声后，后续正常段条形整体变矮且不恢复。
public enum WaveformAmplitudeMapper {
    /// −60 dBFS 对应的线性满刻度值（10^(−60/20)）
    public static let silenceFloorLinear: Float = 0.001

    /// 峰值 → 0～1 高度（全局线性 + 静音门限）
    /// - Parameters:
    ///   - peak: 当前峰值（线性满刻度 0～1，负值按 0 处理）
    ///   - referenceMax: 参考最大峰值（录音态=running max / 编辑态=整段 max / tile=1.0）
    public static func normalized(_ peak: Float, referenceMax: Float) -> Float {
        let p = max(0, peak)
        guard p > silenceFloorLinear, referenceMax > silenceFloorLinear else { return 0 }
        return min(1, p / referenceMax)
    }
}
