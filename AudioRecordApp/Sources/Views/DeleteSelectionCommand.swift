import Foundation
import AVFoundation

// MARK: - DeleteSelectionCommand（UI-022）
/// 删除选区命令 — 删掉选区 [start, end) 样本后拼接前段+后段
/// undo 还原原 buffer（与 TrimCommand 语义一致：execute 存被删段与前段帧数，undo 按位拼回）
/// 全选删除返回 0 帧 buffer（空态，frameCapacity 1），EditHistory 正常入栈、undo 可还原
class DeleteSelectionCommand: EditCommand {

    let description: String

    /// FEAT-007: 草稿规格（重放所需 init 参数）
    let draftSpec: DraftCommandSpec

    /// 待删除帧区间
    private let deleteRange: Range<AVAudioFramePosition>

    /// undo 数据：被删除的段
    private var removed: AVAudioPCMBuffer?
    /// 删除点之前保留的帧数（execute 时锁定；undo 按此拼回）
    private var headFrames: AVAudioFrameCount = 0

    /// - Parameters:
    ///   - startTime/endTime: 选区时间（秒）
    ///   - sampleRate: 采样率
    ///   - totalFrames: 总帧数（endFrame 夹取上限）
    init(startTime: TimeInterval, endTime: TimeInterval, sampleRate: Double, totalFrames: AVAudioFrameCount) {
        let start = max(0, AVAudioFramePosition((startTime * sampleRate).rounded()))
        let end = min(AVAudioFramePosition((endTime * sampleRate).rounded()),
                      AVAudioFramePosition(totalFrames))
        // 逆向/零长统一归零长区间（Range 不允许 lower > upper，直接构造会崩），execute 拒切
        self.deleteRange = (end > start) ? start..<end : start..<start
        self.draftSpec = .deleteSelection(start: startTime, end: endTime)
        self.description = "删除 @ %@s - %@s".localized(
            String(format: "%.1f", startTime), String(format: "%.1f", endTime))
    }

    func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        let total = AVAudioFramePosition(buffer.frameLength)
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)

        let start = max(0, deleteRange.lowerBound)
        let end = min(total, deleteRange.upperBound)
        let delFrames = end - start
        // 空删除 / 逆向选区拒切
        guard delFrames > 0, start < total else { return nil }

        // 存被删段（undo 用）
        guard let removedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(delFrames)) else { return nil }
        removedBuffer.frameLength = AVAudioFrameCount(delFrames)
        for ch in 0..<channelCount {
            memcpy(removedBuffer.floatChannelData![ch],
                   channelData[ch].advanced(by: Int(start)),
                   Int(delFrames) * MemoryLayout<Float>.size)
        }
        removed = removedBuffer
        headFrames = AVAudioFrameCount(start)

        let keepFrames = AVAudioFrameCount(total - delFrames)
        // 空态：全选删除 → 0 帧 buffer（frameCapacity 至少 1，frameLength=0）
        guard let resultBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, keepFrames)) else { return nil }
        resultBuffer.frameLength = keepFrames

        // 拼接：前段 [0, start) + 后段 [end, total)
        let tailFrames = AVAudioFrameCount(total - end)
        for ch in 0..<channelCount {
            if headFrames > 0 {
                memcpy(resultBuffer.floatChannelData![ch],
                       channelData[ch], Int(headFrames) * MemoryLayout<Float>.size)
            }
            if tailFrames > 0 {
                memcpy(resultBuffer.floatChannelData![ch].advanced(by: Int(headFrames)),
                       channelData[ch].advanced(by: Int(end)),
                       Int(tailFrames) * MemoryLayout<Float>.size)
            }
        }
        return resultBuffer
    }

    func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let removed = removed, let removedData = removed.floatChannelData else { return nil }
        let format = buffer.format
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)

        let removedFrames = removed.frameLength
        let currentFrames = buffer.frameLength
        // 当前 buffer = 前段(headFrames) + 后段；校验一致性（防错序 undo）
        guard currentFrames + removedFrames >= headFrames + removedFrames else { return nil }
        let tailFrames = currentFrames - headFrames

        let restoredLength = currentFrames + removedFrames
        guard let resultBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: restoredLength) else { return nil }
        resultBuffer.frameLength = restoredLength

        for ch in 0..<channelCount {
            // 前段原位
            if headFrames > 0 {
                memcpy(resultBuffer.floatChannelData![ch],
                       channelData[ch], Int(headFrames) * MemoryLayout<Float>.size)
            }
            // 被删段插回删除点
            memcpy(resultBuffer.floatChannelData![ch].advanced(by: Int(headFrames)),
                   removedData[ch], Int(removedFrames) * MemoryLayout<Float>.size)
            // 后段接上
            if tailFrames > 0 {
                memcpy(resultBuffer.floatChannelData![ch].advanced(by: Int(headFrames) + Int(removedFrames)),
                       channelData[ch].advanced(by: Int(headFrames)),
                       Int(tailFrames) * MemoryLayout<Float>.size)
            }
        }
        return resultBuffer
    }
}
