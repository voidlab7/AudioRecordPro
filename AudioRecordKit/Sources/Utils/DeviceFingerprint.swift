import Foundation
import IOKit
import CryptoKit

/// 设备指纹获取
/// 基于 IOPlatformUUID + SHA256 派生设备唯一标识
/// 用于文件加密中的设备绑定
class DeviceFingerprint {
    
    static let shared = DeviceFingerprint()
    private let logger = Logger.shared
    
    /// 缓存的设备 ID（懒加载，首次获取后缓存）
    private var _cachedDeviceID: Data?
    private let lock = NSLock()
    
    private init() {}
    
    // MARK: - Public API
    
    /// 获取设备唯一标识（32 bytes SHA256）
    /// 基于 IOPlatformUUID（硬件唯一标识，重装系统不变）
    func deviceID() -> Data {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = _cachedDeviceID {
            return cached
        }
        
        let id = computeDeviceID()
        _cachedDeviceID = id
        logger.info("设备指纹已生成: \(id.prefix(8).map { String(format: "%02x", $0) }.joined())...")
        return id
    }
    
    /// 清除缓存（用于测试或重置场景）
    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        _cachedDeviceID = nil
    }
    
    // MARK: - Private Methods
    
    private func computeDeviceID() -> Data {
        // 方案1: IOPlatformUUID（首选）
        if let uuidString = getIOPlatformUUID() {
            let hash = SHA256.hash(data: Data(uuidString.utf8))
            return Data(hash)
        }
        
        // 方案2: 兜底方案（mac host name + 当前用户名 hash）
        logger.warning("IOPlatformUUID 不可用，使用兜底指纹")
        return fallbackDeviceID()
    }
    
    /// 从 IOKit 获取 IOPlatformUUID
    /// 不需要特殊 entitlement，沙盒下可用
    private func getIOPlatformUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        
        guard service != 0 else {
            logger.warning("无法获取 IOPlatformExpertDevice service")
            return nil
        }
        
        defer { IOObjectRelease(service) }
        
        guard let uuidCF = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            logger.warning("无法读取 IOPlatformUUID 属性")
            return nil
        }
        
        return uuidCF
    }
    
    /// 兜底设备指纹：mac host name + 当前用户名 SHA256
    private func fallbackDeviceID() -> Data {
        let hostName = Host.current().localizedName ?? "unknown-host"
        let userName = NSUserName()
        let combined = "\(hostName):\(userName)"
        let hash = SHA256.hash(data: Data(combined.utf8))
        logger.info("使用兜底设备指纹（hostname + username）")
        return Data(hash)
    }
}
