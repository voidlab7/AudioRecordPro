# AudioRecord Mac App - UI Architecture Analysis

**Project Location:** `/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp`
**Date:** May 4, 2026
**Analysis Scope:** View hierarchy, sidebar implementation, panel visibility management

---

## 1. PROJECT STRUCTURE

### Directory Layout
```
AudioRecordApp/
├── Sources/
│   ├── App/
│   │   ├── main.swift              (Entry point)
│   │   └── AppDelegate.swift       (App lifecycle & window management)
│   ├── Views/
│   │   ├── MainWindowView.swift    (Root UI orchestrator)
│   │   ├── SidebarView.swift       (Left sidebar with tabs)
│   │   ├── TabContainerView.swift  (Tab switching logic)
│   │   ├── ControlPanelView.swift  (Recording controls)
│   │   ├── WaveformView.swift      (Waveform display)
│   │   ├── TracksView.swift        (Track monitoring)
│   │   ├── StatusBarView.swift     (Status display)
│   │   ├── LevelMeterView.swift    (Level meters)
│   │   ├── LevelMetersOverlay.swift (Overlay meters)
│   │   ├── RecordedFilesView.swift (Recorded files list)
│   │   ├── IndustrialControls.swift (Custom UI components)
│   │   └── TimerLabel.swift        (Timer display)
│   ├── Controllers/
│   │   ├── MainViewController.swift (View controller)
│   │   └── AudioRecorderController.swift (Audio logic)
│   └── Utilities/
│       └── IndustrialDesignTokens.swift (Design tokens)
├── Resources/
│   └── Assets
└── build.sh
```

### App Bundle Configuration
**Bundle ID:** `com.voidzhang.audio-record-mac`
**Minimum macOS:** 13.0
**Version:** 0.1.0

---

## 2. INITIAL LAUNCH VIEW HIERARCHY

### Window Creation Flow
1. **AppDelegate.applicationDidFinishLaunching()**
   - Sets NSApp activation policy to `.regular` (regular app with dock icon)
   - Loads and sets app icon from `AudioRecordLogo.png`
   - Requests audio capture permissions
   - Calls `createMainWindow()`

2. **AppDelegate.createMainWindow()**
   - Creates NSWindow: 800×500px
   - Sets window title: "音频录制工具" (Audio Recording Tool)
   - Creates MainViewController as contentViewController
   - Immediately displays and front-moves window

### View Hierarchy on First Launch
```
NSWindow (800×500)
└── MainViewController
    └── MainWindowView (root view)
        └── NSSplitView (vertical split)
            ├── [LEFT] SidebarView (200-400px fixed width)
            │   └── TabContainerView
            │       ├── Tab Bar (44px height)
            │       │   ├── "Audio Recorder" button
            │       │   └── "Saved Files" button
            │       └── Content Area
            │           ├── Audio Recorder Tab (visible by default)
            │           │   ├── "RECORDING TARGET" header
            │           │   ├── "Choose system sound..." hint
            │           │   ├── SystemTargetRow ("全部系统声音")
            │           │   ├── "SELECT APPLICATION SOUND" header
            │           │   ├── Refresh button
            │           │   ├── Apps scroll view (process list)
            │           │   └── Microphone panel (bottom)
            │           └── Saved Files Tab (hidden)
            │
            └── [RIGHT] Content Area
                ├── WaveformView (42% height, top)
                │   └── LevelMetersOverlay (top-right corner)
                ├── TracksView (flexible middle)
                ├── ControlPanelView (150px fixed height, record button)
                └── StatusBarView (28px fixed height, bottom)
```

---

## 3. SIDEBAR IMPLEMENTATION

### File: `SidebarView.swift` (Line 1-577)

#### Key Properties
- **Type:** NSView subclass (not UIView/SwiftUI)
- **Parent:** Added to left side of NSSplitView
- **Width:** Fixed at 200-400px (constrained in MainWindowView line 93)
- **Visibility:** Always visible - **CANNOT BE COLLAPSED**

#### UI Components
1. **TabContainerView** - Tab switching for two sections
   - "Audio Recorder" tab (default)
   - "Saved Files" tab

#### Audio Recorder Tab Contents
```
targetHeader: "RECORDING TARGET" (uppercase label)
targetHintLabel: "先选要录的声音；麦克风作为附加输入"

systemTargetRow: IndustrialAudioTargetRowView
  - Title: "全部系统声音"
  - Subtitle: "CAPTURE FULL MAC OUTPUT"
  - Icon: speaker.wave.3.fill
  - Selection: Blue highlight when selected

appsHeader: "SELECT APPLICATION SOUND" (uppercase label)

refreshButton: "刷新" (Refresh button)

appsScroll: NSScrollView containing dynamic process list
  - Populated by: rebuildProcessRows() method
  - Items: IndustrialProcessRowView (custom rows)
  - Shows: App icon, process name (uppercase), PID

microphonePanel: IndustrialMicrophonePanelView (bottom)
  - Title: "ADD MICROPHONE"
  - Toggle: "同时录入麦克风"
  - State: toggleable, NOT hidden
  - Hint: "MIX INTO SELECTED TARGET"
```

#### Sidebar State Management
**Key Finding:** NO visibility state management, NO UserDefaults/preferences

```swift
// SidebarView.swift, line 285-290
private func selectSystemAudioTarget() {
    logger.info("录制目标切换为：全部系统声音")
    selectedPIDs = []
    systemTargetRow.isSelectedTarget = true
    rebuildProcessRows()
    delegate?.sidebarViewDidSelectProcesses(self, pids: [])
    delegate?.sidebarViewDidChangeSourceSelection(self)
}
```

**State Variables:**
- `selectedPIDs: [pid_t]` - Selected process PIDs
- `availableProcesses: [AudioProcessInfo]` - Available processes
- `microphonePanel.isMicrophoneIncluded` - Mic toggle state

---

## 4. PANEL VISIBILITY & STATE PERSISTENCE

### Current Implementation Status
**❌ NO PANEL VISIBILITY TOGGLE**
**❌ NO STATE PERSISTENCE**
**❌ NO COLLAPSE/EXPAND FUNCTIONALITY**

The sidebar is **permanently visible** with these characteristics:
- Fixed minimum width: 200px (MainWindowView.swift, line 303)
- Fixed maximum width: 400px (MainWindowView.swift, line 309)
- Resizable via split view divider
- Cannot be collapsed (line 312: `return false`)

### NSSplitView Configuration
```swift
// MainWindowView.swift, lines 44-50
private func setupSplitView() {
    splitView.isVertical = true
    splitView.dividerStyle = .thin
    splitView.delegate = self
    splitView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(splitView)
}

// Delegate methods (lines 300-325)
- canCollapseSubview() returns false ❌ (collapse disabled)
- Split view is draggable (default NSSplitView behavior)
```

### Tab Persistence in Sidebar
**Current Behavior:**
- User selects a tab (e.g., "Saved Files")
- No persistence mechanism
- On app restart, "Audio Recorder" tab is shown (default)

**Selected Tab Tracking:**
```swift
// TabContainerView.swift, line 32
private var selectedTabId: String?

// Line 99-101
if selectedTabId == nil {
    selectTab(tab.id)  // Auto-selects first tab on init
}
```

**No UserDefaults usage:**
```bash
# Search result: only 2 files use UserDefaults
grep -r "UserDefaults" /Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/
# Result:
# MainViewController.swift (line 25): private let userDefaults = UserDefaults.standard
# MainViewController.swift (line 26): private let recordingModeKey = "lastRecordingMode"
```

Sidebar tab selection is **NOT persisted** to UserDefaults.

---

## 5. INITIAL UI STATE

### What User Sees on First Launch
1. **Window Title:** "音频录制工具"
2. **Left Sidebar (220px default):**
   - "Audio Recorder" tab selected (blue highlight)
   - "Saved Files" tab available
   - Recording target section:
     - "全部系统声音" row highlighted (selected by default)
   - Application sound selection:
     - "LOADING..." or "NO AUDIO PROCESSES DETECTED" (depends on timing)
   - Microphone toggle (OFF by default)

3. **Right Content Area:**
   - **Top (42% height):** Waveform display (empty, ready for input)
   - **Middle (flexible):** Tracks view showing selected source
   - **Bottom (150px):** Transport control panel
     - Recording button (RED circle, centered)
     - Play/Stop buttons
     - Timer display (00:00.00)
     - Status badge ("STANDBY")
   - **Bottom (28px):** Status bar

### Default Recording Configuration
- **Source:** Full system audio ("全部系统声音")
- **Microphone:** OFF (not included in mix)
- **Format:** WAV (inferred from ControlPanelView line 19)
- **Sample Rate:** 48kHz (from ControlPanelView line 19)

---

## 6. INTERACTION FLOWS

### Sidebar Tab Switching
```swift
// TabContainerView.swift, lines 105-116
func selectTab(_ tabId: String) {
    // Updates button highlighting
    updateTabButtonStates(selectedId: tabId)
    
    // Swaps content view
    updateContentView(with: tab)
    
    // Calls delegate (optional side effects)
    delegate?.tabContainerViewDidSelectTab(self, tabId: tabId)
}
```

### Recording Target Selection
```swift
// SidebarView.swift, lines 378-385 (process selection)
row.onClick = { [weak self] in
    self?.selectedPIDs = [process.pid]
    self?.systemTargetRow.isSelectedTarget = false
    self?.rebuildProcessRows()
    self?.delegate?.sidebarViewDidSelectProcesses(self, pids: [process.pid])
    self?.delegate?.sidebarViewDidChangeSourceSelection(self)
}
```

### Microphone Toggle
```swift
// SidebarView.swift, lines 292-296
private func microphoneInputChanged(enabled: Bool) {
    logger.info("麦克风附加输入: \(enabled ? "开启" : "关闭")")
    delegate?.sidebarViewDidChangeMixAudio(self, enabled: enabled)
    delegate?.sidebarViewDidChangeSourceSelection(self)
}
```

---

## 7. DELEGATION & STATE UPDATES

### MainWindowViewDelegate Protocol (lines 328-342)
The sidebar communicates back to MainViewController via:
- `sidebarViewDidChangeSourceSelection()`
- `sidebarViewDidSelectProcesses(pids:)`
- `sidebarViewDidRequestProcessRefresh()`
- `sidebarViewDidSelectFile(file:)`
- `sidebarViewDidDoubleClickFile(file:)`
- `sidebarViewDidRequestExportToMP3(file:)`
- `sidebarViewDidChangeMixAudio(enabled:)`

### MainViewController Responsibilities (MainViewController.swift)
- Owns AudioRecorderController
- Updates MainWindowView with:
  - Audio levels
  - Recording state
  - Process list
  - Playback status
- Handles file recording/playback

---

## 8. KEY CODE LOCATIONS

| Feature | File | Lines |
|---------|------|-------|
| Window creation | AppDelegate.swift | 121-217 |
| View hierarchy setup | MainWindowView.swift | 33-126 |
| SplitView config | MainWindowView.swift | 44-50, 300-325 |
| Sidebar layout | SidebarView.swift | 59-280 |
| Tab switching | TabContainerView.swift | 105-189 |
| Recording targets | SidebarView.swift | 283-390 |
| Microphone control | SidebarView.swift | 292-296, 689-766 |
| Status updates | ControlPanelView.swift | 50-91 |

---

## 9. CRITICAL FINDINGS

### ✅ WHAT EXISTS
- Persistent sidebar (always visible)
- Two-tab interface (Audio Recorder, Saved Files)
- Recording target selection (system audio or app)
- Microphone toggle
- Dynamic process list
- Visual feedback (highlight selection)

### ❌ WHAT'S MISSING
- **Sidebar collapse/expand button** - Not implemented
- **Tab persistence** - Doesn't save selected tab to UserDefaults
- **Sidebar width persistence** - NSSplitView doesn't save divider position to UserDefaults
- **UI state restoration** - No state saved/restored on app launch
- **Keyboard shortcuts** - No shortcuts for tab switching or sidebar toggle

### 🔄 CURRENT STATE FLOW
```
App Launch
  → AppDelegate creates MainWindow
  → MainViewController loads views
  → MainWindowView creates SplitView
  → SidebarView initializes with Tab 0 (Audio Recorder)
  → systemTargetRow selected by default
  → User interactions modify selectedPIDs only
  → On app restart: state is lost, defaults restored
```

---

## 10. RECOMMENDATIONS FOR ENHANCEMENT

If you want to add collapsible sidebar:

1. **Add state variable to MainWindowView:**
   ```swift
   private var sidebarCollapsed: Bool = false
   ```

2. **Store in UserDefaults:**
   ```swift
   UserDefaults.standard.set(sidebarCollapsed, forKey: "sidebarCollapsed")
   let collapsed = UserDefaults.standard.bool(forKey: "sidebarCollapsed")
   ```

3. **Add collapse button to sidebar header**

4. **Animate width constraint:**
   ```swift
   sidebarView.widthAnchor.constraint(equalToConstant: 
       sidebarCollapsed ? 40 : IndustrialSpacing.sidebarWidth)
   ```

---

**Report Generated:** 2026-05-04
**Analyst:** Claude Code Architecture Review
