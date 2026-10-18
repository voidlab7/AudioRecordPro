// UI-022 硬验证 harness — DeleteSelectionCommand（UI-020 trim 同款口径）
// 复跑（仓库根）：
//   python3 -c "import wave,math,struct; f=wave.open('/tmp/ui023_src.wav','w'); f.setnchannels(1); f.setsampwidth(2); f.setframerate(48000); [f.writeframesraw(struct.pack('<h', int(12000*math.sin(2*math.pi*440*i/48000)))) for i in range(96000)]; f.close()"
//   mkdir -p /tmp/ui022_h && cp e2e/harness/ui022_delete_command_harness.swift /tmp/ui022_h/main.swift
//   swiftc /tmp/ui022_h/main.swift AudioRecordApp/Sources/Editor/EditCommand.swift \
//     AudioRecordApp/Sources/Views/DeleteSelectionCommand.swift AudioRecordKit/Sources/Utils/L10n.swift -o /tmp/ui022_h/harness && /tmp/ui022_h/harness
// 通过判据：12 项断言 ALL PASS + afinfo /tmp/ui022_deleted.wav = 1.000000s。
// ⚠️ harness 写 wav 必须用 do 块让 AVAudioFile 出作用域（否则 header 不 flush，afinfo 读 0 帧——UI-020 同款坑）。

import Foundation
import AVFoundation

// UI-022 硬验证 harness — DeleteSelectionCommand（UI-020 trim 同款脚本口径）
var failures = 0
func check(_ cond: Bool, _ name: String) {
    print(cond ? "PASS  \(name)" : "FAIL  \(name)")
    if !cond { failures += 1 }
}

// ---- 载入源（2s 48kHz mono float32，96000 帧）----
let srcURL = URL(fileURLWithPath: "/tmp/ui023_src.wav")
let file = try! AVAudioFile(forReading: srcURL)
let fmt = file.processingFormat
let src = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
try! file.read(into: src)
let ch0 = src.floatChannelData![0]
check(Int(src.frameLength) == 96000, "源样本数 96000")

// ---- 1. 删 0.5–1.5s → 1.0s（48000 帧），前段+后段逐位保真 ----
let cmd = DeleteSelectionCommand(startTime: 0.5, endTime: 1.5, sampleRate: 48000, totalFrames: src.frameLength)
let ret = cmd.execute(on: src)
check(ret != nil, "execute(删 0.5–1.5s) 成功")
let outFrames = Int(ret!.frameLength)
check(outFrames == 48000, "删除后 48000 帧 (实际 \(outFrames))")
let o = ret!.floatChannelData![0]
var match = true
for i in 0..<24000 where o[i] != ch0[i] { match = false; break }
if match { for i in 0..<24000 where o[24000+i] != ch0[72000+i] { match = false; break } }
check(match, "前段+后段 48000 样本逐位保真（删 [24000,72000) 无漂移）")

// ---- 2. 落盘（外部 afinfo）----
try? FileManager.default.removeItem(at: URL(fileURLWithPath: "/tmp/ui022_deleted.wav"))
// AVAudioFile 必须出作用域析构才 flush header（UI-020 教训：否则 afinfo 读 0 帧）
do {
    let w = try! AVAudioFile(forWriting: URL(fileURLWithPath: "/tmp/ui022_deleted.wav"),
                             settings: ret!.format.settings,
                             commonFormat: .pcmFormatFloat32, interleaved: false)
    try! w.write(from: ret!)
}

// ---- 3. undo → 2.0s 且逐位还原 ----
let undoRet = cmd.undo(on: ret!)
check(undoRet != nil && Int(undoRet!.frameLength) == 96000, "undo 还原 96000 帧 (实际 \(undoRet?.frameLength ?? 0))")
let u = undoRet!.floatChannelData![0]
var uMatch = true
for i in 0..<96000 where u[i] != ch0[i] { uMatch = false; break }
check(uMatch, "undo 后 96000 样本逐位还原")

// ---- 4. redo（重放 execute）→ 1.0s ----
let redoRet = cmd.execute(on: undoRet!)
check(redoRet != nil && Int(redoRet!.frameLength) == 48000, "redo 再删回 48000 帧")

// ---- 5. 全选删除 → 0 帧空态（不崩）；undo 还原 ----
let fullCmd = DeleteSelectionCommand(startTime: 0, endTime: 2.0, sampleRate: 48000, totalFrames: src.frameLength)
let fullRet = fullCmd.execute(on: src)
check(fullRet != nil && fullRet!.frameLength == 0, "全选删除 → 0 帧空态 (实际 \(fullRet?.frameLength as Any))")
let fullUndo = fullCmd.undo(on: fullRet!)
check(fullUndo != nil && Int(fullUndo!.frameLength) == 96000, "空态 undo 还原 96000 帧")

// ---- 6. 边界拒切 ----
check(DeleteSelectionCommand(startTime: 0.5, endTime: 0.5, sampleRate: 48000, totalFrames: src.frameLength).execute(on: src) == nil, "零长选区拒切")
check(DeleteSelectionCommand(startTime: 1.5, endTime: 0.5, sampleRate: 48000, totalFrames: src.frameLength).execute(on: src) == nil, "逆向区间拒切")
// 越界选区夹取：删 1.9–2.5s → 只删到末尾，剩 1.9s
let overCmd = DeleteSelectionCommand(startTime: 1.9, endTime: 2.5, sampleRate: 48000, totalFrames: src.frameLength)
let overRet = overCmd.execute(on: src)
check(overRet != nil && Int(overRet!.frameLength) == 91200, "越界选区夹取到末尾 (实际 \(overRet?.frameLength ?? 0))")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
