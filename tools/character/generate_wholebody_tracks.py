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


# Timing ("間", owner request 2026-10-11: make the rhythm between motions natural). Principles used throughout:
# - a small anticipation dip before every lift, slow-in/slow-out, a soft landing with a tiny rebound;
# - holds keep breathing (a gentle bob) instead of freezing; pose switches sit on motion beats, never < 500 ms apart;
# - after a reaction the face lingers while breathing resumes (lingerMs), the bubble follows the motion (messageAtMs),
#   and a queued reaction waits a short beat (REACTION_GAP_MS);
# - the idle loop varies breath length/depth and tail sweeps (with rests), so it is not a metronome.
# Limits (scripts/check_resources.py): docs/04 durations ±20 %, scale within 0.97-1.03 (breathing <= 1.5 %), rotation
# <= 5° (tail <= 8°), lift <= 40 / dip >= -8 units, every track ends at rest, cross-fade 120-220 ms.
EXPRESSION_BLEND_MS = 180
REACTION_GAP_MS = 350

# Idle: four breaths (period ms, peak scaleY, scaleX at peak) = 14.4 s; inhale 40 %, exhale 45 %, rest 15 %.
IDLE_BREATHS = [(3500, 1.013, 0.997), (3800, 1.015, 0.996), (3400, 1.011, 0.997), (3700, 1.014, 0.996)]
# Tail: slow sweeps of varying size with a rest and one small flick, same loop length.
IDLE_TAIL = [(0, 0), (1300, 4.5), (2900, -3.0), (3700, -1.0), (4800, -1.0), (6000, 5.0), (7600, -4.5), (8800, 0.5),
             (10200, 0.5), (11000, 3.5), (11400, 2.2), (12300, -3.5), (13400, -1.0), (14400, 0)]
# Doze: two slow breaths (period, peak) = 9.6 s; inhale 45 %, exhale 45 %, rest 10 %.
DOZE_BREATHS = [(4600, 1.010), (5000, 1.008)]

# Per clip: duration, linger after the clip, bubble delay.
CLIP_TIMING = {
    "greet": {"durationMs": 1200, "lingerMs": 700, "messageAtMs": 250},
    "pet": {"durationMs": 1000, "lingerMs": 900, "messageAtMs": 200},
    "celebrate": {"durationMs": 1700, "lingerMs": 800, "messageAtMs": 600},
    "cheer": {"durationMs": 1300, "lingerMs": 600, "messageAtMs": 300},
    "settle": {"durationMs": 1500, "lingerMs": 0, "messageAtMs": 300},
    "milestone": {"durationMs": 2400, "lingerMs": 900, "messageAtMs": 400},
}


def breaths(cycles, inhale=0.40, exhale=0.45, x=False):
    """Keyframes for a breathing loop: rise (sine), fall (sine), rest at 1.0 (linear hold)."""
    out, t = [(0, 1.0)], 0
    for period, peak, *rest in cycles:
        top = rest[0] if x else peak
        out += [(t + round(period * inhale), top, "sine"), (t + round(period * (inhale + exhale)), 1.0, "sine"),
                (t + period, 1.0, "linear")]
        t += period
    return out, t


IDLE_SCALE_Y, IDLE_MS = breaths(IDLE_BREATHS)
IDLE_SCALE_X, _ = breaths(IDLE_BREATHS, x=True)
DOZE_SCALE_Y, DOZE_MS = breaths(DOZE_BREATHS, inhale=0.45, exhale=0.45)
assert IDLE_MS == IDLE_TAIL[-1][0], "idle breath and tail loops must share one length"

TRACKS = {
    "idle": [track("bodyPivot", "scaleY", *IDLE_SCALE_Y, ease="sine"),
             track("bodyPivot", "scaleX", *IDLE_SCALE_X, ease="sine"),
             track("tailPivot", "rotation", *IDLE_TAIL, ease="sine")],
    # greet: small dip, rise to look up, a breathing hold, settle
    "greet": [pose((0, "happy")),
              track("bodyPivot", "offsetY", (0, 0), (120, -3, "easeOut"), (420, 12, "easeOut"), (620, 9, "easeInOut"),
                    (880, 11, "sine"), (1200, 0, "easeInOut")),
              track("bodyPivot", "scale", (0, 1.0), (420, 1.012, "easeOut"), (880, 1.01, "sine"), (1200, 1.0, "easeInOut"))],
    # pet: lean into the hand, nestle, ease back out
    "pet": [pose((0, "pet")),
            track("bodyPivot", "rotation", (0, 0), (300, 3.2, "easeOut"), (700, 2.6, "sine"), (1000, 0, "easeInOut")),
            track("bodyPivot", "scale", (0, 1.0), (300, 1.018, "easeOut"), (700, 1.014, "sine"), (1000, 1.0, "easeInOut"))],
    # celebrate: crouch, hop, soft landing with a tiny rebound; the happy face arrives on the settle and bobs
    "celebrate": [pose((0, "celebrate"), (900, "happy")),
                  track("bodyPivot", "offsetY", (0, 0), (120, -5, "easeOut"), (400, 34, "easeOut"), (620, 0, "easeIn"),
                        (720, -3, "easeOut"), (860, 2, "easeOut"), (1000, 0, "easeInOut"), (1350, 3, "sine"), (1700, 0, "sine")),
                  track("shadow", "scale", (0, 1.0), (120, 1.02, "easeOut"), (400, 0.88, "easeOut"), (620, 1.0, "easeIn"),
                        (720, 1.02, "easeOut"), (1000, 1.0, "easeInOut"), (1700, 1.0)),
                  track("shadow", "alpha", (0, 1.0), (400, 0.7, "easeOut"), (620, 1.0, "easeIn"), (1700, 1.0))],
    # cheer: small dip, gentle rise, a soft bob while attentive, settle (never urging)
    "cheer": [pose((0, "happy")),
              track("bodyPivot", "offsetY", (0, 0), (150, -2, "easeOut"), (450, 8, "easeOut"), (800, 6, "sine"),
                    (1050, 8, "sine"), (1300, 0, "easeInOut"))],
    # settle: a long exhale (shoulders drop), the tail lowers and comes back slowly
    "settle": [pose((0, "idle")),
               track("bodyPivot", "scaleY", (0, 1.0), (600, 0.988, "easeInOut"), (1500, 1.0, "sine")),
               track("bodyPivot", "offsetY", (0, 0), (600, -2, "easeInOut"), (1500, 0, "sine")),
               track("tailPivot", "rotation", (0, 0), (700, -4, "easeInOut"), (1500, 0, "sine"))],
    "doze": [track("bodyPivot", "scaleY", *DOZE_SCALE_Y, ease="sine")],
    # milestone: two hops (the second smaller), each with a crouch and a soft landing, then a happy bob
    "milestone": [pose((0, "celebrate"), (1500, "happy")),
                  track("bodyPivot", "offsetY", (0, 0), (120, -4, "easeOut"), (380, 28, "easeOut"), (600, 0, "easeIn"),
                        (700, -2, "easeOut"), (820, 0, "easeOut"), (1050, 22, "easeOut"), (1270, 0, "easeIn"),
                        (1370, -2, "easeOut"), (1500, 0, "easeOut"), (1950, 3, "sine"), (2400, 0, "sine")),
                  track("shadow", "alpha", (0, 1.0), (380, 0.75, "easeOut"), (600, 1.0, "easeIn"), (1050, 0.78, "easeOut"),
                        (1270, 1.0, "easeIn"), (2400, 1.0))],
}
REDUCED = {
    "idle": [], "greet": [pose((0, "happy"))], "pet": [pose((0, "pet"))], "celebrate": [pose((0, "celebrate"), (900, "happy"))],
    "cheer": [pose((0, "happy"))], "settle": [pose((0, "idle"))], "doze": [], "milestone": [pose((0, "celebrate"), (1500, "happy"))],
}
# Heart spawn points sit in the empty corners around the celebrate pose (measured from the texture's alpha) and stay
# below the frame top even after rising; they pop on the hops (first peak, first landing, second peak).
HEARTS = {"spawnAtMs": [380, 650, 1050], "lifeMs": 1000, "riseUnits": 80, "max": 3,
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
        elif cid == "doze":
            clip["durationMs"] = DOZE_MS
        else:
            clip.update(CLIP_TIMING[cid])
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
    data["expressionBlendMs"] = EXPRESSION_BLEND_MS
    data["reactionGapMs"] = REACTION_GAP_MS
    data["trackFormat"] = "same as animations.json; 'expression' tracks carry pose names from mali_poses.json"
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
