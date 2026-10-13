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

    // MARK: - 选择与持久化

    /// 用户首选设备 UID（nil = 跟随系统默认）
    var preferredDeviceUID: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set {
            lock.lock()
            defer { lock.unlock() }
            if let uid = newValue {
                UserDefaults.standard.set(uid, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
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
        return "未知设备"
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
