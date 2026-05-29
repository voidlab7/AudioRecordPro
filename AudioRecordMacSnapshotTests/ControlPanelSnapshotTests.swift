import Cocoa
import SnapshotTesting
import XCTest

final class ControlPanelSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        isRecording = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] == "1"
    }

    func testControlPanelIdle() {
        let view = makeControlPanelView()
        view.updateRecordingState(.idle)
        view.updateTimer("00:00.00")
        view.layoutSubtreeIfNeeded()

        assertSnapshot(of: view, as: .image)
    }

    func testControlPanelRecording() {
        let view = makeControlPanelView()
        view.updateRecordingState(.recording)
        view.updateTimer("00:12.34")
        view.layoutSubtreeIfNeeded()

        assertSnapshot(of: view, as: .image)
    }

    private func makeControlPanelView() -> ControlPanelView {
        let view = ControlPanelView(frame: NSRect(x: 0, y: 0, width: 900, height: 96))
        view.wantsLayer = true
        view.layoutSubtreeIfNeeded()
        return view
    }
}
