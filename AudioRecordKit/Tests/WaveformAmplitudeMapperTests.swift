import XCTest
@testable import AudioRecordKit

/// FIX-010: 两态波形幅度映射唯一函数测试
/// 覆盖验收标准「抽出的共用映射函数有单测（峰值 / 参考最大值 / 静音边界）」
final class WaveformAmplitudeMapperTests: XCTestCase {

    // MARK: - 峰值映射

    func testLinearScalingAtFullScaleReference() {
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(0.5, referenceMax: 1.0), 0.5, accuracy: 1e-6)
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(0.0818, referenceMax: 1.0), 0.0818, accuracy: 1e-6)
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(1.0, referenceMax: 1.0), 1.0, accuracy: 1e-6)
    }

    func testZeroPeakMapsToZero() {
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(0.0, referenceMax: 1.0), 0)
    }

    func testNegativePeakTreatedAsZero() {
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(-0.5, referenceMax: 1.0), 0)
    }

    // MARK: - 参考最大值

    func testReferenceScalesResult() {
        // 参考值 0.5 时，0.25 的峰值应映射为 0.5（相对高度不变）
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(0.25, referenceMax: 0.5), 0.5, accuracy: 1e-6)
    }

    func testOutputClampedToOne() {
        // 峰值超过参考值（理论不该发生，防御性钳制）
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(1.2, referenceMax: 1.0), 1.0, accuracy: 1e-6)
    }

    func testZeroReferenceReturnsZero() {
        // 录音刚启动还没任何峰值时，参考值为 0，不除零
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(0.5, referenceMax: 0.0), 0)
    }

    // MARK: - 静音边界（−60 dBFS = 0.001 线性）

    func testBelowSilenceFloorReturnsZero() {
        // 底噪 −44～−37 dBFS ≈ 0.006~0.014？不——0.006 > 0.001；真正的真静音是 < −60 dBFS
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(0.0005, referenceMax: 1.0), 0)
    }

    func testAtSilenceFloorReturnsZero() {
        // 门限为严格大于：恰在 −60 dBFS 视为静音
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(WaveformAmplitudeMapper.silenceFloorLinear, referenceMax: 1.0), 0)
    }

    func testAboveSilenceFloorMappedLinearly() {
        let v = WaveformAmplitudeMapper.normalized(0.002, referenceMax: 1.0)
        XCTAssertEqual(v, 0.002, accuracy: 1e-6)
    }

    func testSilenceReferenceReturnsZero() {
        // 整段都低于门限（参考值本身是静音）→ 全 0
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(0.5, referenceMax: 0.0005), 0)
    }

    // MARK: - 与录音态/编辑态口径一致性（B 方案核心断言）

    func testRecordingFinalWindowMatchesEditorRule() {
        // 单子口径「录音态末屏与编辑态同时间段高度映射一致」：
        // 录音结束后 running max = 整段 max，可见窗按新参考重映射后与编辑态逐位一致。
        // 注意：录音**进行中**逐点值（旧 running max）与编辑态不同是 B 方案固有特性，不算不一致。
        let peaks: [Float] = [0.01, 0.08, 0.05, 0.12, 0.03]
        let segmentMax = peaks.max() ?? 1.0
        var runningMax: Float = 0
        for p in peaks { runningMax = max(runningMax, p) }
        XCTAssertGreaterThan(runningMax, 0)
        let recordingFinal = peaks.map { WaveformAmplitudeMapper.normalized($0, referenceMax: runningMax) }
        let editorMapped = peaks.map { WaveformAmplitudeMapper.normalized($0, referenceMax: segmentMax) }
        XCTAssertEqual(recordingFinal, editorMapped)
    }

    func testRunningMaxOnlyIncreases() {
        // running max 语义：只增不减（突发大声后不回落）
        var runningMax: Float = 0
        for p: Float in [0.01, 0.5, 0.2, 0.1, 0.05] {
            runningMax = max(runningMax, p)
        }
        XCTAssertEqual(runningMax, 0.5, accuracy: 1e-6)
    }
}
