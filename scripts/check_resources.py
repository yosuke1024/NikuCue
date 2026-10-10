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
        require(langs[c] == load(SPEC / "localization" / f"{c}.json"), f"localization/{c}.json drifted from spec/")
    keys = set(langs["en"])
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

    # 6. reactions reference existing clips and strings
    clip_ids = {c["id"] for c in anims["clips"]}
    for r in reactions["items"]:
        require(r["clipId"] in clip_ids, f"reaction {r['id']}: unknown clip")
        require(set(r["messageKeys"]) <= keys, f"reaction {r['id']}: unknown message keys")

    print(json.dumps({"status": "PASS", "scope": "bundled resource contracts only; not an iOS build",
                      "localizationKeys": len(keys), "rigNodes": len(nodes), "clips": len(anims["clips"]),
                      "artParts": len(parts), "reactions": len(reactions["items"])}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, TypeError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
