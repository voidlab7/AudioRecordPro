#!/bin/bash
# 主构建脚本 - 编译 AudioRecordApp（左右分栏版本）
set -euo pipefail

APP_NAME="audio_record_mac"
PRODUCT_NAME="AudioRecordMac"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC_DIR="$ROOT_DIR/AudioRecordApp/Sources"
SDK_SRC_DIR="$ROOT_DIR/AudioRecordKit/Sources"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$PRODUCT_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 [1/5] 清理旧构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "📦 [2/5] 收集源文件..."
# 收集 SDK 源文件
SDK_SOURCES=$(find "$SDK_SRC_DIR" -name "*.swift" 2>/dev/null | tr '\n' ' ')

# 收集 App 源文件
APP_SOURCES=$(find "$APP_SRC_DIR" -name "*.swift" 2>/dev/null | tr '\n' ' ')

echo "🔧 [3/5] 编译 Swift 源码..."
swiftc \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework Cocoa \
  -framework AVFoundation \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework ScreenCaptureKit \
  -framework IOKit \
  -framework ServiceManagement \
  -o "$MACOS_DIR/$APP_NAME" \
  $SDK_SOURCES \
  $APP_SOURCES

echo "📋 [4/5] 复制资源..."
# 复制 Info.plist
if [ -f "$ROOT_DIR/AudioRecordApp/Resources/Info.plist" ]; then
  plutil -convert binary1 "$ROOT_DIR/AudioRecordApp/Resources/Info.plist" -o "$CONTENTS_DIR/Info.plist"
elif [ -f "$ROOT_DIR/Info.plist" ]; then
  plutil -convert binary1 "$ROOT_DIR/Info.plist" -o "$CONTENTS_DIR/Info.plist"
fi

# 复制资源文件
if [ -d "$ROOT_DIR/AudioRecordApp/Resources/Assets" ]; then
  rsync -a "$ROOT_DIR/AudioRecordApp/Resources/Assets/" "$RESOURCES_DIR/"
elif [ -d "$ROOT_DIR/assets" ]; then
  rsync -a "$ROOT_DIR/assets/" "$RESOURCES_DIR/"
fi

echo "🔐 [5/5] 代码签名..."
# 检查是否有 entitlements
if [ -f "$ROOT_DIR/AudioRecordApp/Resources/AudioRecordMac.entitlements" ]; then
  codesign --force --sign - \
    --entitlements "$ROOT_DIR/AudioRecordApp/Resources/AudioRecordMac.entitlements" \
    "$MACOS_DIR/$APP_NAME"
  codesign --force --sign - \
    --entitlements "$ROOT_DIR/AudioRecordApp/Resources/AudioRecordMac.entitlements" \
    "$APP_DIR"
else
  codesign --force --sign - "$MACOS_DIR/$APP_NAME"
  codesign --force --sign - "$APP_DIR"
fi

echo "✅ 构建完成！"
echo "📂 应用位置: $APP_DIR"
echo "🚀 运行: open \"$APP_DIR\""
