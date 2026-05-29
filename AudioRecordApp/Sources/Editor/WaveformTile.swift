import Foundation

// MARK: - Audio Asset
/// Represents an audio file's metadata for waveform tile generation.
/// Does NOT hold PCM data — only metadata needed for cache key and tile scheduling.
struct AudioAsset {
    let id: String
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double
    let channelCount: Int
    let fileSize: Int64
    let modifiedAt: Date
    
    /// Generate stable ID from file metadata + algorithm version.
    /// Changes in file size, modification time, or algorithm version invalidate the cache.
    static func makeID(url: URL, fileSize: Int64, modifiedAt: Date, algorithmVersion: Int) -> String {
        let raw = "\(url.path)|\(fileSize)|\(Int(modifiedAt.timeIntervalSince1970))|\(algorithmVersion)"
        var hasher = Hasher()
        hasher.combine(raw)
        return String(format: "%016llx", UInt64(bitPattern: Int64(hasher.finalize())))
    }
}

// MARK: - LOD Configuration
/// Level-of-Detail configuration for waveform tile generation.
/// Each LOD level defines how many audio frames are compressed into one peak,
/// and how much time each tile covers.
struct LODConfig {
    let level: Int
    let samplesPerPeak: Int
    let tileDuration: TimeInterval
    
    /// All available LOD levels, from coarsest (0) to finest (4).
    static let allLevels: [LODConfig] = [
        LODConfig(level: 0, samplesPerPeak: 48000 * 5, tileDuration: 300),  // ~1 peak per 5s, overview
        LODConfig(level: 1, samplesPerPeak: 48000,     tileDuration: 120),  // ~1 peak per 1s
        LODConfig(level: 2, samplesPerPeak: 4800,      tileDuration: 60),   // ~10 peaks per s
        LODConfig(level: 3, samplesPerPeak: 960,       tileDuration: 30),   // ~50 peaks per s
        LODConfig(level: 4, samplesPerPeak: 480,       tileDuration: 10),   // ~100 peaks per s, fine edit
    ]
    
    /// Select the appropriate LOD level based on current zoom (pixels per second).
    static func selectLOD(pixelsPerSecond: CGFloat, sampleRate: Double = 48000) -> LODConfig {
        switch pixelsPerSecond {
        case ..<1:     return allLevels[0]
        case 1..<5:    return allLevels[1]
        case 5..<30:   return allLevels[2]
        case 30..<150: return allLevels[3]
        default:       return allLevels[4]
        }
    }
    
    /// Total number of tiles needed to cover the given duration at this LOD level.
    func tileCount(for totalDuration: TimeInterval) -> Int {
        guard tileDuration > 0 else { return 0 }
        return Int(ceil(totalDuration / tileDuration))
    }
}

// MARK: - Tile Key
/// Unique identifier for a waveform tile, used as cache key.
struct WaveformTileKey: Hashable {
    let assetID: String
    let lodLevel: Int
    let tileIndex: Int
    
    /// String representation for NSCache key.
    var cacheKey: NSString {
        "\(assetID)_\(lodLevel)_\(tileIndex)" as NSString
    }
}

// MARK: - Peak Data
/// A single peak measurement representing a segment of audio frames.
/// Stores min/max for accurate waveform rendering and optional RMS for loudness.
struct WaveformPeak {
    let min: Float   // Minimum sample value (negative for downward amplitude)
    let max: Float   // Maximum sample value (positive for upward amplitude)
    let rms: Float?  // Optional RMS for loudness-aware rendering
    
    /// Absolute peak amplitude (for compatibility with existing bar rendering).
    var amplitude: Float {
        Swift.max(abs(min), abs(max))
    }
}

// MARK: - Tile
/// A chunk of pre-computed waveform peaks covering a specific time range at a specific LOD.
struct WaveformTile {
    let key: WaveformTileKey
    let sourceStartTime: TimeInterval
    let duration: TimeInterval
    let samplesPerPeak: Int
    let peaks: [WaveformPeak]
    
    /// Time duration represented by each peak in this tile.
    var peakDuration: TimeInterval {
        guard !peaks.isEmpty else { return 0 }
        return duration / Double(peaks.count)
    }
    
    /// End time of this tile.
    var sourceEndTime: TimeInterval {
        sourceStartTime + duration
    }
}
