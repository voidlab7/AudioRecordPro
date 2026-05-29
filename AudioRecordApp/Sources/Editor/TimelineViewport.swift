import Foundation

// MARK: - TimelineViewport
/// Represents the currently visible time range in the editor waveform view.
/// All tile requests and coordinate transforms are driven by this model.
struct TimelineViewport {
    var visibleStartTime: TimeInterval
    var visibleDuration: TimeInterval
    var viewWidth: CGFloat
    
    // MARK: - Computed Properties
    
    var visibleEndTime: TimeInterval {
        visibleStartTime + visibleDuration
    }
    
    var pixelsPerSecond: CGFloat {
        guard visibleDuration > 0 else { return 0 }
        return viewWidth / CGFloat(visibleDuration)
    }
    
    // MARK: - Tile Index Calculation
    
    /// Calculate which tile indices are needed for the current viewport (with prefetch margin).
    /// - Parameters:
    ///   - lodConfig: The LOD configuration to use for tile sizing.
    ///   - totalDuration: Total duration of the audio asset.
    ///   - prefetchRatio: How much extra to fetch on each side (0.5 = half viewport width).
    /// - Returns: Array of tile indices that should be loaded.
    func requiredTileIndices(lodConfig: LODConfig, totalDuration: TimeInterval, prefetchRatio: Double = 0.5) -> [Int] {
        guard totalDuration > 0, lodConfig.tileDuration > 0 else { return [] }
        
        let prefetchDuration = visibleDuration * prefetchRatio
        let fetchStart = max(0, visibleStartTime - prefetchDuration)
        let fetchEnd = min(totalDuration, visibleEndTime + prefetchDuration)
        
        let startIndex = max(0, Int(floor(fetchStart / lodConfig.tileDuration)))
        let endIndex = min(
            lodConfig.tileCount(for: totalDuration) - 1,
            Int(floor(fetchEnd / lodConfig.tileDuration))
        )
        
        guard startIndex <= endIndex else { return [] }
        return Array(startIndex...endIndex)
    }
    
    // MARK: - Coordinate Transforms
    
    /// Convert a time value to pixel x-coordinate within the viewport.
    func timeToPixel(_ time: TimeInterval) -> CGFloat {
        guard visibleDuration > 0 else { return 0 }
        return CGFloat((time - visibleStartTime) / visibleDuration) * viewWidth
    }
    
    /// Convert a pixel x-coordinate to time value.
    func pixelToTime(_ x: CGFloat) -> TimeInterval {
        guard viewWidth > 0 else { return 0 }
        return visibleStartTime + Double(x / viewWidth) * visibleDuration
    }
    
    // MARK: - Viewport Manipulation
    
    /// Zoom the viewport by a factor, anchored at a specific pixel position.
    /// - Parameters:
    ///   - factor: Zoom factor (>1 = zoom in, <1 = zoom out).
    ///   - anchorX: The pixel position to keep stable during zoom.
    ///   - totalDuration: Total audio duration (for clamping).
    ///   - minDuration: Minimum visible duration (prevents over-zoom).
    mutating func zoom(factor: CGFloat, anchorX: CGFloat, totalDuration: TimeInterval, minDuration: TimeInterval = 0.1) {
        let anchorTime = pixelToTime(anchorX)
        let newDuration = max(minDuration, min(totalDuration, visibleDuration / Double(factor)))
        let anchorRatio = Double(anchorX / viewWidth)
        let newStart = anchorTime - newDuration * anchorRatio
        
        visibleStartTime = max(0, min(newStart, totalDuration - newDuration))
        visibleDuration = newDuration
    }
    
    /// Scroll the viewport by a pixel delta.
    /// - Parameters:
    ///   - deltaPixels: Horizontal scroll amount in pixels (positive = scroll right).
    ///   - totalDuration: Total audio duration (for clamping).
    mutating func scroll(deltaPixels: CGFloat, totalDuration: TimeInterval) {
        guard pixelsPerSecond > 0 else { return }
        let deltaTime = Double(deltaPixels) / Double(pixelsPerSecond)
        visibleStartTime = max(0, min(visibleStartTime + deltaTime, totalDuration - visibleDuration))
    }
    
    /// Reset viewport to show the entire audio duration (Fit All).
    mutating func fitAll(totalDuration: TimeInterval) {
        visibleStartTime = 0
        visibleDuration = totalDuration
    }
}
