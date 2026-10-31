import XCTest
@testable import AudioRecordKit
import AVFoundation

/// UI-041 硬验证：视口逐列真峰值（放大态精细层）。
/// 痛点回归：legacy 固定桶在放大态复制铺满 + 平滑 → 底噪区死平带（老板实机对比剪映有波纹）。
/// 断言五件事：
/// 1) fitAll 概览态不走精细层（桶密度足够，粗路径零开销不变）
/// 2) 放大态（桶复制）判定命中
/// 3) 脉冲定位精确——真峰值落所在列，不扩散到邻近列（粗路径会把整桶峰值复制到多列）
/// 4) 底噪波纹存在性——列间小幅起伏在精细层得以呈现（交替幅值 → 列间差异显著），
///    同一数据在粗路径（桶 max 复制）下无法区分——这正是死平带根因的数值化
/// 5) stride 护栏与门限口径：超大列帧数跳采不超时；−60dBFS 以下真静音归 0（FIX-010 保留）
final class WaveformViewportPeaksTests: XCTestCase {

    private let sampleRate: Double = 48_000

    // MARK: - needsFinePath 判定

    func testFitAllStaysCoarse() {
        // 10s 录音、Phase2 2000 桶、全视图 850 列：视口内桶密度 2000 >> 850
        XCTAssertFalse(WaveformViewportPeaks.needsFinePath(
            allSamplesCount: 2000, totalDuration: 10, visibleDuration: 10, pixelCount: 850))
    }

    func testZoomedNeedsFine() {
        // 放大 64 倍：视口内桶 = 2000/64 ≈ 31 < 850 → 桶复制态
        XCTAssertTrue(WaveformViewportPeaks.needsFinePath(
            allSamplesCount: 2000, totalDuration: 10, visibleDuration: 10.0 / 64.0, pixelCount: 850))
    }

    func testDegenerateInputsStayCoarse() {
        XCTAssertFalse(WaveformViewportPeaks.needsFinePath(
            allSamplesCount: 0, totalDuration: 10, visibleDuration: 1, pixelCount: 850))
        XCTAssertFalse(WaveformViewportPeaks.needsFinePath(
            allSamplesCount: 2000, totalDuration: 0, visibleDuration: 1, pixelCount: 850))
        XCTAssertFalse(WaveformViewportPeaks.needsFinePath(
            allSamplesCount: 2000, totalDuration: 10, visibleDuration: 0, pixelCount: 850))
        XCTAssertFalse(WaveformViewportPeaks.needsFinePath(
            allSamplesCount: 2000, totalDuration: 10, visibleDuration: 1, pixelCount: 1))
    }

    // MARK: - columnPeaks

    private func makeBuffer(frames: Int, channels: Int = 1, fill: (Int) -> Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for ch in 0..<channels {
            for i in 0..<frames {
                buffer.floatChannelData![ch][i] = fill(i)
            }
        }
        return buffer
    }

    private func peaks(of buffer: AVAudioPCMBuffer,
                       start: TimeInterval, duration: TimeInterval, pixels: Int) -> [Float] {
        WaveformViewportPeaks.columnPeaks(
            channelData: buffer.floatChannelData!,
            channels: Int(buffer.format.channelCount),
            totalFrames: Int(buffer.frameLength),
            sampleRate: sampleRate,
            visibleStart: start,
            visibleDuration: duration,
            pixelCount: pixels)
    }

    func testPulseLocalizesToItsColumn() {
        // 1s 静音 + 单脉冲 0.5s 处（帧 24000，幅值 0.5）；视口 [0.4, 0.6]s 放大态 20 列
        let pulseFrame = 24_000
        let buffer = makeBuffer(frames: Int(sampleRate)) { $0 == pulseFrame ? 0.5 : 0.0 }
        let peaks = peaks(of: buffer, start: 0.4, duration: 0.2, pixels: 20)

        XCTAssertEqual(peaks.count, 20)
        // 脉冲帧 24000 → 视口内相对位置 (24000-19200)/9600 = 0.5 → 第 10 列
        let active = peaks.enumerated().filter { $0.element > 0 }.map { $0.offset }
        XCTAssertEqual(active, [10])
        XCTAssertEqual(peaks[10], 0.5, accuracy: 0.001)
        // 粗路径对照：同视口下整桶复制会把脉冲摊到邻近列（≥5 列非零）——死平带根源
        XCTAssertLessThanOrEqual(active.count, 2)
    }

    func testNoiseRippleVisibleInFineLayer() {
        // 底噪波纹存在性：段状慢变幅值（每 0.2s 一段：0.02→0.10 循环），放大态 25 列横跨多段
        // → 列峰值呈阶梯起伏；同一数据在粗路径（固定桶 max 复制+平滑）下被抹成平带。
        let frames = Int(sampleRate)
        let buffer = makeBuffer(frames: frames) { i in
            let segment = i / 9_600  // 每段 0.2s
            return 0.02 + Float(segment % 5) * 0.02  // 0.02/0.04/0.06/0.08/0.10 循环
        }
        let peaks = peaks(of: buffer, start: 0, duration: 1.0, pixels: 25)

        XCTAssertEqual(peaks.count, 25)
        let range = (peaks.max() ?? 0) - (peaks.min() ?? 0)
        XCTAssertGreaterThanOrEqual(range, 0.03)
        XCTAssertGreaterThan(peaks.max() ?? 0, WaveformAmplitudeMapper.silenceFloorLinear)
    }

    func testStrideGuardKeepsLargeViewportFast() {
        // 200 万帧（~41.7s@48k）单列护栏 128：性能粗断言（全扫 >100ms，跳采应远低于 1s）
        let frames = 2_000_000
        let buffer = makeBuffer(frames: frames) { Float($0 % 1000) / 10_000.0 }
        let t0 = Date()
        let peaks = peaks(of: buffer, start: 0, duration: Double(frames) / sampleRate, pixels: 64)
        let elapsed = Date().timeIntervalSince(t0)
        XCTAssertEqual(peaks.count, 64)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testTrueSilenceGatesToZero() {
        // −60dBFS 门限口径保留：0.0005（< 0.001）整段 → 全 0（渲染层画发丝基线）
        let buffer = makeBuffer(frames: 4800) { _ in 0.0005 }
        let peaks = peaks(of: buffer, start: 0, duration: 0.1, pixels: 20)
        XCTAssertTrue(peaks.allSatisfy { $0 == 0 })
    }

    func testViewportClampsAndOverrunReturnsZeroColumns() {
        let buffer = makeBuffer(frames: 4_800) { _ in 0.5 }
        // 起点越界为负：clamp 到 0，首列有值
        let neg = peaks(of: buffer, start: -1.0, duration: 0.05, pixels: 10)
        XCTAssertEqual(neg.count, 10)
        XCTAssertGreaterThan(neg[0], 0)
        // 视口完全超出末尾：列全 0 不崩
        let over = peaks(of: buffer, start: 5.0, duration: 0.1, pixels: 10)
        XCTAssertEqual(over.count, 10)
        XCTAssertTrue(over.allSatisfy { $0 == 0 })
        // 非法输入：返回等长零数组
        let bad = WaveformViewportPeaks.columnPeaks(
            channelData: buffer.floatChannelData!, channels: 1, totalFrames: 0,
            sampleRate: sampleRate, visibleStart: 0, visibleDuration: 0.1, pixelCount: 8)
        XCTAssertEqual(bad, [Float](repeating: 0, count: 8))
    }
}
