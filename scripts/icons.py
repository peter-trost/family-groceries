#!/usr/bin/env python3
"""Draws the app icon and writes every platform size. Needs Pillow.

Usage: python3 scripts/icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

APP = Path(__file__).resolve().parent.parent / "app"
GREEN = (0x2E, 0x7D, 0x32)
SUPERSAMPLE = 4


def basket(size: int) -> Image.Image:
    """A white basket on transparent, filling a size x size box."""
    s = size * SUPERSAMPLE
    mask = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(mask)

    def box(x0, y0, x1, y1):
        return [round(x0 * s), round(y0 * s), round(x1 * s), round(y1 * s)]

    stroke = round(0.075 * s)
    d.arc(box(0.24, 0.06, 0.76, 0.58), 180, 360, fill=255, width=stroke)
    d.polygon(
        [(0.10 * s, 0.50 * s), (0.90 * s, 0.50 * s), (0.79 * s, 0.94 * s), (0.21 * s, 0.94 * s)],
        fill=255,
    )
    d.rounded_rectangle(box(0.02, 0.32, 0.98, 0.50), radius=0.05 * s, fill=255)
    for x in (0.32, 0.47, 0.62):
        d.rounded_rectangle(box(x, 0.58, x + 0.06, 0.86), radius=0.03 * s, fill=0)

    glyph = Image.new("RGBA", (s, s), (255, 255, 255, 0))
    glyph.putalpha(mask)
    return glyph.resize((size, size), Image.LANCZOS)


def icon(size: int, glyph_scale: float, background=GREEN, radius: float = 0.0) -> Image.Image:
    """The glyph centred on a square (rounded when radius > 0) background."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if background is not None:
        s = size * SUPERSAMPLE
        bg = Image.new("L", (s, s), 0)
        ImageDraw.Draw(bg).rounded_rectangle([0, 0, s - 1, s - 1], radius=radius * s, fill=255)
        img.paste(Image.new("RGBA", (size, size), background + (255,)), mask=bg.resize((size, size), Image.LANCZOS))
    g = round(size * glyph_scale)
    offset = (size - g) // 2
    glyph = basket(g)
    img.alpha_composite(glyph, (offset, offset))
    return img


def save(img: Image.Image, path: Path, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    (img.convert("RGB") if opaque else img).save(path, optimize=True)


def main() -> None:
    # The source image and iOS: full-bleed and opaque, iOS masks the corners.
    save(icon(1024, 0.62), APP / "assets/icon/icon.png", opaque=True)
    ios = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for points, scales in {20: (1, 2, 3), 29: (1, 2, 3), 40: (1, 2, 3), 60: (2, 3), 76: (1, 2), 83.5: (2,), 1024: (1,)}.items():
        for scale in scales:
            name = f"Icon-App-{points:g}x{points:g}@{scale}x.png"
            save(icon(round(points * scale), 0.62), ios / name, opaque=True)

    # Android: a legacy rounded-square icon, plus an adaptive icon (API 26+)
    # whose 108dp foreground keeps the glyph inside the 66dp safe zone.
    res = APP / "android/app/src/main/res"
    for density, factor in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        save(icon(round(48 * factor), 0.6, radius=0.22), res / f"mipmap-{density}/ic_launcher.png")
        save(icon(round(108 * factor), 0.42, background=None), res / f"mipmap-{density}/ic_launcher_foreground.png")

    # Web: plain icons full-bleed, maskable ones inside the 80% safe circle.
    web = APP / "web"
    for size in (192, 512):
        save(icon(size, 0.62), web / f"icons/Icon-{size}.png", opaque=True)
        save(icon(size, 0.5), web / f"icons/Icon-maskable-{size}.png", opaque=True)
    save(icon(32, 0.7, radius=0.22), web / "favicon.png")


if __name__ == "__main__":
    main()
