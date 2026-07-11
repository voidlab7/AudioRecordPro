import Cocoa
import Foundation
import AVFoundation

/// 应用程序委托
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    private var window: NSWindow!
    private var mainViewController: MainViewController!
    private let logger = Logger.shared
    
    
    // MARK: - Application Lifecycle
    
    /// 清理日志文件，从0开始记录
    private func clearLogFiles() {
        let logDir = logger.getLogDirectoryURL()
        
        do {
            let fileManager = FileManager.default
            
            // 检查日志目录是否存在
            if fileManager.fileExists(atPath: logDir.path) {
                // 获取目录中的所有文件
                let logFiles = try fileManager.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil)
                
                // 删除所有日志文件
                for fileURL in logFiles {
                    try fileManager.removeItem(at: fileURL)
                    print("🗑️ 已删除旧日志文件: \(fileURL.lastPathComponent)")
                }
                
                print("✅ 所有旧日志文件已清理完成")
            } else {
                print("📁 日志目录不存在，无需清理")
            }
        } catch {
            print("❌ 清理日志文件失败: \(error.localizedDescription)")
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("应用程序启动完成")
        
        // 清理旧日志文件，从0开始记录
        clearLogFiles()
        
        // 输出日志目录信息
        let logDir = logger.getLogDirectoryURL()
        let logFile = logger.getLogFileURL()
        logger.info("日志目录: \(logDir.path)")
        logger.info("日志文件: \(logFile.path)")
        
        // 检查日志目录是否存在
        if FileManager.default.fileExists(atPath: logDir.path) {
            logger.info("✅ 日志目录存在")
        } else {
            logger.warning("❌ 日志目录不存在")
        }
        
        
        // 强制整个应用使用暗色外观（工业风格 = 深色模式）
        NSApp.appearance = NSAppearance(named: .darkAqua)
        
        // 设置应用策略
        NSApp.setActivationPolicy(.regular)
        logger.info("已设置 NSApp 策略为 regular。当前窗口数: \(NSApp.windows.count)")

        // 设置应用 Dock 图标（从 Resources 加载 assets/AudioRecordLogo.png）
        if let iconURL = Bundle.main.url(forResource: "AudioRecordLogo", withExtension: "png") {
            if let iconImage = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = iconImage
                logger.info("应用图标已设置: AudioRecordLogo.png")
            } else {
                logger.warning("无法加载应用图标图像数据")
            }
        } else {
            logger.warning("未找到应用图标资源 AudioRecordLogo.png")
        }
        
        // 请求音频录制权限
        requestAudioCapturePermissions()
        
        // 创建主窗口
        logger.info("准备创建主窗口…")
        createMainWindow()
        
        // 立即显示窗口（改为在 createMainWindow 里处理，这里仅记录当前窗口数）
        logger.info("applicationDidFinishLaunching: 当前窗口数=\(NSApp.windows.count)，window.isVisible=\(window.isVisible)")
        
        // 启动后兜底一次前置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let count = NSApp.windows.count
            let keyBefore = String(describing: NSApp.keyWindow)
            self.logger.info("launch fallback: 当前窗口数=\(count) keyWindow=\(keyBefore)")
            if NSApp.keyWindow == nil || !(self.window?.isVisible ?? false) {
                self.window?.center()
                self.window?.makeKeyAndOrderFront(nil)
                self.window?.orderFrontRegardless()
                self.window?.makeMain()
                NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
                let list = NSApp.windows.map { w in "title=\(w.title) visible=\(w.isVisible) frame=\(NSStringFromRect(w.frame)) level=\(w.level.rawValue)" }.joined(separator: " | ")
                self.logger.info("launch fallback: 前置后 keyWindow=\(String(describing: NSApp.keyWindow)) 列表=\(list)")
            }
        }
        logger.info("应用程序设置完成")
        
        // 检查上次未完成的录制（crash 恢复）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.mainViewController?.checkAndRecoverUnfinishedRecording()
        }
        
        // 添加设置菜单项（Cmd+,）和快捷键
        setupSettingsMenu()
        setupKeyboardShortcuts()
    }
    
    // MARK: - Settings Menu
    private func setupSettingsMenu() {
        // 查找或创建应用菜单
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            // 在「退出」之前插入「设置…」
            let settingsItem = NSMenuItem(
                title: "设置…",
                action: #selector(openSettings),
                keyEquivalent: ","
            )
            settingsItem.target = self
            
            // 找到退出菜单项的位置
            let quitIndex = appMenu.items.firstIndex(where: { $0.action == #selector(NSApplication.terminate(_:)) }) ?? appMenu.items.count
            appMenu.insertItem(NSMenuItem.separator(), at: quitIndex)
            appMenu.insertItem(settingsItem, at: quitIndex)
        }
    }
    
    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }
    
    // MARK: - Keyboard Shortcuts
    private func setupKeyboardShortcuts() {
        guard let mainMenu = NSApp.mainMenu else { return }
        
        // 创建 "编辑" 菜单（Undo/Redo — REQ-1.1-06）
        let editMenu = NSMenu(title: "编辑")
        let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        
        let undoItem = NSMenuItem(title: "撤销", action: #selector(editorUndo), keyEquivalent: "z")
        undoItem.keyEquivalentModifierMask = .command
        editMenu.addItem(undoItem)
        
        let redoItem = NSMenuItem(title: "重做", action: #selector(editorRedo), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        
        mainMenu.addItem(editMenuItem)
        
        // 创建 "录制" 菜单
        let recordMenu = NSMenu(title: "录制")
        let recordMenuItem = NSMenuItem(title: "录制", action: nil, keyEquivalent: "")
        recordMenuItem.submenu = recordMenu
        
        // Cmd+R — 开始/停止录制
        let toggleRecordItem = NSMenuItem(
            title: "开始/停止录制",
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        toggleRecordItem.keyEquivalentModifierMask = .command
        recordMenu.addItem(toggleRecordItem)
        
        // Space — 播放/暂停
        let togglePlayItem = NSMenuItem(
            title: "播放/暂停",
            action: #selector(togglePlayback),
            keyEquivalent: " "
        )
        togglePlayItem.keyEquivalentModifierMask = []
        recordMenu.addItem(togglePlayItem)
        
        // Cmd+E — 导出
        let exportItem = NSMenuItem(
            title: "导出 MP3",
            action: #selector(exportCurrentFile),
            keyEquivalent: "e"
        )
        exportItem.keyEquivalentModifierMask = .command
        recordMenu.addItem(exportItem)
        
        recordMenu.addItem(NSMenuItem.separator())
        
        // Cmd+Backspace — 删除
        let deleteItem = NSMenuItem(
            title: "删除录音",
            action: #selector(deleteCurrentFile),
            keyEquivalent: "\u{8}" // backspace
        )
        deleteItem.keyEquivalentModifierMask = .command
        recordMenu.addItem(deleteItem)
        
        recordMenu.addItem(NSMenuItem.separator())
        
        // Cmd+\ — 切换侧边栏
        let toggleSidebarItem = NSMenuItem(
            title: "切换侧边栏",
            action: #selector(toggleSidebar),
            keyEquivalent: "\\"
        )
        toggleSidebarItem.keyEquivalentModifierMask = .command
        recordMenu.addItem(toggleSidebarItem)
        
        mainMenu.addItem(recordMenuItem)
    }
    
    @objc private func toggleSidebar() {
        mainViewController?.toggleSidebarFromMenu()
    }
    
    @objc private func editorUndo() {
        mainViewController?.editorUndoFromMenu()
    }
    
    @objc private func editorRedo() {
        mainViewController?.editorRedoFromMenu()
    }
    
    @objc private func toggleRecording() {
        mainViewController?.toggleRecordingFromMenu()
    }
    
    @objc private func togglePlayback() {
        mainViewController?.togglePlaybackFromMenu()
    }
    
    @objc private func exportCurrentFile() {
        mainViewController?.exportCurrentFileFromMenu()
    }
    
    @objc private func deleteCurrentFile() {
        mainViewController?.deleteCurrentFileFromMenu()
    }
    
    // BUG-014 fix: 非编辑模式下灰显撤销/重做菜单项
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(editorUndo) || menuItem.action == #selector(editorRedo) {
            return mainViewController?.isInEditorMode ?? false
        }
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("应用程序即将退出")
        
        // 清理资源
        cleanup()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        logger.info("最后一个窗口已关闭，应用程序应该退出")
        return true
    }
    
    // MARK: - Window Management
    private func createMainWindow() {
        let windowSize = NSMakeRect(0, 0, 1200, 750)
        logger.info("createMainWindow: 初始尺寸=\(NSStringFromRect(windowSize))")
        
        window = NSWindow(
            contentRect: windowSize,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        logger.info("createMainWindow: NSWindow 已实例化，isVisible=\(window.isVisible)")
        
        // 设置窗口属性
        window.title = "音频录制工具"
        window.isRestorable = false
        
        // 强制暗色外观 — 工业风格设计需要暗色系统 UI（标题栏、分割线、滚动条）
        window.appearance = NSAppearance(named: .darkAqua)
        
        // 一体化标题栏：透明 + 隐藏标题 → 内容直达窗口顶部
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // 全屏时保持标题栏和红绿灯按钮始终可见
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        // 移除自动保存名称，强制使用新尺寸
        // window.setFrameAutosaveName("MainWindow")
        
        // 强制设置窗口尺寸 - 使用更直接的方法
        let newFrame = NSMakeRect(0, 0, 1200, 750)
        window.setFrame(newFrame, display: true, animate: false)
        logger.info("createMainWindow: setFrame 完成，frame=\(NSStringFromRect(window.frame))")
        
        // 确保窗口尺寸被应用
        DispatchQueue.main.async {
            self.logger.info("createMainWindow: DispatchQueue.main 调整窗口尺寸与居中…")
            self.window.setFrame(newFrame, display: true, animate: false)
            self.window.center()
            self.logger.info("createMainWindow: 主线程调整完成，frame=\(NSStringFromRect(self.window.frame))")
        }
        
        // 设置最小尺寸
        window.minSize = NSSize(width: 960, height: 600)
        
        // 确保窗口可以显示
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        logger.info("createMainWindow: 窗口属性设置完成")
        
        // 创建主视图控制器
        NSLog("🔴 [AppDelegate] B1: before MainViewController()")
        mainViewController = MainViewController()
        NSLog("🔴 [AppDelegate] B2: MainViewController 已创建")
        logger.info("createMainWindow: MainViewController 已创建")
        window.contentViewController = mainViewController
        NSLog("🔴 [AppDelegate] B3: contentViewController 设置完成")
        logger.info("createMainWindow: contentViewController 设置完成")
        // 强制加载视图层次，避免延迟加载导致前置失败
        NSLog("🔴 [AppDelegate] B4: before mainViewController.view")
        _ = mainViewController.view
        NSLog("🔴 [AppDelegate] B5: after mainViewController.view")
        // 立即前置（放在任何异步操作之前）
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeMain()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        logger.info("createMainWindow: first front -> visible=\(window.isVisible) key=\(String(describing: NSApp.keyWindow)) count=\(NSApp.windows.count)")
        
        logger.info("主窗口已创建，大小: \(windowSize)")
        logger.info("窗口是否可见: \(window.isVisible)")
        logger.info("窗口层级: \(window.level.rawValue)")

        // 确保显示（有些情况下需要在设置 contentViewController 后再次激活与前置）
        // 再次确认前置
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        logger.info("createMainWindow: ensure front -> visible=\(window.isVisible) key=\(String(describing: NSApp.keyWindow)) count=\(NSApp.windows.count)")
        
        // 窗口显示后，异步加载进程列表（避免 viewDidLoad 中 Auto Layout 死锁）
        DispatchQueue.main.async { [weak self] in
            self?.mainViewController.loadAvailableProcesses()
        }

        // 再次兜底：稍后再次前置并打印窗口列表
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let beforeKey = String(describing: NSApp.keyWindow)
            self.window.center()
            self.window.makeKeyAndOrderFront(nil)
            self.window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            let afterKey = String(describing: NSApp.keyWindow)
            self.logger.info("createMainWindow: 兜底前置完成。keyWindow 前=\(beforeKey) 后=\(afterKey) 可见=\(self.window.isVisible)")
            let list = NSApp.windows.map { w in "title=\(w.title) visible=\(w.isVisible) frame=\(NSStringFromRect(w.frame)) level=\(w.level.rawValue)" }.joined(separator: " | ")
            self.logger.info("createMainWindow: 当前窗口列表 -> \(list)")
        }
    }
    
    // MARK: - Cleanup
    /// 请求音频录制权限
    private func requestAudioCapturePermissions() {
        logger.info("🎵 开始请求音频录制权限...")
        
        // 请求麦克风权限
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.logger.info("✅ 麦克风权限已授予")
                } else {
                    self?.logger.warning("❌ 麦克风权限被拒绝")
                }
            }
        }
        
        // 请求系统音频捕获权限
        PermissionManager.shared.requestSystemAudioCapturePermission { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .granted:
                    self?.logger.info("✅ 系统音频捕获权限已授予")
                case .denied:
                    self?.logger.warning("❌ 系统音频捕获权限被拒绝")
                case .notDetermined:
                    self?.logger.info("⚠️ 系统音频捕获权限状态未确定")
                case .restricted:
                    self?.logger.warning("⚠️ 系统音频捕获权限受限")
                }
            }
        }
    }
    
    @MainActor
    private func cleanup() {
        // 停止所有音频操作
        if let audioController = mainViewController?.audioRecorderController {
            audioController.stopRecording()
            audioController.stopPlayback()
        }
        
        // 清理临时文件
        FileManagerUtils.shared.cleanupTempFiles()
        
        logger.info("应用程序清理完成")
    }
}
