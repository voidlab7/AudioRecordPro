import XCTest
@testable import AudioRecordKit

/// FIX-010: 两态波形幅度映射唯一函数测试
/// 覆盖验收标准「抽出的共用映射函数有单测（峰值 / 参考最大值 / 静音边界）」
/// FIX-018 修订：录音态/编辑态参考值统一固定满刻度 1.0（老板 2026-10-29 拍板方案 A），
/// 原 running max 语义断言退役，改为「尖峰前后同峰值映射恒等」。
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

    // MARK: - 与录音态/编辑态口径一致性（FIX-018 方案 A 核心断言：固定满刻度）

    func testRecordingFinalWindowMatchesEditorRule() {
        // FIX-018: 录音态/编辑态参考值统一固定满刻度 1.0——同一段峰值两侧逐位一致，且等于线性期望。
        let peaks: [Float] = [0.01, 0.08, 0.05, 0.12, 0.03]
        let recordingMapped = peaks.map { WaveformAmplitudeMapper.normalized($0, referenceMax: 1.0) }
        let editorMapped = peaks.map { WaveformAmplitudeMapper.normalized($0, referenceMax: 1.0) }
        XCTAssertEqual(recordingMapped, editorMapped)
        for (i, p) in peaks.enumerated() {
            XCTAssertEqual(recordingMapped[i], p, accuracy: 1e-6)
        }
    }

    func testSamePeakMapsIdenticallyBeforeAndAfterSpike() {
        // FIX-018 验收「同一次录音内相同峰值的两根条，无论在尖峰前或后，渲染高度一致」：
        // 映射只依赖峰值本身（参考值恒 1.0），尖峰不改变任何其他条的映射值。
        let quiet: Float = 0.08
        let sequence: [Float] = [quiet, 0.03, 0.95, quiet, 0.02]  // 尖峰 0.95 前后各一根同电平条
        let mapped = sequence.map { WaveformAmplitudeMapper.normalized($0, referenceMax: 1.0) }
        XCTAssertEqual(mapped[0], mapped[3], accuracy: 1e-6)
        XCTAssertEqual(mapped[0], quiet, accuracy: 1e-6)
    }

    func testSpikeClampedToFullHeight() {
        // FIX-018 边缘情况：削波/过载（≥1.0）clamp 满高，且不影响同参考下其他条的线性映射
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(1.4, referenceMax: 1.0), 1.0, accuracy: 1e-6)
        XCTAssertEqual(WaveformAmplitudeMapper.normalized(0.5, referenceMax: 1.0), 0.5, accuracy: 1e-6)
    }
}
