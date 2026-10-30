import Foundation
import AVFoundation

// MARK: - DraftRenderEngine
/// 草稿渲染引擎（FEAT-007）：原始 buffer + 命令栈重放 + 增益 → 编辑结果 buffer。
/// 导出（ExportService）与编辑器自验共用同一核心，保证「所见即所导」。
/// 命令构造经 factory 注入——命令具体类型在 App 层，Kit 侧保持纯逻辑可测。
public enum DraftRenderEngine {

    /// 渲染编辑结果。
    /// - Parameters:
    ///   - input: 原始音频 buffer（不被修改；渲染在新拷贝上进行）
    ///   - commands: 草稿命令栈
    ///   - currentIndex: 撤销指针（-1 = 全部已撤销，仅应用增益）
    ///   - clipGain: 增益（线性倍率，渲染末端统一应用并限幅 [-1, 1]）
    ///   - factory: spec → EditCommand 构造器（App 层提供真实命令；测试注入桩命令）
    /// - Returns: 渲染结果；任一命令构造/执行失败返回 nil
    public static func render(input: AVAudioPCMBuffer,
                              commands: [DraftCommandSpec],
                              currentIndex: Int,
                              clipGain: Float,
                              factory: (DraftCommandSpec, AVAudioPCMBuffer) -> EditCommand?) -> AVAudioPCMBuffer? {
        guard var buffer = duplicate(input) else { return nil }

        let target = min(currentIndex, commands.count - 1)
        if target >= 0 {
            for i in 0...target {
                guard let command = factory(commands[i], buffer),
                      let next = command.execute(on: buffer) else {
                    return nil
                }
                buffer = next
            }
        }

        return applyGain(clipGain, to: buffer)
    }

    // MARK: - 增益

    /// 应用增益并限幅（0dBFS 硬限幅，防 16bit 目标格式削波爆音）
    public static func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard abs(gain - 1.0) > 0.0001 else { return buffer }
        guard let channelData = buffer.floatChannelData else { return buffer }
        let channelCount = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for ch in 0..<channelCount {
            for f in 0..<frames {
                var sample = channelData[ch][f] * gain
                if sample > 1.0 { sample = 1.0 }
                if sample < -1.0 { sample = -1.0 }
                channelData[ch][f] = sample
            }
        }
        return buffer
    }

    // MARK: - 拷贝

    /// 深拷贝 PCM buffer（渲染不污染输入）
    public static func duplicate(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frames = buffer.frameLength
        guard frames > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames) else { return nil }
        copy.frameLength = frames
        guard let src = buffer.floatChannelData, let dst = copy.floatChannelData else { return copy }
        let channelCount = Int(buffer.format.channelCount)
        let bytes = Int(frames) * MemoryLayout<Float>.size
        for ch in 0..<channelCount {
            memcpy(dst[ch], src[ch], bytes)
        }
        return copy
    }
}
