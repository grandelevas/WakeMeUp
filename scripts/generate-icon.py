#!/usr/bin/env python3
"""Draw Wakito app icons as opaque 1024 PNGs (no third-party art).

Primary stays the dark clock. Dark, Minimal, and Color are alternate icons.
Small previews are written for Settings.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

SIZE = 1024
ROOT = Path(__file__).resolve().parents[1] / "WakeMeUp" / "Assets.xcassets"


def write_png(path: Path, size: int, pixel) -> None:
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            red, green, blue = pixel(x, y, size)
            rows += bytes((red, green, blue))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    print(f"wrote {path} ({path.stat().st_size} bytes)")


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def clock(x: int, y: int, size: int, background, disc, face, mark, hand) -> tuple[int, int, int]:
    import math

    cx = cy = (size - 1) / 2
    scale = size / 1024
    dx = x - cx
    dy = y - cy
    dist = (dx * dx + dy * dy) ** 0.5 / scale
    if dist < 28:
        return hand
    if dist < 110 and abs(dy + dx * 0.15) < 14 and dx > -8 * scale:
        return hand
    if dist < 150 and abs(dx) < 16 and dy < 8 * scale:
        return hand
    if 168 < dist < 196:
        angle = math.atan2(dy, dx)
        spoke = abs((angle % (math.pi / 6)) - (math.pi / 12))
        if spoke < 0.045:
            return mark
    if dist < 210:
        return face
    if dist < 300:
        shade = 1 - dist / 420
        return tuple(int(disc[i] * shade + background[i] * (1 - shade)) for i in range(3))
    return background


STYLES = {
    "primary": dict(
        background=(18, 22, 34),
        disc=(255, 149, 10),
        face=(255, 246, 230),
        mark=(40, 44, 58),
        hand=(255, 122, 0),
    ),
    "dark": dict(
        background=(8, 8, 10),
        disc=(120, 62, 8),
        face=(28, 28, 32),
        mark=(210, 210, 216),
        hand=(255, 149, 0),
    ),
    "minimal": dict(
        background=(245, 244, 240),
        disc=(230, 228, 222),
        face=(255, 255, 255),
        mark=(28, 28, 30),
        hand=(255, 122, 0),
    ),
    "color": dict(
        background=(255, 122, 0),
        disc=(255, 160, 40),
        face=(255, 248, 236),
        mark=(80, 32, 0),
        hand=(40, 18, 0),
    ),
}

ICONS = {
    "primary": ROOT / "AppIcon.appiconset" / "AppIcon.png",
    "dark": ROOT / "Dark.appiconset" / "Dark.png",
    "minimal": ROOT / "Minimal.appiconset" / "Minimal.png",
    "color": ROOT / "Color.appiconset" / "Color.png",
}

PREVIEWS = {
    "primary": ROOT / "IconPreviewPrimary.imageset" / "preview.png",
    "dark": ROOT / "IconPreviewDark.imageset" / "preview.png",
    "minimal": ROOT / "IconPreviewMinimal.imageset" / "preview.png",
    "color": ROOT / "IconPreviewColor.imageset" / "preview.png",
}


def painter(style: str):
    colors = STYLES[style]

    def pixel(x: int, y: int, size: int) -> tuple[int, int, int]:
        return clock(x, y, size, **colors)

    return pixel


def main() -> None:
    for name, path in ICONS.items():
        write_png(path, SIZE, painter(name))
    for name, path in PREVIEWS.items():
        write_png(path, 128, painter(name))


if __name__ == "__main__":
    main()
