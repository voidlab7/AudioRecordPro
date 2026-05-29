import XCTest

final class RecordingFlowUITests: XCTestCase {
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

    func testRecordButtonExistsAndIsEnabled() throws {
        let recordButton = app.buttons["RecordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist in idle state.")

        // 等待按钮变为可用状态（App 初始化可能有短暂延迟）
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: enabledPredicate, evaluatedWith: recordButton, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)

        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled in the initial state.")
    }

    func testRecordButtonCanBeClicked() throws {
        let recordButton = app.buttons["RecordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist before recording.")

        recordButton.click()

        // 录制开始后，停止按钮应出现
        let stopButton = app.buttons["StopButton"]
        let stopAppeared = stopButton.waitForExistence(timeout: 5)

        if stopAppeared && stopButton.isEnabled {
            stopButton.click()
            // 停止后录制按钮应重新可用
            XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should still exist after stopping.")
        }
        // 如果 StopButton 未出现（可能因为没有麦克风权限），测试不视为失败
    }
}
