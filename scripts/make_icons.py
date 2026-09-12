#!/usr/bin/env python3
"""Generate PWA icons and a macOS .icns file for Writing Assistant.

Run with:  uv run --with pillow python scripts/make_icons.py
"""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ACCENT = (79, 70, 229)   # #4f46e5
WHITE  = (255, 255, 255)
SIZES  = [192, 512, 1024]


def make_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = size // 5
    draw.rounded_rectangle([(0, 0), (size - 1, size - 1)], radius=radius, fill=ACCENT)
    font_size = int(size * 0.6)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except OSError:
        font = ImageFont.load_default(font_size)
    letter = "W"
    bbox = draw.textbbox((0, 0), letter, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (size - w) / 2 - bbox[0]
    y = (size - h) / 2 - bbox[1]
    draw.text((x, y), letter, fill=WHITE, font=font)
    return img


def build_icns(pngs: dict[int, Path], out: Path) -> None:
    icns_map = {
        16: "icon_16x16.png",
        32: "icon_16x16@2x.png",
        64: "icon_32x32@2x.png",
        128: "icon_128x128.png",
        256: "icon_128x128@2x.png",
        512: "icon_512x512.png",
        1024: "icon_512x512@2x.png",
    }
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "icon.iconset"
        iconset.mkdir()
        base = pngs[1024]
        for px, name in icns_map.items():
            img = Image.open(base).resize((px, px), Image.LANCZOS)
            img.save(iconset / name)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(out)],
            check=True,
        )


def main() -> None:
    icons_dir = Path("static/icons")
    icons_dir.mkdir(exist_ok=True)
    pngs: dict[int, Path] = {}
    for size in SIZES:
        path = icons_dir / f"icon-{size}.png"
        make_icon(size).save(path)
        print(f"  wrote {path}")
        pngs[size] = path
    icns = icons_dir / "icon.icns"
    build_icns(pngs, icns)
    print(f"  wrote {icns}")


if __name__ == "__main__":
    main()
