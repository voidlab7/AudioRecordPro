import Foundation
import AVFoundation

// MARK: - Provider Delegate
protocol WaveformTileProviderDelegate: AnyObject {
    /// Called on main queue when tiles become available for display.
    func tileProvider(_ provider: WaveformTileProvider, didLoadTiles keys: [WaveformTileKey])
    /// Called on main queue when tile generation fails.
    func tileProvider(_ provider: WaveformTileProvider, didFailForKey key: WaveformTileKey, error: Error)
}

// MARK: - WaveformTileProvider
/// Core engine for on-demand waveform tile generation with multi-level caching.
/// Handles LOD selection, background generation, memory cache, request cancellation,
/// and priority scheduling based on viewport proximity.
class WaveformTileProvider {
    
    // MARK: - Properties
    weak var delegate: WaveformTileProviderDelegate?
    
    let asset: AudioAsset
    
    /// Algorithm version — bump this to invalidate all disk caches.
    static let algorithmVersion = 1
    
    // Memory cache (NSCache auto-evicts under memory pressure)
    private let memoryCache = NSCache<NSString, WaveformTileWrapper>()
    
    // Disk cache
    private let diskCache: WaveformDiskCache
    
    // Background generation queue
    private let generationQueue = OperationQueue()
    private var pendingOperations: [WaveformTileKey: Operation] = [:]
    private let lock = NSLock()
    
    // Request generation counter (for cancellation)
    private var currentRequestGeneration: UInt64 = 0
    
    // MARK: - Initialization
    
    init(asset: AudioAsset) {
        self.asset = asset
        self.diskCache = WaveformDiskCache(assetID: asset.id)
        
        generationQueue.name = "com.audiorecord.waveform.tile-generation"
        generationQueue.maxConcurrentOperationCount = 2
        generationQueue.qualityOfService = .userInitiated
        
        memoryCache.name = "WaveformTileCache-\(asset.id)"
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100MB budget
    }
    
    // MARK: - Public API
    
    /// Request tiles for the current viewport. Returns immediately available tiles.
    /// Missing tiles are scheduled for background generation; delegate is notified when ready.
    /// - Parameters:
    ///   - viewport: Current visible time range and view width.
    ///   - totalDuration: Total audio duration.
    /// - Returns: Array of tiles that are immediately available (from memory cache).
    func requestTiles(for viewport: TimelineViewport, totalDuration: TimeInterval) -> [WaveformTile] {
        let lodConfig = LODConfig.selectLOD(pixelsPerSecond: viewport.pixelsPerSecond, sampleRate: asset.sampleRate)
        let indices = viewport.requiredTileIndices(lodConfig: lodConfig, totalDuration: totalDuration)
        
        // Increment generation to invalidate stale requests
        lock.lock()
        currentRequestGeneration += 1
        let generation = currentRequestGeneration
        lock.unlock()
        
        // Cancel operations that are no longer needed
        let neededKeys = Set(indices.map { WaveformTileKey(assetID: asset.id, lodLevel: lodConfig.level, tileIndex: $0) })
        cancelOutdatedOperations(keepKeys: neededKeys)
        
        var available: [WaveformTile] = []
        var missing: [WaveformTileKey] = []
        
        for index in indices {
            let key = WaveformTileKey(assetID: asset.id, lodLevel: lodConfig.level, tileIndex: index)
            
            // Check memory cache first
            if let cached = memoryCache.object(forKey: key.cacheKey) {
                available.append(cached.tile)
                continue
            }
            
            // Check disk cache
            if let diskTile = diskCache.loadTile(for: key) {
                memoryCache.setObject(WaveformTileWrapper(tile: diskTile), forKey: key.cacheKey)
                available.append(diskTile)
                continue
            }
            
            missing.append(key)
        }
        
        // Schedule background generation for missing tiles
        for key in missing {
            scheduleTileGeneration(key: key, lodConfig: lodConfig, generation: generation)
        }
        
        return available
    }
    
    /// Get a single tile if available in memory cache, nil otherwise.
    func getTile(for key: WaveformTileKey) -> WaveformTile? {
        if let cached = memoryCache.object(forKey: key.cacheKey) {
            return cached.tile
        }
        return nil
    }
    
    /// Store a tile in memory cache (used by disk cache layer to promote tiles).
    func storeTileInMemory(_ tile: WaveformTile) {
        memoryCache.setObject(WaveformTileWrapper(tile: tile), forKey: tile.key.cacheKey)
    }
    
    /// Try to get a lower-LOD fallback tile covering the same time range.
    /// Used for displaying a blurred/faded preview while the target LOD loads.
    func getFallbackTile(for key: WaveformTileKey) -> WaveformTile? {
        guard key.lodLevel > 0 else { return nil }
        
        let lodConfig = LODConfig.allLevels[key.lodLevel]
        let tileStartTime = Double(key.tileIndex) * lodConfig.tileDuration
        
        // Try each lower LOD level
        for fallbackLevel in stride(from: key.lodLevel - 1, through: 0, by: -1) {
            let fallbackConfig = LODConfig.allLevels[fallbackLevel]
            let fallbackIndex = Int(floor(tileStartTime / fallbackConfig.tileDuration))
            let fallbackKey = WaveformTileKey(assetID: asset.id, lodLevel: fallbackLevel, tileIndex: fallbackIndex)
            
            if let tile = getTile(for: fallbackKey) {
                return tile
            }
        }
        return nil
    }
    
    /// Cancel all pending tile generation operations.
    func cancelAll() {
        lock.lock()
        currentRequestGeneration += 1
        pendingOperations.removeAll()
        lock.unlock()
        generationQueue.cancelAllOperations()
    }
    
    /// Invalidate all caches (e.g., after file edit or algorithm version change).
    func invalidateAll() {
        cancelAll()
        memoryCache.removeAllObjects()
        diskCache.clearAll()
    }
    
    /// Invalidate tiles that overlap with a specific time range (e.g., after trim/edit).
    func invalidateTiles(overlapping timeRange: ClosedRange<TimeInterval>) {
        // Invalidate across all LOD levels
        for lodConfig in LODConfig.allLevels {
            let startIndex = Int(floor(timeRange.lowerBound / lodConfig.tileDuration))
            let endIndex = Int(ceil(timeRange.upperBound / lodConfig.tileDuration))
            
            for index in startIndex...endIndex {
                let key = WaveformTileKey(assetID: asset.id, lodLevel: lodConfig.level, tileIndex: index)
                memoryCache.removeObject(forKey: key.cacheKey)
            }
        }
        diskCache.clearTiles(overlapping: timeRange)
    }
    
    // MARK: - Background Generation
    
    private func scheduleTileGeneration(key: WaveformTileKey, lodConfig: LODConfig, generation: UInt64) {
        lock.lock()
        // Don't schedule if already pending
        guard pendingOperations[key] == nil else {
            lock.unlock()
            return
        }
        lock.unlock()
        
        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }
            
            // Check if this generation is still current (user hasn't scrolled away)
            self.lock.lock()
            let isCurrent = generation == self.currentRequestGeneration
            self.lock.unlock()
            guard isCurrent else { return }
            
            do {
                let tile = try self.generateTile(key: key, lodConfig: lodConfig)
                
                // Store in memory cache
                self.memoryCache.setObject(WaveformTileWrapper(tile: tile), forKey: key.cacheKey)
                
                // Persist to disk cache for second-open acceleration
                self.diskCache.saveTile(tile)
                
                // Notify delegate on main queue
                DispatchQueue.main.async {
                    self.delegate?.tileProvider(self, didLoadTiles: [key])
                }
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.tileProvider(self, didFailForKey: key, error: error)
                }
            }
            
            // Remove from pending
            self.lock.lock()
            self.pendingOperations.removeValue(forKey: key)
            self.lock.unlock()
        }
        
        lock.lock()
        pendingOperations[key] = operation
        lock.unlock()
        
        generationQueue.addOperation(operation)
    }
    
    // MARK: - Tile Generation (runs on background queue)
    
    private func generateTile(key: WaveformTileKey, lodConfig: LODConfig) throws -> WaveformTile {
        let tileStartTime = Double(key.tileIndex) * lodConfig.tileDuration
        let tileDuration = min(lodConfig.tileDuration, asset.duration - tileStartTime)
        
        guard tileDuration > 0 else {
            return WaveformTile(key: key, sourceStartTime: tileStartTime, duration: 0, samplesPerPeak: lodConfig.samplesPerPeak, peaks: [])
        }
        
        // Read only the segment we need (not the entire file)
        let audioFile = try AVAudioFile(forReading: asset.url)
        let startFrame = AVAudioFramePosition(tileStartTime * asset.sampleRate)
        let frameCount = AVAudioFrameCount(tileDuration * asset.sampleRate)
        
        audioFile.framePosition = startFrame
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
            throw TileGenerationError.bufferAllocationFailed
        }
        
        try audioFile.read(into: buffer, frameCount: frameCount)
        
        // Extract peaks from the buffer segment
        let peaks = extractPeaks(from: buffer, samplesPerPeak: lodConfig.samplesPerPeak)
        
        return WaveformTile(
            key: key,
            sourceStartTime: tileStartTime,
            duration: tileDuration,
            samplesPerPeak: lodConfig.samplesPerPeak,
            peaks: peaks
        )
    }
    
    /// Extract min/max/rms peaks from a PCM buffer.
    private func extractPeaks(from buffer: AVAudioPCMBuffer, samplesPerPeak: Int) -> [WaveformPeak] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frameCount > 0, channels > 0 else { return [] }
        
        let peakCount = max(1, frameCount / samplesPerPeak)
        var peaks: [WaveformPeak] = []
        peaks.reserveCapacity(peakCount)
        
        for peakIndex in 0..<peakCount {
            let startFrame = peakIndex * samplesPerPeak
            let endFrame = min(startFrame + samplesPerPeak, frameCount)
            guard startFrame < frameCount else { break }
            
            var peakMin: Float = 0
            var peakMax: Float = 0
            var sumSquares: Float = 0
            let sampleCount = (endFrame - startFrame) * channels
            
            for frame in startFrame..<endFrame {
                for ch in 0..<channels {
                    let sample = channelData[ch][frame]
                    peakMin = Swift.min(peakMin, sample)
                    peakMax = Swift.max(peakMax, sample)
                    sumSquares += sample * sample
                }
            }
            
            let rms = sampleCount > 0 ? sqrt(sumSquares / Float(sampleCount)) : 0
            peaks.append(WaveformPeak(min: peakMin, max: peakMax, rms: rms))
        }
        
        return peaks
    }
    
    // MARK: - Cancellation
    
    private func cancelOutdatedOperations(keepKeys: Set<WaveformTileKey>) {
        lock.lock()
        let toCancel = pendingOperations.filter { !keepKeys.contains($0.key) }
        for (key, op) in toCancel {
            op.cancel()
            pendingOperations.removeValue(forKey: key)
        }
        lock.unlock()
    }
    
    // MARK: - Error Types
    
    enum TileGenerationError: Error, LocalizedError {
        case bufferAllocationFailed
        case readFailed(underlying: Error)
        
        var errorDescription: String? {
            switch self {
            case .bufferAllocationFailed:
                return "Failed to allocate audio buffer for tile generation"
            case .readFailed(let error):
                return "Failed to read audio segment: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Cache Wrapper (for NSCache compatibility)
private class WaveformTileWrapper: NSObject {
    let tile: WaveformTile
    init(tile: WaveformTile) {
        self.tile = tile
    }
}
