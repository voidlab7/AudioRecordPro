import XCTest
@testable import AudioRecordKit
import AVFoundation

/// FIX-020 硬验证：预览回放链（playerNode → EQ(globalGain) → mainMixer）离线渲染取 RMS。
/// 与 App 内 startPreview 构链同一配方（AVAudioEngine offline manual rendering，无需音频设备），
/// 证明四件事：
/// 1) 升益有效——+6dB → RMS ≈ 2×（旧实现 playerNode.volume 钳 1.0，恒等于基线）
/// 2) 降益精确——−12dB → RMS ≈ 0.25×
/// 3) 0dB 透明——旁路频段 EQ + mainMixer 不染色信号
/// 4) 全标尺可放大——+12dB / +20dB（标尺上限）比值精确（旧实现 >0dB 完全无效）
/// 过载说明：链路末端不做软限幅（macOS 26 SDK 已移除 AVAudioUnitDynamicsProcessor，
/// 见 EditorViewController.startPreview 注释）；超满刻度由输出设备硬削波，与导出 ±1 限幅同口径。
final class PreviewGainChainTests: XCTestCase {

    private let sampleRate: Double = 44_100

    // MARK: - 预览链路构链（与 EditorViewController.startPreview 同配方）

    private func makeSineBuffer(amplitude: Float, seconds: Double = 0.5) throws -> AVAudioPCMBuffer {
        // 2ch 立体声：与真实录音（系统混音）一致；mono 会经 mainMixer 声像定律吃 −3dB，
        // 增益比值断言不受影响，但绝对透明度断言需以立体声口径为准
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0..<2 {
            for i in 0..<Int(frames) {
                buffer.floatChannelData![ch][i] = amplitude * sinf(2.0 * .pi * 440.0 * Float(i) / Float(sampleRate))
            }
        }
        return buffer
    }

    /// 按预览链路配方离线渲染，返回 (rms, peak)。分块 renderOffline 累积到样本数组。
    private func renderThroughPreviewChain(gainDB: Double, amplitude: Float) throws -> (rms: Float, peak: Float) {
        let input = try makeSineBuffer(amplitude: amplitude)
        let outFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        // 与 EditorViewController.startPreview 同配方：旁路频段 EQ 承担 globalGain 全带增益
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        eq.bands[0].filterType = .parametric
        eq.bands[0].bypass = true
        engine.attach(player)
        engine.attach(eq)
        engine.connect(player, to: eq, format: input.format)
        engine.connect(eq, to: engine.mainMixerNode, format: input.format)
        eq.globalGain = Float(gainDB)

        try engine.enableManualRenderingMode(.offline, format: outFormat, maximumFrameCount: 4096)
        try engine.start()
        player.scheduleBuffer(input, completionHandler: nil)
        player.play()

        let chunkFrames: AVAudioFrameCount = 4096
        let chunkBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: chunkFrames)!
        var samples: [Float] = []
        samples.reserveCapacity(Int(input.frameLength) * 2)
        var done: AVAudioFrameCount = 0
        var noProgress = 0
        while done < input.frameLength {
            let n = min(chunkFrames, input.frameLength - done)
            let status = try engine.renderOffline(n, to: chunkBuf)
            switch status {
            case .success:
                let written = Int(chunkBuf.frameLength)
                guard written > 0 else {
                    noProgress += 1
                    if noProgress > 100 { XCTFail("renderOffline 零进度"); return (0, 0) }
                    continue
                }
                noProgress = 0
                let data = chunkBuf.floatChannelData![0]  // 0dB 声像下 L=R，单通道计量即可
                for i in 0..<written { samples.append(data[i]) }
                done += AVAudioFrameCount(written)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                noProgress += 1
                if noProgress > 100 { XCTFail("renderOffline 反复重试不推进"); return (0, 0) }
            case .error:
                XCTFail("renderOffline error")
                return (0, 0)
            @unknown default:
                XCTFail("unknown render status")
                return (0, 0)
            }
        }
        engine.stop()

        XCTAssertGreaterThanOrEqual(samples.count, Int(input.frameLength) - 64, "渲染帧数应覆盖输入（±64 帧容差）")
        var sumSquares: Double = 0
        var peak: Float = 0
        for v in samples {
            sumSquares += Double(v) * Double(v)
            peak = max(peak, abs(v))
        }
        let rms = Float(sqrt(sumSquares / Double(samples.count)))
        XCTAssertFalse(rms.isNaN || peak.isNaN, "渲染输出 NaN")
        return (rms, peak)
    }

    private func dbRatio(_ a: Float, _ b: Float) -> Double {
        20 * log10(Double(a / b))
    }

    // MARK: - 增益有效性（验收标准：RMS 比值 ±1dB）

    func testBoostSixDBDoublesRMS() throws {
        let base = try renderThroughPreviewChain(gainDB: 0, amplitude: 0.25)
        let boosted = try renderThroughPreviewChain(gainDB: 6.02, amplitude: 0.25)  // +6dB ≈ 2×（峰值 0.5，未削波）
        let ratio = dbRatio(boosted.rms, base.rms)
        XCTAssertEqual(ratio, 6.0, accuracy: 1.0, "+6dB 升益 RMS 比值应在 6dB±1dB（修前恒 0dB）")
    }

    func testCutTwelveDBQuartersRMS() throws {
        let base = try renderThroughPreviewChain(gainDB: 0, amplitude: 0.25)
        let cut = try renderThroughPreviewChain(gainDB: -12.04, amplitude: 0.25)  // −12dB ≈ 0.25×
        let ratio = dbRatio(cut.rms, base.rms)
        XCTAssertEqual(ratio, -12.0, accuracy: 1.0, "−12dB 降益 RMS 比值应在 −12dB±1dB")
    }

    func testUnityGainIsTransparent() throws {
        let base = try renderThroughPreviewChain(gainDB: 0, amplitude: 0.25)
        // 纯正弦理论 RMS = A/√2；EQ 旁路频段不染色应近乎透明
        let theoryRMS = 0.25 / 2.0.squareRoot()
        let tolerance = theoryRMS * 0.1
        XCTAssertEqual(Double(base.rms), theoryRMS, accuracy: tolerance, "0dB 链路应透明（理论 RMS ±10%）")
    }

    func testBoostBeyondUnityIsExact() throws {
        // 核心回归点：旧实现升益被 playerNode.volume 钳 1.0（+12dB 恒等于基线）
        let base = try renderThroughPreviewChain(gainDB: 0, amplitude: 0.1)
        let boosted = try renderThroughPreviewChain(gainDB: 12.0, amplitude: 0.1)
        let ratio = dbRatio(boosted.rms, base.rms)
        XCTAssertEqual(ratio, 12.0, accuracy: 1.0, "+12dB（旧实现无效区）必须精确生效")
    }

    func testScaleMaxTwentyDBIsReachable() throws {
        // 标尺上限 +20dB（GainScale.maxLinear=10.0）：EQ globalGain 全量程覆盖
        let base = try renderThroughPreviewChain(gainDB: 0, amplitude: 0.12)
        let maxed = try renderThroughPreviewChain(gainDB: 20.0, amplitude: 0.12)
        let ratio = dbRatio(maxed.rms, base.rms)
        XCTAssertEqual(ratio, 20.0, accuracy: 1.0, "+20dB 标尺上限必须可达且精确")
        XCTAssertGreaterThan(maxed.peak, 1.0, "float 域不提前钳制（0.12×10=1.2，削波在输出设备/导出端，口径一致）")
    }
}
