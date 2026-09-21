#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/AudioRecordMac.xcodeproj"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ xcodegen is required to generate AudioRecordMac.xcodeproj"
  echo "Install it with: brew install xcodegen"
  exit 127
fi

if [ ! -d "$PROJECT_FILE" ] || [ "$ROOT_DIR/project.yml" -nt "$PROJECT_FILE" ]; then
  echo "🔧 Generating Xcode project..."
  xcodegen generate --spec "$ROOT_DIR/project.yml"
fi

echo "📸 Running AudioRecordMac snapshot tests..."
mkdir -p "$ROOT_DIR/test_logs"
LOG_FILE="$ROOT_DIR/test_logs/snapshot_test_$(date +%Y%m%d-%H%M%S).log"
set +e
xcodebuild test \
  -project "$PROJECT_FILE" \
  -scheme AudioRecordMac \
  -destination 'platform=macOS' \
  -only-testing:AudioRecordMacSnapshotTests 2>&1 | tee "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}
set -e
echo "📄 日志已落盘: $LOG_FILE"
exit $EXIT_CODE
