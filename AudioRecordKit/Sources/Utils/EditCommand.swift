import Foundation
import AVFoundation

// MARK: - EditCommand Protocol
/// 编辑命令协议 — Command 模式，支持撤销/重做
/// FEAT-007: 自 App 层（Editor/EditCommand.swift）迁入 Kit——草稿重放/渲染引擎需要被 swift test 覆盖
public protocol EditCommand {
    var description: String { get }
    /// FEAT-007: 命令的可序列化规格（草稿自动保存/重放/渲染的唯一数据源）
    var draftSpec: DraftCommandSpec { get }
    func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer?
    func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer?
}

// MARK: - EditHistory
/// 编辑历史栈 — 管理撤销/重做
public final class EditHistory {
    private var commands: [EditCommand] = []
    private var currentIndex: Int = -1
    public let maxSteps: Int = 20

    /// 当前历史位置（草稿同步用：FEAT-007 草稿的 currentIndex 以本栈为唯一真相）
    public var position: Int { currentIndex }

    public var canUndo: Bool { currentIndex >= 0 }
    public var canRedo: Bool { currentIndex < commands.count - 1 }
    public var stepCount: Int { currentIndex + 1 }

    public init() {}

    @discardableResult
    public func execute(_ command: EditCommand, on buffer: inout AVAudioPCMBuffer) -> Bool {
        // 清除 currentIndex 之后的 redo 历史
        if currentIndex < commands.count - 1 {
            commands.removeSubrange((currentIndex + 1)...)
        }

        guard let newBuffer = command.execute(on: buffer) else { return false }
        buffer = newBuffer
        commands.append(command)
        currentIndex = commands.count - 1

        // 超过 maxSteps 移除最早的
        if commands.count > maxSteps {
            commands.removeFirst()
            currentIndex -= 1
        }

        return true
    }

    @discardableResult
    public func undo(on buffer: inout AVAudioPCMBuffer) -> Bool {
        guard canUndo else { return false }
        guard let newBuffer = commands[currentIndex].undo(on: buffer) else { return false }
        buffer = newBuffer
        currentIndex -= 1
        return true
    }

    @discardableResult
    public func redo(on buffer: inout AVAudioPCMBuffer) -> Bool {
        guard canRedo else { return false }
        let nextIndex = currentIndex + 1
        guard let newBuffer = commands[nextIndex].execute(on: buffer) else { return false }
        buffer = newBuffer
        currentIndex = nextIndex
        return true
    }

    public func clear() {
        commands.removeAll()
        currentIndex = -1
    }

    // MARK: - FEAT-007 草稿重放

    /// 草稿重放：按序执行 specs[0...index]（经 factory 构造命令），捕获 undo 数据使撤销延续。
    /// 失败（任一命令构造或执行失败）时完整回滚 buffer 与历史栈，返回 false——调用方状态不变。
    /// 注意：调用方场景是「刚从原始文件加载的干净 buffer + 空历史」，重放不与用户操作并发。
    @discardableResult
    public func replay(specs: [DraftCommandSpec],
                       upTo index: Int,
                       on buffer: inout AVAudioPCMBuffer,
                       factory: (DraftCommandSpec, AVAudioPCMBuffer) -> EditCommand?) -> Bool {
        guard !specs.isEmpty else { return false }
        let target = min(index, specs.count - 1)
        guard target >= 0 else { return false }

        // 快照用于失败回滚：深拷贝防御（协议不禁止命令原地改写样本；真实命令均为拷贝式，
        // 但回滚保证必须无条件成立——失败时调用方拿到的必须是与重放前逐字节一致的 buffer）
        guard let snapshot = DraftRenderEngine.duplicate(buffer) else { return false }
        let originalCommands = commands
        let originalIndex = currentIndex
        clear()

        for i in 0...target {
            guard let cmd = factory(specs[i], buffer), execute(cmd, on: &buffer) else {
                // 回滚：buffer 恢复快照，历史恢复原栈
                buffer = snapshot
                commands = originalCommands
                currentIndex = originalIndex
                return false
            }
        }
        return true
    }
}
