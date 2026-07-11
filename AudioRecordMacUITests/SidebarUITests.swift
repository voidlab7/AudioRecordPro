import XCTest

/// UI 测试：侧边栏多选逻辑（TC-01 ~ TC-05）
/// 前提：App 需以 --ui-testing 启动，并注入 mock 进程列表（至少 6 个进程）
final class SidebarUITests: XCTestCase {
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

    /// 通过 accessibilityIdentifier 获取进程行
    private func processRow(pid: String) -> XCUIElement {
        return app.otherElements["ProcessRow-\(pid)"]
    }

    /// 通过 accessibilityIdentifier 获取 Checkbox
    private func checkbox(pid: String) -> XCUIElement {
        return app.checkBoxes["ProcessCheckbox-\(pid)"]
    }

    // MARK: - TC-01: 单击选中
    func testTC01_SingleSelect() throws {
        let firstRow = app.otherElements["ProcessRow-1001"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5),
                     "进程行 ProcessRow-1001 应存在（mock 数据）")

        firstRow.click()

        // Checkbox 应变为选中态
        let cb = checkbox(pid: "1001")
        XCTAssertTrue(cb.value as? String == "1" || cb.isSelected,
                      "点击后 Checkbox-1001 应被选中")
    }

    // MARK: - TC-02: 多选 2 个
    func testTC02_MultiSelectTwo() throws {
        let row1 = app.otherElements["ProcessRow-1001"]
        let row2 = app.otherElements["ProcessRow-1002"]
        XCTAssertTrue(row1.waitForExistence(timeout: 5))
        XCTAssertTrue(row2.exists)

        row1.click()
        row2.click()

        let cb1 = checkbox(pid: "1001")
        let cb2 = checkbox(pid: "1002")
        XCTAssertEqual(cb1.value as? String, "1", "Checkbox-1001 应被选中")
        XCTAssertEqual(cb2.value as? String, "1", "Checkbox-1002 应被选中")
    }

    // MARK: - TC-03: 多选 5 个（上限）
    func testTC03_SelectFive() throws {
        for i in 1...5 {
            let pid = "100\(i)"
            let row = app.otherElements["ProcessRow-\(pid)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "进程行 \(pid) 应存在")
            row.click()
            let cb = checkbox(pid: pid)
            XCTAssertEqual(cb.value as? String, "1", "Checkbox-\(pid) 点击后应选中")
        }

        // 验证恰好 5 个被选中
        let selectedCount = (1...5).filter { i in
            let cb = checkbox(pid: "100\(i)")
            return cb.value as? String == "1"
        }.count
        XCTAssertEqual(selectedCount, 5, "应恰好选中 5 个进程")
    }

    // MARK: - TC-04: 第 6 个拒绝 + Toast
    func testTC04_SixthSelectionRejected() throws {
        // 先选 5 个
        for i in 1...5 {
            let pid = "100\(i)"
            app.otherElements["ProcessRow-\(pid)"].click()
        }

        // 尝试选第 6 个
        let row6 = app.otherElements["ProcessRow-1006"]
        XCTAssertTrue(row6.waitForExistence(timeout: 5))
        row6.click()

        // 第 6 个 Checkbox 应保持未选中
        let cb6 = checkbox(pid: "1006")
        XCTAssertNotEqual(cb6.value as? String, "1", "第 6 个 Checkbox 应保持未选中")

        // Toast 验证：截图由 AI 视觉巡检完成，此处仅验证 UI 未崩溃
        XCTAssertTrue(app.windows.firstMatch.exists, "点击第 6 个后 App 应未崩溃")
    }

    // MARK: - TC-05: 再次点击取消选中
    func testTC05_DeselectByClick() throws {
        let row1 = app.otherElements["ProcessRow-1001"]
        XCTAssertTrue(row1.waitForExistence(timeout: 5))

        // 选中
        row1.click()
        let cb1 = checkbox(pid: "1001")
        XCTAssertEqual(cb1.value as? String, "1", "第一次点击后应选中")

        // 再次点击 → 取消选中
        row1.click()
        XCTAssertNotEqual(cb1.value as? String, "1", "第二次点击后应取消选中")
    }
}
// ... existing code ...
