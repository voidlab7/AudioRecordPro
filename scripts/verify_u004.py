#!/usr/bin/env python3
"""UI-004 验证 v2：选中绿行右边界 → 推算侧栏宽。"""
from PIL import Image

im = Image.open("shot_u004.png").convert("RGB")
W, H = im.size
# 选中系统行 1x y≈130 → 2x y≈260 附近扫几行
for y2 in (250, 260, 270):
    right = None
    for x in range(W - 1, 0, -1):
        r, g, b = im.getpixel((x, y2))
        if g > 120 and g > r + 40:  # 品牌绿
            right = x
            break
    if right:
        print(f"y2={y2}: green row right edge x={right} -> {right/2.0}pt; sidebar≈{right/2.0 + 12.5:.1f}pt")
