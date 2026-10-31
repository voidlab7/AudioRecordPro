import Foundation

// MARK: - UI-041: 编辑器波形逐列真峰值（分辨率随缩放）
/// 痛点（老板 2026-10-31 实机反馈「放大后有一些是完全平的」「剪映有波纹」）：
/// legacy 路径 allSamples 是全文件固定桶（Phase1 100–600 / Phase2 200–2000，按 fitAll 视图
/// 宽度 1:1 生成），放大 N 倍后每桶复制 N 列 + 3 点平滑 → 底噪区呈恒定死平带。
/// 取证：静音区底噪 −38~−45dBFS 波形成分实际存在（解密当天录音逐段实测），只是画不出来
/// ——渲染精度伪影，非数据/门限问题。
///
/// 本文件只做无状态纯计算（可单测）；buffer 持有与视口缓存在 EditorWaveformView。
/// 归一口径沿用 `WaveformAmplitudeMapper.normalized(referenceMax: 1.0)`（FIX-018 满刻度，
/// 三处同口径铁律）；−60dBFS 真静音列返回 0（FIX-010 门限保留，渲染层画发丝基线）。
public enum WaveformViewportPeaks {
    /// 桶复制态判定：视口内可用粗预览桶密度低于屏幕列密度（每桶将横跨 ≥1 列被复制）。
    /// false = fitAll 概览态，粗路径零开销不变。
    public static func needsFinePath(allSamplesCount: Int,
                                     totalDuration: TimeInterval,
                                     visibleDuration: TimeInterval,
                                     pixelCount: Int) -> Bool {
        guard allSamplesCount > 0, totalDuration > 0,
              visibleDuration > 0, pixelCount > 1 else { return false }
        let bucketsInView = Double(allSamplesCount) * visibleDuration / totalDuration
        return bucketsInView < Double(pixelCount)
    }

    /// 视口逐列真峰值：列 i = 可视时间窗 [start+i·dt, start+(i+1)·dt) 内全部帧的多通道峰值。
    /// - Parameters:
    ///   - maxFramesPerColumn: stride 护栏——单列帧数超过该值时等距跳采（峰值近似）。
    ///     波形显示只需起伏形态：10 分钟文件 2880 万帧 / 850 列 ≈ 3.4 万帧/列，
    ///     全扫 30–50ms 会卡滚动，跳采后 <2ms。
    /// - Returns: 已过 `WaveformAmplitudeMapper.normalized(_:referenceMax: 1.0)`，长度 == pixelCount。
    public static func columnPeaks(channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
                                   channels: Int,
                                   totalFrames: Int,
                                   sampleRate: Double,
                                   visibleStart: TimeInterval,
                                   visibleDuration: TimeInterval,
                                   pixelCount: Int,
                                   maxFramesPerColumn: Int = 4096) -> [Float] {
        let count = max(0, pixelCount)
        guard totalFrames > 0, sampleRate > 0,
              visibleDuration > 0, pixelCount > 1, channels > 0 else {
            return [Float](repeating: 0, count: count)
        }

        let startFrameF = max(0, visibleStart) * sampleRate
        let framesSpan = visibleDuration * sampleRate

        var peaks = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let f0 = Int(startFrameF + Double(i) / Double(pixelCount) * framesSpan)
            let f1 = Int(startFrameF + Double(i + 1) / Double(pixelCount) * framesSpan)
            let lo = min(max(f0, 0), totalFrames)
            guard lo < totalFrames else { continue }  // 视口超出末尾：列保持 0
            let hi = min(max(f1, lo + 1), totalFrames)

            let step = max(1, (hi - lo) / max(1, maxFramesPerColumn))
            var peak: Float = 0
            for ch in 0..<channels {
                let ptr = channelData[ch]
                var f = lo
                while f < hi {
                    let s = ptr[f]
                    let a = s < 0 ? -s : s
                    if a > peak { peak = a }
                    f += step
                }
            }
            peaks[i] = WaveformAmplitudeMapper.normalized(peak, referenceMax: 1.0)
        }
        return peaks
    }
}
