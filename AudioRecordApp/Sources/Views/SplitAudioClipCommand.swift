import Foundation
import AVFoundation

// MARK: - UI-023: 切分命令转正（口径 A · buffer 级真拆分）
/// 语义（剪映同款）：**切分不改变时间轴音频**。
/// - `execute` 在切分点按样本级定位（`round(time × sampleRate)`）把原 buffer 深拷贝切成
///   前/后两个子 buffer（`segments`），时间轴 buffer 原样返回——样本总数不变、无缝无重叠；
/// - `undo` 丢弃产物还原单 clip；`redo`（EditHistory 重放 execute）确定性重建产物；
/// - 边界拒切：切分点落在 0 或末尾（不建空 clip）时 `execute` 返回 nil，不入历史。
/// 迁移注记：clip 级渲染/独立裁剪需区间视图模型（B 迁移），见 TODOS 回池单。
class SplitAudioClipCommand: EditCommand {
    let description: String
    private let time: TimeInterval

    /// 切分产物 [前段, 后段]（execute 成功后非空；undo 清空，redo 重建）
    private(set) var segments: [AVAudioPCMBuffer] = []
    /// 切分样本位（相对原 buffer；execute 成功后有效）
    private(set) var splitFrame: AVAudioFramePosition = 0

    init(time: TimeInterval) {
        self.time = time
        self.description = "切分 @ %@s".localized(String(format: "%.2f", time))
    }

    func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard time.isFinite else { return nil }
        let total = AVAudioFramePosition(buffer.frameLength)
        // 样本级切分点：round(time × sampleRate)，不引入 ±1 帧漂移
        let frame = AVAudioFramePosition((time * buffer.format.sampleRate).rounded())
        // 边界拒切：0 或末尾不建空 clip
        guard frame > 0, frame < total else { return nil }
        guard let left = slice(buffer, 0..<frame),
              let right = slice(buffer, frame..<total) else { return nil }
        // 不变量：两段样本总数 == 原样本数（无缝、无重叠）
        guard left.frameLength + right.frameLength == buffer.frameLength else { return nil }
        segments = [left, right]
        splitFrame = frame
        return buffer
    }

    func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        segments = []
        splitFrame = 0
        return buffer
    }

    // MARK: - 样本级切片（深拷贝）

    /// 从 buffer 复制 [range) 帧区间为新 buffer。
    /// 兼容交错/非交错格式：交错按整块 memcpy，非交错逐 channel 拷贝。
    private func slice(_ src: AVAudioPCMBuffer, _ range: Range<AVAudioFramePosition>) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(range.upperBound - range.lowerBound)
        guard frames > 0,
              let dst = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: frames) else { return nil }
        dst.frameLength = frames

        let bytesPerFrame = Int(src.format.streamDescription.pointee.mBytesPerFrame)
        let startByte = Int(range.lowerBound) * bytesPerFrame
        let copyBytes = Int(frames) * bytesPerFrame
        let srcList = UnsafeMutableAudioBufferListPointer(src.mutableAudioBufferList)
        let dstList = UnsafeMutableAudioBufferListPointer(dst.mutableAudioBufferList)

        if src.format.isInterleaved {
            guard let sp = srcList[0].mData, let dp = dstList[0].mData,
                  startByte + copyBytes <= Int(srcList[0].mDataByteSize) else { return nil }
            memcpy(dp, sp.advanced(by: startByte), copyBytes)
        } else {
            for ch in 0..<min(srcList.count, dstList.count) {
                guard let sp = srcList[ch].mData, let dp = dstList[ch].mData,
                      startByte + copyBytes <= Int(srcList[ch].mDataByteSize) else { return nil }
                memcpy(dp, sp.advanced(by: startByte), copyBytes)
            }
        }
        return dst
    }
}
