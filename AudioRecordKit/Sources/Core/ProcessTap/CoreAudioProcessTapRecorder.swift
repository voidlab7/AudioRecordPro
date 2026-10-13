import Foundation
import Darwin
import AVFoundation
import CoreAudio
import AudioToolbox
import CoreMedia

/// 基于 CoreAudio Process Tap 的系统音频录制器（macOS 14.4+）- 重构版本
@available(macOS 14.4, *)
final class CoreAudioProcessTapRecorder: BaseAudioRecorder {
    
    // MARK: - Properties
    /// 目标进程 PID；为 nil 时表示"系统混音"目标
    private var targetPID: pid_t?
    /// 多进程录制支持
    private var targetPIDs: [pid_t] = []
    
    // 组件管理器
    private let processEnumerator = AudioProcessEnumerator()
    private var processTapManager: ProcessTapManager?
    private var aggregateDeviceManager: AggregateDeviceManager?
    private var swiftProcessTapManager: SwiftProcessTapManager?  // 新增Swift API管理器
    private let audioCallbackHandler = AudioCallbackHandler()
    private var audioToolboxFileManager: AudioToolboxFileManager?

    /// FIX-004: 静音保活——全局 Tap 依附输出设备时钟，系统静音时设备休眠无 IO（落盘 0 帧）
    @available(macOS 14.4, *)
    private let silentKeepAlive = SilentOutputKeepAlive()

    // MARK: FIX-007: 录音中动态麦克风注入（「同时录入麦克风」开关录音中切换即时生效）
    private let micStateLock = NSLock()
    private var micMixEnabled = false
    private var micEngine: AVAudioEngine?
    private var micRingBuffer: [Float] = []
    private var micMaxRingSize = 192000  // 48kHz×2ch×2s，启动麦克风时按实际采样率校正
    private var micWritePos = 0
    private var micReadPos = 0
    private var lastMicSample: Float = 0.0

    /// 录音中开/关麦克风注入（UI「同时录入麦克风」开关直通；幂等）
    func setMicMixEnabled(_ enabled: Bool) {
        micStateLock.lock()
        let changed = (micMixEnabled != enabled)
        micMixEnabled = enabled
        micStateLock.unlock()
        guard changed else { return }
        logger.info("🎤 [FIX007] 录音中麦克风注入开关: \(enabled ? "ON" : "OFF")")
        if enabled {
            startMicEngineIfNeeded()
        } else {
            stopMicEngineIfNeeded()
        }
    }

    /// IO 回调线程调用：取一帧 interleaved 立体声麦克风数据；未开启/数据不足时按 hold 补偿（仅开启时）
    private func takeMicSamples(frameCount: UInt32) -> [Float]? {
        micStateLock.lock()
        let enabled = micMixEnabled
        micStateLock.unlock()
        guard enabled else { return nil }

        let needed = Int(frameCount) * 2
        var out = [Float](repeating: 0, count: needed)
        micStateLock.lock()
        let available = (micWritePos - micReadPos + micMaxRingSize) % micMaxRingSize
        for i in 0..<needed {
            if i < available {
                out[i] = micRingBuffer[micReadPos]
                micReadPos = (micReadPos + 1) % micMaxRingSize
            } else {
                // FIX-006 同款欠载 hold：保持最后采样值，语音不被静音顶掉
                out[i] = i > 0 ? out[i - 1] : lastMicSample
            }
        }
        lastMicSample = out.last ?? lastMicSample
        micStateLock.unlock()
        // FIX-007 打点（一次性）：注入首帧——证明 mic 数据真的进了写入路径
        struct InjectFirstShot { static var done = false }
        if !InjectFirstShot.done {
            InjectFirstShot.done = true
            logger.info("🎤 [FIX007] 麦克风注入首帧: samples=\(out.count)")
        }
        return out
    }

    /// 懒启动麦克风采集引擎（input tap → 环形缓冲，与 MixedAudioRecorder 同构）
    private func startMicEngineIfNeeded() {
        micStateLock.lock()
        if micEngine != nil { micStateLock.unlock(); return }
        micStateLock.unlock()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            logger.error("🎤 [FIX007] 麦克风输入格式无效: \(inFormat)")
            return
        }
        micStateLock.lock()
        micMaxRingSize = Int(inFormat.sampleRate) * 2 * 2
        micRingBuffer = [Float](repeating: 0, count: micMaxRingSize)
        micWritePos = 0
        micReadPos = 0
        micStateLock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self = self, let chData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            guard frames > 0, channels > 0 else { return }
            // FIX-007 打点（一次性）：首帧实测峰值——证明麦克风引擎真的在收音
            struct MicFirstShot { static var done = false }
            if !MicFirstShot.done {
                MicFirstShot.done = true
                var peak: Float = 0
                for f in 0..<frames { let v = abs(chData[0][f]); if v > peak { peak = v } }
                self.logger.info("🎤 [FIX007] 麦克风首帧: frames=\(frames), peak=\(peak)")
            }
            self.micStateLock.lock()
            defer { self.micStateLock.unlock() }
            for f in 0..<frames {
                for ch in 0..<2 {
                    let sample = chData[min(ch, channels - 1)][f]
                    self.micRingBuffer[self.micWritePos] = sample
                    self.micWritePos = (self.micWritePos + 1) % self.micMaxRingSize
                }
            }
        }
        // 主混音器空 tap 驱动渲染循环（与 MicrophoneRecorder 同款），输出音量压到近零防啸叫
        engine.mainMixerNode.outputVolume = 0.01
        // FEAT-004: 绑定用户所选麦克风设备（未选择则跟随系统默认）
        // ⚠️ 必须在任何 installTap 之前：tap 安装会初始化 AU 图，此后 AUHAL 拒绝换设备（-10851）
        MicDeviceManager.shared.applyPreferredDevice(to: engine)
        let mainFmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: mainFmt) { _, _ in }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            logger.error("🎤 [FIX007] 麦克风引擎启动失败: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
            return
        }
        micStateLock.lock()
        micEngine = engine
        micStateLock.unlock()
        logger.info("🎤 [FIX007] 麦克风注入引擎已启动: \(inFormat.sampleRate)Hz × \(inFormat.channelCount)ch")
    }

    private func stopMicEngineIfNeeded() {
        micStateLock.lock()
        let engine = micEngine
        micEngine = nil
        micStateLock.unlock()
        guard let engine = engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        logger.info("🎤 [FIX007] 麦克风注入引擎已停止")
    }

    // REQ-1.0-01: Hot-plug device change listener
    private var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?
    private let deviceChangeQueue = DispatchQueue(label: "com.audiorecord.devicechange", qos: .utility)
    
    // MARK: - Initialization
    override init(mode: RecordingMode) {
        super.init(mode: mode)
    }
    
    /// 指定捕获目标进程 PID（可选）
    func setTargetPID(_ pid: pid_t?) {
        targetPID = pid  // 使用指定的进程PID进行录制
        if let pid = pid {
            targetPIDs = [pid]  // 更新多进程列表
            logger.info("🎯 设置目标进程PID: \(pid)")
        } else {
            targetPIDs = []  // 清空多进程列表，使用系统混音
            logger.info("🎯 未指定目标进程，将使用系统混音")
        }
    }
    
    /// 设置多进程录制（新增方法）
    func setTargetPIDs(_ pids: [pid_t]) {
        targetPIDs = pids
        if pids.count == 1 {
            targetPID = pids.first
        } else {
            targetPID = nil  // 多进程时清空单个PID
        }
        
        if pids.isEmpty {
            logger.info("🎯 设置多进程录制: 系统混音")
        } else {
            logger.info("🎯 设置多进程录制: \(pids.count) 个进程 - \(pids)")
        }
    }
    
    /// 获取目标应用名称
    private func getTargetAppName() -> String? {
        guard let pid = targetPID else { return nil }
        
        let processes = processEnumerator.getAvailableAudioProcesses()
        return processes.first(where: { $0.pid == pid })?.name
    }
    
    /// 使用Swift CoreAudio API进行录制（实验性）
    private func startRecordingWithSwiftAPI() -> Bool {
        logger.info("🚀 开始使用Swift CoreAudio API进行录制")
        
        // 步骤1: 创建Process Tap
        swiftProcessTapManager = SwiftProcessTapManager()
        guard let tapManager = swiftProcessTapManager else {
            logger.error("❌ 无法创建Swift Process Tap管理器")
            return false
        }
        
        // 解析目标进程对象ID
        let processObjectIDs = resolveProcessObjectIDsSync()
        logger.info("🎯 解析到的进程对象ID: \(processObjectIDs)")
        
        guard tapManager.createProcessTap(for: processObjectIDs) else {
            logger.error("❌ Swift API: Process Tap创建失败")
            return false
        }
        
        // 步骤2: 创建聚合设备并绑定Tap
        guard tapManager.createAggregateDeviceBindingTap() else {
            logger.error("❌ Swift API: 聚合设备创建失败")
            tapManager.stopAndDestroy()
            return false
        }
        
        // 步骤3: 设置音频文件
        guard setupAudioFileWithSwiftAPI(tapManager: tapManager) else {
            logger.error("❌ Swift API: 音频文件设置失败")
            tapManager.stopAndDestroy()
            return false
        }
        
        // 步骤4: 设置IO回调并启动
        let (callback, clientData) = audioCallbackHandler.createAudioCallback()
        
        guard tapManager.setupIOProcAndStart(callback: callback, clientData: clientData) else {
            logger.error("❌ Swift API: IO回调设置失败")
            tapManager.stopAndDestroy()
            return false
        }
        
        logger.info("✅ Swift API: 录制已成功启动")
        return true
    }
    
    /// 使用Swift API设置音频文件
    private func setupAudioFileWithSwiftAPI(tapManager: SwiftProcessTapManager) -> Bool {
        // 获取Tap的流格式
        let streamFormat = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        // 创建音频文件
        let fileURL = FileManagerUtils.shared.getTempRecordingFileURL(prefix: "\(recordingMode)_\(getTargetAppName() ?? "unknown")", format: "wav")
        
        audioToolboxFileManager = AudioToolboxFileManager(audioFormat: streamFormat)
        do {
            try audioToolboxFileManager?.createAudioFile(at: fileURL)
        } catch {
            logger.error("❌ AudioToolbox文件管理器初始化失败: \(error)")
            return false
        }
        
        // 设置回调处理器
        audioCallbackHandler.setChannelCount(Int(streamFormat.mChannelsPerFrame))
        audioCallbackHandler.setAudioToolboxFileManager(audioToolboxFileManager!)
        
        logger.info("✅ Swift API: 音频文件设置完成 - \(fileURL.lastPathComponent)")
        return true
    }

    // MARK: - Recording
    override func startRecording() {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            return
        }
        
        logger.info("🚀 开始CoreAudio Process Tap录制")
        
        logger.info("🎯 开始录制，使用C API")
        
        // 回退到原来的C API实现
        startCoreAudioRecordingWithTapFormat()
    }
    
    private func startCoreAudioRecordingWithTapFormat() {
        // REQ-1.0-01: 直接同步调用，避免不必要的线程跳转以减少启动延迟
        createAudioFileWithTapFormat(tapFormat: nil)
    }
    
    private func createAudioFileWithTapFormat(tapFormat: AudioStreamBasicDescription?) {
        logger.info("🎵 使用 AudioToolbox API 创建标准 WAV 文件")
        
        // 使用默认格式或提供的格式
        let audioFormat: AudioStreamBasicDescription
        if let tapFormat = tapFormat {
            // DR-02: Tap 返回的是 Float32 格式，但文件输出应为 16-bit PCM
            // 保留 Tap 的采样率和声道数，仅改变位深和格式标志
            audioFormat = AudioStreamBasicDescription(
                mSampleRate: tapFormat.mSampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4,                     // 2 channels × 2 bytes
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,                      // 2 channels × 2 bytes
                mChannelsPerFrame: tapFormat.mChannelsPerFrame,
                mBitsPerChannel: 16,                    // REQ-1.0-01: 16-bit PCM output
                mReserved: 0
            )
            logger.info("📊 使用Tap采样率 + 16-bit PCM输出: \(tapFormat.mSampleRate)Hz, 声道数=\(tapFormat.mChannelsPerFrame)")
        } else {
            // DR-01: 采样率跟随设备，不硬编码 48kHz
            // 硬编码会导致音频变调（设备44.1kHz但文件头写48kHz → 变快8.8%）
            let detectedSampleRate = AudioUtils.getCurrentAudioDeviceSampleRate()
            audioFormat = AudioStreamBasicDescription(
                mSampleRate: detectedSampleRate,        // ← 跟随设备实际采样率
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4,                     // 2 channels × 2 bytes
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,                      // 2 channels × 2 bytes
                mChannelsPerFrame: 2,
                mBitsPerChannel: 16,                    // REQ-1.0-01: 16-bit PCM output
                mReserved: 0
            )
            logger.info("📊 使用设备采样率 + 16-bit PCM输出: \(detectedSampleRate)Hz, 立体声")
        }
        
        // 获取应用名称
        let appName = getTargetAppName()
        
        // 生成文件名
        let defaultURL = fileManager.getTempRecordingFileURL(prefix: "\(recordingMode)_\(appName ?? "unknown")", format: "wav")
        let fileName = defaultURL.lastPathComponent
        
        do {
            // 创建 AudioToolbox 文件管理器
            let audioToolboxManager = AudioToolboxFileManager(audioFormat: audioFormat)
            try audioToolboxManager.createAudioFile(at: defaultURL)
            
            // 从音频格式中设置实际声道数到回调处理器
            audioCallbackHandler.setChannelCount(Int(audioFormat.mChannelsPerFrame))
            
            // 设置到回调处理器
            audioCallbackHandler.setAudioToolboxFileManager(audioToolboxManager)
            
            // 保存引用以便后续清理
            self.audioToolboxFileManager = audioToolboxManager
            self.outputURL = defaultURL
            
            onStatus?("文件创建成功: %@".localized(fileName))
            logger.info("✅ AudioToolbox 音频文件创建成功: \(fileName)")
            
            // 继续录制流程
            continueRecordingProcess()
            
        } catch {
            let errorMsg = "创建文件失败: \(error.localizedDescription)"
            onStatus?(errorMsg)
            logger.error("❌ \(errorMsg)")
        }
    }
    
    private func continueRecordingProcess() {
        
        // 设置音频文件到回调处理器
        if let audioFile = audioFile {
            audioCallbackHandler.setAudioFile(audioFile)
        }
        
        // 设置电平回调（RMS，用于电平表）
        audioCallbackHandler.setLevelCallback { [weak self] level in
            self?.callOnLevel(level)
        }
        
        // 设置峰值回调（PCM 峰值，用于波形绘制——与播放波形同源）
        audioCallbackHandler.setPeakLevelCallback { [weak self] peakLevel in
            Task { @MainActor in
                self?.onPeakLevel?(peakLevel)
            }
        }

        // FEAT-001 S1: 实时转写 PCM 旁路——源格式优先取 AudioToolbox 写盘 ASBD（WAV 路径无 AVAudioFile）
        if audioCallbackHandler.transcriptionFormat == nil {
            audioCallbackHandler.transcriptionFormat = audioToolboxFileManager.map { fm in
                let asbd = fm.streamBasicDescription
                return AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: asbd.mSampleRate,
                    channels: asbd.mChannelsPerFrame > 0 ? asbd.mChannelsPerFrame : 2,
                    interleaved: (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                )
            } ?? audioFile?.processingFormat
        }
        audioCallbackHandler.onPCMBuffer = { [weak self] buffer in
            self?.onAudioBuffer?(buffer)
        }

        // FIX-007: 录音中动态麦克风注入——provider 每帧被回调，micMixEnabled 关闭时返回 nil（零开销直通）。
        audioCallbackHandler.setMicMixProvider { [weak self] frameCount in
            self?.takeMicSamples(frameCount: frameCount)
        }

        // REQ-1.0-01: 直接在当前 MainActor 上下文启动，减少线程跳转延迟
        // startCoreAudioProcessTapCapture 内部的 CoreAudio 调用本身是同步的
        Task { @MainActor in
            let success = await self.startCoreAudioProcessTapCapture()
            let statusMessage = success ? "已通过 C API 开始录制" : "CoreAudio Process Tap 初始化失败"
            
            if success {
                self.levelMonitor.startMonitoring(source: .simulated)
                self.isRunning = true
                self.installDeviceChangeListener()  // REQ-1.0-01: Monitor device changes
                self.callOnRecordingStarted()  // BUG-1 修复：管线真正启动后才通知（勿用定时器假装）
                self.callOnStatus(statusMessage)
            } else {
                self.logger.error("❌ \(statusMessage)")
                self.callOnStatus(statusMessage)
            }
        }
    }
    
    override func stopRecording() {
        logger.info("🛑 停止CoreAudio Process Tap录制")
        
        // REQ-1.0-01: Remove device change listener
        removeDeviceChangeListener()
        
        // 停止 Swift API 录制（如果正在使用）
        if let swiftManager = swiftProcessTapManager {
            logger.info("🛑 停止Swift API录制")
            swiftManager.stopAndDestroy()
            swiftProcessTapManager = nil
        }
        
        // 停止 C API 录制（如果正在使用）
        stopCoreAudioProcessTapCapture()
        
        // 关闭 AudioToolbox 文件管理器
        audioToolboxFileManager?.closeFile()
        audioToolboxFileManager = nil
        
        super.stopRecording()
    }
    
    // MARK: - REQ-1.0-01: Hot-plug Device Support
    
    /// Install a listener for default output device changes
    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] (numberAddresses, addresses) in
            guard let self = self else { return }
            Task { @MainActor in
                self.logger.info("🔌 REQ-1.0-01: Audio output device changed during recording")
                self.logger.info("🔌 Process Tap + Aggregate Device architecture handles device switching automatically")
                self.callOnStatus("音频设备已切换，录制继续中".localized)
            }
        }
        
        self.deviceChangeListenerBlock = listenerBlock
        
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            deviceChangeQueue,
            listenerBlock
        )
        
        if status == noErr {
            logger.info("🔌 REQ-1.0-01: Device change listener installed")
        } else {
            logger.warning("⚠️ REQ-1.0-01: Failed to install device change listener: \(status)")
        }
    }
    
    /// Remove the device change listener
    private func removeDeviceChangeListener() {
        guard let listenerBlock = deviceChangeListenerBlock else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            deviceChangeQueue,
            listenerBlock
        )
        
        self.deviceChangeListenerBlock = nil
        logger.info("🔌 REQ-1.0-01: Device change listener removed")
    }
    
    // MARK: - Public Methods
    
    /// 获取所有可用的音频进程列表
    func getAvailableAudioProcesses() -> [AudioProcessInfo] {
        return processEnumerator.getAvailableAudioProcesses()
    }
    
    /// 查找QQ音乐进程并设置为录制目标
    func findAndSetQQMusicTarget() -> Bool {
        logger.info("🎵 开始查找QQ音乐进程...")
        let processes = processEnumerator.getAvailableAudioProcesses()
        
        // 查找QQ音乐相关进程
        let qqMusicProcesses = processes.filter { process in
            let name = process.name.lowercased()
            let bundleID = process.bundleID.lowercased()
            return name.contains("qqmusic") || 
                   name.contains("qq音乐") || 
                   bundleID.contains("qqmusic") ||
                   bundleID.contains("com.tencent.qqmusic")
        }
        
        if qqMusicProcesses.isEmpty {
            logger.warning("⚠️ 未找到QQ音乐进程，请确保QQ音乐正在运行")
            logger.info("📋 当前可用的音频进程:")
            for (index, process) in processes.enumerated() {
                logger.info("   [\(index)] \(process.name) (PID: \(process.pid), Bundle: \(process.bundleID))")
            }
            return false
        }
        
        // 选择第一个找到的QQ音乐进程
        let qqMusicProcess = qqMusicProcesses.first!
        logger.info("✅ 找到QQ音乐进程:")
        logger.info("   名称: \(qqMusicProcess.name)")
        logger.info("   PID: \(qqMusicProcess.pid)")
        logger.info("   Bundle ID: \(qqMusicProcess.bundleID)")
        logger.info("   进程对象ID: \(qqMusicProcess.processObjectID)")
        
        // 设置为目标进程
        setTargetPID(qqMusicProcess.pid)
        logger.info("🎯 已设置QQ音乐为目标录制进程")
        
        return true
    }
    
    /// 专门针对QQ音乐的录制测试
    func testQQMusicRecording() async -> Bool {
        logger.info("🎵 开始QQ音乐专用录制测试...")
        
        // 首先查找QQ音乐进程
        guard findAndSetQQMusicTarget() else {
            logger.error("❌ QQ音乐录制测试失败: 未找到QQ音乐进程")
            return false
        }
        
        // 执行完整的录制流程测试
        guard await testRecordingPipeline() else {
            logger.error("❌ QQ音乐录制测试失败: 录制流程测试失败")
            return false
        }
        
        logger.info("🎉 QQ音乐录制测试全部通过！")
        logger.info("💡 建议: 现在可以开始实际录制QQ音乐的音频输出")
        
        return true
    }
    
    /// 测试录制流程（不实际开始录制）
    func testRecordingPipeline() async -> Bool {
        logger.info("🧪 开始测试录制流程...")
        
        do {
            // 测试步骤1: 解析进程对象
            logger.info("🔍 测试步骤1: 解析目标进程对象...")
            let processObjectID = try await resolveProcessObjectID()
            logger.info("✅ 步骤1测试通过: 进程对象ID=\(processObjectID)")
            
            // 测试步骤2: 创建Process Tap
            logger.info("🔧 测试步骤2: 创建Process Tap...")
            let testTapManager = ProcessTapManager()
            guard testTapManager.createProcessTap(for: [processObjectID]) else {
                logger.error("❌ 步骤2测试失败: 无法创建Process Tap")
                return false
            }
            logger.info("✅ 步骤2测试通过: Tap创建成功, ID=\(testTapManager.tapObjectID)")
            
            // 测试步骤3: 读取Tap格式
            logger.info("📊 测试步骤3: 读取Tap流格式...")
            guard testTapManager.readTapStreamFormat() else {
                logger.error("❌ 步骤3测试失败: 无法读取Tap格式")
                testTapManager.destroyProcessTap()
                return false
            }
            logger.info("✅ 步骤3测试通过: Tap格式读取成功")
            
            // 测试步骤4: 创建聚合设备
            logger.info("🔗 测试步骤4: 创建聚合设备...")
            let testAggManager = AggregateDeviceManager()
            guard let tapUUID = testTapManager.uuid,
                  testAggManager.createAggregateDeviceBindingTap(tapUUID: tapUUID) else {
                logger.error("❌ 步骤4测试失败: 无法创建聚合设备")
                testTapManager.destroyProcessTap()
                return false
            }
            logger.info("✅ 步骤4测试通过: 聚合设备创建成功, ID=\(testAggManager.deviceID)")
            
            // 测试步骤5: 创建回调函数
            logger.info("🎧 测试步骤5: 创建音频回调...")
            let (_, _) = audioCallbackHandler.createAudioCallback()
            logger.info("✅ 步骤5测试通过: 音频回调创建成功")
            
            // 清理测试资源
            logger.info("🧹 清理测试资源...")
            testAggManager.stopAndDestroy()
            testTapManager.destroyProcessTap()
            
            logger.info("🎉 录制流程测试全部通过！")
            return true
            
        } catch {
            logger.error("❌ 录制流程测试失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    @available(macOS 14.4, *)
    private func startCoreAudioProcessTapCapture() async -> Bool {
        logger.info("🎵 CoreAudioProcessTapRecorder: >>> 开始初始化系统音频录制")
        logger.info("🎵 目标进程PID: \(targetPID?.description ?? "系统混音")")
        let tStart = Date()

        // FIX-004: 静音保活必须先于 Tap 创建——若输出设备在休眠，先唤醒它，
        // 避免 Tap 就绪后仍要等设备被其它声音唤醒的 +2.8s 死区（严重时整场无 IO）
        silentKeepAlive.start()

        do {
            // 步骤 1: 解析目标进程对象列表
            let t1 = Date()
            logger.info("🔍 步骤1: 开始解析目标进程对象列表...")
            let processObjectIDs = try await resolveProcessObjectIDs()
            logger.info("✅ 步骤1完成: 进程对象ID列表=\(processObjectIDs), 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t1)*1000))")
            
            // 步骤 2: 创建 Process Tap
            let t2 = Date()
            logger.info("🔧 步骤2: 开始创建Process Tap...")
            processTapManager = ProcessTapManager()
            guard let tapManager = processTapManager,
                  tapManager.createProcessTap(for: processObjectIDs) else {
                let errorMsg = "❌ 步骤2失败: 创建Process Tap失败（可能SDK未提供符号或进程不可录制）"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            logger.info("✅ 步骤2完成: Process Tap创建成功, Tap ID=\(tapManager.tapObjectID), 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t2)*1000))")

            // 步骤 3: 读取 Tap 流格式
            let t3 = Date()
            logger.info("📊 步骤3: 开始读取Tap流格式...")
            guard tapManager.readTapStreamFormat() else {
                let errorMsg = "❌ 步骤3失败: 读取Tap格式失败（kAudioTapPropertyFormat不可用）"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            if let format = tapManager.streamFormat {
                logger.info("✅ 步骤3完成: 音频格式 - 采样率=\(format.mSampleRate), 声道数=\(format.mChannelsPerFrame), 位深=\(format.mBitsPerChannel), 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t3)*1000))")
            } else {
                logger.info("✅ 步骤3完成: Tap流格式读取成功, 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t3)*1000))")
            }

            // 步骤 4: 创建聚合设备
            let t4 = Date()
            logger.info("🔗 步骤4: 开始创建聚合设备...")
            aggregateDeviceManager = AggregateDeviceManager()
            guard let aggManager = aggregateDeviceManager,
                  let tapUUID = tapManager.uuid else {
                let errorMsg = "❌ 步骤4失败: 无法获取Tap UUID"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            
            logger.info("🔗 绑定Tap UUID: \(tapUUID)")
            guard aggManager.createAggregateDeviceBindingTap(tapUUID: tapUUID) else {
                let errorMsg = "❌ 步骤4失败: 创建/绑定聚合设备失败（新键或API不可用）"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            logger.info("✅ 步骤4完成: 聚合设备创建成功, 设备ID=\(aggManager.deviceID), 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t4)*1000))")

            // 步骤 5: 设置 IO 回调并启动
            let t5 = Date()
            logger.info("🎧 步骤5: 开始设置IO回调并启动设备...")
            let (callback, clientData) = audioCallbackHandler.createAudioCallback()
            guard aggManager.setupIOProcAndStart(callback: callback, clientData: clientData) else {
                let errorMsg = "❌ 步骤5失败: 安装IO回调或启动失败"
                logger.error(errorMsg)
                callOnStatus(errorMsg)
                return false
            }
            logger.info("✅ 步骤5完成: IO回调已安装并启动, 用时 \(String(format: "%.2fms", Date().timeIntervalSince(t5)*1000))")
            
            let totalTime = String(format: "%.2fms", Date().timeIntervalSince(tStart)*1000)
            logger.info("🎉 CoreAudioProcessTapRecorder: <<< 初始化完成! 总用时: \(totalTime)")
            logger.info("🎵 系统音频录制已成功启动，开始监听音频数据流...")

            return true
            
        } catch {
            // FIX-004: 初始化失败也要撤掉保活，防止静音播放泄漏
            silentKeepAlive.stop()
            let errorMsg = "❌ CoreAudioProcessTapRecorder初始化失败: \(error.localizedDescription)"
            logger.error(errorMsg)
            callOnStatus(errorMsg)
            return false
        }
    }
    
    @available(macOS 14.4, *)
    private func stopCoreAudioProcessTapCapture() {
        logger.info("CoreAudioProcessTapRecorder: 开始停止与清理")

        // FIX-007: 撤除麦克风注入（引擎+provider），不留设备占用
        setMicMixEnabled(false)
        audioCallbackHandler.setMicMixProvider(nil)

        // FIX-004: 先停静音保活
        silentKeepAlive.stop()

        // 停止聚合设备
        aggregateDeviceManager?.stopAndDestroy()
        aggregateDeviceManager = nil
        
        // 销毁 Process Tap
        processTapManager?.destroyProcessTap()
        processTapManager = nil
        
        logger.info("CoreAudioProcessTapRecorder: 停止与清理完成")
    }
    
    @available(macOS 14.4, *)
    private func resolveProcessObjectIDsSync() -> [AudioObjectID] {
        if targetPIDs.isEmpty {
            // 系统混音录制，返回空数组
            return []
        }
        
        var objectIDs: [AudioObjectID] = []
        for pid in targetPIDs {
            if let objectID = processEnumerator.findProcessObjectID(by: pid) {
                objectIDs.append(objectID)
            }
        }
        return objectIDs
    }
    
    @available(macOS 14.4, *)
    private func resolveProcessObjectIDs() async throws -> [AudioObjectID] {
        var processObjectIDs: [AudioObjectID] = []
        
        if !targetPIDs.isEmpty {
            // 使用指定的多个PID — 始终关联查找（Chrome 等多进程应用主进程不产生音频）
            logger.info("🎯 使用指定的目标PID列表: \(targetPIDs)")
            for pid in targetPIDs {
                let related = processEnumerator.findAllRelatedProcessObjectIDs(by: pid)
                if !related.isEmpty {
                    processObjectIDs.append(contentsOf: related)
                    logger.info("✅ PID=\(pid) 关联到 \(related.count) 个音频进程对象")
                } else {
                    logger.warning("⚠️ 未找到PID=\(pid)对应的任何进程对象，跳过")
                }
            }
            
            if processObjectIDs.isEmpty {
                throw NSError(domain: "CoreAudioProcessTapRecorder", code: -2, userInfo: [NSLocalizedDescriptionKey: "所有指定的PID都无法找到对应的进程对象".localized])
            }
        } else {
            // 未指定PID，使用系统混音
            logger.info("🔍 未指定PID，使用系统混音录制...")
            if let systemPid = processEnumerator.resolveDefaultSystemMixPID() {
                logger.info("✅ 找到系统混音PID: \(systemPid)")
                if let processObjectID = processEnumerator.findProcessObjectID(by: systemPid) {
                    processObjectIDs.append(processObjectID)
                }
            } else {
                logger.info("⚠️ 未找到系统混音，返回空列表使用系统混音")
                // 返回空列表，表示系统混音
            }
        }
        
        return processObjectIDs
    }
    
    @available(macOS 14.4, *)
    private func resolveProcessObjectID() async throws -> AudioObjectID {
        // 兼容性方法，返回第一个进程对象ID
        let processObjectIDs = try await resolveProcessObjectIDs()
        if let firstObjectID = processObjectIDs.first {
            return firstObjectID
        } else {
            // 系统混音情况，返回系统对象ID
            return AudioObjectID(kAudioObjectSystemObject)
        }
    }
    
    // MARK: - Static Audio Callback
    
    /// 静态音频回调函数（C 函数指针）
    static let audioCallback: AudioDeviceIOProc = { (inDevice, inNow, inInputData, inInputTime, inOutputData, inOutputTime, inClientData) -> OSStatus in
        // 这里需要实现音频数据处理逻辑
        // 暂时返回成功状态
        return noErr
    }
}

