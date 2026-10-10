#!/usr/bin/env python3
"""Adds explicit keyframe tracks to the bundled animations.json.

Input : spec/assets-spec/animations.json (pack contract: ids, durations, controls,
        reducedMotion intent, celebrate timeline)
Output: NikuCue/Resources/Character/animations.json (same clips + `tracks`,
        `reducedMotionTracks`, `ambient.blink`)

Track format (consumed by Character/AnimationLibrary.swift and tools/rig-preview/rig.js):
  { "node": "<rig node id>", "property": "<rotation|offsetX|offsetY|scaleX|scaleY|scale|alpha|expression>",
    "keyframes": [ { "t": ms, "v": value, "ease": "easeInOut|easeIn|easeOut|sine|linear" }, ... ] }
  rotation: degrees added to the rest rotation (counter-clockwise positive, SpriteKit convention)
  offsetX/Y: design units added to the rest position
  scaleX/Y/scale: multiplied with the rest scale (1 = rest)
  alpha: multiplied with the rest alpha
  expression: string, switched with a short crossfade (node "face")
Numbers are the docs/04 §4 starting values; ±20 % tuning is allowed and should be recorded.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "spec" / "assets-spec" / "animations.json"
OUT = ROOT / "NikuCue" / "Resources" / "Character" / "animations.json"


def kf(*pairs, ease="easeInOut"):
    out = []
    for p in pairs:
        if len(p) == 3:
            out.append({"t": p[0], "v": p[1], "ease": p[2]})
        else:
            out.append({"t": p[0], "v": p[1], "ease": ease})
    out[0].pop("ease", None)
    return out


def track(node, prop, *pairs, ease="easeInOut"):
    return {"node": node, "property": prop, "keyframes": kf(*pairs, ease=ease)}


def expr(*pairs):
    return {"node": "face", "property": "expression", "keyframes": [{"t": t, "v": v} for t, v in pairs]}


TRACKS = {
    "idle": [
        track("bodyPivot", "scaleY", (0, 1.0), (900, 1.01), (2700, 0.99), (3600, 1.0), ease="sine"),
        track("headPivot", "offsetY", (0, 0), (900, 3), (2700, -3), (3600, 0), ease="sine"),
        track("tailPivot", "rotation", (0, 0), (900, 5), (2700, -5), (3600, 0), ease="sine"),
    ],
    "greet": [
        expr((0, "softSmile")),
        track("headPivot", "offsetY", (0, 0), (250, 12), (900, 12), (1100, 0)),
        track("headPivot", "rotation", (0, 0), (250, -3), (900, -3), (1100, 0)),
        track("forePawRPivot", "rotation", (0, 0), (180, 26), (330, 12), (480, 26), (640, 12), (820, 0), (1100, 0)),
        track("forePawRPivot", "offsetY", (0, 0), (180, 8), (820, 8), (1100, 0)),
    ],
    "pet": [
        expr((0, "closedHappy")),
        track("headPivot", "rotation", (0, 0), (250, 7), (650, 7), (900, 0)),
        track("headPivot", "offsetX", (0, 0), (250, 6), (650, 6), (900, 0)),
        track("headPivot", "offsetY", (0, 0), (250, -4), (650, -4), (900, 0)),
        track("tailPivot", "rotation", (0, 0), (300, 9), (700, 9), (900, 0)),
    ],
    "celebrate": [
        expr((0, "softSmile"), (680, "closedHappy"), (1250, "softSmile")),
        track("bodyPivot", "scaleX", (0, 1.0), (140, 1.03, "easeOut"), (420, 1.0, "easeOut"), (680, 1.035, "easeIn"), (1050, 1.0), (1600, 1.0)),
        track("bodyPivot", "scaleY", (0, 1.0), (140, 0.96, "easeOut"), (420, 1.025, "easeOut"), (680, 0.96, "easeIn"), (1050, 1.0), (1600, 1.0)),
        track("bodyPivot", "offsetY", (0, 0), (140, 0, "easeIn"), (420, 34, "easeOut"), (680, 0, "easeIn"), (1600, 0)),
        track("headPivot", "offsetY", (0, 0), (140, -8, "easeOut"), (420, 6, "easeOut"), (680, -6, "easeIn"), (1050, 0), (1600, 0)),
        track("headPivot", "rotation", (0, 0), (680, 0), (1050, 5), (1600, 0)),
        track("forePawLPivot", "rotation", (0, 0), (140, 0), (420, -18, "easeOut"), (680, 0, "easeIn"), (1600, 0)),
        track("forePawRPivot", "rotation", (0, 0), (140, 0), (420, 18, "easeOut"), (680, 0, "easeIn"), (1600, 0)),
        track("tailPivot", "rotation", (0, 0), (1050, 0), (1200, 10), (1400, -8), (1600, 0)),
        track("shadow", "scale", (0, 1.0), (140, 1.02), (420, 0.88, "easeOut"), (680, 1.02, "easeIn"), (900, 1.0), (1600, 1.0)),
        track("shadow", "alpha", (0, 1.0), (140, 1.0), (420, 0.7, "easeOut"), (680, 1.0, "easeIn"), (1600, 1.0)),
    ],
    "cheer": [
        expr((0, "curious")),
        track("headPivot", "offsetY", (0, 0), (300, 8), (900, 8), (1200, 0)),
        track("forePawLPivot", "rotation", (0, 0), (350, 14), (850, 14), (1200, 0)),
        track("forePawLPivot", "offsetY", (0, 0), (350, 30), (850, 30), (1200, 0)),
        track("forePawLPivot", "scaleY", (0, 1.0), (350, 0.7), (850, 0.7), (1200, 1.0)),
        track("forePawRPivot", "rotation", (0, 0), (350, -14), (850, -14), (1200, 0)),
        track("forePawRPivot", "offsetY", (0, 0), (350, 30), (850, 30), (1200, 0)),
        track("forePawRPivot", "scaleY", (0, 1.0), (350, 0.7), (850, 0.7), (1200, 1.0)),
    ],
    "settle": [
        expr((0, "softSmile")),
        track("eyeL", "scaleY", (0, 1.0), (350, 0.08, "easeIn"), (700, 0.08), (1000, 1.0, "easeOut"), (1300, 1.0)),
        track("eyeR", "scaleY", (0, 1.0), (350, 0.08, "easeIn"), (700, 0.08), (1000, 1.0, "easeOut"), (1300, 1.0)),
        track("bodyPivot", "scaleY", (0, 1.0), (500, 0.985), (1300, 1.0)),
        track("headPivot", "offsetY", (0, 0), (500, -8), (1300, 0)),
    ],
    "doze": [
        track("bodyPivot", "scaleY", (0, 1.0), (1200, 1.01), (3600, 0.99), (4800, 1.0), ease="sine"),
        track("headPivot", "offsetY", (0, -14), (4800, -14)),
        track("headPivot", "rotation", (0, 3), (4800, 3)),
    ],
    "milestone": [
        expr((0, "softSmile"), (400, "closedHappy")),
        track("bodyPivot", "offsetY", (0, 0), (150, 0, "easeIn"), (400, 26, "easeOut"), (650, 0, "easeIn"), (800, 0, "easeIn"), (1050, 22, "easeOut"), (1300, 0, "easeIn"), (2200, 0)),
        track("bodyPivot", "scaleY", (0, 1.0), (150, 0.96), (400, 1.02), (650, 0.97), (800, 0.97), (1050, 1.02), (1300, 0.97), (1500, 1.0), (2200, 1.0)),
        track("bodyPivot", "scaleX", (0, 1.0), (150, 1.03), (400, 1.0), (650, 1.03), (800, 1.03), (1050, 1.0), (1300, 1.03), (1500, 1.0), (2200, 1.0)),
        track("headPivot", "rotation", (0, 0), (400, -4), (1050, 4), (1500, 0), (2200, 0)),
        track("forePawLPivot", "rotation", (0, 0), (400, -14), (650, 0), (1050, -14), (1300, 0), (2200, 0)),
        track("forePawRPivot", "rotation", (0, 0), (400, 14), (650, 0), (1050, 14), (1300, 0), (2200, 0)),
        track("tailPivot", "rotation", (0, 0), (1300, 0), (1500, 10), (1700, -10), (1900, 8), (2200, 0)),
    ],
}

REDUCED = {
    "idle": [],
    "greet": [expr((0, "softSmile"))],
    "pet": [expr((0, "closedHappy"))],
    "celebrate": [expr((0, "softSmile"), (300, "closedHappy"))],
    "cheer": [expr((0, "curious"))],
    "settle": [expr((0, "softSmile"))],
    "doze": [track("headPivot", "offsetY", (0, -14), (4800, -14)), track("headPivot", "rotation", (0, 3), (4800, 3))],
    "milestone": [expr((0, "closedHappy"))],
}

# Hearts: positions are design-unit offsets from the rig root (ground centre); they float
# beside/above the head, never over the face. Reduce Motion shows one static heart.
HEARTS = {"spawnAtMs": [250, 510, 770], "lifeMs": 900, "riseUnits": 90, "max": 3,
          "positions": [[-268, 600], [0, 760], [268, 600]], "scale": 1.3,
          "reducedMotion": {"position": [268, 600], "scale": 1.3}}


def main() -> None:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    for clip in data["clips"]:
        cid = clip["id"]
        clip["tracks"] = TRACKS[cid]
        clip["reducedMotionTracks"] = REDUCED[cid]
        for tr in clip["tracks"] + clip["reducedMotionTracks"]:
            assert tr["keyframes"][-1]["t"] <= clip["durationMs"], f"{cid}: track exceeds duration"
            allowed = set(clip["controls"]) | {"face"}
            assert tr["node"] in allowed, f"{cid}: node {tr['node']} not in controls"
        if cid == "milestone":
            clip["hearts"] = HEARTS
    data["ambient"] = {"blink": {"intervalMs": [4000, 7000], "durationMs": 160, "closedScaleY": 0.08}}
    data["expressionBlendMs"] = 100
    data["trackFormat"] = ("keyframes per node/property; rotation=deg added to rest, offsetX/Y=design units added to rest, "
                           "scale*=multiplied with rest, alpha=multiplied, expression=string on node 'face'")
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
