import Foundation

// MARK: - FIX-010: 两态波形幅度映射唯一函数（全局线性）；FIX-018 修订：各态参考值统一固定满刻度 1.0
/// 录音态（WaveformView）/ 编辑态 legacy 路径（EditorWaveformView Phase1/2）/ tile 路径参考值均为满刻度 1.0
/// （FIX-018 老板 2026-10-29 拍板方案 A）。FIX-010 时代的录音态 running max 与编辑态整段 max 口径已废除：
/// 同电平永远同高，条落即定稿，录音中标尺不再随尖峰漂移。
/// 三处必须都走本函数，禁止再出现第二套口径（FIX-010 立单原因即两套口径漂移）。
///
/// 真静音（< −60 dBFS）返回 0，渲染层按各自最小高度画圆点行，不放大底噪（FIX-010 口径保留）。
/// FIX-018 修订注记：原「副作用（B 方案固有）——突发大声后历史条整体变矮且不恢复」已随固定满刻度废除。
public enum WaveformAmplitudeMapper {
    /// −60 dBFS 对应的线性满刻度值（10^(−60/20)）
    public static let silenceFloorLinear: Float = 0.001

    /// 峰值 → 0～1 高度（全局线性 + 静音门限）
    /// - Parameters:
    ///   - peak: 当前峰值（线性满刻度 0～1，负值按 0 处理）
    ///   - referenceMax: 参考最大峰值（FIX-018 起各态统一传 1.0；参数保留，供未来标定/特殊口径复用）
    public static func normalized(_ peak: Float, referenceMax: Float) -> Float {
        let p = max(0, peak)
        guard p > silenceFloorLinear, referenceMax > silenceFloorLinear else { return 0 }
        return min(1, p / referenceMax)
    }
}
