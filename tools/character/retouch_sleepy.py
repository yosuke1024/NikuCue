#!/usr/bin/env python3
"""
NikuCue / Mali sleepy pose retouch ("mirror fill").

Owner report 2026-10-11: the sleepy texture showed five paws (one raised + four on the floor). This is a
deterministic, code-only retouch of the owner's PNG (no generative AI, Pillow + numpy); the original stays
in docs/assets/mali_v1 and import_wholebody_pack.py applies this before the fringe cleanup. It is a
candidate for owner art review (CLAUDE.md: a code-generated draft is never automatically art-approved).
Three strategies were generated and judged (clone fill / mirror fill / re-centred paw); mirror fill won
and then received the seam fixes listed in docs/IMPLEMENTATION_LOG.md.

Problem: mali_sleepy.png shows the cat yawning with the viewer's-left front paw
raised to its mouth, but the floor row still shows four paws.  The viewer's-left
central front paw (x ~344-480, y ~877-958) is the extra one.

What this script does (deterministic, Pillow + numpy only, no randomness):
  1. Erases the extra paw (interior, toe lines, its own outline strokes and the
     left half of the merged V-stroke between the two central paws).
  2. Fills the gap with a horizontally MIRRORED copy of the chest/belly fur that
     sits above the remaining (viewer's-right) front paw.  Mirror axis x = 502
     (x_src = 1004 - x); the copy is shifted down by 100 px so that the bottom
     of the copy lands on the floor line.  The band was chosen so that the
     mirrored centre-chest stroke falls under the opaque right paw and the
     mirrored right hind-leg contour falls under the new belly outline.
  3. Cuts the fill with a smooth belly/floor contour that continues the left
     hind paw's bottom outline and runs under the remaining front paw, draws a
     soft tan outline stroke along it (cross-section modelled on the existing
     paw outlines) and adds the soft shadow band the original has above every
     floor outline.
  4. Rebuilds the remaining front paw's left edge: the old edge was the straight
     V-crevice stroke shared with the erased paw (8 px wide, running straight up
     into the chest).  A rounded top-left corner is given to the paw: the paw
     interior next to the new edge is a mirrored copy of the paw's own
     top-right corner (axis x = 551.5) and a normal-width outline is drawn
     along the new edge, fading in at the top like the paw's right edge does.
  5. Composites: original (with the erased areas made transparent, feathered at
     the top and left seams) OVER the belly fill.  Pixels outside REGION are
     untouched; pixels inside REGION that no step touches are restored exactly.
     The alpha bounding box of the image is asserted unchanged.

Usage: python3 -I retouch_sleepy.py <input.png> <output.png>
"""
import sys
import numpy as np
from PIL import Image

# ---------------------------------------------------------------- geometry ---
# All coordinates are PNG pixel coordinates (x right, y down) of the 1024 image.
REGION = (343, 850, 512, 962)        # x0, y0, x1, y1 (exclusive): every edit lies inside
BODY_ALPHA = 252.0                    # alpha the original uses inside the body
MIRROR_SUM = 1004                     # x_src = MIRROR_SUM - x   (mirror axis x = 502)
DY = 100                              # y_src = y - DY           (copy shifted down)
TOP_FEATHER = (850.0, 876.0)          # erase mask ramps 0 -> 1 over these rows (0 exactly at the region top: no step)
LEFT_X = 344                          # hind paw's right outline occupies x 340..343 (343 = its anti-aliasing, kept)
LEFT_FEATHER_ROWS = (868.0, 894.0)    # above the hind paw the left seam is feathered
LEFT_FEATHER_W = 24.0
# New left edge of the remaining front paw, (y, x) control points.  Rows >= 938
# follow the original stroke, which starts at V_RIGHT_EDGE[y] + 1.
PAW_EDGE_PTS = [(876, 500.0), (880, 494.0), (884, 489.0), (888, 486.0), (892, 484.0),
                (896, 482.8), (900, 482.0), (906, 481.3), (914, 481.0), (924, 481.0),
                (930, 481.4), (935, 482.4), (938, 484.0), (941, 485.6), (944, 487.6),
                (948, 492.6), (952, 499.0)]
WEDGE_KEEP_X = 477.5                        # see right_lim in retouch()
WEDGE_KEEP_ROWS = (876.0, 892.0)
PAW_EDGE_STROKE_ROWS = (874.0, 890.0)     # the side stroke fades in over these rows (covers the crevice join)
PAW_EDGE_STROKE_RGB = np.array([200.0, 142.0, 100.0])   # lighter, like the paws' own side outlines
PAW_MIRROR_SUM = 1103                      # paw interior clone: x_src = 1103 - x (axis 551.5)
PAW_PATCH_ROWS = (878, 938)                # rows that get the cloned paw corner (exclusive end)
PAW_PATCH_FADE = (492.0, 499.0)            # clone blends back into the original over these x
# Rows 938..955: last x that still belongs to the gap (end of the transparent
# V-notch between the two paws); the right paw's outline starts at x+1.
V_RIGHT_EDGE = {938: 483, 939: 484, 940: 484, 941: 485, 942: 486, 943: 487,
                944: 487, 945: 488, 946: 489, 947: 490, 948: 492, 949: 493,
                950: 495, 951: 497, 952: 499, 953: 502, 954: 505, 955: 510}
# Belly / floor contour (x, y) control points, Catmull-Rom interpolated.  It
# starts on the left hind paw's bottom stroke (core rows 937-939, edge at 940).
CONTOUR_PTS = [(326, 939.8), (336, 939.9), (344, 940.0), (362, 942.5), (385, 945.8),
               (410, 948.2), (435, 949.5), (460, 949.5), (480, 948.6), (495, 947.3),
               (515, 945.2), (535, 942.8)]
STROKE_RGB = np.array([168.0, 104.0, 62.0])  # core colour of the floor outline (mean of the painted paw-bottom strokes)
CREASE_ATTENUATE = ((438, 481), (854, 893), 0.6)  # mirrored chest-crevice strokes: x range, y range, blend toward row fur mean
RNG_SEED = 7                                 # stroke-weight modulation (hand-painted look), fixed seed
TONE_MATCH_ROWS = (850, 876)                 # rows used for the per-row tone match (original fur above the erased paw)
TONE_MATCH_FADE = 24.0                       # rows over which the match fades out below
HIND_EDGE_ROWS = (882, 936)                  # fill columns 344/345 get a soft edge here
HIND_EDGE_RGB = np.array([190.0, 128.0, 85.0])
SHADE = np.array([0.95, 0.885, 0.84])        # multiplicative shadow right above the outline
SHADE_SPAN = (2.6, 20.0)                     # d-range (px above contour) of the shadow band


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def catmull_rom_curve(pts, samples_per_seg=64):
    """Dense polyline through pts (list of (u, v)); returns (u, v) arrays."""
    p = np.array(pts, dtype=np.float64)
    ext = np.vstack([p[0] - (p[1] - p[0]), p, p[-1] + (p[-1] - p[-2])])
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        t = np.linspace(0.0, 1.0, samples_per_seg, endpoint=False)[:, None]
        q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2
                   + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)
        out.append(q)
    out.append(ext[-2][None, :])
    c = np.vstack(out)
    return c[:, 0], c[:, 1]


def alpha_bbox(a):
    ys, xs = np.nonzero(a)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def retouch(src_u8):
    H, W, C = src_u8.shape
    assert (W, H, C) == (1024, 1024, 4), "input must be 1024x1024 RGBA"
    src = src_u8.astype(np.float64)
    x0, y0, x1, y1 = REGION
    reg = src[y0:y1, x0:x1].copy()                # float copy of the edit region
    rh, rw = reg.shape[:2]
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float64)
    pcx, pcy = xx + 0.5, yy + 0.5                  # pixel centres

    # ---- A. new left edge of the remaining paw (x as a function of y) ----------
    ey, ex = catmull_rom_curve(PAW_EDGE_PTS)       # (y, x) curve, y increasing
    edge_x = np.interp(pcy, ey, ex)                # for rows < 876 this clamps to 500
    # distance from each pixel centre to the edge polyline (for the side stroke)
    band = (xx >= 470) & (xx <= 510) & (yy >= 870) & (yy <= 940)
    dist = np.full((rh, rw), 99.0)
    bi = np.nonzero(band)
    px, py = pcx[bi], pcy[bi]
    dmin = np.full(px.shape, 99.0)
    for cy_, cx_ in zip(ey, ex):
        dmin = np.minimum(dmin, np.hypot(px - cx_, py - cy_))
    dist[bi] = dmin

    # ---- B. erase mask M (1 = original pixel removed) --------------------------
    top = smoothstep((yy - TOP_FEATHER[0]) / (TOP_FEATHER[1] - TOP_FEATHER[0]))
    # right boundary of the erased area: the new paw edge (rows < 938) or the
    # transparent V-notch (rows 938..955); everything below 956 is floor.
    right_lim = edge_x - 0.5                       # erase up to the edge line
    # above the paw corner keep the dark arm/chest crevice stroke (x >= 478):
    # the boundary slides from x = 477.5 (rows <= 876) to the paw edge (rows >= 892)
    wk = smoothstep((yy - WEDGE_KEEP_ROWS[0]) / (WEDGE_KEEP_ROWS[1] - WEDGE_KEEP_ROWS[0]))
    right_lim = WEDGE_KEEP_X + (right_lim - WEDGE_KEEP_X) * wk
    for r in range(rh):
        y = y0 + r
        if y in V_RIGHT_EDGE:
            right_lim[r, :] = V_RIGHT_EDGE[y] + 0.5
        elif y >= 956:
            right_lim[r, :] = x1 + 1.0
    horiz = np.clip(right_lim - pcx + 0.5, 0.0, 1.0)       # 1 px anti-aliased boundary
    # feathered left seam above the hind paw's outline (rows 872..892)
    lw = LEFT_FEATHER_W * smoothstep((LEFT_FEATHER_ROWS[1] - yy)
                                     / (LEFT_FEATHER_ROWS[1] - LEFT_FEATHER_ROWS[0]))
    left = np.where(lw > 0.0, np.clip((xx - LEFT_X + 0.5) / np.maximum(lw, 1e-6), 0.0, 1.0), 1.0)
    # column 343 is the hind paw outline's own anti-aliasing: keep it, except the erased paw's nub below the contour
    left[:, 0] = np.where(yy[:, 0] >= 937, 1.0, 0.0)
    M = top * horiz * left
    # the remaining paw's own anti-aliased silhouette (0 < alpha < 250 right of the V-notch) is never erased
    orig_a = reg[..., 3]
    for r in range(rh):
        y = y0 + r
        if 938 <= y <= 958:
            xe = V_RIGHT_EDGE.get(y, 510)
            keep = (orig_a[r] > 0) & (orig_a[r] < 250) & (xx[r] >= xe - 2)
            M[r][keep] = 0.0

    # ---- C. mirrored, down-shifted fur copy = belly fill --------------------------
    sx = (MIRROR_SUM - xx).astype(np.int64)
    sy = (yy - DY).astype(np.int64)
    fill = src[sy, sx].copy()
    fill[..., 3] = BODY_ALPHA
    # tone-match the copy to the fur it joins: per-row gain (original / copy mean
    # over x 350..475) for the rows above the old paw top, fading out below it
    cols = slice(350 - x0, 476 - x0)
    gain_rows = np.ones((rh, 3))
    for r in range(rh):
        y = y0 + r
        if y <= TONE_MATCH_ROWS[1]:
            om = reg[r, cols, :3].mean(0)
            fm = fill[r, cols, :3].mean(0)
            gain_rows[r] = np.clip(om / np.maximum(fm, 1.0), 0.90, 1.10)   # mirrored chest fur is brighter than belly fur
    k = np.ones(5) / 5.0                                     # light smoothing over rows
    for c in range(3):
        g = np.pad(gain_rows[:, c], 2, mode="edge")
        gain_rows[:, c] = np.convolve(g, k, mode="valid")
    last = gain_rows[TONE_MATCH_ROWS[1] - y0]
    for r in range(rh):
        y = y0 + r
        if y > TONE_MATCH_ROWS[1]:
            w = 1.0 - smoothstep((y - TONE_MATCH_ROWS[1]) / TONE_MATCH_FADE)
            gain_rows[r] = 1.0 + (last - 1.0) * w
    fill[..., :3] = np.clip(fill[..., :3] * gain_rows[:, None, :], 0.0, 255.0)
    # the mirrored chest-crevice strokes would add a second crease converging on the paw: fade them toward
    # the row's fur mean (smooth falloff at the band edges)
    (ax0, ax1), (ay0, ay1), amt = CREASE_ATTENUATE
    fur_cols = slice(350 - x0, 436 - x0)
    for r in range(rh):
        y = y0 + r
        if ay0 <= y < ay1:
            row_mean = fill[r, fur_cols, :3].mean(0)
            wy = smoothstep((y - ay0) / 6.0) * smoothstep((ay1 - y) / 6.0)
            for x in range(ax0, ax1):
                wx = smoothstep((x - ax0) / 6.0) * smoothstep((ax1 - x) / 6.0)
                c = x - x0
                fill[r, c, :3] += (row_mean - fill[r, c, :3]) * amt * wy * wx
    # left seam: the hind paw outline (x 340..342) keeps its own anti-aliasing at x 343; the fill's first columns
    # ramp gently toward it so no column is darker than its left neighbour (a dip there read as a doubled stroke)
    for r in range(rh):
        y = y0 + r
        if HIND_EDGE_ROWS[0] <= y <= HIND_EDGE_ROWS[1]:
            fill[r, 1, :3] += (HIND_EDGE_RGB - fill[r, 1, :3]) * 0.08
            fill[r, 2, :3] += (HIND_EDGE_RGB - fill[r, 2, :3]) * 0.03
    rng = np.random.default_rng(RNG_SEED)
    def modulation(n):
        m = 0.82 + 0.18 * rng.random(n + 4)
        return np.convolve(m, np.ones(5) / 5.0, mode="valid")
    col_mod = modulation(rw)                      # along x, for the floor contour stroke
    row_mod = modulation(rh)                      # along y, for the paw's side stroke

    # belly / floor contour, outline stroke and shadow band
    cx, cy = catmull_rom_curve(CONTOUR_PTS)
    yc = np.interp(pcx, cx, cy)
    d = yc - pcy                                   # >0 above the contour (inside body)
    coverage = np.clip(d + 0.5, 0.0, 1.0)
    s = np.clip(d + 0.6, 0.0, 1.0) * np.clip((3.8 - d) / 1.2, 0.0, 1.0) * col_mod[None, :]
    t = smoothstep((d - SHADE_SPAN[0]) / (SHADE_SPAN[1] - SHADE_SPAN[0]))
    shade = SHADE[None, None, :] + (1.0 - SHADE[None, None, :]) * t[..., None]
    rgb = fill[..., :3] * shade
    rgb = rgb + (STROKE_RGB[None, None, :] - rgb) * s[..., None]
    fill[..., :3] = np.clip(rgb, 0.0, 255.0)
    fill[..., 3] = fill[..., 3] * coverage

    # ---- D. paw corner patch on the ORIGINAL layer -----------------------------
    orig_a = reg[..., 3]
    patch_w = np.zeros((rh, rw))
    pr = (yy >= PAW_PATCH_ROWS[0]) & (yy < PAW_PATCH_ROWS[1]) & (xx > edge_x + 1.0) & (xx < PAW_PATCH_FADE[1])
    fade = smoothstep((PAW_PATCH_FADE[1] - pcx) / (PAW_PATCH_FADE[1] - PAW_PATCH_FADE[0]))
    inner = np.clip(xx - edge_x - 1.0, 0.0, 1.0)   # 1 px anti-aliased start next to the edge
    patch_w = np.where(pr, fade * inner, 0.0)
    psx = (PAW_MIRROR_SUM - xx).astype(np.int64)
    clone = src[yy.astype(np.int64), psx]
    reg[..., :3] = reg[..., :3] + (clone[..., :3] - reg[..., :3]) * patch_w[..., None]

    # ---- E. composite: erased original OVER fill --------------------------------
    transparent = (orig_a < 250).astype(np.float64)
    Wt = np.maximum((M > 0.0).astype(np.float64), transparent)
    fill_a = fill[..., 3] * Wt / 255.0
    fa = (orig_a / 255.0) * (1.0 - M)
    out_a_raw = fa + fill_a * (1.0 - fa)
    num = reg[..., :3] * fa[..., None] + fill[..., :3] * (fill_a * (1.0 - fa))[..., None]
    safe = np.where(out_a_raw > 1e-6, out_a_raw, 1.0)
    out_rgb = num / safe[..., None]                       # un-premultiply with the raw alpha (a plain lerp of colours)
    out_rgb = np.where((out_a_raw > 1e-6)[..., None], out_rgb, reg[..., :3])
    # the body alpha (252) is never exceeded: clamping after the colour maths keeps the lerp exact (an earlier
    # version divided by the clamped alpha and brightened the feathered rows by ~1 %)
    out_a = np.where(orig_a >= 250, np.minimum(out_a_raw, orig_a / 255.0), out_a_raw)

    # ---- F. side stroke along the new paw edge (drawn over the composite) ------
    s_edge = np.clip((2.0 - dist) / 1.2, 0.0, 1.0) * row_mod[:, None]   # ~2 px core, soft edges, varied weight
    s_edge *= smoothstep((yy - PAW_EDGE_STROKE_ROWS[0]) / (PAW_EDGE_STROKE_ROWS[1] - PAW_EDGE_STROKE_ROWS[0]))
    s_edge = np.where((yy < 938) & (out_a > 0.5), s_edge, 0.0)
    out_rgb = out_rgb + (PAW_EDGE_STROKE_RGB[None, None, :] - out_rgb) * s_edge[..., None]
    # junction: the floor contour's core continues into the paw's own bottom stroke (take the darker of the two)
    junction = (xx >= 486) & (xx <= 496) & (yy >= 943) & (yy <= 948) & (out_a > 0.5)
    with_stroke = out_rgb + (STROKE_RGB[None, None, :] - out_rgb) * np.clip(s, 0.0, 1.0)[..., None]
    j_touch = junction & (with_stroke.sum(2) < out_rgb.sum(2))
    out_rgb = np.where(j_touch[..., None], with_stroke, out_rgb)

    # ---- G. write back, restoring every pixel that no step touched --------------
    touched = (M > 0.0) | (transparent > 0.0) | (patch_w > 0.0) | (s_edge > 0.0) | j_touch
    region_out = np.empty_like(reg)
    region_out[..., :3] = out_rgb
    region_out[..., 3] = out_a * 255.0
    region_u8 = np.clip(np.rint(region_out), 0, 255).astype(np.uint8)
    region_u8[~touched] = src_u8[y0:y1, x0:x1][~touched]
    out = src_u8.copy()
    out[y0:y1, x0:x1] = region_u8
    return out


def main(argv):
    if len(argv) != 3:
        print("usage: retouch_sleepy.py <input.png> <output.png>", file=sys.stderr)
        return 2
    im = Image.open(argv[1])
    assert im.size == (1024, 1024) and im.mode == "RGBA", "input must be a 1024x1024 RGBA PNG"
    src = np.array(im)
    out = retouch(src)

    # ---- verification ------------------------------------------------------------
    x0, y0, x1, y1 = REGION
    outside = np.ones((1024, 1024), dtype=bool)
    outside[y0:y1, x0:x1] = False
    assert np.array_equal(src[outside], out[outside]), "pixels outside REGION changed"
    bb_in, bb_out = alpha_bbox(src[..., 3]), alpha_bbox(out[..., 3])
    assert bb_in == bb_out, f"alpha bbox changed: {bb_in} -> {bb_out}"
    a_in, a_out = src[..., 3].astype(int), out[..., 3].astype(int)
    assert not np.any((a_in >= 250) & (a_out > a_in)), "alpha raised above the original body alpha (seam ridge)"
    paw = np.zeros_like(a_in, dtype=bool)
    for y in range(938, 959):
        paw[y, V_RIGHT_EDGE.get(y, 510) - 2:512] = True
    assert not np.any(paw & (a_in > 0) & (a_in < 250) & (a_out < a_in)), "the remaining paw's anti-aliased edge was eroded"
    changed = np.any(src != out, axis=2)
    ys, xs = np.nonzero(changed)
    print(f"changed pixels: {int(changed.sum())}  bbox x{xs.min()}-{xs.max()} y{ys.min()}-{ys.max()}")
    print(f"alpha bbox unchanged: {bb_in}")
    Image.fromarray(out, "RGBA").save(argv[2], optimize=True)
    print("wrote", argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
