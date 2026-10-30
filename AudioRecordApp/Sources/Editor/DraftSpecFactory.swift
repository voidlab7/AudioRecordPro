import Foundation
import AVFoundation

// MARK: - DraftSpecFactory
/// FEAT-007: 草稿命令规格 → 命令实例（重放/渲染用）。
/// sampleRate/totalFrames 等运行时参数取自「重放时刻的 buffer」——草稿按序重放时
/// 每一步的 buffer 帧数与原始执行时确定一致，行为可复现。
enum DraftSpecFactory {

    /// 从 spec 构造命令；buffer 为该步执行前的 buffer（提供 sampleRate/totalFrames）
    static func command(from spec: DraftCommandSpec, buffer: AVAudioPCMBuffer) -> EditCommand? {
        let sampleRate = buffer.format.sampleRate
        let totalFrames = buffer.frameLength

        switch spec {
        case .trim(let start, let end):
            return TrimCommand(startTime: start, endTime: end,
                               sampleRate: sampleRate, totalFrames: totalFrames)
        case .deleteSelection(let start, let end):
            return DeleteSelectionCommand(startTime: start, endTime: end,
                                          sampleRate: sampleRate, totalFrames: totalFrames)
        case .split(let time):
            return SplitAudioClipCommand(time: time)
        case .silenceTrim(let segments):
            let silenceSegments = segments.map {
                SilenceSegment(startTime: $0.start, endTime: $0.end, isSelected: true)
            }
            return SilenceTrimCommand(segments: silenceSegments, sampleRate: sampleRate)
        case .normalize(let presetRaw, let customLUFS):
            let preset = NormalizePreset(rawValue: presetRaw) ?? .custom
            return NormalizeCommand(preset: preset, customLUFS: customLUFS, sampleRate: sampleRate)
        case .fade(let fadeIn, let fadeOut, let curveRaw):
            let curve = FadeCurveType(rawValue: curveRaw) ?? .linear
            return FadeCommand(fadeIn: fadeIn, fadeOut: fadeOut, curve: curve, sampleRate: sampleRate)
        }
    }
}
