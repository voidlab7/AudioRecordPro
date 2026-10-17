import Foundation

// MARK: - FIX-009 探针（临时自验基建，验后即拆）
// 用途：按来源统计峰值回调节奏（calls/s）与峰值幅度，验证「条间空隙」根因分析。
// 输出：容器 tmp/fix009_probe.log，每满 1 秒按来源落一行：`<t> <source> calls=<n> max=<v>`
// 打点位置（4 处）：WaveformView.updatePeakLevel(view) / AudioCallbackHandler.calculateAndReportLevel(sys-tap)
//                 / MixedAudioRecorder.updateLevel(mixed) / MicrophoneRecorder tap(mic)
enum FIX009Probe {
    private static let lock = NSLock()
    private static var windows: [String: (start: CFTimeInterval, count: Int, max: Float)] = [:]

    static func mark(_ source: String, value: Float) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        defer { lock.unlock() }
        var w = windows[source] ?? (now, 0, 0)
        w.count += 1
        w.max = Swift.max(w.max, value)
        if now - w.start >= 1.0 {
            let line = String(format: "%.3f %@ calls=%d max=%.4f\n", now, source, w.count, w.max)
            let path = NSTemporaryDirectory() + "fix009_probe.log"
            if let fh = FileHandle(forWritingAtPath: path) {
                defer { fh.closeFile() }
                fh.seekToEndOfFile()
                fh.write(Data(line.utf8))
            } else {
                FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
            }
            w = (now, 0, 0)
        }
        windows[source] = w
    }
}
