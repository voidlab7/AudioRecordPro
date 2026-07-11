import Foundation
import AVFoundation
import Accelerate
import CoreAudio

/// 音频工具类
class AudioUtils {
    static let shared = AudioUtils()
    
    private let logger = Logger.shared
    
    private init() {}
    
    /// 获取当前系统默认音频输出设备的采样率
    static func getCurrentAudioDeviceSampleRate() -> Double {
        var defaultOutputProperty = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var outputDeviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let getStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputProperty,
            0,
            nil,
            &propertySize,
            &outputDeviceID
        )
        
        guard getStatus == noErr else {
            Logger.shared.warning("无法获取默认输出设备，使用默认采样率 44100")
            return 44100.0
        }
        
        // 获取设备的流格式
        var streamFormatProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var asbd = AudioStreamBasicDescription()
        var streamFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let streamFormatStatus = AudioObjectGetPropertyData(
            outputDeviceID,
            &streamFormatProperty,
            0,
            nil,
            &streamFormatSize,
            &asbd
        )
        
        if streamFormatStatus == noErr && asbd.mSampleRate > 0 {
            Logger.shared.info("检测到当前音频设备采样率: \(asbd.mSampleRate) Hz")
            return asbd.mSampleRate
        } else {
            Logger.shared.warning("无法获取音频设备采样率，使用默认采样率 44100")
            return 44100.0
        }
    }
    
    // AudioFormat 和 RecordingMode 已移动到 API/Types.swift
    // 在 SDK 内部直接使用全局定义的类型
    
    /// 计算音频电平（RMS）
    static func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        // 使用 vDSP 计算 RMS
        vDSP_measqv(channelData, 1, &sum, vDSP_Length(frameCount))
        let rms = sqrtf(sum)
        
        // 转换为 dB
        let db = 20 * log10f(max(rms, 1e-6))
        
        // 归一化到 0-1 范围（假设 -60dB 到 0dB）
        let normalized = max(0, min(1, (db + 60) / 60))
        
        return normalized
    }
    
    /// 验证音频文件
    func validateAudioFile(at url: URL) -> Bool {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            logger.info("音频文件验证通过: \(url.lastPathComponent), 时长: \(String(format: "%.2f", duration))秒")
            return duration > 0
        } catch {
            logger.error("音频文件验证失败 \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }
    
    /// 获取音频文件信息
    func getAudioFileInfo(at url: URL) -> AudioFileInfo? {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            let sampleRate = audioFile.fileFormat.sampleRate
            let channels = audioFile.fileFormat.channelCount
            
            return AudioFileInfo(
                url: url,
                duration: duration,
                sampleRate: sampleRate,
                channels: channels,
                format: audioFile.fileFormat.commonFormat
            )
        } catch {
            logger.error("获取音频文件信息失败 \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 检查音频权限
    func checkAudioPermissions() -> (microphone: Bool, systemAudioCapture: Bool) {
        let microphonePermission = checkMicrophonePermission()
        let systemAudioCapturePermission = checkSystemAudioCapturePermission()
        
        logger.info("音频权限 - 麦克风: \(microphonePermission), 系统音频捕获: \(systemAudioCapturePermission)")
        
        return (microphonePermission, systemAudioCapturePermission)
    }
    
    /// 检查系统音频捕获权限（通过 TCC preflight）
    private func checkSystemAudioCapturePermission() -> Bool {
        let status = PermissionManager.shared.checkAllPermissions().systemAudioCapture
        return status == .granted
    }
    
    /// 请求屏幕录制权限（已废弃，转发到系统音频捕获权限）
    func requestScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        PermissionManager.shared.requestSystemAudioCapturePermission { status in
            completion(status == .granted)
        }
    }
    
    /// 获取详细的权限状态信息
    func getDetailedPermissionStatus() -> (microphone: Bool, systemAudioCapture: Bool, systemVersion: String) {
        let microphonePermission = checkMicrophonePermission()
        let systemAudioCapturePermission = checkSystemAudioCapturePermission()
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        return (microphonePermission, systemAudioCapturePermission, systemVersion)
    }
    
    /// 检查麦克风权限（macOS方式）
    private func checkMicrophonePermission() -> Bool {
        // 在macOS上，我们通过检查系统权限状态来验证麦克风权限
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    /// 请求麦克风权限
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            DispatchQueue.main.async {
                completion(true)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                completion(false)
            }
        @unknown default:
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
    
    // MARK: - 音频数据转换工具
    
    /// 转换32位浮点数据为16位整数数据
    static func convertFloat32ToInt16(bufferList: AudioBufferList, frameCount: UInt32, inputChannels: Int, outputChannels: Int) throws -> Data {
        guard bufferList.mNumberBuffers == 1 else {
            throw AudioDataConversionError.unsupportedBufferCount(bufferList.mNumberBuffers)
        }
        
        let buffer = bufferList.mBuffers
        guard let srcData = buffer.mData else {
            throw AudioDataConversionError.emptyInputData
        }
        
        let frameCountInt = Int(frameCount)
        let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        
        Logger.shared.info("🔄 数据转换: 输入声道=\(inputChannels), 输出声道=\(outputChannels), 帧数=\(frameCountInt)")
        
        // 创建输出数据缓冲区
        let outputBytesPerFrame = outputChannels * MemoryLayout<Int16>.size
        let outputDataSize = frameCountInt * outputBytesPerFrame
        var outputData = Data(count: outputDataSize)
        
        let srcFloatData = srcData.assumingMemoryBound(to: Float.self)
        
        outputData.withUnsafeMutableBytes { outputBytes in
            let dstInt16Data = outputBytes.bindMemory(to: Int16.self)
            
            if inputChannels == 1 && outputChannels == 2 {
                // 单声道转立体声
                for frame in 0..<frameCountInt {
                    if frame < totalSamples {
                        let monoValue = srcFloatData[frame]
                        let int16Value = Int16(max(-1.0, min(1.0, monoValue)) * 32767.0)
                        dstInt16Data[frame * 2] = int16Value      // 左声道
                        dstInt16Data[frame * 2 + 1] = int16Value  // 右声道
                    }
                }
                Logger.shared.debug("🔄 单声道转立体声完成")
            } else if inputChannels == outputChannels {
                // 声道数匹配：直接转换
                for frame in 0..<frameCountInt {
                    for channel in 0..<outputChannels {
                        let srcIndex = frame * inputChannels + channel
                        if srcIndex < totalSamples {
                            let floatValue = srcFloatData[srcIndex]
                            let int16Value = Int16(max(-1.0, min(1.0, floatValue)) * 32767.0)
                            dstInt16Data[frame * outputChannels + channel] = int16Value
                        }
                    }
                }
                Logger.shared.debug("🔄 直接转换完成")
            } else {
                // 其他情况：尝试交错格式解析
                let channelDataSize = min(totalSamples / inputChannels, frameCountInt)
                for frame in 0..<channelDataSize {
                    for channel in 0..<min(outputChannels, inputChannels) {
                        let srcIndex = frame * inputChannels + channel
                        if srcIndex < totalSamples {
                            let floatValue = srcFloatData[srcIndex]
                            let int16Value = Int16(max(-1.0, min(1.0, floatValue)) * 32767.0)
                            dstInt16Data[frame * outputChannels + channel] = int16Value
                        }
                    }
                }
                Logger.shared.debug("🔄 交错格式解析完成")
            }
        }
        
        return outputData
    }
    
    /// 复制音频数据到PCM缓冲区（支持多种格式）
    static func copyAudioDataToPCMBuffer(
        from bufferList: AudioBufferList,
        to pcmBuffer: AVAudioPCMBuffer,
        frameCount: UInt32,
        inputChannels: Int,
        outputChannels: Int
    ) -> Bool {
        guard bufferList.mNumberBuffers == 1 else {
            Logger.shared.warning("⚠️ 不支持多缓冲区格式")
            return false
        }
        
        let buffer = bufferList.mBuffers
        guard let srcData = buffer.mData, buffer.mDataByteSize > 0 else {
            Logger.shared.warning("⚠️ 输入数据为空")
            return false
        }
        
        let frameCountInt = Int(frameCount)
        let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        
        Logger.shared.debug("🔄 PCM缓冲区数据复制: 输入声道=\(inputChannels), 输出声道=\(outputChannels), 帧数=\(frameCountInt)")
        
        if let dstChannelData = pcmBuffer.floatChannelData {
            // 输出格式是32位浮点
            let srcFloatData = srcData.assumingMemoryBound(to: Float.self)
            
            if inputChannels == 1 && outputChannels == 2 {
                // 单声道转立体声
                for frame in 0..<frameCountInt {
                    if frame < totalSamples {
                        let monoValue = srcFloatData[frame]
                        dstChannelData[0][frame] = monoValue  // 左声道
                        dstChannelData[1][frame] = monoValue  // 右声道
                    }
                }
                Logger.shared.debug("🔄 单声道转立体声完成")
            } else if inputChannels == outputChannels {
                // 声道数匹配：直接复制
                for frame in 0..<frameCountInt {
                    for channel in 0..<outputChannels {
                        let srcIndex = frame * inputChannels + channel
                        if srcIndex < totalSamples {
                            dstChannelData[channel][frame] = srcFloatData[srcIndex]
                        }
                    }
                }
                Logger.shared.debug("🔄 直接复制完成")
            } else {
                // 其他情况：尝试交错格式解析
                let channelDataSize = min(totalSamples / inputChannels, frameCountInt)
                for frame in 0..<channelDataSize {
                    for channel in 0..<min(outputChannels, inputChannels) {
                        let srcIndex = frame * inputChannels + channel
                        if srcIndex < totalSamples {
                            dstChannelData[channel][frame] = srcFloatData[srcIndex]
                        }
                    }
                }
                Logger.shared.debug("🔄 交错格式解析完成")
            }
            
            pcmBuffer.frameLength = UInt32(frameCountInt)
            return true
            
        } else if let dstChannelData = pcmBuffer.int16ChannelData {
            // 输出格式是16位整数
            let srcFloatData = srcData.assumingMemoryBound(to: Float.self)
            
            if inputChannels == 1 && outputChannels == 2 {
                // 单声道转立体声
                for frame in 0..<frameCountInt {
                    if frame < totalSamples {
                        let monoValue = Int16(srcFloatData[frame] * 32767.0)
                        dstChannelData[0][frame] = monoValue  // 左声道
                        dstChannelData[1][frame] = monoValue  // 右声道
                    }
                }
                Logger.shared.debug("🔄 单声道转立体声完成")
            } else if inputChannels == outputChannels {
                // 声道数匹配：直接转换
                for frame in 0..<frameCountInt {
                    for channel in 0..<outputChannels {
                        let srcIndex = frame * inputChannels + channel
                        if srcIndex < totalSamples {
                            dstChannelData[channel][frame] = Int16(srcFloatData[srcIndex] * 32767.0)
                        }
                    }
                }
                Logger.shared.debug("🔄 直接转换完成")
            } else {
                // 其他情况：尝试交错格式解析
                let channelDataSize = min(totalSamples / inputChannels, frameCountInt)
                for frame in 0..<channelDataSize {
                    for channel in 0..<min(outputChannels, inputChannels) {
                        let srcIndex = frame * inputChannels + channel
                        if srcIndex < totalSamples {
                            dstChannelData[channel][frame] = Int16(srcFloatData[srcIndex] * 32767.0)
                        }
                    }
                }
                Logger.shared.debug("🔄 交错格式解析完成")
            }
            
            pcmBuffer.frameLength = UInt32(frameCountInt)
            return true
        }
        
        Logger.shared.warning("⚠️ 不支持的PCM缓冲区格式")
        return false
    }
    
    /// 计算音频电平（从AudioBufferList）
    static func calculateAudioLevel(from bufferList: AudioBufferList, frameCount: UInt32) -> (maxLevel: Float, rmsLevel: Float, normalizedLevel: Float) {
        let buffer = bufferList.mBuffers
        guard let data = buffer.mData, buffer.mDataByteSize > 0 else {
            return (0.0, 0.0, 0.0)
        }
        
        let samples = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        
        var maxLevel: Float = 0.0
        var sumSquares: Float = 0.0
        
        for i in 0..<sampleCount {
            let sample = abs(samples[i])
            if sample > maxLevel {
                maxLevel = sample
            }
            sumSquares += sample * sample
        }
        
        // 计算 RMS
        let rmsLevel = sampleCount > 0 ? sqrt(sumSquares / Float(sampleCount)) : 0.0
        
        // 转换为 dB
        let _ = maxLevel > 0 ? 20 * log10(maxLevel) : -96.0 // 暂时未使用，但保留以备将来使用
        let rmsDB = rmsLevel > 0 ? 20 * log10(rmsLevel) : -96.0
        let normalizedLevel = max(0, min(1, (rmsDB + 96) / 96))
        
        return (maxLevel, rmsLevel, normalizedLevel)
    }
}

/// 音频数据转换错误类型
enum AudioDataConversionError: Error, LocalizedError {
    case unsupportedBufferCount(UInt32)
    case emptyInputData
    case unsupportedFormat
    case conversionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedBufferCount(let count):
            return "不支持的缓冲区数量: \(count)"
        case .emptyInputData:
            return "输入数据为空"
        case .unsupportedFormat:
            return "不支持的音频格式"
        case .conversionFailed(let reason):
            return "数据转换失败: \(reason)"
        }
    }
}

/// 音频文件信息结构
struct AudioFileInfo {
    let url: URL
    let duration: Double
    let sampleRate: Double
    let channels: AVAudioChannelCount
    let format: AVAudioCommonFormat
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var formattedSampleRate: String {
        return String(format: "%.0f Hz", sampleRate)
    }
    
    var formattedChannels: String {
        return channels == 1 ? "单声道" : "立体声"
    }
}

// MARK: - Process Tap Constants
/// CoreAudio Process Tap 相关常量定义
extension AudioUtils {
    
    /// Process Tap 属性常量
    static let kAudioTapPropertyUID: AudioObjectPropertySelector = AudioObjectPropertySelector(0x74706175) // 'tpau' - Tap Property UID
    static let kAudioTapPropertyFormat: AudioObjectPropertySelector = AudioObjectPropertySelector(kAudioDevicePropertyStreamFormat) // 使用标准流格式属性
    static let kAudioTapPropertyIsActive: AudioObjectPropertySelector = AudioObjectPropertySelector(0x74617061) // 'tapa' - Tap Property IsActive
    
    /// Process Tap 相关错误代码
    static let kAudioTapErrorNotAvailable: OSStatus = OSStatus(0x7470616E) // 'tpan' - Tap Not Available
    
    /// Aggregate Device 相关常量
    static let kAudioAggregateDevicePropertyTapAutoStart: AudioObjectPropertySelector = AudioObjectPropertySelector(0x74617073) // 'taps' - Tap Auto Start
    static let kAudioTapErrorAlreadyExists: OSStatus = OSStatus(0x74706165) // 'tpae' - Tap Already Exists
}
