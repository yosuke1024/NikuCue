#!/usr/bin/env python3
"""Keyframe tracks for the whole-body texture rig (NikuCue/Resources/Character/mali_wholebody_animations.json).

Same schema as animations.json, but the only animated nodes are bodyPivot/shadow and the "expression" track
carries POSE names (idle/happy/celebrate/pet/sleepy). Motion stays within the asset README limits:
breathing ≤ 1.5 % scale, celebrate = modest lift and return, pet = tiny tilt/scale, no squash, no fake blinks.
Run: python3 tools/character/generate_wholebody_tracks.py
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "spec" / "assets-spec" / "animations.json"
OUT = ROOT / "NikuCue" / "Resources" / "Character" / "mali_wholebody_animations.json"
POSES_PATH = ROOT / "NikuCue" / "Resources" / "Character" / "mali_poses.json"


def kf(*pairs, ease="easeInOut"):
    out = [{"t": p[0], "v": p[1], "ease": p[2] if len(p) == 3 else ease} for p in pairs]
    out[0].pop("ease", None)
    return out


def track(node, prop, *pairs, ease="easeInOut"):
    return {"node": node, "property": prop, "keyframes": kf(*pairs, ease=ease)}


def pose(*pairs):
    return {"node": "pose", "property": "expression", "keyframes": [{"t": t, "v": v} for t, v in pairs]}


# Idle (owner request 2026-10-11): slow, visible breathing within the README's 1.5 % limit and a tail sway on the
# separate tail layer. Breath 3.6 s (inhale 1.7 s / exhale 1.9 s) x4 and sway 4.8 s x3 share a 14.4 s loop so the two
# rhythms drift against each other instead of pulsing in step.
IDLE_MS = 14400
BREATH_MS, SWAY_MS = 3600, 4800


def repeat(period, pairs, total):
    out = []
    for k in range(total // period):
        for t, v, *ease in pairs:
            if k > 0 and t == 0: continue
            out.append((k * period + t, v, *ease))
    return out


TRACKS = {
    "idle": [track("bodyPivot", "scaleY", *repeat(BREATH_MS, [(0, 1.0), (1700, 1.015), (3600, 1.0)], IDLE_MS), ease="sine"),
             track("bodyPivot", "scaleX", *repeat(BREATH_MS, [(0, 1.0), (1700, 0.996), (3600, 1.0)], IDLE_MS), ease="sine"),
             track("tailPivot", "rotation", *repeat(SWAY_MS, [(0, 0), (1200, 5), (3600, -5), (4800, 0)], IDLE_MS), ease="sine")],
    "greet": [pose((0, "happy")),
              track("bodyPivot", "offsetY", (0, 0), (250, 10), (900, 10), (1100, 0)),
              track("bodyPivot", "scale", (0, 1.0), (250, 1.01), (900, 1.01), (1100, 1.0))],
    "pet": [pose((0, "pet")),
            track("bodyPivot", "rotation", (0, 0), (250, 3), (650, 3), (900, 0)),
            track("bodyPivot", "scale", (0, 1.0), (250, 1.02), (650, 1.02), (900, 1.0))],
    "celebrate": [pose((0, "celebrate"), (1300, "happy")),
                  track("bodyPivot", "offsetY", (0, 0), (140, 0, "easeIn"), (420, 34, "easeOut"), (680, 0, "easeIn"), (1600, 0)),
                  track("shadow", "scale", (0, 1.0), (140, 1.0), (420, 0.9, "easeOut"), (680, 1.0, "easeIn"), (1600, 1.0)),
                  track("shadow", "alpha", (0, 1.0), (140, 1.0), (420, 0.7, "easeOut"), (680, 1.0, "easeIn"), (1600, 1.0))],
    "cheer": [pose((0, "happy")),
              track("bodyPivot", "offsetY", (0, 0), (300, 8), (900, 8), (1200, 0))],
    "settle": [pose((0, "idle")),
               track("bodyPivot", "scaleY", (0, 1.0), (500, 0.99), (1300, 1.0))],
    "doze": [track("bodyPivot", "scaleY", (0, 1.0), (1200, 1.01), (3600, 0.994), (4800, 1.0), ease="sine")],
    "milestone": [pose((0, "celebrate"), (1500, "happy")),
                  track("bodyPivot", "offsetY", (0, 0), (150, 0, "easeIn"), (400, 26, "easeOut"), (650, 0, "easeIn"), (800, 0, "easeIn"),
                        (1050, 22, "easeOut"), (1300, 0, "easeIn"), (2200, 0)),
                  track("shadow", "alpha", (0, 1.0), (400, 0.75), (650, 1.0), (1050, 0.78), (1300, 1.0), (2200, 1.0))],
}
REDUCED = {
    "idle": [], "greet": [pose((0, "happy"))], "pet": [pose((0, "pet"))], "celebrate": [pose((0, "celebrate"), (1300, "happy"))],
    "cheer": [pose((0, "happy"))], "settle": [pose((0, "idle"))], "doze": [], "milestone": [pose((0, "celebrate"), (1500, "happy"))],
}
# Heart spawn points sit in the empty corners around the celebrate pose (measured from the texture's alpha:
# left of the head above the raised left paw, right of the ears, and beside the body on the right) and stay
# below the frame top (rootGroundY + above-floor extent + headroom) even after rising.
HEARTS = {"spawnAtMs": [250, 510, 770], "lifeMs": 900, "riseUnits": 80, "max": 3,
          "positions": [[-360, 840], [320, 860], [440, 620]], "scale": 1.8,
          "reducedMotion": {"position": [320, 860], "scale": 1.8}}


def main() -> None:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    poses = json.loads(POSES_PATH.read_text(encoding="utf-8"))
    clip_pose = poses["clipPoses"]
    for clip in data["clips"]:
        cid = clip["id"]
        clip["expression"] = clip_pose[cid]           # pose shown when the clip starts (asset manifest mapping)
        clip["controls"] = ["bodyPivot", "shadow", "pose", "tailPivot"]
        if cid == "idle":
            clip["durationMs"] = IDLE_MS
        clip["tracks"] = TRACKS[cid]
        clip["reducedMotionTracks"] = REDUCED[cid]
        clip["description"] = f"Whole-body texture treatment: {clip.get('description', '')}"
        if cid == "milestone":
            clip["hearts"] = HEARTS
        for tr in clip["tracks"] + clip["reducedMotionTracks"]:
            assert tr["keyframes"][-1]["t"] <= clip["durationMs"], cid
    data["characterId"] = "mali_v1_wholebody"
    data["coordinateUnits"] = "1024-design-units (texture pixels), not display pixels"
    data["ambient"] = {"blink": {"intervalMs": [4000, 7000], "durationMs": 160, "closedScaleY": 0.08, "enabled": False}}
    data["expressionBlendMs"] = 180
    data["trackFormat"] = "same as animations.json; 'expression' tracks carry pose names from mali_poses.json"
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
