import Foundation
import CoreAudio
import AudioUnit
import AVFoundation

/// FEAT-004R2: 自建 AUHAL input unit 采集麦克风（OBS/QuickTime 同款架构）
///
/// 根因背景（2026-10-13 CLI 七连实验实锤）：
/// AVAudioEngine 的 inputNode 与 outputNode 是**同一个 IO AUHAL unit**，
/// 对 inputNode set `kAudioOutputUnitProperty_CurrentDevice` = 把整个引擎的 IO 换成所选麦克风
/// → 扬声器侧 `outputHWFormat` 失配 → `engine.start()` 必报 **-10875**。
/// 与调用时机无关（start 前 / running 态 / stop 后均失败），是共用 unit 的架构死路。
///
/// 本类独立于 AVAudioEngine：HALOutput unit 只做输入采集，换设备不影响任何引擎。
/// 输出与 AVAudioEngine input tap 同构的 `AVAudioPCMBuffer`，下游消费方零改动。
final class MicCaptureUnit {

    private let logger = Logger.shared

    /// 收到 PCM 数据（实时音频线程回调，消费方保证线程安全——与 engine tap 同一约定）
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private var unit: AudioUnit?
    private var renderBufferList: UnsafeMutablePointer<AudioBufferList>?
    private var channelCount: Int = 1
    private var sampleRate: Double = 48000
    private var firstCallbackLogged = false

    /// 预分配容量（帧）；HALOutput 每次回调帧数 ≤ 硬件 IO 帧长，8192 足够
    private static let maxFrames = 8192

    var isRunning: Bool { unit != nil }

    /// 从设备读原生输入 stream format
    private func deviceStreamFormat(deviceID: AudioDeviceID) -> AVAudioFormat? {
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &asbd) == noErr,
              asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else {
            return nil
        }
        let channels = min(Int(asbd.mChannelsPerFrame), 8)
        return AVAudioFormat(commonFormat: .pcmFormatFloat32,
                             sampleRate: asbd.mSampleRate,
                             channels: AVAudioChannelCount(channels),
                             interleaved: false)
    }

    /// 在指定设备上启动采集
    func start(deviceID: AudioDeviceID) throws {
        stop()

        // BUGFIX 2026-10-28: 刚启动/HAL 重配置窗口期 StreamFormat 读取可能瞬时失败
        // （实测 22:31 selftest 首查失败，6 秒后同设备同查询 noErr）。有界重试 3×150ms；
        // 若为持续性故障（设备真不可用），重试日志反而留下完整证据
        var format: AVAudioFormat?
        for attempt in 1...3 {
            format = deviceStreamFormat(deviceID: deviceID)
            if format != nil { break }
            logger.warning("🎤 [MicCaptureUnit] 设备 id=\(deviceID) 输入格式读取失败，重试 \(attempt)/3")
            Thread.sleep(forTimeInterval: 0.15)
        }
        guard let format = format else {
            throw NSError(domain: "MicCaptureUnit", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无法读取设备输入格式（已重试 3 次）"])
        }
        sampleRate = format.sampleRate
        channelCount = Int(format.channelCount)

        // 1. 创建 HALOutput unit
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "MicCaptureUnit", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "找不到 HALOutput 组件"])
        }
        var au: AudioUnit?
        let st0 = AudioComponentInstanceNew(comp, &au)
        guard st0 == noErr, let au = au else {
            throw NSError(domain: "MicCaptureUnit", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "创建 unit 失败: \(st0)"])
        }
        unit = au

        // 2. 启用输入、禁用输出
        var enable: UInt32 = 1
        var disable: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, 1, &enable, size)
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, 0, &disable, size)

        // 3. 绑定设备（initialize 之前 set——纯 AU 层，无 AVAudioEngine 缓存问题）
        var devID = deviceID
        let stDev = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                         kAudioUnitScope_Global, 0,
                                         &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard stDev == noErr else {
            AudioComponentInstanceDispose(au)
            unit = nil
            throw NSError(domain: "MicCaptureUnit", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "绑定设备失败: \(stDev)"])
        }

        // 3.5 客户端格式（输入数据出口端 Output/1——不设则 IOProc 不被调度）
        var asbd = AudioStreamBasicDescription(
            mSampleRate: format.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0)
        let stFmt = AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Output, 1, &asbd,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard stFmt == noErr else {
            freeRenderBuffers()
            AudioComponentInstanceDispose(au)
            unit = nil
            throw NSError(domain: "MicCaptureUnit", code: -7,
                          userInfo: [NSLocalizedDescriptionKey: "设置客户端格式失败: \(stFmt)"])
        }

        // 4. 预分配 render buffer（实时线程零 malloc）
        let ablList = AudioBufferList.allocate(maximumBuffers: channelCount)
        for i in 0..<channelCount {
            ablList[i].mNumberChannels = 1
            ablList[i].mDataByteSize = UInt32(Self.maxFrames * MemoryLayout<Float>.size)
            ablList[i].mData = UnsafeMutableRawPointer.allocate(
                byteCount: Self.maxFrames * MemoryLayout<Float>.size,
                alignment: MemoryLayout<Float>.alignment)
        }
        renderBufferList = UnsafeMutablePointer<AudioBufferList>(ablList.unsafeMutablePointer)

        // 5. 输入回调（HALOutput 输入专用 SetInputCallback——SetRenderCallback 挂在被 disable 的输出端永不触发）
        var cb = AURenderCallbackStruct(
            inputProc: micRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        let stCb = AudioUnitSetProperty(au, kAudioOutputUnitProperty_SetInputCallback,
                                        kAudioUnitScope_Global, 0, &cb,
                                        UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard stCb == noErr else {
            freeRenderBuffers()
            AudioComponentInstanceDispose(au)
            unit = nil
            throw NSError(domain: "MicCaptureUnit", code: -8,
                          userInfo: [NSLocalizedDescriptionKey: "设置输入回调失败: \(stCb)"])
        }

        // 6. initialize + start
        let stInit = AudioUnitInitialize(au)
        guard stInit == noErr else {
            freeRenderBuffers()
            AudioComponentInstanceDispose(au)
            unit = nil
            throw NSError(domain: "MicCaptureUnit", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "initialize 失败: \(stInit)"])
        }
        let stStart = AudioOutputUnitStart(au)
        guard stStart == noErr else {
            AudioUnitUninitialize(au)
            freeRenderBuffers()
            AudioComponentInstanceDispose(au)
            unit = nil
            throw NSError(domain: "MicCaptureUnit", code: -6,
                          userInfo: [NSLocalizedDescriptionKey: "start 失败: \(stStart)"])
        }
        firstCallbackLogged = false
        logger.info("🎤 [FEAT004R2] MicCaptureUnit 已启动: 设备ID=\(deviceID), \(Int(sampleRate))Hz x\(channelCount)ch")
    }

    func stop() {
        guard let au = unit else { return }
        unit = nil
        AudioOutputUnitStop(au)
        AudioUnitUninitialize(au)
        AudioComponentInstanceDispose(au)
        freeRenderBuffers()
        logger.info("🎤 [FEAT004R2] MicCaptureUnit 已停止")
    }

    private func freeRenderBuffers() {
        guard let abl = renderBufferList else { return }
        renderBufferList = nil
        let list = UnsafeMutableAudioBufferListPointer(abl)
        for buf in list {
            buf.mData?.deallocate()
        }
        abl.deallocate()
    }

    /// render 回调实际逻辑（实时线程）：从 bus 1 拉数据 → 转 AVAudioPCMBuffer → 上抛
    /// （fileprivate：文件顶层 C 回调桥函数需要访问）
    fileprivate func doRender(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                          _ ts: UnsafePointer<AudioTimeStamp>,
                          _ frames: UInt32,
                          _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        // 诊断：proc 是否被调度（前 3 次打点）
        struct ProcShot { static var count = 0 }
        ProcShot.count += 1
        if ProcShot.count <= 3 {
            logger.info("🎤 [FEAT004R2] render proc 进入[\(ProcShot.count)]: frames=\(frames), ioData=\(ioData != nil)")
        }
        guard let au = unit, let abl = renderBufferList else { return noErr }
        guard frames > 0, Int(frames) <= Self.maxFrames else { return noErr }

        // 设置本次帧长后从 bus 1 拉取输入数据
        let list = UnsafeMutableAudioBufferListPointer(abl)
        for i in 0..<channelCount {
            list[i].mDataByteSize = frames * UInt32(MemoryLayout<Float>.size)
        }
        let st = AudioUnitRender(au, flags, ts, 1, frames, abl)
        guard st == noErr else {
            struct ErrShot { static var count = 0 }
            ErrShot.count += 1
            if ErrShot.count <= 5 { logger.error("🎤 [FEAT004R2] AudioUnitRender 失败[\(ErrShot.count)]: \(st)") }
            return noErr
        }

        guard let onBuffer = onBuffer,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: sampleRate,
                                            channels: AVAudioChannelCount(channelCount),
                                            interleaved: false),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outFormat,
                                               frameCapacity: AVAudioFrameCount(frames)) else { return noErr }

        pcmBuffer.frameLength = AVAudioFrameCount(frames)
        if let chData = pcmBuffer.floatChannelData {
            for ch in 0..<channelCount {
                if let src = list[ch].mData?.assumingMemoryBound(to: Float.self) {
                    chData[ch].update(from: src, count: Int(frames))
                }
            }
        }

        if !firstCallbackLogged {
            firstCallbackLogged = true
            logger.info("🎤 [FEAT004R2] 首帧到达: frames=\(frames), \(Int(sampleRate))Hz x\(channelCount)ch")
        }
        onBuffer(pcmBuffer)
        return noErr
    }
}

/// C 函数指针桥（AURenderCallback 不能用闭包捕获上下文）
private func micRenderCallback(_ refCon: UnsafeMutableRawPointer,
                               _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                               _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
                               _ inBusNumber: UInt32,
                               _ inNumberFrames: UInt32,
                               _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let holder = Unmanaged<MicCaptureUnit>.fromOpaque(refCon).takeUnretainedValue()
    return holder.doRender(ioActionFlags, inTimeStamp, inNumberFrames, ioData)
}
