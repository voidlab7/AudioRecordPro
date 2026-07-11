#!/bin/bash
# =============================================================================
# AI UI Test Script — AudioRecord Mac App
# =============================================================================
# Purpose: Build, launch, screenshot, and simulate interactions for AI review.
# Usage:
#   ./scripts/ai-ui-test.sh              # Full test (build + screenshot + interaction)
#   ./scripts/ai-ui-test.sh --screenshot  # Screenshot only (app must be running)
#   ./scripts/ai-ui-test.sh --interact    # Interaction test only (app must be running)
#   ./scripts/ai-ui-test.sh --static      # Static code audit only (no build needed)
#
# Output: Screenshots saved to test_logs/ui-test-<timestamp>/
# AI Review: After running, ask AI to read screenshots via read_image tool
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$PROJECT_ROOT/test_logs/ui-test-$TIMESTAMP"
APP_NAME="audio_record_mac"
APP_BUNDLE="$PROJECT_ROOT/build/AudioRecordMac.app"
BUILD_SCRIPT="$PROJECT_ROOT/AudioRecordApp/build.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

ensure_output_dir() {
    mkdir -p "$OUTPUT_DIR"
    log_info "Output directory: $OUTPUT_DIR"
}

get_window_id() {
    osascript -e "
        tell application \"System Events\"
            tell process \"audio_record_mac\"
                set frontWindow to front window
                return id of frontWindow
            end tell
        end tell
    " 2>/dev/null || echo ""
}

take_screenshot() {
    local name="$1"
    local filepath="$OUTPUT_DIR/${name}.png"
    
    # Method 1: Try to capture the frontmost window
    screencapture -w "$filepath" 2>/dev/null
    
    # Method 2: If window capture fails, try full screen capture
    if [ ! -f "$filepath" ] || [ ! -s "$filepath" ]; then
        screencapture "$filepath" 2>/dev/null
    fi
    
    # Method 3: If still no screenshot, try to find and capture specific app window
    if [ ! -f "$filepath" ] || [ ! -s "$filepath" ]; then
        local wid
        wid=$(osascript -e "
            tell application \"System Events\"
                try
                    tell process \"audio_record_mac\"
                        return id of front window
                    end tell
                on error
                    return \"\"
                end try
            end tell
        " 2>/dev/null || echo "")
        
        if [ -n "$wid" ]; then
            screencapture -l "$wid" "$filepath" 2>/dev/null
        fi
    fi
    
    if [ -f "$filepath" ] && [ -s "$filepath" ]; then
        log_ok "Screenshot: $name.png"
        echo "$filepath"
    else
        log_warn "Failed to capture: $name"
        echo ""
    fi
}

wait_for_app() {
    local max_wait=10
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
            sleep 1
            log_ok "App is running"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    log_err "App did not start within ${max_wait}s"
    return 1
}

# =============================================================================
# Phase 1: Build
# =============================================================================

phase_build() {
    log_info "=== Phase 1: Building App ==="
    
    if [ ! -f "$BUILD_SCRIPT" ]; then
        log_err "Build script not found: $BUILD_SCRIPT"
        return 1
    fi
    
    cd "$PROJECT_ROOT/AudioRecordApp"
    bash build.sh 2>&1 | tail -5
    
    if [ -d "$APP_BUNDLE" ]; then
        log_ok "Build successful: $APP_BUNDLE"
    else
        log_err "Build failed — app bundle not found"
        return 1
    fi
}

# =============================================================================
# Phase 2: Launch & Screenshot (Static Visual Test)
# =============================================================================

phase_screenshot() {
    log_info "=== Phase 2: Screenshot Test ==="
    ensure_output_dir
    
    # Check if app is already running
    if ! pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        log_info "Launching app..."
        open "$APP_BUNDLE"
        wait_for_app || return 1
        sleep 3  # Wait for UI to fully render
    else
        log_info "App already running"
    fi
    
    # Bring app to front
    osascript -e "
        tell application \"System Events\"
            try
                set frontmost of process \"audio_record_mac\" to true
                delay 0.5
            on error
                -- If activation fails, try to launch the app
                tell application \"audio_record_mac\" to activate
                delay 1
            end try
        end tell
    " 2>/dev/null || true
    sleep 1
    
    # Screenshot 1: Idle state (Recording Workspace)
    take_screenshot "01-idle-recording-workspace"
    
    # Screenshot 2: Try to resize window to minimum
    osascript -e "
        tell application \"System Events\"
            tell process \"$APP_NAME\"
                set size of front window to {960, 600}
                set position of front window to {100, 100}
            end tell
        end tell
    " 2>/dev/null || true
    sleep 1
    take_screenshot "02-minimum-size"
    
    # Screenshot 3: Resize to large
    osascript -e "
        tell application \"System Events\"
            tell process \"$APP_NAME\"
                set size of front window to {1400, 900}
                set position of front window to {50, 50}
            end tell
        end tell
    " 2>/dev/null || true
    sleep 1
    take_screenshot "03-large-size"
    
    # Restore default size
    osascript -e "
        tell application \"System Events\"
            tell process \"$APP_NAME\"
                set size of front window to {1200, 750}
            end tell
        end tell
    " 2>/dev/null || true
    sleep 1
    
    log_ok "Screenshot phase complete"
}

# =============================================================================
# Phase 3: Interaction Test (State Transitions)
# =============================================================================

phase_interact() {
    log_info "=== Phase 3: Interaction Test ==="
    ensure_output_dir
    
    # Check if app is running
    if ! pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        log_err "App not running. Launch it first or use full test mode."
        return 1
    fi
    
    # Bring app to front
    osascript -e "
        tell application \"System Events\"
            try
                set frontmost of process \"audio_record_mac\" to true
                delay 0.5
            on error
                -- If activation fails, try to launch the app
                tell application \"audio_record_mac\" to activate
                delay 1
            end try
        end tell
    " 2>/dev/null || true
    sleep 1
    
    # --- Test 1: Record button click ---
    log_info "Test: Click Record button"
    take_screenshot "10-before-record"
    
    # Try clicking the record button via accessibility
    osascript -e "
        tell application \"System Events\"
            tell process \"$APP_NAME\"
                -- Try to find and click the record button
                set allButtons to every button of front window
                repeat with btn in allButtons
                    try
                        if description of btn contains \"Record\" or title of btn contains \"Record\" or name of btn contains \"Record\" then
                            click btn
                            exit repeat
                        end if
                    end try
                end repeat
            end tell
        end tell
    " 2>/dev/null || log_warn "Could not click Record button via accessibility"
    sleep 2
    take_screenshot "11-after-record-click"
    
    # --- Test 2: Stop recording ---
    log_info "Test: Click Stop button"
    sleep 3  # Let it record for a moment
    osascript -e "
        tell application \"System Events\"
            tell process \"$APP_NAME\"
                set allButtons to every button of front window
                repeat with btn in allButtons
                    try
                        if description of btn contains \"Stop\" or title of btn contains \"Stop\" or name of btn contains \"Stop\" then
                            click btn
                            exit repeat
                        end if
                    end try
                end repeat
            end tell
        end tell
    " 2>/dev/null || log_warn "Could not click Stop button via accessibility"
    sleep 2
    take_screenshot "12-after-stop"
    
    # --- Test 3: Sidebar interaction ---
    log_info "Test: Sidebar file selection"
    osascript -e "
        tell application \"System Events\"
            tell process \"$APP_NAME\"
                -- Try to click on a file in the sidebar
                set allRows to every row of every table of front window
            end tell
        end tell
    " 2>/dev/null || log_warn "Could not interact with sidebar"
    sleep 1
    take_screenshot "13-sidebar-interaction"
    
    # --- Test 4: Keyboard shortcuts ---
    log_info "Test: Keyboard shortcut Cmd+,"
    osascript -e "
        tell application \"System Events\"
            tell process \"$APP_NAME\"
                keystroke \",\" using command down
            end tell
        end tell
    " 2>/dev/null || log_warn "Could not trigger Cmd+,"
    sleep 2
    take_screenshot "14-settings-window"
    
    # Close settings if opened
    osascript -e "
        tell application \"System Events\"
            tell process \"$APP_NAME\"
                keystroke \"w\" using command down
            end tell
        end tell
    " 2>/dev/null || true
    sleep 1
    
    log_ok "Interaction phase complete"
}

# =============================================================================
# Phase 4: Static Code Audit (Design Spec Compliance)
# =============================================================================

phase_static() {
    log_info "=== Phase 4: Static Code Audit ==="
    ensure_output_dir
    
    local VIEWS_DIR="$PROJECT_ROOT/AudioRecordApp/Sources/Views"
    local UTILS_DIR="$PROJECT_ROOT/AudioRecordApp/Sources/Utilities"
    local REPORT="$OUTPUT_DIR/static-audit-report.md"
    
    echo "# Static UI Audit Report" > "$REPORT"
    echo "" >> "$REPORT"
    echo "> Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT"
    echo "" >> "$REPORT"
    
    # --- Check 1: Hardcoded colors (should use IndustrialColors tokens) ---
    echo "## 1. Hardcoded Colors (should use IndustrialColors)" >> "$REPORT"
    echo "" >> "$REPORT"
    echo '```' >> "$REPORT"
    grep -rn "NSColor(" "$VIEWS_DIR" --include="*.swift" | grep -v "IndustrialColors" | grep -v ".bak" | head -30 >> "$REPORT" 2>/dev/null || echo "None found" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"
    
    # --- Check 2: Hardcoded hex values ---
    echo "## 2. Hardcoded Hex Color Values" >> "$REPORT"
    echo "" >> "$REPORT"
    echo '```' >> "$REPORT"
    grep -rn '#[0-9A-Fa-f]\{6\}' "$VIEWS_DIR" --include="*.swift" | grep -v ".bak" | head -20 >> "$REPORT" 2>/dev/null || echo "None found" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"
    
    # --- Check 3: Font usage (should use IndustrialTypography) ---
    echo "## 3. Font Usage (should use IndustrialTypography)" >> "$REPORT"
    echo "" >> "$REPORT"
    echo '```' >> "$REPORT"
    grep -rn "NSFont\." "$VIEWS_DIR" --include="*.swift" | grep -v "IndustrialTypography" | grep -v ".bak" | head -20 >> "$REPORT" 2>/dev/null || echo "None found" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"
    
    # --- Check 4: Spacing values (should be multiples of 4) ---
    echo "## 4. Non-standard Spacing Values (not multiples of 4)" >> "$REPORT"
    echo "" >> "$REPORT"
    echo '```' >> "$REPORT"
    grep -rn "constant:" "$VIEWS_DIR" --include="*.swift" | grep -v ".bak" | grep -oE 'constant: -?[0-9]+' | sort | uniq -c | sort -rn | head -20 >> "$REPORT" 2>/dev/null || echo "None found" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"
    
    # --- Check 5: Accessibility identifiers ---
    echo "## 5. Accessibility Identifiers" >> "$REPORT"
    echo "" >> "$REPORT"
    echo '```' >> "$REPORT"
    local acc_count
    acc_count=$(grep -rn "accessibilityIdentifier\|accessibilityLabel\|setAccessibility" "$VIEWS_DIR" --include="*.swift" | grep -v ".bak" | wc -l)
    echo "Total accessibility annotations: $acc_count" >> "$REPORT"
    grep -rn "accessibilityIdentifier\|accessibilityLabel\|setAccessibility" "$VIEWS_DIR" --include="*.swift" | grep -v ".bak" | head -10 >> "$REPORT" 2>/dev/null || true
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"
    
    # --- Check 6: Empty delegate methods ---
    echo "## 6. Empty Delegate/Protocol Methods (potential interaction gaps)" >> "$REPORT"
    echo "" >> "$REPORT"
    echo '```' >> "$REPORT"
    grep -rn -A2 "func.*{$" "$VIEWS_DIR" --include="*.swift" | grep -B1 "^.*}$" | grep "func" | grep -v ".bak" | head -20 >> "$REPORT" 2>/dev/null || echo "None found" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"
    
    # --- Check 7: TODO/FIXME/HACK in views ---
    echo "## 7. TODO/FIXME/HACK Comments in Views" >> "$REPORT"
    echo "" >> "$REPORT"
    echo '```' >> "$REPORT"
    grep -rn "TODO\|FIXME\|HACK\|XXX" "$VIEWS_DIR" --include="*.swift" | grep -v ".bak" | head -20 >> "$REPORT" 2>/dev/null || echo "None found" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"
    
    # --- Check 8: DispatchQueue.main usage (UI thread safety) ---
    echo "## 8. DispatchQueue.main Usage (UI thread safety)" >> "$REPORT"
    echo "" >> "$REPORT"
    echo '```' >> "$REPORT"
    grep -rn "DispatchQueue.main" "$VIEWS_DIR" --include="*.swift" | grep -v ".bak" | head -15 >> "$REPORT" 2>/dev/null || echo "None found" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"
    
    # --- Summary ---
    echo "## Summary" >> "$REPORT"
    echo "" >> "$REPORT"
    local total_views
    total_views=$(find "$VIEWS_DIR" -name "*.swift" ! -name "*.bak" | wc -l)
    echo "- Total View files scanned: $total_views" >> "$REPORT"
    echo "- Report location: $REPORT" >> "$REPORT"
    echo "- Next step: AI reads this report + screenshots for comprehensive review" >> "$REPORT"
    
    log_ok "Static audit report: $REPORT"
    cat "$REPORT"
}

# =============================================================================
# Phase 5: Generate AI Review Prompt
# =============================================================================

phase_review_prompt() {
    log_info "=== Phase 5: AI Review Prompt ==="
    
    local PROMPT_FILE="$OUTPUT_DIR/ai-review-prompt.md"
    
    cat > "$PROMPT_FILE" << 'PROMPT'
# AI UI Review Instructions

## For the AI reviewer (read_image each screenshot):

### Visual Checklist (per screenshot):
1. **Background**: Is it `#0E1416` (cool dark teal-black)? Not pure black.
2. **Text color**: Is primary text `#DDE4E5`? Not pure white.
3. **Accent color**: Is interactive accent Cyan `#8AEBFF`? Not blue/purple.
4. **Waveform**: Is it Coral `#FF6B5F`? The signature color.
5. **Borders**: Are they subtle `#3C494C`? Not bright.
6. **Font**: System font (SF Pro)? Numbers monospaced?
7. **Spacing**: 8px grid rhythm? Consistent padding?
8. **Record button**: Red circle, prominent, with glow when active?
9. **Status bar**: Compact, monospaced data, bottom of window?
10. **Information density**: Dense but not cluttered?

### Interaction Checklist (comparing before/after screenshots):
1. **State transition**: Is the visual change clear between states?
2. **Button feedback**: Did the button visually respond?
3. **Status update**: Did status bar text change appropriately?
4. **Waveform**: Did it start/stop scrolling?
5. **Level meter**: Did it respond to audio?
6. **No UI glitches**: No overlapping, no truncation, no misalignment?

### Design System Violations to Flag:
- Pure white (#FFFFFF) text
- Pure black (#000000) background
- Emoji as UI elements (should be SF Symbols)
- Rounded corners > 16px (except record button)
- Decorative gradients
- Center-aligned body text
- Card with colored left border pattern
PROMPT

    log_ok "AI review prompt: $PROMPT_FILE"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║     AudioRecord AI UI Test Suite                 ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    local mode="${1:-full}"
    
    case "$mode" in
        --screenshot)
            phase_screenshot
            phase_review_prompt
            ;;
        --interact)
            phase_interact
            phase_review_prompt
            ;;
        --static)
            phase_static
            ;;
        --full|full|"")
            phase_build
            phase_screenshot
            phase_interact
            phase_static
            phase_review_prompt
            ;;
        *)
            echo "Usage: $0 [--screenshot|--interact|--static|--full]"
            exit 1
            ;;
    esac
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "Test complete. Results in: $OUTPUT_DIR"
    echo ""
    echo "Next steps for AI review:"
    echo "  1. AI reads screenshots via read_image tool"
    echo "  2. AI reads static-audit-report.md"
    echo "  3. AI compares against docs/设计/design-system.md"
    echo "  4. AI outputs findings and fix suggestions"
    echo "═══════════════════════════════════════════════════"
}

main "$@"
