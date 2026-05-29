# Audio Record Mac - Editor Zoom & Scroll Functionality Map

**Project Location:** `/Users/voidzhang/Documents/workspace/audio_record_mac`

---

## 1. ZOOM & SCROLL IMPLEMENTATIONS

### 1.1 EditorWaveformView - Core Zoom/Scroll Engine
**File:** `AudioRecordApp/Sources/Views/Editor/EditorWaveformView.swift`

#### Zoom Methods:
- **Line 228-235:** `zoomIn(anchorX:)` - Zoom in by 1.5x factor, maintains anchor point
  - Calculates new visible duration: `visibleDuration = totalDuration / Double(zoomLevel)`
  - Clamps zoom to `maxZoomLevel` (line 276-279)
  - Requests tile refresh on zoom
  - **Usage:** Cmd+scroll wheel (up)
  
- **Line 237-244:** `zoomOut(anchorX:)` - Zoom out by 1.5x factor, minimum 1.0
  - Restores visible duration proportionally
  - **Usage:** Cmd+scroll wheel (down)

- **Line 221-226:** `fitAll()` - Reset to 1:1 zoom showing entire audio
  - Sets: `visibleStartTime = 0`, `visibleDuration = totalDuration`, `zoomLevel = 1.0`
  - **Line 96:** Auto-called on audio load

- **Line 203-207:** `setZoomLevel(_ level: Double)` - Programmatic zoom setting
  - Public API for external zoom control
  - Validates minimum zoom of 1.0

#### Zoom Properties:
- **Line 31:** `zoomLevel: CGFloat = 1.0` - Current zoom multiplier
- **Line 29-30:** `visibleStartTime`, `visibleDuration` - Viewport state
- **Line 276-279:** `maxZoomLevel` - Calculated from duration and sample rate
  - Formula: `CGFloat(totalDuration * sampleRate / 600)`
  - Prevents zoom factor exceeding 1 pixel per sample at 600px width

#### Scroll Methods:
- **Line 210-213:** `setScrollOffset(_ offset: Double)` - Programmatic horizontal scroll
  - Clamps to valid range: `[0, totalDuration - visibleDuration]`
  - Updates visible tiles after scroll

- **Line 570-583:** `scrollWheel(with:)` - Mouse scroll wheel handling
  - **Line 571:** Cmd+scroll = Zoom (vertical delta)
  - **Line 579-582:** Normal scroll = Pan (horizontal delta)
    - Scroll amount: `visibleDuration * Double(scrollingDeltaX / bounds.width) * 0.5`
    - Updates `visibleStartTime` and requests new tiles

#### Coordinate Transform Methods:
- **Line 287-290:** `timeToPixel(_ time:)` - Convert time to pixel X position
  - Formula: `CGFloat((time - visibleStartTime) / visibleDuration) * waveformRect.width`
  - Used by: playhead, selection handles, time ruler

- **Line 292-295:** `pixelToTime(_ x:)` - Convert pixel X to time
  - Inverse of `timeToPixel`
  - Used by: mouse interaction, seeking

---

### 1.2 TimelineViewport - Viewport Math Model
**File:** `AudioRecordApp/Sources/Editor/TimelineViewport.swift`

#### Viewport State:
- **Line 7-9:** `visibleStartTime`, `visibleDuration`, `viewWidth`
- **Line 13-15:** `visibleEndTime` (computed)
- **Line 17-20:** `pixelsPerSecond` (computed: `viewWidth / visibleDuration`)

#### Viewport Manipulation Methods:
- **Line 69-77:** `zoom(factor:anchorX:totalDuration:minDuration:)`
  - Generic zoom with anchor point preservation
  - Used by: EditorWaveformView zoom methods
  - Clamps new duration between `minDuration` and `totalDuration`

- **Line 83-87:** `scroll(deltaPixels:totalDuration:)`
  - Converts pixel delta to time delta: `deltaTime = deltaPixels / pixelsPerSecond`
  - Updates `visibleStartTime` with clamping

- **Line 90-93:** `fitAll(totalDuration:)`
  - Reset to full view: `visibleDuration = totalDuration`

#### Tile Index Calculation:
- **Line 30-45:** `requiredTileIndices(lodConfig:totalDuration:prefetchRatio:)`
  - Calculates which tiles needed for viewport (with prefetch margin)
  - Returns sorted array of tile indices to load

---

## 2. WAVEFORM RENDERING

### 2.1 EditorWaveformView - Drawing
**File:** `AudioRecordApp/Sources/Views/Editor/EditorWaveformView.swift`

#### Draw Methods:
- **Line 299-334:** `draw(_:)` - Main render dispatch
  - Checks loading state, error state, empty state
  - Draws: time ruler, selection overlay, waveform (bars or tiles), playhead, handles

- **Line 488-517:** `drawWaveformBars(in:)` - Legacy full-buffer waveform
  - Renders bars with amplitude-based height
  - **Line 510:** Alpha blending: outside selection = dim, inside = bright

- **Line 682-724:** `drawWaveformTiles(in:)` - Tile-based waveform (V2.0)
  - Iterates through `currentTiles` array
  - Renders only visible peaks per tile
  - Skips peaks outside viewport

- **Line 726-743:** `drawSkeletonWaveform(in:)` - Loading placeholder
  - Animated placeholder bars while tiles load
  - Uses `skeletonPhase` for animation

#### Time Ruler:
- **Line 377-468:** `drawTimeRuler(in:)` - Adaptive time labels and ticks
  - Auto-adjusts tick interval based on `pixelsPerSecond` zoom level:
    - `> 200 px/s`: 10ms steps
    - `> 50 px/s`: 0.5s steps
    - `> 15 px/s`: 2s steps
    - `< 15 px/s`: 5s, 10s, or 30s steps
  - Draws main ticks, sub-ticks, and time labels
  - **Line 432-457:** Tick placement logic

#### Selection & Playhead:
- **Line 519-541:** `drawPlayhead(in:)` - Playback cursor with triangle handle
  - Red triangle at bottom, vertical line through waveform
  - Uses `IndustrialColors.waveformAccent` (#FF453A)

- **Line 543-566:** `drawSelectionHandles(in:)` - Selection range handles
  - Cyan rounded rectangles at selection start/end
  - Draggable by mouse for selection resize
  - Uses `IndustrialColors.editorHandle` (#8AEBFF)

- **Line 470-486:** `drawSelectionOverlay(in:)` - Dim areas outside selection
  - Uses `IndustrialColors.editorDimOverlay` (dark with 0.4 alpha)

---

### 2.2 Tile System
**File:** `AudioRecordApp/Sources/Editor/WaveformTileProvider.swift`

#### Tile Generation:
- **Line 42-53:** `init(asset:)` - Initialize tile provider
  - Sets up memory cache (100MB limit, 200 tile limit)
  - Disk cache for persistence
  - Background generation queue (max 2 concurrent ops)

- **Line 63-105:** `requestTiles(for:totalDuration:)` - On-demand tile request
  - Returns immediately available tiles
  - Schedules missing tiles for background generation
  - **Line 74-75:** Selects LOD based on pixel density
  - **Line 100-102:** Schedules generation for missing tiles

- **Line 122-139:** `getFallbackTile(for:)` - Lower-LOD preview
  - Returns lower detail tile while higher-LOD loads
  - Progressive refinement

#### Caching Hierarchy:
1. Memory cache (NSCache, auto-evicted under pressure)
2. Disk cache (persistent across sessions)
3. On-demand generation (background)

---

## 3. EDITOR ARCHITECTURE

### 3.1 EditorViewController - Main Controller
**File:** `AudioRecordApp/Sources/Editor/EditorViewController.swift`

#### View Hierarchy:
```
editorView (NSView)
├── navigationBar (EditorNavigationBar) - Height: 44px
├── waveformView (EditorWaveformView) - Main editor area
├── toolbar (EditorToolbar) - Height: 36px
└── statusBar (EditorStatusBar) - Height: 24px
```

**Line 92-127:** `setupEditorView()` - Auto-layout constraints setup

#### Key Properties:
- **Line 38:** `waveformView` - Core waveform rendering view
- **Line 48:** `session: EditorSession?` - Caches viewport state across file switches

#### Audio Loading:
- **Line 140-246:** `loadAudio()` - Load audio file
  - **Line 159-160:** Decision: tile mode (>60s or >50MB) vs full-buffer
  - **Line 162-200:** Tile mode: loads asset for WaveformTileProvider
  - **Line 201-235:** Legacy mode: full buffer in memory

#### Viewport State Restoration (V2.1):
- **Line 754-760:** `currentViewportState()` - Save zoom/scroll/playhead
- **Line 768-772:** `restoreViewportState(_:)` - Restore on file switch
  - **Line 769-771:** Calls: `setZoomLevel()`, `setScrollOffset()`, `setPlayheadPosition()`

---

### 3.2 EditorSession - State Cache
**File:** `AudioRecordApp/Sources/Editor/EditorSession.swift`

#### Viewport State Struct:
- **Line 5-9:** `ViewportState`
  - `zoomLevel: Double`
  - `scrollOffset: Double`
  - `playheadPosition: Double`

#### Session Properties:
- **Line 23:** `viewportState: ViewportState` - Preserved across file switches
- **Line 19-20:** `audioBuffer`, `audioFormat` - Cached audio data
- **Line 31:** `isLoaded: Bool` - Tracks load state

---

## 4. EDITOR TOOLBAR & NAVIGATION

### 4.1 EditorToolbar - Bottom Control Bar
**File:** `AudioRecordApp/Sources/Views/Editor/EditorToolbar.swift`

#### Components:
- **Line 31-32:** Preview play/stop buttons (center-aligned)
- **Line 88-91:** `updatePreviewState(isPlaying:)` - Toggle button states

#### Height:
- **IndustrialSpacing.editorToolbarHeight = 36px** (from IndustrialDesignTokens.swift:315)

---

### 4.2 EditorNavigationBar - Top Toolbar
**File:** `AudioRecordApp/Sources/Views/Editor/EditorNavigationBar.swift`

#### Components:
- **Line 20:** Back button (◀)
- **Line 22-23:** Undo/Redo buttons (↩↪)
- **Line 25:** Tool buttons (Trim, Silence Trim, Normalize, Fade)
- **Line 26:** Save button

#### Layout (left to right):
```
[◀ Back] | [↩ Undo ↪ Redo] | [✂ 🔇 📊 🔊] ... [Save]
```

#### Height:
- **IndustrialSpacing.editorNavBarHeight = 44px** (from IndustrialDesignTokens.swift:312)

---

### 4.3 EditorStatusBar - Bottom Status Bar
**File:** `AudioRecordApp/Sources/Views/Editor/EditorStatusBar.swift`

#### Display Fields:
- **Line 8:** Current playback time (large, cyan)
- **Line 10:** Total duration (gray)
- **Line 12:** Sample rate, channels, edit count (small, tertiary)

#### Height:
- **IndustrialSpacing.editorStatusBarHeight = 24px** (from IndustrialDesignTokens.swift:318)

#### Time Formatting:
- **Line 108-113:** `formatTimePrecise()` - MM:SS.ms format (3 decimal places)
- **Line 101-106:** `formatTime()` - MM:SS.cs format (2 decimal places)

---

## 5. INDUSTRIAL DESIGN TOKENS

### 5.1 Colors - IndustrialColors
**File:** `AudioRecordApp/Sources/Utilities/IndustrialDesignTokens.swift`

#### Editor-Specific Colors:
- **Line 239:** `editorHandle = #8AEBFF` - Cyan selection handles
- **Line 242:** `editorDimOverlay = #0E1416, alpha:0.4` - Selection dim
- **Line 245:** `editorSilenceOverlay = #242B2D, alpha:0.6` - Silence highlight
- **Line 248:** `editorSilenceLine = #FFB4AB` - Silence delete marker
- **Line 251:** `editorEditingBadge = #FFD6A3` - Edit status badge

#### Waveform Colors:
- **Line 198:** `waveformAccent = #FF453A` - Playhead (Apple red)
- **Line 201:** `waveformCoral = #FF6B5F` - Main waveform bars
- **Line 204:** `waveformSoft = #FF8A80` - Secondary/weak bars
- **Line 207:** `waveformMuted = #FF6B5F, alpha:0.32` - Silence bars

#### Surface Colors:
- **Line 12:** `surface = #0E1416` - Main background
- **Line 24:** `surfaceContainerLow = #161D1E` - Waveform background
- **Line 27:** `surfaceContainer = #1A2122` - Toolbar background
- **Line 38:** `primary = #8AEBFF` - Cyan accent

---

### 5.2 Spacing - IndustrialSpacing
**File:** `AudioRecordApp/Sources/Utilities/IndustrialDesignTokens.swift`

#### Editor Dimensions:
- **Line 312:** `editorNavBarHeight = 44`
- **Line 315:** `editorToolbarHeight = 36`
- **Line 318:** `editorStatusBarHeight = 24`
- **Line 321:** `editorHandleWidth = 4` - Selection handle width
- **Line 324:** `editorHandleHitZone = 8` - Mouse hit detection zone

#### Standard Spacing:
- **Line 283:** `unit = 4` - Base unit
- **Line 286:** `xs = 4` - Extra small
- **Line 289:** `sm = 8` - Small
- **Line 292:** `md = 16` - Medium
- **Line 295:** `lg = 24` - Large

---

### 5.3 Typography - IndustrialTypography
**File:** `AudioRecordApp/Sources/Utilities/IndustrialDesignTokens.swift`

#### Editor Fonts:
- **Line 273:** `timer = 28px Bold monospace` - Large time display
- **Line 276:** `monoDB = 10px Regular monospace` - Small DB values
- **Line 264:** `body = 13px Regular` - Default text
- **Line 264:** `label = 11px Semibold` - Labels

---

## 6. MOUSE INTERACTION

### 6.1 EditorWaveformView - Mouse Events
**File:** `AudioRecordApp/Sources/Views/Editor/EditorWaveformView.swift`

#### Drag Modes:
- **Line 41:** `enum DragMode` - `none | panScroll | leftHandle | rightHandle | seeking | creating`

#### Mouse Down (Line 585-614):
1. Check if clicking on selection handle (left/right)
2. If not, prepare to seek or create selection
3. Immediately seek to click position (line 611)

#### Mouse Dragged (Line 616-655):
1. **leftHandle/rightHandle:** Drag to resize selection
2. **seeking:** If drag >5px threshold, switch to selection creation
3. **creating:** Extend selection to follow mouse
4. Updates delegate with selection changes

#### Mouse Up (Line 657-666):
1. If selection < 0.05s, clear it (minimum threshold)
2. Finalize selection state

#### Cursor Rects (Line 668-678):
- Show resize cursor over selection handles (±8px hit zone)
- Updates dynamically when selection changes

#### Scroll Wheel (Line 570-583):
- **Cmd+Up:** `zoomIn()`
- **Cmd+Down:** `zoomOut()`
- **Horizontal scroll:** Pan waveform left/right

---

## 7. EDIT OPERATIONS & STATE MANAGEMENT

### 7.1 Edit Commands
**File:** `AudioRecordApp/Sources/Editor/EditorViewController.swift`

#### Operations Triggering Waveform Refresh:
- **Line 250-272:** `executeCommand(_:)` - Runs edit, invalidates tiles
- **Line 274-286:** `undo()` - Undoes last operation
- **Line 288-300:** `redo()` - Redoes operation

#### After Each Edit:
```swift
waveformView.loadAudio(from: buffer, sampleRate: format.sampleRate)
waveformView.invalidateAllTiles()  // Clears tile cache
```

**Line 257-259:** Invalidates tile caches after edits (audio has changed)

---

## 8. KEY LINE NUMBER REFERENCES

### Zoom/Scroll:
| Feature | File | Lines |
|---------|------|-------|
| zoomIn() | EditorWaveformView.swift | 228-235 |
| zoomOut() | EditorWaveformView.swift | 237-244 |
| fitAll() | EditorWaveformView.swift | 221-226 |
| setZoomLevel() | EditorWaveformView.swift | 203-207 |
| setScrollOffset() | EditorWaveformView.swift | 210-213 |
| scrollWheel() | EditorWaveformView.swift | 570-583 |
| Zoom::zoom() | TimelineViewport.swift | 69-77 |
| Scroll::scroll() | TimelineViewport.swift | 83-87 |

### Rendering:
| Feature | File | Lines |
|---------|------|-------|
| drawWaveformBars() | EditorWaveformView.swift | 488-517 |
| drawWaveformTiles() | EditorWaveformView.swift | 682-724 |
| drawTimeRuler() | EditorWaveformView.swift | 377-468 |
| drawPlayhead() | EditorWaveformView.swift | 519-541 |
| drawSelectionHandles() | EditorWaveformView.swift | 543-566 |
| drawSelectionOverlay() | EditorWaveformView.swift | 470-486 |

### Architecture:
| Component | File | Lines |
|-----------|------|-------|
| EditorViewController setup | EditorViewController.swift | 92-127 |
| EditorSession state | EditorSession.swift | 5-9 |
| Viewport state restore | EditorViewController.swift | 754-772 |
| View hierarchy | EditorViewController.swift | 36-44 |

### Design Tokens:
| Tokens | File | Lines |
|--------|------|-------|
| Editor colors | IndustrialDesignTokens.swift | 236-252 |
| Spacing (editor) | IndustrialDesignTokens.swift | 309-325 |
| Typography | IndustrialDesignTokens.swift | 254-277 |
| Waveform colors | IndustrialDesignTokens.swift | 195-208 |

---

## 9. SCROLL & SCROLLBAR NOTES

### Current Scroll Implementation:
- **No visual scrollbar** - Scroll is implicit in the waveform viewport
- **Horizontal panning:** Mouse scroll wheel or drag (not implemented in code shown)
- **Scroll encode/decode:** Line 579-582 in EditorWaveformView
  - `scrollingDeltaX` mapped to time offset
  - Smooth continuous scrolling via scroll wheel

### Potential Scrollbar Additions:
If horizontal scrollbar needed:
1. Add NSScroller under waveformView
2. Bind to `visibleStartTime / totalDuration` position
3. Bind size to `visibleDuration / totalDuration`
4. Handle scroller actions to update `visibleStartTime`
5. Update scroller when zoom/scroll changes

---

## 10. AUDIO ASSET & TILE KEY STRUCTURES

### AudioAsset (referenced in code):
```swift
class AudioAsset {
    let id: String
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double
    let channelCount: Int
    let fileSize: Int64
    let modifiedAt: Date
}
```

### WaveformTileKey (referenced in code):
```swift
struct WaveformTileKey {
    let assetID: String
    let lodLevel: Int
    let tileIndex: Int
}
```

### WaveformTile (referenced in code):
```swift
struct WaveformTile {
    let key: WaveformTileKey
    let sourceStartTime: TimeInterval
    let duration: TimeInterval
    let peaks: [WaveformPeak]
}
```

---

## 11. VIEWPORT STATE RESTORATION FLOW (V2.1)

```
User switches files:
1. EditorViewController.currentViewportState() 
   → Returns ViewportState (zoom, scroll, playhead)
2. SessionManager saves to EditorSession
3. User opens new file
4. EditorViewController.restoreViewportState(state)
   → waveformView.setZoomLevel(state.zoomLevel)
   → waveformView.setScrollOffset(state.scrollOffset)
   → waveformView.setPlayheadPosition(state.playheadPosition)
```

---

**End of Code Map**

Generated: 2026-05-25
Project: Audio Record Mac (macOS audio editor)
Scope: Zoom, scroll, waveform rendering, editor architecture
