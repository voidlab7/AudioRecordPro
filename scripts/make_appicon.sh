#!/bin/bash
# UI-007: 从 1024 正本生成 Loocap LC 图标 AppIcon.icns（可复跑）
# 用法: make_appicon.sh [正本路径]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/docs/设计稿/logo-lc-正本-1024.jpg}"
OUT_PNG="$ROOT/build/AppIcon-1024.png"
ICNS_OUT="$ROOT/AudioRecordApp/Resources/Assets/AppIcon.icns"
ICONSET="$ROOT/build/AppIcon.iconset"

command -v iconutil >/dev/null || { echo "need macOS iconutil"; exit 1; }
[ -f "$SRC" ] || { echo "正本不存在: $SRC"; exit 1; }

# 1) 像素定位圆角方框主体（灰描边 ~#969696 on 深底 #1A1A1C），裁掉底部 Loocap 文字与边距
python3 - "$SRC" "$OUT_PNG" <<'PY'
import sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
W, H = im.size
px = im.load()
def is_edge(p):  # 灰描边像素
    r, g, b = p
    return r > 100 and abs(r-g) < 20 and abs(g-b) < 20
minx, miny, maxx, maxy = W, H, 0, 0
for y in range(0, H, 2):
    for x in range(0, W, 2):
        if is_edge(px[x, y]):
            # 排除底部文字区（Loocap 文字也是灰的，取面积最大的上块：y < H*0.82）
            if y < H * 0.82:
                minx, miny = min(minx, x), min(miny, y)
                maxx, maxy = max(maxx, x), max(maxy, y)
# 方形化并留 2% 余量
cx, cy = (minx+maxx)//2, (miny+maxy)//2
side = max(maxx-minx, maxy-miny) + int(W*0.02)
half = side//2
box = (max(0,cx-half), max(0,cy-half), min(W,cx+half), min(H,cy+half))
icon = im.crop(box).resize((1024,1024), Image.LANCZOS)
icon.save(out)
print(f"主体 bbox=({minx},{miny},{maxx},{maxy}) crop={box} -> {out}")
PY

# 2) 全尺寸 iconset → icns
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
  size=${spec%% *}; name=${spec#* }
  sips -z "$size" "$size" "$OUT_PNG" --out "$ICONSET/$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
echo "✅ AppIcon.icns 已更新: $ICNS_OUT"
