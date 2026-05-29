import Foundation
import CoreAudio
import AudioToolbox

// MARK: - ProcessTapManager
/// Process Tap 管理器 - 负责创建和管理 CoreAudio Process Tap
@available(macOS 14.4, *)
class ProcessTapManager {
    
    // MARK: - Properties
    private let logger = Logger.shared
    private var processTapObjectID: AudioObjectID = 0
    var uuid: CFString?
    private var streamFormatASBD: AudioStreamBasicDescription?
    
    // MARK: - Public Methods
    
    /// 创建 Process Tap（支持多进程混音）
    func createProcessTap(for processObjectIDs: [AudioObjectID]) -> Bool {
        logger.info("🔧 ProcessTapManager: 开始创建Process Tap...")
        logger.info("🎯 目标进程对象ID列表: \(processObjectIDs)")
        
        // 动态符号声明
        typealias CreateTapFn = @convention(c) (CATapDescription, UnsafeMutablePointer<AudioObjectID>) -> OSStatus

        // dlsym 加载符号
        let handle = dlopen(nil, RTLD_NOW)
        defer { if handle != nil { dlclose(handle) } }
        guard let sym = dlsym(handle, "AudioHardwareCreateProcessTap") else {
            logger.error("❌ ProcessTapManager: 符号 AudioHardwareCreateProcessTap 不可用")
            logger.error("💡 提示: 这通常意味着macOS版本不支持或SDK未包含此符号")
            return false
        }
        let createTap = unsafeBitCast(sym, to: CreateTapFn.self)
        logger.info("✅ 成功加载 AudioHardwareCreateProcessTap 符号")

        // 构造 CATapDescription
        let uuid = UUID()
        logger.info("🔑 生成Tap UUID: \(uuid.uuidString)")
        
        var tapID: AudioObjectID = 0
        
        // 检查是否为空列表（系统混音）
        if processObjectIDs.isEmpty {
            logger.info("🎯 ProcessTapManager: 创建系统混音Tap")
            
            // 尝试使用 stereoGlobalTapButExcludeProcesses API（类似Audio Capture Pro）
            logger.info("🔧 尝试使用 stereoGlobalTapButExcludeProcesses API（全局Tap，排除本进程）")
            let globalDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            globalDesc.uuid = uuid
            globalDesc.muteBehavior = .unmuted
            
            logger.info("📝 全局Tap描述: UUID=\(uuid.uuidString), 静音行为=unmuted")
            
            let globalStatus = createTap(globalDesc, &tapID)
            if globalStatus == noErr && tapID != 0 {
                logger.info("✅ 全局Tap创建成功（类似Audio Capture Pro的方案）")
                self.processTapObjectID = tapID
            } else {
                logger.warning("⚠️ 全局Tap创建失败: OSStatus=\(globalStatus)，回退到系统混音方案")
                
                // 回退到系统混音录制
                let systemDesc = CATapDescription(stereoMixdownOfProcesses: [])
                systemDesc.uuid = uuid
                systemDesc.muteBehavior = .unmuted
                
                logger.info("📝 系统混音Tap描述: UUID=\(uuid.uuidString), 静音行为=unmuted")
                
                let systemStatus = createTap(systemDesc, &tapID)
                if systemStatus != noErr || tapID == 0 {
                    logger.error("❌ ProcessTapManager: 系统混音Tap创建失败: OSStatus=\(systemStatus)")
                    return false
                } else {
                    logger.info("✅ 系统混音Tap创建成功")
                }
                self.processTapObjectID = tapID
            }
        } else {
            // 录制特定进程（支持多进程混音）
            logger.info("🎯 ProcessTapManager: 为进程列表创建Tap: \(processObjectIDs)")
            
            // 方法1: 尝试 stereoMixdownOfProcesses (支持多进程)
            logger.info("🔧 尝试方法1: stereoMixdownOfProcesses (多进程混音)")
            let desc = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
            desc.uuid = uuid
            desc.muteBehavior = .unmuted
            desc.isExclusive = false  // 参考audio-rec
            desc.isMixdown = true     // 参考audio-rec
            
            logger.info("📝 Tap描述: 进程列表=\(processObjectIDs), UUID=\(uuid.uuidString), 静音行为=unmuted, 独占=\(desc.isExclusive), 混音=\(desc.isMixdown)")
            
            let status = createTap(desc, &tapID)
            
            if status != noErr || tapID == 0 {
                logger.error("❌ ProcessTapManager: 创建Process Tap失败")
                logger.error("   错误代码: OSStatus=\(status)")
                logger.error("   返回的Tap ID: \(tapID)")
                return false
            } else {
                logger.info("✅ Process Tap创建成功: 录制 \(processObjectIDs.count) 个进程")
            }
            
            self.processTapObjectID = tapID
        }
        
        logger.info("🎉 ProcessTapManager: Process Tap创建成功!")
        logger.info("   Tap ID: \(tapID)")
        logger.info("   生成的UUID: \(uuid.uuidString)")
        
        // 获取Process Tap的真实UID
        var tapUIDProperty = AudioObjectPropertyAddress(
            mSelector: AudioUtils.kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var tapUID: CFString?
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = withUnsafeMutablePointer(to: &tapUID) { tapUIDPtr in
            AudioObjectGetPropertyData(tapID, &tapUIDProperty, 0, nil, &dataSize, tapUIDPtr)
        }
        
        if uidStatus == noErr, let realTapUID = tapUID {
            self.uuid = realTapUID
            logger.info("✅ 获取到Tap真实UID: \(realTapUID)")
        } else {
            // 'who?' (0x77686F3F) 表示属性不可用，这是正常的
            logger.debug("⚠️ 无法获取Tap真实UID (错误码: \(uidStatus)/'who?')，使用生成的UUID")
            // 作为后备方案，使用生成的UUID
            self.uuid = uuid.uuidString as CFString
            logger.info("✅ 使用生成的UUID: \(uuid.uuidString)")
        }
        
        // Process Tap创建成功，等待聚合设备激活
        logger.info("🔧 ProcessTapManager: Process Tap已创建，等待聚合设备激活")
        
        return true
    }
    
    /// 读取 Tap 流格式
    func readTapStreamFormat() -> Bool {
        logger.info("📊 ProcessTapManager: 开始读取Tap流格式...")
        guard processTapObjectID != 0 else { 
            logger.error("❌ ProcessTapManager: Process Tap未创建，无法读取格式")
            return false 
        }
        
        logger.info("🔍 查询Tap属性: kAudioTapPropertyFormat")
        var address = AudioObjectPropertyAddress(
            mSelector: AudioUtils.kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(processTapObjectID, &address, 0, nil, &dataSize, &asbd)
        if status != noErr {
            logger.warning("⚠️ ProcessTapManager: 读取kAudioTapPropertyFormat失败，使用默认格式")
            logger.warning("   错误代码: OSStatus=\(status)")
            logger.warning("   Tap ID: \(processTapObjectID)")
            
            // DR-01: 回退格式使用动态检测的采样率 + Float32（匹配回调实际数据格式）
            // 注意：这里是 Tap 的原生格式（Float32），不是文件输出格式（16-bit PCM）
            // 文件格式转换在 CoreAudioProcessTapRecorder.createAudioFileWithTapFormat 中处理
            let detectedSampleRate = AudioUtils.getCurrentAudioDeviceSampleRate()
            asbd = AudioStreamBasicDescription(
                mSampleRate: detectedSampleRate,        // ← 跟随设备实际采样率
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 8,
                mFramesPerPacket: 1,
                mBytesPerFrame: 8,
                mChannelsPerFrame: 2,
                mBitsPerChannel: 32,                    // ← Float32（回调原生格式）
                mReserved: 0
            )
            logger.info("📊 使用动态检测回退格式: \(detectedSampleRate)Hz, 32bit Float, 立体声")
        }
        
        self.streamFormatASBD = asbd
        logger.info("🎉 ProcessTapManager: Tap流格式读取成功!")
        logger.info("📊 音频格式详情:")
        logger.info("   采样率: \(asbd.mSampleRate) Hz")
        logger.info("   声道数: \(asbd.mChannelsPerFrame)")
        logger.info("   位深: \(asbd.mBitsPerChannel) bit")
        logger.info("   每帧字节数: \(asbd.mBytesPerFrame)")
        logger.info("   每包帧数: \(asbd.mFramesPerPacket)")
        logger.info("   格式ID: \(asbd.mFormatID)")
        logger.info("   格式标志: \(asbd.mFormatFlags)")
        
        return true
    }
    
    /// 销毁 Process Tap
    func destroyProcessTap() {
        logger.info("ProcessTapManager: 开始销毁 Process Tap")
        
        if processTapObjectID != 0 {
            typealias DestroyTapFn = @convention(c) (AudioObjectID) -> OSStatus
            let handle = dlopen(nil, RTLD_NOW)
            defer { if handle != nil { dlclose(handle) } }
            if let sym = dlsym(handle, "AudioHardwareDestroyProcessTap") {
                let destroyTap = unsafeBitCast(sym, to: DestroyTapFn.self)
                let status = destroyTap(processTapObjectID)
                if status != noErr {
                    logger.warning("ProcessTapManager: AudioHardwareDestroyProcessTap 失败: \(status)")
                } else {
                    logger.info("ProcessTapManager: Process Tap 已销毁")
                }
            }
            processTapObjectID = 0
        }
        
        self.uuid = nil
        streamFormatASBD = nil
    }
    
    // MARK: - Getters
    
    var tapObjectID: AudioObjectID {
        return processTapObjectID
    }
    
    var tapUUIDProperty: CFString? {
        return self.uuid
    }
    
    var streamFormat: AudioStreamBasicDescription? {
        return streamFormatASBD
    }
    
    var isCreated: Bool {
        return processTapObjectID != 0
    }
}
