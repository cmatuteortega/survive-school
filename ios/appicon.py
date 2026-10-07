#!/usr/bin/env python3
"""Bakes the iOS app icon out of the cool S.

The same S as the Android launcher icon (android/icon.py, whose reader this
borrows), in ink on white, scaled by a whole number for the same reason: a
9x17 drawing resampled to fit a box comes out as a grey smear.

iOS wants one 1024x1024 picture and makes every other size itself, so this
writes that one into an app icon set and replaces the set's Contents.json with
one naming it as a single "universal" icon. It is RGB with no alpha channel on
purpose: App Store Connect rejects an icon that has one, and iOS rounds the
corners itself.

Standard library only, so the workflow needs nothing installed.

    python3 ios/appicon.py <love>/platform/xcode/Images.xcassets/<name>.appiconset
"""

import json
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "android"))
from icon import INK, WHITE, read_cools  # noqa: E402

SIZE = 1024
# 17 rows x 42 = 714px: the S stands about 70% of the square, like the Android
# legacy icon, and well clear of the corner rounding.
SCALE = 42


def png_rgb(path, size, pixel):
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter: none
        for x in range(size):
            raw.extend(pixel(x, y))

    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = sys.argv[1]
    rows = read_cools()

    w, h = len(rows[0]) * SCALE, len(rows) * SCALE
    if max(w, h) > SIZE * 3 // 4:
        sys.exit("appicon.py: Sprites.COOLS grew past the safe area; lower SCALE")
    ox, oy = (SIZE - w) // 2, (SIZE - h) // 2

    def pixel(x, y):
        gx, gy = x - ox, y - oy
        if 0 <= gx < w and 0 <= gy < h and rows[gy // SCALE][gx // SCALE] != ".":
            return INK
        return WHITE

    os.makedirs(folder, exist_ok=True)
    for name in os.listdir(folder):
        if name.endswith(".png"):
            os.remove(os.path.join(folder, name))
    png_rgb(os.path.join(folder, "icon-1024.png"), SIZE, pixel)
    with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({
            "images": [{
                "filename": "icon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }],
            "info": {"author": "xcode", "version": 1},
        }, f, indent=2)


if __name__ == "__main__":
    main()
