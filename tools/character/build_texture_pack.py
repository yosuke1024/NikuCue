#!/usr/bin/env python3
"""Converts an illustrator's layer export into the runtime texture pack (docs/CHARACTER_ASSET_PIPELINE.md §2–§3).

Input directory must contain:
  layers_export.json   {"canvasPx": [2048, 2048], "pixelsPerUnit": 2,
                        "layers": [{"name": "body", "file": "body.png", "x": 300, "y": 900, "width": 880, "height": 720}, ...],
                        "pivots": {"root": [1024, 1688], "bodyPivot": [...], "tailPivot": [...], "forePawLPivot": [...],
                                   "forePawRPivot": [...], "headPivot": [...], "earLPivot": [...], "earRPivot": [...]}}
                       x/y are the layer's top-left in canvas pixels (y down, as design tools export them).
                       Layer names: node ids from character_spec.json; expression variants as "eyeL.neutral", "mouth.sleepy".
  <file>.png per layer (cropped to the layer bounds; transparent background).

Outputs (default paths, override with --out):
  NikuCue/Resources/Assets.xcassets/MaliParts.spriteatlas/<texture>.png (+ Contents.json)
  NikuCue/Resources/Character/mali_texture_pack.json
  NikuCue/Resources/Character/character_spec.json with node positions/sizes re-derived from the pivots (REV entry appended)
  artifacts/texture-pack/composite_check.png — all parts re-assembled at rest; compare with the flat illustration.

Standard library + Pillow (for the composite check). Run: python3 tools/character/build_texture_pack.py <export_dir> [--dry-run]
"""
from __future__ import annotations
import argparse
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC_PATH = ROOT / "NikuCue" / "Resources" / "Character" / "character_spec.json"
ATLAS_DIR = ROOT / "NikuCue" / "Resources" / "Assets.xcassets" / "MaliParts.spriteatlas"
MANIFEST_PATH = ROOT / "NikuCue" / "Resources" / "Character" / "mali_texture_pack.json"
CHECK_DIR = ROOT / "artifacts" / "texture-pack"

# Parts whose node origin is a marked joint rather than the layer centre.
JOINT_ORIGIN = {"tail": "tailPivot", "forePawL": "forePawLPivot", "forePawR": "forePawRPivot", "earL": "earLPivot", "earR": "earRPivot"}
REQUIRED_PIVOTS = ["root", "bodyPivot", "tailPivot", "forePawLPivot", "forePawRPivot", "headPivot", "earLPivot", "earRPivot"]


def to_units(px_point, canvas_h, ppu):
    """Canvas px (y down) → design units (y up)."""
    return (px_point[0] / ppu, (canvas_h - px_point[1]) / ppu)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("export_dir")
    ap.add_argument("--dry-run", action="store_true", help="validate and write only the composite check")
    ap.add_argument("--atlas-name", default="MaliParts")
    args = ap.parse_args()
    export_dir = Path(args.export_dir)
    export = json.loads((export_dir / "layers_export.json").read_text(encoding="utf-8"))
    canvas_w, canvas_h = export["canvasPx"]
    ppu = float(export["pixelsPerUnit"])
    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    nodes = {n["id"]: n for n in spec["nodes"]}
    layers = {l["name"]: l for l in export["layers"]}
    pivots_px = export["pivots"]
    missing = [p for p in REQUIRED_PIVOTS if p not in pivots_px]
    if missing:
        raise SystemExit(f"missing pivots: {missing}")

    # 1. origin of every node in design units
    origins: dict[str, tuple[float, float]] = {}
    for name in REQUIRED_PIVOTS:
        origins[name] = to_units(pivots_px[name], canvas_h, ppu)
    origins["face"] = origins["headPivot"]

    def layer_centre(layer):
        return to_units((layer["x"] + layer["width"] / 2, layer["y"] + layer["height"] / 2), canvas_h, ppu)

    def base_layer(node_id):
        if node_id in layers:
            return layers[node_id]
        for e in ("neutral", "softSmile", "closedHappy", "curious", "sleepy"):
            if f"{node_id}.{e}" in layers:
                return layers[f"{node_id}.{e}"]
        return None

    problems = []
    for node in spec["nodes"]:
        nid = node["id"]
        if node["kind"] == "pivot" or nid in origins:
            continue
        if nid in JOINT_ORIGIN:
            origins[nid] = origins[JOINT_ORIGIN[nid]]
            continue
        layer = base_layer(nid)
        if layer is None:
            problems.append(f"no layer for node {nid}")
            continue
        origins[nid] = layer_centre(layer)
    if problems:
        raise SystemExit("\n".join(problems))

    # 2. node positions relative to parents, sizes from layers
    for node in spec["nodes"]:
        nid = node["id"]
        if node["parent"] is None:
            node["position"] = [round(origins["root"][0], 1), round(origins["root"][1], 1)]
            continue
        parent = node["parent"]
        po = origins[parent]
        o = origins[nid]
        node["position"] = [round(o[0] - po[0], 1), round(o[1] - po[1], 1)]
        layer = base_layer(nid)
        if layer is not None and node["kind"] != "pivot":
            node["size"] = [round(layer["width"] / ppu, 1), round(layer["height"] / ppu, 1)]

    # 3. manifest parts with bounds relative to node origin (units, y up)
    def bounds_for(layer, origin):
        min_x = layer["x"] / ppu - origin[0]
        max_x = (layer["x"] + layer["width"]) / ppu - origin[0]
        top_units = (canvas_h - layer["y"]) / ppu - origin[1]
        bottom_units = (canvas_h - layer["y"] - layer["height"]) / ppu - origin[1]
        return [round(min_x, 2), round(bottom_units, 2), round(max_x, 2), round(top_units, 2)]

    parts = {}
    for node in spec["nodes"]:
        nid = node["id"]
        if node["kind"] == "pivot":
            continue
        variants = {e: layers[f"{nid}.{e}"] for e in ("neutral", "softSmile", "closedHappy", "curious", "sleepy") if f"{nid}.{e}" in layers}
        if variants:
            parts[nid] = {"variants": {e: {"texture": f"{nid}_{e}", "bounds": bounds_for(l, origins[nid])} for e, l in variants.items()}}
        else:
            parts[nid] = {"texture": nid, "bounds": bounds_for(layers[nid], origins[nid])}
    if "heart" in layers:
        hl = layers["heart"]
        parts["heart"] = {"texture": "heart", "bounds": bounds_for(hl, layer_centre(hl))}
    else:
        problems.append("no heart layer")

    manifest = {
        "schemaVersion": 1,
        "characterId": export.get("characterId", "mali_v2"),
        "isProductionArt": False,
        "status": "Imported texture pack awaiting owner approval (R02)",
        "atlas": args.atlas_name,
        "pixelsPerUnit": ppu,
        "parts": parts,
        "license": export.get("license", "REPLACE_WITH_LICENSE_STATEMENT"),
        "source": export.get("source", "REPLACE_WITH_SOURCE_FILE"),
    }

    # 4. composite check image
    try:
        from PIL import Image
        canvas = Image.new("RGBA", (canvas_w, canvas_h), (251, 239, 217, 255))
        order = sorted(export["layers"], key=lambda l: [n["id"] for n in spec["nodes"]].index(l["name"].split(".")[0]) if l["name"].split(".")[0] in nodes else 999)
        for l in order:
            if "." in l["name"] and not l["name"].endswith(".neutral"):
                continue
            img = Image.open(export_dir / l["file"]).convert("RGBA")
            if img.size != (l["width"], l["height"]):
                problems.append(f"{l['name']}: png size {img.size} != layer bounds {(l['width'], l['height'])}")
            canvas.alpha_composite(img, (int(l["x"]), int(l["y"])))
        CHECK_DIR.mkdir(parents=True, exist_ok=True)
        canvas.save(CHECK_DIR / "composite_check.png")
    except ImportError:
        print("Pillow not available: composite check skipped")

    if problems:
        raise SystemExit("\n".join(problems))
    if args.dry_run:
        print(json.dumps(manifest, indent=2)[:2000])
        return

    # 5. write atlas, manifest, spec revision
    ATLAS_DIR.mkdir(parents=True, exist_ok=True)
    for name, part in parts.items():
        drawings = part["variants"].items() if "variants" in part else [("_", part)]
        for key, d in drawings:
            src_name = name if key == "_" else f"{name}.{key}"
            shutil.copyfile(export_dir / layers[src_name]["file"], ATLAS_DIR / f"{d['texture']}.png")
    (ATLAS_DIR / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    spec.setdefault("revisions", []).append({
        "id": f"REV-ART-{len(spec.get('revisions', [])) + 1}",
        "change": "node positions/sizes re-derived from the illustrator's pivots and layer bounds",
        "reason": "texture pack import (docs/CHARACTER_ASSET_PIPELINE.md §5 S3)",
        "nodes": [n["id"] for n in spec["nodes"]],
    })
    SPEC_PATH.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {MANIFEST_PATH.relative_to(ROOT)}, {ATLAS_DIR.relative_to(ROOT)} ({len(parts)} parts), updated character_spec.json")


if __name__ == "__main__":
    main()
