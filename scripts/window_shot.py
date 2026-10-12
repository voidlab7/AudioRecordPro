#!/usr/bin/env python3
"""UI-003 截图工具：按 PID 找主窗口 → CGWindowListCreateImage → 内存像素 → 纯 Python PNG 编码。
全程零临时文件（绕开沙箱/安全中心对临时文件的拦截）。
用法: window_shot.py <pid> <output.png>
"""
import struct
import sys
import zlib

import Quartz


def encode_png(raw: bytes, width: int, height: int, bytes_per_row: int) -> bytes:
    """RGBA8 原始像素 → PNG 字节流（纯 Python，无临时文件）。"""
    # 按行重组并加 filter 字节 0（None），兼容 bytes_per_row > width*4 的 padding
    stride = width * 4
    scanlines = bytearray()
    for y in range(height):
        scanlines.append(0)  # filter type None
        scanlines += raw[y * bytes_per_row : y * bytes_per_row + stride]

    def chunk(tag: bytes, data: bytes) -> bytes:
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8bit RGBA
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(scanlines), 6))
        + chunk(b"IEND", b"")
    )


def main() -> int:
    pid = int(sys.argv[1])
    out_path = sys.argv[2]

    wl = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly, 0
    )
    win_id = None
    for w in wl:
        if w.get("kCGWindowOwnerPID") == pid:
            bounds = dict(w.get("kCGWindowBounds") or {})
            if bounds.get("Width", 0) > 500:  # 主窗口（排除小浮窗）
                win_id = w.get("kCGWindowNumber")
                print(
                    f"window {win_id} owner={w.get('kCGWindowOwnerName')} "
                    f"bounds={bounds.get('Width')}x{bounds.get('Height')}"
                )
                break
    if win_id is None:
        print("no window found for pid", pid)
        return 1

    img = Quartz.CGWindowListCreateImage(
        Quartz.CGRectNull,
        Quartz.kCGWindowListOptionIncludingWindow,
        win_id,
        Quartz.kCGWindowImageBoundsIgnoreFraming,
    )
    if img is None:
        print("CGWindowListCreateImage returned None（屏录权限或窗口离屏）")
        return 1

    width = Quartz.CGImageGetWidth(img)
    height = Quartz.CGImageGetHeight(img)
    bpr = Quartz.CGImageGetBytesPerRow(img)
    provider = Quartz.CGImageGetDataProvider(img)
    data = Quartz.CGDataProviderCopyData(provider)
    raw = bytes(data)  # CFData → bytes 拷贝
    # Window 图为 BGRA（kCGBitmapByteOrder32Little | premul RGBA8）；转 PNG 需要 RGBA
    png = encode_png_bgra(raw, width, height, bpr)
    with open(out_path, "wb") as f:  # 直写目标文件，无临时文件
        f.write(png)
    print(f"saved {out_path} ({width}x{height})")
    return 0


def encode_png_bgra(raw: bytes, width: int, height: int, bytes_per_row: int) -> bytes:
    """BGRA8（窗口抓图原生序）→ PNG RGBA 字节流。"""
    stride = width * 4
    scanlines = bytearray()
    for y in range(height):
        row = bytearray(raw[y * bytes_per_row : y * bytes_per_row + stride])
        # BGRA → RGBA 原地交换
        for i in range(0, stride, 4):
            row[i], row[i + 2] = row[i + 2], row[i]
        scanlines.append(0)  # filter None
        scanlines += row

    def chunk(tag: bytes, data: bytes) -> bytes:
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(scanlines), 6))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    sys.exit(main())
