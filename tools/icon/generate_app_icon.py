#!/usr/bin/env python3
"""NikuCue App Store icon: an original stylized cat paw print (docs/14_APP_ICON.md).

Editable source = this script (geometry below) + the SVG it writes. Outputs:
  NikuCue/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png   1024×1024, sRGB, opaque, no rounded corners
  artifacts/icon/app_icon_source.svg                                       editable vector of the same geometry
  artifacts/icon/preview_sizes.png                                         180/120/60/40 px previews with iOS-style rounded mask
  artifacts/icon/preview_home_light.png / preview_home_dark.png            the icon on light/dark backgrounds at 60 px

One large pad + four toe pads, flat shapes, no outline, no text, no camera cues. Requires Pillow (stdlib otherwise).
Run: python3 tools/icon/generate_app_icon.py
Not art-approved until the owner reviews it (R14).
"""
from __future__ import annotations
import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ICONSET = ROOT / "NikuCue" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
OUT = ROOT / "artifacts" / "icon"

BG = "#FFF8EF"       # ivory (docs/14 §2)
PAD = "#C98E62"      # caramel
INNER = "#DC9292"    # blush, used sparingly on the big pad

# Geometry in a 1024 canvas (y down). Big pad: a rounded, slightly heart-shaped blob; toes: ellipses on an arc.
BIG_PAD = {"cx": 512, "cy": 662, "rx": 205, "ry": 178}
TOES = [  # (cx, cy, rx, ry, rotation_deg) — four clearly separated toes on an arc above the pad
    (268, 452, 74, 92, -28),
    (412, 318, 76, 96, -10),
    (612, 318, 76, 96, 10),
    (756, 452, 74, 92, 28),
]
SUPERSAMPLE = 4


def blob_points(cx: float, cy: float, rx: float, ry: float, n: int = 240) -> list[tuple[float, float]]:
    """Big pad: an ellipse whose top edge dips slightly in the middle (two gentle lobes) and whose bottom is rounder."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = math.cos(t)
        y = math.sin(t)
        # dip the top (y < 0) by a cosine bump centred on x = 0, widen the lower half a little
        dip = 0.16 * math.exp(-(x * 3.2) ** 2) if y < 0 else 0
        widen = 1.0 + (0.08 * y if y > 0 else 0)
        pts.append((cx + rx * x * widen, cy + ry * (y + dip)))
    return pts


def ellipse_points(cx, cy, rx, ry, rot_deg, n=160):
    r = math.radians(rot_deg)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + x * math.cos(r) - y * math.sin(r), cy + x * math.sin(r) + y * math.cos(r)))
    return pts


def render(size: int) -> Image.Image:
    s = SUPERSAMPLE
    big = size * s
    scale = big / 1024
    img = Image.new("RGB", (big, big), BG)
    d = ImageDraw.Draw(img)
    d.polygon([(x * scale, y * scale) for x, y in blob_points(**BIG_PAD)], fill=PAD)
    for toe in TOES:
        d.polygon([(x * scale, y * scale) for x, y in ellipse_points(*toe)], fill=PAD)
    # a soft blush highlight inside the big pad (small, flat)
    hl = ellipse_points(BIG_PAD["cx"], BIG_PAD["cy"] + 40, 110, 70, 0)
    overlay = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(overlay).polygon([(x * scale, y * scale) for x, y in hl], fill=(220, 146, 146, 70))
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
    return img.resize((size, size), Image.LANCZOS)


def svg() -> str:
    def path(pts):
        return "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
    parts = [f'<rect width="1024" height="1024" fill="{BG}"/>', f'<path d="{path(blob_points(**BIG_PAD))}" fill="{PAD}"/>']
    for toe in TOES:
        parts.append(f'<path d="{path(ellipse_points(*toe))}" fill="{PAD}"/>')
    parts.append(f'<path d="{path(ellipse_points(BIG_PAD["cx"], BIG_PAD["cy"] + 40, 110, 70, 0))}" fill="{INNER}" fill-opacity="0.27"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n  '
            + "\n  ".join(parts) + "\n</svg>\n")


def rounded_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * 0.2237), fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    icon = render(1024)
    icon.save(ICONSET / "AppIcon-1024.png", format="PNG", optimize=True)
    (OUT / "app_icon_source.svg").write_text(svg(), encoding="utf-8")

    sizes = [180, 120, 60, 40]
    gap = 24
    sheet = Image.new("RGB", (sum(sizes) + gap * (len(sizes) + 1), 180 + gap * 2), "#EDE6DC")
    x = gap
    for sz in sizes:
        small = icon.resize((sz, sz), Image.LANCZOS)
        sheet.paste(small, (x, gap + (180 - sz) // 2), rounded_mask(sz))
        x += sz + gap
    sheet.save(OUT / "preview_sizes.png")
    for name, bg in (("light", "#F2F2F7"), ("dark", "#1C1C1E")):
        home = Image.new("RGB", (240, 120), bg)
        small = icon.resize((60, 60), Image.LANCZOS)
        home.paste(small, (90, 30), rounded_mask(60))
        home.save(OUT / f"preview_home_{name}.png")
    print("wrote", ICONSET / "AppIcon-1024.png", "and previews in", OUT)


if __name__ == "__main__":
    main()
