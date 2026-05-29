import Foundation
import AVFoundation

// MARK: - SilenceSegment
/// 静音段描述
struct SilenceSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    var duration: TimeInterval { endTime - startTime }
    var isSelected: Bool = true  // 默认选中删除
}

// MARK: - SilenceTrimCommand
/// 静音裁剪命令 — 检测并删除静音段，删除点交叉淡化
/// 用于 REQ-1.1-03
class SilenceTrimCommand: EditCommand {
    
    let description: String
    
    private let segments: [SilenceSegment]  // 要删除的静音段（已选中的）
    private let sampleRate: Double
    private let crossFadeDuration: TimeInterval = 0.05  // 50ms 交叉淡化
    
    // undo 数据
    private var originalBuffer: AVAudioPCMBuffer?
    
    /// 静音检测参数
    struct DetectionParams {
        var thresholdDB: Double = -40   // -60 ~ -20 dB
        var minDuration: TimeInterval = 1.0  // 0.5 ~ 3.0 秒
        
        var thresholdLinear: Float {
            Float(pow(10.0, thresholdDB / 20.0))
        }
    }
    
    init(segments: [SilenceSegment], sampleRate: Double) {
        let selected = segments.filter { $0.isSelected }
        self.segments = selected
        self.sampleRate = sampleRate
        self.description = "静音裁剪: 删除 \(selected.count) 个静音段"
    }
    
    // MARK: - Static Detection
    
    /// 检测音频中的静音段
    static func detectSilence(in buffer: AVAudioPCMBuffer, sampleRate: Double, params: DetectionParams) -> [SilenceSegment] {
        let channelCount = Int(buffer.format.channelCount)
        let totalFrames = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData, totalFrames > 0 else { return [] }
        
        let threshold = params.thresholdLinear
        let minFrames = Int(params.minDuration * sampleRate)
        
        // RMS 检测窗口（10ms）
        let windowSize = max(1, Int(sampleRate * 0.01))
        var segments: [SilenceSegment] = []
        var silenceStart: Int?
        
        var frame = 0
        while frame < totalFrames {
            let end = min(frame + windowSize, totalFrames)
            
            // 计算窗口 RMS
            var sumSquares: Float = 0
            for ch in 0..<channelCount {
                for f in frame..<end {
                    let s = channelData[ch][f]
                    sumSquares += s * s
                }
            }
            let rms = sqrt(sumSquares / Float((end - frame) * channelCount))
            
            if rms < threshold {
                // 静音
                if silenceStart == nil {
                    silenceStart = frame
                }
            } else {
                // 非静音：检查之前的静音段是否满足最小时长
                if let start = silenceStart {
                    let duration = frame - start
                    if duration >= minFrames {
                        segments.append(SilenceSegment(
                            startTime: Double(start) / sampleRate,
                            endTime: Double(frame) / sampleRate
                        ))
                    }
                    silenceStart = nil
                }
            }
            
            frame = end
        }
        
        // 处理尾部静音
        if let start = silenceStart {
            let duration = totalFrames - start
            if duration >= minFrames {
                segments.append(SilenceSegment(
                    startTime: Double(start) / sampleRate,
                    endTime: Double(totalFrames) / sampleRate
                ))
            }
        }
        
        return segments
    }
    
    // MARK: - Execute
    
    func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        let totalFrames = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        guard let channelData = buffer.floatChannelData, !segments.isEmpty else { return nil }
        
        // 保存原始数据（用于 undo）
        if let origBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength) {
            origBuf.frameLength = buffer.frameLength
            for ch in 0..<channelCount {
                memcpy(origBuf.floatChannelData![ch], channelData[ch], totalFrames * MemoryLayout<Float>.size)
            }
            originalBuffer = origBuf
        }
        
        // 按时间倒序排列（从后往前删除，避免索引偏移）
        let sortedSegments = segments.sorted { $0.startTime > $1.startTime }
        let crossFadeFrames = Int(crossFadeDuration * sampleRate)
        
        // 计算结果长度
        var removedFrames = 0
        for seg in sortedSegments {
            let startFrame = Int(seg.startTime * sampleRate)
            let endFrame = min(Int(seg.endTime * sampleRate), totalFrames)
            removedFrames += (endFrame - startFrame)
        }
        
        // BUG-009 fix: 预分配加 margin 防止浮点精度导致越界
        let resultFrames = AVAudioFrameCount(max(0, totalFrames - removedFrames))
        guard resultFrames > 0 else { return nil }
        let allocFrames = resultFrames + 1024  // safety margin
        
        // 构建保留区间
        var keepRanges: [(Int, Int)] = []  // (startFrame, endFrame)
        var prevEnd = 0
        let forwardSegments = segments.sorted { $0.startTime < $1.startTime }
        
        for seg in forwardSegments {
            let segStart = Int(seg.startTime * sampleRate)
            let segEnd = min(Int(seg.endTime * sampleRate), totalFrames)
            if segStart > prevEnd {
                keepRanges.append((prevEnd, segStart))
            }
            prevEnd = segEnd
        }
        if prevEnd < totalFrames {
            keepRanges.append((prevEnd, totalFrames))
        }
        
        // 拼接保留区间
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: allocFrames) else { return nil }
        result.frameLength = resultFrames
        
        var writeOffset = 0
        for (rangeStart, rangeEnd) in keepRanges {
            let length = rangeEnd - rangeStart
            guard length > 0 else { continue }
            
            for ch in 0..<channelCount {
                memcpy(
                    result.floatChannelData![ch].advanced(by: writeOffset),
                    channelData[ch].advanced(by: rangeStart),
                    length * MemoryLayout<Float>.size
                )
            }
            
            // 交叉淡化：在拼接点应用短淡出+淡入
            if writeOffset > 0 {
                let fadeLen = min(crossFadeFrames, writeOffset, length)
                for ch in 0..<channelCount {
                    // 拼接点前的淡出
                    for f in 0..<fadeLen {
                        let gain = Float(f) / Float(fadeLen)
                        let idx = writeOffset - fadeLen + f
                        if idx >= 0 && idx < Int(resultFrames) {
                            result.floatChannelData![ch][idx] *= (1.0 - gain) * 0.5 + 0.5
                        }
                    }
                    // 拼接点后的淡入
                    for f in 0..<fadeLen {
                        let gain = Float(f) / Float(fadeLen)
                        let idx = writeOffset + f
                        if idx < Int(resultFrames) {
                            result.floatChannelData![ch][idx] *= gain * 0.5 + 0.5
                        }
                    }
                }
            }
            
            writeOffset += length
        }
        
        // 修正实际帧长
        result.frameLength = AVAudioFrameCount(writeOffset)
        
        return result
    }
    
    // MARK: - Undo
    
    func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let original = originalBuffer else { return nil }
        let format = buffer.format
        let totalFrames = original.frameLength
        let channelCount = Int(format.channelCount)
        
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
        result.frameLength = totalFrames
        for ch in 0..<channelCount {
            memcpy(result.floatChannelData![ch], original.floatChannelData![ch], Int(totalFrames) * MemoryLayout<Float>.size)
        }
        return result
    }
}
