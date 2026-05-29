import Cocoa
import Foundation
import AVFoundation
import IOKit.pwr_mgt
import ObjectiveC
import UniformTypeIdentifiers

/// 主视图控制器
class MainViewController: NSViewController {
    private enum AudioExportFormat: String, CaseIterable {
        case original = "原格式"
        case mp3 = "MP3"

        var fileExtension: String? {
            switch self {
            case .original:
                return nil
            case .mp3:
                return "mp3"
            }
        }
    }
    
    // MARK: - Properties
    private var mainWindowView: MainWindowView!
    var audioRecorderController: AudioRecorderController!
    private let logger = Logger.shared
    private let fileManager = FileManagerUtils.shared
    
    // Recording state
    private var isRecording = false
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private var lastRecordedFile: URL?
    private var selectedPlaybackFile: RecordedFileInfo?
    private var currentPlaybackFile: RecordedFileInfo?
    private var playbackPlayer: AVAudioPlayer?
    private var isPlaybackPaused = false
    private var currentRecordingMode: RecordingMode = .microphone
    private let userDefaults = UserDefaults.standard
    private let recordingModeKey = "lastRecordingMode"
    private var currentFormat: AudioFormat = .m4a
    private var playbackDuration: TimeInterval = 0
    
    // 进程列表相关
    private var availableProcesses: [AudioProcessInfo] = []
    private var selectedProcesses: Set<AudioProcessInfo> = []
    private var selectedPIDs: [pid_t] = []
    
    // 混音设置
    private var shouldMixAudio: Bool = false
    
    // 进程列表自动刷新
    private var processRefreshTimer: Timer?
    
    // 进程退出监听
    private var processExitObserver: Any?
    
    // 睡眠阻止（IOPMAssertion）
    private var sleepAssertionID: IOPMAssertionID = 0
    private var sleepAssertionActive = false
    
    // 磁盘空间监控
    private var diskMonitorTimer: Timer?
    
    // MARK: - Lifecycle
    override func loadView() {
        mainWindowView = MainWindowView()
        mainWindowView.delegate = self
        view = mainWindowView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("主视图控制器开始加载")
        setupInitialState()
        // 关闭启动时的权限监控与静默检查，避免任何权限链路阻塞 UI
        // checkAudioPermissionsSilently()
        logger.info("主视图控制器已加载")
    }
    
    private func ensureAudioControllerInitialized() {
        guard audioRecorderController == nil else { return }
        
        logger.info("开始初始化音频控制器")
        audioRecorderController = AudioRecorderController()
        setupAudioRecorder()
        logger.info("音频控制器初始化完成")
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        // 延迟检查按钮位置
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.mainWindowView.debugButtonPosition()
        }
    }
    
    // MARK: - Setup
    private func setupAudioRecorder() {
        guard let audioRecorderController = audioRecorderController else {
            logger.warning("音频控制器未初始化，跳过设置")
            return
        }
        
        audioRecorderController.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.mainWindowView.updateLevel(level)
            }
        }
        
        // 峰值回调（PCM 峰值，直接传给 WaveformView 绘制——与播放波形同源）
        audioRecorderController.onPeakLevel = { [weak self] peakLevel in
            DispatchQueue.main.async {
                self?.mainWindowView.updatePeakLevel(peakLevel)
            }
        }
        
        audioRecorderController.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                self?.mainWindowView.updateStatus(status)
                
                // 检查是否是录音失败的状态，如果是则停止计时器
                if status.contains("失败") || 
                   status.contains("错误") || 
                   status.contains("权限") ||
                   status.contains("denied") ||
                   status.contains("permission") {
                    self?.handleRecordingFailure()
                }
            }
        }
        
        audioRecorderController.onRecordingComplete = { [weak self] recording in
            DispatchQueue.main.async {
                self?.handleRecordingComplete(recording)
            }
        }
        
        audioRecorderController.onPlaybackComplete = { [weak self] in
            DispatchQueue.main.async {
                self?.finishPlayback()
            }
        }
        
        audioRecorderController.setRecordingMode(currentRecordingMode)
        audioRecorderController.setAudioFormat(currentFormat)
    }
    
    private func setupInitialState() {
        // 加载上次的录制模式
        loadLastRecordingMode()
        
        // 从 UserDefaults 加载设置
        loadSettingsFromDefaults()
        
        // 监听设置变更通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .settingsChanged,
            object: nil
        )
        
        mainWindowView.updateMode(currentRecordingMode)
        mainWindowView.updateRecordingState(.idle)
        mainWindowView.updateStatus("准备就绪")
        
        // 加载可用进程列表
        loadAvailableProcesses()
        
        // 启动进程列表自动刷新（2 秒间隔）
        startProcessRefreshTimer()
        
        // 监听进程退出通知
        setupProcessExitMonitoring()
        
        // 加载录音文件列表
        loadRecordedFilesOnStartup()
        
        // 清理旧日志
        logger.cleanupOldLogs()
        
        // 清理临时文件
        fileManager.cleanupTempFiles()
    }
    
    /// 静默权限检查（启动时不弹窗）
    private func checkAudioPermissionsSilently() {
        let permissions = PermissionManager.shared.checkAllPermissions()
        
        // 只记录日志，不显示状态信息
        switch permissions.microphone {
        case .granted:
            logger.info("麦克风权限已授予")
        case .denied:
            logger.info("麦克风权限被拒绝")
        case .notDetermined:
            logger.info("麦克风权限未确定")
        case .restricted:
            logger.info("麦克风权限受限制")
        }
        
        switch permissions.screenRecording {
        case .granted:
            logger.info("屏幕录制权限已授予")
        case .denied:
            logger.info("屏幕录制权限被拒绝")
        case .notDetermined:
            logger.info("屏幕录制权限未确定")
        case .restricted:
            logger.info("屏幕录制权限受限制")
        }
        
        // 开始权限监控
        startPermissionMonitoring()
    }
    
    /// 主动权限检查（录制时使用）
    private func checkAudioPermissions() {
        let permissions = PermissionManager.shared.checkAllPermissions()
        
        // 检查麦克风权限
        switch permissions.microphone {
        case .granted:
            logger.info("麦克风权限已授予")
        case .denied:
            logger.warning("麦克风权限被拒绝")
            mainWindowView.updateStatus("麦克风权限被拒绝，可以切换到系统音频模式")
        case .notDetermined:
            logger.info("麦克风权限未确定，将在需要时请求")
        case .restricted:
            logger.warning("麦克风权限受限制")
            mainWindowView.updateStatus("麦克风权限受系统限制")
        }
        
        // 检查屏幕录制权限
        switch permissions.screenRecording {
        case .granted:
            logger.info("屏幕录制权限已授予")
        case .denied:
            logger.warning("屏幕录制权限被拒绝")
            mainWindowView.updateStatus("屏幕录制权限被拒绝，请在系统设置中允许")
        case .notDetermined:
            logger.info("屏幕录制权限未确定，将在需要时请求")
        case .restricted:
            logger.warning("屏幕录制权限受限制")
            mainWindowView.updateStatus("屏幕录制权限受系统限制")
        }
    }
    
    private func startPermissionMonitoring() {
        PermissionManager.shared.startPermissionMonitoring { [weak self] type, status in
            DispatchQueue.main.async {
                self?.handlePermissionStatusChange(type: type, status: status)
            }
        }
    }
    
    private func handlePermissionStatusChange(type: PermissionManager.PermissionType, status: PermissionManager.PermissionStatus) {
        // 只在录制过程中或权限状态发生重要变化时显示提示
        guard isRecording else { return }
        
        switch type {
        case .microphone:
            switch status {
            case .granted:
                logger.info("麦克风权限已授予")
                if currentRecordingMode == .microphone {
                    mainWindowView.updateStatus("麦克风权限已授予，可以开始录制")
                }
            case .denied:
                logger.warning("麦克风权限被拒绝")
                if currentRecordingMode == .microphone {
                    mainWindowView.updateStatus("麦克风权限被拒绝，请切换到系统音频模式")
                }
            default:
                break
            }
        case .screenRecording:
            switch status {
            case .granted:
                logger.info("屏幕录制权限已授予")
                // 屏幕录制权限相关代码已移除
            case .denied:
                logger.warning("屏幕录制权限被拒绝")
                // 屏幕录制权限相关代码已移除
            default:
                break
            }
        case .systemAudioCapture:
            switch status {
            case .granted:
                logger.info("系统音频捕获权限已授予")
            case .denied:
                logger.warning("系统音频捕获权限被拒绝")
                if currentRecordingMode == .specificProcess || currentRecordingMode == .systemMixdown {
                    mainWindowView.updateStatus("系统音频捕获权限被拒绝，请点击允许或在设置中开启")
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Recording Management
    private func startRecording() {
        guard !isRecording else {
            logger.warning("录制已在进行中")
            return
        }
        
        // 磁盘空间检测（录制前）
        if !fileManager.hasSufficientDiskSpace() {
            let available = fileManager.getAvailableDiskSpace().map { fileManager.formatDiskSpace($0) } ?? "未知"
            logger.warning("磁盘空间不足: \(available)")
            let alert = NSAlert()
            alert.messageText = "磁盘空间不足"
            alert.informativeText = "当前可用空间仅 \(available)，可能无法完成录制。建议清理磁盘后再试。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "仍然录制")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertSecondButtonReturn {
                return
            }
        }
        
        // 确保音频控制器已初始化
        ensureAudioControllerInitialized()
        
        // 根据左侧选择动态确定录制源
        let wantMic = mainWindowView.isMicrophoneSourceSelected()
        let wantSystemMixdown = mainWindowView.isSystemAudioSourceSelected()
        let wantSpecificProcess = !selectedPIDs.isEmpty  // 多进程支持
        
        // 新侧边栏默认选择“全部系统声音”，这里保留兜底防御
        guard wantSystemMixdown || wantSpecificProcess else {
            mainWindowView.updateStatus("请选择录制目标：全部系统声音或某个应用")
            return
        }
        
        // 根据UI逻辑调整：如果启用混音，则自动包含麦克风（不需要单独录制麦克风轨道）
        let actualWantMic = shouldMixAudio ? false : wantMic  // 混音模式下不需要单独的麦克风轨道
        
        logger.info("开始多音源录制 - 麦克风:\(actualWantMic), 系统:\(wantSystemMixdown), 进程:\(wantSpecificProcess), 混音:\(shouldMixAudio)")
        
        // 构建录制源描述
        let targetText = wantSpecificProcess ? "应用声音" : "全部系统声音"
        let sourcesText = shouldMixAudio ? "\(targetText) + 麦克风" : targetText
        
        // 根据实际录制源检查权限
        checkPermissionsBeforeRecording(
            wantMic: actualWantMic,
            wantSystem: wantSystemMixdown,
            wantProcess: wantSpecificProcess,
            mixAudio: shouldMixAudio
        ) { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.logger.warning("权限未通过，取消录制")
                self.handleRecordingFailure()
                return
            }
            
            // 录制前主动请求系统音频捕获权限（TCC）
            if wantSystemMixdown || wantSpecificProcess {
                PermissionManager.shared.requestSystemAudioCapturePermission { status in
                    // 无论结果如何，继续尝试启动，系统也会再次弹窗
                }
            }
            
            // 如果启用混音，提前请求麦克风权限，避免启动时卡顿
            if self.shouldMixAudio {
                PermissionManager.shared.requestMicrophonePermission { status in
                    // 权限请求完成后继续
                    self.logger.info("混音模式：麦克风权限状态 - \(status)")
                }
            }
            
            self.isRecording = true
            self.recordingStartTime = Date()
            self.mainWindowView.updateRecordingState(.preparing)
            self.mainWindowView.updateStatus("准备录制 \(sourcesText)…")
            self.startTimer()
            
            // 阻止系统睡眠
            self.preventSleep()
            
            // 启动磁盘空间监控（每 10 秒检测）
            self.startDiskMonitor()
            
            // 设置音频格式
            self.audioRecorderController.setAudioFormat(self.currentFormat)
            
            // 使用新的多音源录制方法
            self.audioRecorderController.startMultiSourceRecording(
                wantMic: actualWantMic,
                wantSystem: wantSystemMixdown,
                wantProcess: wantSpecificProcess,
                targetPID: self.selectedPIDs.first,
                mixAudio: self.shouldMixAudio
            )
            
            // 标记录制中（crash 恢复用）— 写入录制目录路径，crash 后扫描最新文件
            self.fileManager.markRecordingStarted(fileURL: self.fileManager.getRecordingsDirectory())
            
            // 视觉上进入录制态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.isRecording { self.mainWindowView.updateRecordingState(.recording) }
            }
        }
    }
    
    /// 根据实际录制源检查权限
    /// - Parameters:
    ///   - wantMic: 是否需要麦克风（纯麦克风轨道）
    ///   - wantSystem: 是否需要系统音频
    ///   - wantProcess: 是否需要特定进程音频
    ///   - mixAudio: 是否启用混音（混音需要麦克风+系统音频）
    ///   - completion: 权限检查结果回调
    private func checkPermissionsBeforeRecording(
        wantMic: Bool,
        wantSystem: Bool,
        wantProcess: Bool,
        mixAudio: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        // 判断是否需要麦克风权限：
        // 1. 纯麦克风录制 (wantMic = true)
        // 2. 混音模式 (mixAudio = true，需要麦克风+系统音频)
        let needMicPermission = wantMic || mixAudio
        
        logger.info("权限检查 - 需要麦克风:\(needMicPermission), 系统:\(wantSystem), 进程:\(wantProcess), 混音:\(mixAudio)")
        
        if needMicPermission {
            // 需要麦克风权限
            logger.info("请求麦克风权限...")
            mainWindowView.updateStatus("正在请求麦克风权限...")
            
            PermissionManager.shared.requestMicrophonePermission { [weak self] status in
                DispatchQueue.main.async {
                    switch status {
                    case .granted:
                        self?.logger.info("麦克风权限已授予")
                        completion(true)
                    case .denied, .restricted:
                        self?.logger.warning("麦克风权限被拒绝")
                        if wantMic && !wantSystem && !wantProcess {
                            // 只录麦克风但权限被拒绝
                            self?.mainWindowView.updateStatus("麦克风权限被拒绝，请在系统设置中开启")
                            completion(false)
                        } else if mixAudio {
                            // 混音模式但麦克风被拒绝
                            self?.mainWindowView.updateStatus("麦克风权限被拒绝，混音功能不可用")
                            completion(false)
                        } else {
                            // 有其他音源，可以继续
                            completion(true)
                        }
                    case .notDetermined:
                        self?.logger.warning("麦克风权限未确定")
                        self?.mainWindowView.updateStatus("麦克风权限未确定，请重试")
                        completion(false)
                    }
                }
            }
        } else if wantSystem || wantProcess {
            // 只需要系统音频或进程音频，CoreAudio 方案不需要预先检查权限
            // 系统会在首次使用时提示系统音频捕获权限
            logger.info("CoreAudio 模式：只录制系统/进程音频，无需麦克风权限，直接开始")
            DispatchQueue.main.async { completion(true) }
        } else {
            // 没有选择任何音源（理论上不会到这里，前面已经检查过）
            logger.warning("未选择任何录制源")
            DispatchQueue.main.async { completion(false) }
        }
    }
    
    private func stopRecording() {
        guard isRecording else {
            logger.warning("没有正在进行的录制")
            mainWindowView.updateStatus("没有正在进行的录制")
            return
        }
        
        logger.info("停止录制")
        
        isRecording = false
        mainWindowView.updateRecordingState(.stopping)
        mainWindowView.updateStatus("正在停止录制...")
        
        // 停止计时器
        stopTimer()
        
        // 停止磁盘监控
        stopDiskMonitor()
        
        // 允许系统睡眠
        allowSleep()
        
        // 停止底层录制
        audioRecorderController.stopRecording()
        
        logger.info("录制已停止")
    }
    
    private func handleRecordingComplete(_ recording: AudioRecording) {
        lastRecordedFile = recording.fileURL
        mainWindowView.updateRecordingState(.idle)
        mainWindowView.updateStatus("录制完成: \(recording.fileName)")
        
        // 清除录制标记（crash 恢复用）
        fileManager.markRecordingFinished()
        
        logger.info("录制完成: \(recording.fileName), 时长: \(recording.formattedDuration), 大小: \(recording.formattedFileSize)")
        
        // 添加到已录制文件列表
        let fileInfo = RecordedFileInfo(
            url: recording.fileURL,
            name: recording.fileName,
            date: recording.createdAt,
            duration: recording.duration,
            size: recording.fileSize
        )
        selectedPlaybackFile = fileInfo
        mainWindowView.addRecordedFile(fileInfo)
        
        // 录制完成后加载真实 PCM 波形
        mainWindowView.loadFileWaveform(url: recording.fileURL)
        
        mainWindowView.updatePlaybackDisplay(
            fileName: fileInfo.name,
            currentTime: 0,
            duration: fileInfo.duration,
            isPlaying: false,
            isPaused: false
        )
        
        // REQ-2.0-05: 录制完成后直接进入编辑器（零操作过渡）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.enterEditor(file: fileInfo)
        }
    }
    
    // MARK: - Timer Management
    private func startTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }
    
    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        mainWindowView.updateTimer("00:00:00")
    }
    
    private func handleRecordingFailure() {
        logger.warning("录音失败，停止计时器")
        isRecording = false
        recordingStartTime = nil
        stopTimer()
        stopDiskMonitor()
        allowSleep()
        fileManager.markRecordingFinished()
        mainWindowView.updateRecordingState(.idle)
    }
    
    private func updateTimer() {
        guard let startTime = recordingStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed) % 3600 / 60
        let seconds = Int(elapsed) % 60
        let milliseconds = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 10)
        
        let timeString = String(format: "%02d:%02d:%02d.%d", hours, minutes, seconds, milliseconds)
        mainWindowView.updateTimer(timeString)
    }
    
    // MARK: - Playback Management
    private func playRecording() {
        guard !isRecording else {
            mainWindowView.updateStatus("录制中不能播放音频")
            return
        }

        if let player = playbackPlayer, currentPlaybackFile?.url == selectedPlaybackFile?.url {
            if player.isPlaying {
                pausePlayback()
            } else {
                resumePlayback()
            }
            return
        }

        guard let file = selectedPlaybackFile else {
            mainWindowView.updateStatus("请先在已录制音频中选择要播放的文件")
            logger.warning("没有选中的可播放录音文件")
            return
        }

        startPlayback(file: file)
    }

    private func selectPlaybackFile(_ file: RecordedFileInfo) {
        if currentPlaybackFile?.url != file.url {
            stopPlayback(resetDisplay: false)
        }

        selectedPlaybackFile = file
        playbackDuration = file.duration
        mainWindowView.updateStatus("已选择播放文件: \(file.name)")
        mainWindowView.updatePlaybackDisplay(
            fileName: file.name,
            currentTime: 0,
            duration: file.duration,
            isPlaying: false,
            isPaused: false
        )
        
        // 加载并展示文件的静态波形
        mainWindowView.loadFileWaveform(url: file.url)
    }

    private func startPlayback(file: RecordedFileInfo) {
        guard fileManager.fileExists(at: file.url) else {
            mainWindowView.updateStatus("播放失败：文件不存在")
            logger.warning("播放失败，文件不存在: \(file.url.path)")
            return
        }

        stopPlayback(resetDisplay: false)

        do {
            let player = try AVAudioPlayer(contentsOf: file.url)
            player.delegate = self
            player.isMeteringEnabled = true  // 启用播放电平监测
            player.prepareToPlay()

            playbackPlayer = player
            currentPlaybackFile = file
            selectedPlaybackFile = file
            playbackDuration = player.duration > 0 ? player.duration : file.duration
            isPlaybackPaused = false

            player.play()
            mainWindowView.updateRecordingState(.playing)
            mainWindowView.updateStatus("正在播放: \(file.name)")
            mainWindowView.updatePlaybackDisplay(
                fileName: file.name,
                currentTime: player.currentTime,
                duration: playbackDuration,
                isPlaying: true,
                isPaused: false
            )
            startPlaybackTimer()
            logger.info("播放启动: \(file.name), 时长: \(String(format: "%.2f", playbackDuration)) 秒")
        } catch {
            mainWindowView.updateStatus("播放失败: \(error.localizedDescription)")
            logger.error("播放失败: \(error.localizedDescription)")
            finishPlayback(resetProgress: true)
        }
    }

    private func pausePlayback() {
        guard let player = playbackPlayer, player.isPlaying else { return }
        player.pause()
        isPlaybackPaused = true
        stopPlaybackTimer()
        mainWindowView.updateRecordingState(.playing)
        mainWindowView.updatePlaybackDisplay(
            fileName: currentPlaybackFile?.name,
            currentTime: player.currentTime,
            duration: playbackDuration,
            isPlaying: false,
            isPaused: true
        )
        mainWindowView.updateStatus("播放已暂停: \(currentPlaybackFile?.name ?? "")")
        logger.info("播放已暂停")
    }

    private func resumePlayback() {
        guard let player = playbackPlayer, let file = currentPlaybackFile else { return }
        player.play()
        isPlaybackPaused = false
        mainWindowView.updateRecordingState(.playing)
        mainWindowView.updatePlaybackDisplay(
            fileName: file.name,
            currentTime: player.currentTime,
            duration: playbackDuration,
            isPlaying: true,
            isPaused: false
        )
        mainWindowView.updateStatus("继续播放: \(file.name)")
        startPlaybackTimer()
        logger.info("继续播放")
    }
    
    private func stopPlayback() {
        stopPlayback(resetDisplay: true)
    }

    private func stopPlayback(resetDisplay: Bool) {
        logger.info("停止播放")
        stopPlaybackTimer()
        playbackPlayer?.stop()
        playbackPlayer = nil
        currentPlaybackFile = nil
        isPlaybackPaused = false
        audioRecorderController?.stopPlayback()
        mainWindowView.updateRecordingState(.idle)

        if resetDisplay, let file = selectedPlaybackFile {
            mainWindowView.updatePlaybackDisplay(
                fileName: file.name,
                currentTime: 0,
                duration: file.duration,
                isPlaying: false,
                isPaused: false
            )
            mainWindowView.updateStatus("播放已停止")
        }
    }
    
    private func startPlaybackTimer() {
        stopPlaybackTimer() // 确保之前的定时器被停止
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlaybackTimer()
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updatePlaybackTimer() {
        guard let player = playbackPlayer, let file = currentPlaybackFile else { return }

        let currentTime = min(player.currentTime, playbackDuration)
        mainWindowView.updateTimer(formatTransportTime(currentTime))
        mainWindowView.updatePlaybackDisplay(
            fileName: file.name,
            currentTime: currentTime,
            duration: playbackDuration,
            isPlaying: player.isPlaying,
            isPaused: isPlaybackPaused
        )
        
        // 播放电平监测 → 更新电平表
        player.updateMeters()
        let leftDB = player.averagePower(forChannel: 0)
        let rightDB = player.numberOfChannels > 1 ? player.averagePower(forChannel: 1) : leftDB
        // dB → 归一化 (0~1)，-60dB=0，0dB=1
        let leftNorm = max(0, min(1, (leftDB + 60) / 60))
        let rightNorm = max(0, min(1, (rightDB + 60) / 60))
        mainWindowView.updateLevel(Float(leftNorm))
        
        // 同步波形播放进度
        if playbackDuration > 0 {
            mainWindowView.updateWaveformProgress(currentTime / playbackDuration)
        }

        if playbackDuration > 0 && currentTime >= playbackDuration {
            finishPlayback()
        }
    }

    private func finishPlayback(resetProgress: Bool = false) {
        let finishedFile = currentPlaybackFile ?? selectedPlaybackFile
        stopPlaybackTimer()
        playbackPlayer?.stop()
        playbackPlayer = nil
        currentPlaybackFile = nil
        isPlaybackPaused = false
        mainWindowView.updateRecordingState(.idle)
        mainWindowView.updateTimer("00:00:00.0")

        if let file = finishedFile {
            mainWindowView.updatePlaybackDisplay(
                fileName: file.name,
                currentTime: resetProgress ? 0 : (playbackDuration > 0 ? playbackDuration : file.duration),
                duration: playbackDuration > 0 ? playbackDuration : file.duration,
                isPlaying: false,
                isPaused: false
            )
        }
        mainWindowView.updateStatus("播放完成")
    }

    private func formatTransportTime(_ time: TimeInterval) -> String {
        let elapsed = max(0, time)
        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed) % 3600 / 60
        let seconds = Int(elapsed) % 60
        let milliseconds = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d:%02d.%d", hours, minutes, seconds, milliseconds)
    }
    
    // MARK: - Recording Mode Management
    private func loadLastRecordingMode() {
        // 不记录之前的选择，每次启动都使用默认模式
        logger.info("使用默认录制模式: \(currentRecordingMode.rawValue)")
    }
    
    private func saveRecordingMode(_ mode: RecordingMode) {
        userDefaults.set(mode.rawValue, forKey: recordingModeKey)
        logger.info("已保存录制模式: \(mode.rawValue)")
    }
    
    // MARK: - File Management
    private func downloadRecording() {
        guard let fileURL = lastRecordedFile, fileManager.fileExists(at: fileURL) else {
            mainWindowView.updateStatus("没有可下载的录音文件")
            logger.warning("没有可下载的录音文件")
            return
        }
        
        logger.info("开始下载: \(fileURL.lastPathComponent)")
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择保存位置"
        panel.message = "选择录音文件的保存位置"
        
        panel.begin { [weak self] response in
            if response == .OK, let saveURL = panel.url {
                let destinationURL = saveURL.appendingPathComponent(fileURL.lastPathComponent)
                
                do {
                    try self?.fileManager.copyFile(from: fileURL, to: destinationURL)
                    self?.mainWindowView.updateStatus("文件已保存到: \(destinationURL.path)")
                    self?.logger.info("文件已保存到: \(destinationURL.path)")
                } catch {
                    let errorMsg = "保存失败: \(error.localizedDescription)"
                    self?.mainWindowView.updateStatus(errorMsg)
                    self?.logger.error("保存文件失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Mode Management
    private func switchRecordingMode() {
        // 三态循环：microphone -> specificProcess -> systemMixdown -> microphone
        switch currentRecordingMode {
        case .microphone:
            currentRecordingMode = .specificProcess
        case .specificProcess:
            currentRecordingMode = .systemMixdown
        case .systemMixdown:
            currentRecordingMode = .microphone
        }
        
        // 确保音频控制器已初始化
        ensureAudioControllerInitialized()
        
        audioRecorderController?.setRecordingMode(currentRecordingMode)
        mainWindowView.updateMode(currentRecordingMode)
        
        logger.info("录制模式已切换到: \(currentRecordingMode.rawValue)")
        
        // 根据模式提示/检查权限
        switch currentRecordingMode {
        case .microphone:
            checkMicrophonePermissionOnModeSwitch()
        case .specificProcess:
            // 特定进程录制需要 NSAudioCaptureUsageDescription（已在 Info.plist）
            mainWindowView.updateStatus("特定进程录制：需要系统音频捕获权限，开始录制时会提示授权")
            // 模式切到特定进程录制时，同步一次当前选择（若有）
            if let pid = selectedPIDs.first {
                audioRecorderController?.setCoreAudioTargetPID(pid)
            } else {
                audioRecorderController?.setCoreAudioTargetPID(nil)
            }
        case .systemMixdown:
            // 系统混音录制需要 NSAudioCaptureUsageDescription（已在 Info.plist）
            mainWindowView.updateStatus("系统混音录制：需要系统音频捕获权限，开始录制时会提示授权")
        
        }
    }
    
    private func checkMicrophonePermissionOnModeSwitch() {
        logger.info("检查麦克风权限（模式切换时）")
        
        let permissions = PermissionManager.shared.checkAllPermissions()
        switch permissions.microphone {
        case .granted:
            logger.info("麦克风权限已授予")
            mainWindowView.updateStatus("麦克风权限已授予，可以开始录制")
        case .denied, .restricted:
            logger.warning("麦克风权限被拒绝")
            mainWindowView.updateStatus("麦克风权限被拒绝，开始录制时将重新请求")
        case .notDetermined:
            logger.info("麦克风权限未确定")
            mainWindowView.updateStatus("麦克风权限未确定，开始录制时将请求权限")
        }
    }

    private func checkScreenRecordingPermissionOnModeSwitch() {
        logger.info("检查屏幕录制权限（模式切换时）")
        
        let permissions = PermissionManager.shared.checkAllPermissions()
        switch permissions.screenRecording {
        case .granted:
            logger.info("屏幕录制权限已授予")
            mainWindowView.updateStatus("屏幕录制权限已授予，可以开始录制")
        case .denied, .restricted:
            logger.warning("屏幕录制权限被拒绝")
            mainWindowView.updateStatus("屏幕录制权限被拒绝，开始录制时将重新请求")
        case .notDetermined:
            logger.info("屏幕录制权限未确定")
            mainWindowView.updateStatus("屏幕录制权限未确定，开始录制时将请求权限")
        }
    }
    
    // MARK: - Menu Keyboard Shortcuts
    
    func toggleRecordingFromMenu() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func toggleSidebarFromMenu() {
        mainWindowView.toggleSidebar()
    }
    
    func editorUndoFromMenu() {
        currentEditor?.undo()
    }
    
    func editorRedoFromMenu() {
        currentEditor?.redo()
    }
    
    // BUG-014 fix: 暴露编辑器模式状态给菜单验证
    var isInEditorMode: Bool {
        return currentEditor != nil
    }
    
    func togglePlaybackFromMenu() {
        if playbackPlayer != nil {
            if playbackPlayer?.isPlaying == true {
                pausePlayback()
            } else if isPlaybackPaused {
                resumePlayback()
            }
        } else if selectedPlaybackFile != nil {
            playRecording()
        }
    }
    
    func exportCurrentFileFromMenu() {
        guard let file = selectedPlaybackFile else { return }
        exportAudio(file: file)
    }
    
    func deleteCurrentFileFromMenu() {
        guard let file = selectedPlaybackFile else { return }
        // 停止播放
        if playbackPlayer != nil { stopPlayback() }
        // 删除文件
        do {
            try FileManager.default.removeItem(at: file.url)
            selectedPlaybackFile = nil
            loadRecordedFilesOnStartup() // 刷新文件列表
            mainWindowView.updateStatus("已删除: \(file.name)")
            logger.info("已删除录音文件: \(file.name)")
        } catch {
            logger.error("删除文件失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Settings Sync
    
    /// 从 UserDefaults 加载设置
    private func loadSettingsFromDefaults() {
        let defaults = UserDefaults.standard
        
        // 录制格式
        let formatStr = defaults.string(forKey: SettingsWindowController.Keys.recordingFormat) ?? "m4a"
        currentFormat = formatStr == "wav" ? .wav : .m4a
        
        logger.info("已加载设置 — 格式: \(currentFormat.rawValue)")
    }
    
    /// 响应设置变更通知
    @objc private func handleSettingsChanged() {
        loadSettingsFromDefaults()
        
        // 同步到音频控制器
        if let controller = audioRecorderController {
            controller.setAudioFormat(currentFormat)
        }
        
        logger.info("设置已同步 — 格式: \(currentFormat.rawValue)")
    }
    
    // MARK: - Debug Methods
    private func simulateButtonClick() {
        logger.info("🤖 开始模拟按钮点击测试...")
        
        // 方法1: 直接调用按钮的action（最小化版本暂时注释）
        logger.info("方法1: 直接调用按钮action - 跳过（最小化版本）")
        // mainWindowView.perform(#selector(MainWindowView.modeSwitchButtonClicked))
        
        // 方法2: 直接调用delegate方法
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.logger.info("方法2: 直接调用delegate方法")
            self.mainWindowViewDidSwitchMode(self.mainWindowView)
        }
        
        // 方法3: 直接调用switchRecordingMode
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.logger.info("方法3: 直接调用switchRecordingMode")
            self.switchRecordingMode()
        }
    }
    
    private func changeFormat(_ formatString: String) {
        let newFormat: AudioFormat
        switch formatString.lowercased() {
        case "wav":
            newFormat = .wav
        default:
            newFormat = .m4a
        }
        
        if newFormat != currentFormat {
            currentFormat = newFormat
            
            // 确保音频控制器已初始化
            ensureAudioControllerInitialized()
            
            audioRecorderController?.setAudioFormat(newFormat)
            logger.info("音频格式已更改为: \(newFormat.rawValue)")
        }
    }
}

// MARK: - MainWindowViewDelegate
extension MainViewController: MainWindowViewDelegate {
    func mainWindowViewDidSwitchMode(_ view: MainWindowView) {
        logger.info("🎯 主视图控制器收到模式切换请求")
        logger.info("切换前当前模式: \(currentRecordingMode.rawValue)")
        switchRecordingMode()
        logger.info("切换后当前模式: \(currentRecordingMode.rawValue)")
    }
    
    func mainWindowViewDidStartRecording(_ view: MainWindowView) {
        startRecording()
    }
    
    func mainWindowViewDidStopRecording(_ view: MainWindowView) {
        logger.info("🛑 主视图控制器收到停止录制请求")
        logger.info("当前录制状态: \(isRecording)")
        stopRecording()
    }
    
    func mainWindowViewDidPlayRecording(_ view: MainWindowView) {
        playRecording()
    }
    
    func mainWindowViewDidDownloadRecording(_ view: MainWindowView) {
        // Fallback: use selectedPlaybackFile or lastRecordedFile
        if let file = selectedPlaybackFile {
            exportAudio(file: file)
        } else if let url = lastRecordedFile, fileManager.fileExists(at: url) {
            let fileInfo = RecordedFileInfo(url: url, name: url.lastPathComponent, date: Date(), duration: 0, size: 0)
            exportAudio(file: fileInfo)
        } else {
            mainWindowView.updateStatus("没有可导出的录音文件")
        }
    }
    
    func mainWindowViewDidChangeFormat(_ view: MainWindowView, format: String) {
        changeFormat(format)
    }
    
    func mainWindowViewDidOpenPermissions(_ view: MainWindowView) {
        openSystemPreferences()
    }
    
    func mainWindowViewDidStopPlayback(_ view: MainWindowView) {
        stopPlayback()
    }

    func mainWindowViewDidSelectRecordedFile(_ view: MainWindowView, file: RecordedFileInfo) {
        // 选中文件即进入编辑态（波形+工具栏），不需要单独点编辑
        enterEditor(file: file)
    }
    
    func mainWindowViewDidSelectProcesses(_ view: MainWindowView, pids: [pid_t]) {
        selectedPIDs = pids
        
        // 不保存选择状态，每次启动都完全重置
        ensureAudioControllerInitialized()
        audioRecorderController?.setCoreAudioTargetPID(pids.first)
        
        if let first = pids.first {
            mainWindowView.updateStatus("录制目标：应用声音")
        } else {
            mainWindowView.updateStatus("录制目标：全部系统声音")
        }
    }
    
    func mainWindowViewDidRequestProcessRefresh(_ view: MainWindowView) {
        refreshProcessList()
    }
    
    func mainWindowViewDidRequestExportAudio(_ view: MainWindowView, file: RecordedFileInfo) {
        exportAudio(file: file)
    }
    
    func mainWindowViewDidRenameFile(_ view: MainWindowView, file: RecordedFileInfo, newName: String) {
        let directory = file.url.deletingLastPathComponent()
        let newURL = directory.appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: file.url, to: newURL)
            logger.info("文件已重命名: \(file.name) → \(newName)")
            loadRecordedFilesOnStartup() // 刷新列表
            mainWindowView.updateStatus("已重命名: \(newName)")
        } catch {
            logger.error("重命名失败: \(error.localizedDescription)")
            mainWindowView.updateStatus("重命名失败")
        }
    }
    
    func mainWindowViewDidChangeMixAudio(_ view: MainWindowView, enabled: Bool) {
        shouldMixAudio = enabled
        logger.info("混音设置已更改: \(enabled)")
        
        if enabled {
            mainWindowView.updateStatus("已开启麦克风叠加：会混入当前录制目标")
            
            // 立即请求麦克风权限，避免录制时卡顿
            logger.info("预先请求麦克风权限...")
            PermissionManager.shared.requestMicrophonePermission { [weak self] status in
                DispatchQueue.main.async {
                    switch status {
                    case .granted:
                        self?.logger.info("麦克风权限已授予")
                        self?.mainWindowView.updateStatus("麦克风权限就绪，可以开始录制")
                    case .denied, .restricted:
                        self?.logger.warning("麦克风权限被拒绝")
                        self?.mainWindowView.updateStatus("麦克风权限被拒绝，混音录制可能无法使用")
                    case .notDetermined:
                        self?.logger.info("麦克风权限未确定")
                    }
                }
            }
        } else {
            mainWindowView.updateStatus("已关闭麦克风叠加")
        }
    }
    
    func mainWindowViewDidSeekToProgress(_ view: MainWindowView, progress: Double) {
        // 如果有正在播放/暂停的文件，跳转到对应时间
        if let player = playbackPlayer {
            let targetTime = player.duration * progress
            player.currentTime = targetTime
            
            // 更新 UI 显示
            if let file = currentPlaybackFile {
                mainWindowView.updatePlaybackDisplay(
                    fileName: file.name,
                    currentTime: targetTime,
                    duration: playbackDuration,
                    isPlaying: player.isPlaying,
                    isPaused: isPlaybackPaused
                )
                mainWindowView.updateTimer(formatTransportTime(targetTime))
            }
        } else if let file = selectedPlaybackFile {
            // 没有正在播放但有选中文件 → 从指定位置开始播放
            startPlayback(file: file)
            if let player = playbackPlayer {
                let targetTime = player.duration * progress
                player.currentTime = targetTime
                mainWindowView.updateWaveformProgress(progress)
            }
        }
    }
    
    func mainWindowViewDidRequestEditFile(_ view: MainWindowView, file: RecordedFileInfo) {
        enterEditor(file: file)
    }
    
    private func refreshProcessList() {
        logger.info("🔄 刷新进程列表...")
        mainWindowView.updateStatus("正在刷新进程列表...")
        
        // 在后台线程刷新进程列表
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if #available(macOS 14.4, *) {
                Task { @MainActor in
                    let coreAudioRecorder = CoreAudioProcessTapRecorder(mode: .systemMixdown)
                    let processes = coreAudioRecorder.getAvailableAudioProcesses()
                    
                    self.mainWindowView.updateProcessList(processes)
                    self.logger.info("✅ 进程列表刷新完成，发现 \(processes.count) 个进程")
                    self.mainWindowView.updateStatus("进程列表已刷新，发现 \(processes.count) 个进程")
                    
                    // 不恢复上次的选择状态，完全重置
                    self.logger.info("📝 进程列表刷新完成，完全重置状态")
                }
            } else {
                DispatchQueue.main.async {
                    self.mainWindowView.updateStatus("当前系统不支持 CoreAudio Process Tap")
                }
            }
        }
    }
    
    private func exportAudio(file: RecordedFileInfo) {
        logger.info("🎵 准备导出音频: \(file.name)")

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 34))
        let formatLabel = NSTextField(labelWithString: "导出格式：")
        formatLabel.frame = NSRect(x: 0, y: 7, width: 72, height: 20)
        let formatPopup = NSPopUpButton(frame: NSRect(x: 78, y: 2, width: 170, height: 26), pullsDown: false)
        formatPopup.addItems(withTitles: AudioExportFormat.allCases.map { $0.rawValue })
        accessoryView.addSubview(formatLabel)
        accessoryView.addSubview(formatPopup)

        let panel = NSSavePanel()
        panel.title = "导出音频"
        panel.prompt = "导出"
        panel.message = "选择导出位置和格式"
        panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent
        panel.canCreateDirectories = true
        panel.accessoryView = accessoryView
        // Note: allowedContentTypes is set dynamically below via formatPopup callback

        // Set initial content type based on default format selection (original)
        let initialFormat = AudioExportFormat.allCases[safe: formatPopup.indexOfSelectedItem] ?? .original
        updateSavePanel(panel, format: initialFormat, sourceURL: file.url)

        // Update panel when format selection changes
        formatPopup.target = self
        formatPopup.action = #selector(formatPopupChanged(_:))
        // Store panel and source URL for callback access
        objc_setAssociatedObject(formatPopup, &AssociatedKeys.savePanel, panel, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(formatPopup, &AssociatedKeys.sourceURL, file.url, .OBJC_ASSOCIATION_RETAIN)

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else { return }

        let selectedFormat = AudioExportFormat.allCases[safe: formatPopup.indexOfSelectedItem] ?? .original
        let outputURL = normalizedExportURL(for: selectedURL, sourceURL: file.url, format: selectedFormat)

        mainWindowView.updateStatus("正在导出: \(outputURL.lastPathComponent)...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                switch selectedFormat {
                case .original:
                    if self.fileManager.fileExists(at: outputURL) {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                    try FileManager.default.copyItem(at: file.url, to: outputURL)
                case .mp3:
                    try self.convertAudioToMP3(inputURL: file.url, outputURL: outputURL)
                }

                DispatchQueue.main.async {
                    self.logger.info("✅ 音频导出成功: \(outputURL.lastPathComponent)")
                    self.mainWindowView.updateStatus("导出成功: \(outputURL.lastPathComponent)")
                    NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputURL.deletingLastPathComponent().path)
                    self.mainWindowView.refreshRecordedFiles()
                }
            } catch {
                DispatchQueue.main.async {
                    self.logger.error("❌ 音频导出失败: \(error.localizedDescription)")
                    self.mainWindowView.updateStatus("导出失败: \(error.localizedDescription)")
                    self.showExportError(error)
                }
            }
        }
    }

    private func normalizedExportURL(for selectedURL: URL, sourceURL: URL, format: AudioExportFormat) -> URL {
        let targetExtension = format.fileExtension ?? sourceURL.pathExtension.lowercased()
        if selectedURL.pathExtension.lowercased() == targetExtension {
            return selectedURL
        }
        return selectedURL.deletingPathExtension().appendingPathExtension(targetExtension)
    }

    // MARK: - Export Format Popup Callback

    @objc private func formatPopupChanged(_ sender: NSPopUpButton) {
        guard let panel = objc_getAssociatedObject(sender, &AssociatedKeys.savePanel) as? NSSavePanel,
              let sourceURL = objc_getAssociatedObject(sender, &AssociatedKeys.sourceURL) as? URL else { return }

        let selectedFormat = AudioExportFormat.allCases[safe: sender.indexOfSelectedItem] ?? .original
        updateSavePanel(panel, format: selectedFormat, sourceURL: sourceURL)
    }

    private func updateSavePanel(_ panel: NSSavePanel, format: AudioExportFormat, sourceURL: URL) {
        switch format {
        case .original:
            // Allow the source file's type or common audio types
            let sourceExt = sourceURL.pathExtension.lowercased()
            if let utType = UTType(filenameExtension: sourceExt) {
                panel.allowedContentTypes = [utType]
            } else {
                panel.allowedContentTypes = [.audio]
            }
            panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent
        case .mp3:
            if let mp3Type = UTType(filenameExtension: "mp3") {
                panel.allowedContentTypes = [mp3Type]
            } else {
                panel.allowedContentTypes = [.audio]
            }
            panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent
        }
    }

    private func convertAudioToMP3(inputURL: URL, outputURL: URL) throws {
        guard let ffmpegURL = findFFmpegExecutable() else {
            throw NSError(
                domain: "AudioRecord.Export",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "未找到 ffmpeg，无法转换 MP3。请先安装 ffmpeg（终端运行: brew install ffmpeg）。"]
            )
        }

        if fileManager.fileExists(at: outputURL) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-y",
            "-i", inputURL.path,
            "-vn",
            "-codec:a", "libmp3lame",
            "-b:a", "192k",
            outputURL.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        logger.info("执行转换命令: \(ffmpegURL.path) \(process.arguments?.joined(separator: " ") ?? "")")

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Sandbox may block Process execution
            logger.error("ffmpeg 进程启动失败（沙盒限制？）: \(error.localizedDescription)")
            throw NSError(
                domain: "AudioRecord.Export",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法启动 ffmpeg，可能是沙盒限制。请尝试导出为原格式（M4A/WAV），或关闭沙盒后重试。"]
            )
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "ffmpeg 转换失败"
            logger.error("ffmpeg 转换失败，退出码: \(process.terminationStatus), \(errorMessage)")
            throw NSError(
                domain: "AudioRecord.Export",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "MP3 转换失败：\(errorMessage)"]
            )
        }
    }

    private func findFFmpegExecutable() -> URL? {
        let candidatePaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private func showExportError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "导出失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // MARK: - Process Selection Persistence

    func mainWindowViewDidRequestMode(_ view: MainWindowView, mode: RecordingMode) {
        ensureAudioControllerInitialized()
        if currentRecordingMode != mode {
            currentRecordingMode = mode
            audioRecorderController?.setRecordingMode(mode)
            mainWindowView.updateMode(mode)
            saveRecordingMode(mode)
            switch mode {
            case .specificProcess:
                mainWindowView.updateStatus("特定进程录制模式：录制选中的进程")
            case .systemMixdown:
                mainWindowView.updateStatus("系统混音录制模式：录制系统所有音频输出")
            case .microphone:
                mainWindowView.updateStatus("麦克风模式已选中")
            }
        }
    }
    
    private func openSystemPreferences() {
        logger.info("打开系统偏好设置")
        PermissionManager.shared.openSystemPreferences()
        
        // 显示提示信息
        mainWindowView.updateStatus("已打开系统偏好设置，请允许麦克风和屏幕录制权限")
        
        // 3秒后重新检查权限
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.checkAudioPermissions()
        }
    }
    
    /// 加载可用的音频进程列表
    private func loadAvailableProcesses() {
        logger.info("开始加载可用音频进程列表")
        
        // 在主线程获取，避免 MainActor 隔离告警
        ensureAudioControllerInitialized()
        
        let processes: [AudioProcessInfo]
        if #available(macOS 14.4, *) {
            // Use AudioProcessEnumerator directly to avoid MainActor isolation issues
            let enumerator = AudioProcessEnumerator()
            processes = enumerator.getAvailableAudioProcesses()
        } else {
            logger.warning("CoreAudio Process Tap 需要 macOS 14.4+，无法加载进程列表")
            processes = []
        }
        
        self.availableProcesses = processes
        self.mainWindowView.updateProcessList(processes)
        self.mainWindowView.updateTracksDisplay()
        self.logger.info("已加载 \(processes.count) 个可用音频进程")
        
        // 不恢复上次的选择状态，完全重置
        logger.info("📝 完全重置状态，不恢复上次选择")
    }
    
    /// 启动时加载录音文件列表
    private func loadRecordedFilesOnStartup() {
        logger.info("开始加载录音文件列表...")
        
        // 在后台线程加载文件列表，避免阻塞UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let recordingsPath = documentsPath.appendingPathComponent("AudioRecordings")
            
            var files: [RecordedFileInfo] = []
            
            do {
                // 检查录音目录是否存在
                if !FileManager.default.fileExists(atPath: recordingsPath.path) {
                    DispatchQueue.main.async {
                        self.logger.info("录音目录不存在，将在首次录制时创建")
                        self.mainWindowView.updateStatus("准备就绪")
                    }
                    return
                }
                
                let fileURLs = try FileManager.default.contentsOfDirectory(at: recordingsPath, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
                
                for url in fileURLs {
                    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                    let fileSize = resourceValues.fileSize ?? 0
                    let creationDate = resourceValues.creationDate ?? Date()
                    
                    // 只处理音频文件
                    let pathExtension = url.pathExtension.lowercased()
                    guard ["wav", "m4a", "mp3"].contains(pathExtension) else {
                        continue
                    }
                    
                    // 获取音频文件时长
                    let duration = self.getAudioFileDuration(url: url)
                    
                    let fileInfo = RecordedFileInfo(
                        url: url,
                        name: url.lastPathComponent,
                        date: creationDate,
                        duration: duration,
                        size: Int64(fileSize)
                    )
                    
                    files.append(fileInfo)
                }
                
                // 按日期排序（最新的在前）
                files.sort { $0.date > $1.date }
                
            } catch {
                DispatchQueue.main.async {
                    self.logger.error("加载录制文件失败: \(error.localizedDescription)")
                    self.mainWindowView.updateStatus("加载录音文件失败")
                }
                return
            }
            
            // 在主线程更新UI
            DispatchQueue.main.async {
                self.logger.info("✅ 启动时加载了 \(files.count) 个录音文件")
                self.mainWindowView.updateStatus("已加载 \(files.count) 个录音文件")
                
                // 将文件列表传递给UI
                self.mainWindowView.loadRecordedFiles(files)
            }
        }
    }
    
    /// 获取音频文件时长
    private func getAudioFileDuration(url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            return Double(audioFile.length) / audioFile.fileFormat.sampleRate
        } catch {
            logger.warning("无法获取音频文件时长 \(url.lastPathComponent): \(error.localizedDescription)")
            return 0
        }
    }
}

// MARK: - Process Auto-Refresh (2s interval)
extension MainViewController {
    func startProcessRefreshTimer() {
        stopProcessRefreshTimer()
        processRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.silentRefreshProcessList()
        }
    }
    
    func stopProcessRefreshTimer() {
        processRefreshTimer?.invalidate()
        processRefreshTimer = nil
    }
    
    /// 静默刷新进程列表（不显示状态栏提示）
    private func silentRefreshProcessList() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var processes: [AudioProcessInfo] = []
            if #available(macOS 14.4, *) {
                // Use AudioProcessEnumerator directly to avoid MainActor isolation issues
                let enumerator = AudioProcessEnumerator()
                processes = enumerator.getAvailableAudioProcesses()
            }
            DispatchQueue.main.async {
                let oldCount = self.availableProcesses.count
                self.availableProcesses = processes
                if processes.count != oldCount {
                    self.mainWindowView.updateProcessList(processes)
                }
                self.checkSelectedProcessStillAlive()
            }
        }
    }
    
    /// 检查当前选中的录制目标进程是否还存在
    private func checkSelectedProcessStillAlive() {
        guard !selectedPIDs.isEmpty, isRecording else { return }
        let stillAlive = selectedPIDs.allSatisfy { pid in
            availableProcesses.contains { $0.pid == pid }
        }
        if !stillAlive {
            logger.warning("录制目标进程已退出，自动停止录制")
            stopRecording()
            DispatchQueue.main.async { [weak self] in
                self?.mainWindowView.updateStatus("目标进程已退出，录制已自动停止并保存")
                let alert = NSAlert()
                alert.messageText = "录制目标已退出"
                alert.informativeText = "你选中的进程已经退出，录制已自动停止。已录制的内容已保存。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        }
    }
}

// MARK: - Process Exit Monitoring
extension MainViewController {
    func setupProcessExitMonitoring() {
        processExitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  self.isRecording,
                  !self.selectedPIDs.isEmpty else { return }
            
            let terminatedPID = app.processIdentifier
            if self.selectedPIDs.contains(terminatedPID) {
                self.logger.warning("录制目标进程 PID=\(terminatedPID) 已退出")
                self.stopRecording()
                self.mainWindowView.updateStatus("目标进程已退出，录制已停止并保存")
            }
        }
    }
    
    func teardownProcessExitMonitoring() {
        if let observer = processExitObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            processExitObserver = nil
        }
    }
}

// MARK: - Sleep Prevention (IOPMAssertion)
extension MainViewController {
    /// 阻止系统睡眠（录制期间）
    func preventSleep() {
        guard !sleepAssertionActive else { return }
        let reason = "Audio recording in progress" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )
        if result == kIOReturnSuccess {
            sleepAssertionActive = true
            logger.info("已阻止系统睡眠（IOPMAssertion）")
        } else {
            logger.warning("阻止系统睡眠失败，错误码: \(result)")
        }
    }
    
    /// 允许系统睡眠（录制结束后）
    func allowSleep() {
        guard sleepAssertionActive else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionActive = false
        sleepAssertionID = 0
        logger.info("已允许系统睡眠")
    }
}

// MARK: - Disk Space Monitor
extension MainViewController {
    /// 启动磁盘空间监控（录制期间每 10 秒检测）
    func startDiskMonitor() {
        stopDiskMonitor()
        diskMonitorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkDiskSpaceDuringRecording()
        }
    }
    
    /// 停止磁盘空间监控
    func stopDiskMonitor() {
        diskMonitorTimer?.invalidate()
        diskMonitorTimer = nil
    }
    
    /// 录制中磁盘空间检测
    private func checkDiskSpaceDuringRecording() {
        guard isRecording else {
            stopDiskMonitor()
            return
        }
        
        if !fileManager.hasSufficientDiskSpace() {
            let available = fileManager.getAvailableDiskSpace().map { fileManager.formatDiskSpace($0) } ?? "未知"
            logger.warning("录制中磁盘空间不足: \(available)，自动停止录制")
            
            // 先停止录制
            stopRecording()
            
            // 弹窗提示
            DispatchQueue.main.async { [weak self] in
                let alert = NSAlert()
                alert.messageText = "磁盘空间不足，录制已自动停止"
                alert.informativeText = "当前可用空间仅 \(available)，已保存已录制的内容。请清理磁盘空间后再继续录制。"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "确定")
                alert.runModal()
                self?.mainWindowView.updateStatus("磁盘空间不足，录制已停止")
            }
        }
    }
}

// MARK: - Crash Recovery
extension MainViewController {
    /// 检查并恢复上次未完成的录制（由 AppDelegate 调用）
    func checkAndRecoverUnfinishedRecording() {
        guard let unfinishedURL = fileManager.checkForUnfinishedRecording() else {
            return
        }
        
        let fileName = unfinishedURL.lastPathComponent
        let fileSize = fileManager.getFileSize(at: unfinishedURL).map { fileManager.formatFileSize($0) } ?? "未知"
        
        let alert = NSAlert()
        alert.messageText = "发现未保存的录音"
        alert.informativeText = "上次录制可能因异常中断，发现未保存的录音文件（\(fileName)，大小 \(fileSize)）。是否恢复？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "丢弃")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 恢复
            if let recoveredURL = fileManager.recoverRecording(from: unfinishedURL) {
                logger.info("录制文件已恢复: \(recoveredURL.lastPathComponent)")
                mainWindowView.updateStatus("已恢复录音: \(recoveredURL.lastPathComponent)")
                // 刷新文件列表
                loadRecordedFilesOnStartup()
            } else {
                mainWindowView.updateStatus("恢复失败")
            }
        } else {
            // 丢弃
            try? FileManager.default.removeItem(at: unfinishedURL)
            logger.info("用户选择丢弃未完成的录制")
        }
    }
}

// MARK: - Editor Management (V2.1 — Session Pool + Cross-dissolve)
extension MainViewController {

    private var currentEditor: EditorViewController? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.editorKey) as? EditorViewController }
        set { objc_setAssociatedObject(self, &AssociatedKeys.editorKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private struct AssociatedKeys {
        nonisolated(unsafe) static var editorKey: UInt8 = 0
        nonisolated(unsafe) static var savePanel: UInt8 = 0
        nonisolated(unsafe) static var sourceURL: UInt8 = 0
    }

    /// 会话管理器
    private var sessionManager: EditorSessionManager { EditorSessionManager.shared }

    func enterEditor(file: RecordedFileInfo) {
        guard !isRecording else {
            mainWindowView.updateStatus("录制中不能进入编辑器")
            return
        }

        // 如果已在编辑同一文件，直接返回
        if let current = currentEditor, current.file.url == file.url {
            logger.info("已在编辑同一文件，忽略: \(file.name)")
            return
        }

        // 停止播放
        if playbackPlayer != nil { stopPlayback() }

        // 保存当前编辑器状态到 session
        saveCurrentEditorState()

        // 获取或创建 session
        let session = sessionManager.session(for: file)

        // 创建新编辑器（使用缓存的 session 数据）
        let editor = EditorViewController(file: file, session: session)
        editor.delegate = self

        // Cross-dissolve 切换
        let previousEditor = currentEditor
        currentEditor = editor

        if previousEditor != nil {
            // 已在编辑器模式：cross-dissolve 切换（不退出编辑模式）
            mainWindowView.crossDissolveEditor(to: editor.editorView)
        } else {
            // 首次进入编辑器：正常进入
            mainWindowView.showEditor(editor.editorView)
        }

        mainWindowView.updateStatus("编辑: \(file.name)")
        logger.info("进入编辑器: \(file.name) (session pool: \(sessionManager.sessionCount))")
    }

    func exitEditor() {
        saveCurrentEditorState()
        currentEditor = nil
        mainWindowView.hideEditor()
        mainWindowView.updateStatus("准备就绪")
        logger.info("退出编辑器")
    }

    /// 保存当前编辑器的视图状态到 session
    private func saveCurrentEditorState() {
        guard let editor = currentEditor else { return }
        if let session = sessionManager.existingSession(for: editor.file.url) {
            session.viewportState = editor.currentViewportState()
            session.selectionRange = editor.currentSelectionRange()
        }
    }
}

// MARK: - EditorViewControllerDelegate
extension MainViewController: EditorViewControllerDelegate {
    func editorDidSave(_ editor: EditorViewController, file: RecordedFileInfo) {
        mainWindowView.updateStatus("保存完成: \(file.name)")
        // 刷新文件列表
        loadRecordedFilesOnStartup()
    }
    
    func editorDidCancel(_ editor: EditorViewController) {
        exitEditor()
    }
}

// MARK: - AVAudioPlayerDelegate
extension MainViewController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.logger.info("播放完成: \(flag)")
            self?.finishPlayback()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.logger.error("播放解码失败: \(error?.localizedDescription ?? "未知错误")")
            self?.mainWindowView.updateStatus("播放失败: \(error?.localizedDescription ?? "未知错误")")
            self?.finishPlayback(resetProgress: true)
        }
    }
}
