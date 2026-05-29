# Static UI Audit Report

> Generated: 2026-05-22 00:08:57

## 1. Hardcoded Colors (should use IndustrialColors)

```
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMeterCardView.swift:101:        let slotColor = NSColor(calibratedWhite: 0.08, alpha: 1.0)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMeterCardView.swift:131:            (NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.28, alpha: 1.0), 0.0),
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMeterCardView.swift:132:            (NSColor(calibratedRed: 0.45, green: 0.75, blue: 0.2, alpha: 1.0), 0.55),
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMeterCardView.swift:133:            (NSColor(calibratedRed: 0.85, green: 0.75, blue: 0.1, alpha: 1.0), 0.78),
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMeterCardView.swift:134:            (NSColor(calibratedRed: 0.88, green: 0.18, blue: 0.12, alpha: 1.0), 1.0)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:90:        let slotColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:105:            .foregroundColor: NSColor(calibratedWhite: 0.5, alpha: 1.0)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:119:            (NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.3, alpha: 1.0), 0.0),    // 绿
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:120:            (NSColor(calibratedRed: 0.5, green: 0.8, blue: 0.2, alpha: 1.0), 0.5),    // 黄绿
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:121:            (NSColor(calibratedRed: 0.9, green: 0.8, blue: 0.1, alpha: 1.0), 0.75),   // 黄
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:122:            (NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.15, alpha: 1.0), 1.0)    // 红
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:148:            .foregroundColor: NSColor(calibratedWhite: 0.4, alpha: 1.0)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:159:            NSColor(calibratedWhite: 0.25, alpha: 1.0).setStroke()
```

## 2. Hardcoded Hex Color Values

```
None found
```

## 3. Font Usage (should use IndustrialTypography)

```
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMeterCardView.swift:115:            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMeterCardView.swift:158:            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:104:            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/LevelMetersOverlay.swift:147:            .font: NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular),
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/TrackPanelView.swift:153:                iconLabel.font = NSFont.systemFont(ofSize: 14)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/TrackPanelView.swift:168:        nameLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/TrackPanelView.swift:201:        soloButton.font = NSFont.systemFont(ofSize: 9, weight: .bold)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/EditToolbarView.swift:133:        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/SettingsWindowController.swift:87:        directoryLabel.font = NSFont.systemFont(ofSize: 11)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/SettingsWindowController.swift:121:        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/SettingsWindowController.swift:142:            popup.font = NSFont.systemFont(ofSize: 13)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/StatusBarView.swift:92:        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/IndustrialControls.swift:192:        iconLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/IndustrialControls.swift:293:        checkLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/IndustrialControls.swift:516:        iconLabel.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/TracksView.swift:86:        emptyStateIcon.font = NSFont.systemFont(ofSize: 24, weight: .ultraLight)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/TracksView.swift:96:        emptyStateLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/TracksView.swift:103:            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/TracksView.swift:350:                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/TracksView.swift:358:                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
```

## 4. Non-standard Spacing Values (not multiples of 4)

```
  20 constant: 12
  20 constant: -12
  18 constant: 8
  12 constant: 6
  12 constant: 10
  10 constant: -8
   6 constant: -10
   5 constant: 16
   5 constant: -4
   5 constant: -16
   4 constant: 4
   4 constant: 2
   3 constant: 24
   3 constant: -6
   2 constant: 9
   2 constant: 3
   2 constant: -20
   1 constant: 78
   1 constant: 32
   1 constant: 26
```

## 5. Accessibility Identifiers

```
Total accessibility annotations:       18
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:150:        playButton.setAccessibilityIdentifier("PlayButton")
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:151:        playButton.setAccessibilityLabel("Play")
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:152:        stopButton.setAccessibilityIdentifier("StopButton")
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:153:        stopButton.setAccessibilityLabel("Stop")
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:206:        recordButton.setAccessibilityIdentifier("RecordButton")
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:207:        recordButton.setAccessibilityLabel("Record")
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:208:        recordButton.setAccessibilityRole(.button)
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:93:        setAccessibilityIdentifier("MainWindowView")
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:104:        sidebarView.setAccessibilityIdentifier("Sidebar")
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:105:        waveformView.setAccessibilityIdentifier("WaveformView")
```

## 6. Empty Delegate/Protocol Methods (potential interaction gaps)

```
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/TabContainerView.swift:106:    func selectTab(_ tabId: String) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/WaveformView.swift:119:    func updatePeakLevel(_ peakLevel: Float) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/WaveformView.swift:450:    private func drawWaveform(in rect: NSRect) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:336:    func updatePlaybackPaused(_ isPaused: Bool) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:488:    private func layoutStopSquareLayer() {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/ControlPanelView.swift:497:    private func setRecordButtonSize(_ size: CGFloat, animated: Bool) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/SidebarView.swift:356:    func getSelectedProcesses() -> [AudioProcessInfo] {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/EditToolbarView.swift:158:    override func mouseEntered(with event: NSEvent) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/EditToolbarView.swift:169:    override func mouseDown(with event: NSEvent) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/EditToolbarView.swift:174:    override func mouseUp(with event: NSEvent) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/SettingsWindowController.swift:48:    private func setupUI() {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:491:    private func switchToMode(_ mode: ViewMode) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:555:    func hideRecordingCompleteActions() {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:567:    func showEditor(_ editorView: NSView) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:595:    func hideEditor() {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:794:    func collapseSidebar(animated: Bool = true) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:810:    func expandSidebar(animated: Bool = true) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/RecordedFilesView.swift:221:    @objc private func handleRenameFile(_ sender: NSMenuItem) {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/IndustrialControls.swift:82:    private func updateAppearance() {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/IndustrialControls.swift:104:    override func mouseEntered(with event: NSEvent) {
```

## 7. TODO/FIXME/HACK Comments in Views

```
None found
```

## 8. DispatchQueue.main Usage (UI thread safety)

```
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/WaveformView.swift:112:        DispatchQueue.main.async {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/WaveformView.swift:205:            DispatchQueue.main.async {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/SidebarView.swift:420:                    DispatchQueue.main.async {
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/MainWindowView.swift:547:        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
/Users/voidzhang/Documents/workspace/audio_record_mac/AudioRecordApp/Sources/Views/StatusBarView.swift:245:                DispatchQueue.main.async {
```

## Summary

- Total View files scanned:       21
- Report location: /Users/voidzhang/Documents/workspace/audio_record_mac/test_logs/ui-test-20260522_000857/static-audit-report.md
- Next step: AI reads this report + screenshots for comprehensive review
