#!/bin/bash
# 打 DMG：make-dmg.sh <app_path> <dmg_output> [卷名]
# 布局 = App + /Applications 软链（拖拽安装），UDZO 压缩。
set -euo pipefail

APP_PATH="${1:?用法: make-dmg.sh <app_path> <dmg_output> [卷名]}"
DMG_OUT="${2:?缺 dmg 输出路径}"
VOL_NAME="${3:-Loocap}"

[[ -d "$APP_PATH" ]] || { echo "❌ App 不存在: $APP_PATH" >&2; exit 1; }
APP_BUNDLE="$(basename "$APP_PATH")"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/loocap-dmg.XXXXXX")"
SRC_DIR="$STAGING/src"
mkdir -p "$SRC_DIR"
trap 'rm -rf "$STAGING"' EXIT

# 复制 App 并清隔离属性（避免「已损坏」提示）
# 注意：raw.dmg 必须放在 src/ 之外——hdiutil 输出落在 srcfolder 内会静默失败
ditto "$APP_PATH" "$SRC_DIR/$APP_BUNDLE"
xattr -dr com.apple.quarantine "$SRC_DIR/$APP_BUNDLE" 2>/dev/null || true
xattr -dr com.apple.metadata:kMDItemWhereFroms "$SRC_DIR/$APP_BUNDLE" 2>/dev/null || true

# 拖到 Applications 的软链
ln -s /Applications "$SRC_DIR/Applications"

RAW_DMG="$STAGING/raw.dmg"
hdiutil create -fs HFS+ -volname "$VOL_NAME" -srcfolder "$SRC_DIR" -ov "$RAW_DMG"
mkdir -p "$(dirname "$DMG_OUT")"
hdiutil convert "$RAW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT" -quiet

echo "💿 DMG 已生成：$DMG_OUT"
