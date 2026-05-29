import XCTest

final class AppLaunchUITests: XCTestCase {
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

    func testAppLaunchesAndShowsMainWindow() throws {
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5), "Main window should appear after launch.")
    }

    func testMainLayoutHasCoreRegions() throws {
        XCTAssertTrue(app.groups["MainWindowView"].waitForExistence(timeout: 5), "MainWindowView should be discoverable for automation.")
        XCTAssertTrue(app.groups["Sidebar"].exists, "Sidebar should be present.")
        XCTAssertTrue(app.groups["ControlPanel"].exists, "ControlPanel should be present.")
        XCTAssertTrue(app.groups["WaveformView"].exists, "WaveformView should be present.")
        XCTAssertTrue(app.groups["StatusBar"].exists, "StatusBar should be present.")
    }

    func testPrimaryControlsHaveStableIdentifiers() throws {
        XCTAssertTrue(app.buttons["RecordButton"].waitForExistence(timeout: 5), "RecordButton should be available for UI automation.")
        // StopButton and PlayButton are hidden in idle state — verify they appear after interaction
    }
}
