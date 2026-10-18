// UI-023 硬验证 harness — SplitAudioClipCommand 转正（口径 A · buffer 级真拆分）
// 复跑（仓库根）：
//   python3 -c "import wave,math,struct; f=wave.open('/tmp/ui023_src.wav','w'); f.setnchannels(1); f.setsampwidth(2); f.setframerate(48000); [f.writeframesraw(struct.pack('<h', int(12000*math.sin(2*math.pi*440*i/48000)))) for i in range(96000)]; f.close()"
//   swiftc e2e/harness/ui023_split_command_harness.swift \
//     AudioRecordApp/Sources/Editor/EditCommand.swift \
//     AudioRecordApp/Sources/Views/SplitAudioClipCommand.swift \
//     AudioRecordKit/Sources/Utils/L10n.swift -o /tmp/ui023_harness && /tmp/ui023_harness
// 通过判据：23 项断言 ALL PASS + afinfo 两段各 1.000000s。
// 注：App target 无测试基建（Kit 测试引不到 App 源），本 harness 即本命令的单测等价物。

import Foundation
import AVFoundation

// UI-023 硬验证 harness：引正本 EditCommand + SplitAudioClipCommand + L10n
var failures = 0
func check(_ cond: Bool, _ name: String) {
    print(cond ? "PASS  \(name)" : "FAIL  \(name)")
    if !cond { failures += 1 }
}

// ---- 载入源（2s 48kHz mono，AVAudioFile 读出为非交错 float32）----
let srcURL = URL(fileURLWithPath: "/tmp/ui023_src.wav")
let file = try! AVAudioFile(forReading: srcURL)
let fmt = file.processingFormat  // 48kHz float32 deinterleaved
let src = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
try! file.read(into: src)
let ch0 = src.floatChannelData![0]
let total = Int(src.frameLength)
check(total == 96000, "源样本数 96000 (实际 \(total))")

// ---- 1. execute @1.0s：两段各 48000，总和不变，时间轴 buffer 原样 ----
let cmd = SplitAudioClipCommand(time: 1.0)
let ret = cmd.execute(on: src)
check(ret != nil, "execute(1.0) 成功")
check(cmd.segments.count == 2, "产出两段 (实际 \(cmd.segments.count))")
let lf = Int(cmd.segments[0].frameLength), rf = Int(cmd.segments[1].frameLength)
check(lf == 48000 && rf == 48000, "前/后段各 48000 帧 (实际 \(lf)/\(rf))")
check(lf + rf == total, "样本总数不变 \(lf+rf) == \(total)")
check(ret!.frameLength == AVAudioFramePosition(total), "时间轴 buffer 帧数不变")
check(cmd.splitFrame == 48000, "splitFrame=48000 样本级定位 (实际 \(cmd.splitFrame))")

// ---- 2. 样本级数据保真（±0 帧漂移）：段边界采样值与源逐位一致 ----
let l = cmd.segments[0].floatChannelData![0]
let r = cmd.segments[1].floatChannelData![0]
check(l[lf-1] == ch0[47999], "前段末样本 == 源[47999] (\(l[lf-1]) vs \(ch0[47999]))")
check(r[0] == ch0[48000], "后段首样本 == 源[48000] (\(r[0]) vs \(ch0[48000]))")
check(r[rf-1] == ch0[95999], "后段末样本 == 源[95999]")
check(l[0] == ch0[0], "前段首样本 == 源[0]")
// 全量校验（96000 样本逐位比对）
var allMatch = true
for i in 0..<48000 where l[i] != ch0[i] { allMatch = false; break }
if allMatch { for i in 0..<48000 where r[i] != ch0[48000+i] { allMatch = false; break } }
check(allMatch, "96000 样本逐位保真（无缝无重叠）")

// ---- 3. 两段落盘（afinfo 外部验证时长）----
func writeWav(_ buf: AVAudioPCMBuffer, _ path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    // float32 buffer 直接写 float32 wav，processingFormat 自动匹配
    let f = try! AVAudioFile(forWriting: url, settings: buf.format.settings,
                             commonFormat: .pcmFormatFloat32, interleaved: buf.format.isInterleaved)
    try! f.write(from: buf)
}
writeWav(cmd.segments[0], "/tmp/ui023_left.wav")
writeWav(cmd.segments[1], "/tmp/ui023_right.wav")

// ---- 4. undo：产物清空、buffer 不变；redo：确定性重建 ----
let undoRet = cmd.undo(on: src)
check(undoRet != nil && cmd.segments.isEmpty, "undo 后产物清空")
check(undoRet!.frameLength == AVAudioFramePosition(total), "undo 后 buffer 帧数不变")
let redoRet = cmd.execute(on: src)
check(redoRet != nil && cmd.segments.count == 2 && cmd.splitFrame == 48000, "redo 重建两段，splitFrame 一致")

// ---- 5. 边界拒切：0 / 末尾 / 越界 / NaN 不建空 clip ----
check(SplitAudioClipCommand(time: 0.0).execute(on: src) == nil, "边界 0 拒切")
check(SplitAudioClipCommand(time: 2.0).execute(on: src) == nil, "边界末尾拒切")
check(SplitAudioClipCommand(time: -0.5).execute(on: src) == nil, "负时刻拒切")
check(SplitAudioClipCommand(time: Double.nan).execute(on: src) == nil, "NaN 拒切")

// ---- 6. 交错 int16 stereo 分支（slice 的 interleaved 路径）----
let iFmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 4800,
                         channels: 2, interleaved: true)!
let cap: AVAudioFrameCount = 4800  // 1s
let ibuf = AVAudioPCMBuffer(pcmFormat: iFmt, frameCapacity: cap)!
ibuf.frameLength = cap
let i16 = ibuf.int16ChannelData![0]
for fr in 0..<Int(cap) {
    i16[fr*2]   = Int16((fr * 7) % 30000)       // L 可识别梯度
    i16[fr*2+1] = Int16((fr * 11) % 30000)      // R
}
let icmd = SplitAudioClipCommand(time: 0.5)
let iret = icmd.execute(on: ibuf)
check(iret != nil && icmd.segments.count == 2, "交错格式 execute 成功")
let il = icmd.segments[0], ir = icmd.segments[1]
check(il.frameLength == 2400 && ir.frameLength == 2400, "交错两段各 2400 帧")
let ilp = UnsafeMutableAudioBufferListPointer(il.mutableAudioBufferList)[0]
let irp = UnsafeMutableAudioBufferListPointer(ir.mutableAudioBufferList)[0]
let ilData = UnsafeRawPointer(ilp.mData!).assumingMemoryBound(to: Int16.self)
let irData = UnsafeRawPointer(irp.mData!).assumingMemoryBound(to: Int16.self)
check(ilData[2399*2] == i16[2399*2] && ilData[2399*2+1] == i16[2399*2+1], "交错前段末帧 L/R 保真")
check(irData[0] == i16[2400*2] && irData[1] == i16[2400*2+1], "交错后段首帧 L/R 保真")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
