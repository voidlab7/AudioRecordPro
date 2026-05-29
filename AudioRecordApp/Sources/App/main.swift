import Cocoa

// 单实例控制：检查是否已有实例在运行
let bundleID = Bundle.main.bundleIdentifier ?? "com.audiorecord.app"
let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
if runningApps.count > 1 {
    // 已有实例在运行，激活已有实例并退出
    if let existingApp = runningApps.first(where: { $0 != NSRunningApplication.current }) {
        existingApp.activate(options: [.activateIgnoringOtherApps])
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
