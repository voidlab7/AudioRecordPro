#!/usr/bin/env python3
"""批次2k 验证第二版：修正 DB METER / Not Monitoring 扫描区域（1x→2x 坐标换算）。"""
from collections import Counter

from PIL import Image

im = Image.open("shot_u003_2k.png").convert("RGB")

# DB METER：预览(0.9x)约 (1023..1058, 80..88) → 1x (1136..1176, 89..98) → 2x (2272..2352, 178..196)
c2 = Counter()
for y in range(170, 205):
    for x in range(2240, 2380):
        p = im.getpixel((x, y))
        if p[0] > 80:
            c2[p] += 1
print("DB METER text top:", c2.most_common(5))

# Not Monitoring：预览 (1012..1057, 305..317) → 2x x(2248..2350) y(678..706)
c3 = Counter()
for y in range(660, 720):
    for x in range(2230, 2380):
        p = im.getpixel((x, y))
        if p[0] > 80:
            c3[p] += 1
print("NotMonitoring text top:", c3.most_common(5))

# L/R 标签：预览 y≈537 → 2x y≈1190..1215, x 2240..2360
c4 = Counter()
for y in range(1180, 1230):
    for x in range(2240, 2370):
        p = im.getpixel((x, y))
        if p[0] > 80:
            c4[p] += 1
print("L/R label top:", c4.most_common(3))
