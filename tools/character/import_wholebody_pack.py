#!/usr/bin/env python3
"""Imports the owner-supplied whole-body Mali textures (docs/assets/mali_v1) into the app.

Produces:
  NikuCue/Resources/Assets.xcassets/Mali/Mali<Pose>.imageset/{Contents.json, mali_<pose>.png}   (fringe-cleaned copies)
  NikuCue/Resources/Character/mali_poses.json              pose pack manifest: poses → image set, bounds relative to the floor centre
  NikuCue/Resources/Character/mali_wholebody_spec.json     4-node rig (root/shadow/bodyPivot/pose) with poses as "expressions"
  artifacts/mali-assets-v1/inspection_{light,dark}.png     cleaned textures on light and dark surfaces for owner review

Cleaning is deliberately conservative: pixels whose alpha is below 8, and isolated pixels that lie outside a 4 px
dilation of the opaque silhouette, get alpha 0. Colours are never changed. The originals stay in docs/assets/mali_v1.
Whole-body textures are an interim treatment: no blinking, tail or limb motion is synthesised from them (asset README §6).
Run: python3 tools/character/import_wholebody_pack.py
"""
from __future__ import annotations
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import retouch_sleepy  # noqa: E402  (deterministic code retouch of the owner's sleepy texture: five paws → four)
SRC = ROOT / "docs" / "assets" / "mali_v1"
CATALOG = ROOT / "NikuCue" / "Resources" / "Assets.xcassets" / "Mali"
RES = ROOT / "NikuCue" / "Resources" / "Character"
ART = ROOT / "artifacts" / "mali-assets-v1"

POSES = ["idle", "happy", "celebrate", "pet", "sleepy", "sad"]
IMAGESET = {p: f"Mali{p.capitalize()}" for p in POSES}
# Clip → pose mapping from the asset manifest; milestone is a celebration that settles into happy.
CLIP_POSES = {"idle": "idle", "greet": "happy", "pet": "pet", "celebrate": "celebrate", "cheer": "happy",
              "settle": "idle", "doze": "sleepy", "milestone": "celebrate"}
# Rig expressions (engine vocabulary) → poses, so existing reaction intents keep working.
EXPRESSION_MAP = {"neutral": "idle", "softSmile": "happy", "closedHappy": "happy", "curious": "happy", "sleepy": "sleepy"}
SEATED_FLOOR_FROM_TOP = 961  # alpha bbox bottom shared by the seated textures (asset manifest QA)
# Idle tail layer (owner request 2026-10-11: tail sway while idle). The tail is cut out of the owner's idle image along
# the hip outline so it can rotate as its own sprite BEHIND the body; everything is derived, nothing is redrawn.
TAIL_ROWS = (500, 915)        # image rows (y down) that can hold tail pixels right of the cut
TAIL_GAP_ROWS_END = 722       # above this row the cheek and the tail are separated by transparent background
TAIL_PIVOT_IMG = (748, 828)   # tail base behind the hip, image pixels (x right, y down)
TAIL_UNDERLAP = 28            # tail pixels extended under the body so a sway never shows a gap at the hip
# Hip/hind-leg outline below the gap, read from artifacts/mali-assets-v1/tail_split_check.png (image px, y down).
# The cut snaps to the stroke found within ±8 px of this guide so the tail's own fur strokes are not mistaken for it.
HIP_GUIDE = [(765, 722), (772, 745), (780, 768), (787, 795), (792, 813), (790, 828), (781, 840), (770, 862),
             (765, 880), (757, 895), (745, 906), (733, 913), (725, 916)]
TAIL_IMAGESETS = {"body": "MaliIdleBody", "tail": "MaliIdleTail"}
# Rig frame: the floor centre (root) sits GROUND_Y units above the frame bottom (room for the shadow ellipse),
# and the frame top leaves LIFT_HEADROOM above the tallest pose for the celebrate lift (34 units) and hearts.
GROUND_Y = 60
LIFT_HEADROOM = 40


def clean(im: Image.Image) -> tuple[Image.Image, dict]:
    a = np.array(im.convert("RGBA"))
    alpha = a[:, :, 3].astype(np.int32)
    opaque = Image.fromarray(((alpha > 200) * 255).astype("uint8")).filter(ImageFilter.MaxFilter(9))
    near = np.array(opaque) > 0
    stray = (alpha > 0) & ~near
    faint = (alpha > 0) & (alpha < 8)
    removed = int((stray | faint).sum())
    alpha[stray | faint] = 0
    a[:, :, 3] = alpha.astype("uint8")
    cleaned = Image.fromarray(a, "RGBA")
    ys, xs = np.where(alpha > 0)
    bbox = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
    return cleaned, {"removedPixels": removed, "opaqueBBox": bbox}


def _stroke_like(px) -> bool:
    r, g, b, a = px
    lum = (r * 299 + g * 587 + b * 114) // 1000
    return a > 200 and (r - b) > 60 and lum < 215


def _guide_x(y: int) -> int | None:
    """Linear interpolation of HIP_GUIDE at row y (None outside its rows)."""
    for (x0, y0), (x1, y1) in zip(HIP_GUIDE, HIP_GUIDE[1:]):
        if y0 <= y <= y1:
            return round(x0 + (x1 - x0) * (y - y0) / (y1 - y0))
    return None


def tail_cut(im: Image.Image) -> dict[int, int]:
    """Per image row, the first x that belongs to the tail (rows without a tail are absent).

    Rows above TAIL_GAP_ROWS_END: cheek/body and tail are separated by transparent background. The tail is the
    first opaque run that is at least 12 px wide and starts right of x=760 (whisker tips are thinner); the cut is
    the middle of the gap just left of it. Rows below: body fur and the tail's underside are separated by the
    hip outline stroke (soft tan line); the cut is just right of the first stroke run found from x=720. Rows
    whose stroke could not be found are interpolated from their neighbours. Nothing is smoothed: a jagged cut
    inside transparent background is invisible, and the stroke is continuous by itself."""
    px = im.load()
    w, h = im.size
    cuts: dict[int, int | None] = {}
    for y in range(*TAIL_ROWS):
        if y < TAIL_GAP_ROWS_END:
            runs = []
            x = 690
            while x < w:
                while x < w and px[x, y][3] <= 40: x += 1
                if x >= w: break
                s0 = x
                while x < w and px[x, y][3] > 40: x += 1
                runs.append((s0, x))
            big = [r for r in runs if r[1] - r[0] >= 10 and r[0] >= 760]
            if not big:
                continue
            tail_start = big[0][0]
            prev_end = max([r[1] for r in runs if r[1] <= tail_start], default=None)
            cuts[y] = (prev_end + tail_start) // 2 if prev_end is not None else tail_start - 2
        else:
            guide = _guide_x(y)
            if guide is None:
                continue
            runs = []
            x = guide - 8
            while x <= guide + 8:
                if _stroke_like(px[x, y]) and _stroke_like(px[x + 1, y]):
                    end = x
                    while end < w - 1 and _stroke_like(px[end, y]): end += 1
                    runs.append((x, end))
                    x = end
                x += 1
            # A real outline stroke is 3-8 px wide; longer stroke-like runs are the tail's shaded underside.
            strokes = [r for r in runs if r[1] - r[0] <= 8]
            if strokes:
                end = min(strokes, key=lambda r: abs((r[0] + r[1]) / 2 - guide))[1]
                cuts[y] = end + 1
            else:
                cuts[y] = guide + 2
    # interpolate missing stroke rows between found neighbours
    stroke_rows = [y for y in range(TAIL_GAP_ROWS_END, TAIL_ROWS[1]) if y in cuts]
    known = [y for y in stroke_rows if cuts[y] is not None]
    for y in stroke_rows:
        if cuts[y] is None:
            below = [k for k in known if k > y]; above = [k for k in known if k < y]
            if above and below:
                a, b = above[-1], below[0]
                cuts[y] = round(cuts[a] + (cuts[b] - cuts[a]) * (y - a) / (b - a))
            elif above: cuts[y] = cuts[above[-1]]
            elif below: cuts[y] = cuts[below[0]]
    out = {}
    for y, cut in cuts.items():
        if cut is None: continue
        if any(px[xx, y][3] > 40 for xx in range(cut, w)):
            out[y] = cut
    return out


def largest_component(mask: np.ndarray) -> np.ndarray:
    """Keeps the largest 8-connected component of a boolean mask (drops stray fragments)."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    best: list[tuple[int, int]] = []
    ys, xs = np.where(mask)
    for sy, sx in zip(ys.tolist(), xs.tolist()):
        if seen[sy, sx]: continue
        stack = [(sy, sx)]; seen[sy, sx] = True; comp = []
        while stack:
            cy, cx = stack.pop(); comp.append((cy, cx))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True; stack.append((ny, nx))
        if len(comp) > len(best): best = comp
    out = np.zeros_like(mask)
    for cy, cx in best: out[cy, cx] = True
    return out


def split_tail(idle: Image.Image) -> tuple[Image.Image, Image.Image, list[int], dict]:
    """Returns (body without tail, tail layer cropped, tail crop box [x0,y0,x1,y1], qa)."""
    a = np.array(idle.convert("RGBA"))
    h, w = a.shape[:2]
    cuts = tail_cut(idle)
    mask = np.zeros((h, w), dtype=bool)
    for y, cut in cuts.items():
        mask[y, cut:] = True
    mask &= a[:, :, 3] > 0
    fragments_before = int(mask.sum())
    mask = largest_component(mask)
    dropped_fragments = fragments_before - int(mask.sum())
    # Grow into the narrow rows at the top of the tail curl (x >= 790, above the body) that the run rule skipped.
    opaque = a[:, :, 3] > 0
    grow_zone = np.zeros_like(mask); grow_zone[:600, 790:] = True
    for _ in range(12):
        neigh = np.zeros_like(mask)
        neigh[1:, :] |= mask[:-1, :]; neigh[:-1, :] |= mask[1:, :]; neigh[:, 1:] |= mask[:, :-1]; neigh[:, :-1] |= mask[:, 1:]
        added = neigh & opaque & grow_zone & ~mask
        if not added.any(): break
        mask |= added
    body = a.copy()
    body[mask] = 0
    tail = a.copy()
    tail[~mask] = 0
    # Underlap: extend the tail's edge pixel leftwards under the body on rows where tail and body touch.
    underlapped = 0
    for y, cut in cuts.items():
        if a[y, cut, 3] <= 40 or cut - 1 < 0 or a[y, cut - 1, 3] <= 40:
            continue                                                # gap row: real silhouette, nothing to hide
        edge = a[y, cut].copy()
        for i in range(1, TAIL_UNDERLAP + 1):
            x = cut - i
            if x < 0: break
            feather = 1.0 if i <= TAIL_UNDERLAP - 10 else max(0.0, (TAIL_UNDERLAP - i) / 10)
            tail[y, x] = edge
            tail[y, x, 3] = int(edge[3] * feather)
            underlapped += 1
    ys, xs = np.where(tail[:, :, 3] > 0)
    box = [int(xs.min()) - 2, int(ys.min()) - 2, int(xs.max()) + 3, int(ys.max()) + 3]
    tail_img = Image.fromarray(tail, "RGBA").crop(box)
    body_img = Image.fromarray(body, "RGBA")
    # Rest composite must reproduce the original exactly where the body is opaque (tail is drawn behind).
    comp = Image.new("RGBA", idle.size, (0, 0, 0, 0))
    comp.alpha_composite(tail_img, (box[0], box[1]))
    comp.alpha_composite(body_img)
    diff = np.abs(np.array(comp).astype(int) - a.astype(int))
    qa = {"rows": [min(cuts), max(cuts)], "cutRange": [min(cuts.values()), max(cuts.values())], "underlapPixels": underlapped,
          "droppedFragmentPixels": dropped_fragments, "cuts": {str(y): c for y, c in cuts.items() if y % 10 == 0},
          "restCompositeMaxDiff": int(diff.max()), "restCompositeMeanDiff": round(float(diff.mean()), 4), "tailCropBox": box}
    return body_img, tail_img, box, qa


def tail_check_sheet(idle: Image.Image, body: Image.Image, tail: Image.Image, box: list[int], cuts: dict[int, int]) -> Image.Image:
    """Review sheet: original | body | tail, then rest / -5° / +5° composites on light and dark surfaces."""
    px, py = TAIL_PIVOT_IMG
    def composite(angle_deg: float) -> Image.Image:
        layer = Image.new("RGBA", idle.size, (0, 0, 0, 0))
        layer.alpha_composite(tail, (box[0], box[1]))
        if angle_deg:
            layer = layer.rotate(angle_deg, resample=Image.BICUBIC, center=(px, py))
        layer.alpha_composite(body)
        return layer
    tiles = [("original", idle), ("body", body)]
    tail_full = Image.new("RGBA", idle.size, (0, 0, 0, 0)); tail_full.alpha_composite(tail, (box[0], box[1]))
    tiles.append(("tail layer", tail_full))
    for ang in (0, -5, 5):
        tiles.append((f"composite {ang:+d}°", composite(ang)))
    size = 300
    sheet = Image.new("RGB", (6 * (size + 10) + 10, 2 * (size + 30) + 10), (251, 239, 217))
    draw = ImageDraw.Draw(sheet)
    for row, bg in enumerate(((251, 239, 217), (36, 30, 27))):
        for col, (label, im) in enumerate(tiles):
            cell = Image.new("RGB", im.size, bg); cell.paste(im, (0, 0), im)
            x = 10 + col * (size + 10); y = 10 + row * (size + 30)
            draw.rectangle([x, y, x + size, y + size], fill=bg)
            sheet.paste(cell.resize((size, size), Image.LANCZOS), (x, y))
            draw.text((x + 4, y + size + 4), label, fill=(90, 70, 60))
    # zoomed junction: cut line on the original, then rest / +5° / -5° composites, light background
    overlay = Image.new("RGB", idle.size, (251, 239, 217)); overlay.paste(idle, (0, 0), idle)
    od = ImageDraw.Draw(overlay)
    for y, cut in cuts.items(): od.point((cut, y), fill=(220, 30, 30))
    od.ellipse([px - 5, py - 5, px + 5, py + 5], outline=(30, 90, 220), width=2)
    zoom_src = [overlay.crop((640, 480, 900, 940))] + [composite(a).crop((640, 480, 900, 940)) for a in (0, 5, -5)]
    zsheet = Image.new("RGB", (4 * 270, 470), (251, 239, 217))
    for i, z in enumerate(zoom_src):
        cell = Image.new("RGB", z.size, (251, 239, 217)); cell.paste(z, (0, 0), z.getchannel("A") if z.mode == "RGBA" else None); zsheet.paste(cell, (i * 270, 5))
    out = Image.new("RGB", (sheet.width, sheet.height + zsheet.height + 10), (251, 239, 217))
    out.paste(sheet, (0, 0)); out.paste(zsheet, (10, sheet.height + 5))
    return out


def retouch_sheet(original: Image.Image, retouched: Image.Image) -> Image.Image:
    """Review sheet for the sleepy retouch: whole image at phone size and a 4x paw-row crop, light and dark."""
    def on(bg, im):
        b = Image.new("RGB", im.size, bg); b.paste(im, (0, 0), im); return b
    sheet = Image.new("RGB", (4 * 250 + 50, 270 + 2 * 450 + 20), (251, 239, 217))
    draw = ImageDraw.Draw(sheet)
    cells = [((251, 239, 217), original, "original / light"), ((251, 239, 217), retouched, "retouched / light"),
             ((36, 30, 27), original, "original / dark"), ((36, 30, 27), retouched, "retouched / dark")]
    for i, (bg, im, label) in enumerate(cells):
        sheet.paste(on(bg, im).crop((100, 40, 980, 970)).resize((240, 254), Image.LANCZOS), (10 + i * 250, 8))
        draw.text((10 + i * 250, 262), label, fill=(90, 70, 60))
    for i, bg in enumerate(((251, 239, 217), (36, 30, 27))):
        for j, im in enumerate((original, retouched)):
            sheet.paste(on(bg, im).crop((320, 840, 490, 950)).resize((500, 324), Image.LANCZOS), (10 + j * 510, 290 + i * 340))
    draw.text((10, 290 + 2 * 340 - 10), "paw row 4x: original (left) vs retouched (right), light then dark. Code retouch; owner art review pending (R02).", fill=(90, 70, 60))
    return sheet


def main() -> None:
    manifest_in = json.loads((SRC / "mali_asset_manifest.json").read_text(encoding="utf-8"))
    width, height = manifest_in["size"]
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
    ART.mkdir(parents=True, exist_ok=True)
    poses: dict = {}
    qa: dict = {}
    sheets = {"light": Image.new("RGB", (len(POSES) * 300 + 20, 330), (251, 239, 217)),
              "dark": Image.new("RGB", (len(POSES) * 300 + 20, 330), (36, 30, 27))}
    for i, pose in enumerate(POSES):
        src = SRC / "Assets" / "Mali" / f"mali_{pose}.png"
        im = Image.open(src).convert("RGBA")
        assert im.size == (width, height), f"{pose}: unexpected size {im.size}"
        if pose == "sleepy":
            # Owner report 2026-10-11: the yawning pose showed four paws on the floor plus the raised one.
            original = im
            im = Image.fromarray(retouch_sleepy.retouch(np.array(im)), "RGBA")
            retouch_sheet(original, im).save(ART / "sleepy_retouch_check.png")
        cleaned, stats = clean(im)
        if pose == "sleepy":
            stats["retouch"] = "tools/character/retouch_sleepy.py (mirror fill); owner art review pending"
        folder = CATALOG / f"{IMAGESET[pose]}.imageset"
        folder.mkdir(exist_ok=True)
        cleaned.save(folder / f"mali_{pose}.png", optimize=True)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"mali_{pose}.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n", encoding="utf-8")
        # Bounds relative to the node origin = floor centre (design units = pixels, y up).
        # Every texture keeps the same 1024 frame; the frame is shifted so this pose's alpha bottom sits on the floor.
        bottom_from_top = stats["opaqueBBox"][3]
        floor_from_bottom = height - 1 - bottom_from_top
        poses[pose] = {
            "imageSet": IMAGESET[pose],
            "bounds": [-width / 2, -floor_from_bottom, width / 2, height - floor_from_bottom],
            "floorShiftFromSeated": SEATED_FLOOR_FROM_TOP - bottom_from_top,
        }
        qa[pose] = stats
        small = cleaned.resize((300, 300), Image.LANCZOS)
        for sheet in sheets.values():
            sheet.paste(small, (10 + i * 300, 15), small)
    for name, sheet in sheets.items():
        sheet.save(ART / f"inspection_{name}.png")

    # Idle tail layer: body (full frame, tail removed) + tail crop that rotates around TAIL_PIVOT_IMG behind the body.
    idle_clean = Image.open(CATALOG / f"{IMAGESET['idle']}.imageset" / "mali_idle.png").convert("RGBA")
    body_img, tail_img, tail_box, tail_qa = split_tail(idle_clean)
    for key, png_name, im in (("body", "mali_idle_body.png", body_img), ("tail", "mali_idle_tail.png", tail_img)):
        folder = CATALOG / f"{TAIL_IMAGESETS[key]}.imageset"
        folder.mkdir(exist_ok=True)
        im.save(folder / png_name, optimize=True)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": png_name, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n", encoding="utf-8")
    # The whole idle image is no longer shipped (body + tail reproduce it at rest); keep the catalog lean.
    whole_idle = CATALOG / f"{IMAGESET['idle']}.imageset"
    for f in whole_idle.glob("*"): f.unlink()
    whole_idle.rmdir()
    px, py = TAIL_PIVOT_IMG
    idle_floor = -poses["idle"]["bounds"][1]                       # floor_from_bottom for idle
    pivot_rel_root = [px - width / 2, (height - py) - idle_floor]  # design units, y up, relative to the floor centre
    tail_bounds = [tail_box[0] - px, py - tail_box[3], tail_box[2] - px, py - tail_box[1]]
    poses["idle"]["imageSet"] = TAIL_IMAGESETS["body"]
    poses["idle"]["layers"] = {"tail": {"imageSet": TAIL_IMAGESETS["tail"], "bounds": tail_bounds, "pivot": pivot_rel_root}}
    qa["idle"]["tailSplit"] = tail_qa
    tail_check_sheet(idle_clean, body_img, tail_img, tail_box, tail_cut(idle_clean)).save(ART / "tail_split_check.png")

    union = [min(q["opaqueBBox"][0] for q in qa.values()), min(q["opaqueBBox"][1] for q in qa.values()),
             max(q["opaqueBBox"][2] for q in qa.values()), max(q["opaqueBBox"][3] for q in qa.values())]
    pack = {
        "schemaVersion": 1,
        "characterId": "mali_v1_wholebody",
        "isProductionArt": False,
        "status": "Owner-supplied whole-body textures (Concept A), interim cross-fade treatment; visual sign-off pending (R02)",
        "source": "docs/assets/mali_v1 (NikuCue_Mali_Assets_v1.zip from the owner)",
        "license": "Owner-provided artwork for NikuCue; see docs/assets/mali_v1/README.md",
        "pixelsPerUnit": 1,
        "frame": [width, height],
        "poses": poses,
        "clipPoses": CLIP_POSES,
        "expressionMap": EXPRESSION_MAP,
        "optionalPoses": ["sad"],
        "neverShowOnSkip": ["sad"],
        "layerParts": ["tail"],
        "layerNote": "idle.layers.tail is cut from the owner's idle image along the hip outline (tools/character/import_wholebody_pack.py) and rotates behind the body; other poses keep their painted tail",
        "qa": qa,
    }
    (RES / "mali_poses.json").write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    cat_w = union[2] - union[0]
    # Tallest opaque extent above the floor across poses (celebrate's raised paws/ears), in design units.
    above_max = max(poses[p]["bounds"][3] - qa[p]["opaqueBBox"][1] for p in POSES)
    frame_h = GROUND_Y + above_max + LIFT_HEADROOM
    spec = {
        "schemaVersion": 1,
        "characterId": "mali_v1_wholebody",
        "isProductionArt": False,
        "status": "Whole-body texture rig: one pose sprite, cross-faded; no articulated parts",
        "canvas": {"width": width, "height": frame_h, "coordinateOrigin": "bottomLeft", "units": "designUnits", "transparent": True, "rootGroundY": GROUND_Y},
        # CatScene fits designSize into 92 % of the view and puts the root 6 % above the bottom edge, so the frame
        # height is the design height: every pose, the celebrate lift and the milestone hearts stay inside the view.
        "designSize": [cat_w + 40, frame_h],
        "palette": {"shadow": "#D7C9B8"},
        "expressions": POSES,
        "expressionMap": EXPRESSION_MAP,
        "nodes": [
            {"id": "root", "parent": None, "position": [width // 2, GROUND_Y], "z": 0, "kind": "pivot"},
            {"id": "shadow", "parent": "root", "position": [0, 0], "z": 0, "kind": "ellipse", "size": [360, 44], "scale": 2.1, "fill": "shadow"},
            {"id": "bodyPivot", "parent": "root", "position": [0, 0], "z": 1, "kind": "pivot"},
            {"id": "tailPivot", "parent": "bodyPivot", "position": pivot_rel_root, "z": 1, "kind": "pivot"},
            {"id": "tail", "parent": "tailPivot", "position": [0, 0], "z": 0, "kind": "layerSprite",
             "size": [tail_box[2] - tail_box[0], tail_box[3] - tail_box[1]]},
            {"id": "pose", "parent": "bodyPivot", "position": [0, 0], "z": 2, "kind": "poseSprite", "size": [width, height]},
        ],
        "note": "Generated by tools/character/import_wholebody_pack.py from the owner's asset pack.",
    }
    (RES / "mali_wholebody_spec.json").write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"poses": {p: {"removed": qa[p]["removedPixels"], "bbox": qa[p]["opaqueBBox"], "floorShift": poses[p]["floorShiftFromSeated"]} for p in POSES},
                      "designSize": spec["designSize"], "aboveFloorMax": above_max, "tail": tail_qa,
                      "tailPivotRelRoot": pivot_rel_root, "tailBounds": tail_bounds}, indent=1))


if __name__ == "__main__":
    main()
