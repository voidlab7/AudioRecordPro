import XCTest
@testable import AudioRecordKit

/// UI-042 硬验证：窗口 resize 时间-像素映射锁定。
/// 痛点回归：拖动窗口边框 → 视口宽度变化 → 波形横向拉伸/压缩 + 标尺步长档位
/// 跳变（5s↔10s↔15s，老板 2026-10-31「拖动边框的时候，轨道不用动，轨道的标尺不用动」）。
/// 断言六件事：
/// 1) 缩窄/拉宽后 pixelsPerSecond 与 resize 前恒定（波形不拉伸的核心不变量）
/// 2) 标尺档位稳定——同一 pps 下 niceStep 档位不变（TimeRulerView rawStep = 80 / pps）
/// 3) 锚左缘——合法区间内 visibleStartTime 精确保持
/// 4) 右端 clamp——起点越出尾部时被拉回 totalDuration - duration
/// 5) 全显 + 右端留白态——拉宽超过全音频时 duration > totalDuration 且起点归零
/// 6) 边界输入——宽度未变/无效、时长无效返回 nil；极端窄窗触底 0.05s
final class ViewportResizeLockTests: XCTestCase {

    /// 与 App 层 TimeRulerView.niceSteps / EditorWaveformView drawTimeRuler 同源的档位表
    /// （若 App 层改表须同步此处——档位断言是 UI-042 验收标准明文项）
    private static let niceSteps: [TimeInterval] = [
        0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600
    ]

    private func niceStep(forPPS pps: Double) -> TimeInterval {
        let raw = 80.0 / max(pps, 0.001)
        for s in Self.niceSteps where s >= raw { return s }
        return Self.niceSteps.last ?? 600
    }

    // MARK: - pps 恒定（核心不变量）

    func testPPSConstantOnShrink() {
        // 10s 音频、视口 800px 全显（pps=80）→ 缩窄到 520px
        let r = ViewportResizeLock.resolve(
            oldWidth: 800, newWidth: 520,
            visibleStartTime: 0, visibleDuration: 10, totalDuration: 10)
        XCTAssertNotNil(r)
        let ppsBefore = ViewportResizeLock.pixelsPerSecond(viewWidth: 800, visibleDuration: 10)
        let ppsAfter = ViewportResizeLock.pixelsPerSecond(viewWidth: 520, visibleDuration: r!.duration)
        XCTAssertEqual(ppsAfter, ppsBefore, accuracy: 1e-9)
    }

    func testPPSConstantOnWiden() {
        // 放大态（visibleDuration=4s、宽 800、pps=200）→ 拉宽到 1100px：多露内容，映射不变
        let r = ViewportResizeLock.resolve(
            oldWidth: 800, newWidth: 1100,
            visibleStartTime: 3, visibleDuration: 4, totalDuration: 10)
        XCTAssertNotNil(r)
        let ppsBefore = ViewportResizeLock.pixelsPerSecond(viewWidth: 800, visibleDuration: 4)
        let ppsAfter = ViewportResizeLock.pixelsPerSecond(viewWidth: 1100, visibleDuration: r!.duration)
        XCTAssertEqual(ppsAfter, ppsBefore, accuracy: 1e-9)
        XCTAssertEqual(r!.duration, 5.5, accuracy: 1e-9)  // 1100/200
    }

    func testRulerStepStableAcrossResize() {
        // 档位稳定：缩窄/拉宽前后 rawStep 落在同一 niceStep 档（验收标准「无 5s↔10s 跳变」）
        let r1 = ViewportResizeLock.resolve(
            oldWidth: 800, newWidth: 520,
            visibleStartTime: 0, visibleDuration: 10, totalDuration: 10)
        let r2 = ViewportResizeLock.resolve(
            oldWidth: 520, newWidth: 1150,
            visibleStartTime: r1!.start, visibleDuration: r1!.duration, totalDuration: 10)
        let step0 = niceStep(forPPS: ViewportResizeLock.pixelsPerSecond(viewWidth: 800, visibleDuration: 10))
        let step1 = niceStep(forPPS: ViewportResizeLock.pixelsPerSecond(viewWidth: 520, visibleDuration: r1!.duration))
        let step2 = niceStep(forPPS: ViewportResizeLock.pixelsPerSecond(viewWidth: 1150, visibleDuration: r2!.duration))
        XCTAssertEqual(step0, step1)
        XCTAssertEqual(step0, step2)
    }

    // MARK: - 锚点与 clamp

    func testAnchorLeftEdgeHolds() {
        // 起点在合法区间（start + newDuration ≤ total）→ 精确保持（锚左缘）
        let r = ViewportResizeLock.resolve(
            oldWidth: 800, newWidth: 600,
            visibleStartTime: 3, visibleDuration: 4, totalDuration: 10)
        XCTAssertEqual(r!.start, 3, accuracy: 1e-12)  // 3 + 3 < 10 未触 clamp
    }

    func testRightClampWhenTailOverflows() {
        // 起点越出右端（3 + 8 > 10）→ clamp 到 totalDuration - newDuration
        let r = ViewportResizeLock.resolve(
            oldWidth: 400, newWidth: 800,
            visibleStartTime: 3, visibleDuration: 4, totalDuration: 10)
        XCTAssertEqual(r!.duration, 8, accuracy: 1e-9)
        XCTAssertEqual(r!.start, 2, accuracy: 1e-9)  // 10 - 8
    }

    func testOversizeShowsBlankTail() {
        // 拉宽超过全音频：新时长 15s > 10s → 允许超界（全显 + 右端留白），起点归零，
        // 不强行重铺（重铺 = 波形重新拉伸，正是 UI-042 要消灭的行为）
        let r = ViewportResizeLock.resolve(
            oldWidth: 800, newWidth: 1200,
            visibleStartTime: 0, visibleDuration: 10, totalDuration: 10)
        XCTAssertEqual(r!.duration, 15, accuracy: 1e-9)
        XCTAssertEqual(r!.start, 0)
        XCTAssertGreaterThan(r!.duration, 10)
    }

    // MARK: - 边界输入

    func testNilWhenWidthUnchangedOrInvalid() {
        XCTAssertNil(ViewportResizeLock.resolve(
            oldWidth: 800, newWidth: 800,
            visibleStartTime: 0, visibleDuration: 10, totalDuration: 10))  // 宽度未变
        XCTAssertNil(ViewportResizeLock.resolve(
            oldWidth: 0, newWidth: 600,
            visibleStartTime: 0, visibleDuration: 10, totalDuration: 10))  // 旧宽无效
        XCTAssertNil(ViewportResizeLock.resolve(
            oldWidth: 800, newWidth: 0,
            visibleStartTime: 0, visibleDuration: 10, totalDuration: 10))  // 新宽无效
        XCTAssertNil(ViewportResizeLock.resolve(
            oldWidth: 800, newWidth: 600,
            visibleStartTime: 0, visibleDuration: 0, totalDuration: 10))   // 可见时长无效
        XCTAssertNil(ViewportResizeLock.resolve(
            oldWidth: 800, newWidth: 600,
            visibleStartTime: 0, visibleDuration: 10, totalDuration: 0))   // 总时长无效
    }

    func testMinDurationFloorOnExtremeNarrow() {
        // 极端窄窗：新时长触底 0.05s（防无交互意义的微视口）
        let r = ViewportResizeLock.resolve(
            oldWidth: 10_000, newWidth: 0.5,
            visibleStartTime: 0, visibleDuration: 1, totalDuration: 100)
        XCTAssertEqual(r!.duration, ViewportResizeLock.minVisibleDuration, accuracy: 1e-12)
    }

    func testPixelsPerSecondGuards() {
        XCTAssertEqual(ViewportResizeLock.pixelsPerSecond(viewWidth: 0, visibleDuration: 10), 0)
        XCTAssertEqual(ViewportResizeLock.pixelsPerSecond(viewWidth: 100, visibleDuration: 0), 0)
        XCTAssertEqual(ViewportResizeLock.pixelsPerSecond(viewWidth: 100, visibleDuration: 4), 25)
    }
}
