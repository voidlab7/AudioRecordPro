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
xcodebuild test \
  -project "$PROJECT_FILE" \
  -scheme AudioRecordMac \
  -destination 'platform=macOS' \
  -only-testing:AudioRecordMacSnapshotTests
