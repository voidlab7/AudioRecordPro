import Foundation
import Darwin
import CoreAudio
import AppKit

// AudioProcessInfo 已移动到 API/Types.swift

// MARK: - AudioProcessEnumerator
/// 音频进程枚举器 - 负责获取和管理可录制的音频进程列表
class AudioProcessEnumerator {
    
    // MARK: - Properties
    private let logger = Logger.shared
    
    // MARK: - Public Methods
    
    /// 获取所有可用的音频进程列表
    func getAvailableAudioProcesses() -> [AudioProcessInfo] {
        logger.info("🔍 AudioProcessEnumerator: 开始枚举可用音频进程...")
        var results: [AudioProcessInfo] = []

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // 读取列表大小
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else {
            logger.error("❌ AudioProcessEnumerator: 读取进程对象列表大小失败: OSStatus=\(status)")
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        logger.info("📊 发现 \(count) 个音频进程对象")

        // 读取进程对象ID数组
        var objectIDs = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &objectIDs)
        guard status == noErr else {
            logger.error("❌ AudioProcessEnumerator: 读取进程对象列表失败: OSStatus=\(status)")
            return []
        }

        logger.info("🔍 开始解析每个进程对象...")
        for (index, oid) in objectIDs.enumerated() where oid != kAudioObjectUnknown {
            guard let pid = readPID(for: oid) else { 
                logger.debug("⚠️ 进程对象[\(index)] ID=\(oid): 无法读取PID，跳过")
                continue 
            }
            
            let (name, path) = readNameAndPath(for: pid)
            
            // 跳过被过滤的进程
            if name.isEmpty {
                logger.debug("⚠️ 进程对象[\(index)] PID=\(pid): 被过滤，跳过")
                continue
            }
            
            let bundleID = readBundleID(for: oid) ?? ""

            // 进一步过滤：排除 Helper/Renderer/GPU 等辅助进程（如 Google Chrome Helper）
            if isHelperApp(name: name, bundleID: bundleID, path: path) {
                logger.debug("🧹 过滤 Helper 进程: name=\(name), bundle=\(bundleID), path=\(path)")
                continue
            }
            
            // 对 Chromium 音频服务进程，提取主应用名显示
            // "Comet Helper" → "Comet", "Google Chrome Helper" → "Google Chrome"
            var displayName = name
            let nameLower = name.lowercased()
            if isAppBundleHelper(path: path) {
                // 提取主应用名：
                // "Comet Helper" → "Comet"
                // "ChatGPT Atlas (Service)" → "ChatGPT Atlas"
                // "ChatGPT Atlas (Renderer)" → "ChatGPT Atlas"
                // "Google Chrome Helper" → "Google Chrome"
                if nameLower.hasSuffix(" helper") {
                    displayName = String(name.dropLast(" Helper".count))
                } else if let parenRange = name.range(of: " (", options: .backwards) {
                    displayName = String(name[name.startIndex..<parenRange.lowerBound])
                }
                if displayName != name {
                    logger.debug("📛 重命名: \(name) → \(displayName)")
                }
            }
            
            let info = AudioProcessInfo(
                pid: pid,
                name: displayName,
                bundleID: bundleID,
                path: path,
                processObjectID: oid
            )
            results.append(info)
            logger.debug("✅ 进程对象[\(index)]: \(name) (PID: \(pid), Bundle: \(bundleID))")
        }

        logger.info("🎉 AudioProcessEnumerator: 枚举完成，返回 \(results.count) 个可用音频进程")
        
        // 按显示名去重（同一应用的多个 Helper 只保留第一个）
        var seen = Set<String>()
        var dedupResults: [AudioProcessInfo] = []
        for process in results {
            let key = process.name.lowercased()
            if seen.contains(key) {
                logger.debug("🔄 去重跳过: \(process.name) (PID=\(process.pid))")
                continue
            }
            seen.insert(key)
            dedupResults.append(process)
        }
        results = dedupResults
        
        // 输出所有进程的详细信息
        for (index, process) in results.enumerated() {
            logger.info("   [\(index)] \(process.name) (PID: \(process.pid), Bundle: \(process.bundleID), 对象ID: \(process.processObjectID))")
        }
        
        return results
    }
    
    /// 根据 PID 查找进程对象 ID
    func findProcessObjectID(by pid: pid_t) -> AudioObjectID? {
        let processes = getAvailableAudioProcesses()
        return processes.first { $0.pid == pid }?.processObjectID
    }
    
    /// 根据 PID 查找该应用及其所有音频子进程的 ObjectID
    /// Chrome 等多进程应用：主进程注册在 CoreAudio 但不产生音频，Helper 进程才有数据
    /// 策略：主进程 + 所有同名前缀的子进程全部加入 Tap
    func findAllRelatedProcessObjectIDs(by pid: pid_t) -> [AudioObjectID] {
        // 读取完整进程列表（未过滤的）
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return [] }
        
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &objectIDs)
        guard status == noErr else { return [] }
        
        // 读取目标 PID 的进程名（使用不过滤的原始版本，避免进程退出或被过滤导致匹配失败）
        let targetName = readRawProcessName(for: pid)
        let targetNameLower = targetName.lowercased()
        
        if targetNameLower.isEmpty {
            logger.warning("⚠️ findAllRelatedProcessObjectIDs: 目标PID=\(pid) 无法获取进程名（可能已退出）")
            return []
        }
        
        // Extract the base app name for matching (e.g. "Google Chrome Helper" → "Google Chrome")
        // This ensures we match all related processes regardless of suffix
        let baseAppName = extractBaseAppName(from: targetNameLower)
        logger.info("🔍 findAllRelatedProcessObjectIDs: targetName=\(targetName), baseAppName=\(baseAppName)")
        
        var result: [AudioObjectID] = []
        
        for oid in objectIDs where oid != kAudioObjectUnknown {
            guard let oPid = readPID(for: oid) else { continue }
            // Use raw proc_name without filtering — we need ALL related processes
            let name = readRawProcessName(for: oPid)
            let nameLower = name.lowercased()
            guard !nameLower.isEmpty else { continue }
            
            // Match rules:
            // 1. Exact PID match
            // 2. Process name contains the base app name (e.g. "google chrome helper (renderer)" contains "google chrome")
            // 3. Base app name contains the process name (e.g. target is helper, find main process)
            if oPid == pid || nameLower.contains(baseAppName) || baseAppName.contains(nameLower) {
                result.append(oid)
                logger.info("🔗 关联进程: \(name) (PID=\(oPid)) -> ObjectID=\(oid)")
            }
        }
        
        logger.info("🎯 PID=\(pid) (\(targetName)) 共关联 \(result.count) 个音频进程")
        return result
    }
    
    /// Read raw process name without any filtering (for use in findAllRelatedProcessObjectIDs)
    /// This avoids the issue where shouldFilterProcess returns empty for valid Chrome Helper processes
    private func readRawProcessName(for pid: pid_t) -> String {
        let nameBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(MAXPATHLEN))
        let pathBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(MAXPATHLEN))
        defer { nameBuffer.deallocate(); pathBuffer.deallocate() }
        
        let nameLen = proc_name(pid, nameBuffer, UInt32(MAXPATHLEN))
        let pathLen = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        
        if nameLen > 0 {
            return String(cString: nameBuffer)
        } else if pathLen > 0 {
            let path = String(cString: pathBuffer)
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return ""
    }
    
    /// Extract the base application name from a process name
    /// "Google Chrome Helper (Renderer)" → "google chrome"
    /// "Google Chrome Helper" → "google chrome"
    /// "Google Chrome" → "google chrome"
    private func extractBaseAppName(from nameLower: String) -> String {
        // Remove common suffixes to get the base app name
        var base = nameLower
        
        // Remove parenthetical suffixes: " (renderer)", " (gpu)", " (service)" etc.
        if let parenRange = base.range(of: " (", options: .backwards) {
            base = String(base[base.startIndex..<parenRange.lowerBound])
        }
        
        // Remove " helper" suffix
        if base.hasSuffix(" helper") {
            base = String(base.dropLast(" helper".count))
        }
        
        return base
    }
    
    /// 解析系统混音 PID（coreaudiod 进程）
    func resolveDefaultSystemMixPID() -> pid_t? {
        logger.info("AudioProcessEnumerator: 尝试解析系统混音 PID...")
        
        // 尝试通过 ps 命令查找 coreaudiod 进程
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid,comm"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                logger.warning("AudioProcessEnumerator: 无法解析 ps 输出，使用默认 PID 171")
                return 171
            }
            
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if parts.count >= 2, let pidStr = parts.first, let pid = Int32(pidStr) {
                    let command = parts[1]
                    if command.contains("coreaudiod") {
                        logger.info("AudioProcessEnumerator: 找到 coreaudiod 进程 PID: \(pid)")
                        return pid
                    }
                }
            }
            
            logger.warning("AudioProcessEnumerator: 未找到 coreaudiod 进程，使用默认 PID 171")
            return 171
            
        } catch {
            logger.error("AudioProcessEnumerator: 执行 ps 命令失败: \(error)，使用默认 PID 171")
            return 171
        }
    }
    
    // MARK: - Private Methods
    
    private func readPID(for objectID: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        let s = AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &pid)
        return s == noErr && pid > 0 ? pid : nil
    }

    private func readBundleID(for objectID: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfstr: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let s = withUnsafeMutablePointer(to: &cfstr) { ptr -> OSStatus in
            AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, ptr)
        }
        if s == noErr, let bid = cfstr as String?, !bid.isEmpty { return bid }
        return nil
    }

    private func readNameAndPath(for pid: pid_t) -> (String, String) {
        let nameBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(MAXPATHLEN))
        let pathBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(MAXPATHLEN))
        defer { nameBuffer.deallocate(); pathBuffer.deallocate() }
        
        let nameLen = proc_name(pid, nameBuffer, UInt32(MAXPATHLEN))
        let pathLen = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        
        var name: String
        var path: String
        
        if nameLen > 0 {
            name = String(cString: nameBuffer)
        } else {
            if pathLen > 0 {
                path = String(cString: pathBuffer)
                name = URL(fileURLWithPath: path).lastPathComponent
                if name.isEmpty {
                    name = "System Process (\(pid))"
                }
            } else {
                name = "System Process (\(pid))"
            }
        }
        
        path = pathLen > 0 ? String(cString: pathBuffer) : ""
        
        let bundlePath = convertToBundlePath(path)
        
        if shouldFilterProcess(name: name, pid: pid, path: bundlePath) {
            return ("", "")
        }
        
        return (name, bundlePath)
    }
    
    private func shouldFilterProcess(name: String, pid: pid_t, path: String) -> Bool {
        let systemProcesses = [
            "kernel_task", "launchd", "kernel", "mach_init",
            "WindowServer", "loginwindow", "sh", "bash", "zsh"
        ]
        
        if systemProcesses.contains(name) {
            return true
        }
        
        if pid < 100 {
            return true
        }
        
        if path.isEmpty {
            return true
        }
        
        // 过滤自己（当前应用）
        if pid == getpid() {
            logger.debug("🚫 过滤当前应用: name=\(name), pid=\(pid)")
            return true
        }
        
        // 过滤自己的应用名称
        if name == "audio_record_mac" || path.contains("audio_record_mac") {
            logger.debug("🚫 过滤当前应用: name=\(name), path=\(path)")
            return true
        }
        
        let systemPaths = [
            "/System/Library/",
            "/usr/libexec/",
            "/usr/sbin/",
            "/sbin/"
        ]
        
        for systemPath in systemPaths {
            if path.hasPrefix(systemPath) {
                return true
            }
        }
        
        // 仅保留 Dock 应用（ActivationPolicy == .regular）
        // 例外：/Applications/xxx.app/ 下的 Helper 子进程也保留（Chromium 系音频进程）
        if !isDockApp(pid: pid, path: path) {
            if isAppBundleHelper(path: path) {
                logger.debug("✅ shouldFilter: 保留 App Bundle Helper: \(name)")
                return false
            }
            return true
        }
        
        return false
    }
    
    /// 判断是否是某个 /Applications/xxx.app/ 下的子进程（Helper/Service/Renderer 等）
    /// 覆盖 Chromium 系（Chrome Helper.app）和非标准命名（ChatGPT Atlas (Service).app）
    private func isAppBundleHelper(path: String) -> Bool {
        let p = path.lowercased()
        // 必须在 /applications/ 下
        guard p.contains("/applications/") else { return false }
        // 路径包含 /helpers/ 或 /frameworks/ 且在某个 .app 内 = 子进程
        return p.contains("/helpers/") || p.contains("/frameworks/")
    }

    /// 判断是否为浏览器/应用的 Helper、Renderer、GPU 等辅助进程
    private func isHelperApp(name: String, bundleID: String, path: String) -> Bool {
        let n = name.lowercased()
        let b = bundleID.lowercased()
        let p = path.lowercased()

        // 通用规则：/Applications/xxx.app/ 下的 Helper 如果在 CoreAudio 进程列表中
        // 说明它正在使用音频，应该保留（而非过滤）
        // 覆盖所有 Chromium 系：Chrome/Comet/Arc/Brave/Edge/Electron 等
        if isAppBundleHelper(path: path) {
            logger.debug("✅ 保留 App Bundle 音频 Helper: name=\(name), path=\(path)")
            return false
        }
        
        // 保留已知浏览器/应用主进程
        let knownMainApps = [
            "google chrome", "safari", "firefox", "comet", "arc",
            "brave browser", "microsoft edge", "opera", "vivaldi",
            "chatgpt atlas"
        ]
        if knownMainApps.contains(n) {
            logger.debug("✅ 保留已知主进程: name=\(name)")
            return false
        }
        if b == "com.google.chrome" || b == "com.apple.safari" || b.contains("org.mozilla.firefox") {
            return false
        }

        // 常见关键字过滤
        let keywords = [" helper", "renderer", "gpu", "webhelper", "plugin", "(renderer)"]
        if keywords.contains(where: { n.contains($0) }) {
            logger.debug("🚫 过滤 Helper/Plugin 进程: name=\(name)")
            return true 
        }
        if keywords.contains(where: { b.contains($0) }) { 
            return true 
        }

        // 路径特征：在 Helpers 目录下或以 Helper.app 结尾
        if p.contains("/helpers/") || p.hasSuffix("helper.app") { 
            logger.debug("🚫 过滤 Helper 路径: path=\(path)")
            return true 
        }

        // WebKit/GPU 相关
        if n.contains("webkit") && (n.contains("gpu") || n.contains("network") || n.contains("webcontent")) {
            return true
        }
        return false
    }
    
    /// 判断是否为 Dock 应用
    private func isDockApp(pid: pid_t, path: String) -> Bool {
        // 特殊处理：Chrome Helper 音频服务进程总是允许
        if path.contains("Google Chrome Helper.app") && path.contains("audio.mojom.AudioService") {
            logger.debug("✅ isDockApp: 允许 Chrome 音频服务进程: path=\(path)")
            return true
        }
        
        // 使用系统 API 判断是否为 Dock App（.regular activationPolicy）
        if let running = NSRunningApplication(processIdentifier: pid) {
            let isRegular = running.activationPolicy == .regular
            if isRegular {
                logger.debug("✅ isDockApp: 通过 activationPolicy 判断为 Dock App: \(path)")
            }
            return isRegular
        }
        
        let bundleURL = URL(fileURLWithPath: path)
        if let bundle = Bundle(url: bundleURL) {
            if let uiElement = bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool, uiElement { return false }
            if let bgOnly = bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool, bgOnly { return false }
            return true
        }
        
        return false
    }
    
    /// 将可执行文件路径转换为 .app bundle 路径
    private func convertToBundlePath(_ executablePath: String) -> String {
        guard !executablePath.isEmpty else { return executablePath }
        
        let url = URL(fileURLWithPath: executablePath)
        var currentURL = url
        
        while currentURL.path != "/" {
            if currentURL.pathExtension == "app" {
                return currentURL.path
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        return executablePath
    }
}
