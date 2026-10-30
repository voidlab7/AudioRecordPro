#!/bin/bash
# 本地版本化构建流水线：主线（master）每次合并产出一个可追溯版本 1.1.<build>
#
# 职责：
#   1. 递增 build 号（releases/BUILD_NUMBER，本地计数，构建失败不消耗号）
#   2. 调 build-app.sh 出包（版本号经 LOOCAP_VERSION / LOOCAP_BUILD / LOOCAP_BUILD_COMMIT 注入 Info.plist）
#   3. 归档产物到 releases/<版本>/Loocap.app + 打 DMG
#   4. 追加台账 releases/builds.tsv（build 号 ↔ commit ↔ 时间 ↔ 说明）
#   5. 打 tag v<版本> 推送 GitHub，并上传 DMG 创建 Release（可跳过；失败不阻断本地版本）
#
# 用法：
#   scripts/release-build.sh                # 正常出下一个版本（同 commit 已构建过则跳过）
#   scripts/release-build.sh --force        # 强制对当前 commit 重出一个新版本号
#   scripts/release-build.sh --no-release   # 只出本地版本，不打 tag 不上传
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FORCE=0
NO_RELEASE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --no-release) NO_RELEASE=1 ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

# 只在主线 master 上出正式版本号
BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "master" ]]; then
  echo "⏭️  跳过：当前分支 $BRANCH 不是 master（只有主线合并才出版本）"
  exit 0
fi

COMMIT="$(git rev-parse --short HEAD)"
SUBJECT="$(git log -1 --pretty=%s)"

mkdir -p releases
STATE="releases/BUILD_NUMBER"
LEDGER="releases/builds.tsv"
LAST="releases/.last_built_commit"

# 同一 commit 已构建过（如 merge 前手动打包过验收）则跳过，防双份
if [[ $FORCE -eq 0 && -f "$LAST" && "$(cat "$LAST")" == "$COMMIT" ]]; then
  echo "⏭️  跳过：$COMMIT 已构建为 build $(cat "$STATE" 2>/dev/null || echo 0)（--force 可强制重建）"
  exit 0
fi

BUILD=$(( $(cat "$STATE" 2>/dev/null || echo 0) + 1 ))
MARKETING="$(cat VERSION 2>/dev/null || echo 1.1)"
VERSION="$MARKETING.$BUILD"

echo "🚀 构建版本 ${VERSION}（build #$BUILD @ ${COMMIT}）"
echo "   $SUBJECT"

# 构建失败则 build 号不消耗（STATE 不落盘，修复后重试顶上同一个号）
export LOOCAP_VERSION="$MARKETING"
export LOOCAP_BUILD="$BUILD"
export LOOCAP_BUILD_COMMIT="$COMMIT"
if ! bash "$ROOT/build-app.sh"; then
  echo "❌ 构建失败：build 号 $BUILD 未消耗，修复后重跑即可" >&2
  exit 1
fi

echo "$BUILD" > "$STATE"
echo "$COMMIT" > "$LAST"

# 归档产物（ditto 保留签名与元数据）
DEST="releases/$VERSION"
rm -rf "$DEST"
mkdir -p "$DEST"
ditto "build/Loocap.app" "$DEST/Loocap.app"

# 台账：build 号 ↔ commit 追溯
if [[ ! -f "$LEDGER" ]]; then
  printf "build\tversion\tcommit\tdate\tnote\n" > "$LEDGER"
fi
printf "%s\t%s\t%s\t%s\t%s\n" \
  "$BUILD" "$VERSION" "$COMMIT" "$(date '+%Y-%m-%d %H:%M:%S')" "$SUBJECT" >> "$LEDGER"

echo ""
echo "📦 版本 $VERSION 已归档：$DEST/Loocap.app"

# ── DMG 打包 ──
DMG_PATH="$DEST/Loocap-$VERSION.dmg"
if ! bash "$ROOT/scripts/make-dmg.sh" "$DEST/Loocap.app" "$DMG_PATH" "Loocap $VERSION"; then
  echo "⚠️ DMG 打包失败（归档的 .app 不受影响），跳过 tag/发布" >&2
  exit 0
fi

if [[ $NO_RELEASE -eq 1 || "${LOOCAP_SKIP_RELEASE:-0}" == "1" ]]; then
  echo "⏭️  按参数要求跳过 GitHub 发布（本地版本 $VERSION 已就绪）"
  exit 0
fi

# ── GitHub 发布：tag + DMG 上传（离线/无凭据不阻断，留重试提示）──
TAG="v$VERSION"

git tag -f -a "$TAG" -m "Loocap ${VERSION}（build #$BUILD @ ${COMMIT}）" 2>/dev/null
if GIT_TERMINAL_PROMPT=0 git push -f origin "$TAG" 2>/dev/null; then
  echo "🏷️  标签 $TAG 已推送 GitHub"
else
  echo "⚠️ 标签推送失败（离线或无凭据？），手动重试: git push -f origin $TAG" >&2
fi

GH_BIN="$(command -v gh || echo /opt/homebrew/bin/gh)"
if [[ ! -x "$GH_BIN" ]] || ! "$GH_BIN" auth status >/dev/null 2>&1; then
  echo "⏭️  gh 未登录，跳过 Release 上传（跑一次: gh auth login，之后钩子自动发布）"
  echo "    手动补发: $GH_BIN release create $TAG $DMG_PATH --title Loocap-$VERSION --notes ..."
  exit 0
fi

# Release Notes：上一个 tag 以来的提交列表
PREV_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
if [[ -n "$PREV_TAG" ]]; then
  CHANGELOG="$(git log --pretty='- %s' "$PREV_TAG"..HEAD)"
else
  CHANGELOG="$(git log --pretty='- %s' -5)"
fi
NOTES="Loocap ${VERSION}（build #${BUILD}，commit ${COMMIT}）

## 本次变更
$CHANGELOG

## 安装
下载 DMG → 拖入 Applications。首跑若提示「已损坏」或未公证警告：右键 App → 打开（或 xattr -cr /Applications/Loocap.app）。"

echo "🚀 创建 GitHub Release $TAG ..."
if "$GH_BIN" release create "$TAG" "$DMG_PATH" \
    --title "Loocap $VERSION" \
    --notes "$NOTES"; then
  echo "   ✅ Release 已发布：$DMG_PATH 已随附上传"
else
  echo "⚠️ Release 创建失败，手动重试:" >&2
  echo "   $GH_BIN release create $TAG $DMG_PATH --title Loocap-$VERSION --notes-file <file>" >&2
fi
