import Foundation
import AudioToolbox
import CoreAudio

/// 使用 AudioToolbox API 的音频文件管理器
/// 用于创建标准 WAV 文件，避免 AVAudioFile 的 FLLR 块问题
@available(macOS 14.4, *)
class AudioToolboxFileManager {
    
    // MARK: - Properties
    private let logger = Logger.shared
    private var audioFileID: AudioFileID?
    private var outputURL: URL?
    private var audioFormat: AudioStreamBasicDescription
    private var totalFramesWritten: UInt64 = 0
    
    // MARK: - Initialization
    
    init(audioFormat: AudioStreamBasicDescription) {
        self.audioFormat = audioFormat
        logger.info("🎵 AudioToolboxFileManager: 初始化，格式 - 采样率: \(audioFormat.mSampleRate), 声道数: \(audioFormat.mChannelsPerFrame), 位深: \(audioFormat.mBitsPerChannel)")
    }
    
    deinit {
        closeFile()
    }
    
    // MARK: - Public Methods
    
    /// 创建音频文件
    func createAudioFile(at url: URL) throws {
        logger.info("📁 AudioToolboxFileManager: 创建音频文件: \(url.path)")
        
        // 确保目录存在
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        
        // 删除已存在的文件
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            logger.info("🗑️ 删除已存在的文件")
        }
        
        // 创建标准 WAV 格式的 AudioStreamBasicDescription
        var wavFormat = createStandardWAVFormat(from: audioFormat)
        
        // 使用 AudioFileCreateWithURL 创建文件
        let status = AudioFileCreateWithURL(
            url as CFURL,
            kAudioFileWAVEType,  // WAV 文件类型
            &wavFormat,
            AudioFileFlags(rawValue: 0),  // 不使用特殊标志
            &audioFileID
        )
        
        guard status == noErr, let _ = audioFileID else {
            let error = NSError(domain: "AudioToolboxFileManager", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "创建音频文件失败: \(status)"
            ])
            logger.error("❌ AudioToolboxFileManager: 创建文件失败 - \(status)")
            throw error
        }
        
        self.outputURL = url
        logger.info("✅ AudioToolboxFileManager: 音频文件创建成功")
        logger.info("📊 文件格式: 采样率=\(wavFormat.mSampleRate), 声道数=\(wavFormat.mChannelsPerFrame), 位深=\(wavFormat.mBitsPerChannel)")
    }
    
    /// 写入音频数据
    func writeAudioData(_ bufferList: AudioBufferList, frameCount: UInt32) throws {
        guard let fileID = audioFileID else {
            logger.warning("⚠️ AudioToolboxFileManager: 文件未打开，跳过写入")
            return
        }
        
        guard frameCount > 0 else {
            logger.warning("⚠️ AudioToolboxFileManager: 帧数为0，跳过写入")
            return
        }
        
        // 检查是否需要格式转换
        let buffer = bufferList.mBuffers
        let isFloatFormat = (audioFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        
        let convertedData: Data
        if isFloatFormat {
            // 32-bit Float 格式，直接使用原始数据
            let dataSize = Int(buffer.mDataByteSize)
            convertedData = Data(bytes: buffer.mData!, count: dataSize)
        } else {
            // 非 Float 格式，需要转换
            let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let inputChannels = totalSamples / Int(frameCount)
            let outputChannels = Int(audioFormat.mChannelsPerFrame)
            
            convertedData = try AudioUtils.convertFloat32ToInt16(
                bufferList: bufferList,
                frameCount: frameCount,
                inputChannels: inputChannels,
                outputChannels: outputChannels
            )
        }
        
        // 准备写入数据
        var inNumPackets = frameCount
        let ioNumBytes = UInt32(convertedData.count)
        
        // 使用 AudioFileWritePackets 写入数据
        let status = convertedData.withUnsafeBytes { bytes in
            AudioFileWritePackets(
                fileID,
                false,  // 不使用缓存
                ioNumBytes,
                nil,    // 包描述符（PCM 不需要）
                Int64(totalFramesWritten),  // 起始包
                &inNumPackets,
                bytes.baseAddress!
            )
        }
        
        guard status == noErr else {
            logger.error("❌ AudioToolboxFileManager: 写入数据失败 - \(status)")
            throw NSError(domain: "AudioToolboxFileManager", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "写入音频数据失败: \(status)"
            ])
        }
        
        totalFramesWritten += UInt64(inNumPackets)
        
        // REQ-1.0-01: Log every ~1 minute at 48kHz (2880000 frames) for long recording stability
        if totalFramesWritten % 2_880_000 == 0 {
            let durationMinutes = Double(totalFramesWritten) / audioFormat.mSampleRate / 60.0
            logger.info("📝 AudioToolboxFileManager: 已写入 \(totalFramesWritten) 帧 (\(String(format: "%.1f", durationMinutes)) 分钟)")
        }
    }
    
    /// 关闭文件
    func closeFile() {
        if let fileID = audioFileID {
            AudioFileClose(fileID)
            audioFileID = nil
            logger.info("🔒 AudioToolboxFileManager: 文件已关闭，总共写入 \(totalFramesWritten) 帧")
        }
        outputURL = nil
        totalFramesWritten = 0
    }
    
    /// 获取文件信息
    func getFileInfo() -> (url: URL?, totalFrames: UInt64, duration: TimeInterval) {
        let duration = totalFramesWritten > 0 ? Double(totalFramesWritten) / audioFormat.mSampleRate : 0.0
        return (outputURL, totalFramesWritten, duration)
    }
    
    // MARK: - Private Methods
    
    
    /// 创建标准 WAV 格式
    private func createStandardWAVFormat(from inputFormat: AudioStreamBasicDescription) -> AudioStreamBasicDescription {
        var wavFormat = AudioStreamBasicDescription()
        
        // 基本格式信息
        wavFormat.mSampleRate = inputFormat.mSampleRate
        wavFormat.mChannelsPerFrame = inputFormat.mChannelsPerFrame
        wavFormat.mFormatID = kAudioFormatLinearPCM
        
        // 保持输入格式的位深和格式标志，确保格式一致性
        wavFormat.mBitsPerChannel = inputFormat.mBitsPerChannel
        wavFormat.mBytesPerFrame = inputFormat.mBytesPerFrame
        wavFormat.mFramesPerPacket = inputFormat.mFramesPerPacket
        wavFormat.mBytesPerPacket = inputFormat.mBytesPerPacket
        wavFormat.mFormatFlags = inputFormat.mFormatFlags
        
        logger.info("🎵 创建标准WAV格式:")
        logger.info("   采样率: \(wavFormat.mSampleRate)")
        logger.info("   声道数: \(wavFormat.mChannelsPerFrame)")
        logger.info("   位深: \(wavFormat.mBitsPerChannel)")
        logger.info("   格式标志: \(wavFormat.mFormatFlags)")
        logger.info("   每帧字节数: \(wavFormat.mBytesPerFrame)")
        
        return wavFormat
    }
}
