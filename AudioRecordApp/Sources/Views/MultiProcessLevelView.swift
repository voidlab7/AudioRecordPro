import Cocoa
final class MultiProcessLevelView: NSView {
    func setProcesses(_ processes: [(pid: pid_t, name: String)]) {}
    func updateLevel(for pid: pid_t, level: Float) {}
    func updatePeakLevel(for pid: pid_t, peakLevel: Float) {}
    func reset() {}
    func clear() {}
}
