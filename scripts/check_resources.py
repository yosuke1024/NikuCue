#!/usr/bin/env python3
"""Validates the JSON contracts bundled in NikuCue/Resources against the pack rules plus the
repository additions (animation tracks, path data). Mirrors spec/scripts/validate_pack.py but
targets the copies the app actually ships. Standard library only; no network.

Run: python3 scripts/check_resources.py
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "NikuCue" / "Resources"
SPEC = ROOT / "spec"


def load(p: Path):
    with p.open(encoding="utf-8") as f:
        return json.load(f)


def require(cond: bool, msg: str) -> None:
    if not cond:
        raise ValueError(msg)


def placeholders(text: str) -> set[str]:
    return set(re.findall(r"\{([A-Za-z][A-Za-z0-9_]*)\}", text))


PATH_RE = re.compile(r"^(?:[MLCQZ](?:\s-?\d+(?:\.\d+)?)*\s*)+$")


def main() -> None:
    # 1. localization: identical to the pack and internally consistent
    langs = {c: load(RES / "Localization" / f"{c}.json") for c in ("ja", "en", "th")}
    for c in langs:
        pack = load(SPEC / "localization" / f"{c}.json")
        for k, v in pack.items():
            require(langs[c].get(k) == v, f"localization/{c}.json: pack key {k} changed")
    keys = set(langs["en"])
    extra = keys - set(load(SPEC / "localization" / "en.json"))
    # additions beyond the pack are allowed only when documented in docs/SPEC_REVISIONS.md
    revisions = (ROOT / "docs" / "SPEC_REVISIONS.md").read_text(encoding="utf-8")
    for k in sorted(extra):
        require(k in revisions, f"localization key {k} added without a SPEC_REVISIONS entry")
    for c, data in langs.items():
        require(set(data) == keys, f"keys differ: {c}")
        for k, v in data.items():
            require(isinstance(v, str) and v.strip(), f"empty: {c}/{k}")
            require(placeholders(v) == placeholders(langs["en"][k]), f"placeholder mismatch: {c}/{k}")

    # 2. reactions: identical to the pack
    reactions = load(RES / "Reactions" / "reactions.json")
    require(reactions == load(SPEC / "assets-spec" / "reactions.json"), "reactions.json drifted from spec/")

    # 3. character spec: same nodes as the pack except documented revisions
    character = load(RES / "Character" / "character_spec.json")
    spec_character = load(SPEC / "assets-spec" / "character_spec.json")
    nodes = character["nodes"]
    node_ids = {n["id"] for n in nodes}
    require(node_ids == {n["id"] for n in spec_character["nodes"]}, "node id set changed")
    revised = {nid for r in character.get("revisions", []) for nid in r["nodes"]}
    for n, s in zip(nodes, spec_character["nodes"]):
        require(n["id"] == s["id"], "node order changed")
        if n["id"] in revised:
            continue
        require(n == s, f"node {n['id']} changed without a revision entry")
    by_id = {n["id"]: n for n in nodes}
    for n in nodes:
        seen = {n["id"]}
        p = n["parent"]
        while p is not None:
            require(p in by_id, f"missing parent {p}")
            require(p not in seen, f"cycle at {p}")
            seen.add(p)
            p = by_id[p]["parent"]

    # 4. animations: pack fields unchanged, tracks well-formed
    anims = load(RES / "Character" / "animations.json")
    spec_anims = load(SPEC / "assets-spec" / "animations.json")
    require(len(anims["clips"]) == 8, "expected eight clips")
    props = {"rotation", "offsetX", "offsetY", "scaleX", "scaleY", "scale", "alpha", "expression"}
    eases = {"linear", "easeIn", "easeOut", "easeInOut", "sine"}
    for clip, sclip in zip(anims["clips"], spec_anims["clips"]):
        for k, v in sclip.items():
            require(clip.get(k) == v, f"clip {clip['id']}: pack field {k} changed")
        allowed = set(clip["controls"]) | {"face"}
        for tr in clip["tracks"] + clip["reducedMotionTracks"]:
            require(tr["node"] in allowed, f"{clip['id']}: track node {tr['node']} not in controls")
            require(tr["property"] in props, f"{clip['id']}: bad property {tr['property']}")
            times = [k["t"] for k in tr["keyframes"]]
            require(times == sorted(times) and times[0] >= 0 and times[-1] <= clip["durationMs"], f"{clip['id']}: bad keyframe times")
            for kf in tr["keyframes"]:
                require(kf.get("ease", "easeInOut") in eases, f"{clip['id']}: bad ease")
                if tr["property"] == "expression":
                    require(kf["v"] in character["expressions"], f"{clip['id']}: bad expression {kf['v']}")
                else:
                    require(isinstance(kf["v"], (int, float)), f"{clip['id']}: non-numeric value")
        if clip["id"] == "milestone":
            require(len(clip["hearts"]["positions"]) == clip["hearts"]["max"] == 3, "milestone hearts must be three")
    require(anims["ambient"]["blink"]["intervalMs"] == [4000, 7000], "blink interval per docs/04")

    # 5. mali_paths: every drawable node has art, every expression variant exists
    paths = load(RES / "Character" / "mali_paths.json")
    parts = paths["parts"]
    for n in nodes:
        if n["kind"] == "pivot":
            continue
        require(n["id"] in parts, f"no art for node {n['id']}")
    for part_id, part in parts.items():
        variants = part["variants"] if "variants" in part else {"_": part}
        if "variants" in part:
            require(set(variants) == set(character["expressions"]), f"{part_id}: variants must cover all expressions")
        for vid, v in variants.items():
            require(len(v["bounds"]) == 4 and v["bounds"][0] < v["bounds"][2] and v["bounds"][1] < v["bounds"][3], f"{part_id}/{vid}: bounds")
            require(v["layers"], f"{part_id}/{vid}: no layers")
            for layer in v["layers"]:
                require(PATH_RE.match(layer["path"].strip()), f"{part_id}/{vid}: malformed path")
                require(("fill" in layer) != ("stroke" in layer), f"{part_id}/{vid}: layer needs exactly one of fill/stroke")
                colour = layer.get("fill") or layer.get("stroke")
                require(colour in paths["palette"], f"{part_id}/{vid}: unknown palette colour {colour}")
    require(paths["isProductionArt"] is False, "prototype art must not be flagged as production")

    # 5b. texture pack (production art), only when bundled
    pack_path = RES / "Character" / "mali_texture_pack.json"
    pack_parts = 0
    if pack_path.exists():
        pack = load(pack_path)
        require(pack.get("pixelsPerUnit", 0) > 0, "texture pack: pixelsPerUnit")
        atlas_dir = RES / "Assets.xcassets" / f"{pack.get('atlas', 'MaliParts')}.spriteatlas"
        folder = RES / "Character" / pack["folder"] if pack.get("folder") else None
        for n in nodes:
            if n["kind"] == "pivot":
                continue
            require(n["id"] in pack["parts"], f"texture pack: no part for node {n['id']}")
        require("heart" in pack["parts"], "texture pack: heart missing")
        for part_id, part in pack["parts"].items():
            drawings = part["variants"] if "variants" in part else {"_": part}
            if "variants" in part:
                require(set(drawings) >= set(character["expressions"]), f"texture pack: {part_id} lacks expression variants")
            for vid, d in drawings.items():
                b = d["bounds"]
                require(len(b) == 4 and b[0] < b[2] and b[1] < b[3], f"texture pack: {part_id}/{vid} bounds")
                png = (atlas_dir if pack.get("atlas") else folder) / f"{d['texture']}.png"
                require(png.exists(), f"texture pack: missing {png.name}")
                try:
                    import struct
                    with png.open("rb") as fh:
                        head = fh.read(24)
                    w, h = struct.unpack(">II", head[16:24])
                    ew, eh = (b[2] - b[0]) * pack["pixelsPerUnit"], (b[3] - b[1]) * pack["pixelsPerUnit"]
                    require(abs(w - ew) <= 1 and abs(h - eh) <= 1, f"texture pack: {png.name} is {w}x{h}, manifest expects {ew:.0f}x{eh:.0f}")
                except struct.error:
                    raise ValueError(f"texture pack: {png.name} is not a PNG")
            pack_parts += 1

    def imageset_size(catalog, image_set, label):
        import struct
        folder = catalog / f"{image_set}.imageset"
        pngs = sorted(folder.glob("*.png")) if folder.exists() else []
        require(len(pngs) == 1 and (folder / "Contents.json").exists(), f"{label}: image set {image_set} missing or ambiguous")
        if not pngs:
            return 0, 0
        with pngs[0].open("rb") as fh:
            head = fh.read(24)
        return struct.unpack(">II", head[16:24])

    # 5c. whole-body pose textures (owner-supplied), when bundled
    poses_path = RES / "Character" / "mali_poses.json"
    wb_summary = "absent"
    if poses_path.exists():
        poses = load(poses_path)
        wb_spec = load(RES / "Character" / "mali_wholebody_spec.json")
        wb_anims = load(RES / "Character" / "mali_wholebody_animations.json")
        catalog = RES / "Assets.xcassets" / "Mali"
        require(set(wb_spec["expressions"]) <= set(poses["poses"]), "whole-body: rig looks must all be poses")
        for name, pose in poses["poses"].items():
            b = pose["bounds"]
            require(len(b) == 4 and b[0] < b[2] and b[1] < b[3], f"whole-body: {name} bounds")
            w, h = imageset_size(catalog, pose["imageSet"], f"whole-body: {name}")
            require([w, h] == poses["frame"], f"whole-body: {name} is {w}x{h}, frame is {poses['frame']}")
            require(abs((b[2] - b[0]) - w) < 1 and abs((b[3] - b[1]) - h) < 1, f"whole-body: {name} bounds do not match the frame")
            for part, layer in pose.get("layers", {}).items():
                require(part in poses.get("layerParts", []), f"whole-body: {name}.{part} not declared in layerParts")
                lb = layer["bounds"]
                require(len(lb) == 4 and lb[0] < lb[2] and lb[1] < lb[3], f"whole-body: {name}.{part} bounds")
                lw, lh = imageset_size(catalog, layer["imageSet"], f"whole-body: {name}.{part}")
                require(abs((lb[2] - lb[0]) - lw) < 1 and abs((lb[3] - lb[1]) - lh) < 1, f"whole-body: {name}.{part} bounds do not match its image")
        node_by_id = {n["id"]: n for n in wb_spec["nodes"]}
        for part in poses.get("layerParts", []):
            require(part in node_by_id, f"whole-body: layer part {part} has no rig node")
            pivot = node_by_id.get(node_by_id[part]["parent"]) if part in node_by_id else None
            require(pivot is not None and pivot["kind"] == "pivot", f"whole-body: {part} needs a pivot parent")
            require(pivot is not None and pivot["z"] < node_by_id["pose"]["z"], f"whole-body: {part} layer must draw behind the pose sprite")
            for name, pose in poses["poses"].items():
                pv = pose.get("layers", {}).get(part, {}).get("pivot")
                if pv is not None and pivot is not None:
                    require(abs(pv[0] - pivot["position"][0]) <= 0.5 and abs(pv[1] - pivot["position"][1]) <= 0.5,
                            f"whole-body: {name}.{part} pivot {pv} differs from rig node {pivot['id']} {pivot['position']}")
        for clip_id, pose in poses["clipPoses"].items():
            require(pose in poses["poses"], f"whole-body: clip {clip_id} → unknown pose {pose}")
        require(poses["clipPoses"]["settle"] not in poses.get("neverShowOnSkip", []), "whole-body: settle must not show a guilt pose")
        for e in character["expressions"]:
            require(poses["expressionMap"].get(e) in poses["poses"], f"whole-body: expressionMap lacks {e}")
        ids = {n["id"] for n in wb_spec["nodes"]}
        require({"root", "shadow", "bodyPivot", "pose"} <= ids, "whole-body: rig nodes")
        require(len(wb_anims["clips"]) == 8, "whole-body: eight clips")
        eases = {"linear", "easeIn", "easeOut", "easeInOut", "sine"}
        for clip in wb_anims["clips"]:
            require(clip["expression"] == poses["clipPoses"][clip["id"]], f"whole-body: clip {clip['id']} default pose")
            for tr in clip["tracks"] + clip["reducedMotionTracks"]:
                require(tr["node"] in ids, f"whole-body: {clip['id']} track node {tr['node']}")
                require(tr["node"] in clip["controls"], f"whole-body: {clip['id']} track node {tr['node']} not in controls")
                times = [k["t"] for k in tr["keyframes"]]
                require(times == sorted(times) and times[0] >= 0 and times[-1] <= clip["durationMs"], f"whole-body: {clip['id']} {tr['node']}.{tr['property']} keyframe times")
                require(all(k.get("ease", "easeInOut") in eases for k in tr["keyframes"]), f"whole-body: {clip['id']} {tr['node']}.{tr['property']} ease name")
                if tr["property"] == "expression":
                    for kf in tr["keyframes"]:
                        require(kf["v"] in poses["poses"], f"whole-body: {clip['id']} pose {kf['v']}")
                else:
                    for kf in tr["keyframes"]:
                        if tr["property"] in ("scale", "scaleX", "scaleY") and tr["node"] == "bodyPivot":
                            require(0.97 <= kf["v"] <= 1.03, f"whole-body: {clip['id']} scale {kf['v']} distorts the artwork")
                        if tr["property"] == "rotation" and tr["node"] == "bodyPivot":
                            require(abs(kf["v"]) <= 5, f"whole-body: {clip['id']} rotation {kf['v']} too large for a single portrait")
                        if tr["property"] == "rotation" and tr["node"] == "tailPivot":
                            require(abs(kf["v"]) <= 8, f"whole-body: {clip['id']} tail rotation {kf['v']} would show the cut at the hip")
        # Timing ("間"): clip lengths stay within docs/04 ±20 %, every track ends at rest, no pose flashes (< 500 ms
        # on screen, counting the linger after the clip), cross-fades stay in the asset README window, and the
        # controller hooks (linger, bubble delay, gap between queued reactions) stay in sane ranges.
        spec_ms = {"greet": 1100, "pet": 900, "celebrate": 1600, "cheer": 1200, "settle": 1300, "milestone": 2200}
        rest_value = {"rotation": 0, "offsetX": 0, "offsetY": 0, "scaleX": 1, "scaleY": 1, "scale": 1, "alpha": 1}
        require(120 <= wb_anims["expressionBlendMs"] <= 220, "whole-body: cross-fade must stay within 120-220 ms (asset README)")
        require(0 <= wb_anims.get("reactionGapMs", 0) <= 1000, "whole-body: reactionGapMs out of range")
        for clip in wb_anims["clips"]:
            cid, dur = clip["id"], clip["durationMs"]
            if cid in spec_ms:
                require(0.8 * spec_ms[cid] <= dur <= 1.2 * spec_ms[cid], f"whole-body: {cid} lasts {dur} ms, docs/04 allows ±20 % of {spec_ms[cid]}")
            require(0 <= clip.get("lingerMs", 0) <= 3000, f"whole-body: {cid} lingerMs out of range")
            require(0 <= clip.get("messageAtMs", 0) < dur, f"whole-body: {cid} messageAtMs must fall inside the clip")
            for tr in clip["tracks"]:
                if tr["property"] == "expression":
                    continue
                if not clip.get("loop"):
                    require(abs(tr["keyframes"][-1]["v"] - rest_value[tr["property"]]) < 1e-6 and tr["keyframes"][-1]["t"] == dur,
                            f"whole-body: {cid} {tr['node']}.{tr['property']} must end at rest at {dur} ms")
                else:
                    require(abs(tr["keyframes"][0]["v"] - tr["keyframes"][-1]["v"]) < 1e-6 and tr["keyframes"][-1]["t"] == dur,
                            f"whole-body: {cid} {tr['node']}.{tr['property']} must loop seamlessly")
                if tr["node"] == "bodyPivot" and tr["property"] == "offsetY":
                    require(all(-6 <= k["v"] <= 40 for k in tr["keyframes"]), f"whole-body: {cid} lift/dip out of range")
                # A reaction never drives what the ambient loop drives (breathing scale, tail): starting it would snap
                # those properties instead of easing them back over the blend.
                if not clip.get("loop"):
                    require(not (tr["node"] == "bodyPivot" and tr["property"] in ("scale", "scaleX", "scaleY")),
                            f"whole-body: reaction {cid} must not drive the breathing scale")
                    require(not (tr["node"] == "tailPivot"), f"whole-body: reaction {cid} must not drive the idle tail")
            if clip.get("loop"):
                # An expression track on an ambient loop would call setLook on its first frame and cancel every linger.
                require(all(tr["property"] != "expression" for tr in clip["tracks"] + clip["reducedMotionTracks"]),
                        f"whole-body: ambient loop {cid} must not carry an expression track")
            if "hearts" in clip:
                h = clip["hearts"]
                require(all(at + h["lifeMs"] <= dur for at in h["spawnAtMs"]), f"whole-body: {cid} hearts must end inside the clip")
            for tr in clip["tracks"] + clip["reducedMotionTracks"]:
                if tr["property"] != "expression":
                    continue
                times = [k["t"] for k in tr["keyframes"]] + [dur + clip.get("lingerMs", 0)]
                for a, b in zip(times, times[1:]):
                    require(b - a >= 500, f"whole-body: {cid} shows a pose for only {b - a} ms (flash)")
        # Every pose, the biggest lift and the milestone hearts must stay inside the rig frame (CatScene fits
        # designSize into the view, root 6 % above the bottom), otherwise ears or hearts get clipped on device.
        canvas = wb_spec["canvas"]
        require(wb_spec["designSize"][1] == canvas["height"], "whole-body: design height must equal the frame height")
        headroom = canvas["height"] - canvas["rootGroundY"]
        above_max = max(pose["bounds"][3] - poses["qa"][name]["opaqueBBox"][1] for name, pose in poses["poses"].items())
        lift_max = max((kf["v"] for c in wb_anims["clips"] for tr in c["tracks"]
                        if tr["node"] == "bodyPivot" and tr["property"] == "offsetY" for kf in tr["keyframes"]), default=0)
        require(above_max + lift_max <= headroom, f"whole-body: tallest pose + lift ({above_max + lift_max}) exceeds the frame ({headroom})")
        milestone = next(c for c in wb_anims["clips"] if c["id"] == "milestone")
        hearts = milestone["hearts"]
        heart_half = 26 * hearts["scale"]
        for pos in hearts["positions"] + [hearts["reducedMotion"]["position"]]:
            require(abs(pos[0]) + 24 * hearts["scale"] <= canvas["width"] / 2, f"whole-body: heart {pos} leaves the frame sideways")
            require(pos[1] + hearts["riseUnits"] + heart_half <= headroom, f"whole-body: heart {pos} rises above the frame")
        wb_summary = f"present ({len(poses['poses'])} poses, {sum(1 for c in wb_anims['clips'])} clips, frame {canvas['width']}x{canvas['height']})"

    # 6. reactions reference existing clips and strings
    clip_ids = {c["id"] for c in anims["clips"]}
    for r in reactions["items"]:
        require(r["clipId"] in clip_ids, f"reaction {r['id']}: unknown clip")
        require(set(r["messageKeys"]) <= keys, f"reaction {r['id']}: unknown message keys")

    print(json.dumps({"status": "PASS", "scope": "bundled resource contracts only; not an iOS build",
                      "localizationKeys": len(keys), "rigNodes": len(nodes), "clips": len(anims["clips"]),
                      "artParts": len(parts), "reactions": len(reactions["items"]),
                      "texturePack": "present (%d parts)" % pack_parts if pack_path.exists() else "absent",
                      "wholeBodyPoses": wb_summary}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, TypeError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
