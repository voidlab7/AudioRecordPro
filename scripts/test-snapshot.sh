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

echo "⏸️  Snapshot 测试已停用（LOOP-05，2026-10-13）"
echo "   原因：SnapshotTesting 包引擎的 sandbox-exec 在本机执行环境必死（sandbox_apply EPERM），"
echo "   包已从工程摘除（project.yml 无 SnapshotTests target）；测试源码保留在 AudioRecordMacSnapshotTests/，"
echo "   恢复方式见 TODOS.md 归档 LOOP-05 条目。"
exit 0
