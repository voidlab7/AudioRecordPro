import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

// MARK: - 全局 C 函数指针
/// 全局音频回调函数（C 函数指针）
@available(macOS 14.4, *)
func globalAudioCallback(
    inDevice: AudioDeviceID,
    inNow: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    inInputTime: UnsafePointer<AudioTimeStamp>,
    inOutputData: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime: UnsafePointer<AudioTimeStamp>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    // 通过 inClientData 获取 AudioCallbackHandler 实例
    guard let clientData = inClientData else {
        return noErr
    }
    
    let handler = Unmanaged<AudioCallbackHandler>.fromOpaque(clientData).takeUnretainedValue()
    
    // 处理音频数据
    let bufferList = inInputData.pointee
    let buffer = bufferList.mBuffers
    
    // REQ-1.0-01: Optimized callback counter for long recording stability (4h+)
    // Using modular counter to prevent unbounded growth
    struct CallCounter {
        static var count: UInt64 = 0
        static var lastNonZeroDataSize = UInt32(0)
        static var nonZeroCount: UInt64 = 0
    }
    CallCounter.count &+= 1  // Wrapping addition for safety
    
    // Log first 3 callbacks for debugging, then every 10000 (~2 min at 48kHz)
    let shouldLog = CallCounter.count <= 3 || CallCounter.count % 10000 == 0
    
    if shouldLog {
        handler.logger.info("🎧 音频回调[\(CallCounter.count)]: device=\(inDevice), dataSize=\(buffer.mDataByteSize), 有效数据次数=\(CallCounter.nonZeroCount)")
    }
    
    // Track non-zero data
    if buffer.mDataByteSize > 0 {
        CallCounter.lastNonZeroDataSize = buffer.mDataByteSize
        CallCounter.nonZeroCount &+= 1
    }
    
    // Warn if no valid data received after 1000 callbacks (only once)
    if CallCounter.count == 1000 && CallCounter.nonZeroCount == 0 {
        handler.logger.warning("⚠️ 警告: 已调用1000次音频回调，但从未收到有效数据！")
        handler.logger.warning("💡 建议: 检查Process Tap配置或目标应用是否真的在播放音频")
    }
    
    // 计算实际的帧数：使用正确的帧数计算
    // 对于32位浮点格式，每帧4字节，但需要考虑声道数
    let bytesPerSample = 4 // 32位浮点 = 4字节
    // 注意：bufferList.mNumberBuffers 是缓冲区数量，不是声道数
    // 对于交错格式，通常只有一个缓冲区包含所有声道数据
    let totalSamples = Int(buffer.mDataByteSize) / bytesPerSample
    // 从 handler 获取实际音频格式的声道数
    let channels = handler.channelCount
    let frameCount = UInt32(totalSamples / channels)
    
    // 计算电平
    handler.calculateAndReportLevel(from: bufferList, frameCount: frameCount)
    
    // 写入音频数据
    handler.writeAudioData(from: bufferList, frameCount: frameCount)
    
    return noErr
}

// MARK: - AudioCallbackHandler
/// 音频回调处理器 - 负责处理音频数据流和文件写入
@available(macOS 14.4, *)
class AudioCallbackHandler {
    
    // MARK: - Properties
    let logger = Logger.shared
    private var audioFile: AVAudioFile?
    private var audioToolboxFileManager: AudioToolboxFileManager?
    private var onLevel: ((Float) -> Void)?
    private var onPeakLevel: ((Float) -> Void)?
    
    /// 音频格式的声道数（从实际音频格式中获取）
    private(set) var channelCount: Int = 2
    
    // 自定义回调（用于混音录制）
    private var customCallback: ((UnsafePointer<AudioBufferList>, UInt32) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    /// 设置声道数（应在录制开始时从 ASBD 格式中获取并设置）
    func setChannelCount(_ count: Int) {
        self.channelCount = max(1, count)
        logger.info("🎵 AudioCallbackHandler: 声道数设置为 \(self.channelCount)")
    }
    
    // MARK: - Public Methods
    
    /// 设置音频文件
    func setAudioFile(_ file: AVAudioFile) {
        self.audioFile = file
    }
    
    /// 设置 AudioToolbox 文件管理器
    func setAudioToolboxFileManager(_ manager: AudioToolboxFileManager) {
        self.audioToolboxFileManager = manager
        logger.info("🎵 AudioCallbackHandler: 设置 AudioToolbox 文件管理器")
    }
    
    /// 设置电平回调（RMS，用于电平表）
    func setLevelCallback(_ callback: @escaping (Float) -> Void) {
        self.onLevel = callback
    }
    
    /// 设置峰值回调（PCM 峰值，用于波形绘制——与播放波形同源）
    func setPeakLevelCallback(_ callback: @escaping (Float) -> Void) {
        self.onPeakLevel = callback
    }
    
    /// 设置自定义回调（用于混音录制）
    func setCustomCallback(_ callback: @escaping (UnsafePointer<AudioBufferList>, UInt32) -> Void) {
        self.customCallback = callback
        logger.info("🎵 AudioCallbackHandler: 设置自定义回调（混音模式）")
    }
    
    /// 创建音频回调函数
    func createAudioCallback() -> (AudioDeviceIOProc, UnsafeMutableRawPointer) {
        logger.info("🎧 AudioCallbackHandler: 创建音频回调函数...")
        // 创建 self 的不安全指针，用于传递给 C 回调函数
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        logger.info("✅ 音频回调函数创建成功，客户端数据指针: \(selfPointer)")
        return (globalAudioCallback, selfPointer)
    }
    
    /// 创建 PCM 缓冲区
    func makePCMBuffer(from bufferList: UnsafePointer<AudioBufferList>, frames: UInt32, asbd: AudioStreamBasicDescription) -> AVAudioPCMBuffer? {
        guard let audioFile = audioFile else { return nil }
        
        let format = audioFile.processingFormat
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            return nil
        }
        
        pcm.frameLength = AVAudioFrameCount(frames)
        
        let abl = bufferList.pointee
        let channels = Int(asbd.mChannelsPerFrame)
        let _ = Int(asbd.mBytesPerFrame) // 暂时未使用，但保留以备将来使用
        
        guard let src = abl.mBuffers.mData else { return nil }
        
        if let dst = pcm.floatChannelData {
            let totalFrames = Int(frames)
            for c in 0..<channels {
                var s = src.assumingMemoryBound(to: Float.self).advanced(by: c)
                let d = dst[c]
                for i in 0..<totalFrames {
                    d[i] = s.pointee
                    s = s.advanced(by: channels)
                }
            }
        } else if let dst = pcm.int16ChannelData {
            // 将32位浮点数据转换为16位整数数据
            let totalFrames = Int(frames)
            for c in 0..<channels {
                var s = src.assumingMemoryBound(to: Float.self).advanced(by: c)
                let d = dst[c]
                for i in 0..<totalFrames {
                    // 将浮点数转换为16位整数：-1.0 到 1.0 映射到 -32768 到 32767
                    let floatValue = s.pointee
                    let int16Value = Int16(max(-1.0, min(1.0, floatValue)) * 32767.0)
                    d[i] = int16Value
                    s = s.advanced(by: channels)
                }
            }
        } else if let dst = pcm.int32ChannelData {
            let totalFrames = Int(frames)
            for c in 0..<channels {
                var s = src.assumingMemoryBound(to: Int32.self).advanced(by: c)
                let d = dst[c]
                for i in 0..<totalFrames {
                    d[i] = s.pointee
                    s = s.advanced(by: channels)
                }
            }
        }
        
        return pcm
    }
    
    // MARK: - Private Methods
    
    func calculateAndReportLevel(from bufferList: AudioBufferList, frameCount: UInt32) {
        let hasLevelCb = onLevel != nil
        let hasPeakCb = onPeakLevel != nil
        guard hasLevelCb || hasPeakCb else { return }
        
        // 使用统一的工具类计算电平（同时拿到 maxLevel 和 normalizedLevel）
        let (maxLevel, _, normalizedLevel) = AudioUtils.calculateAudioLevel(from: bufferList, frameCount: frameCount)
        
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(normalizedLevel)
            // 峰值回调：直接传 PCM 峰值（0~1），与 extractWaveformSamples 一致
            self?.onPeakLevel?(maxLevel)
        }
    }
    
     func writeAudioData(from bufferList: AudioBufferList, frameCount: UInt32) {
        guard frameCount > 0 else { return }
        
        // 如果设置了自定义回调（混音模式），则调用自定义回调
        if let customCallback = customCallback {
            withUnsafePointer(to: bufferList) { bufferListPointer in
                customCallback(bufferListPointer, frameCount)
            }
            return
        }
        
        // 优先使用 AudioToolbox 文件管理器
        if let audioToolboxManager = audioToolboxFileManager {
            do {
                try audioToolboxManager.writeAudioData(bufferList, frameCount: frameCount)
                // 成功写入，不再输出每次的日志（减少冗余）
                return
            } catch {
                logger.error("AudioCallbackHandler: AudioToolbox 写入失败: \(error.localizedDescription)")
                // 如果 AudioToolbox 失败，回退到 AVAudioFile
            }
        }
        
        // 回退到 AVAudioFile（保持向后兼容）
        guard let audioFile = audioFile else { return }
        
        logger.debug("AudioCallbackHandler: 使用 AVAudioFile 准备写入 \(frameCount) 帧音频数据")
        
        // 创建PCM缓冲区，确保大小足够
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
            logger.error("AudioCallbackHandler: 无法创建PCM缓冲区")
            return
        }
        
        // 调试：检查格式匹配
        logger.debug("AudioCallbackHandler: PCM缓冲区格式 - 声道数: \(audioFile.processingFormat.channelCount), 采样率: \(audioFile.processingFormat.sampleRate), 交错: \(audioFile.processingFormat.isInterleaved)")
        
        // 处理交错和非交错格式
        if bufferList.mNumberBuffers == 1 {
            // 交错格式：所有声道数据在一个buffer中
            let buffer = bufferList.mBuffers
            logger.debug("AudioCallbackHandler: 检查buffer数据 - mData: \(buffer.mData != nil), mDataByteSize: \(buffer.mDataByteSize)")
            guard buffer.mData != nil && buffer.mDataByteSize > 0 else { 
                logger.warning("AudioCallbackHandler: buffer数据无效，跳过写入")
                return 
            }
            
            // 计算输入数据的实际声道数
            let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let inputChannels = totalSamples / Int(frameCount)
            let outputChannels = Int(audioFile.processingFormat.channelCount)
            
            logger.debug("AudioCallbackHandler: 数据解析 - 总样本: \(totalSamples), 帧数: \(frameCount), 输入声道: \(inputChannels), 输出声道: \(outputChannels)")
            
            // 使用统一的工具类复制数据到PCM缓冲区
            let success = AudioUtils.copyAudioDataToPCMBuffer(
                from: bufferList,
                to: pcmBuffer,
                frameCount: frameCount,
                inputChannels: inputChannels,
                outputChannels: outputChannels
            )
            
            if !success {
                logger.warning("AudioCallbackHandler: 数据复制失败，跳过写入")
                return
            }
        } else {
            // 非交错格式：每个声道有独立的buffer
            logger.debug("AudioCallbackHandler: 处理非交错格式，buffer数量: \(bufferList.mNumberBuffers)")
            
            // 暂时跳过非交错格式的处理，记录警告
            logger.warning("AudioCallbackHandler: 非交错格式暂不支持，跳过数据写入")
            return
        }
        
        do {
            // 确保frameLength正确设置
            if pcmBuffer.frameLength == 0 {
                logger.warning("AudioCallbackHandler: PCM缓冲区帧数为0，跳过写入")
                return
            }
            
            // 调试：检查写入前的状态
            logger.debug("AudioCallbackHandler: 写入前检查 - frameLength: \(pcmBuffer.frameLength), frameCapacity: \(pcmBuffer.frameCapacity)")
            
            try audioFile.write(from: pcmBuffer)
            logger.debug("AudioCallbackHandler: 使用 AVAudioFile 成功写入 \(pcmBuffer.frameLength) 帧音频数据")
        } catch {
            logger.error("AudioCallbackHandler: AVAudioFile 写入失败: \(error.localizedDescription)")
        }
    }
}