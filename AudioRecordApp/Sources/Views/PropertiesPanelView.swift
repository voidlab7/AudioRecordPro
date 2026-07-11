import Cocoa
final class PropertiesPanelView: NSView {
    weak var delegate: AnyObject?
    func setEnabled(_ enabled: Bool) {}
    func updateProperties(volume: Float, fadeIn: Float, fadeOut: Float) {}
    func updateFileInfo(name: String, duration: String, sampleRate: String, format: String, channels: String, fileSize: String) {}
}
