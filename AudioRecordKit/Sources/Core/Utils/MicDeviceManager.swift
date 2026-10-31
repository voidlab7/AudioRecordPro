import Foundation
import CoreAudio
import AudioUnit
import AVFoundation

/// 麦克风输入设备信息
struct MicDeviceInfo {
    let deviceID: AudioDeviceID
    let uid: String
    let name: String
    let isSystemDefault: Bool
}

/// FIX-007/FEAT-004: 麦克风输入设备探测与选择
/// - 枚举全部输入设备（内建麦/外接耳机麦/聚合设备等）
/// - 选择持久化（UserDefaults 存设备 UID，跨重启保持）
/// - 绑定到 AVAudioEngine inputNode（底层 AUHAL 设备重定向）
/// - 设备热插拔监听：所选设备失效时回退系统默认并回调通知（界面内提示）
final class MicDeviceManager {

    static let shared = MicDeviceManager()

    private let logger = Logger.shared
    private let defaultsKey = "preferredMicDeviceUID"
    private var changeCallback: (() -> Void)?
    private var installedListener = false
    private let lock = NSLock()

    private init() {}

    // MARK: - 枚举

    /// 枚举全部可用麦克风输入设备（含系统默认标记）
    func listMicrophones() -> [MicDeviceInfo] {
        var devices: [MicDeviceInfo] = []
        var defaultID = AudioDeviceID(0)
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &defaultSize, &defaultID)

        var propSize: UInt32 = 0
        var hwAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &hwAddr, 0, nil, &propSize) == noErr else {
            logger.error("MicDeviceManager: 枚举硬件设备失败")
            return devices
        }
        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &hwAddr, 0, nil, &propSize, &ids)

        for id in ids {
            guard hasInputStreams(id) else { continue }
            let name = deviceName(id)
            // FIX-021: 过滤本 App 自建的 ProcessTap 聚合（名字恒为 "Tap-<UUID>"）——
            // 私有聚合对创建进程可见：在跑的那只录音期间会污染列表，崩溃残留的跨会话
            // 泄漏也会一直躺在麦列表里（老板 10-31 截图实锤：聚合设备 #89802 / #81333）
            if name.hasPrefix("Tap-") { continue }
            // FIX-021: 过滤已失效设备（isAlive=0，如死聚合残留/已拔出设备）
            guard isDeviceAlive(id) else {
                logger.info("MicDeviceManager: 跳过失效设备 id=\(id) name=\(name)")
                continue
            }
            let uid = deviceUID(id)
            guard let uid = uid, !uid.isEmpty else { continue }
            devices.append(MicDeviceInfo(deviceID: id, uid: uid, name: name, isSystemDefault: id == defaultID))
        }
        return devices
    }

    /// 当前系统默认输入设备
    func defaultInputDevice() -> MicDeviceInfo? {
        listMicrophones().first { $0.isSystemDefault }
    }

    // MARK: - UI-015 设备显示名友好化

    /// 设备的 UI 友好显示名。
    /// - 普通设备：原 name 直接用（已是「MacBook Pro Microphone」等）
    /// - Aggregate 设备：尝试解析组成设备名拼成「聚合· A + B」，解析失败显示「聚合设备 #短序号」。
    ///   严禁裸露 `CADefaultDeviceAggregate-76186-6` 之类的系统内部 ID（验收 #2）。
    func displayName(for info: MicDeviceInfo) -> String {
        let raw = info.name
        // 普通设备：name 已经是人可读的（不会含 hex 串或 CADefault 前缀）
        if !looksLikeSystemID(raw) { return raw }
        // Aggregate 设备：先试解子设备
        if let subs = aggregateSubDeviceNames(info.deviceID), !subs.isEmpty {
            if subs.count <= 3 { return "聚合· ".localized + subs.joined(separator: " + ") }
            return "聚合· ".localized + subs[0] + " + " + subs[1] + " +\(subs.count - 2)"
        }
        // fallback：聚合设备 + 短序号（取 uid 末段数字；无则 deviceID）
        let serial = shortSerial(from: info.uid) ?? "\(info.deviceID)"
        return "聚合设备 #".localized + serial
    }

    /// 判断字符串是否像系统内部 ID（hex 串 / CADefault 前缀 / AggregateDevice 等需友好化的特征）
    private func looksLikeSystemID(_ s: String) -> Bool {
        if s.range(of: #"[0-9A-Fa-f]{8,}"#, options: .regularExpression) != nil { return true }
        if s.contains("CADefaultDeviceAggregate") { return true }
        if s.contains("AggregateDevice") { return true }
        return false
    }

    /// 从 uid 字符串提取 3-8 位连续数字串（取最后一组做短序号），无则 nil
    private func shortSerial(from uid: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\d{3,8}"#) else { return nil }
        let nsr = NSRange(uid.startIndex..<uid.endIndex, in: uid)
        let matches = regex.matches(in: uid, range: nsr)
        guard let last = matches.last, let range = Range(last.range, in: uid) else { return nil }
        return String(uid[range])
    }

    /// 解析 Aggregate 设备的组成子设备名（CFArray of UID CFString）
    /// 非 Aggregate 或失败返回 nil（让调用方走 fallback）
    private func aggregateSubDeviceNames(_ id: AudioDeviceID) -> [String]? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
        guard let cfArray = malloc(Int(size))?.assumingMemoryBound(to: CFArray?.self) else { return nil }
        defer { free(cfArray) }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, cfArray) == noErr else { return nil }
        guard let array = cfArray.pointee else { return nil }
        let count = CFArrayGetCount(array)
        var names: [String] = []
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(array, i) else { continue }
            // CFArrayGetValueAtIndex 返回 const void* (UnsafeRawPointer?)，不能直接 `as? String` cast
            // （Swift 编译警告且恒失败）。CFArray element 按 macOS 版本时为 CFString(UID) 或
            // CFDictionary(含 kAudioAggregateDeviceSubDeviceUIDKey)。用 unsafeBitCast → CFTypeRef
            // 再按 CFGetTypeID 分流，Unmanaged 安全提取 CFString → String。
            let cfObj = unsafeBitCast(raw, to: CFTypeRef.self)
            var uidStr: String?
            if CFGetTypeID(cfObj) == CFStringGetTypeID() {
                uidStr = (cfObj as! CFString) as String
            } else if CFGetTypeID(cfObj) == CFDictionaryGetTypeID() {
                let dict = cfObj as! CFDictionary
                // kAudioAggregateDeviceSubDeviceUIDKey 在 Swift CoreAudio overlay 中的可用性不稳，
                // 用其字面值 "uid"（CoreAudio/AudioHardwareBaseTypes.h 原定义）作 CFDictionary key。
                let uidKey = Unmanaged<CFString>.passUnretained("uid" as CFString).toOpaque()
                if let raw = CFDictionaryGetValue(dict, uidKey) {
                    let cfStr = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
                    uidStr = cfStr as String
                }
            }
            if let uid = uidStr, let name = subDeviceNameByUID(uid) {
                names.append(name)
            }
        }
        return names.isEmpty ? nil : names
    }

    /// 通过 `kAudioHardwarePropertyDeviceForUID` 反查 AudioDeviceID，再取 name
    private func subDeviceNameByUID(_ uid: String) -> String? {
        var devID = AudioDeviceID(0)
        var uidRef: CFString = uid as CFString
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDeviceForUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<CFString>.size), &uidRef, &size, &devID) == noErr,
              devID != kAudioObjectUnknown else { return nil }
        return deviceName(devID)
    }

    // MARK: - 选择与持久化

    /// 用户首选设备 UID（nil = 跟随系统默认）
    var preferredDeviceUID: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set {
            let old = UserDefaults.standard.string(forKey: defaultsKey)
            lock.lock()
            if let uid = newValue {
                UserDefaults.standard.set(uid, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
            lock.unlock()
            // FIX-021: 变更即在锁外广播（录音中切麦 → 录制器重建注入引擎）
            if old != newValue {
                firePreferredDeviceChanged(newValue)
            }
        }
    }

    // MARK: - FIX-021: 偏好设备变更广播

    private var preferredChangeCallback: ((String?) -> Void)?

    /// 订阅偏好麦克风设备变更（参数=新偏好 uid，nil=跟随系统默认）
    func onPreferredDeviceChanged(_ callback: @escaping (String?) -> Void) {
        lock.lock()
        preferredChangeCallback = callback
        lock.unlock()
    }

    private func firePreferredDeviceChanged(_ uid: String?) {
        lock.lock()
        let cb = preferredChangeCallback
        lock.unlock()
        cb?(uid)
    }

    /// FEAT-004R2: 解析偏好设备为可用设备（在线校验）
    /// 返回 nil = 无偏好或偏好已失效（调用方回退系统默认输入）
    func resolvedPreferredDevice() -> MicDeviceInfo? {
        guard let uid = preferredDeviceUID, !uid.isEmpty else { return nil }
        let match = listMicrophones().first { $0.uid == uid }
        if match == nil {
            logger.warning("MicDeviceManager: 偏好设备 UID=\(uid) 当前不在线，回退系统默认")
        }
        return match
    }


    // MARK: - 热插拔监听

    /// 设备列表变化回调（拔出/插入）；App 层据此刷新设备列表与提示
    func onDevicesChanged(_ callback: @escaping () -> Void) {
        lock.lock()
        changeCallback = callback
        let needInstall = !installedListener
        installedListener = true
        lock.unlock()
        guard needInstall else { return }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            let mgr = Unmanaged<MicDeviceManager>.fromOpaque(selfPtr).takeUnretainedValue()
            DispatchQueue.main.async { mgr.fireChange() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    }

    private func fireChange() {
        lock.lock()
        let cb = changeCallback
        lock.unlock()
        cb?()
    }

    // MARK: - Private

    private func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    /// FIX-021: 设备存活探测（kAudioDevicePropertyDeviceIsAlive，0=失效）
    private func isDeviceAlive(_ id: AudioDeviceID) -> Bool {
        var alive: UInt32 = 1
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &alive) == noErr else {
            return true  // 查询失败保守放行，不误杀
        }
        return alive != 0
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr {
            return name as String
        }
        return "未知设备".localized  // REL-003
    }

    private func deviceUID(_ id: AudioDeviceID) -> String? {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &uid) == noErr {
            return uid as String
        }
        return nil
    }
}
