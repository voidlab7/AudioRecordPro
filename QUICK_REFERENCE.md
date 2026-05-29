# Audio Record Mac - Zoom & Scroll Quick Reference Card

## 🎯 Key Files at a Glance

| Component | File | Key Methods | Lines |
|-----------|------|-------------|-------|
| **Waveform Editor** | EditorWaveformView.swift | `zoomIn/Out()`, `fitAll()`, `scrollWheel()` | 228-244, 570-583 |
| **Viewport Logic** | TimelineViewport.swift | `zoom()`, `scroll()`, `fitAll()` | 69-93 |
| **Tile Provider** | WaveformTileProvider.swift | `requestTiles()`, `getFallbackTile()` | 63-139 |
| **Main Controller** | EditorViewController.swift | `setupEditorView()`, `loadAudio()`, `restoreViewportState()` | 92-127, 754-772 |
| **Session State** | EditorSession.swift | `ViewportState` struct | 5-9 |
| **Design System** | IndustrialDesignTokens.swift | Colors, spacing, typography | 6-344 |

---

## 🖱️ User Interactions

### Keyboard + Mouse
```
Cmd + Scroll Up       → Zoom in (1.5× multiplier, anchor at cursor)
Cmd + Scroll Down     → Zoom out (1.5× divisor, min 1.0)
Scroll Left/Right     → Pan waveform horizontally
Click on waveform     → Seek to position (display playhead)
Click + Drag (>5px)   → Create/resize selection
Click + Drag handle   → Resize selection edge
```

---

## 📊 Zoom State Model

```swift
// EditorWaveformView properties
zoomLevel: CGFloat = 1.0           // 1.0 = fit all, >1 = zoomed in
visibleStartTime: TimeInterval     // Viewport left edge (seconds)
visibleDuration: TimeInterval      // Viewport width (seconds)
totalDuration: TimeInterval        // Full audio length
maxZoomLevel: CGFloat              // totalDuration * sampleRate / 600

// Derived
pixelsPerSecond = waveformRect.width / visibleDuration
visibleEndTime = visibleStartTime + visibleDuration
```

---

## 🔧 Core Methods Reference

### Zoom Operations
```swift
// Zoom in with anchor point preservation
zoomIn(anchorX: CGFloat? = nil)
  → zoomLevel *= 1.5 (clamped to maxZoomLevel)
  → visibleDuration = totalDuration / zoomLevel
  → visibleStartTime adjusted to keep anchorX stable

// Zoom out (inverse)
zoomOut(anchorX: CGFloat? = nil)
  → zoomLevel /= 1.5 (min 1.0)
  → visibleDuration = totalDuration / zoomLevel
  → visibleStartTime adjusted to keep anchorX stable

// Reset to 1:1 (entire audio visible)
fitAll()
  → zoomLevel = 1.0
  → visibleStartTime = 0
  → visibleDuration = totalDuration

// Programmatic zoom setting
setZoomLevel(_ level: Double)
  → zoomLevel = max(1.0, level)
  → visibleDuration = totalDuration / Double(zoomLevel)
```

### Scroll Operations
```swift
// Programmatic horizontal scroll
setScrollOffset(_ offset: Double)
  → visibleStartTime = max(0, min(offset, totalDuration - visibleDuration))
  → requestVisibleTiles() [if tile mode]

// Mouse scroll wheel handling
scrollWheel(with: NSEvent)
  → if Cmd key: zoom (vertical delta)
  → else: pan (horizontal delta = visibleDuration × scrollingDeltaX/width × 0.5)
```

### Coordinate Transforms
```swift
// Time → Pixel (for drawing)
timeToPixel(_ time: TimeInterval) -> CGFloat
  = (time - visibleStartTime) / visibleDuration × waveformRect.width + minX

// Pixel → Time (for interaction)
pixelToTime(_ x: CGFloat) -> TimeInterval
  = visibleStartTime + (x / waveformRect.width) × visibleDuration
```

---

## 🎨 Color Palette

| Element | Color | Hex Code | Notes |
|---------|-------|----------|-------|
| Waveform bars | Coral | #FF6B5F | Main audio peaks |
| Playhead line | Red | #FF453A | Apple native recording red |
| Selection handles | Cyan | #8AEBFF | Primary accent color |
| Selection dim | Dark | #0E1416, 0.4α | Outside selection area |
| Background | Dark | #161D1E | Container low |
| Center line | Grid | #FFFFFF, 0.06α | 50% reference (dashed) |

---

## 📐 Spacing & Dimensions

| Element | Size | Notes |
|---------|------|-------|
| Nav bar height | 44px | Back, Undo/Redo, Tools, Save |
| Toolbar height | 36px | Play/Pause/Stop (centered) |
| Status bar height | 24px | Time / Duration / Info |
| Handle width | 4px | Selection edge indicator |
| Handle hit zone | ±8px | Mouse click detection radius |
| Waveform padding | 16px | Left/right margins |

---

## 🔄 Tile System Integration

When viewport changes (zoom/scroll):

1. **requestVisibleTiles()** called
2. **TimelineViewport** calculates required tile indices
3. **WaveformTileProvider.requestTiles()** checks caches:
   - Memory cache (100MB limit)
   - Disk cache (persistent)
   - Background generation queue
4. **currentTiles** array updated with available tiles
5. **drawWaveformTiles()** renders visible peaks
6. Missing tiles loaded asynchronously
7. Delegate callback → redraw with new tiles

---

## 🎬 Mouse Interaction State Machine

```
State: NONE
  ├─ mouseDown()
  │   ├─ On handle? → State: LEFT/RIGHT_HANDLE
  │   └─ Not on handle? → State: SEEKING (seek immediately)
  │
  ├─ mouseDragged()
  │   ├─ SEEKING + drag>5px? → State: CREATING
  │   ├─ LEFT/RIGHT_HANDLE? → Resize selection
  │   └─ CREATING? → Extend selection
  │
  └─ mouseUp()
      ├─ CREATING + duration<0.05s? → Clear selection
      └─ State: NONE (reset)
```

---

## 📋 Time Ruler Adaptive Scale

| Pixels/Second | Tick Step | Sub-steps | Format | Example |
|--------------|-----------|-----------|--------|---------|
| > 200 | 10ms | 5 | M:SS.sss | 0:12.345 |
| > 50 | 0.5s | 5 | M:SS.ms | 0:15.5 |
| > 15 | 2s | 4 | M:SS | 0:15 |
| < 15 | 5/10/30s | 5 | M:SS | 2:45 |

(Step chosen based on duration; more spacing = larger steps)

---

## 🔐 Viewport State Persistence (V2.1)

```swift
struct ViewportState {
    var zoomLevel: Double         // Current zoom multiplier
    var scrollOffset: Double      // Visible start time (seconds)
    var playheadPosition: Double  // Cursor position (seconds)
}

// Save on file switch
currentViewportState() → EditorSession[file].viewportState

// Restore when returning
restoreViewportState(_ state)
  → setZoomLevel(state.zoomLevel)
  → setScrollOffset(state.scrollOffset)
  → setPlayheadPosition(state.playheadPosition)
```

---

## 📦 View Hierarchy

```
editorView
├── EditorNavigationBar (top bar)
├── EditorWaveformView (main content)
│   ├── Time ruler (top of waveform)
│   ├── Waveform bars/tiles (main area)
│   ├── Playhead (red line + triangle)
│   ├── Selection handles (cyan rectangles)
│   └── Selection overlay (dim outside areas)
├── EditorToolbar (play/stop buttons)
└── EditorStatusBar (time / duration / info)
```

---

## 🚀 Performance Tips

1. **Zooming:** 1.5× multiplier provides smooth progression
2. **Tile prefetch:** Loads tiles 50% beyond viewport on each side
3. **LOD selection:** Auto-selects resolution based on pixel density
4. **Memory cache:** NSCache auto-evicts under pressure (100MB limit)
5. **Background generation:** Max 2 concurrent tile operations

---

## 🐛 Common Issues & Fixes

| Issue | Cause | Solution |
|-------|-------|----------|
| Selection handles off-screen | visibleStartTime bounds unchecked | Verify clamp in `setScrollOffset()` |
| Time ruler labels overlap | pixelsPerSecond too low | Check tick interval logic in `drawTimeRuler()` |
| Tiles don't load | Cache miss, generation queue full | Check WaveformTileProvider delegate |
| Playhead jumps on zoom | Coordinate transform error | Verify `timeToPixel()` formula |
| Selection lost on edit | Edit invalidates tiles but not selection | Save/restore selection after edits |

---

## 📞 Key Delegates & Callbacks

```swift
// EditorWaveformViewDelegate
func editorWaveformView(_, didChangeSelection range:)  // Selection changed
func editorWaveformView(_, didSeekTo time:)             // Cursor moved

// WaveformTileProviderDelegate
func tileProvider(_, didLoadTiles keys:)                // Tiles ready
func tileProvider(_, didFailForKey key:, error:)        // Tile generation failed

// EditorToolbarDelegate
func editorToolbarDidTapPreviewPlay(_)                  // Play button
func editorToolbarDidTapPreviewStop(_)                  // Stop button
```

---

## 🔍 Debugging Checklist

- [ ] **Zoom bounds:** Is `zoomLevel` clamped between 1.0 and `maxZoomLevel`?
- [ ] **Scroll bounds:** Is `visibleStartTime` in `[0, totalDuration - visibleDuration]`?
- [ ] **Viewport math:** Does `pixelsPerSecond` calculation match screen state?
- [ ] **Tile requests:** Are missing tiles scheduled for background generation?
- [ ] **Drawing:** Is `needsDisplay = true` called after viewport changes?
- [ ] **Selection:** Do handles appear at correct `timeToPixel()` positions?
- [ ] **Time ruler:** Does tick interval adapt to `pixelsPerSecond`?

---

**Last Updated:** 2026-05-25  
**Project:** Audio Record Mac  
**Scope:** Editor zoom, scroll, waveform rendering

