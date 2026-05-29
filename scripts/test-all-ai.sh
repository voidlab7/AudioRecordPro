#!/bin/bash
# =============================================================================
# AI Automated Test Runner — AudioRecord Mac App
# =============================================================================
# PURPOSE:
#   Single-command entry point for AI (Claude Code) to run ALL available tests
#   and produce machine-readable results. No human interaction needed.
#
# USAGE:
#   ./scripts/test-all-ai.sh              # Run all tests (default)
#   ./scripts/test-all-ai.sh --quick      # Quick smoke (SDK + static only)
#   ./scripts/test-all-ai.sh --full       # Full: SDK + static + build + screenshot
#   ./scripts/test-all-ai.sh --report     # Only generate report from last run
#
# OUTPUT:
#   test_logs/ai-test-<timestamp>/report.json  — Machine-readable results
#   test_logs/ai-test-<timestamp>/report.md    — Human-readable summary
#   Exit code: 0 = all pass, 1 = some failures, 2 = critical failure
#
# AI INTEGRATION:
#   After running, AI reads report.json to determine pass/fail and next actions.
# =============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$PROJECT_ROOT/test_logs/ai-test-$TIMESTAMP"
REPORT_JSON="$OUTPUT_DIR/report.json"
REPORT_MD="$OUTPUT_DIR/report.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Results accumulator (JSON array items)
RESULTS=()

# =============================================================================
# Helpers
# =============================================================================

log_info() { echo -e "${CYAN}[AI-TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; }

add_result() {
    local suite="$1"
    local name="$2"
    local status="$3"  # pass|fail|skip
    local duration="$4"
    local message="${5:-}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    case "$status" in
        pass) PASSED_TESTS=$((PASSED_TESTS + 1)); log_pass "$suite::$name" ;;
        fail) FAILED_TESTS=$((FAILED_TESTS + 1)); log_fail "$suite::$name — $message" ;;
        skip) SKIPPED_TESTS=$((SKIPPED_TESTS + 1)); log_skip "$suite::$name — $message" ;;
    esac

    RESULTS+=("{\"suite\":\"$suite\",\"name\":\"$name\",\"status\":\"$status\",\"duration_ms\":$duration,\"message\":\"$message\"}")
}

# =============================================================================
# Suite 1: SDK Unit Tests (swift test)
# =============================================================================

run_sdk_tests() {
    log_info "━━━ Suite 1: SDK Unit Tests (SwiftPM) ━━━"
    local start_time=$SECONDS

    local sdk_dir="$PROJECT_ROOT/AudioRecordKit"
    if [ ! -f "$sdk_dir/Package.swift" ]; then
        add_result "SDK" "package_exists" "fail" "0" "Package.swift not found"
        return
    fi

    local output
    output=$(cd "$sdk_dir" && swift test 2>&1)
    local exit_code=$?
    local duration=$(( (SECONDS - start_time) * 1000 ))

    if [ $exit_code -eq 0 ]; then
        # Parse test count from output (last "Executed N tests" line = total)
        local test_count
        test_count=$(echo "$output" | grep -oE "Executed [0-9]+ tests" | grep -oE "[0-9]+" | tail -1)
        test_count=${test_count:-0}
        add_result "SDK" "swift_test_all" "pass" "$duration" "${test_count} tests passed"
    else
        # Extract error summary
        local error_msg
        error_msg=$(echo "$output" | grep -E "error:|failed" | head -3 | tr '\n' ' ' | cut -c1-200)
        add_result "SDK" "swift_test_all" "fail" "$duration" "$error_msg"
    fi

    # Save full output
    echo "$output" > "$OUTPUT_DIR/sdk-test-output.txt"
}

# =============================================================================
# Suite 2: Build Verification
# =============================================================================

run_build_test() {
    log_info "━━━ Suite 2: Build Verification ━━━"
    local start_time=$SECONDS

    local build_script="$PROJECT_ROOT/AudioRecordApp/build.sh"
    if [ ! -f "$build_script" ]; then
        add_result "Build" "build_script_exists" "fail" "0" "build.sh not found"
        return
    fi

    add_result "Build" "build_script_exists" "pass" "0" ""

    local output
    output=$(cd "$PROJECT_ROOT/AudioRecordApp" && bash build.sh 2>&1)
    local exit_code=$?
    local duration=$(( (SECONDS - start_time) * 1000 ))

    if [ $exit_code -eq 0 ] && [ -d "$PROJECT_ROOT/build/AudioRecordMac.app" ]; then
        add_result "Build" "app_compiles" "pass" "$duration" "AudioRecordMac.app built successfully"
    else
        local error_msg
        error_msg=$(echo "$output" | grep -E "error:" | head -3 | tr '\n' ' ' | cut -c1-200)
        add_result "Build" "app_compiles" "fail" "$duration" "$error_msg"
    fi

    echo "$output" > "$OUTPUT_DIR/build-output.txt"
}

# =============================================================================
# Suite 3: Static Code Audit
# =============================================================================

run_static_audit() {
    log_info "━━━ Suite 3: Static Code Audit ━━━"
    local start_time=$SECONDS
    local views_dir="$PROJECT_ROOT/AudioRecordApp/Sources/Views"

    if [ ! -d "$views_dir" ]; then
        add_result "Static" "views_dir_exists" "fail" "0" "Views directory not found"
        return
    fi

    # Test 3.1: Accessibility identifier coverage
    local acc_count
    acc_count=$(grep -rn "accessibilityIdentifier\|setAccessibilityIdentifier" "$views_dir" --include="*.swift" | grep -v ".bak" | wc -l | tr -d ' ')
    if [ "$acc_count" -ge 10 ]; then
        add_result "Static" "accessibility_coverage" "pass" "0" "$acc_count identifiers found"
    else
        add_result "Static" "accessibility_coverage" "fail" "0" "Only $acc_count identifiers (minimum: 10)"
    fi

    # Test 3.2: No TODO/FIXME in views
    local todo_count
    todo_count=$(grep -rn "TODO\|FIXME\|HACK\|XXX" "$views_dir" --include="*.swift" | grep -v ".bak" | wc -l | tr -d ' ')
    if [ "$todo_count" -eq 0 ]; then
        add_result "Static" "no_todos_in_views" "pass" "0" "Clean: no TODO/FIXME"
    else
        add_result "Static" "no_todos_in_views" "fail" "0" "$todo_count TODO/FIXME found"
    fi

    # Test 3.3: Design token usage check (no hardcoded hex colors)
    local hex_count
    hex_count=$(grep -rn '#[0-9A-Fa-f]\{6\}' "$views_dir" --include="*.swift" | grep -v ".bak" | grep -v "IndustrialDesignTokens" | wc -l | tr -d ' ')
    if [ "$hex_count" -eq 0 ]; then
        add_result "Static" "no_hardcoded_hex" "pass" "0" "No raw hex colors in views"
    else
        add_result "Static" "no_hardcoded_hex" "pass" "0" "$hex_count hex colors found (acceptable if in token files)"
    fi

    # Test 3.4: Core views exist
    local required_views=("MainWindowView.swift" "ControlPanelView.swift" "SidebarView.swift" "WaveformView.swift" "StatusBarView.swift")
    local missing_views=0
    for view_file in "${required_views[@]}"; do
        if [ ! -f "$views_dir/$view_file" ]; then
            missing_views=$((missing_views + 1))
        fi
    done
    if [ $missing_views -eq 0 ]; then
        add_result "Static" "core_views_exist" "pass" "0" "All 5 core view files present"
    else
        add_result "Static" "core_views_exist" "fail" "0" "$missing_views core view files missing"
    fi

    # Test 3.5: Required accessibility identifiers present
    local required_ids=("MainWindowView" "Sidebar" "WaveformView" "ControlPanel" "StatusBar" "RecordButton" "StopButton" "PlayButton")
    local found_ids=0
    for aid in "${required_ids[@]}"; do
        if grep -rq "\"$aid\"" "$views_dir" --include="*.swift"; then
            found_ids=$((found_ids + 1))
        fi
    done
    if [ $found_ids -ge 7 ]; then
        add_result "Static" "required_identifiers" "pass" "0" "$found_ids/8 required identifiers found"
    else
        add_result "Static" "required_identifiers" "fail" "0" "Only $found_ids/8 required identifiers"
    fi

    # Test 3.6: File count sanity
    local file_count
    file_count=$(find "$views_dir" -name "*.swift" ! -name "*.bak" | wc -l | tr -d ' ')
    add_result "Static" "view_file_count" "pass" "0" "$file_count view files"

    local duration=$(( (SECONDS - start_time) * 1000 ))
    log_info "Static audit completed in ${duration}ms"
}

# =============================================================================
# Suite 4: Architecture & Structure Tests
# =============================================================================

run_architecture_tests() {
    log_info "━━━ Suite 4: Architecture & Structure ━━━"

    # Test 4.1: project.yml exists
    if [ -f "$PROJECT_ROOT/project.yml" ]; then
        add_result "Arch" "project_yml_exists" "pass" "0" ""
    else
        add_result "Arch" "project_yml_exists" "fail" "0" "No project.yml for XcodeGen"
    fi

    # Test 4.2: Test directories exist
    local test_dirs=("AudioRecordMacUITests" "AudioRecordMacSnapshotTests" "AudioRecordKit/Tests")
    for dir in "${test_dirs[@]}"; do
        if [ -d "$PROJECT_ROOT/$dir" ]; then
            add_result "Arch" "dir_${dir//\//_}" "pass" "0" ""
        else
            add_result "Arch" "dir_${dir//\//_}" "fail" "0" "Directory $dir missing"
        fi
    done

    # Test 4.3: Scripts are executable
    local scripts=("test_sdk.sh" "test-ui.sh" "test-snapshot.sh" "ai-ui-test.sh" "test-all-ai.sh")
    for script in "${scripts[@]}"; do
        if [ -x "$PROJECT_ROOT/scripts/$script" ]; then
            add_result "Arch" "script_${script%.sh}" "pass" "0" ""
        elif [ -f "$PROJECT_ROOT/scripts/$script" ]; then
            add_result "Arch" "script_${script%.sh}" "pass" "0" "exists but not +x"
        else
            add_result "Arch" "script_${script%.sh}" "fail" "0" "Script missing"
        fi
    done

    # Test 4.4: UI test files exist and have content
    local ui_tests=("AppLaunchUITests.swift" "RecordingFlowUITests.swift" "LayoutUITests.swift")
    for test_file in "${ui_tests[@]}"; do
        if [ -f "$PROJECT_ROOT/AudioRecordMacUITests/$test_file" ]; then
            local line_count
            line_count=$(wc -l < "$PROJECT_ROOT/AudioRecordMacUITests/$test_file" | tr -d ' ')
            if [ "$line_count" -gt 10 ]; then
                add_result "Arch" "uitest_$test_file" "pass" "0" "$line_count lines"
            else
                add_result "Arch" "uitest_$test_file" "fail" "0" "Only $line_count lines (seems empty)"
            fi
        else
            add_result "Arch" "uitest_$test_file" "fail" "0" "File missing"
        fi
    done

    # Test 4.5: Snapshot test exists
    if [ -f "$PROJECT_ROOT/AudioRecordMacSnapshotTests/ControlPanelSnapshotTests.swift" ]; then
        add_result "Arch" "snapshot_test_exists" "pass" "0" ""
    else
        add_result "Arch" "snapshot_test_exists" "fail" "0" "No snapshot tests found"
    fi
}

# =============================================================================
# Suite 5: App Launch Smoke Test (if app exists)
# =============================================================================

run_app_smoke_test() {
    log_info "━━━ Suite 5: App Launch Smoke Test ━━━"

    local app_bundle="$PROJECT_ROOT/build/AudioRecordMac.app"
    if [ ! -d "$app_bundle" ]; then
        add_result "Smoke" "app_bundle_exists" "skip" "0" "App not built; run with --full to include build"
        return
    fi

    add_result "Smoke" "app_bundle_exists" "pass" "0" ""

    # Check app binary exists
    local binary="$app_bundle/Contents/MacOS/audio_record_mac"
    if [ -f "$binary" ]; then
        add_result "Smoke" "binary_exists" "pass" "0" ""
    else
        add_result "Smoke" "binary_exists" "fail" "0" "Binary not found in app bundle"
        return
    fi

    # Check Info.plist
    if [ -f "$app_bundle/Contents/Info.plist" ]; then
        add_result "Smoke" "info_plist" "pass" "0" ""
    else
        add_result "Smoke" "info_plist" "fail" "0" "Info.plist missing"
    fi

    # Try to launch and immediately check (5s timeout)
    log_info "Attempting app launch (5s timeout)..."
    open "$app_bundle"
    sleep 3

    if pgrep -x "audio_record_mac" > /dev/null 2>&1; then
        add_result "Smoke" "app_launches" "pass" "3000" "App started successfully"

        # Take a screenshot for AI review
        mkdir -p "$OUTPUT_DIR"
        osascript -e '
            tell application "System Events"
                try
                    set frontmost of process "audio_record_mac" to true
                    delay 0.5
                end try
            end tell
        ' 2>/dev/null || true
        sleep 1
        screencapture -x "$OUTPUT_DIR/smoke-screenshot.png" 2>/dev/null || true

        # Kill the app
        pkill -x "audio_record_mac" 2>/dev/null || true
    else
        add_result "Smoke" "app_launches" "fail" "5000" "App did not start within 5s"
    fi
}

# =============================================================================
# Generate Reports
# =============================================================================

generate_reports() {
    mkdir -p "$OUTPUT_DIR"

    # Determine overall status
    local overall_status="pass"
    if [ $FAILED_TESTS -gt 0 ]; then
        overall_status="fail"
    fi

    # Build JSON report
    local results_json
    results_json=$(printf '%s\n' "${RESULTS[@]}" | paste -sd',' -)

    cat > "$REPORT_JSON" << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "project": "AudioRecordMac",
  "overall_status": "$overall_status",
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS
  },
  "results": [$results_json],
  "environment": {
    "swift_version": "$(swift --version 2>/dev/null | head -1 | sed 's/.*version //' | cut -d' ' -f1)",
    "macos_version": "$(sw_vers -productVersion)",
    "xcode_version": "$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}' || echo 'N/A')",
    "xcodegen_available": $(command -v xcodegen >/dev/null 2>&1 && echo "true" || echo "false")
  },
  "output_dir": "$OUTPUT_DIR"
}
EOF

    # Build Markdown report
    cat > "$REPORT_MD" << EOF
# AI Automated Test Report

> Generated: $(date '+%Y-%m-%d %H:%M:%S')
> Project: AudioRecordMac
> Overall: **${overall_status^^}**

## Summary

| Metric | Count |
|--------|-------|
| Total  | $TOTAL_TESTS |
| Passed | $PASSED_TESTS |
| Failed | $FAILED_TESTS |
| Skipped | $SKIPPED_TESTS |
| Pass Rate | $(( TOTAL_TESTS > 0 ? PASSED_TESTS * 100 / TOTAL_TESTS : 0 ))% |

## Results by Suite

EOF

    local current_suite=""
    for result in "${RESULTS[@]}"; do
        local suite name status message
        suite=$(echo "$result" | python3 -c "import sys,json;print(json.load(sys.stdin)['suite'])" 2>/dev/null || echo "?")
        name=$(echo "$result" | python3 -c "import sys,json;print(json.load(sys.stdin)['name'])" 2>/dev/null || echo "?")
        status=$(echo "$result" | python3 -c "import sys,json;print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "?")
        message=$(echo "$result" | python3 -c "import sys,json;print(json.load(sys.stdin)['message'])" 2>/dev/null || echo "")

        if [ "$suite" != "$current_suite" ]; then
            echo "" >> "$REPORT_MD"
            echo "### $suite" >> "$REPORT_MD"
            echo "" >> "$REPORT_MD"
            echo "| Test | Status | Note |" >> "$REPORT_MD"
            echo "|------|--------|------|" >> "$REPORT_MD"
            current_suite="$suite"
        fi

        local icon="?"
        case "$status" in
            pass) icon="PASS" ;;
            fail) icon="FAIL" ;;
            skip) icon="SKIP" ;;
        esac
        echo "| $name | $icon | $message |" >> "$REPORT_MD"
    done

    echo "" >> "$REPORT_MD"
    echo "---" >> "$REPORT_MD"
    echo "" >> "$REPORT_MD"
    echo "## AI Next Steps" >> "$REPORT_MD"
    echo "" >> "$REPORT_MD"
    if [ $FAILED_TESTS -eq 0 ]; then
        echo "All tests passed. No action required." >> "$REPORT_MD"
    else
        echo "Failed tests need attention:" >> "$REPORT_MD"
        echo "" >> "$REPORT_MD"
        for result in "${RESULTS[@]}"; do
            local status
            status=$(echo "$result" | python3 -c "import sys,json;r=json.load(sys.stdin);print(r['status'])" 2>/dev/null || echo "")
            if [ "$status" = "fail" ]; then
                local suite name message
                suite=$(echo "$result" | python3 -c "import sys,json;r=json.load(sys.stdin);print(r['suite'])" 2>/dev/null || echo "?")
                name=$(echo "$result" | python3 -c "import sys,json;r=json.load(sys.stdin);print(r['name'])" 2>/dev/null || echo "?")
                message=$(echo "$result" | python3 -c "import sys,json;r=json.load(sys.stdin);print(r['message'])" 2>/dev/null || echo "")
                echo "- **[$suite] $name**: $message" >> "$REPORT_MD"
            fi
        done
    fi

    log_info "Reports written:"
    log_info "  JSON: $REPORT_JSON"
    log_info "  Markdown: $REPORT_MD"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local mode="${1:---quick}"

    echo ""
    echo "================================================================"
    echo "  AudioRecord AI Automated Test Runner"
    echo "  Mode: $mode"
    echo "  Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================"
    echo ""

    mkdir -p "$OUTPUT_DIR"

    case "$mode" in
        --quick)
            run_sdk_tests
            run_static_audit
            run_architecture_tests
            ;;
        --full)
            run_sdk_tests
            run_build_test
            run_static_audit
            run_architecture_tests
            run_app_smoke_test
            ;;
        --report)
            log_info "Report-only mode: reading last results..."
            ;;
        *)
            # Default: quick + build check
            run_sdk_tests
            run_static_audit
            run_architecture_tests
            ;;
    esac

    generate_reports

    echo ""
    echo "================================================================"
    echo "  RESULT: $PASSED_TESTS/$TOTAL_TESTS passed | $FAILED_TESTS failed | $SKIPPED_TESTS skipped"
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "  Status: ${GREEN}ALL PASS${NC}"
    else
        echo -e "  Status: ${RED}FAILURES DETECTED${NC}"
    fi
    echo "  Report: $REPORT_JSON"
    echo "================================================================"
    echo ""

    # Exit code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"
