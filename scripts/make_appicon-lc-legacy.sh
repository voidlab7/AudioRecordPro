#!/bin/bash
# UI-016: 从 SVG 正本生成 Loocap v2 logo AppIcon.icns（可复跑）
# 管线：SVG 正本 → Swift NSImage 渲染 → PIL 底板合成（1024 母版）→ iconset → icns
# 用法: make_appicon.sh [SVG 正本路径]（默认 docs/设计稿/logo-v2.svg）
# 旧 LC 字标管线备份：make_appicon-lc-legacy.sh（保留备用）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG_SRC="${1:-$ROOT/docs/设计稿/logo-v2.svg}"
RENDER_PNG="$ROOT/build/logo-v2-render.png"   # SVG 渲染中间产物 800×630
OUT_PNG="$ROOT/build/AppIcon-1024.png"        # 1024 母版
ICNS_OUT="$ROOT/AudioRecordApp/Resources/Assets/AppIcon.icns"
ICONSET="$ROOT/build/AppIcon.iconset"
RENDERER="$ROOT/scripts/render_svg.swift"

command -v iconutil >/dev/null || { echo "need macOS iconutil"; exit 1; }
command -v python3 >/dev/null || { echo "need python3"; exit 1; }
[ -f "$SVG_SRC" ] || { echo "SVG 正本不存在: $SVG_SRC"; exit 1; }
[ -f "$RENDERER" ] || { echo "渲染器不存在: $RENDERER"; exit 1; }

# 1) SVG → PNG（Swift NSImage 原生渲染）
mkdir -p "$ROOT/build"
swift "$RENDERER" "$SVG_SRC" "$RENDER_PNG" 800 630

# 2) PIL 底板合成（1024 母版）：米白圆角方块 + logo 内容居中
#    macOS 标准图标网格：1024 画布，圆角方块 824×824、圆角 185、底色 #F7F7F5
#    logo 内容（SVG bbox 155,75-700,560 = 545×485）1:1 贴入 → 占方块 545/824 ≈ 66%（验收 ~64-70%）
python3 - "$RENDER_PNG" "$OUT_PNG" <<'PY'
import sys
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")

# logo 内容 bbox（SVG 坐标）外扩 15px 容纳笔画半径（stroke-width 30 的一半）
BBOX = (140, 60, 715, 575)
logo = im.crop(BBOX)

CANVAS = 1024
BLOCK = 824
RADIUS = 185
canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
draw = ImageDraw.Draw(canvas)
BX = (CANVAS - BLOCK) // 2  # 100
BY = (CANVAS - BLOCK) // 2  # 100
draw.rounded_rectangle((BX, BY, BX + BLOCK, BY + BLOCK), radius=RADIUS,
                       fill=(247, 247, 245, 255))  # #F7F7F5 米白

lw, lh = logo.size
lx = BX + (BLOCK - lw) // 2
ly = BY + (BLOCK - lh) // 2
canvas.paste(logo, (lx, ly), logo)
canvas.save(out)
print(f"底板合成完成: {out} | 内容 {lw}x{lh} 占方块 {lw/BLOCK*100:.1f}%（验收 ~64-70%）")
PY

# 3) 全尺寸 iconset → icns
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
  size=${spec%% *}; name=${spec#* }
  sips -z "$size" "$size" "$OUT_PNG" --out "$ICONSET/$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
echo "✅ AppIcon.icns 已更新: $ICNS_OUT"
