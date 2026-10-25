#!/bin/bash
# 主构建脚本 - 编译 AudioRecordApp（左右分栏版本）
set -euo pipefail

APP_NAME="Loocap"
PRODUCT_NAME="Loocap"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC_DIR="$ROOT_DIR/AudioRecordApp/Sources"
SDK_SRC_DIR="$ROOT_DIR/AudioRecordKit/Sources"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$PRODUCT_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 [1/5] 清理旧构建..."
# macOS 26 App Management TCC 会拦截 rm 已签名 bundle（Operation not permitted）：
# 先 mv 挪走再删，rm 失败也不阻断构建（旧目录留在 build.trash-*，无副作用）
if [ -d "$BUILD_DIR" ]; then
  TRASH_DIR="${BUILD_DIR}.trash-$(date +%s)"
  mv "$BUILD_DIR" "$TRASH_DIR" 2>/dev/null || true
  rm -rf "$TRASH_DIR" 2>/dev/null || true
fi
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
  -framework IOKit \
  -framework CryptoKit \
  -framework ServiceManagement \
  -framework ScreenCaptureKit \
  -framework Accelerate \
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

# i18n: 复制本地化资源（en.lproj / zh-Hans.lproj 的 Localizable.strings / InfoPlist.strings）
if [ -d "$ROOT_DIR/AudioRecordApp/Sources/L10n" ]; then
  find "$ROOT_DIR/AudioRecordApp/Sources/L10n" -name "*.lproj" -type d | while read -r lproj; do
    rsync -a "$lproj/" "$RESOURCES_DIR/$(basename "$lproj")/"
  done
  echo "   ✅ 本地化资源 (lproj) → App Resources"
fi

# V2.0: 复制 ffmpeg 到 App Resources（优先用 Resources 里的完整版）
echo "🎬 检查 ffmpeg..."
FFMPEG_SRC=""
# 1. 项目 Resources 目录（完整静态编译版，77MB）
if [ -x "$ROOT_DIR/AudioRecordApp/Resources/ffmpeg" ]; then
  FFMPEG_SRC="$ROOT_DIR/AudioRecordApp/Resources/ffmpeg"
# 2. Homebrew（可能只是 wrapper，检查是否足够大）
elif [ -x "/opt/homebrew/bin/ffmpeg" ] && [ "$(stat -f %z /opt/homebrew/bin/ffmpeg 2>/dev/null || echo 0)" -gt 1000000 ]; then
  FFMPEG_SRC="/opt/homebrew/bin/ffmpeg"
elif [ -x "/usr/local/bin/ffmpeg" ] && [ "$(stat -f %z /usr/local/bin/ffmpeg 2>/dev/null || echo 0)" -gt 1000000 ]; then
  FFMPEG_SRC="/usr/local/bin/ffmpeg"
fi
if [ -n "$FFMPEG_SRC" ]; then
  cp "$FFMPEG_SRC" "$RESOURCES_DIR/ffmpeg"
  chmod +x "$RESOURCES_DIR/ffmpeg"
  echo "   ✅ ffmpeg → App Resources"
else
  echo "   ⚠️  未找到 ffmpeg，FLAC/OGG 导出将不可用"
  echo "   安装: brew install ffmpeg"
fi

echo "🔐 [5/5] 代码签名..."
# INFRA-002: 优先用稳定身份 LoocapDev（自签证书，TCC 授权不随重编译重置）；
# 证书缺失时回退 adhoc（每次 cdhash 变化，TCC 当新 App，授权清零）
SIGN_IDENTITY="${LOOCAP_SIGN_IDENTITY:-LoocapDev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  SIGN_FLAG=(--sign "$SIGN_IDENTITY")
  echo "   使用稳定签名身份: $SIGN_IDENTITY"
else
  SIGN_FLAG=(--sign -)
  echo "   ⚠️ 未找到 $SIGN_IDENTITY，回退 adhoc（重建后需重新授权录屏/麦克风）"
  echo "   修复: 见 docs/INFRA-002-证书重建路径.md"
fi
# 检查是否有 entitlements
ENTITLEMENTS=""
for candidate in \
  "$ROOT_DIR/AudioRecordApp/Resources/AudioRecordMac.entitlements" \
  "$ROOT_DIR/AudioRecordMac.entitlements" \
  "$ROOT_DIR/BuildResources/AudioRecordMac.entitlements"; do
  if [ -f "$candidate" ]; then ENTITLEMENTS="$candidate"; break; fi
done
if [ -n "$ENTITLEMENTS" ]; then
  codesign --force "${SIGN_FLAG[@]}" \
    --entitlements "$ENTITLEMENTS" \
    "$MACOS_DIR/$APP_NAME"
  codesign --force "${SIGN_FLAG[@]}" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR"
  echo "   ✅ 已签名（含 entitlements）"
else
  codesign --force "${SIGN_FLAG[@]}" "$MACOS_DIR/$APP_NAME"
  codesign --force "${SIGN_FLAG[@]}" "$APP_DIR"
  echo "   ✅ 已签名（无 entitlements）"
fi

echo "✅ 构建完成！"
echo "📂 应用位置: $APP_DIR"
echo "🚀 运行: open \"$APP_DIR\""
