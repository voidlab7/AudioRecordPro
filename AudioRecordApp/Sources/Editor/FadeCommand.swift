import Foundation
import AVFoundation

// MARK: - Fade Curve Type
enum FadeCurveType: String, CaseIterable {
    case linear = "线性"
    case logarithmic = "对数"
    case sCurve = "S 曲线"
    
    /// 计算给定进度（0~1）下的增益
    func gain(at progress: Double) -> Double {
        switch self {
        case .linear:
            return progress
        case .logarithmic:
            // 对数曲线：起始快，结束慢
            return log10(1 + 9 * progress)
        case .sCurve:
            // S 曲线：smoothstep
            return progress * progress * (3 - 2 * progress)
        }
    }
}

// MARK: - FadeCommand
/// 淡入淡出命令 — 对选区或全局应用音量渐变
/// 用于 REQ-1.1-05
class FadeCommand: EditCommand {
    
    let description: String
    
    private let fadeInDuration: TimeInterval   // 淡入时长（秒），0 表示不淡入
    private let fadeOutDuration: TimeInterval  // 淡出时长（秒），0 表示不淡出
    private let curveType: FadeCurveType
    private let sampleRate: Double
    
    // undo 数据：保存被修改前的原始采样
    private var originalHead: AVAudioPCMBuffer?  // 淡入区域原始数据
    private var originalTail: AVAudioPCMBuffer?  // 淡出区域原始数据
    private let fadeInFrames: AVAudioFrameCount
    private let fadeOutFrames: AVAudioFrameCount
    
    init(fadeIn: TimeInterval, fadeOut: TimeInterval, curve: FadeCurveType, sampleRate: Double) {
        self.fadeInDuration = fadeIn
        self.fadeOutDuration = fadeOut
        self.curveType = curve
        self.sampleRate = sampleRate
        self.fadeInFrames = AVAudioFrameCount(fadeIn * sampleRate)
        self.fadeOutFrames = AVAudioFrameCount(fadeOut * sampleRate)
        
        var parts: [String] = []
        if fadeIn > 0 { parts.append("淡入 \(String(format: "%.1f", fadeIn))s") }
        if fadeOut > 0 { parts.append("淡出 \(String(format: "%.1f", fadeOut))s") }
        self.description = parts.joined(separator: " + ") + " (\(curve.rawValue))"
    }
    
    func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        let totalFrames = buffer.frameLength
        let channelCount = Int(format.channelCount)
        guard let channelData = buffer.floatChannelData else { return nil }
        
        // 创建结果 buffer（拷贝）
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
        result.frameLength = totalFrames
        for ch in 0..<channelCount {
            memcpy(result.floatChannelData![ch], channelData[ch], Int(totalFrames) * MemoryLayout<Float>.size)
        }
        
        // BUG-007 fix: 淡入+淡出 > 总帧数时等比缩放
        var actualFadeIn = min(fadeInFrames, totalFrames)
        var actualFadeOut = min(fadeOutFrames, totalFrames)
        if actualFadeIn + actualFadeOut > totalFrames {
            let ratio = Double(totalFrames) / Double(actualFadeIn + actualFadeOut)
            actualFadeIn = AVAudioFrameCount(Double(actualFadeIn) * ratio)
            actualFadeOut = totalFrames - actualFadeIn
        }
        
        // 保存淡入区域原始数据（用于 undo）
        if actualFadeIn > 0 {
            if let headBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: actualFadeIn) {
                headBuf.frameLength = actualFadeIn
                for ch in 0..<channelCount {
                    memcpy(headBuf.floatChannelData![ch], channelData[ch], Int(actualFadeIn) * MemoryLayout<Float>.size)
                }
                originalHead = headBuf
            }
        }
        
        // 保存淡出区域原始数据（用于 undo）
        if actualFadeOut > 0 {
            let tailStart = totalFrames - actualFadeOut
            if let tailBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: actualFadeOut) {
                tailBuf.frameLength = actualFadeOut
                for ch in 0..<channelCount {
                    memcpy(tailBuf.floatChannelData![ch], channelData[ch].advanced(by: Int(tailStart)), Int(actualFadeOut) * MemoryLayout<Float>.size)
                }
                originalTail = tailBuf
            }
        }
        
        // 应用淡入
        if actualFadeIn > 0 {
            for frame in 0..<Int(actualFadeIn) {
                let progress = Double(frame) / Double(actualFadeIn)
                let gain = Float(curveType.gain(at: progress))
                for ch in 0..<channelCount {
                    result.floatChannelData![ch][frame] *= gain
                }
            }
        }
        
        // 应用淡出
        if actualFadeOut > 0 {
            let fadeOutStart = Int(totalFrames - actualFadeOut)
            for frame in 0..<Int(actualFadeOut) {
                let progress = Double(frame) / Double(actualFadeOut)
                let gain = Float(curveType.gain(at: 1.0 - progress))  // 反向：1→0
                for ch in 0..<channelCount {
                    result.floatChannelData![ch][fadeOutStart + frame] *= gain
                }
            }
        }
        
        return result
    }
    
    func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        let totalFrames = buffer.frameLength
        let channelCount = Int(format.channelCount)
        guard let channelData = buffer.floatChannelData else { return nil }
        
        // 创建结果 buffer（拷贝）
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
        result.frameLength = totalFrames
        for ch in 0..<channelCount {
            memcpy(result.floatChannelData![ch], channelData[ch], Int(totalFrames) * MemoryLayout<Float>.size)
        }
        
        // 恢复淡入区域
        if let head = originalHead, let headData = head.floatChannelData {
            let headFrames = head.frameLength
            for ch in 0..<channelCount {
                memcpy(result.floatChannelData![ch], headData[ch], Int(headFrames) * MemoryLayout<Float>.size)
            }
        }
        
        // 恢复淡出区域
        if let tail = originalTail, let tailData = tail.floatChannelData {
            let tailFrames = tail.frameLength
            let tailStart = Int(totalFrames - tailFrames)
            for ch in 0..<channelCount {
                memcpy(result.floatChannelData![ch].advanced(by: tailStart), tailData[ch], Int(tailFrames) * MemoryLayout<Float>.size)
            }
        }
        
        return result
    }
}
