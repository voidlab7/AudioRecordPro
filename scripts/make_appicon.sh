#!/bin/bash
# UI-016: 从 SVG 矢量正本生成 Loocap 新 logo AppIcon.icns（可复跑）
# 管线：docs/设计稿/logo-v2.svg → 合成 1024 母版（macOS 标准网格圆角方块 + 米白底）→ iconset 10 档 → icns
# 旧 LC 暗底管线备份在 make_appicon-lc-legacy.sh（UI-007，备用不删）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/docs/设计稿/logo-v2.svg"
MASTER_SVG="$ROOT/build/AppIcon-master.svg"
OUT_PNG="$ROOT/build/AppIcon-1024.png"
ICNS_OUT="$ROOT/AudioRecordApp/Resources/Assets/AppIcon.icns"
ICONSET="$ROOT/build/AppIcon.iconset"

command -v rsvg-convert >/dev/null || { echo "need rsvg-convert (brew install librsvg)"; exit 1; }
command -v iconutil >/dev/null || { echo "need macOS iconutil"; exit 1; }
[ -f "$SVG" ] || { echo "SVG 正本不存在: $SVG"; exit 1; }
mkdir -p "$ROOT/build"

# 1) 合成 1024 母版：macOS 标准图标网格——圆角方块 824×824（边距 100，圆角 ~185），
#    米白底 #F9F9F7；logo 内容(bbox 570×526 @ (437,340))缩放 0.95 → 占方块宽 65.7%，居中
python3 - "$SVG" "$MASTER_SVG" <<'PY'
import sys, re
svg_src, out = sys.argv[1], sys.argv[2]
text = open(svg_src, encoding='utf-8').read()
m = re.search(r'<svg[^>]*>(.*)</svg>', text, re.S)
inner = m.group(1)
# 去掉注释与 xmlns 重复风险：只保留 <g>/<circle> 元素
body = "\n".join(l for l in inner.splitlines() if not l.strip().startswith('<!--') and '<!--' not in l)
s = 0.95
tx, ty = 512 - 437*s, 512 - 340*s
master = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <rect x="100" y="100" width="824" height="824" rx="185" ry="185" fill="#F9F9F7"/>
  <g transform="translate({tx:.2f},{ty:.2f}) scale({s})">
{body}
  </g>
</svg>
'''
open(out,'w').write(master)
print(f"母版 SVG: tile 824×824 r185 米白, logo scale={s} 居中")
PY

# 2) 渲染 1024 母版 PNG
rsvg-convert -w 1024 -h 1024 "$MASTER_SVG" -o "$OUT_PNG"
echo "✅ 1024 母版: $OUT_PNG"

# 3) iconset 10 档（直接从母版 SVG 矢量渲染，小尺寸不发糊）
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" \
            "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" \
            "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  size=${spec%% *}; name=${spec#* }
  rsvg-convert -w "$size" -h "$size" "$MASTER_SVG" -o "$ICONSET/$name"
done
echo "✅ iconset 10 档生成"

# 4) icns
iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
echo "✅ icns: $ICNS_OUT"

# 5) 512 预览（验收用）
rsvg-convert -w 512 -h 512 "$MASTER_SVG" -o "$ROOT/build/AppIcon-512-preview.png"
echo "完成。预览: $ROOT/build/AppIcon-512-preview.png"
