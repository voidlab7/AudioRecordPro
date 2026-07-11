import Foundation

// （移除内嵌 MicrophoneRecorder，统一使用独立文件 MicrophoneRecorder.swift）

// MARK: - Factory Controller

/// 音频源类型
enum AudioSourceType: String {
    case microphone = "microphone"
    case systemAudio = "system"
    case specificProcess = "process"
}

/// 单个进程的录制状态信息
struct ProcessRecordingInfo {
    let pid: pid_t
    let processName: String
    var level: Float = 0
    var peakLevel: Float = 0
    var isRunning: Bool = false
    var outputURL: URL?
}

/// 重构后的音频录制控制器（支持多音源同时录制）
@MainActor
class AudioRecorderController: NSObject {
    
    // MARK: - Properties
    private var activeRecorders: [AudioSourceType: AudioRecorderProtocol] = [:]
    private var _currentFormat: AudioFormat = .m4a
    private var _coreAudioTargetPID: pid_t?  // 保存CoreAudio目标PID
    private let logger = Logger.shared
    
    // MARK: - Multi-Process Independent Recording
    /// Per-process independent recorders (keyed by PID)
    private var processRecorders: [pid_t: AudioRecorderProtocol] = [:]
    /// Per-process recording info (keyed by PID)
    private(set) var processRecordingInfos: [pid_t: ProcessRecordingInfo] = [:]
    /// Whether currently in multi-process independent recording mode
    private(set) var isMultiProcessMode: Bool = false
    
    // 混音设置（预留，暂未实现）
    var shouldMixAudio: Bool = false
    
    // 多录制完成回调
    var onRecordingsComplete: (([AudioRecording]) -> Void)?
    
    // MARK: - Public Interface
    var isRunning: Bool {
        if isMultiProcessMode {
            return !processRecorders.isEmpty && processRecorders.values.contains(where: { $0.isRunning })
        }
        return !activeRecorders.isEmpty && activeRecorders.values.contains(where: { $0.isRunning })
    }
    
    var onLevel: ((Float) -> Void)? {
        didSet {
            activeRecorders.values.forEach { $0.onLevel = onLevel }
        }
    }
    
    var onPeakLevel: ((Float) -> Void)? {
        didSet {
            activeRecorders.values.forEach { $0.onPeakLevel = onPeakLevel }
        }
    }
    
    /// Per-process level callback: (pid, rmsLevel)
    var onProcessLevel: ((pid_t, Float) -> Void)?
    
    /// Per-process peak level callback: (pid, peakLevel)
    var onProcessPeakLevel: ((pid_t, Float) -> Void)?
    
    /// Per-process recording complete callback: (pid, recording)
    var onProcessRecordingComplete: ((pid_t, AudioRecording) -> Void)?
    
    /// All process recordings complete callback
    var onAllProcessRecordingsComplete: (([pid_t: AudioRecording]) -> Void)?
    
    var onStatus: ((String) -> Void)? {
        didSet {
            activeRecorders.values.forEach { $0.onStatus = onStatus }
        }
    }
    
    // 保持向后兼容
    var onRecordingComplete: ((AudioRecording) -> Void)?
    
    var onPlaybackComplete: (() -> Void)? {
        didSet {
            activeRecorders.values.forEach { $0.onPlaybackComplete = onPlaybackComplete }
        }
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// 设置音频格式
    func setAudioFormat(_ format: AudioFormat) {
        _currentFormat = format
        activeRecorders.values.forEach { $0.setAudioFormat(format) }
        processRecorders.values.forEach { $0.setAudioFormat(format) }
        logger.info("音频格式已设置为: \(format.rawValue)")
    }
    
    // MARK: - Multi-Process Independent Recording
    
    /// 启动多进程独立录制（每个进程独立音轨 + 独立电平）
    /// - Parameters:
    ///   - pids: 要录制的进程 PID 列表
    ///   - processNames: PID 对应的进程名称字典
    ///   - mixAudio: 是否同时混入麦克风（每个进程轨道都混入）
    func startMultiProcessIndependentRecording(
        pids: [pid_t],
        processNames: [pid_t: String],
        mixAudio: Bool = false
    ) {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            onStatus?("录制已在进行中")
            return
        }
        
        guard !pids.isEmpty else {
            logger.warning("没有指定要录制的进程")
            onStatus?("请选择至少一个应用")
            return
        }
        
        guard #available(macOS 14.4, *) else {
            logger.warning("多进程独立录制需要 macOS 14.4+")
            onStatus?("多进程独立录制需要 macOS 14.4+")
            return
        }
        
        isMultiProcessMode = true
        logger.info("🎯 启动多进程独立录制模式，进程数: \(pids.count)")
        
        // Clear previous state
        processRecorders.removeAll()
        processRecordingInfos.removeAll()
        var completedRecordings: [pid_t: AudioRecording] = [:]
        
        // Create independent recorder for each process
        for pid in pids {
            let processName = processNames[pid] ?? "Process-\(pid)"
            
            if mixAudio {
                // Mixed mode: each process + microphone
                let recorder = MixedAudioRecorder(mode: .specificProcess)
                recorder.setTargetPID(pid)
                recorder.setAudioFormat(_currentFormat)
                setupProcessRecorderCallbacks(recorder, pid: pid, processName: processName, completedRecordings: &completedRecordings)
                processRecorders[pid] = recorder
            } else {
                // Pure process audio capture
                let recorder = CoreAudioProcessTapRecorder(mode: .specificProcess)
                recorder.setTargetPID(pid)
                recorder.setAudioFormat(_currentFormat)
                setupProcessRecorderCallbacks(recorder, pid: pid, processName: processName, completedRecordings: &completedRecordings)
                processRecorders[pid] = recorder
            }
            
            // Initialize recording info
            processRecordingInfos[pid] = ProcessRecordingInfo(
                pid: pid,
                processName: processName,
                isRunning: true
            )
            
            logger.info("✅ 创建进程录制器: \(processName) (PID: \(pid))")
        }
        
        // Start all recorders
        for (pid, recorder) in processRecorders {
            let name = processNames[pid] ?? "Process-\(pid)"
            logger.info("🎬 启动录制器: \(name) (PID: \(pid))")
            recorder.startRecording()
        }
        
        let names = pids.compactMap { processNames[$0] }.joined(separator: ", ")
        onStatus?("正在独立录制 \(pids.count) 个应用: \(names)")
    }
    
    /// 获取指定进程的当前电平
    func getProcessLevel(for pid: pid_t) -> Float {
        return processRecordingInfos[pid]?.level ?? 0
    }
    
    /// 获取指定进程的当前峰值电平
    func getProcessPeakLevel(for pid: pid_t) -> Float {
        return processRecordingInfos[pid]?.peakLevel ?? 0
    }
    
    /// 获取所有进程的电平字典
    func getAllProcessLevels() -> [pid_t: Float] {
        var levels: [pid_t: Float] = [:]
        for (pid, info) in processRecordingInfos {
            levels[pid] = info.level
        }
        return levels
    }
    
    // MARK: - Legacy Multi-Source Recording
    
    /// 启动多个音源的录制
    /// - Parameters:
    ///   - wantMic: 是否录制麦克风
    ///   - wantSystem: 是否录制系统音频
    ///   - wantProcess: 是否录制特定进程
    ///   - targetPID: 特定进程的PID
    ///   - mixAudio: 是否混音录制（系统音频+麦克风混合到一个文件）
    func startMultiSourceRecording(
        wantMic: Bool,
        wantSystem: Bool,
        wantProcess: Bool,
        targetPID: pid_t? = nil,
        mixAudio: Bool = false
    ) {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            onStatus?("录制已在进行中")
            return
        }
        
        // 如果启用麦克风叠加，将麦克风混入当前录制目标
        if mixAudio && (wantSystem || wantProcess) {
            logger.info("启动麦克风叠加录制模式")
            startMixedRecording(wantSystem: wantSystem, wantProcess: wantProcess, targetPID: targetPID)
            return
        }
        
        isMultiProcessMode = false
        logger.info("开始多音源录制 - 麦克风:\(wantMic), 系统:\(wantSystem), 进程:\(wantProcess)")
        
        // 创建需要的录制器
        var newRecorders: [AudioSourceType: AudioRecorderProtocol] = [:]
        
        // 1. 麦克风录制器
        if wantMic {
            logger.info("创建麦克风录制器")
            let micRecorder = MicrophoneRecorder(mode: .microphone)
            micRecorder.setAudioFormat(_currentFormat)
            setupRecorderCallbacks(micRecorder, sourceType: .microphone)
            newRecorders[.microphone] = micRecorder
        }
        
        // 2. 系统音频录制器（需要 macOS 14.4+）
        if wantSystem {
            if #available(macOS 14.4, *) {
                logger.info("创建系统音频录制器")
                let systemRecorder = CoreAudioProcessTapRecorder(mode: .systemMixdown)
                systemRecorder.setTargetPID(nil)
                systemRecorder.setAudioFormat(_currentFormat)
                setupRecorderCallbacks(systemRecorder, sourceType: .systemAudio)
                newRecorders[.systemAudio] = systemRecorder
            } else {
                logger.warning("系统音频录制需要 macOS 14.4+")
                onStatus?("系统音频录制需要 macOS 14.4+，请升级系统")
            }
        }
        
        // 3. 特定进程录制器
        if wantProcess, let pid = targetPID {
            if #available(macOS 14.4, *) {
                logger.info("创建特定进程录制器，PID: \(pid)")
                let processRecorder = CoreAudioProcessTapRecorder(mode: .specificProcess)
                processRecorder.setTargetPID(pid)
                processRecorder.setAudioFormat(_currentFormat)
                setupRecorderCallbacks(processRecorder, sourceType: .specificProcess)
                newRecorders[.specificProcess] = processRecorder
            } else {
                logger.warning("特定进程录制需要 macOS 14.4+")
                onStatus?("特定进程录制需要 macOS 14.4+")
            }
        }
        
        // 检查是否有录制器
        guard !newRecorders.isEmpty else {
            logger.warning("没有可用的录制器")
            onStatus?("请选择至少一个音频源")
            return
        }
        
        activeRecorders = newRecorders
        
        // 启动所有录制器
        for (type, recorder) in activeRecorders {
            logger.info("启动录制器: \(type.rawValue)")
            recorder.startRecording()
        }
        
        let sources = activeRecorders.keys.map { $0.rawValue }.joined(separator: ", ")
        onStatus?("正在录制: \(sources)")
    }
    
    /// 停止所有录制
    func stopRecording() {
        if isMultiProcessMode {
            logger.info("停止多进程独立录制，当前活跃录制器数: \(processRecorders.count)")
            for (pid, recorder) in processRecorders {
                let name = processRecordingInfos[pid]?.processName ?? "PID-\(pid)"
                logger.info("停止录制器: \(name) (PID: \(pid))")
                recorder.stopRecording()
            }
        } else {
            logger.info("停止所有录制，当前活跃录制器数: \(activeRecorders.count)")
            for (type, recorder) in activeRecorders {
                logger.info("停止录制器: \(type.rawValue)")
                recorder.stopRecording()
            }
        }
    }
    
    /// 播放录音（使用第一个录制器）
    func playRecording(at url: URL) {
        activeRecorders.values.first?.playRecording(at: url)
    }
    
    /// 停止播放
    func stopPlayback() {
        activeRecorders.values.forEach { $0.stopPlayback() }
    }
    
    /// 设置CoreAudio目标PID
    func setCoreAudioTargetPID(_ pid: pid_t?) {
        _coreAudioTargetPID = pid
        logger.info("CoreAudio 目标 PID 已保存为: \(pid.map { String($0) } ?? "nil")")
        
        if #available(macOS 14.4, *) {
            if let core = activeRecorders[.specificProcess] as? CoreAudioProcessTapRecorder {
                core.setTargetPID(pid)
                logger.info("CoreAudio 目标 PID 已应用到特定进程录制器: \(pid.map { String($0) } ?? "nil")")
            }
        }
    }
    
    /// 设置多进程录制
    func setCoreAudioTargetPIDs(_ pids: [pid_t]) {
        logger.info("CoreAudio 目标 PID 列表已设置为: \(pids)")
        
        if #available(macOS 14.4, *) {
            if let core = activeRecorders[.specificProcess] as? CoreAudioProcessTapRecorder {
                core.setTargetPIDs(pids)
                logger.info("CoreAudio 目标 PID 列表已应用到特定进程录制器: \(pids)")
            }
        }
    }
    
    /// 清理所有录制器
    func clearRecorders() {
        logger.info("清理所有录制器")
        activeRecorders.removeAll()
        processRecorders.removeAll()
        processRecordingInfos.removeAll()
        isMultiProcessMode = false
    }
    
    // MARK: - 向后兼容的单音源录制方法
    
    /// 设置录制模式（向后兼容）
    func setRecordingMode(_ mode: RecordingMode) {
        logger.info("录制模式已设置为: \(mode.rawValue)")
        // 这个方法保留用于兼容旧的调用方式
    }
    
    /// 开始录制（向后兼容，单音源）
    func startRecording() {
        logger.warning("使用了旧的单音源录制方法，建议使用 startMultiSourceRecording")
        // 默认启动麦克风录制
        startMultiSourceRecording(wantMic: true, wantSystem: false, wantProcess: false)
    }
    
    // MARK: - Private Methods
    
    /// 启动混音录制（系统音频 + 麦克风混合到一个文件）
    private func startMixedRecording(wantSystem: Bool, wantProcess: Bool, targetPID: pid_t?) {
        if #available(macOS 14.4, *) {
            isMultiProcessMode = false
            logger.info("创建混音录制器")
            let mixedRecorder = MixedAudioRecorder(mode: wantProcess ? .specificProcess : .systemMixdown)
            
            // 设置目标PID
            if let pid = targetPID {
                mixedRecorder.setTargetPID(pid)
                logger.info("设置进程混音录制，PID: \(pid)")
            } else {
                logger.info("设置系统混音录制（混音模式）")
            }
            
            mixedRecorder.setAudioFormat(_currentFormat)
            setupRecorderCallbacks(mixedRecorder, sourceType: .systemAudio)
            
            activeRecorders[.systemAudio] = mixedRecorder
            
            logger.info("启动混音录制器")
            mixedRecorder.startRecording()
            
            onStatus?("正在录制当前目标 + 麦克风")
        } else {
            logger.warning("混音录制需要 macOS 14.4+")
            onStatus?("混音录制需要 macOS 14.4+")
        }
    }
    
    /// Setup callbacks for per-process independent recorders
    private func setupProcessRecorderCallbacks(
        _ recorder: AudioRecorderProtocol,
        pid: pid_t,
        processName: String,
        completedRecordings: inout [pid_t: AudioRecording]
    ) {
        // Per-process level callback
        recorder.onLevel = { [weak self] lvl in
            guard let self = self else { return }
            self.processRecordingInfos[pid]?.level = lvl
            self.onProcessLevel?(pid, lvl)
            // Also forward combined level (max of all processes) for backward compatibility
            let maxLevel = self.processRecordingInfos.values.map { $0.level }.max() ?? 0
            self.onLevel?(maxLevel)
        }
        
        // Per-process peak level callback
        recorder.onPeakLevel = { [weak self] peak in
            guard let self = self else { return }
            self.processRecordingInfos[pid]?.peakLevel = peak
            self.onProcessPeakLevel?(pid, peak)
            // Also forward combined peak for backward compatibility
            let maxPeak = self.processRecordingInfos.values.map { $0.peakLevel }.max() ?? 0
            self.onPeakLevel?(maxPeak)
        }
        
        recorder.onStatus = { [weak self] status in
            self?.onStatus?("[\(processName)] \(status)")
        }
        
        recorder.onRecordingComplete = { [weak self] recording in
            guard let self = self else { return }
            
            self.logger.info("✅ 进程录制完成: \(processName) (PID: \(pid)) → \(recording.fileURL.lastPathComponent)")
            self.processRecordingInfos[pid]?.isRunning = false
            self.processRecordingInfos[pid]?.outputURL = recording.fileURL
            
            // Notify per-process completion
            self.onProcessRecordingComplete?(pid, recording)
            
            // Also notify legacy callback
            self.onRecordingComplete?(recording)
            
            // Check if all process recorders are done
            self.checkAllProcessRecordingsComplete()
        }
        
        recorder.onPlaybackComplete = { [weak self] in
            self?.onPlaybackComplete?()
        }
    }
    
    private func setupRecorderCallbacks(_ recorder: AudioRecorderProtocol, sourceType: AudioSourceType) {
        recorder.onLevel = { [weak self] lvl in
            self?.onLevel?(lvl)
        }
        
        recorder.onPeakLevel = { [weak self] peak in
            self?.onPeakLevel?(peak)
        }
        
        recorder.onStatus = { [weak self] status in
            self?.onStatus?(status)
        }
        
        recorder.onRecordingComplete = { [weak self] recording in
            guard let self = self else { return }
            
            self.logger.info("录制器 \(sourceType.rawValue) 完成录制: \(recording.fileURL.lastPathComponent)")
            
            // 通知单个录制完成（向后兼容）
            self.onRecordingComplete?(recording)
            
            // 检查是否所有录制器都完成了
            self.checkAllRecordingsComplete()
        }
        
        recorder.onPlaybackComplete = { [weak self] in
            self?.onPlaybackComplete?()
        }
    }
    
    private func checkAllRecordingsComplete() {
        // 检查是否所有录制器都已停止
        let allStopped = activeRecorders.values.allSatisfy { !$0.isRunning }
        
        if allStopped {
            logger.info("所有录制器已完成")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                self.clearRecorders()
            }
        }
    }
    
    private func checkAllProcessRecordingsComplete() {
        let allStopped = processRecorders.values.allSatisfy { !$0.isRunning }
        
        if allStopped {
            logger.info("🎉 所有进程录制器已完成")
            
            // Collect all recordings
            var allRecordings: [pid_t: AudioRecording] = [:]
            for (pid, info) in processRecordingInfos {
                if let url = info.outputURL {
                    // Create AudioRecording from URL
                    if let audioInfo = AudioUtils.shared.getAudioFileInfo(at: url),
                       let fileSize = FileManagerUtils.shared.getFileSize(at: url) {
                        let recording = AudioRecording(
                            fileURL: url,
                            duration: audioInfo.duration,
                            fileSize: fileSize,
                            format: _currentFormat.rawValue,
                            recordingMode: RecordingMode.specificProcess.rawValue,
                            sampleRate: audioInfo.sampleRate,
                            channels: Int(audioInfo.channels)
                        )
                        allRecordings[pid] = recording
                    }
                }
            }
            
            // Notify all complete
            onAllProcessRecordingsComplete?(allRecordings)
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                self.clearRecorders()
            }
        }
    }
    
    /// 获取当前活跃的录制器（向后兼容）
    func getCurrentRecorder() -> AudioRecorderProtocol? {
        if isMultiProcessMode {
            return processRecorders.values.first
        }
        return activeRecorders.values.first
    }
}

// MARK: - Supporting Classes (same as before)

 
