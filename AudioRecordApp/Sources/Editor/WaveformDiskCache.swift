import Foundation

// MARK: - WaveformDiskCache
/// Disk-based cache for waveform tiles, enabling fast second-open of audio files.
/// Uses a compact binary format for minimal I/O overhead.
/// Cache key incorporates file metadata + algorithm version for automatic invalidation.
class WaveformDiskCache {
    
    // MARK: - Properties
    private let assetID: String
    private let cacheDirectory: URL
    
    /// Bump this when the binary format changes to invalidate all existing caches.
    static let cacheVersion: UInt8 = 2
    
    // MARK: - Initialization
    
    init(assetID: String) {
        self.assetID = assetID
        
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesDir
            .appendingPathComponent("AudioRecord")
            .appendingPathComponent("Waveforms")
            .appendingPathComponent(assetID)
        
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Load a tile from disk cache. Returns nil if not cached or cache is invalid.
    func loadTile(for key: WaveformTileKey) -> WaveformTile? {
        let fileURL = tileFileURL(for: key)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return decodeTile(from: data, key: key)
    }
    
    /// Save a tile to disk cache. Failures are silently ignored (cache is best-effort).
    func saveTile(_ tile: WaveformTile) {
        let fileURL = tileFileURL(for: tile.key)
        guard let data = encodeTile(tile) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    /// Remove all cached tiles for this asset.
    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Remove cached tiles that overlap with a specific time range.
    func clearTiles(overlapping timeRange: ClosedRange<TimeInterval>) {
        for lodConfig in LODConfig.allLevels {
            let startIndex = Int(floor(timeRange.lowerBound / lodConfig.tileDuration))
            let endIndex = Int(ceil(timeRange.upperBound / lodConfig.tileDuration))
            
            for index in startIndex...endIndex {
                let key = WaveformTileKey(assetID: assetID, lodLevel: lodConfig.level, tileIndex: index)
                let fileURL = tileFileURL(for: key)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
    
    // MARK: - Static Utilities
    
    /// Remove all waveform caches globally (e.g., on algorithm version change or app reset).
    static func clearGlobalCache() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let waveformDir = cachesDir
            .appendingPathComponent("AudioRecord")
            .appendingPathComponent("Waveforms")
        try? FileManager.default.removeItem(at: waveformDir)
    }
    
    /// Calculate total disk usage of all waveform caches.
    static func totalCacheSize() -> Int64 {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let waveformDir = cachesDir
            .appendingPathComponent("AudioRecord")
            .appendingPathComponent("Waveforms")
        
        guard let enumerator = FileManager.default.enumerator(
            at: waveformDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }
    
    // MARK: - Private — File Path
    
    private func tileFileURL(for key: WaveformTileKey) -> URL {
        cacheDirectory.appendingPathComponent("lod\(key.lodLevel)_tile\(key.tileIndex).wfcache")
    }
    
    // MARK: - Private — Binary Encoding
    
    /// Binary format (compact, no JSON overhead):
    /// [version: UInt8]
    /// [startTime: Float64]
    /// [duration: Float64]
    /// [samplesPerPeak: Int32]
    /// [peakCount: Int32]
    /// [peaks: peakCount × (min: Float32, max: Float32, rms: Float32)]
    ///
    /// Total header: 1 + 8 + 8 + 4 + 4 = 25 bytes
    /// Each peak: 12 bytes
    /// Typical tile (100 peaks): 25 + 1200 = 1225 bytes
    
    private func encodeTile(_ tile: WaveformTile) -> Data? {
        var data = Data()
        data.reserveCapacity(25 + tile.peaks.count * 12)
        
        // Header
        var version = Self.cacheVersion
        data.append(Data(bytes: &version, count: 1))
        
        var startTime = tile.sourceStartTime
        data.append(Data(bytes: &startTime, count: MemoryLayout<Double>.size))
        
        var duration = tile.duration
        data.append(Data(bytes: &duration, count: MemoryLayout<Double>.size))
        
        var spp = Int32(tile.samplesPerPeak)
        data.append(Data(bytes: &spp, count: MemoryLayout<Int32>.size))
        
        var count = Int32(tile.peaks.count)
        data.append(Data(bytes: &count, count: MemoryLayout<Int32>.size))
        
        // Peaks
        for peak in tile.peaks {
            var minVal = peak.min
            var maxVal = peak.max
            var rmsVal = peak.rms ?? -1.0  // -1.0 sentinel for "no RMS"
            data.append(Data(bytes: &minVal, count: MemoryLayout<Float>.size))
            data.append(Data(bytes: &maxVal, count: MemoryLayout<Float>.size))
            data.append(Data(bytes: &rmsVal, count: MemoryLayout<Float>.size))
        }
        
        return data
    }
    
    private func decodeTile(from data: Data, key: WaveformTileKey) -> WaveformTile? {
        let headerSize = 1 + MemoryLayout<Double>.size * 2 + MemoryLayout<Int32>.size * 2
        guard data.count >= headerSize else { return nil }

        var offset = 0

        // Version check
        let version = data[offset]
        guard version == Self.cacheVersion else { return nil }
        offset += 1

        // Safe unaligned read using memcpy (fixes Apple Silicon crash at unaligned offsets)
        var startTime: Double = 0
        _ = data.withUnsafeBytes { memcpy(&startTime, $0.baseAddress! + offset, MemoryLayout<Double>.size) }
        offset += MemoryLayout<Double>.size

        var duration: Double = 0
        _ = data.withUnsafeBytes { memcpy(&duration, $0.baseAddress! + offset, MemoryLayout<Double>.size) }
        offset += MemoryLayout<Double>.size

        var spp: Int32 = 0
        _ = data.withUnsafeBytes { memcpy(&spp, $0.baseAddress! + offset, MemoryLayout<Int32>.size) }
        offset += MemoryLayout<Int32>.size

        var count: Int32 = 0
        _ = data.withUnsafeBytes { memcpy(&count, $0.baseAddress! + offset, MemoryLayout<Int32>.size) }
        offset += MemoryLayout<Int32>.size

        // Validate: count must be non-negative and data size sufficient
        guard count >= 0 else { return nil }
        let peakSize = MemoryLayout<Float>.size * 3  // min + max + rms
        guard data.count >= offset + Int(count) * peakSize else { return nil }

        // Decode peaks
        var peaks: [WaveformPeak] = []
        peaks.reserveCapacity(Int(count))

        for _ in 0..<count {
            var minVal: Float = 0
            _ = data.withUnsafeBytes { memcpy(&minVal, $0.baseAddress! + offset, MemoryLayout<Float>.size) }
            offset += MemoryLayout<Float>.size

            var maxVal: Float = 0
            _ = data.withUnsafeBytes { memcpy(&maxVal, $0.baseAddress! + offset, MemoryLayout<Float>.size) }
            offset += MemoryLayout<Float>.size

            var rmsVal: Float = 0
            _ = data.withUnsafeBytes { memcpy(&rmsVal, $0.baseAddress! + offset, MemoryLayout<Float>.size) }
            offset += MemoryLayout<Float>.size

            peaks.append(WaveformPeak(min: minVal, max: maxVal, rms: rmsVal < 0 ? nil : rmsVal))
        }

        return WaveformTile(
            key: key,
            sourceStartTime: startTime,
            duration: duration,
            samplesPerPeak: Int(spp),
            peaks: peaks
        )
    }
}
