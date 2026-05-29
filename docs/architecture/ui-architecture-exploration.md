# AudioRecord Mac App - UI Design & Architecture Exploration Report

**Project Root:** `/Users/voidzhang/Documents/workspace/audio_record_mac`  
**Platform:** macOS (AppKit + Swift)  
**Design Pattern:** Industrial Design (work-studio-grade professional appearance)  
**Architecture:** Component-based with delegate pattern

---

## 1. PROJECT STRUCTURE

### Directory Layout
```
AudioRecordApp/
├── Sources/
│   ├── App/
│   │   ├── main.swift                    # Entry point: NSApplication setup
│   │   └── AppDelegate.swift             # Window creation & lifecycle
│   ├── Controllers/
│   │   ├── MainViewController.swift      # Main view controller (UI logic)
│   │   └── AudioRecorderController.swift # Audio recording backend
│   ├── Views/                            # SwiftUI/AppKit Views (primary UI)
│   │   ├── MainWindowView.swift          # Main window container (master layout)
│   │   ├── SidebarView.swift             # Left sidebar (audio sources + saved files)
│   │   ├── TabContainerView.swift        # Tab switching container
│   │   ├── ControlPanelView.swift        # Transport controls & recording button
│   │   ├── WaveformView.swift            # Waveform visualization
│   │   ├── LevelMetersOverlay.swift      # L/R level meters
│   │   ├── TracksView.swift              # Active tracks display
│   │   ├── StatusBarView.swift           # Status information bar
│   │   ├── RecordedFilesView.swift       # Saved files list
│   │   ├── IndustrialControls.swift      # Reusable UI components
│   │   └── TimerLabel.swift              # Timer display
│   └── Utilities/
│       └── IndustrialDesignTokens.swift  # Design system (colors, spacing, etc.)
├── AudioRecordKit/                       # Shared recording SDK
├── Info.plist                            # App metadata & permissions
└── AudioRecordMac.entitlements          # App capabilities
```

### Key File Counts
- **Swift View Files:** 13 files
- **Swift Controller Files:** 2 files
- **Total Swift Files in App:** 17 files

---

## 2. APP LAUNCH FLOW & INITIAL STATE

### 2.1 Startup Sequence

```
main.swift
  ↓
NSApplicationMain() 
  ↓
AppDelegate.applicationDidFinishLaunching()
  │
  ├─ clearLogFiles()                    # Clean old logs
  ├─ requestAudioCapturePermissions()   # Request mic + system audio permissions
  ├─ createMainWindow()                  # Create NSWindow (800x500)
  │  │
  │  ├─ NSWindow initialization (800x500, titled, closable, miniaturizable, resizable)
  │  ├─ MainViewController creation
  │  ├─ MainWindowView assigned as contentViewController
  │  ├─ window.makeKeyAndOrderFront()    # Show window
  │  └─ NSApp.activate(ignoringOtherApps: true)
  │
  └─ Fallback front() dispatch @ 0.3s
```

### 2.2 Window Configuration

**File:** `AppDelegate.swift` (lines 121-217)

```swift
// Window properties:
window = NSWindow(
    contentRect: NSMakeRect(0, 0, 800, 500),  // Initial size: 800×500
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)

// Key settings:
window.title = "音频录制工具"
window.isRestorable = false               // Don't restore previous state
window.minSize = NSSize(width: 800, height: 500)
window.isReleasedWhenClosed = false
window.hidesOnDeactivate = false

// Fullscreen behavior:
window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]

// Toolbar:
let toolbar = NSToolbar(identifier: "MainToolbar")
toolbar.displayMode = .iconOnly
toolbar.showsBaselineSeparator = false
window.toolbar = toolbar
window.toolbarStyle = .expanded  // (macOS 11+)
window.titleVisibility = .visible
window.titlebarAppearsTransparent = false
```

**Default Window Size:** 800×500 pixels (not restorable)

---

## 3. UI HIERARCHY & LAYOUT

### 3.1 Main View Structure

**File:** `MainWindowView.swift` (primary layout orchestration)

```
MainWindowView (NSView)
│
├─ NSSplitView (vertical)
│  │
│  ├─ SidebarView (left panel, fixed 280px width)
│  │  └─ TabContainerView
│  │     ├─ Tab 1: Audio Recorder
│  │     │  ├─ targetHeader ("录制目标")
│  │     │  ├─ targetHintLabel
│  │     │  ├─ systemTargetRow (全部系统声音 - SELECTED BY DEFAULT)
│  │     │  ├─ appsHeader ("选择应用声音")
│  │     │  ├─ refreshButton
│  │     │  ├─ appsScroll (scrollable list of processes)
│  │     │  └─ microphonePanel (麦克风叠加)
│  │     │
│  │     └─ Tab 2: Saved Files
│  │        └─ RecordedFilesView (list of recorded files)
│  │
│  └─ ContentView (right panel, flexible)
│     ├─ WaveformView (waveform visualization, 42% height)
│     │  └─ LevelMetersOverlay (L/R meters, top-right, 180×64)
│     ├─ TracksView (active tracks display)
│     ├─ ControlPanelView (transport controls, 150px height)
│     └─ StatusBarView (status text, 28px height)
```

### 3.2 Sidebar/Left Panel Configuration

**Default State at Launch:**

The sidebar is **ALWAYS VISIBLE** and **NOT COLLAPSIBLE** (NSSplitView delegate forbids collapse):

```swift
// File: MainWindowView.swift, lines 312-314
func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
    return false  // ← Sidebar CANNOT be collapsed
}
```

**Initial Sidebar Width:** 280 pixels (constant constraint)

```swift
// File: MainWindowView.swift, line 93
sidebarView.widthAnchor.constraint(equalToConstant: IndustrialSpacing.sidebarWidth)
// IndustrialSpacing.sidebarWidth = 280 (from IndustrialDesignTokens.swift)
```

**Min/Max Sidebar Width (draggable):**
- **Minimum:** 200px
- **Maximum:** 400px

```swift
// File: MainWindowView.swift, lines 301-310
func splitView(_ splitView: NSSplitView,
               constrainMinCoordinate proposedMinimumPosition: CGFloat,
               ofSubviewAt dividerIndex: Int) -> CGFloat {
    return 200  // Sidebar can shrink to 200px
}

func splitView(_ splitView: NSSplitView,
               constrainMaxCoordinate proposedMaximumPosition: CGFloat,
               ofSubviewAt dividerIndex: Int) -> CGFloat {
    return 400  // Sidebar can expand to 400px
}
```

**Default Tab:** "Audio Recorder" (Tab 1 is auto-selected as first tab)

```swift
// File: TabContainerView.swift, lines 98-101
if selectedTabId == nil {
    selectTab(tab.id)  // First tab auto-selected
}
```

### 3.3 Sidebar Content - Audio Recorder Tab (Default)

**File:** `SidebarView.swift` (partial, lines 119-280)

**Components in Order:**
1. **Target Header** - "录制目标" (UPPERCASE)
2. **Hint Label** - "先选要录的声音；麦克风作为附加输入"
3. **System Target Row** - "全部系统声音" ← **SELECTED BY DEFAULT** ✓
4. **Apps Header** - "选择应用声音"
5. **Refresh Button** - Refresh process list
6. **Apps Scroll View** - List of audio processes (scrollable)
7. **Microphone Panel** - Toggle mic mixing

**Key: Default Selection State**

```swift
// File: SidebarView.swift, lines 195-199
private func setupTargetControls() {
    systemTargetRow.translatesAutoresizingMaskIntoConstraints = false
    systemTargetRow.isSelectedTarget = true  // ← DEFAULT IS "全部系统声音"
    systemTargetRow.onClick = { [weak self] in
        self?.selectSystemAudioTarget()
    }
}
```

This is set up during view initialization, so **"全部系统声音" (All System Audio) is ALWAYS pre-selected at app launch**.

### 3.4 Control Panel (Bottom Section)

**File:** `ControlPanelView.swift` (lines 14-40)

```
ControlPanelView (150px height)
├─ topSeparator (visual divider)
├─ headerLabel ("TRANSPORT CONTROL")
├─ statusBadge (shows "STANDBY", "RECORDING", etc.)
├─ readoutLabel ("INPUT BUS: READY    FORMAT: WAV    SAMPLE RATE: 48KHZ")
├─ timerLabel (large cyan-glowing timer: "00:00:00")
├─ buttonContainer (hardware-styled button layout)
│  ├─ recordButton (64px red button, pulsing glow)
│  ├─ outerRingLayer (visual ring effect)
│  └─ innerSquareLayer (white stop square during recording)
└─ playButton + stopButton (small transport controls)
```

**Initial Recording Button State:** IDLE (not recording)

---

## 4. SIDEBAR STATE MANAGEMENT

### 4.1 UI State at Launch (SidebarView)

**File:** `SidebarView.swift`

```swift
// Lines 195-206: Default state setup
private func setupTargetControls() {
    systemTargetRow.translatesAutoresizingMaskIntoConstraints = false
    systemTargetRow.isSelectedTarget = true         // ✓ PRE-SELECTED
    
    microphonePanel.translatesAutoresizingMaskIntoConstraints = false
    microphonePanel.onChange = { [weak self] enabled in
        self?.microphoneInputChanged(enabled: enabled)
    }
}

// Lines 283-290: Selection handling
private func selectSystemAudioTarget() {
    logger.info("录制目标切换为：全部系统声音")
    selectedPIDs = []                               // No specific process
    systemTargetRow.isSelectedTarget = true         // ✓ MARK AS SELECTED
    rebuildProcessRows()                            // Rebuild visual list
    delegate?.sidebarViewDidSelectProcesses(self, pids: [])
    delegate?.sidebarViewDidChangeSourceSelection(self)
}

// Lines 337-343: Query APIs
func isSystemAudioSourceSelected() -> Bool {
    return selectedPIDs.isEmpty                     // ✓ True at startup
}

func isMicrophoneSourceSelected() -> Bool {
    return microphonePanel.isMicrophoneIncluded    // False at startup
}
```

### 4.2 Recorded Files Tab Initialization

**File:** `SidebarView.swift` (lines 147-170)

When the app starts, the "Saved Files" tab is created but **NOT immediately selected**.

```swift
// Only the "Audio Recorder" tab is displayed by default
// Users must click the "Saved Files" tab to switch

// File: MainViewController.swift, lines 1123-1193
private func loadRecordedFilesOnStartup() {
    // Background thread loads files asynchronously
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        // ... scan AudioRecordings directory ...
        DispatchQueue.main.async {
            self?.mainWindowView.loadRecordedFiles(files)
        }
    }
}
```

### 4.3 Process List Loading

**File:** `MainViewController.swift` (lines 1098-1121)

```swift
private func loadAvailableProcesses() {
    logger.info("开始加载可用音频进程列表")
    
    if #available(macOS 14.4, *) {
        let lister = CoreAudioProcessTapRecorder(mode: .systemMixdown)
        processes = lister.getAvailableAudioProcesses()  // Async fetch
    }
    
    self.availableProcesses = processes
    self.mainWindowView.updateProcessList(processes)
    self.mainWindowView.updateTracksDisplay()
    
    // ← NO STATE RESTORATION: "完全重置状态，不恢复上次选择"
    logger.info("📝 完全重置状态，不恢复上次选择")
}
```

**Key:** Process selection state is **NOT persisted**. Every launch defaults to "全部系统声音".

---

## 5. UI STATE MANAGEMENT

### 5.1 Recording State Enum

**Defined in App Architecture** (controller determines visual state):

```swift
enum RecordingState {
    case idle              // Not recording
    case preparing         // Starting recording
    case recording         // Recording in progress
    case playing           // Playback active
    case stopping          // Stopping recording
    case error             // Error occurred
}
```

### 5.2 MainViewController State Initialization

**File:** `MainViewController.swift` (lines 115-135)

```swift
private func setupInitialState() {
    // 1. Load last recording mode (but always use default in this version)
    loadLastRecordingMode()  // Uses .microphone by default
    
    // 2. Update UI to idle state
    mainWindowView.updateMode(currentRecordingMode)
    mainWindowView.updateRecordingState(.idle)     // ← INITIAL STATE: IDLE
    mainWindowView.updateStatus("准备就绪")         // Status: "Ready"
    
    // 3. Load process list asynchronously
    loadAvailableProcesses()
    
    // 4. Load saved recordings
    loadRecordedFilesOnStartup()
    
    // 5. Cleanup old logs and temp files
    logger.cleanupOldLogs()
    fileManager.cleanupTempFiles()
}
```

**Initial Status String:** "准备就绪" (Ready)

---

## 6. SIDEBAR VISUAL STYLING (INDUSTRIAL DESIGN)

### 6.1 Color Scheme

**File:** `IndustrialDesignTokens.swift`

| Element | Color | Hex | Purpose |
|---------|-------|-----|---------|
| **Sidebar Background** | surfaceContainer | #1a2122 | Dark backdrop |
| **Grid Texture** | gridLight | white @ 2% opacity | Subtle pattern |
| **Right Border** | outlineVariant | #3c494c | Visual divider |
| **Text - Headers** | onSurface | #dde4e5 | High contrast |
| **Text - Secondary** | onSurfaceVariant | #bbc9cd | Muted text |
| **Text - Tertiary** | textTertiary | #9CA3AF | Disabled/hint |
| **Selection Highlight** | primary | #8aebff | Cyan accent |

### 6.2 Typography

**All UI labels use `IndustrialTypography` constants:**

```swift
// Header: "录制目标" (14px, bold, uppercase)
font: IndustrialTypography.h2          // 14px bold
textColor: IndustrialColors.onSurface

// Hint label
font: IndustrialTypography.small       // Small size
textColor: IndustrialColors.textTertiary

// App list items
font: IndustrialTypography.label       // Standard label
```

### 6.3 Sidebar Layout Constraints

**File:** `SidebarView.swift` (lines 237-280)

```swift
NSLayoutConstraint.activate([
    // Target header: 16px from top, 16px from left/right
    targetHeader.topAnchor.constraint(equalTo: audioRecorderTabView.topAnchor, constant: 16),
    targetHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
    
    // Hint label: below header, 4px gap
    targetHintLabel.topAnchor.constraint(equalTo: targetHeader.bottomAnchor, constant: 4),
    
    // System target row: 10px below hint, 56px height
    systemTargetRow.topAnchor.constraint(equalTo: targetHintLabel.bottomAnchor, constant: 10),
    systemTargetRow.heightAnchor.constraint(equalToConstant: 56),
    
    // Apps header: 18px below system target
    appsHeader.topAnchor.constraint(equalTo: systemTargetRow.bottomAnchor, constant: 18),
    
    // Refresh button: right-aligned, center vertically with header
    refreshButton.centerYAnchor.constraint(equalTo: appsHeader.centerYAnchor),
    refreshButton.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -16),
    refreshButton.widthAnchor.constraint(equalToConstant: 80),
    refreshButton.heightAnchor.constraint(equalToConstant: 24),
    
    // Microphone panel: bottom, 12px from edge, 92px height
    microphonePanel.bottomAnchor.constraint(equalTo: audioRecorderTabView.bottomAnchor, constant: -12),
    microphonePanel.heightAnchor.constraint(equalToConstant: 92),
    
    // Apps scroll view: fills middle space
    appsScroll.topAnchor.constraint(equalTo: appsHeader.bottomAnchor, constant: 10),
    appsScroll.bottomAnchor.constraint(equalTo: microphonePanel.topAnchor, constant: -12)
])
```

---

## 7. MAIN WINDOW VIEW LAYOUT

### 7.1 Content Area Constraints

**File:** `MainWindowView.swift` (lines 86-126)

```
┌─────────────────────────────────────────┐
│ SplitView (full window)                  │
│ ┌──────────────┬──────────────────────┐ │
│ │   Sidebar    │   Content            │ │
│ │  (280px)     │   Area               │ │
│ │              │                      │ │
│ │ [≡≡≡≡≡≡≡≡≡≡] │ ┌──────────────────┐ │
│ │ [≡≡≡≡≡≡≡≡≡≡] │ │  Waveform        │ │
│ │              │ │  (42% height)     │ │
│ │ ┌──────────┐ │ │  + Level Meters  │ │
│ │ │⊕ System  │ │ │  (overlay)       │ │
│ │ │ Audio    │ │ └──────────────────┘ │
│ │ └──────────┘ │ ┌──────────────────┐ │
│ │              │ │  Tracks View     │ │
│ │ Apps:        │ │  (flexible)      │ │
│ │ - Chrome     │ └──────────────────┘ │
│ │ - Spotify    │ ┌──────────────────┐ │
│ │ - Safari     │ │  Control Panel   │ │
│ │              │ │  (150px)         │ │
│ │ ┌──────────┐ │ │  [RECORD BTN]    │ │
│ │ │🎤 Mic    │ │ └──────────────────┘ │
│ │ │Add Mic   │ │ ┌──────────────────┐ │
│ │ └──────────┘ │ │  Status Bar      │ │
│ │              │ │  (28px)          │ │
│ └──────────────┼──────────────────────┘ │
└─────────────────────────────────────────┘
```

**Layout Breakdown:**

```swift
// Waveform: Top 42% of content area
waveformView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.42)

// Tracks: Middle, flexible
tracksView.bottomAnchor.constraint(equalTo: controlPanelView.topAnchor, constant: -12)

// Control Panel: Fixed 150px
controlPanelView.heightAnchor.constraint(equalToConstant: 150)

// Status Bar: Fixed 28px at bottom
statusBarView.heightAnchor.constraint(equalToConstant: 28)
```

---

## 8. DESIGN SYSTEM - INDUSTRIAL DESIGN TOKENS

### 8.1 Spacing

```swift
struct IndustrialSpacing {
    static let sidebarWidth: CGFloat = 280       // Sidebar fixed width
    static let xs: CGFloat = 4                   // Extra small
    static let sm: CGFloat = 8                   // Small
    static let md: CGFloat = 16                  // Medium (16px)
    static let lg: CGFloat = 24                  // Large
    static let xl: CGFloat = 32                  // Extra large
    static let xxl: CGFloat = 48                 // 2X large
    static let gutter: CGFloat = 12              // Panel gutter
    static let gridTextureInterval: CGFloat = 8  // Grid line spacing
}
```

### 8.2 Corner Radius

```swift
struct IndustrialCornerRadius {
    static let xs: CGFloat = 4        // Tiny
    static let sm: CGFloat = 8        // Small
    static let md: CGFloat = 12       // Medium
    static let lg: CGFloat = 16       // Large
    static let full: CGFloat = 999    // Fully rounded
}
```

### 8.3 Shadow Effects

```swift
struct IndustrialShadow {
    static func small(for layer: CALayer) {
        layer.shadowColor = IndustrialColors.shadowColor.cgColor
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.45
        layer.shadowOffset = CGSize(width: 0, height: 3)
    }
}
```

### 8.4 Glow Effects

```swift
struct IndustrialGlow {
    static func multiLayer(on layer: CALayer, color: NSColor, 
                          configs: [(radius: CGFloat, opacity: Float)]) {
        for config in configs {
            let glowLayer = CALayer()
            glowLayer.backgroundColor = color.cgColor
            glowLayer.cornerRadius = layer.cornerRadius
            glowLayer.shadowColor = color.cgColor
            glowLayer.shadowRadius = config.radius
            glowLayer.shadowOpacity = config.opacity
            layer.addSublayer(glowLayer)
        }
    }
}
```

**Record Button Glow Example:**
- 3-layer cyan glow (40px, 20px, 10px radiuses)
- Creates pulsing visual effect for active recording

---

## 9. DELEGATE PATTERN & EVENT FLOW

### 9.1 Delegation Chain

```
MainWindowView
  ├─ delegate: MainWindowViewDelegate
  │  └─ MainViewController (implements delegate)
  │
  ├─ sidebarView: SidebarView
  │  └─ delegate: SidebarViewDelegate
  │     └─ MainWindowView (intermediate)
  │        └─ delegates to MainWindowViewDelegate → MainViewController
  │
  ├─ controlPanelView: ControlPanelView
  │  └─ delegate: ControlPanelViewDelegate
  │     └─ MainWindowView (intermediate)
  │
  └─ tracksView: TracksView
     └─ delegate: TracksViewDelegate
        └─ MainWindowView (intermediate)
```

### 9.2 Key User Interaction Events

**Recording Button Click Flow:**

```
ControlPanelView.recordButton.onClick()
  ↓
controlPanelViewDidStartRecording() [delegate]
  ↓
MainWindowView delegates to MainWindowViewDelegate
  ↓
MainViewController.mainWindowViewDidStartRecording()
  ↓
MainViewController.startRecording()
  ↓
- Check permissions
- audioRecorderController.startMultiSourceRecording()
- updateRecordingState(.recording)
```

**Sidebar Selection Change Flow:**

```
SidebarView.systemTargetRow.onClick()
  ↓
selectSystemAudioTarget()
  ↓
sidebarViewDidSelectProcesses(pids: [])
  ↓
MainWindowView (intermediate delegate)
  ↓
MainViewController.mainWindowViewDidSelectProcesses()
  ↓
- Save selectedPIDs
- Update status message
```

---

## 10. CRITICAL CODE SNIPPETS

### 10.1 Sidebar Default State

**File:** `SidebarView.swift`

```swift
// Line 195-199: Set "全部系统声音" as default
private func setupTargetControls() {
    systemTargetRow.translatesAutoresizingMaskIntoConstraints = false
    systemTargetRow.isSelectedTarget = true  // ← KEY: Pre-selected
    systemTargetRow.onClick = { [weak self] in
        self?.selectSystemAudioTarget()
    }
}

// Line 337-339: Query confirms system audio is selected by default
func isSystemAudioSourceSelected() -> Bool {
    return selectedPIDs.isEmpty  // Empty = system audio selected
}
```

### 10.2 Sidebar Visibility

**File:** `MainWindowView.swift`

```swift
// Lines 312-314: Sidebar CANNOT be collapsed
func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
    return false  // Sidebar always visible
}

// Line 93: Fixed width constraint
sidebarView.widthAnchor.constraint(equalToConstant: IndustrialSpacing.sidebarWidth)
// = 280 pixels (constant)
```

### 10.3 App Lifecycle Initialization

**File:** `MainViewController.swift`

```swift
// Lines 116-135: Initial UI state setup
private func setupInitialState() {
    loadLastRecordingMode()           // Default: .microphone
    mainWindowView.updateMode(currentRecordingMode)
    mainWindowView.updateRecordingState(.idle)    // ← IDLE state
    mainWindowView.updateStatus("准备就绪")       // ← "Ready"
    loadAvailableProcesses()          // Fetch process list
    loadRecordedFilesOnStartup()      // Load saved files async
    logger.cleanupOldLogs()
    fileManager.cleanupTempFiles()
}
```

### 10.4 Window Setup

**File:** `AppDelegate.swift`

```swift
// Lines 121-172: Window creation and configuration
private func createMainWindow() {
    let windowSize = NSMakeRect(0, 0, 800, 500)
    window = NSWindow(
        contentRect: windowSize,
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    
    window.title = "音频录制工具"
    window.isRestorable = false       // Don't restore window state
    window.minSize = NSSize(width: 800, height: 500)
    window.isReleasedWhenClosed = false
    
    mainViewController = MainViewController()
    window.contentViewController = mainViewController
    
    window.center()
    window.makeKeyAndOrderFront(nil)  // Show window
    NSApp.activate(ignoringOtherApps: true)
}
```

---

## 11. UI STATE AT LAUNCH - COMPREHENSIVE CHECKLIST

| Component | State | Value | File | Line |
|-----------|-------|-------|------|------|
| **Window** | Visible | ✓ Yes | AppDelegate.swift | 187 |
| **Window** | Size | 800×500 | AppDelegate.swift | 122 |
| **Window** | Restorable | ✗ No | AppDelegate.swift | 135 |
| **Recording State** | Initial | .idle | MainViewController.swift | 121 |
| **Status Text** | Initial | "准备就绪" | MainViewController.swift | 122 |
| **Sidebar** | Visible | ✓ Always | MainWindowView.swift | 312 |
| **Sidebar** | Width | 280px | MainWindowView.swift | 93 |
| **Sidebar** | Collapsible | ✗ No | MainWindowView.swift | 313 |
| **Audio Target** | Selected | System Audio | SidebarView.swift | 197 |
| **Apps List** | Loaded | Background thread | MainViewController.swift | 1128 |
| **Saved Files** | Loaded | Background thread | MainViewController.swift | 1128 |
| **Saved Files Tab** | Active | ✗ No (Audio Recorder tab) | TabContainerView.swift | 99 |
| **Microphone** | Enabled | ✗ No (off by default) | SidebarView.swift | ~202 |
| **Record Button** | State | Idle (red, not glowing) | ControlPanelView.swift | ~164 |
| **Timer Display** | Initial | "00:00:00" | ControlPanelView.swift | 94 |

---

## 12. FILE MAPPINGS

### View Files (13 total)

| File | Purpose | Key Responsibilities |
|------|---------|----------------------|
| `MainWindowView.swift` | Master layout container | SplitView orchestration, all sub-view management |
| `SidebarView.swift` | Left panel with tabs | Audio source selection, process list, saved files |
| `TabContainerView.swift` | Tab switching system | Tab bar, content switching |
| `ControlPanelView.swift` | Bottom control panel | Record button, play/stop, timer display, transport |
| `WaveformView.swift` | Waveform visualization | Audio level visualization, waveform drawing |
| `LevelMetersOverlay.swift` | L/R level meters | Real-time level display (overlay on waveform) |
| `TracksView.swift` | Active tracks display | Shows current recording targets |
| `StatusBarView.swift` | Status information bar | Status message display |
| `RecordedFilesView.swift` | Saved files list | File browsing, selection, export |
| `IndustrialControls.swift` | Reusable components | Button views, row views, visual elements |
| `TimerLabel.swift` | Timer display widget | Formatted time string with glow effect |

### Controller Files (2 total)

| File | Purpose |
|------|---------|
| `MainViewController.swift` | Main UI logic, state management, event handling |
| `AudioRecorderController.swift` | Audio recording backend, multi-source recording |

---

## 13. DESIGN PHILOSOPHY

### Industrial Design Principles Applied

1. **Professional Studio Aesthetic**
   - Dark theme (matching audio studio environment)
   - Metal-inspired colors and textures
   - Clear functional zones

2. **High Information Density**
   - Waveform + levels + tracks all visible simultaneously
   - Monospace font for timecode/values
   - Sufficient spacing to avoid clutter

3. **Direct Feedback**
   - Red glow for record button (active state)
   - Cyan timer with glow effect
   - Color-coded level meters (green → yellow → red)

4. **Function Over Form**
   - Every visual element serves a purpose
   - No unnecessary decoration
   - Consistent with hardware recording interfaces

---

## 14. CONCLUSION

### UI Architecture Summary

- **Launch State:** Sidebar always visible, system audio pre-selected, idle state
- **Layout Type:** NSSplitView vertical (sidebar 280px fixed, content flexible)
- **Theme:** Industrial design (dark, professional, work-studio-grade)
- **Navigation:** Tab-based sidebar (Audio Recorder tab default, Saved Files tab 2nd)
- **State Persistence:** Minimal (no window state restore, no selection persistence)
- **Async Loading:** Process list and saved files load in background at startup

### Key Files for Reference

- **App Entry:** `main.swift` + `AppDelegate.swift`
- **Main ViewController:** `MainViewController.swift`
- **Master Layout:** `MainWindowView.swift`
- **Left Sidebar:** `SidebarView.swift`
- **Design Tokens:** `IndustrialDesignTokens.swift`
- **Design Spec:** `docs/AudioRecordApp_Industrial_Design_UI_Prompt.md`

