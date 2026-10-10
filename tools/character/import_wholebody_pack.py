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
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
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
        im = Image.open(src)
        assert im.size == (width, height), f"{pose}: unexpected size {im.size}"
        cleaned, stats = clean(im)
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
            {"id": "pose", "parent": "bodyPivot", "position": [0, 0], "z": 2, "kind": "poseSprite", "size": [width, height]},
        ],
        "note": "Generated by tools/character/import_wholebody_pack.py from the owner's asset pack.",
    }
    (RES / "mali_wholebody_spec.json").write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"poses": {p: {"removed": qa[p]["removedPixels"], "bbox": qa[p]["opaqueBBox"], "floorShift": poses[p]["floorShiftFromSeated"]} for p in POSES},
                      "designSize": spec["designSize"], "aboveFloorMax": above_max}, indent=1))


if __name__ == "__main__":
    main()
