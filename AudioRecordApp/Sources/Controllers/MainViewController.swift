import Cocoa
import Foundation
import AVFoundation
import IOKit.pwr_mgt
import ObjectiveC
import UniformTypeIdentifiers

/// 主视图控制器 (V2.0: .arlock 加密 + 解密播放 + 沙盒容器)
class MainViewController: NSViewController {
    
    // MARK: - Properties
    private var mainWindowView: MainWindowView!
    var audioRecorderController: AudioRecorderController!
    private let logger = Logger.shared
    private let fileManager = FileManagerUtils.shared
    private let encryptor = AudioFileEncryptor.shared
    private let exportService = ExportService.shared
    
    // Recording state
    private var isRecording = false
    /// INFRA-006: 自验 lite 通道待跑标志（触发器 "N uitest" 置位，enterEditor 消费）
    private var pendingLiteUITest = false
    private var recordingStartTime: Date?
    private var captureStartTime: Date?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private var lastRecordedFile: RecordedFileInfo?
    private var selectedPlaybackFile: RecordedFileInfo?
    private var currentPlaybackFile: RecordedFileInfo?
    private var playbackPlayer: AVAudioPlayer?
    private var isPlaybackPaused = false
    // 初始值与侧边栏默认保持一致（SidebarView 默认 selectedPIDs=[] → 系统混音）
    private var currentRecordingMode: RecordingMode = .systemMixdown
    private let userDefaults = UserDefaults.standard
    private let recordingModeKey = "lastRecordingMode"
    private var currentFormat: AudioFormat = .m4a
    private var playbackDuration: TimeInterval = 0
    
    // V2.0: 播放临时文件追踪
    private var playbackTempURL: URL?
    
    // 进程列表相关
    private var availableProcesses: [AudioProcessInfo] = []
    private var selectedProcesses: Set<AudioProcessInfo> = []
    private var selectedPIDs: [pid_t] = []
    
    // 混音设置
    private var shouldMixAudio: Bool = false
    
    // 进程列表自动刷新
    private var processRefreshTimer: Timer?
    private var processExitObserver: Any?
    
    // 睡眠阻止
    private var sleepAssertionID: IOPMAssertionID = 0
    private var sleepAssertionActive = false
    
    // 磁盘空间监控
    private var diskMonitorTimer: Timer?
    
    // BUG-1 修复：录制期间峰值电平最大值（用于静音/无效录音拦截）
    private var maxPeakDuringRecording: Float = 0

    // FEAT-001 S1: 实时转写面板（录制中显示在主窗口下方）
    private lazy var liveTranscriptPanel = LiveTranscriptPanel()

    /// FEAT-003 (2026-10-13 老板指令「实时翻译要下掉先」)：实时转写浮窗开关。
    /// false = 浮窗不弹（本单交付态）；true = 恢复 FEAT-001 S1 原行为。
    /// 转写主链路（识别→落盘 .atranscript.json→导出 txt）与本开关无关，始终运行。
    private static let enableLiveTranscriptPanel = false
    
    // LOOP-05: UI 测试 mock 模式（XCUITest 以 --ui-testing 启动参数拉起）
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    
    // MARK: - Lifecycle
    override func loadView() {
        // 初始 frame 必须与窗口 contentRect 一致（1200x750），否则设置
        // contentViewController 时 AppKit 会把窗口缩小到 view 的 frame（0x0），
        // 被 minSize 钳制后表现为「启动时窗口先小后大」的跳变。
        mainWindowView = MainWindowView(frame: NSRect(x: 0, y: 0, width: 1200, height: 750))
        mainWindowView.delegate = self
        view = mainWindowView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("主视图控制器 V2.0 开始加载（加密模式）")
        setupInitialState()
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
            DispatchQueue.main.async { self?.mainWindowView.updateLevel(level) }
        }

        audioRecorderController.onPeakLevel = { [weak self] peakLevel in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.mainWindowView.updatePeakLevel(peakLevel)
                if self.isRecording && peakLevel > self.maxPeakDuringRecording {
                    self.maxPeakDuringRecording = peakLevel
                }
            }
        }
        
        // BUG-1 修复：录制态由管线真正启动回调驱动
        audioRecorderController.onRecordingStarted = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.isRecording, self.captureStartTime == nil else { return }
                self.logger.info("🎙️ 管线确认启动，进入录制态")
                self.startTimer()
                self.mainWindowView.updateRecordingState(.recording)

                // FEAT-001 S1: 绑定首个录制器的 PCM 旁路（多录制器只转写第一个；
                // 混音模式第一个即混合录制器，天然覆盖 麦克风+系统 双源）
                if #available(macOS 26.0, *) {
                    if let recorder = self.audioRecorderController.getCurrentRecorder() {
                        LiveTranscriptionCoordinator.shared.bind(recorder: recorder)
                    }
                }
            }
        }
        
        audioRecorderController.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                self?.mainWindowView.updateStatus(status)
                if status.containsStatusFailure() {
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
            DispatchQueue.main.async { self?.finishPlayback() }
        }
        
        audioRecorderController.setRecordingMode(currentRecordingMode)
        audioRecorderController.setAudioFormat(currentFormat)
    }
    
    private func setupInitialState() {
        loadLastRecordingMode()
        loadSettingsFromDefaults()
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSettingsChanged),
            name: .settingsChanged, object: nil
        )
        
        mainWindowView.updateMode(currentRecordingMode)
        mainWindowView.updateRecordingState(.idle)
        mainWindowView.updateStatus("准备就绪".localized)
        
        startProcessRefreshTimer()
        setupProcessExitMonitoring()
        loadRecordedFilesOnStartup()
        
        logger.cleanupOldLogs()
        
        // V2.0: 清理遗留临时文件
        fileManager.cleanupTempFiles()
        fileManager.cleanupLegacyTempAudioFiles()
    }
    
    /// 静默权限检查
    private func checkAudioPermissionsSilently() {
        let permissions = PermissionManager.shared.checkAllPermissions()
        switch permissions.microphone {
        case .granted: logger.info("麦克风权限已授予")
        case .denied: logger.info("麦克风权限被拒绝")
        case .notDetermined: logger.info("麦克风权限未确定")
        case .restricted: logger.info("麦克风权限受限制")
        }
        switch permissions.systemAudioCapture {
        case .granted: logger.info("屏幕录制权限已授予")
        case .denied: logger.info("屏幕录制权限被拒绝")
        case .notDetermined: logger.info("屏幕录制权限未确定")
        case .restricted: logger.info("屏幕录制权限受限制")
        }
        startPermissionMonitoring()
    }
    
    private func startPermissionMonitoring() {
        PermissionManager.shared.startPermissionMonitoring { [weak self] type, status in
            DispatchQueue.main.async { self?.handlePermissionStatusChange(type: type, status: status) }
        }
    }
    
    private func handlePermissionStatusChange(type: PermissionManager.PermissionType, status: PermissionManager.PermissionStatus) {
        guard isRecording else { return }
        switch type {
        case .microphone:
            if case .denied = status, shouldMixAudio {
                mainWindowView.updateStatus("麦克风权限被拒绝，将仅录制系统/应用声音".localized)
            }
        case .systemAudioCapture:
            if case .denied = status {
                mainWindowView.updateStatus("系统音频捕获权限被拒绝，请点击允许或在设置中开启".localized)
            }
        }
    }
    
    // MARK: - Recording Management

    /// FIX-004 诊断自测（临时）：无头驱动一轮真实录音——启动 N 秒后自动停。
    /// 用法：Loocap --selftest-record 5（3 秒后开始，录 5 秒，自动停）
    func runSelftestRecording(seconds: Int, mixMic: Bool = false, mixMicMidway: Bool = false, uitest: Bool = false) {
        logger.info("🔬 [FIX004] selftest: 开始录音（\(seconds)s 后自动停, mixMic=\(mixMic), mixMidway=\(mixMicMidway), uitest=\(uitest)）")
        pendingLiteUITest = uitest
        if mixMic {
            // FIX-006 复现钩子：等价手点「同时录入麦克风」，走 MixedAudioRecorder 混录链路
            mainWindowView.setMicrophoneMixEnabled(true)
        }
        startRecording()
        if mixMicMidway {
            // FIX-007 回归钩子：纯系统起录，5s 后切「同时录入麦克风」开——录音中动态注入
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self, self.isRecording else { return }
                self.logger.info("🔬 [FIX007] selftest: 录音中切麦克风开")
                self.mainWindowView.setMicrophoneMixEnabled(true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
            self?.logger.info("🔬 [FIX004] selftest: 停止录音")
            self?.stopRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        
        // LOOP-05: UI 测试模式——模拟录制状态机，不启动真实管线（mock PID 无真实音频）
        if isUITesting {
            logger.info("🧪 UI 测试模式：模拟启动录制")
            isRecording = true
            recordingStartTime = Date()
            maxPeakDuringRecording = 0
            mainWindowView.updateRecordingState(.preparing)
            mainWindowView.updateStatus("准备录制…".localized)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, self.isRecording else { return }
                self.startTimer()
                self.mainWindowView.updateRecordingState(.recording)
            }
            return
        }
        
        if !fileManager.hasSufficientDiskSpace() {
            let available = fileManager.getAvailableDiskSpace().map { fileManager.formatDiskSpace($0) } ?? "未知".localized
            let alert = NSAlert()
            alert.messageText = "磁盘空间不足".localized
            alert.informativeText = "当前可用空间仅 %@，可能无法完成录制。建议清理磁盘后再试。".localized(available)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "仍然录制".localized)
            alert.addButton(withTitle: "取消".localized)
            if alert.runModal() == .alertSecondButtonReturn { return }
        }
        
        ensureAudioControllerInitialized()
        
        let wantMic = mainWindowView.isMicrophoneSourceSelected()
        let wantSystemMixdown = mainWindowView.isSystemAudioSourceSelected()
        let wantSpecificProcess = !selectedPIDs.isEmpty
        
        guard wantSystemMixdown || wantSpecificProcess else {
            mainWindowView.updateStatus("请选择录制目标：全部系统声音或某个应用".localized)
            return
        }
        
        let actualWantMic = shouldMixAudio ? false : wantMic
        
        checkPermissionsBeforeRecording(
            wantMic: actualWantMic, wantSystem: wantSystemMixdown,
            wantProcess: wantSpecificProcess, mixAudio: shouldMixAudio
        ) { [weak self] granted in
            guard let self = self, granted else {
                self?.handleRecordingFailure(); return
            }
            
            if wantSystemMixdown || wantSpecificProcess {
                PermissionManager.shared.requestSystemAudioCapturePermission { _ in }
            }
            if self.shouldMixAudio {
                PermissionManager.shared.requestMicrophonePermission { _ in }
            }
            
            self.isRecording = true
            self.recordingStartTime = Date()
            self.maxPeakDuringRecording = 0
            UXEventLog.shared.action("start_recording", detail: [
                "mode": self.actualRecordingMode.rawValue,
                "format": self.currentFormat.rawValue,
                "mix_mic": self.shouldMixAudio,
                "target_pid": self.selectedPIDs.first.map { Int($0) } ?? 0,
            ])
            UXEventLog.shared.module("Recording", "start", detail: [
                "mode": self.actualRecordingMode.rawValue,
                "format": self.currentFormat.rawValue,
            ])
            self.mainWindowView.updateRecordingState(.preparing)
            self.mainWindowView.updateStatus("准备录制…".localized)
            self.preventSleep()
            self.startDiskMonitor()
            self.audioRecorderController.setAudioFormat(self.currentFormat)
            
            self.audioRecorderController.startMultiSourceRecording(
                wantMic: actualWantMic, wantSystem: wantSystemMixdown,
                wantProcess: wantSpecificProcess, targetPID: self.selectedPIDs.first,
                mixAudio: self.shouldMixAudio
            )

            // FEAT-001 S1: 实时转写——预热会话 + 展示 live 文本条
            if #available(macOS 26.0, *) {
                let coordinator = LiveTranscriptionCoordinator.shared
                // FEAT-003: 实时转写浮窗下掉（改回 true 一键恢复），转写主链路不受影响——
                // coordinator 照常跑，文稿仍随录音落盘 <uuid>.atranscript.json（导出 txt 数据源）
                if Self.enableLiveTranscriptPanel {
                    coordinator.onLiveText = { [weak self] finalized, volatile in
                        self?.liveTranscriptPanel.update(finalized: finalized, volatile: volatile)
                    }
                }
                coordinator.onError = { [weak self] message in
                    self?.mainWindowView.updateStatus("实时转写不可用: %@".localized(message))
                }
                coordinator.start()
                if Self.enableLiveTranscriptPanel {
                    self.liveTranscriptPanel.show(for: self.view.window)
                }
                UXEventLog.shared.module("Transcription", "live_start", detail: ["locale": "auto"])
            }
            
            // V2.0: 标记录制目录（用于 crash 恢复扫描 temp 目录）
            self.fileManager.markRecordingStarted(fileURL: self.fileManager.getRecordingsDirectory())
            // BUG-1 修复：删除 0.3s 定时器假装进入 recording 的逻辑。
            // 录制态由 audioRecorderController.onRecordingStarted（管线真正启动）驱动。
        }
    }
    
    private func checkPermissionsBeforeRecording(
        wantMic: Bool, wantSystem: Bool, wantProcess: Bool, mixAudio: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        let needMicPermission = wantMic || mixAudio
        
        if needMicPermission {
            mainWindowView.updateStatus("正在请求麦克风权限...".localized)
            PermissionManager.shared.requestMicrophonePermission { [weak self] status in
                DispatchQueue.main.async {
                    switch status {
                    case .granted: completion(true)
                    case .denied, .restricted:
                        if !wantSystem && !wantProcess {
                            self?.mainWindowView.updateStatus("麦克风权限被拒绝".localized)
                            completion(false)
                        } else { completion(true) }
                    case .notDetermined:
                        self?.mainWindowView.updateStatus("麦克风权限未确定，请重试".localized)
                        completion(false)
                    }
                }
            }
        } else if wantSystem || wantProcess {
            DispatchQueue.main.async { completion(true) }
        } else {
            DispatchQueue.main.async { completion(false) }
        }
    }
    
    private func stopRecording() {
        // BUG-1 修复：停止按钮无条件可达——只要点过录制（recordingStartTime 非空）就允许停止，
        // 不受 isRecording 拦截（防状态不一致时 UI 停在录制态但停止按钮失灵）
        guard recordingStartTime != nil else { return }
        
        // LOOP-05: UI 测试模式——模拟停止，不触碰真实管线
        if isUITesting {
            logger.info("🧪 UI 测试模式：模拟停止录制")
            isRecording = false
            recordingStartTime = nil
            stopTimer()
            stopDiskMonitor()
            allowSleep()
            fileManager.markRecordingFinished()
            mainWindowView.updateRecordingState(.idle)
            mainWindowView.updateStatus("准备就绪".localized)
            return
        }
        
        logger.info("停止录制")
        let elapsed = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        UXEventLog.shared.action("stop_recording", detail: ["elapsed_sec": elapsed])
        UXEventLog.shared.module("Recording", "stop", elapsedMs: elapsed * 1000, detail: ["duration_sec": elapsed])
        isRecording = false
        mainWindowView.updateRecordingState(.stopping)
        mainWindowView.updateStatus("正在停止录制…".localized)
        stopTimer()
        stopDiskMonitor()
        allowSleep()
        audioRecorderController.stopRecording()

        // FEAT-001 S1: 结束实时转写并收集文稿（暂存 coordinator，加密管线落盘）
        if #available(macOS 26.0, *) {
            LiveTranscriptionCoordinator.shared.finishAndCollect()
            liveTranscriptPanel.dismiss()
        }
    }
    
    // MARK: - Recording Complete + Encryption Pipeline (V2.0)
    
    private func handleRecordingComplete(_ recording: AudioRecording) {
        let peak = maxPeakDuringRecording
        maxPeakDuringRecording = 0
        
        // BUG-1 修复：0 秒/静音录音在落盘前拦截（不进入加密管线）
        // FIX-014：uitest 自验序列豁免峰值检查（仅 duration 拦截保留）——深夜/系统静音下
        // 外放声源不可达（实测 peak=0.0028 纯底噪），峰值拦截会静默丢弃自验录音导致 lite
        // 断链；自验有效性由 frames≈N 断言承担，混录链路「真在收音」由首帧 peak 日志留痕
        if recording.duration < 1.0 || (peak < 0.01 && !pendingLiteUITest) {
            logger.warning("拦截无效录音: 时长=\(recording.duration)s, 峰值电平=\(peak)")
            fileManager.markRecordingFinished()
            SecureDelete.deleteFile(at: recording.fileURL)
            mainWindowView.updateRecordingState(.idle)
            mainWindowView.updateStatus("录制时间过短或内容为空，已取消保存".localized)

            // FEAT-001 S1: 无效录音同时丢弃实时转写
            if #available(macOS 26.0, *) {
                LiveTranscriptionCoordinator.shared.cancel()
                liveTranscriptPanel.dismiss()
            }
            return
        }
        
        mainWindowView.updateRecordingState(.idle)
        mainWindowView.updateStatus("正在保存…".localized)
        fileManager.markRecordingFinished()
        
        logger.info("录制完成: \(recording.fileName), 时长: \(recording.formattedDuration)")
        UXEventLog.shared.module("Recording", "captured", detail: [
            "file": recording.fileName,
            "duration_sec": recording.duration,
            "channels": recording.channels,
            "sample_rate": recording.sampleRate,
            "mode": recording.recordingMode,
        ])
        
        // V2.0: 加密管线（异步执行，避免阻塞 UI）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.encryptAndFinalizeRecording(recording)
        }
    }
    
    /// V2.0: 加密管线 — 录完 → 加密 → 写 .arlock → 删除临时文件
    private func encryptAndFinalizeRecording(_ recording: AudioRecording) {
        do {
            // 1. 生成 recordingUUID
            let recordingUUID = fileManager.generateRecordingUUID()
            let originalFileURL = recording.fileURL

            // 2. 读原始 M4A 数据（录制器已经产出了 M4A）
            let audioData = try Data(contentsOf: originalFileURL)

            // 3. V2.1: 计算 sourceApp（混音用 `+` 连接多进程名）和显示名
            let sourceAppName = computeSourceAppName()
            let displayTitle = defaultDisplayName(
                sourceApp: sourceAppName,
                sourceType: recording.recordingMode,
                date: recording.createdAt
            )

            // 4. 构造元数据
            let dateFormatter = ISO8601DateFormatter()
            let metadata = ArlockMetadata(
                title: displayTitle,
                durationSec: recording.duration,
                sampleRate: recording.sampleRate,
                channels: recording.channels,
                bitsPerSample: 16,
                audioCodec: "aac",
                createdAt: dateFormatter.string(from: recording.createdAt),
                sourceType: recording.recordingMode,
                sourceApp: sourceAppName
            )

            // 5. 加密并写入 .arlock
            let arlockURL = fileManager.getRecordingFileURL(uuid: recordingUUID)
            try encryptor.encryptAndWrite(audioData: audioData, metadata: metadata, recordingUUID: recordingUUID, outputURL: arlockURL)

            // 5.5 FEAT-001 S1 + FIX-012: 实时转写文稿落盘改为双向握手——
            // 此处只登记 .arlock 落点，finish 完成后由 coordinator 触发落盘；
            // 旧实现此处同步读 collectedTranscript，finish 慢于管线（实测差 83ms）时文稿永久丢失
            if #available(macOS 26.0, *) {
                LiveTranscriptionCoordinator.shared.registerTranscriptDestination(arlockURL)
            }

            // 6. 安全删除原始临时 M4A
            SecureDelete.deleteFile(at: originalFileURL)

            // 7. 创建 RecordedFileInfo 并更新 UI
            let fileSize = fileManager.getFileSize(at: arlockURL) ?? 0
            let fileInfo = RecordedFileInfo(
                url: arlockURL,
                name: displayTitle,
                date: recording.createdAt,
                duration: metadata.durationSec,
                size: fileSize
            )

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastRecordedFile = fileInfo
                self.selectedPlaybackFile = fileInfo
                self.mainWindowView.addRecordedFile(fileInfo)
                self.mainWindowView.updateStatus("录制完成: %@".localized(displayTitle))

                // 进入编辑器
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.enterEditor(file: fileInfo)
                }
            }

            logger.info("加密保存完成: \(arlockURL.lastPathComponent), title=\(displayTitle)")
            UXEventLog.shared.module("Encrypt", "write", ok: true, detail: ["title": displayTitle, "uuid": recordingUUID])
            UXEventLog.shared.artifact("arlock_created", path: arlockURL.path, detail: [
                "title": displayTitle,
                "duration_sec": metadata.durationSec,
                "codec": metadata.audioCodec,
            ])

        } catch {
            logger.error("加密保存失败: \(error.localizedDescription)")
            UXEventLog.shared.module("Encrypt", "write", ok: false, detail: ["error": error.localizedDescription])
            DispatchQueue.main.async { [weak self] in
                self?.mainWindowView.updateStatus("保存失败: %@".localized(error.localizedDescription))

                // 保留原始 M4A 文件作为兜底
                if FileManager.default.fileExists(atPath: recording.fileURL.path) {
                    self?.mainWindowView.updateStatus("已保留原始录音文件".localized)
                }
            }
        }
    }

    // MARK: - V2.1: 显示名生成

    /// 计算当前选中进程的名字（混音场景用 `+` 连接多进程）
    private func computeSourceAppName() -> String {
        let pids = selectedPIDs
        if pids.isEmpty { return "" }
        // 保持用户选择的顺序（按 selectedPIDs 数组顺序）
        let nameByPid = Dictionary(uniqueKeysWithValues: availableProcesses.map { ($0.pid, $0.name) })
        let names = pids.compactMap { nameByPid[$0] }
        return names.joined(separator: "+")
    }

    /// 生成显示名：`进程名_YYYYMMDD_HHmmss`（混音：`A+B_YYYYMMDD_HHmmss`）
    /// sourceApp 为空时按 sourceType 兜底（系统混音/麦克风/应用声音）
    private func defaultDisplayName(sourceApp: String, sourceType: String, date: Date) -> String {
        let timestamp = Self.filenameTimestamp(from: date)
        if !sourceApp.isEmpty {
            return "\(sourceApp)_\(timestamp)"
        }
        switch sourceType {
        case "microphone":         return "麦克风_%@".localized(timestamp)
        case "systemMixdown",
             "systemAudio":        return "系统混音_%@".localized(timestamp)
        case "specificProcess":    return "应用声音_%@".localized(timestamp)
        case "recovered":          return "已恢复_%@".localized(timestamp)
        default:                   return "录音_%@".localized(timestamp)
        }
    }

    /// 文件名时间戳（线程安全的静态 formatter）
    private static func filenameTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    // MARK: - Timer Management
    private func startTimer() {
        captureStartTime = Date()
        updateTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        captureStartTime = nil
        mainWindowView.updateTimer("00:00.00")
    }
    
    private func handleRecordingFailure() {
        UXEventLog.shared.module("Recording", "fail", ok: false)
        isRecording = false; recordingStartTime = nil
        stopTimer(); stopDiskMonitor(); allowSleep()
        fileManager.markRecordingFinished()
        mainWindowView.updateRecordingState(.idle)

        // FEAT-001 S1: 录制失败同时放弃实时转写
        if #available(macOS 26.0, *) {
            LiveTranscriptionCoordinator.shared.cancel()
            liveTranscriptPanel.dismiss()
        }
    }
    
    private func updateTimer() {
        guard let startTime = captureStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let hours = Int(elapsed) / 3600
        let minutes = Int(elapsed) % 3600 / 60
        let seconds = Int(elapsed) % 60
        let centiseconds = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 100)
        let timeString = hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
        mainWindowView.updateTimer(timeString)
    }
    
    // MARK: - Playback Management (V2.0: decrypt → temp → play → cleanup)
    
    private func playRecording() {
        guard !isRecording else {
            mainWindowView.updateStatus("录制中不能播放音频".localized); return
        }
        
        if let player = playbackPlayer, currentPlaybackFile?.url == selectedPlaybackFile?.url {
            if player.isPlaying { pausePlayback() } else { resumePlayback() }
            return
        }
        
        guard let file = selectedPlaybackFile else {
            mainWindowView.updateStatus("请先选择要播放的文件".localized); return
        }
        
        startPlayback(file: file)
    }
    
    private func selectPlaybackFile(_ file: RecordedFileInfo) {
        UXEventLog.shared.action("select_file", detail: ["file": file.name, "duration_sec": file.duration, "size": file.size])
        if currentPlaybackFile?.url != file.url { stopPlayback(resetDisplay: false) }
        selectedPlaybackFile = file
        playbackDuration = file.duration
        mainWindowView.updateStatus("已选择: %@".localized(file.name))
        mainWindowView.updatePlaybackDisplay(fileName: file.name, currentTime: 0, duration: file.duration, isPlaying: false, isPaused: false)
    }
    
    /// V2.0: 播放 — 解密 .arlock → 临时 .m4a → AVAudioPlayer
    /// FIX-003: initialProgress 非 nil 时解密完成后从该进度（0.0~1.0）起播（异步链路，seek 不能在调用侧同步写）
    private func startPlayback(file: RecordedFileInfo, initialProgress: Double? = nil) {
        guard fileManager.fileExists(at: file.url) else {
            mainWindowView.updateStatus("播放失败：文件不存在".localized); return
        }

        stopPlayback(resetDisplay: false)

        // V2.0: 异步解密（长录音可能耗时）
        mainWindowView.updateStatus("正在加载…".localized)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // 解密 .arlock → AAC Data
                let (audioData, _) = try self.encryptor.decrypt(from: file.url)

                // 写临时 .m4a
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent("\(AudioCryptoConfig.TempFilePattern.playbackPrefix)\(UUID().uuidString).\(AudioCryptoConfig.TempFilePattern.m4aExtension)")
                try audioData.write(to: tempURL, options: .atomic)

                // 清理上一个播放临时文件
                if let oldTemp = self.playbackTempURL {
                    SecureDelete.deleteFile(at: oldTemp)
                }
                self.playbackTempURL = tempURL

                DispatchQueue.main.async {
                    self.playDecryptedFile(tempURL, file: file, initialProgress: initialProgress)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    if let cryptoErr = error as? CryptoError {
                        switch cryptoErr {
                        case .decryptionFailed:
                            self?.mainWindowView.updateStatus("播放失败：文件不属于本设备或已损坏".localized)
                            self?.showAlert(title: "无法播放".localized, message: "此录音文件不属于本设备，或文件已损坏。".localized)
                        default:
                            self?.mainWindowView.updateStatus("播放失败: %@".localized(error.localizedDescription))
                        }
                    } else {
                        self?.mainWindowView.updateStatus("播放失败: %@".localized(error.localizedDescription))
                    }
                }
            }
        }
    }
    
    private func playDecryptedFile(_ url: URL, file: RecordedFileInfo, initialProgress: Double? = nil) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.isMeteringEnabled = true
            player.prepareToPlay()

            playbackPlayer = player
            currentPlaybackFile = file
            selectedPlaybackFile = file
            playbackDuration = player.duration > 0 ? player.duration : file.duration
            isPlaybackPaused = false

            // FIX-003: 冷启动 seek — 在 play() 前定位到点击进度（避免先从头出声再跳）
            if let progress = initialProgress, playbackDuration > 0 {
                player.currentTime = player.duration * min(max(progress, 0), 1)
            }

            player.play()
            UXEventLog.shared.module("Playback", "start", ok: true, detail: ["file": file.name, "duration_sec": playbackDuration, "initial_sec": initialProgress.map { player.duration * $0 } ?? 0])
            mainWindowView.updateRecordingState(.playing)
            mainWindowView.updateStatus("正在播放: %@".localized(file.name))
            mainWindowView.updatePlaybackDisplay(fileName: file.name, currentTime: player.currentTime, duration: playbackDuration, isPlaying: true, isPaused: false)
            startPlaybackTimer()
            logger.info("播放启动: \(file.name)")
        } catch {
            UXEventLog.shared.module("Playback", "start", ok: false, detail: ["file": file.name, "error": error.localizedDescription])
            mainWindowView.updateStatus("播放失败: %@".localized(error.localizedDescription))
            logger.error("播放失败: \(error.localizedDescription)")
            finishPlayback(resetProgress: true)
        }
    }
    
    private func pausePlayback() {
        guard let player = playbackPlayer, player.isPlaying else { return }
        UXEventLog.shared.action("pause_playback")
        player.pause(); isPlaybackPaused = true
        stopPlaybackTimer()
        mainWindowView.updateRecordingState(.playing)
        mainWindowView.updatePlaybackDisplay(fileName: currentPlaybackFile?.name, currentTime: player.currentTime, duration: playbackDuration, isPlaying: false, isPaused: true)
    }
    
    private func resumePlayback() {
        guard let player = playbackPlayer, let file = currentPlaybackFile else { return }
        UXEventLog.shared.action("resume_playback")
        player.play(); isPlaybackPaused = false
        mainWindowView.updateRecordingState(.playing)
        mainWindowView.updatePlaybackDisplay(fileName: file.name, currentTime: player.currentTime, duration: playbackDuration, isPlaying: true, isPaused: false)
        startPlaybackTimer()
    }
    
    private func stopPlayback() { stopPlayback(resetDisplay: true) }
    
    private func stopPlayback(resetDisplay: Bool) {
        stopPlaybackTimer()
        playbackPlayer?.stop()
        playbackPlayer = nil
        currentPlaybackFile = nil
        isPlaybackPaused = false
        audioRecorderController?.stopPlayback()
        mainWindowView.updateRecordingState(.idle)
        
        if resetDisplay, let file = selectedPlaybackFile {
            mainWindowView.updatePlaybackDisplay(fileName: file.name, currentTime: 0, duration: file.duration, isPlaying: false, isPaused: false)
        }
        
        // V2.0: 清理播放临时文件
        if let tempURL = playbackTempURL {
            SecureDelete.deleteFile(at: tempURL)
            playbackTempURL = nil
        }
    }
    
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlaybackTimer()
        }
    }
    
    private func stopPlaybackTimer() { playbackTimer?.invalidate(); playbackTimer = nil }
    
    private func updatePlaybackTimer() {
        guard let player = playbackPlayer, let file = currentPlaybackFile else { return }
        let currentTime = min(player.currentTime, playbackDuration)
        mainWindowView.updateTimer(formatTransportTime(currentTime))
        mainWindowView.updatePlaybackDisplay(fileName: file.name, currentTime: currentTime, duration: playbackDuration, isPlaying: player.isPlaying, isPaused: isPlaybackPaused)
        player.updateMeters()
        let leftDB = player.averagePower(forChannel: 0)
        let leftNorm = max(0, min(1, (leftDB + 60) / 60))
        mainWindowView.updateLevel(Float(leftNorm))
        if playbackDuration > 0 { mainWindowView.updateWaveformProgress(currentTime / playbackDuration) }
        if playbackDuration > 0 && currentTime >= playbackDuration { finishPlayback() }
    }
    
    private func finishPlayback(resetProgress: Bool = false) {
        UXEventLog.shared.module("Playback", "finish", ok: true, detail: ["file": (currentPlaybackFile ?? selectedPlaybackFile)?.name ?? ""])
        let finishedFile = currentPlaybackFile ?? selectedPlaybackFile
        stopPlaybackTimer()
        playbackPlayer?.stop(); playbackPlayer = nil
        currentPlaybackFile = nil; isPlaybackPaused = false
        mainWindowView.updateRecordingState(.idle)
        mainWindowView.updateTimer("00:00:00.0")
        if let file = finishedFile {
            mainWindowView.updatePlaybackDisplay(fileName: file.name, currentTime: resetProgress ? 0 : playbackDuration, duration: playbackDuration, isPlaying: false, isPaused: false)
        }
        mainWindowView.updateStatus("播放完成".localized)
    }
    
    private func formatTransportTime(_ time: TimeInterval) -> String {
        let elapsed = max(0, time)
        let hours = Int(elapsed) / 3600, minutes = Int(elapsed) % 3600 / 60,
            seconds = Int(elapsed) % 60, milliseconds = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d:%02d.%d", hours, minutes, seconds, milliseconds)
    }
    
    // MARK: - Recording Mode Management
    private func loadLastRecordingMode() {
        logger.info("使用默认录制模式: \(currentRecordingMode.rawValue)")
    }
    
    private func saveRecordingMode(_ mode: RecordingMode) {
        userDefaults.set(mode.rawValue, forKey: recordingModeKey)
    }

    /// 实际录制主目标（真相来源 = 侧边栏选择）。
    /// 侧边栏 selectedPIDs 空 = 系统混音；非空 = 特定进程。
    /// 麦克风是「叠加」选项（shouldMixAudio / 麦克风面板），不作为主目标——
    /// 这正是 BUG 根因：`currentRecordingMode` 是旧版切换按钮的僵尸状态，与侧边栏脱节。
    private var actualRecordingMode: RecordingMode {
        return selectedPIDs.isEmpty ? .systemMixdown : .specificProcess
    }
    
    // MARK: - File Management
    
    /// V2.0: 导出（通过导出卡片）
    private func exportRecording() {
        guard let fileURL = selectedPlaybackFile?.url ?? lastRecordedFile?.url else {
            mainWindowView.updateStatus("没有可导出的录音文件".localized); return
        }
        guard fileManager.fileExists(at: fileURL) else {
            mainWindowView.updateStatus("文件不存在".localized); return
        }
        UXEventLog.shared.action("export_card_opened", detail: ["file": fileURL.lastPathComponent])
        showExportCard(for: fileURL)
    }
    
    /// 弹导出卡片（编辑器上下文也用这个）
    private func showExportCard(for fileURL: URL) {
        // 读取元数据
        let displayName: String
        var duration: TimeInterval = 0
        do {
            let metadata = try encryptor.decryptMetadataOnly(from: fileURL)
            displayName = metadata.title
            duration = metadata.durationSec
        } catch {
            displayName = fileURL.deletingPathExtension().lastPathComponent
        }
        let fileSize = fileManager.getFileSize(at: fileURL) ?? 0
        ExportCardWindowController.shared.show(
            fileURL: fileURL,
            displayName: displayName,
            duration: duration,
            fileSize: fileSize
        )
    }
    
    // MARK: - Mode Management
    private func switchRecordingMode() {
        switch currentRecordingMode {
        case .microphone: currentRecordingMode = .specificProcess
        case .specificProcess: currentRecordingMode = .systemMixdown
        case .systemMixdown: currentRecordingMode = .microphone
        }
        UXEventLog.shared.state("recording_mode_changed", detail: ["mode": currentRecordingMode.rawValue])
        ensureAudioControllerInitialized()
        audioRecorderController?.setRecordingMode(currentRecordingMode)
        mainWindowView.updateMode(currentRecordingMode)
        
        switch currentRecordingMode {
        case .microphone:
            checkMicrophonePermissionOnModeSwitch()
        case .specificProcess:
            mainWindowView.updateStatus("特定进程录制：开始录制时会提示授权".localized)
            if let pid = selectedPIDs.first { audioRecorderController?.setCoreAudioTargetPID(pid) }
        case .systemMixdown:
            mainWindowView.updateStatus("系统混音录制：开始录制时会提示授权".localized)
        }
    }
    
    private func checkMicrophonePermissionOnModeSwitch() {
        let permissions = PermissionManager.shared.checkAllPermissions()
        switch permissions.microphone {
        case .granted: mainWindowView.updateStatus("麦克风权限已授予".localized)
        case .denied, .restricted: mainWindowView.updateStatus("麦克风权限被拒绝".localized)
        case .notDetermined: mainWindowView.updateStatus("麦克风权限未确定".localized)
        }
    }
    
    // MARK: - Menu Actions
    func toggleRecordingFromMenu() {
        if isRecording { stopRecording() } else { startRecording() }
    }
    
    func toggleSidebarFromMenu() { mainWindowView.toggleSidebar() }
    func editorUndoFromMenu() { currentEditor?.undo() }
    func editorRedoFromMenu() { currentEditor?.redo() }
    var isInEditorMode: Bool { currentEditor != nil }
    
    func togglePlaybackFromMenu() {
        if playbackPlayer != nil {
            if playbackPlayer?.isPlaying == true { pausePlayback() }
            else if isPlaybackPaused { resumePlayback() }
        } else if selectedPlaybackFile != nil { playRecording() }
    }
    
    func exportCurrentFileFromMenu() {
        guard selectedPlaybackFile != nil else { return }
        exportRecording()
    }
    
    func deleteCurrentFileFromMenu() {
        guard let file = selectedPlaybackFile else { return }
        UXEventLog.shared.action("delete_file", detail: ["file": file.name])
        if playbackPlayer != nil { stopPlayback() }
        // V2.0: 安全删除 .arlock
        SecureDelete.deleteFile(at: file.url)
        UXEventLog.shared.artifact("file_deleted", path: file.url.path, detail: ["name": file.name])
        selectedPlaybackFile = nil
        loadRecordedFilesOnStartup()
        mainWindowView.updateStatus("已删除: %@".localized(file.name))
    }
    
    // MARK: - Settings Sync
    private func loadSettingsFromDefaults() {
        let defaults = UserDefaults.standard
        let formatStr = defaults.string(forKey: SettingsWindowController.Keys.recordingFormat) ?? "m4a"
        currentFormat = formatStr == "wav" ? .wav : .m4a
    }
    
    @objc private func handleSettingsChanged() {
        loadSettingsFromDefaults()
        if let controller = audioRecorderController { controller.setAudioFormat(currentFormat) }
    }
    
    // MARK: - Permission
    private func openSystemPreferences() {
        PermissionManager.shared.openSystemPreferences()
        mainWindowView.updateStatus("已打开系统偏好设置，请允许相关权限".localized)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in self?.checkAudioPermissions() }
    }
    
    private func checkAudioPermissions() {
        let permissions = PermissionManager.shared.checkAllPermissions()
        switch permissions.microphone {
        case .granted: logger.info("麦克风权限已授予")
        case .denied: mainWindowView.updateStatus("麦克风权限被拒绝".localized)
        default: break
        }
        switch permissions.systemAudioCapture {
        case .granted: logger.info("屏幕录制权限已授予")
        case .denied: mainWindowView.updateStatus("屏幕录制权限被拒绝".localized)
        default: break
        }
    }
    
    // MARK: - File List (V2.0: .arlock metadata)
    
    private func loadRecordedFilesOnStartup() {
        logger.info("加载录音文件列表 (V2.0 .arlock)...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let arlockFiles = self.fileManager.getRecordingFiles()
            var files: [RecordedFileInfo] = []

            for url in arlockFiles {
                if let metadata = try? AudioFileEncryptor.shared.decryptMetadataOnly(from: url),
                   let size = self.fileManager.getFileSize(at: url) {
                    let date = ISO8601DateFormatter().date(from: metadata.createdAt) ?? Date()
                    // V2.1: 兜底显示名 — 旧文件 / V1 文件（无 sourceApp 或 title 是 UUID/临时文件名）用 sourceApp+日期
                    let displayName = self.resolvedDisplayName(
                        metadata: metadata,
                        fileURL: url,
                        date: date
                    )
                    let info = RecordedFileInfo(url: url, name: displayName, date: date, duration: metadata.durationSec, size: size)
                    files.append(info)
                } else {
                    self.logger.warning("跳过无法读取的 .arlock: \(url.lastPathComponent)")
                }
            }

            files.sort { $0.date > $1.date }

            DispatchQueue.main.async {
                self.logger.info("已加载 \(files.count) 个录音文件")
                UXEventLog.shared.module("FileList", "load", ok: true, detail: ["count": files.count])
                self.mainWindowView.loadRecordedFiles(files)
            }
        }
    }

    /// V2.1: 解析显示名 — title 已有且不像默认临时名时直接用；否则用 sourceApp+日期兜底
    private func resolvedDisplayName(metadata: ArlockMetadata, fileURL: URL, date: Date) -> String {
        let title = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        // 标题看起来像"用户起的名字"（不是 UUID 也不是临时 record_xxx）则保留
        if !title.isEmpty, !looksLikeDefaultFilename(title, fileURL: fileURL) {
            return title
        }
        // 用元数据里的 sourceApp 兜底
        if !metadata.sourceApp.isEmpty {
            return defaultDisplayName(sourceApp: metadata.sourceApp, sourceType: metadata.sourceType, date: date)
        }
        // 极端兜底（连 sourceApp 都没有的旧文件）
        return defaultDisplayName(sourceApp: "", sourceType: metadata.sourceType, date: date)
    }

    /// 判断 title 是不是"系统默认"（临时 record_xxx、UUID、和 .arlock 文件名一致）
    private func looksLikeDefaultFilename(_ title: String, fileURL: URL) -> Bool {
        // 1. 和 .arlock 文件名（去掉扩展名的 UUID）一致 → 说明 title 没设置过
        let fileStem = fileURL.deletingPathExtension().lastPathComponent
        if title == fileStem { return true }
        // 2. 临时文件格式：record_<prefix>_<timestamp>
        if title.hasPrefix("record_") { return true }
        // 3. UUID 格式（8-4-4-4-12）
        if UUID(uuidString: title) != nil { return true }
        return false
    }
    
    // MARK: - Process Management
    func loadAvailableProcesses() {
        // LOOP-05: UI 测试模式注入 mock 进程
        if isUITesting {
            deliverMockProcesses()
            return
        }
        ensureAudioControllerInitialized()
        let processes: [AudioProcessInfo]
        if #available(macOS 14.4, *) {
            let enumerator = AudioProcessEnumerator()
            processes = enumerator.getAvailableAudioProcesses()
        } else { processes = [] }
        availableProcesses = processes
        mainWindowView.updateProcessList(processes)
        mainWindowView.updateTracksDisplay()
    }
    
    /// LOOP-05: 交付 mock 进程列表（--ui-testing 模式，1001-1006 对齐 XCUITest 期望）
    private func deliverMockProcesses() {
        let mockNames = ["Chrome", "Safari", "Music", "Zoom", "Teams", "Slack"]
        let mocks = mockNames.enumerated().map { idx, name in
            AudioProcessInfo(pid: pid_t(1001 + idx), name: name)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.availableProcesses = mocks
            self.mainWindowView.updateProcessList(mocks)
            self.mainWindowView.updateTracksDisplay()
        }
    }
    
    private func refreshProcessList() {
        // LOOP-05: UI 测试模式注入 mock 进程（1001-1006），不依赖真实系统进程
        if isUITesting {
            deliverMockProcesses()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if #available(macOS 14.4, *) {
                Task { @MainActor in
                    let coreRecorder = CoreAudioProcessTapRecorder(mode: .systemMixdown)
                    let processes = coreRecorder.getAvailableAudioProcesses()
                    self.mainWindowView.updateProcessList(processes)
                    self.mainWindowView.updateStatus("进程列表已刷新".localized)
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定".localized)
        alert.runModal()
    }
}

// MARK: - MainWindowViewDelegate
extension MainViewController: MainWindowViewDelegate {
    func mainWindowViewDidSwitchMode(_ view: MainWindowView) { switchRecordingMode() }
    func mainWindowViewDidStartRecording(_ view: MainWindowView) { startRecording() }
    func mainWindowViewDidStopRecording(_ view: MainWindowView) { stopRecording() }
    func mainWindowViewDidPlayRecording(_ view: MainWindowView) { playRecording() }
    
    func mainWindowViewDidDownloadRecording(_ view: MainWindowView) {
        // 优先使用 selectedPlaybackFile，其次是编辑器中打开的文件
        if selectedPlaybackFile != nil {
            exportRecording()
        } else if let editorFile = currentEditor?.file {
            showExportCard(for: editorFile.url)
        } else {
            mainWindowView.updateStatus("没有可导出的录音文件".localized)
        }
    }
    
    func mainWindowViewDidChangeFormat(_ view: MainWindowView, format: String) {
        let newFormat: AudioFormat = format.lowercased() == "wav" ? .wav : .m4a
        if newFormat != currentFormat { currentFormat = newFormat; audioRecorderController?.setAudioFormat(newFormat) }
    }
    
    func mainWindowViewDidOpenPermissions(_ view: MainWindowView) { openSystemPreferences() }
    func mainWindowViewDidStopPlayback(_ view: MainWindowView) { stopPlayback() }
    
    func mainWindowViewDidSelectRecordedFile(_ view: MainWindowView, file: RecordedFileInfo) {
        enterEditor(file: file)
    }
    
    func mainWindowViewDidSelectProcesses(_ view: MainWindowView, pids: [pid_t]) {
        UXEventLog.shared.action("select_record_target", detail: ["pids": pids.map { Int($0) }])
        selectedPIDs = pids
        // V2.1: 同步填充 selectedProcesses（修复 BUG：之前字段永远为空）
        // 用 PID 集合匹配当前 availableProcesses 拿到完整 name，用于文件名兜底
        let pidSet = Set(pids)
        selectedProcesses = Set(availableProcesses.filter { pidSet.contains($0.pid) })
        ensureAudioControllerInitialized()
        // 同步录制模式状态：让 currentRecordingMode 与侧边栏真相保持一致（修复状态机脱节）
        let mode: RecordingMode = pids.isEmpty ? .systemMixdown : .specificProcess
        if currentRecordingMode != mode {
            currentRecordingMode = mode
            saveRecordingMode(mode)
            audioRecorderController?.setRecordingMode(mode)
            mainWindowView.updateMode(mode)
        }
        audioRecorderController?.setCoreAudioTargetPID(pids.first)
        mainWindowView.updateStatus(pids.first != nil ? "录制目标：应用声音".localized : "录制目标：全部系统声音".localized)
    }
    
    func mainWindowViewDidRequestProcessRefresh(_ view: MainWindowView) { refreshProcessList() }
    
    func mainWindowViewDidRequestExportAudio(_ view: MainWindowView, file: RecordedFileInfo) {
        showExportCard(for: file.url)
    }
    
    func mainWindowViewDidRenameFile(_ view: MainWindowView, file: RecordedFileInfo, newName: String) {
        // V2.1: 持久化重命名到 .arlock 元数据（同 UUID，重加密整个文件）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try AudioFileEncryptor.shared.updateTitle(in: file.url, newTitle: newName)
                self.logger.info("已重命名: \(file.url.lastPathComponent) → \(newName)")
                UXEventLog.shared.module("File", "rename", ok: true, detail: ["old": file.name, "new": newName])
                DispatchQueue.main.async {
                    self.mainWindowView.updateStatus("已重命名: %@".localized(newName))
                    self.loadRecordedFilesOnStartup()
                }
            } catch {
                self.logger.error("重命名失败: \(error.localizedDescription)")
                UXEventLog.shared.module("File", "rename", ok: false, detail: ["error": error.localizedDescription])
                DispatchQueue.main.async {
                    self.mainWindowView.updateStatus("重命名失败: %@".localized(error.localizedDescription))
                }
            }
        }
    }
    
    func mainWindowViewDidChangeMixAudio(_ view: MainWindowView, enabled: Bool) {
        UXEventLog.shared.action("mix_audio_toggle", detail: ["enabled": enabled])
        shouldMixAudio = enabled
        // FIX-007: 录音中切「同时录入麦克风」→ 直通纯系统 Tap 录制器动态注入，无需重启录音。
        // （开录前切开关的路径不变：startRecording 时读取 shouldMixAudio 决定 MixedAudioRecorder。）
        if isRecording {
            if #available(macOS 14.4, *), let recorder = audioRecorderController?.getCurrentRecorder() as? CoreAudioProcessTapRecorder {
                recorder.setMicMixEnabled(enabled)
                logger.info("🎤 [FIX007] 录音中麦克风注入 → \(enabled ? "开启" : "关闭")（已下发录制器）")
                mainWindowView.updateStatus(enabled
                    ? "麦克风已加入本次录制".localized
                    : "麦克风已移出本次录制".localized)
                if enabled {
                    PermissionManager.shared.requestMicrophonePermission { _ in }
                }
                return
            }
        }
        if enabled {
            mainWindowView.updateStatus("已开启麦克风叠加".localized)
            PermissionManager.shared.requestMicrophonePermission { _ in }
        } else { mainWindowView.updateStatus("已关闭麦克风叠加".localized) }
    }
    
    /// FIX-003: 波形 seek — 播放/暂停态直写 currentTime；无播放器（含已播完）时带初始进度启动播放
    func mainWindowViewDidSeekToProgress(_ view: MainWindowView, progress: Double) {
        if let player = playbackPlayer {
            let targetTime = player.duration * progress
            player.currentTime = targetTime
            if let file = currentPlaybackFile {
                mainWindowView.updatePlaybackDisplay(fileName: file.name, currentTime: targetTime, duration: playbackDuration, isPlaying: player.isPlaying, isPaused: isPlaybackPaused)
                mainWindowView.updateTimer(formatTransportTime(targetTime))
            }
            mainWindowView.updateWaveformProgress(progress)
            UXEventLog.shared.module("Playback", "seek", ok: true, detail: ["progress": progress, "target_sec": targetTime, "wasPlaying": player.isPlaying])
        } else if let file = selectedPlaybackFile {
            // 播放器不存在（未开始/已播完）：异步解密后从点击位置起播
            UXEventLog.shared.module("Playback", "seek", ok: true, detail: ["progress": progress, "mode": "cold_start"])
            startPlayback(file: file, initialProgress: progress)
        }
    }

    /// FIX-003: 拖拽 scrubbing 开始 — 暂停播放静音跟手（playhead 由 seek 回调驱动）
    func mainWindowViewDidBeginScrubbing(_ view: MainWindowView) {
        guard let player = playbackPlayer, player.isPlaying else { return }
        player.pause()
        isPlaybackPaused = true
        stopPlaybackTimer()
        UXEventLog.shared.action("scrub_begin")
    }

    /// FIX-003: 拖拽 scrubbing 结束 — 从松手位置恢复播放
    func mainWindowViewDidEndScrubbing(_ view: MainWindowView) {
        guard let player = playbackPlayer, let file = currentPlaybackFile, isPlaybackPaused, player.currentTime < player.duration - 0.05 else {
            UXEventLog.shared.action("scrub_end")
            return
        }
        player.play()
        isPlaybackPaused = false
        mainWindowView.updateRecordingState(.playing)
        mainWindowView.updatePlaybackDisplay(fileName: file.name, currentTime: player.currentTime, duration: playbackDuration, isPlaying: true, isPaused: false)
        startPlaybackTimer()
        UXEventLog.shared.action("scrub_end", detail: ["resume_sec": player.currentTime])
    }
    
    func mainWindowViewDidRequestEditFile(_ view: MainWindowView, file: RecordedFileInfo) {
        enterEditor(file: file)
    }
    
    func mainWindowViewDidRequestMode(_ view: MainWindowView, mode: RecordingMode) {
        ensureAudioControllerInitialized()
        if currentRecordingMode != mode {
            currentRecordingMode = mode
            audioRecorderController?.setRecordingMode(mode)
            mainWindowView.updateMode(mode)
            saveRecordingMode(mode)
        }
    }
}

// MARK: - Process Auto-Refresh
extension MainViewController {
    func startProcessRefreshTimer() {
        stopProcessRefreshTimer()
        processRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.silentRefreshProcessList()
        }
    }
    
    func stopProcessRefreshTimer() { processRefreshTimer?.invalidate(); processRefreshTimer = nil }
    
    private func silentRefreshProcessList() {
        // LOOP-05: UI 测试模式——保持 mock 列表，禁止真实进程覆盖
        if isUITesting { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var processes: [AudioProcessInfo] = []
            if #available(macOS 14.4, *) {
                let enumerator = AudioProcessEnumerator()
                processes = enumerator.getAvailableAudioProcesses()
            }
            DispatchQueue.main.async {
                self.availableProcesses = processes
                self.mainWindowView.updateProcessList(processes)
                self.checkSelectedProcessStillAlive()
            }
        }
    }
    
    private func checkSelectedProcessStillAlive() {
        guard !selectedPIDs.isEmpty, isRecording else { return }
        let stillAlive = selectedPIDs.allSatisfy { pid in availableProcesses.contains { $0.pid == pid } }
        if !stillAlive {
            logger.warning("录制目标进程已退出，自动停止录制")
            UXEventLog.shared.module("Recording", "autostop", detail: ["reason": "target_process_exited"])
            stopRecording()
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "录制目标已退出".localized
                alert.informativeText = "你选中的进程已经退出，录制已自动停止。已录制的内容已保存。".localized
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定".localized)
                alert.runModal()
            }
        }
    }
}

// MARK: - Process Exit Monitoring
extension MainViewController {
    func setupProcessExitMonitoring() {
        processExitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  self.isRecording, !self.selectedPIDs.isEmpty else { return }
            if self.selectedPIDs.contains(app.processIdentifier) {
                self.logger.warning("录制目标进程已退出")
                self.stopRecording()
                self.mainWindowView.updateStatus("目标进程已退出，录制已停止并保存".localized)
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

// MARK: - Sleep Prevention
extension MainViewController {
    func preventSleep() {
        guard !sleepAssertionActive else { return }
        let result = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Audio recording in progress" as CFString, &sleepAssertionID)
        if result == kIOReturnSuccess { sleepAssertionActive = true }
    }
    
    func allowSleep() {
        guard sleepAssertionActive else { return }
        IOPMAssertionRelease(sleepAssertionID); sleepAssertionActive = false; sleepAssertionID = 0
    }
}

// MARK: - Disk Space Monitor
extension MainViewController {
    func startDiskMonitor() {
        stopDiskMonitor()
        diskMonitorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkDiskSpaceDuringRecording()
        }
    }
    
    func stopDiskMonitor() { diskMonitorTimer?.invalidate(); diskMonitorTimer = nil }
    
    private func checkDiskSpaceDuringRecording() {
        guard isRecording else { stopDiskMonitor(); return }
        if !fileManager.hasSufficientDiskSpace() {
            let available = fileManager.getAvailableDiskSpace().map { fileManager.formatDiskSpace($0) } ?? "未知".localized
            stopRecording()
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "磁盘空间不足，录制已自动停止".localized
                alert.informativeText = "当前可用空间仅 %@，已保存已录制的内容。".localized(available)
                alert.alertStyle = .critical
                alert.addButton(withTitle: "确定".localized)
                alert.runModal()
            }
        }
    }
}

// MARK: - Crash Recovery (V2.0: temp file scan)
extension MainViewController {
    func checkAndRecoverUnfinishedRecording() {
        guard let unfinishedURL = fileManager.checkForUnfinishedRecording() else { return }
        
        let fileName = unfinishedURL.lastPathComponent
        let fileSize = fileManager.getFileSize(at: unfinishedURL).map { fileManager.formatFileSize($0) } ?? "未知".localized
        
        let alert = NSAlert()
        alert.messageText = "发现未保存的录音".localized
        alert.informativeText = "上次录制可能因异常中断，发现未保存的临时录音文件（%@，大小 %@）。是否恢复？".localized(fileName, fileSize)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "恢复".localized)
        alert.addButton(withTitle: "丢弃".localized)
        
        if alert.runModal() == .alertFirstButtonReturn {
            // V2.0: 恢复 = 加密转为 .arlock
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                do {
                    let cafData = try Data(contentsOf: unfinishedURL)
                    let uuid = self.fileManager.generateRecordingUUID()
                    
                    // 简单元数据（恢复场景，信息有限）
                    let metadata = ArlockMetadata(
                        title: "恢复_%@".localized(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)),
                        durationSec: 0,
                        sampleRate: 44100,
                        channels: 2,
                        bitsPerSample: 16,
                        audioCodec: "pcm",
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        sourceType: "recovered",
                        sourceApp: ""
                    )
                    
                    let arlockURL = self.fileManager.getRecordingFileURL(uuid: uuid)
                    try self.encryptor.encryptAndWrite(audioData: cafData, metadata: metadata, recordingUUID: uuid, outputURL: arlockURL)
                    
                    // 安全删除临时 CAF
                    SecureDelete.deleteFile(at: unfinishedURL)
                    
                    DispatchQueue.main.async {
                        self.logger.info("录制文件已恢复: \(arlockURL.lastPathComponent)")
                        UXEventLog.shared.module("Recovery", "restore", ok: true)
                        UXEventLog.shared.artifact("recovered_arlock_created", path: arlockURL.path)
                        self.mainWindowView.updateStatus("已恢复录音".localized)
                        self.loadRecordedFilesOnStartup()
                    }
                } catch {
                    DispatchQueue.main.async {
                        UXEventLog.shared.module("Recovery", "restore", ok: false, detail: ["error": error.localizedDescription])
                        self.mainWindowView.updateStatus("恢复失败: %@".localized(error.localizedDescription))
                    }
                }
            }
        } else {
            SecureDelete.deleteFile(at: unfinishedURL)
            logger.info("用户选择丢弃未完成的录制")
        }
    }
}

// MARK: - Editor Management
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
    
    private var sessionManager: EditorSessionManager { EditorSessionManager.shared }
    
    func enterEditor(file: RecordedFileInfo) {
        guard !isRecording else { mainWindowView.updateStatus("录制中不能进入编辑器".localized); return }
        if let current = currentEditor, current.file.url == file.url { return }
        UXEventLog.shared.action("enter_editor", detail: ["file": file.name, "duration_sec": file.duration])
        if playbackPlayer != nil { stopPlayback() }
        saveCurrentEditorState()
        let session = sessionManager.session(for: file)
        let editor = EditorViewController(file: file, session: session)
        editor.delegate = self
        let previousEditor = currentEditor
        currentEditor = editor
        if previousEditor != nil {
            mainWindowView.crossDissolveEditor(to: editor.editorView)
        } else {
            mainWindowView.showEditor(editor.editorView)
        }
        mainWindowView.updateStatus("编辑: %@".localized(file.name))
        // UI 状态已切换：记录状态 + 视图树快照（验证编辑器视图真实挂载）
        UXEventLog.shared.state("editor_shown", detail: ["file": file.name], snapshotWindow: true)
        // INFRA-006: 自验 lite 通道——触发器带 uitest 位时，编辑器就绪后自动跑脚本化命令序列
        if pendingLiteUITest {
            pendingLiteUITest = false
            let editor = currentEditor
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let editor = editor else { return }
                self?.logger.info("🔬 [INFRA006] lite selftest: 开始脚本化序列")
                editor.runLiteSelftest()
            }
        }
    }
    
    func exitEditor() {
        saveCurrentEditorState(); currentEditor = nil
        mainWindowView.hideEditor(); mainWindowView.updateStatus("准备就绪".localized)
        UXEventLog.shared.state("editor_hidden", snapshotWindow: true)
    }
    
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
        UXEventLog.shared.module("Editor", "save", ok: true, detail: ["file": file.name])
        mainWindowView.updateStatus("保存完成: %@".localized(file.name))
        loadRecordedFilesOnStartup()
    }
    func editorDidCancel(_ editor: EditorViewController) { exitEditor() }
}

// MARK: - AVAudioPlayerDelegate
extension MainViewController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in self?.finishPlayback() }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.mainWindowView.updateStatus("播放失败: %@".localized(error?.localizedDescription ?? "未知错误".localized))
            self?.finishPlayback(resetProgress: true)
        }
    }
}
