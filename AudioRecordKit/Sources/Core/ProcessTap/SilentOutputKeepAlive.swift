import AVFoundation
import Foundation

/// FIX-004: 录音期间保活系统输出设备（静音播放）。
///
/// 根因：全局 Process Tap 依附输出设备时钟——系统完全静音时输出硬件休眠，
/// 聚合设备无 IO 回调，表现为「计时走、波形/电平全无、落盘 0 帧」。
/// 实测证据（2026-10-13 selftest）：静音系统下录 5s，「总共写入 0 帧」；
/// 有声场次 IO 延迟 +2.8s（设备唤醒）或 +30ms（设备已在运行）。
/// 修法：录音期间以零采样持续播放（AudioCap 同款思路），迫使输出设备保持运行，
/// Tap 即可收到真实的零值帧——静音段波形基线/电平地板随之恢复。
final class SilentOutputKeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isKeepingAlive = false
    private let logger = Logger.shared

    /// 启动静音保活（幂等）
    func start() {
        guard !isKeepingAlive else { return }
        let format = engine.outputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            logger.error("❌ [FIX004] 静音保活: 输出设备格式无效，跳过")
            return
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(Self.silentBuffer(format: format), at: nil, options: .loops)
        do {
            try engine.start()
            player.play()
            isKeepingAlive = true
            logger.info("🔇 [FIX004] 静音保活已启动 sr=\(format.sampleRate) ch=\(format.channelCount)")
        } catch {
            logger.error("❌ [FIX004] 静音保活启动失败: \(error.localizedDescription)")
            engine.stop()
            engine.detach(player)
        }
    }

    /// 停止保活（幂等）
    func stop() {
        guard isKeepingAlive else { return }
        player.stop()
        engine.stop()
        engine.detach(player)
        isKeepingAlive = false
        logger.info("🔇 [FIX004] 静音保活已停止")
    }

    /// 1 秒长全零 PCM 缓冲（Float32 非交织，零填充即静音）
    private static func silentBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) ?? AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!,
            frameCapacity: 48000
        )!
        buffer.frameLength = frames
        return buffer
    }
}
