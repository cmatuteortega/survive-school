#!/usr/bin/env python3
"""Bakes the desktop icons out of the cool S.

The desktop half of android/icon.py, and built on it: the same S read straight
out of `Sprites.COOLS`, the same ink on white, the same whole-number scales (a
9x17 drawing resampled to fit a box comes out as a grey smear, so every size
here picks the largest whole scale that fits and centres it).

Three files are written into the given directory:

- icon.ico, for the Windows .exe (rcedit puts it in before game.love is fused
  on). No 16px entry: the S is 17 rows tall and has no whole scale below 1, so
  Windows shrinks the 32px one for the smallest views instead.
- icon.icns, the macOS app icon: a white rounded square inside the transparent
  margin every Mac icon keeps, so it sits on the dock at the size of its
  neighbours.
- icon.png, 512px square, the Linux AppImage's icon.

PNG-in-ICO and PNG-in-ICNS are both standard, so this is standard library only.

    python3 desktop/icon.py <out-dir>
"""

import io
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "android"))
from icon import INK, WHITE, png, read_cools  # noqa: E402

# Share of the square the S stands in, as on the Android legacy icon.
FILL = 0.7


def fitted(rows, size):
    return max(1, int(size * FILL) // len(rows))


def square(rows, size):
    """Ink S on a white square that fills the icon."""
    scale = fitted(rows, size)
    w, h = len(rows[0]) * scale, len(rows) * scale
    ox, oy = (size - w) // 2, (size - h) // 2

    def pixel(x, y):
        gx, gy = x - ox, y - oy
        if 0 <= gx < w and 0 <= gy < h and rows[gy // scale][gx // scale] != ".":
            return INK + (255,)
        return WHITE + (255,)

    return pixel


def mac(rows, size):
    """Apple's grid: an 824/1024 rounded square, radius 185/1024, centred."""
    body = size * 824 // 1024
    radius = size * 185 // 1024
    lo = (size - body) // 2
    hi = lo + body
    scale = max(1, int(body * FILL) // len(rows))
    w, h = len(rows[0]) * scale, len(rows) * scale
    ox, oy = (size - w) // 2, (size - h) // 2

    def inside(x, y):
        if not (lo <= x < hi and lo <= y < hi):
            return False
        cx = min(max(x, lo + radius), hi - 1 - radius)
        cy = min(max(y, lo + radius), hi - 1 - radius)
        return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2

    def pixel(x, y):
        if not inside(x, y):
            return (0, 0, 0, 0)
        gx, gy = x - ox, y - oy
        if 0 <= gx < w and 0 <= gy < h and rows[gy // scale][gx // scale] != ".":
            return INK + (255,)
        return WHITE + (255,)

    return pixel


def png_bytes(size, pixels):
    # android/icon.py's png() writes to a path; go through a scratch file
    # rather than fork it.
    path = os.path.join(OUT, ".scratch.png")
    png(path, size, pixels)
    with open(path, "rb") as f:
        data = f.read()
    os.remove(path)
    return data


def ico(path, images):
    """images: [(size, png bytes)]. Width/height 0 means 256."""
    head = struct.pack("<HHH", 0, 1, len(images))
    offset = len(head) + 16 * len(images)
    entries, blobs = b"", b""
    for size, data in images:
        side = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", side, side, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    with open(path, "wb") as f:
        f.write(head + entries + blobs)


def icns(path, images):
    """images: [(OSType, png bytes)]."""
    body = io.BytesIO()
    for kind, data in images:
        body.write(kind + struct.pack(">I", 8 + len(data)) + data)
    data = body.getvalue()
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", 8 + len(data)) + data)


def main():
    global OUT
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    OUT = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    rows = read_cools()

    ico(os.path.join(OUT, "icon.ico"),
        [(s, png_bytes(s, square(rows, s))) for s in (32, 48, 64, 128, 256)])

    # ic07..ic10 are the 128..1024 PNG slots; ic11..ic14 the same at @2x of
    # 16..512, which is what Retina docks and Finder ask for.
    icns(os.path.join(OUT, "icon.icns"), [
        (b"ic07", png_bytes(128, mac(rows, 128))),
        (b"ic08", png_bytes(256, mac(rows, 256))),
        (b"ic09", png_bytes(512, mac(rows, 512))),
        (b"ic10", png_bytes(1024, mac(rows, 1024))),
        (b"ic12", png_bytes(64, mac(rows, 64))),
        (b"ic13", png_bytes(256, mac(rows, 256))),
        (b"ic14", png_bytes(512, mac(rows, 512))),
    ])

    png(os.path.join(OUT, "icon.png"), 512, square(rows, 512))


if __name__ == "__main__":
    main()
