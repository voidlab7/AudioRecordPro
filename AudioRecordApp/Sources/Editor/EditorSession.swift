import AVFoundation

// MARK: - ViewportState
/// 编辑器视口状态快照 — 用于文件切换时保持/恢复状态
struct ViewportState {
    var zoomLevel: Double = 1.0
    var scrollOffset: Double = 0.0
    var playheadPosition: Double = 0.0
}

// MARK: - EditorSession
/// 单个音频文件的编辑会话 — 持有音频数据、编辑历史和视图状态
class EditorSession {

    // MARK: - Properties
    let file: RecordedFileInfo

    // 音频数据（加载后缓存）
    var audioBuffer: AVAudioPCMBuffer?
    var audioFormat: AVAudioFormat?

    // 视图状态（切换时保持）
    var viewportState: ViewportState = ViewportState()
    var selectionRange: Range<Int>?

    // 编辑历史
    let editHistory = EditHistory()
    var hasUnsavedChanges: Bool = false

    // 生命周期
    private(set) var isLoaded: Bool = false
    private(set) var isLoading: Bool = false
    var lastAccessTime: Date = Date()

    // 加载错误
    var loadError: String?

    // MARK: - Initialization
    init(file: RecordedFileInfo) {
        self.file = file
    }

    // MARK: - Audio Loading

    /// 异步加载音频数据
    func loadAudio(completion: @escaping (Bool) -> Void) {
        guard !isLoaded && !isLoading else {
            completion(isLoaded)
            return
        }

        isLoading = true
        lastAccessTime = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let audioFile = try AVAudioFile(forReading: self.file.url)
                let format = audioFile.processingFormat
                let fileLength = audioFile.length
                let frameCount = AVAudioFrameCount(fileLength)

                guard frameCount > 0,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    DispatchQueue.main.async {
                        self.loadError = "无法分配音频缓冲区"
                        self.isLoading = false
                        completion(false)
                    }
                    return
                }

                try audioFile.read(into: buffer)

                DispatchQueue.main.async {
                    self.audioBuffer = buffer
                    self.audioFormat = format
                    self.isLoaded = true
                    self.isLoading = false
                    self.loadError = nil
                    completion(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadError = "无法读取音频文件: \(error.localizedDescription)"
                    self.isLoading = false
                    completion(false)
                }
            }
        }
    }

    // MARK: - State Management

    /// 标记访问时间（LRU 淘汰依据）
    func touch() {
        lastAccessTime = Date()
    }

    /// 释放音频缓冲区以节省内存（保留状态）
    func releaseBuffer() {
        audioBuffer = nil
        isLoaded = false
    }

    /// 估算内存占用（字节）
    var estimatedMemoryUsage: Int {
        guard let buffer = audioBuffer else { return 0 }
        return Int(buffer.frameLength) * Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
    }
}
