#!/usr/bin/env python3
"""Draw the WakeMeUp app icon as a single 1024 PNG (no third-party art)."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

SIZE = 1024
OUT = (
    Path(__file__).resolve().parents[1]
    / "WakeMeUp"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "AppIcon.png"
)


def pixel(x: int, y: int) -> tuple[int, int, int, int]:
    # Dark navy background.
    red, green, blue = 18, 22, 34
    cx = cy = (SIZE - 1) / 2
    dx = x - cx
    dy = y - cy
    dist = (dx * dx + dy * dy) ** 0.5

    # Soft orange disc.
    if dist < 300:
        shade = 1 - dist / 420
        red = int(255 * shade + 180 * (1 - shade))
        green = int(149 * shade + 70 * (1 - shade))
        blue = int(10 * shade)
    # Inner clock face.
    if dist < 210:
        red, green, blue = 255, 246, 230
    # Hour marks.
    if 168 < dist < 196:
        angle = math_atan2(dy, dx)
        spoke = abs((angle % (math_pi() / 6)) - (math_pi() / 12))
        if spoke < 0.045:
            red, green, blue = 40, 44, 58
    # Hands, both orange, pivoted at the center.
    if dist < 150 and abs(dx) < 16 and dy < 8:
        red, green, blue = 255, 122, 0
    if dist < 110 and abs(dy + dx * 0.15) < 14 and dx > -8:
        red, green, blue = 255, 90, 0
    # Hub.
    if dist < 28:
        red, green, blue = 255, 122, 0
    return red, green, blue, 255


def math_pi() -> float:
    return 3.141592653589793


def math_atan2(y: float, x: float) -> float:
    # Local atan2 so the script stays dependency-free.
    import math

    return math.atan2(y, x)


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def main() -> None:
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            red, green, blue, alpha = pixel(x, y)
            rows += bytes((red, green, blue, alpha))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
