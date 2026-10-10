#!/usr/bin/env python3
"""Editable source for Mali's prototype vector art (second iteration: rounder chibi cat).

Generates NikuCue/Resources/Character/mali_paths.json from the rig contract in
NikuCue/Resources/Character/character_spec.json. Every part is described in *design units*
(1024 canvas, origin bottom-left, y up — the SpriteKit convention) relative to the part's own
node origin, which sits where the rig contract says the part pivots (ear base, tail base,
paw shoulder). Rotating the node therefore rotates the art around the right point.

Output: plain path data (M/L/C/Q/Z, absolute coordinates) plus fill/stroke layers, consumed
unchanged by Character/VectorArtProvider.swift (CGPath → SKTexture) and tools/rig-preview.

Run:  python3 tools/character/generate_mali_paths.py
Standard library only. Prototype art — not approved production art (docs/04 §6, R02).
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "NikuCue" / "Resources" / "Character" / "character_spec.json"
OUT = ROOT / "NikuCue" / "Resources" / "Character" / "mali_paths.json"

KAPPA = 0.5522847498


def f(v: float) -> str:
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


def ellipse(cx: float, cy: float, rx: float, ry: float) -> str:
    kx, ky = rx * KAPPA, ry * KAPPA
    return " ".join([
        f"M {f(cx + rx)} {f(cy)}",
        f"C {f(cx + rx)} {f(cy + ky)} {f(cx + kx)} {f(cy + ry)} {f(cx)} {f(cy + ry)}",
        f"C {f(cx - kx)} {f(cy + ry)} {f(cx - rx)} {f(cy + ky)} {f(cx - rx)} {f(cy)}",
        f"C {f(cx - rx)} {f(cy - ky)} {f(cx - kx)} {f(cy - ry)} {f(cx)} {f(cy - ry)}",
        f"C {f(cx + kx)} {f(cy - ry)} {f(cx + rx)} {f(cy - ky)} {f(cx + rx)} {f(cy)}",
        "Z",
    ])


def smooth_closed(points, tension=0.5) -> str:
    n = len(points)
    parts = [f"M {f(points[0][0])} {f(points[0][1])}"]
    for i in range(n):
        p0, p1, p2, p3 = points[(i - 1) % n], points[i], points[(i + 1) % n], points[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) * tension / 3, p1[1] + (p2[1] - p0[1]) * tension / 3)
        c2 = (p2[0] - (p3[0] - p1[0]) * tension / 3, p2[1] - (p3[1] - p1[1]) * tension / 3)
        parts.append(f"C {f(c1[0])} {f(c1[1])} {f(c2[0])} {f(c2[1])} {f(p2[0])} {f(p2[1])}")
    parts.append("Z")
    return " ".join(parts)


def smooth_open(points, tension=0.5) -> str:
    n = len(points)
    parts = [f"M {f(points[0][0])} {f(points[0][1])}"]
    for i in range(n - 1):
        p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, n - 1)]
        c1 = (p1[0] + (p2[0] - p0[0]) * tension / 3, p1[1] + (p2[1] - p0[1]) * tension / 3)
        c2 = (p2[0] - (p3[0] - p1[0]) * tension / 3, p2[1] - (p3[1] - p1[1]) * tension / 3)
        parts.append(f"C {f(c1[0])} {f(c1[1])} {f(c2[0])} {f(c2[1])} {f(p2[0])} {f(p2[1])}")
    return " ".join(parts)


def rounded_polygon(points, radius: float) -> str:
    n = len(points)
    parts = []
    for i in range(n):
        p_prev, p, p_next = points[(i - 1) % n], points[i], points[(i + 1) % n]
        d1 = (p[0] - p_prev[0], p[1] - p_prev[1])
        d2 = (p_next[0] - p[0], p_next[1] - p[1])
        l1, l2 = math.hypot(*d1), math.hypot(*d2)
        r = min(radius, l1 / 2, l2 / 2)
        a = (p[0] - d1[0] / l1 * r, p[1] - d1[1] / l1 * r)
        b = (p[0] + d2[0] / l2 * r, p[1] + d2[1] / l2 * r)
        parts.append(("M" if i == 0 else "L") + f" {f(a[0])} {f(a[1])}")
        parts.append(f"Q {f(p[0])} {f(p[1])} {f(b[0])} {f(b[1])}")
    parts.append("Z")
    return " ".join(parts)


def mirror_x(points):
    return [(-x, y) for (x, y) in points]


def mirror_path(d: str) -> str:
    toks = d.replace(",", " ").split()
    out, i = [], 0
    while i < len(toks):
        t = toks[i]
        if t in ("M", "L", "C", "Q", "Z"):
            out.append(t); i += 1; continue
        out.append(f(-float(t))); out.append(toks[i + 1]); i += 2
    return " ".join(out)


def mirror_layers(layers):
    return [dict(l, path=mirror_path(l["path"])) for l in layers]


def layer(path, fill=None, stroke=None, width=None, opacity=None, cap=None) -> dict:
    d: dict = {"path": path}
    if fill:
        d["fill"] = fill
    if stroke:
        d["stroke"] = stroke
        d["width"] = width or 4
        d["cap"] = cap or "round"
    if opacity is not None:
        d["opacity"] = opacity
    return d


def bounds_of(layers) -> list:
    xs, ys = [], []
    for ly in layers:
        pad = (ly.get("width", 0) / 2) if "stroke" in ly else 0
        toks = ly["path"].replace(",", " ").split()
        i = 0
        while i < len(toks):
            t = toks[i]
            if t in ("M", "L", "C", "Q", "Z"):
                i += 1; continue
            xs += [float(t) - pad, float(t) + pad]
            ys += [float(toks[i + 1]) - pad, float(toks[i + 1]) + pad]
            i += 2
    m = 2.0
    return [math.floor(min(xs) - m), math.floor(min(ys) - m), math.ceil(max(xs) + m), math.ceil(max(ys) + m)]


def part(layers) -> dict:
    return {"bounds": bounds_of(layers), "layers": layers}


OUTLINE_W = 6


def build() -> dict:
    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    size = {n["id"]: n.get("size") for n in spec["nodes"]}
    parts: dict = {}

    # ---- shadow ------------------------------------------------------------
    sw, sh = size["shadow"]
    parts["shadow"] = part([layer(ellipse(0, 0, sw / 2, sh / 2), fill="shadow", opacity=0.7)])

    # ---- body: short, wide "mochi" — narrower shoulders, round hips ---------
    bw, bh = size["body"]            # 400 x 340, centred on bodyPivot
    hw, hh = bw / 2, bh / 2
    body_pts = [
        (0, hh), (hw * 0.60, hh * 0.88), (hw * 0.92, hh * 0.38), (hw * 1.00, -hh * 0.28),
        (hw * 0.86, -hh * 0.80), (hw * 0.46, -hh * 1.00), (-hw * 0.46, -hh * 1.00),
        (-hw * 0.86, -hh * 0.80), (-hw * 1.00, -hh * 0.28), (-hw * 0.92, hh * 0.38), (-hw * 0.60, hh * 0.88),
    ]
    body_path = smooth_closed(body_pts, 0.55)
    chest = ellipse(0, -hh * 0.30, hw * 0.50, hh * 0.46)
    parts["body"] = part([
        layer(body_path, fill="cream"),
        layer(chest, fill="white", opacity=0.5),
        layer(body_path, stroke="outline", width=OUTLINE_W),
    ])

    # ---- hind paws ----------------------------------------------------------
    pw, ph = size["hindPawL"]        # 110 x 60
    hind = ellipse(0, 0, pw / 2, ph / 2)
    hind_layers = [
        layer(hind, fill="cream"),
        layer(hind, stroke="outline", width=OUTLINE_W - 1),
        layer(f"M {f(-pw*0.14)} {f(-ph*0.48)} L {f(-pw*0.12)} {f(-ph*0.12)}", stroke="outline", width=4),
        layer(f"M {f(pw*0.14)} {f(-ph*0.48)} L {f(pw*0.12)} {f(-ph*0.12)}", stroke="outline", width=4),
    ]
    parts["hindPawL"] = part(hind_layers)
    parts["hindPawR"] = part(hind_layers)

    # ---- fore paws: stubby capsule from the shoulder (origin) to a round paw --
    fw, fh = size["forePawL"]        # 96 x 150, anchor 0.5/0.9 → origin near the top
    top = fh * 0.10
    bottom = -fh * 0.90
    rx = fw / 2
    leg = (
        f"M {f(-rx)} {f(top - rx * 0.6)} "
        f"C {f(-rx)} {f(top)} {f(-rx*0.5)} {f(top + 6)} 0 {f(top + 6)} "
        f"C {f(rx*0.5)} {f(top + 6)} {f(rx)} {f(top)} {f(rx)} {f(top - rx * 0.6)} "
        f"L {f(rx*1.06)} {f(bottom + rx)} "
        f"C {f(rx*1.06)} {f(bottom + rx*0.15)} {f(rx*0.58)} {f(bottom)} 0 {f(bottom)} "
        f"C {f(-rx*0.58)} {f(bottom)} {f(-rx*1.06)} {f(bottom + rx*0.15)} {f(-rx*1.06)} {f(bottom + rx)} Z"
    )
    toe0, toe1 = bottom + 3, bottom + 20
    fore_layers = [
        layer(leg, fill="cream"),
        layer(leg, stroke="outline", width=OUTLINE_W),
        layer(f"M {f(-rx*0.30)} {f(toe0)} L {f(-rx*0.26)} {f(toe1)}", stroke="outline", width=4),
        layer(f"M {f(rx*0.30)} {f(toe0)} L {f(rx*0.26)} {f(toe1)}", stroke="outline", width=4),
    ]
    parts["forePawL"] = part(fore_layers)
    parts["forePawR"] = part(fore_layers)

    # ---- tail: thick, rising beside the body, tip curling in ---------------
    base_w = 66
    centre = [(0, 0), (48, 44), (96, 108), (108, 178), (76, 230)]
    tail_line = smooth_open(centre, 0.6)
    tip_line = smooth_open(centre[2:], 0.6)
    parts["tail"] = part([
        layer(tail_line, stroke="outline", width=base_w + OUTLINE_W * 2),
        layer(tail_line, stroke="cream", width=base_w),
        layer(tip_line, stroke="caramel", width=base_w),
    ])

    # ---- head: big, wide, soft chin, chubby cheeks; whiskers on the head ----
    hwid, hhgt = size["head"]        # 540 x 430, centred on the head node
    hx, hy = hwid / 2, hhgt / 2
    head_pts = [
        (0, hy * 1.00), (hx * 0.56, hy * 0.93), (hx * 0.90, hy * 0.50), (hx * 1.00, -hy * 0.10),
        (hx * 0.84, -hy * 0.70), (hx * 0.44, -hy * 0.97), (0, -hy * 1.00), (-hx * 0.44, -hy * 0.97),
        (-hx * 0.84, -hy * 0.70), (-hx * 1.00, -hy * 0.10), (-hx * 0.90, hy * 0.50), (-hx * 0.56, hy * 0.93),
    ]
    head_path = smooth_closed(head_pts, 0.55)
    wx0, wx1 = hx * 0.62, hx * 0.98
    whiskers = []
    for (y0, y1) in ((-hy * 0.30, -hy * 0.24), (-hy * 0.44, -hy * 0.46)):
        whiskers.append(layer(f"M {f(-wx0)} {f(y0)} L {f(-wx1)} {f(y1)}", stroke="ink", width=3, opacity=0.28))
        whiskers.append(layer(f"M {f(wx0)} {f(y0)} L {f(wx1)} {f(y1)}", stroke="ink", width=3, opacity=0.28))
    parts["head"] = part([
        layer(head_path, fill="cream"),
        layer(head_path, stroke="outline", width=OUTLINE_W),
        *whiskers,
    ])

    # ---- ears: short rounded triangles, origin at the base centre -----------
    ew, eh = size["earL"]            # 150 x 150
    base_y = -eh * 0.12
    tip_y = eh * 0.88
    earL_outer = [(-ew / 2, base_y + 4), (ew / 2, base_y - 4), (-ew * 0.16, tip_y)]
    earL_inner = [(-ew * 0.28, base_y + 34), (ew * 0.26, base_y + 28), (-ew * 0.12, tip_y - 42)]
    earL_layers = [
        layer(rounded_polygon(earL_outer, 34), fill="caramel"),
        layer(rounded_polygon(earL_outer, 34), stroke="outline", width=OUTLINE_W),
        layer(rounded_polygon(earL_inner, 20), fill="blush", opacity=0.8),
    ]
    parts["earL"] = part(earL_layers)
    parts["earR"] = part([
        layer(rounded_polygon(mirror_x(earL_outer), 34), fill="caramel"),
        layer(rounded_polygon(mirror_x(earL_outer), 34), stroke="outline", width=OUTLINE_W),
        layer(rounded_polygon(mirror_x(earL_inner), 20), fill="blush", opacity=0.8),
    ])

    # ---- muzzle: two soft white bumps ----------------------------------------
    mw, mh = size["muzzle"]          # 150 x 88
    parts["muzzle"] = part([
        layer(ellipse(-mw * 0.22, 0, mw * 0.30, mh / 2), fill="white", opacity=0.75),
        layer(ellipse(mw * 0.22, 0, mw * 0.30, mh / 2), fill="white", opacity=0.75),
    ])

    # ---- cheeks ---------------------------------------------------------------
    cw, ch = size["cheekL"]          # 84 x 36
    cheek = [layer(ellipse(0, 0, cw / 2, ch / 2), fill="blush", opacity=0.9)]
    parts["cheekL"] = part(cheek)
    parts["cheekR"] = part(cheek)

    # ---- nose -----------------------------------------------------------------
    nw, nh = size["nose"]            # 26 x 18
    parts["nose"] = part([layer(rounded_polygon([(-nw / 2, nh * 0.45), (nw / 2, nh * 0.45), (0, -nh * 0.55)], 6), fill="blush")])

    # ---- eyes: big, low, two highlights ---------------------------------------
    ex, ey = size["eyeL"]            # 64 x 80
    rx_e, ry_e = ex / 2, ey / 2

    def open_eye(sx: float, sy: float, hl: float):
        rxx, ryy = rx_e * sx, ry_e * sy
        return [
            layer(ellipse(0, 0, rxx, ryy), fill="ink"),
            layer(ellipse(-rxx * 0.34, ryy * 0.42, rxx * hl, rxx * hl), fill="white"),
            layer(ellipse(rxx * 0.36, -ryy * 0.40, rxx * hl * 0.45, rxx * hl * 0.45), fill="white", opacity=0.9),
        ]

    closed_happy = [layer(f"M {f(-rx_e*0.98)} {f(-4)} Q 0 {f(ry_e*0.95)} {f(rx_e*0.98)} {f(-4)}", stroke="ink", width=9)]
    # sleepy: relaxed closed eye — a soft downward arc (peaceful, never a glare) with a tiny lash
    sleepy = [
        layer(f"M {f(-rx_e*0.95)} 6 Q 0 {f(-ry_e*0.42)} {f(rx_e*0.95)} 6", stroke="ink", width=7),
        layer(f"M {f(-rx_e*0.95)} 6 L {f(-rx_e*1.12)} 14", stroke="ink", width=5),
    ]
    soft_smile = [
        layer(ellipse(0, 0, rx_e, ry_e * 0.82), fill="ink"),
        layer(ellipse(-rx_e * 0.34, ry_e * 0.30, rx_e * 0.34, rx_e * 0.34), fill="white"),
        # lower lid pushed up by the smile
        layer(f"M {f(-rx_e*1.1)} {f(-ry_e*0.60)} Q 0 {f(-ry_e*0.15)} {f(rx_e*1.1)} {f(-ry_e*0.60)} L {f(rx_e*1.1)} {f(-ry_e)} L {f(-rx_e*1.1)} {f(-ry_e)} Z", fill="cream"),
    ]
    eye_variants = {
        "neutral": open_eye(1.0, 1.0, 0.44),
        "softSmile": soft_smile,
        "closedHappy": closed_happy,
        "curious": open_eye(1.12, 1.12, 0.50),
        "sleepy": sleepy,
    }
    parts["eyeL"] = {"variants": {k: part(v) for k, v in eye_variants.items()}}
    parts["eyeR"] = {"variants": {k: part(mirror_layers(v)) for k, v in eye_variants.items()}}

    # ---- mouth ------------------------------------------------------------------
    mw2, mh2 = size["mouth"]         # 60 x 26
    hw2 = mw2 / 2
    omega = f"M {f(-hw2*0.70)} 8 Q {f(-hw2*0.36)} {f(-6)} 0 4 Q {f(hw2*0.36)} {f(-6)} {f(hw2*0.70)} 8"
    mouth_variants = {
        "neutral": [layer(omega, stroke="ink", width=4.5)],
        "softSmile": [layer(f"M {f(-hw2*0.78)} 9 Q 0 {f(-9)} {f(hw2*0.78)} 9", stroke="ink", width=4.5)],
        "closedHappy": [
            layer(f"M {f(-hw2*0.80)} 8 Q 0 {f(-mh2*1.0)} {f(hw2*0.80)} 8 Z", fill="ink"),
            layer(f"M {f(-hw2*0.32)} {f(-7)} Q 0 {f(-18)} {f(hw2*0.32)} {f(-7)} Z", fill="blush"),
        ],
        "curious": [layer(ellipse(0, 0, 7, 8), fill="ink")],
        "sleepy": [layer(f"M {f(-hw2*0.46)} 5 Q {f(-hw2*0.23)} {f(-1)} 0 4 Q {f(hw2*0.23)} {f(-1)} {f(hw2*0.46)} 5", stroke="ink", width=4)],
    }
    parts["mouth"] = {"variants": {k: part(v) for k, v in mouth_variants.items()}}

    # ---- heart (milestone) ----------------------------------------------------
    heart = "M 0 -16 C -4 -8 -22 -2 -22 10 C -22 20 -12 24 0 12 C 12 24 22 20 22 10 C 22 -2 4 -8 0 -16 Z"
    parts["heart"] = part([layer(heart, fill="blush")])

    palette = dict(spec["palette"])
    palette["outline"] = "#DCC09A"

    return {
        "schemaVersion": 1,
        "characterId": spec["characterId"],
        "isProductionArt": False,
        "status": "Code-drawn prototype art generated from tools/character/generate_mali_paths.py; requires human visual approval (R02)",
        "units": "design units; origin bottom-left, y up; coordinates relative to each part's node origin (its pivot)",
        "pathSyntax": "SVG-like absolute commands: M x y | L x y | C x1 y1 x2 y2 x y | Q cx cy x y | Z",
        "palette": palette,
        "parts": parts,
    }


if __name__ == "__main__":
    data = build()
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(data['parts'])} parts)")
