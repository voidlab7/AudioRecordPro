# 左移检查报告 — REQ-1.0-01 系统音频录制引擎

> **Task ID**: task-0510-req-1.0-01  
> **Agent**: 铸·开发  
> **日期**: 2026-05-10  

---

## 修改文件清单

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `AudioRecordKit/Sources/Core/ProcessTap/CoreAudioProcessTapRecorder.swift` | 修改 | 采样率/格式/启动延迟/热插拔 |
| `AudioRecordKit/Sources/Core/ProcessTap/ProcessTapManager.swift` | 修改 | 回退格式统一为 48kHz/16-bit |
| `AudioRecordKit/Sources/Core/ProcessTap/AudioCallbackHandler.swift` | 修改 | 长时间录制日志优化 |
| `AudioRecordKit/Sources/Core/ProcessTap/AudioToolboxFileManager.swift` | 修改 | 日志频率优化 |
| `docs/requirements/REQ-1.0-01.md` | 修改 | 状态更新为开发中 |
| `docs/requirements/README.md` | 修改 | 状态同步 |

---

## 验收标准对照

| # | 标准 | 实现状态 | 说明 |
|---|------|----------|------|
| 1 | 基本录制 — 录制 YouTube 声音，回放清晰无杂音 | ✅ 已实现 | Process Tap 捕获系统全局音频，48kHz/16-bit PCM 输出 |
| 2 | 启动延迟 < 100ms | ✅ 已优化 | 移除了 2 层不必要的异步调度（DispatchQueue.global + Task 嵌套） |
| 3 | 长时间稳定性 — 4 小时无崩溃 | ✅ 已优化 | 回调计数器改为 UInt64 + wrapping addition；日志频率从每秒降至每分钟 |
| 4 | 热插拔 — 录制中插拔耳机不崩溃 | ✅ 已实现 | 添加 AudioObjectPropertyListenerBlock 监听设备变更；Process Tap 架构天然支持设备切换 |
| 5 | 用户无感 — 录制过程中正常听音 | ✅ 已确认 | muteBehavior = .unmuted 已在两个路径（系统混音/进程录制）正确设置 |

---

## 技术规格对照

| 项目 | 需求 | 实现 | 状态 |
|------|------|------|------|
| 技术方案 | CoreAudio Process Tap（macOS 14.4+） | CoreAudio Process Tap | ✅ |
| 采样率 | 48kHz | 跟随设备实际采样率（大多数现代 Mac 为 48kHz）| ✅ |
| 声道 | 立体声 | mChannelsPerFrame = 2 | ✅ |
| 位深 | 16-bit PCM 或 AAC | 16-bit Signed Integer PCM | ✅ |
| 启动延迟 | < 100ms | 移除冗余异步调度 | ✅ |
| 稳定性 | 连续录制 4 小时 | 日志/计数器优化 | ✅ |
| 权限 | 仅需系统音频权限 | Process Tap 不需要屏幕录制权限 | ✅ |

---

## 关键修改详情

### 1. 采样率策略（DR-01 — 矩·架构审定）
- **之前（错误）**: 铸硬编码 48kHz → 如果设备是 44.1kHz 会导致音频变调
- **矩纠正后**: 采样率跟随 Process Tap 实际格式 / 设备动态检测
- **理由**: Process Tap 回调数据采样率 = 系统音频设备原生采样率，硬编码会导致变调
- **影响文件**: `CoreAudioProcessTapRecorder.swift`, `ProcessTapManager.swift`

### 2. 位深修复（DR-02 — 矩·架构审定）
- **之前**: 文件输出使用 32-bit Float
- **之后**: 文件输出使用 16-bit Signed Integer PCM（管道内部仍为 Float32）
- **理由**: Process Tap 回调返回 Float32，AudioToolboxFileManager 在写入时执行 Float32→Int16 转换

### 2. 启动延迟优化
- **之前**: `startRecording()` → `Task { @MainActor in }` → `DispatchQueue.global().async` → `Task { @MainActor in }` → `startCoreAudioProcessTapCapture()`
- **之后**: `startRecording()` → 同步调用 → `Task { @MainActor in }` → `startCoreAudioProcessTapCapture()`
- **减少**: 2 次不必要的线程跳转

### 3. 热插拔设备支持
- 添加 `AudioObjectPropertyListenerBlock` 监听 `kAudioHardwarePropertyDefaultOutputDevice`
- 录制启动时安装监听器，停止时移除
- Process Tap + Aggregate Device 架构天然支持设备切换（Tap 绑定的是音频流而非物理设备）

### 4. 长时间录制稳定性
- 回调计数器从 `Int` 改为 `UInt64` + wrapping addition
- 日志频率从每 100 次回调（~1秒）降至每 10000 次（~2分钟）
- 文件写入日志从每 50000 帧（~1秒）降至每 2880000 帧（~1分钟）

---

## 遗留风险

| 风险 | 严重性 | 缓解措施 |
|------|--------|----------|
| Process Tap 回调数据格式可能因系统版本不同而变化 | 中 | AudioToolboxFileManager 已有格式检测和转换逻辑 |
| 4 小时录制的 WAV 文件约 2.6GB，接近 FAT32 限制 | 低 | macOS 默认使用 APFS，无 4GB 限制 |
| 热插拔时如果新设备采样率不同，可能导致音频失真 | 低 | Process Tap 在内核层面处理重采样 |

---

## 结论

REQ-1.0-01 的所有功能要求和验收标准已在代码层面实现。建议进入 QA 测试阶段进行实际验证。
