import XCTest
@testable import AudioRecordKit
import AVFoundation

/// FEAT-007 非破坏编辑模型单测：
/// 1) 草稿规格 Codable 往返  2) 草稿仓库存取/失效  3) EditHistory 草稿重放（撤销延续）
/// 4) DraftRenderEngine 渲染语义（命令重放 + 增益限幅）
final class EditDraftTests: XCTestCase {

    // MARK: - 测试桩命令

    /// 乘法增益命令：execute 样本×factor，undo 样本÷factor（确定可逆）
    private final class ScaleCommand: EditCommand {
        let description: String
        let draftSpec: DraftCommandSpec
        let factor: Float
        init(factor: Float) {
            self.factor = factor
            self.description = "scale×\(factor)"
            self.draftSpec = .split(time: 0)  // 占位（桩命令不走真实工厂）
        }
        func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            guard let data = buffer.floatChannelData else { return nil }
            let frames = Int(buffer.frameLength)
            for ch in 0..<Int(buffer.format.channelCount) {
                for f in 0..<frames { data[ch][f] *= factor }
            }
            return buffer
        }
        func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            guard let data = buffer.floatChannelData else { return nil }
            let frames = Int(buffer.frameLength)
            for ch in 0..<Int(buffer.format.channelCount) {
                for f in 0..<frames { data[ch][f] /= factor }
            }
            return buffer
        }
    }

    /// 恒失败命令（重放失败路径用）
    private final class FailCommand: EditCommand {
        let description = "fail"
        let draftSpec: DraftCommandSpec = .split(time: 0)
        func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? { nil }
        func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? { nil }
    }

    // MARK: - 工具

    private func makeSineBuffer(seconds: Double = 0.1, sampleRate: Double = 48000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        let twoPi: Double = 2 * Double.pi
        let amplitude: Float = 0.5
        for f in 0..<Int(frames) {
            let phase = twoPi * 440.0 * Double(f) / sampleRate
            data[f] = Float(sin(phase)) * amplitude
        }
        return buffer
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: 1) Codable 往返

    func testDraftCommandSpecCodableRoundtrip() throws {
        let specs: [DraftCommandSpec] = [
            .trim(start: 1.5, end: 9.25),
            .deleteSelection(start: 0.1, end: 2.0),
            .split(time: 3.75),
            .silenceTrim(segments: [DraftSilenceSegment(start: 1.0, end: 2.5),
                                    DraftSilenceSegment(start: 8.0, end: 9.0)]),
            .normalize(preset: "播客", customLUFS: -15.5),
            .normalize(preset: "YouTube", customLUFS: nil),
            .fade(fadeIn: 0.5, fadeOut: 1.0, curve: "对数"),
        ]
        for spec in specs {
            let data = try JSONEncoder().encode([spec])
            let decoded = try JSONDecoder().decode([DraftCommandSpec].self, from: data)
            XCTAssertEqual(decoded.first, spec, "spec 往返必须等值: \(spec)")
        }
    }

    func testEditDraftMutationSemantics() {
        var draft = EditDraft(originalURL: URL(fileURLWithPath: "/tmp/x.arlock"), originalFileSize: 100)
        XCTAssertFalse(draft.hasEdits)
        XCTAssertFalse(draft.hasRenderableEdits)

        draft.append(.trim(start: 0, end: 1), historyPosition: 0)
        draft.append(.split(time: 0.5), historyPosition: 1)
        XCTAssertEqual(draft.commands.count, 2)
        XCTAssertEqual(draft.currentIndex, 1)
        XCTAssertTrue(draft.hasEdits)

        // 撤销一格
        draft.syncIndex(0)
        XCTAssertEqual(draft.currentIndex, 0)
        XCTAssertTrue(draft.hasEdits, "撤销后命令栈仍在（撤销栈本身是状态）")
        XCTAssertTrue(draft.hasRenderableEdits, "有命令即需渲染（重放到指针处）")

        // redo 段被新命令截断（对齐 EditHistory 语义：执行新命令后 position=1，栈=[trim, fade]）
        draft.append(.fade(fadeIn: 0.1, fadeOut: 0.1, curve: "线性"), historyPosition: 1)
        XCTAssertEqual(draft.commands.count, 2)
        XCTAssertEqual(draft.currentIndex, 1)
        XCTAssertEqual(draft.commands.first, .trim(start: 0, end: 1), "redo 段（split）应被截断")

        // 增益
        draft.setGain(2.0)
        XCTAssertEqual(draft.clipGain, 2.0)
        draft.setGain(5.0)  // 上限夹取
        XCTAssertEqual(draft.clipGain, 2.0)
    }

    // MARK: 2) 草稿仓库

    func testDraftStoreSaveLoadRemove() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = EditDraftStore(directory: dir)

        let original = URL(fileURLWithPath: "/tmp/draft-store-test-\(UUID().uuidString).arlock")
        // 原文件真实存在（仓库校验大小需要）
        try Data([0x01, 0x02, 0x03]).write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }

        var draft = EditDraft(originalURL: original, originalFileSize: 3)
        draft.append(.trim(start: 0.5, end: 2.5), historyPosition: 0)
        store.save(draft)
        store.flushForTesting()

        let loaded = store.draft(for: original)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.commands, draft.commands)
        XCTAssertEqual(loaded?.currentIndex, 0)
        XCTAssertTrue(store.hasEdits(for: original))

        store.remove(for: original)
        store.flushForTesting()
        XCTAssertNil(store.draft(for: original))
        XCTAssertFalse(store.hasEdits(for: original))
    }

    func testDraftStoreInvalidWhenOriginalReplaced() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = EditDraftStore(directory: dir)

        let original = URL(fileURLWithPath: "/tmp/draft-valid-test-\(UUID().uuidString).arlock")
        try Data(repeating: 0x07, count: 10).write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }

        let draft = EditDraft(originalURL: original, originalFileSize: 10)
        XCTAssertTrue(store.isDraftValid(draft, originalURL: original))

        // 原始文件被替换（大小变化）→ 草稿失效
        try Data(repeating: 0x07, count: 99).write(to: original)
        XCTAssertFalse(store.isDraftValid(draft, originalURL: original))

        // 路径不匹配 → 失效
        let other = URL(fileURLWithPath: "/tmp/other.arlock")
        XCTAssertFalse(store.isDraftValid(draft, originalURL: other))
    }

    func testDraftStoreSequentialAppendsCoherentWithoutFlush() throws {
        // 回归（FEAT-007 自审发现）：同步读+异步写下，连续两次 append 第二次
        // 曾读到未落盘旧草稿丢命令——内存权威缓存修复后必须连续可见
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = EditDraftStore(directory: dir)

        let original = URL(fileURLWithPath: "/tmp/draft-coherent-test-\(UUID().uuidString).arlock")
        try Data([0x01]).write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }

        store.append(.trim(start: 0.1, end: 0.9), historyPosition: 0, for: original)
        store.append(.split(time: 0.5), historyPosition: 1, for: original)  // 不 flush 直接读

        let draft = store.draft(for: original)
        XCTAssertEqual(draft?.commands.count, 2, "背靠背 append 不得丢命令")
        XCTAssertEqual(draft?.currentIndex, 1)
        XCTAssertTrue(store.hasEdits(for: original))
    }

    func testDraftStoreCorruptFileReturnsNilAndCleans() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = EditDraftStore(directory: dir)

        let original = URL(fileURLWithPath: "/tmp/draft-corrupt-test.arlock")
        let draftURL = store.draftURL(for: original)
        try Data("not-json".utf8).write(to: draftURL)

        XCTAssertNil(store.draft(for: original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path), "坏草稿应被顺带清理")
    }

    // MARK: 3) EditHistory 草稿重放（撤销延续）

    func testEditHistoryReplayRestoresUndo() {
        var buffer = makeSineBuffer()
        let original = DraftRenderEngine.duplicate(buffer)!
        let history = EditHistory()

        let specs: [DraftCommandSpec] = [.split(time: 0), .split(time: 0)]  // 桩命令工厂忽略 spec
        let ok = history.replay(specs: specs, upTo: 1, on: &buffer) { _, _ in ScaleCommand(factor: 2.0) }
        XCTAssertTrue(ok)
        XCTAssertEqual(history.position, 1)
        XCTAssertTrue(history.canUndo)
        // 重放后 buffer = original × 4
        if let src = original.floatChannelData, let dst = buffer.floatChannelData {
            XCTAssertEqual(dst[0][10], src[0][10] * 4.0, accuracy: 1e-6)
        }

        // 撤销延续：undo 两次回到原始样本
        XCTAssertTrue(history.undo(on: &buffer))
        XCTAssertTrue(history.undo(on: &buffer))
        XCTAssertFalse(history.canUndo)
        if let src = original.floatChannelData, let dst = buffer.floatChannelData {
            XCTAssertEqual(dst[0][10], src[0][10], accuracy: 1e-6)
        }
    }

    func testEditHistoryReplayRollsBackOnFailure() {
        var buffer = makeSineBuffer()
        let original = DraftRenderEngine.duplicate(buffer)!
        let history = EditHistory()

        let specs: [DraftCommandSpec] = [.split(time: 0), .trim(start: 1.0, end: 2.0)]
        let ok = history.replay(specs: specs, upTo: 1, on: &buffer) { spec, _ in
            let command: EditCommand = (spec == specs[0]) ? ScaleCommand(factor: 2.0) : FailCommand()
            return command
        }
        XCTAssertFalse(ok, "第二步失败 → 整体重放失败")
        // 回滚：buffer 与历史栈恢复原状
        if let src = original.floatChannelData, let dst = buffer.floatChannelData {
            XCTAssertEqual(dst[0][10], src[0][10], accuracy: 1e-6, "失败后 buffer 必须回滚")
        }
        XCTAssertFalse(history.canUndo, "失败后历史栈必须为空")
    }

    // MARK: 4) DraftRenderEngine

    func testRenderEngineReplaysCommandsAndGain() {
        let input = makeSineBuffer()
        var work = DraftRenderEngine.duplicate(input)!
        let history = EditHistory()
        _ = history.execute(ScaleCommand(factor: 2.0), on: &work)
        let specs: [DraftCommandSpec] = [.split(time: 0)]

        let rendered = DraftRenderEngine.render(input: input, commands: specs, currentIndex: 0,
                                                clipGain: 1.0) { _, _ in ScaleCommand(factor: 2.0) }
        XCTAssertNotNil(rendered)
        XCTAssertEqual(rendered?.frameLength, input.frameLength)
        if let src = input.floatChannelData, let dst = rendered?.floatChannelData {
            XCTAssertEqual(dst[0][100], src[0][100] * 2.0, accuracy: 1e-6)
        }
    }

    func testRenderEngineAppliesGainWithClamp() {
        // 样本 0.5 × gain 2.0 = 1.0（临界）；0.9 × 2.0 限幅到 1.0
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
        buffer.frameLength = 4
        buffer.floatChannelData![0][0] = 0.5
        buffer.floatChannelData![0][1] = 0.9
        buffer.floatChannelData![0][2] = -0.9
        buffer.floatChannelData![0][3] = 0.1

        let out = DraftRenderEngine.applyGain(2.0, to: buffer)!
        XCTAssertEqual(out.floatChannelData![0][0], 1.0, accuracy: 1e-6)
        XCTAssertEqual(out.floatChannelData![0][1], 1.0, accuracy: 1e-6, "正向限幅")
        XCTAssertEqual(out.floatChannelData![0][2], -1.0, accuracy: 1e-6, "负向限幅")
        XCTAssertEqual(out.floatChannelData![0][3], 0.2, accuracy: 1e-6)

        // gain=1 原样返回
        let out2 = DraftRenderEngine.applyGain(1.0, to: buffer)
        XCTAssertTrue(out2 === buffer)
    }

    func testRenderEngineFailsCleanlyWhenCommandFails() {
        let input = makeSineBuffer()
        let rendered = DraftRenderEngine.render(input: input, commands: [.split(time: 0)],
                                                currentIndex: 0, clipGain: 1.0) { _, _ in FailCommand() }
        XCTAssertNil(rendered)
    }

    func testRenderEngineUndoAllOnlyAppliesGain() {
        let input = makeSineBuffer()
        let rendered = DraftRenderEngine.render(input: input, commands: [.split(time: 0)],
                                                currentIndex: -1, clipGain: 0.5) { _, _ in
            XCTFail("currentIndex=-1 不应执行任何命令")
            return nil
        }
        XCTAssertNotNil(rendered)
        XCTAssertEqual(rendered?.frameLength, input.frameLength)
        if let src = input.floatChannelData, let dst = rendered?.floatChannelData {
            XCTAssertEqual(dst[0][50], src[0][50] * 0.5, accuracy: 1e-6)
        }
    }
}
