import Foundation
import AVFoundation

// MARK: - TrimCommand
/// 裁剪命令 — 删除选区外的音频（保留选区内的部分）
/// 用于 REQ-1.1-02 裁剪首尾
class TrimCommand: EditCommand {
    
    let description: String
    
    /// 保留区间（帧范围）
    private let keepRange: Range<AVAudioFramePosition>
    
    /// undo 数据：被裁掉的头部和尾部
    private var removedHead: AVAudioPCMBuffer?
    private var removedTail: AVAudioPCMBuffer?
    private let originalFrameLength: AVAudioFrameCount
    
    /// 初始化裁剪命令
    /// - Parameters:
    ///   - startTime: 保留区间起始时间（秒）
    ///   - endTime: 保留区间结束时间（秒）
    ///   - sampleRate: 采样率
    ///   - totalFrames: 总帧数
    init(startTime: TimeInterval, endTime: TimeInterval, sampleRate: Double, totalFrames: AVAudioFrameCount) {
        let startFrame = AVAudioFramePosition(startTime * sampleRate)
        let endFrame = min(AVAudioFramePosition(endTime * sampleRate), AVAudioFramePosition(totalFrames))
        self.keepRange = startFrame..<endFrame
        self.originalFrameLength = totalFrames
        
        let trimmedStart = String(format: "%.1f", startTime)
        let trimmedEnd = String(format: "%.1f", endTime)
        self.description = "裁剪: 保留 \(trimmedStart)s ~ \(trimmedEnd)s"
    }
    
    func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        let totalFrames = AVAudioFramePosition(buffer.frameLength)
        
        let keepStart = max(0, keepRange.lowerBound)
        let keepEnd = min(totalFrames, keepRange.upperBound)
        let keepLength = AVAudioFrameCount(keepEnd - keepStart)
        
        guard keepLength > 0 else { return nil }
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)
        
        // 保存被裁掉的头部（用于 undo）
        if keepStart > 0 {
            let headLength = AVAudioFrameCount(keepStart)
            if let headBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: headLength) {
                headBuffer.frameLength = headLength
                for ch in 0..<channelCount {
                    memcpy(headBuffer.floatChannelData![ch], channelData[ch], Int(headLength) * MemoryLayout<Float>.size)
                }
                removedHead = headBuffer
            }
        }
        
        // 保存被裁掉的尾部（用于 undo）
        if keepEnd < totalFrames {
            let tailLength = AVAudioFrameCount(totalFrames - keepEnd)
            if let tailBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: tailLength) {
                tailBuffer.frameLength = tailLength
                for ch in 0..<channelCount {
                    let srcPtr = channelData[ch].advanced(by: Int(keepEnd))
                    memcpy(tailBuffer.floatChannelData![ch], srcPtr, Int(tailLength) * MemoryLayout<Float>.size)
                }
                removedTail = tailBuffer
            }
        }
        
        // 创建裁剪后的 buffer
        guard let resultBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: keepLength) else { return nil }
        resultBuffer.frameLength = keepLength
        
        for ch in 0..<channelCount {
            let srcPtr = channelData[ch].advanced(by: Int(keepStart))
            memcpy(resultBuffer.floatChannelData![ch], srcPtr, Int(keepLength) * MemoryLayout<Float>.size)
        }
        
        return resultBuffer
    }
    
    func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        let channelCount = Int(format.channelCount)
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let headFrames = AVAudioFrameCount(removedHead?.frameLength ?? 0)
        let tailFrames = AVAudioFrameCount(removedTail?.frameLength ?? 0)
        let currentFrames = buffer.frameLength
        let restoredLength = headFrames + currentFrames + tailFrames
        
        guard let resultBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: restoredLength) else { return nil }
        resultBuffer.frameLength = restoredLength
        
        for ch in 0..<channelCount {
            var offset = 0
            
            // 恢复头部
            if let head = removedHead, let headData = head.floatChannelData {
                memcpy(resultBuffer.floatChannelData![ch].advanced(by: offset), headData[ch], Int(headFrames) * MemoryLayout<Float>.size)
                offset += Int(headFrames)
            }
            
            // 恢复当前数据（中间部分）
            memcpy(resultBuffer.floatChannelData![ch].advanced(by: offset), channelData[ch], Int(currentFrames) * MemoryLayout<Float>.size)
            offset += Int(currentFrames)
            
            // 恢复尾部
            if let tail = removedTail, let tailData = tail.floatChannelData {
                memcpy(resultBuffer.floatChannelData![ch].advanced(by: offset), tailData[ch], Int(tailFrames) * MemoryLayout<Float>.size)
            }
        }
        
        return resultBuffer
    }
}
