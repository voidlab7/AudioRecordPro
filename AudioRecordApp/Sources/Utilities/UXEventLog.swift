import AppKit
import Foundation

/// UXEventLog — 结构化 UX 事件流（Event Sourcing 式可观测性）
///
/// 一份 JSONL 事件流，三种用途：
/// 1. 自动化测试断言：输入(input) → 动作(action) → 状态(state) → 产物(artifact) 闭环验证
/// 2. 用户报障回放：还原完整操作时间线（"用户做了什么"）
/// 3. 行为分析：高频操作路径、功能触达统计
///
/// 事件模型（每行一个 JSON 对象）：
/// ```
/// {"ts":"2026-09-19 10:30:00.123","epoch_ms":1758241800123,"seq":42,"session":"ab12cd34",
///  "type":"input","event":"click","detail":{"target":"RecordButton","hit":"NSButton",...}}
/// ```
///
/// type 枚举：
/// - lifecycle: app_launch / app_terminate
/// - input:     物理输入事件（click / key / scroll），自动采集，零埋点成本
/// - action:    业务动作（用户意图层），在动作分发处埋点
/// - state:     UI 状态变化（Tab 切换、编辑器进出、弹窗出现），附带视图树快照
/// - module:    功能模块运转（start/ok/fail + 耗时），功能是否正常的关键证据
/// - artifact:  落盘产物（录音文件创建、导出完成），最终硬验证依据
final class UXEventLog {
    static let shared = UXEventLog()

    // MARK: - 事件类型

    enum EventType: String {
        case lifecycle
        case input
        case action
        case state
        case module
        case artifact
    }

    // MARK: - 私有状态

    private let queue = DispatchQueue(label: "com.audiorecordmac.uxeventlog", qos: .utility)
    private let fileManager = FileManager.default
    private var fileHandle: FileHandle?
    private var seq: Int64 = 0
    private let sessionID = String(UUID().uuidString.prefix(8))
    private var monitorInstalled = false

    // 滚动节流（避免高频 scroll 淹没日志）
    private var lastScrollLogDate: Date = .distantPast

    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let fileTsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    // MARK: - 目录

    private var logDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("AudioRecordings/Logs/UXEvents")
    }

    private var logFileURL: URL {
        let ts = Self.fileTsFormatter.string(from: Date())
        return logDirectory.appendingPathComponent("uxevents_\(ts)_\(sessionID).jsonl")
    }

    private init() {
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    // MARK: - 会话

    /// 会话开始：在 applicationDidFinishLaunching 里调用（clearLogFiles 之后）
    func startSession() {
        var detail: [String: Any] = [
            "session": sessionID,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            detail["app_version"] = version
        }
        log(.lifecycle, "app_launch", detail: detail)
        Logger.shared.info("UXEventLog 会话开始: \(logFileURL.path)")
    }

    /// 会话结束：在 applicationWillTerminate 里调用，同步 flush
    func shutdown() {
        log(.lifecycle, "app_terminate", detail: ["total_events": Int(seq)])
        queue.sync {
            fileHandle?.closeFile()
            fileHandle = nil
        }
    }

    // MARK: - 核心 API

    /// 记录一条事件（通用入口）
    func log(_ type: EventType, _ event: String, detail: [String: Any] = [:]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.seq += 1
            let now = Date()
            let record: [String: Any] = [
                "ts": Self.tsFormatter.string(from: now),
                "epoch_ms": Int64(now.timeIntervalSince1970 * 1000),
                "seq": self.seq,
                "session": self.sessionID,
                "type": type.rawValue,
                "event": event,
                "detail": detail,
            ]
            guard JSONSerialization.isValidJSONObject(record),
                  let data = try? JSONSerialization.data(withJSONObject: record),
                  var line = String(data: data, encoding: .utf8) else {
                return
            }
            line += "\n"
            self.appendLine(line)
        }
    }

    /// 业务动作埋点：用户意图层（在动作分发处调用）
    /// 例：UXEventLog.shared.action("toggle_recording", detail: ["from": "menu"])
    func action(_ name: String, detail: [String: Any] = [:]) {
        log(.action, name, detail: detail)
    }

    /// UI 状态变化埋点：状态机转换的关键证据
    /// 例：UXEventLog.shared.state("tab_changed", detail: ["from": "record", "to": "files"])
    /// 传 snapshotWindow: true 时自动附带当前视图树快照（用于对比 UI 是否真的变了）
    func state(_ event: String, detail: [String: Any] = [:], snapshotWindow: Bool = false) {
        var d = detail
        if snapshotWindow, let window = NSApp.keyWindow ?? NSApp.mainWindow {
            d["view_tree"] = dumpTree(of: window)
        }
        log(.state, event, detail: d)
    }

    /// 模块功能埋点：功能是否启动、是否正常运转（ok/fail + 耗时是关键）
    /// 例：UXEventLog.shared.module("Recording", "start", ok: true, elapsedMs: 120, detail: ["device": "Aggregate"])
    func module(_ name: String, _ event: String, ok: Bool? = nil, elapsedMs: Double? = nil, detail: [String: Any] = [:]) {
        var d = detail
        d["module"] = name
        if let ok { d["ok"] = ok }
        if let elapsedMs { d["elapsed_ms"] = elapsedMs }
        log(.module, "\(name).\(event)", detail: d)
    }

    /// 产物埋点：落盘硬验证依据
    /// 例：UXEventLog.shared.artifact("recording_file_created", path: url.path, detail: ["format": "m4a"])
    func artifact(_ event: String, path: String? = nil, detail: [String: Any] = [:]) {
        var d = detail
        if let path { d["path"] = path }
        if let path, let attrs = try? fileManager.attributesOfItem(atPath: path) {
            d["size"] = (attrs[.size] as? Int) ?? 0
        }
        log(.artifact, event, detail: d)
    }

    // MARK: - 全局输入监控（零埋点采集所有点击/键盘/滚动）

    /// 安装 App 内全局事件监控。只捕获发往本 App 的事件，不影响事件正常派发。
    /// 配合控件的 accessibilityIdentifier（项目已有），target 可直接定位到具体控件。
    func installGlobalInputMonitor() {
        guard !monitorInstalled else { return }
        monitorInstalled = true

        let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
            self?.recordClick(event)
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.recordKey(event)
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.recordScroll(event)
            return event
        }
    }

    private func recordClick(_ event: NSEvent) {
        var d = describeTarget(of: event)
        d["button"] = clickButtonName(event.type)
        log(.input, "click", detail: d)
    }

    private func recordKey(_ event: NSEvent) {
        var d = describeTarget(of: event)
        d["key"] = event.charactersIgnoringModifiers ?? "?"
        d["keyCode"] = Int(event.keyCode)
        d["modifiers"] = Self.describeFlags(event.modifierFlags)
        log(.input, "key", detail: d)
    }

    private func recordScroll(_ event: NSEvent) {
        // 300ms 节流：滚动是连续事件，只记录节拍
        let now = Date()
        guard now.timeIntervalSince(lastScrollLogDate) > 0.3 else { return }
        lastScrollLogDate = now
        var d = describeTarget(of: event)
        d["deltaY"] = Int(event.scrollingDeltaY)
        d["deltaX"] = Int(event.scrollingDeltaX)
        log(.input, "scroll", detail: d)
    }

    private func clickButtonName(_ type: NSEvent.EventType) -> String {
        switch type {
        case .leftMouseDown: return "left"
        case .rightMouseDown: return "right"
        case .otherMouseDown: return "middle"
        default: return "unknown"
        }
    }

    /// 解析事件目标：命中视图 + 沿祖先链找 accessibilityIdentifier / label / 控件标题
    private func describeTarget(of event: NSEvent) -> [String: Any] {
        var d: [String: Any] = [:]
        let loc = event.locationInWindow
        d["x"] = Int(loc.x)
        d["y"] = Int(loc.y)

        guard let window = event.window else {
            d["window"] = "none"
            return d
        }
        d["window"] = windowTitle(of: window)

        guard let content = window.contentView else { return d }
        let point = content.convert(loc, from: nil)
        guard let hit = content.hitTest(point) else { return d }
        d["hit"] = String(describing: type(of: hit))
        d["hit_frame"] = NSStringFromRect(hit.frame)

        // 祖先链上第一个有 identifier 的视图作为语义目标
        var cursor: NSView? = hit
        while let v = cursor {
            if let id = v.identifier?.rawValue, !id.isEmpty {
                d["target"] = id
                break
            }
            cursor = v.superview
        }
        if d["target"] == nil, let label = hit.accessibilityLabel(), !label.isEmpty {
            d["target"] = label
        }
        if let control = hit as? NSControl {
            d["enabled"] = control.isEnabled
            if let button = control as? NSButton, !button.title.isEmpty {
                d["title"] = button.title
            }
        }
        return d
    }

    private func windowTitle(of window: NSWindow) -> String {
        if window === NSApp.mainWindow || window === NSApp.keyWindow { return "main" }
        return window.title.isEmpty ? String(describing: type(of: window)) : window.title
    }

    private static func describeFlags(_ m: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if m.contains(.command) { parts.append("cmd") }
        if m.contains(.shift) { parts.append("shift") }
        if m.contains(.option) { parts.append("opt") }
        if m.contains(.control) { parts.append("ctrl") }
        if m.contains(.function) { parts.append("fn") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    // MARK: - 视图树快照（UI 状态的可读序列化）

    /// 导出当前主窗口（或指定窗口）的视图树快照文本
    @discardableResult
    func dumpTree(of window: NSWindow, maxDepth: Int = 14) -> String {
        var lines: [String] = []
        dumpView(window.contentView ?? NSView(), depth: 0, maxDepth: maxDepth, out: &lines)
        return lines.joined(separator: "\n")
    }

    /// 记录一次 UI 状态快照到事件流（供测试断言 / 报障回放）
    func recordStateSnapshot(reason: String, window: NSWindow? = nil) {
        guard let target = window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        state("view_snapshot", detail: [
            "reason": reason,
            "window_frame": NSStringFromRect(target.frame),
            "view_tree": dumpTree(of: target),
        ])
    }

    private func dumpView(_ view: NSView, depth: Int, maxDepth: Int, out: inout [String]) {
        guard depth <= maxDepth else { return }
        let indent = String(repeating: "  ", count: depth)
        var line = "\(indent)\(String(describing: type(of: view)))"
        if let id = view.identifier?.rawValue, !id.isEmpty { line += " id=\(id)" }
        if let label = view.accessibilityLabel(), !label.isEmpty { line += " label=\(label)" }
        line += " frame=\(NSStringFromRect(view.frame))"
        if view.isHidden { line += " hidden" }
        if let control = view as? NSControl {
            line += " enabled=\(control.isEnabled)"
            if let button = control as? NSButton {
                if !button.title.isEmpty { line += " title=\(button.title)" }
                line += " state=\(button.state.rawValue)"
            } else if !control.stringValue.isEmpty {
                line += " value=\(control.stringValue.prefix(60))"
            }
        }
        out.append(line)
        for sub in view.subviews {
            dumpView(sub, depth: depth + 1, maxDepth: maxDepth, out: &out)
        }
    }

    // MARK: - 写入

    private func appendLine(_ line: String) {
        if fileHandle == nil {
            let created = fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
            if created {
                fileHandle = FileHandle(forWritingAtPath: logFileURL.path)
            }
        }
        guard let handle = fileHandle, let data = line.data(using: .utf8) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        // INFRA-006: 写后同步落盘——UXEventLog 是自验/取证的控制流信号（lite 通道轮询它断言），
        // FileHandle 无缓冲刷新会滞留内存直到进程退出，外部脚本实时读不到。
        handle.synchronizeFile()
    }

    /// 当前事件流文件路径（供测试脚本读取）
    func currentLogFileURL() -> URL {
        return logFileURL
    }
}
