import Foundation
import AVFoundation

// MARK: - Normalize Preset
enum NormalizePreset: String, CaseIterable {
    case podcast = "播客"      // -16 LUFS
    case youtube = "YouTube"   // -14 LUFS
    case broadcast = "广播"    // -24 LUFS
    case custom = "自定义"
    
    var targetLUFS: Double {
        switch self {
        case .podcast: return -16
        case .youtube: return -14
        case .broadcast: return -24
        case .custom: return -16  // 默认值，实际由用户指定
        }
    }
}

// MARK: - NormalizeCommand
/// 音量标准化命令 — 基于 LUFS 算法归一化响度
/// 用于 REQ-1.1-04
class NormalizeCommand: EditCommand {
    
    let description: String
    
    private let targetLUFS: Double
    private let truePeakLimit: Double  // dBTP
    private let sampleRate: Double
    
    // undo 数据：保存增益系数的倒数（精确恢复）
    private var appliedGain: Float = 1.0
    private var originalBuffer: AVAudioPCMBuffer?  // 降级方案：保存原始数据
    
    init(preset: NormalizePreset, customLUFS: Double? = nil, sampleRate: Double) {
        self.targetLUFS = customLUFS ?? preset.targetLUFS
        self.truePeakLimit = -1.0  // -1 dBTP
        self.sampleRate = sampleRate
        self.description = "标准化: \(preset.rawValue) (\(String(format: "%.0f", customLUFS ?? preset.targetLUFS)) LUFS)"
    }
    
    func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        let totalFrames = buffer.frameLength
        let channelCount = Int(format.channelCount)
        guard let channelData = buffer.floatChannelData, totalFrames > 0 else { return nil }
        
        // 1. 计算当前 LUFS（简化版：使用 RMS 近似）
        let currentLUFS = measureLUFS(buffer: buffer)
        
        // 如果太安静（接近静音），提示
        guard currentLUFS > -70 else {
            // 信号太弱，无法有效标准化
            return nil
        }
        
        // 2. 计算目标增益
        let gainDB = targetLUFS - currentLUFS
        var gain = Float(pow(10.0, gainDB / 20.0))
        
        // 3. 检查 True Peak 限制
        let currentPeak = findPeak(buffer: buffer)
        let peakAfterGain = currentPeak * gain
        let truePeakLinear = Float(pow(10.0, truePeakLimit / 20.0))  // -1 dBTP → 0.891
        
        if peakAfterGain > truePeakLinear {
            // 限制增益以满足峰值要求
            gain = truePeakLinear / currentPeak
        }
        
        // 保存原始数据（用于 undo）
        if let origBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) {
            origBuf.frameLength = totalFrames
            for ch in 0..<channelCount {
                memcpy(origBuf.floatChannelData![ch], channelData[ch], Int(totalFrames) * MemoryLayout<Float>.size)
            }
            originalBuffer = origBuf
        }
        
        appliedGain = gain
        
        // 4. 应用增益
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
        result.frameLength = totalFrames
        
        for ch in 0..<channelCount {
            for frame in 0..<Int(totalFrames) {
                var sample = channelData[ch][frame] * gain
                // 软限幅（soft clipping）防止削波
                if sample > truePeakLinear { sample = truePeakLinear }
                if sample < -truePeakLinear { sample = -truePeakLinear }
                result.floatChannelData![ch][frame] = sample
            }
        }
        
        return result
    }
    
    func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // 优先使用保存的原始数据（精确恢复）
        if let original = originalBuffer {
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
        return nil
    }
    
    // MARK: - LUFS Measurement
    
    /// 简化版 LUFS 测量（基于 K-weighted RMS）
    private func measureLUFS(buffer: AVAudioPCMBuffer) -> Double {
        let channelCount = Int(buffer.format.channelCount)
        let totalFrames = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData, totalFrames > 0 else { return -70 }
        
        // 计算所有声道的均方和
        var sumSquares: Double = 0
        for ch in 0..<channelCount {
            for frame in 0..<totalFrames {
                let sample = Double(channelData[ch][frame])
                sumSquares += sample * sample
            }
        }
        
        let meanSquare = sumSquares / Double(totalFrames * channelCount)
        guard meanSquare > 0 else { return -70 }
        
        // LUFS ≈ -0.691 + 10 * log10(meanSquare)
        // 简化：使用 RMS → dBFS → 近似 LUFS
        let rmsDB = 10 * log10(meanSquare)
        return rmsDB - 0.691
    }
    
    /// 查找峰值
    private func findPeak(buffer: AVAudioPCMBuffer) -> Float {
        let channelCount = Int(buffer.format.channelCount)
        let totalFrames = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        var peak: Float = 0
        for ch in 0..<channelCount {
            for frame in 0..<totalFrames {
                let sample = abs(channelData[ch][frame])
                if sample > peak { peak = sample }
            }
        }
        return peak
    }
}
