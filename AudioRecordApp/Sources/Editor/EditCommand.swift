import Foundation
import AVFoundation

// MARK: - EditCommand Protocol
/// 编辑命令协议 — Command 模式，支持撤销/重做
protocol EditCommand {
    var description: String { get }
    func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer?
    func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer?
}

// MARK: - EditHistory
/// 编辑历史栈 — 管理撤销/重做
class EditHistory {
    private var commands: [EditCommand] = []
    private var currentIndex: Int = -1
    let maxSteps: Int = 20
    
    var canUndo: Bool { currentIndex >= 0 }
    var canRedo: Bool { currentIndex < commands.count - 1 }
    var stepCount: Int { currentIndex + 1 }
    
    func execute(_ command: EditCommand, on buffer: inout AVAudioPCMBuffer) -> Bool {
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
    
    func undo(on buffer: inout AVAudioPCMBuffer) -> Bool {
        guard canUndo else { return false }
        guard let newBuffer = commands[currentIndex].undo(on: buffer) else { return false }
        buffer = newBuffer
        currentIndex -= 1
        return true
    }
    
    func redo(on buffer: inout AVAudioPCMBuffer) -> Bool {
        guard canRedo else { return false }
        let nextIndex = currentIndex + 1
        guard let newBuffer = commands[nextIndex].execute(on: buffer) else { return false }
        buffer = newBuffer
        currentIndex = nextIndex
        return true
    }
    
    func clear() {
        commands.removeAll()
        currentIndex = -1
    }
}
