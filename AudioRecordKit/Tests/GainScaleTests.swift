import XCTest
@testable import AudioRecordKit

/// FIX-020: 增益标尺单一来源 GainScale 的换算与钳制一致性
final class GainScaleTests: XCTestCase {

    // MARK: - dB ↔ 线性

    func testLinearFromDBBasics() {
        XCTAssertEqual(GainScale.linear(fromDB: 0), 1.0, accuracy: 1e-6)
        XCTAssertEqual(GainScale.linear(fromDB: 20), 10.0, accuracy: 1e-4)
        XCTAssertEqual(GainScale.linear(fromDB: -20), 0.1, accuracy: 1e-6)
        XCTAssertEqual(GainScale.linear(fromDB: -24), 0.0631, accuracy: 1e-3)
        XCTAssertEqual(GainScale.linear(fromDB: 6), 1.9953, accuracy: 1e-3)
    }

    func testDBFromLinearBasics() {
        XCTAssertEqual(GainScale.db(fromLinear: 1.0), 0.0, accuracy: 1e-6)
        XCTAssertEqual(GainScale.db(fromLinear: 10.0), 20.0, accuracy: 1e-4)
        XCTAssertEqual(GainScale.db(fromLinear: 0.1), -20.0, accuracy: 1e-4)
        XCTAssertEqual(GainScale.db(fromLinear: 2.0), 6.0206, accuracy: 1e-3)
    }

    func testDBLinearRoundTrip() {
        for db in stride(from: GainScale.minDB, through: GainScale.maxDB, by: 0.5) {
            let linear = GainScale.linear(fromDB: db)
            let back = GainScale.db(fromLinear: linear)
            XCTAssertEqual(back, db, accuracy: 1e-3, "往返失真 @ \(db)dB")
        }
    }

    // MARK: - 钳制（上限与标尺一致，消除 2.0 vs 10.0 双口径）

    func testClampLinearUpperBoundMatchesScaleMax() {
        XCTAssertEqual(GainScale.clampLinear(GainScale.maxLinear), GainScale.maxLinear)
        XCTAssertEqual(GainScale.clampLinear(50.0), 10.0, accuracy: 1e-4, "超 +20dB 钳到 10.0")
        XCTAssertEqual(GainScale.clampLinear(2.5), 2.5, accuracy: 1e-6, "+8dB 内不截断（旧上限 2.0 会截断）")
        XCTAssertEqual(GainScale.clampLinear(2.0), 2.0, accuracy: 1e-6)
    }

    func testClampLinearLowerBound() {
        XCTAssertEqual(GainScale.clampLinear(0), 0)
        XCTAssertEqual(GainScale.clampLinear(-3.0), 0, "负值钳到 0（静音合法值）")
    }

    func testMaxLinearIsTwentyDB() {
        XCTAssertEqual(GainScale.maxLinear, GainScale.linear(fromDB: GainScale.maxDB), accuracy: 1e-6)
        XCTAssertEqual(Double(GainScale.maxLinear), 10.0, accuracy: 1e-4)
    }

    // MARK: - 回放映射（EQ globalGain）

    func testPlaybackDBMapping() {
        XCTAssertEqual(GainScale.playbackDB(for: 1.0), 0.0, accuracy: 1e-6)
        XCTAssertEqual(GainScale.playbackDB(for: GainScale.maxLinear), 20.0, accuracy: 1e-4)
        XCTAssertEqual(GainScale.playbackDB(for: 4.0), 12.0412, accuracy: 1e-3)
        XCTAssertEqual(GainScale.playbackDB(for: 0.25), -12.0412, accuracy: 1e-3)
    }

    func testPlaybackDBZeroIsMute() {
        XCTAssertEqual(GainScale.playbackDB(for: 0), GainScale.muteDB)
        XCTAssertEqual(GainScale.muteDB, -96.0)
        XCTAssertLessThan(GainScale.playbackDB(for: -0.5), GainScale.muteDB + 0.001, "非法负值也按静音处理")
    }

    func testPlaybackDBNeverExceedsScale() {
        XCTAssertEqual(GainScale.playbackDB(for: 100.0), GainScale.maxDB, accuracy: 1e-6, "超量程钳 +20dB")
    }
}
