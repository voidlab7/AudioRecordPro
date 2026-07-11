import Foundation
import AppKit
import AVFoundation
import Darwin

/// 权限管理器
class PermissionManager {
    static let shared = PermissionManager()
    
    private let logger = Logger.shared
    private var permissionCheckTimer: Timer?
    
    private init() {}
    
    /// 权限状态枚举
    enum PermissionStatus {
        case granted
        case denied
        case notDetermined
        case restricted
    }
    
    /// 权限类型
    enum PermissionType {
        case microphone
        case systemAudioCapture
    }
    
    /// 检查所有权限状态
    func checkAllPermissions() -> (microphone: PermissionStatus, systemAudioCapture: PermissionStatus) {
        let microphoneStatus = checkMicrophonePermission()
        let systemAudioCaptureStatus = checkSystemAudioCapturePermission()
        
        logger.info("权限检查结果 - 麦克风: \(microphoneStatus), 系统音频捕获: \(systemAudioCaptureStatus)")
        
        return (microphoneStatus, systemAudioCaptureStatus)
    }
    
    /// 检查麦克风权限
    private func checkMicrophonePermission() -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        @unknown default:
            return .notDetermined
        }
    }
    
    // MARK: - System Audio Capture (TCC SPI)
    private static let tccPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"
    private static let tccHandle: UnsafeMutableRawPointer? = {
        let handle = dlopen(tccPath, RTLD_NOW)
        return handle
    }()
    private typealias PreflightFuncType = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFuncType = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void
    private static let tccPreflight: PreflightFuncType? = {
        guard let handle = tccHandle, let sym = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(sym, to: PreflightFuncType.self)
    }()
    private static let tccRequest: RequestFuncType? = {
        guard let handle = tccHandle, let sym = dlsym(handle, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(sym, to: RequestFuncType.self)
    }()
    private let tccServiceAudioCapture: CFString = "kTCCServiceAudioCapture" as CFString

    /// 检查系统音频捕获权限
    private func checkSystemAudioCapturePermission() -> PermissionStatus {
        return preflightSystemAudioCapture()
    }
    
    private func preflightSystemAudioCapture() -> PermissionStatus {
        guard let preflight = PermissionManager.tccPreflight else { return .notDetermined }
        let result = preflight(tccServiceAudioCapture, nil)
        if result == 0 { return .granted }
        if result == 1 { return .denied }
        return .notDetermined
    }
    
    func requestSystemAudioCapturePermission(completion: @escaping (PermissionStatus) -> Void) {
        // 先静默查询
        let status = preflightSystemAudioCapture()
        switch status {
        case .granted, .denied:
            completion(status)
            return
        case .notDetermined, .restricted:
            break
        }
        guard let request = PermissionManager.tccRequest else {
            completion(.notDetermined)
            return
        }
        logger.info("请求系统音频捕获权限（TCC）…")
        request(tccServiceAudioCapture, nil) { [weak self] granted in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.logger.info("系统音频捕获权限结果: \(granted)")
                completion(granted ? .granted : .denied)
            }
        }
    }

    /// 获取麦克风权限状态（公开方法）
    func getMicrophonePermissionStatus() -> PermissionStatus {
        return checkMicrophonePermission()
    }
    
    /// 请求麦克风权限（异步版本）
    func requestMicrophonePermissionAsync() async -> Bool {
        let status = checkMicrophonePermission()
        switch status {
        case .granted:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// 请求麦克风权限
    func requestMicrophonePermission(completion: @escaping (PermissionStatus) -> Void) {
        let currentStatus = checkMicrophonePermission()
        
        switch currentStatus {
        case .granted:
            completion(.granted)
        case .denied, .restricted:
            completion(currentStatus)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted ? .granted : .denied)
                }
            }
        }
    }
    
    /// 请求屏幕录制权限（已废弃，使用 requestSystemAudioCapturePermission）
    func requestScreenRecordingPermission(completion: @escaping (PermissionStatus) -> Void) {
        // 已废弃：产品不再使用 ScreenCaptureKit，统一使用系统音频捕获权限
        requestSystemAudioCapturePermission(completion: completion)
    }
    
    /// 开始权限监控（定期检查权限状态变化）
    func startPermissionMonitoring(interval: TimeInterval = 5.0, onStatusChange: @escaping (PermissionType, PermissionStatus) -> Void) {
        stopPermissionMonitoring()
        
        var lastMicrophoneStatus = checkMicrophonePermission()
        var lastSystemAudioStatus = checkSystemAudioCapturePermission()
        
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 检查麦克风权限变化
            let currentMicrophoneStatus = self.checkMicrophonePermission()
            if currentMicrophoneStatus != lastMicrophoneStatus {
                lastMicrophoneStatus = currentMicrophoneStatus
                onStatusChange(.microphone, currentMicrophoneStatus)
            }
            
            // 检查系统音频捕获权限变化
            let currentSystemAudioStatus = self.checkSystemAudioCapturePermission()
            if currentSystemAudioStatus != lastSystemAudioStatus {
                lastSystemAudioStatus = currentSystemAudioStatus
                onStatusChange(.systemAudioCapture, currentSystemAudioStatus)
            }
        }
    }
    
    /// 停止权限监控
    func stopPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
    
    /// 打开系统偏好设置（麦克风/音频权限页）
    func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
    
    /// 获取权限状态描述
    func getPermissionStatusDescription(_ status: PermissionStatus) -> String {
        switch status {
        case .granted:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .notDetermined:
            return "未确定"
        case .restricted:
            return "受限制"
        }
    }
    
    /// 获取权限设置指导信息
    func getPermissionGuide(for type: PermissionType) -> String {
        switch type {
        case .microphone:
            return """
            麦克风权限设置：
            1. 打开 系统偏好设置 > 安全性与隐私 > 隐私
            2. 选择左侧的"麦克风"
            3. 勾选"音频录制工具"应用
            """
        case .systemAudioCapture:
            return """
            系统音频捕获权限设置：
            1. 当系统弹出"允许录制系统音频"对话框时，点击"允许"
            2. 如被拒绝，可重启应用再次触发或在'隐私'中重置权限
            """
        }
    }}
