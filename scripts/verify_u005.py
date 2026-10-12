#!/usr/bin/env python3
"""UI-005 验证：底栏红钮质心 x vs 窗口水平中心。"""
from PIL import Image

im = Image.open("shot_u005.png").convert("RGB")
W, H = im.size
print("size", W, H)
# 底栏红钮：控制面板在窗口底部，1x 底栏区约 y 590-660 → 2x y 1180-1320
# 红色像素：r>180, g<120, b<120
xs = []
for y2 in range(1180, 1320):
    for x2 in range(1000, 1700):  # 只扫底栏中部，排除侧栏麦克风图标等杂散红
        r, g, b = im.getpixel((x2, y2))
        if r > 180 and g < 120 and b < 120:
            xs.append(x2)
if not xs:
    print("no red pixels found")
else:
    left, right = min(xs), max(xs)
    center = (left + right) / 2.0
    target = W / 2.0
    print(f"red button x-range 2x: [{left}, {right}] center={center}")
    print(f"window center={target}, deviation={abs(center-target)/2.0:.2f}pt")
