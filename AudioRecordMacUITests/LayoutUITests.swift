import XCTest

final class LayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testDefaultWindowHasMinimumDimensions() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Main window should exist.")

        let frame = window.frame
        XCTAssertGreaterThanOrEqual(frame.width, 900, "Default window width should be at least 900.")
        XCTAssertGreaterThanOrEqual(frame.height, 550, "Default window height should be at least 550.")
    }

    func testCoreLayoutSurvivesMinimumWindowSize() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Main window should exist before resizing.")

        // 使用 AppleScript 调整窗口到最小支持尺寸
        let resizeScript = """
            tell application "System Events"
                tell process "audio_record_mac"
                    set size of front window to {960, 600}
                    set position of front window to {80, 80}
                end tell
            end tell
        """
        let script = NSAppleScript(source: resizeScript)
        script?.executeAndReturnError(nil)
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertTrue(app.groups["Sidebar"].waitForExistence(timeout: 3), "Sidebar should remain present at minimum size.")
        XCTAssertTrue(app.groups["WaveformView"].exists, "WaveformView should remain present at minimum size.")
        XCTAssertTrue(app.groups["ControlPanel"].exists, "ControlPanel should remain present at minimum size.")
        XCTAssertTrue(app.buttons["RecordButton"].exists, "RecordButton should remain present at minimum size.")
    }

    func testCoreLayoutAtLargeWindowSize() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Main window should exist before resizing.")

        // 放大窗口
        let resizeScript = """
            tell application "System Events"
                tell process "audio_record_mac"
                    set size of front window to {1400, 900}
                    set position of front window to {50, 50}
                end tell
            end tell
        """
        let script = NSAppleScript(source: resizeScript)
        script?.executeAndReturnError(nil)
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertTrue(app.groups["Sidebar"].waitForExistence(timeout: 3), "Sidebar should remain present at large size.")
        XCTAssertTrue(app.groups["WaveformView"].exists, "WaveformView should remain present at large size.")
        XCTAssertTrue(app.groups["ControlPanel"].exists, "ControlPanel should remain present at large size.")
        XCTAssertTrue(app.groups["StatusBar"].exists, "StatusBar should remain present at large size.")
    }

    func testNoGapBetweenSidebarAndContent() throws {
        // 验证侧边栏和波形区之间没有异常空白
        let sidebar = app.groups["Sidebar"]
        let waveform = app.groups["WaveformView"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(waveform.exists)

        // 侧边栏右边缘到波形左边缘的间距不应超过合理范围（分隔线 + 少量 padding）
        let gap = waveform.frame.minX - sidebar.frame.maxX
        XCTAssertLessThan(gap, 80, "Gap between sidebar and waveform should be < 80px, but was \(gap)px. Possible hidden view still taking up space.")
    }
}
