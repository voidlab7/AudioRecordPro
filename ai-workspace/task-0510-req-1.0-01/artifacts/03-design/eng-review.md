# 技术方案 — REQ-1.0-01 系统音频录制引擎

> **Agent**: 矩·架构  
> **Task ID**: task-0510-req-1.0-01  
> **日期**: 2026-05-10  
> **评审结果**: ⚠️ 有条件通过 (30/50)

---

## 1. 架构概览

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│ System Audio │────▶│ CoreAudio        │────▶│ Process Tap         │
│ (any app)    │     │ Process Tap API  │     │ (kernel-level tap)  │
└──────────────┘     └──────────────────┘     └──────────┬──────────┘
                                                          │
                                                          ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Aggregate Device                               │
│  (binds Tap + system output device, auto-starts)                 │
└──────────────────────────────────────┬───────────────────────────┘
                                       │
                                       ▼ IOProc callback (Float32)
┌──────────────────────────────────────────────────────────────────┐
│              AudioCallbackHandler (globalAudioCallback)           │
│  Input: AudioBufferList (Float32, device native sample rate)     │
│  Process: Float32 → Int16 conversion                             │
│  Output: → AudioToolboxFileManager → WAV file (16-bit PCM)      │
└──────────────────────────────────────────────────────────────────┘
```

## 2. 关键技术决策

### DR-01: 采样率策略 — 跟随设备，不硬编码

**决策**: 文件采样率跟随 Process Tap 实际返回的格式，不硬编码 48kHz。

**理由**:
- Process Tap 回调数据的采样率 = 系统音频设备的原生采样率
- 硬编码 48kHz 但设备是 44.1kHz → 音频变调（变快 8.8%）
- 硬编码 48kHz 但设备是 96kHz → 音频变调（变慢 50%）
- 大多数现代 Mac 设备默认 48kHz，但不能假设所有设备都是

**实现**:
1. 优先使用 `ProcessTapManager.readTapStreamFormat()` 返回的实际 ASBD
2. 如果 Tap 格式读取失败，回退到 `AudioUtils.getCurrentAudioDeviceSampleRate()` 动态检测
3. 文件头使用实际检测到的采样率

**爆炸半径**: 低 — 仅影响文件头元数据
**可逆性**: 5/5 — 随时可改

### DR-02: 位深策略 — 管道 Float32，输出 16-bit PCM

**决策**: 录制管道内部保持 Float32（Process Tap 原生格式），文件输出使用 16-bit PCM。

**理由**:
- Process Tap 回调返回 Float32 数据，这是不可改变的
- 在管道中间转换会损失精度
- AudioToolboxFileManager 已有 Float32→Int16 转换逻辑
- 16-bit PCM WAV 满足需求规格

**实现**:
1. `createAudioFileWithTapFormat` 中的 audioFormat 定义为 16-bit PCM（文件格式）
2. 回调处理器内部仍以 Float32 处理数据
3. `AudioToolboxFileManager.writeAudioData` 在写入时执行 Float32→Int16 转换

### DR-03: 启动延迟 — 移除冗余异步调度

**决策**: 移除 `startCoreAudioRecordingWithTapFormat` 中的 `Task { @MainActor in }` 包装，
移除 `continueRecordingProcess` 中的 `DispatchQueue.global().async` 包装。

**理由**: 这些调度是不必要的，因为 `startRecording()` 已经在 MainActor 上下文中。

### DR-04: 热插拔 — 设备变更监听

**决策**: 添加 `AudioObjectPropertyListenerBlock` 监听 `kAudioHardwarePropertyDefaultOutputDevice`。

**理由**: Process Tap + Aggregate Device 架构天然支持设备切换，监听器用于日志记录和状态通知。

---

## 3. 测试覆盖缺口（交鉴深度展开）

| 测试场景 | 优先级 | 说明 |
|----------|--------|------|
| 基本录制 + 回放验证 | P0 | 录制 YouTube 声音，回放清晰 |
| 采样率匹配验证 | P0 | 文件采样率 = 设备实际采样率 |
| 长时间录制 4h | P0 | 内存不泄漏，文件完整 |
| 热插拔耳机 | P1 | 录制中插拔不崩溃 |
| 启动延迟测量 | P1 | < 100ms |
| 不同设备采样率 | P1 | 44.1k/48k/96k 设备 |

---

## 4. 技术债评估

| 项目 | 严重度 | 说明 |
|------|--------|------|
| Swift API vs C API 双路径 | 中 | 两套 Process Tap 实现并存，增加维护成本 |
| 回调中的 static var | 低 | 已优化为 UInt64，但全局状态不理想 |
| 日志过多 | 低 | 已优化频率，但仍有改进空间 |
