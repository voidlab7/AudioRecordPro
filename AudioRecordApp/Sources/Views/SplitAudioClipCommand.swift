import Foundation
import AVFoundation

class SplitAudioClipCommand: EditCommand {
    let description: String
    private let time: TimeInterval

    init(time: TimeInterval) {
        self.time = time
        self.description = "切分 @ %@s".localized(String(format: "%.2f", time))
    }

    func execute(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        return buffer  // TODO: P0 editor WIP
    }

    func undo(on buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        return buffer
    }
}
