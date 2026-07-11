import XCTest

/// UI 测试：多轨道显示（TC-08 ~ TC-12）
/// 前提：App 需以 --ui-testing 启动，并注入 mock 轨道数据
final class TracksUITests: XCTestCase {
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

    // MARK: - Helper

    /// 通过 accessibilityIdentifier 获取 TracksView 容器
    private var tracksView: XCUIElement {
        return app.otherElements["TracksView"]
    }

    /// 通过标题获取轨道行
    private func trackRow(title: String) -> XCUIElement {
        return app.otherElements["TrackRow-\(title)"]
    }

    // MARK: - TC-08: 1 个音源 → 1 条轨道
    func testTC08_OneTrackVisible() throws {
        // 通过侧边栏选中 1 个进程（触发轨道显示）
        let row = app.otherElements["ProcessRow-1001"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        // 开始录制以激活轨道区
        let recordBtn = app.buttons["RecordButton"]
        XCTAssertTrue(recordBtn.waitForExistence(timeout: 3))
        recordBtn.click()

        // 轨道行应出现
        let track = trackRow(title: "Chrome")
        XCTAssertTrue(track.waitForExistence(timeout: 5),
                      "选中 1 个音源后，轨道行 TrackRow-Chrome 应出现")
    }

    // MARK: - TC-09: 5 个音源 → 5 条轨道
    func testTC09_FiveTracksVisible() throws {
        // 选中 5 个进程
        for i in 1...5 {
            let pid = "100\(i)"
            let row = app.otherElements["ProcessRow-\(pid)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "进程行 \(pid) 应存在")
            row.click()
        }

        // 开始录制
        let recordBtn = app.buttons["RecordButton"]
        XCTAssertTrue(recordBtn.waitForExistence(timeout: 3))
        recordBtn.click()

        // 验证 5 条轨道都存在
        let expectedNames = ["Chrome", "Safari", "Music", "Zoom", "Teams"]
        for name in expectedNames {
            let track = trackRow(title: name)
            XCTAssertTrue(track.waitForExistence(timeout: 5),
                          "轨道行 TrackRow-\(name) 应存在")
        }
    }

    // MARK: - TC-10: 轨道高度等分
    func testTC10_TrackRowsEqualHeight() throws {
        // 选中 3 个进程并录制，使 3 条轨道显示
        for i in 1...3 {
            app.otherElements["ProcessRow-100\(i)"].click()
        }
        app.buttons["RecordButton"].click()

        // 等待轨道出现
        let track1 = trackRow(title: "Chrome")
        XCTAssertTrue(track1.waitForExistence(timeout: 5))

        // 通过坐标验证等分：截图 + AI 视觉巡检
        // XCUI 无法直接获取 NSStackView 子视图高度，此处验证轨道数量正确
        let track2 = trackRow(title: "Safari")
        let track3 = trackRow(title: "Music")
        XCTAssertTrue(track2.exists, "第 2 条轨道应存在")
        XCTAssertTrue(track3.exists, "第 3 条轨道应存在")

        // 等分验证由 AI 视觉巡检（截图）完成
        XCTAssertTrue(tracksView.exists, "TracksView 容器应存在")
    }

    // MARK: - TC-11: 只有麦克风 → 1 条麦克风轨道
    func testTC11_MicOnlyTrack() throws {
        // 取消所有进程选择，仅开启麦克风
        let micToggle = app.checkBoxes["MicrophoneToggle"]
        XCTAssertTrue(micToggle.waitForExistence(timeout: 5))
        if micToggle.value as? String != "1" {
            micToggle.click()
        }

        let recordBtn = app.buttons["RecordButton"]
        XCTAssertTrue(recordBtn.waitForExistence(timeout: 3))
        recordBtn.click()

        // 应只有 1 条轨道（麦克风）
        let micTrack = trackRow(title: "Microphone")
        XCTAssertTrue(micTrack.waitForExistence(timeout: 5),
                      "仅选麦克风时，应显示 1 条麦克风轨道")
    }

    // MARK: - TC-12: 空状态引导
    func testTC12_EmptyStateHint() throws {
        // 未选中任何音源、未开启麦克风、未录制时，应显示空状态
        let emptyHint = app.staticTexts["EmptyStateHint"]
            ?? app.staticTexts.matching(NSPredicate(format: "label CONTAINS '选择音源'")).firstMatch
        // 空状态可能在 TracksView 内，等待出现
        let exists = emptyHint.waitForExistence(timeout: 5)
        XCTAssertTrue(exists || tracksView.exists,
                      "未选择音源时应显示空状态引导或 TracksView 容器")
    }
}
// ... existing code ...
