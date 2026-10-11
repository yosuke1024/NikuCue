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


# Timing ("間", owner request 2026-10-11: make the rhythm between motions natural).
# Designed by a judge panel of three independent proposals (animation principles / calm real cat / interaction
# rhythm) scored by three judges; all three chose the "principles" design, with agreed grafts. One rhythm runs
# through every reaction: react on the input frame (pose cross-fade), move, smile on a motion beat, speak, linger
# with the final face while breathing resumes, then breathe.
# - lifts rise easeOut and fall easeIn; landings get a short give and a small rebound before settling;
# - holds keep a slow drift or tilt instead of freezing; pose switches sit inside a landing give (never < 500 ms apart);
# - reactions drive only offsetY/rotation/shadow, never the breathing scale or the tail, so starting a reaction never
#   snaps an ambient property (those ease back over the blend instead);
# - the idle loop varies breath length and depth with a short rest after each exhale and a closing sigh; the tail
#   sweeps vary in size, keyframes sit only at sweep ends and rests, and the tail is still for the first second so
#   the idle face fades back in on a quiet tail after any linger;
# - doze: three slow breaths (one a sigh), no tilt (every reaction drives rotation and would snap it on waking).
# Limits (scripts/check_resources.py): docs/04 durations ±20 %, scale within 0.97-1.03 (breathing <= 1.5 %), rotation
# <= 5° (tail <= 5° as checked on tail_split_check.png), lift <= 40 / dip >= -6 units, tracks end at rest,
# cross-fade 120-220 ms, hearts end inside the clip.
EXPRESSION_BLEND_MS = 180
REACTION_GAP_MS = 400        # never longer than the shortest linger: the controller holds max(linger, gap)

# Per clip: duration (docs/04 ±20 %), linger of the last face after the clip, bubble delay after the clip starts.
CLIP_TIMING = {
    "greet": {"durationMs": 1200, "lingerMs": 600, "messageAtMs": 400},       # docs/04 1100 (+9 %)
    "pet": {"durationMs": 1000, "lingerMs": 400, "messageAtMs": 280},         # 900 (+11 %); face ends < 2000 ms cooldown
    "celebrate": {"durationMs": 1600, "lingerMs": 600, "messageAtMs": 900},   # 1600; speaks after the smile
    "cheer": {"durationMs": 1300, "lingerMs": 500, "messageAtMs": 450},       # 1200 (+8 %)
    "settle": {"durationMs": 1400, "lingerMs": 600, "messageAtMs": 450},      # 1300 (+8 %); idle face, so no visible linger
    "milestone": {"durationMs": 2300, "lingerMs": 700, "messageAtMs": 1300},  # 2200 (+4.5 %); speaks after the smile
}

# Idle: four breaths 3400/3900/3300/3800 ms (average 3600), peaks 1.011/1.014/1.010/1.012, a 400 ms rest after each
# exhale and a sigh to 0.997 closing the loop. scaleX counters at about a quarter of the scaleY change.
IDLE_SCALE_Y = [(0, 1.0), (1400, 1.011), (3000, 1.0), (3400, 1.0), (5050, 1.014), (6900, 1.0), (7300, 1.0),
                (8600, 1.010), (10200, 1.0), (10600, 1.0), (12100, 1.012), (13950, 0.997), (14400, 1.0)]
IDLE_SCALE_X = [(0, 1.0), (1400, 0.997), (3000, 1.0), (3400, 1.0), (5050, 0.9962), (6900, 1.0), (7300, 1.0),
                (8600, 0.9973), (10200, 1.0), (10600, 1.0), (12100, 0.9968), (13950, 1.0008), (14400, 1.0)]
IDLE_TAIL = [(0, 0), (1000, 0), (2400, 4.5), (4300, -3.5), (5400, 1.0), (6400, 1.0), (7900, -5.0), (9700, 3.5),
             (10900, -1.0), (12100, -1.0), (13300, 3.0), (14400, 0)]
# Doze: breaths 4700/5400/4300 ms (average 4800); the middle one is a sigh. scaleX = 1 - 0.25 * (scaleY - 1).
DOZE_SCALE_Y = [(0, 1.0), (1800, 1.010), (4200, 1.0), (4700, 1.0), (6800, 1.013), (9600, 0.997), (10100, 1.0),
                (11800, 1.009), (13900, 1.0), (14400, 1.0)]
DOZE_SCALE_X = [(t, round(1 - 0.25 * (v - 1), 5)) for t, v in DOZE_SCALE_Y]
IDLE_MS = IDLE_SCALE_Y[-1][0]
DOZE_MS = DOZE_SCALE_Y[-1][0]
assert IDLE_MS == IDLE_TAIL[-1][0] == IDLE_SCALE_X[-1][0], "idle breath and tail loops must share one length"

TRACKS = {
    "idle": [track("bodyPivot", "scaleY", *IDLE_SCALE_Y, ease="sine"),
             track("bodyPivot", "scaleX", *IDLE_SCALE_X, ease="sine"),
             track("tailPivot", "rotation", *IDLE_TAIL, ease="sine")],
    # greet: perk up and look at you, two slow rocks (the paw wave of docs/04 as a whole-body sway), settle
    "greet": [pose((0, "happy")),
              track("bodyPivot", "offsetY", (0, 0), (380, 12, "easeOut"), (620, 10.5, "sine"), (860, 12, "sine"),
                    (1060, -2, "easeInOut"), (1200, 0, "sine")),
              track("bodyPivot", "rotation", (0, 0), (380, 0, "linear"), (600, 1.4, "sine"), (860, -1.0, "sine"),
                    (1080, 0, "sine"), (1200, 0, "linear")),
              track("shadow", "scale", (0, 1.0), (380, 0.97, "easeOut"), (860, 0.975, "sine"), (1060, 1.0, "easeInOut"),
                    (1200, 1.0, "linear")),
              track("shadow", "alpha", (0, 1.0), (380, 0.9, "easeOut"), (860, 0.92, "sine"), (1060, 1.0, "easeInOut"),
                    (1200, 1.0, "linear"))],
    # pet: no anticipation (the touch is the cue): lean into the hand at once, one nuzzle, ease out with a sigh
    "pet": [pose((0, "pet")),
            track("bodyPivot", "rotation", (0, 0), (240, 3.5, "easeOut"), (420, 2.5, "sine"), (600, 3.4, "sine"),
                  (880, -0.5, "easeInOut"), (1000, 0, "sine")),
            track("bodyPivot", "offsetY", (0, 0), (240, 3, "easeOut"), (420, 2, "sine"), (600, 3, "sine"),
                  (880, -1, "easeInOut"), (1000, 0, "sine"))],
    # celebrate: crouch, hop, soft landing; the smile arrives inside the landing give; a small happy tilt; speak at 900
    "celebrate": [pose((0, "celebrate"), (700, "happy")),
                  track("bodyPivot", "offsetY", (0, 0), (150, -5, "easeInOut"), (420, 32, "easeOut"), (660, 0, "easeIn"),
                        (760, -4, "easeOut"), (960, 1.5, "easeInOut"), (1150, 0, "sine"), (1600, 0, "linear")),
                  track("bodyPivot", "rotation", (0, 0), (1000, 0, "linear"), (1300, 1.2, "sine"), (1600, 0, "sine")),
                  track("shadow", "scale", (0, 1.0), (150, 1.03, "easeInOut"), (420, 0.88, "easeOut"), (660, 1.0, "easeIn"),
                        (760, 1.03, "easeOut"), (960, 1.0, "easeInOut"), (1600, 1.0, "linear")),
                  track("shadow", "alpha", (0, 1.0), (150, 1.0, "linear"), (420, 0.7, "easeOut"), (660, 1.0, "easeIn"),
                        (1600, 1.0, "linear"))],
    # cheer: a gentle rise and an attentive tilt, no bounce (never urging)
    "cheer": [pose((0, "happy")),
              track("bodyPivot", "offsetY", (0, 0), (420, 9, "easeOut"), (900, 8, "sine"), (1150, -1.5, "easeInOut"),
                    (1300, 0, "sine")),
              track("bodyPivot", "rotation", (0, 0), (300, 0, "linear"), (640, 1.8, "sine"), (900, 1.4, "sine"),
                    (1180, -0.3, "easeInOut"), (1300, 0, "sine"))],
    # settle: a small lift on the first frame, then a long exhale (sink and lean), back to rest; tail and breath ease out
    "settle": [pose((0, "idle")),
               track("bodyPivot", "offsetY", (0, 0), (380, 3, "easeOut"), (1000, -4, "sine"), (1400, 0, "sine")),
               track("bodyPivot", "rotation", (0, 0), (600, -1.2, "easeOut"), (1400, 0, "sine")),
               track("shadow", "scale", (0, 1.0), (380, 0.98, "easeOut"), (1000, 1.03, "sine"), (1400, 1.0, "sine"))],
    "doze": [track("bodyPivot", "scaleY", *DOZE_SCALE_Y, ease="sine"),
             track("bodyPivot", "scaleX", *DOZE_SCALE_X, ease="sine")],
    # milestone: two beats of joy, the second one bigger; the smile inside the second landing give; speak at 1300
    "milestone": [pose((0, "celebrate"), (1260, "happy")),
                  track("bodyPivot", "offsetY", (0, 0), (140, -4, "easeInOut"), (380, 22, "easeOut"), (580, 0, "easeIn"),
                        (680, -5, "easeOut"), (960, 34, "easeOut"), (1220, 0, "easeIn"), (1320, -4, "easeOut"),
                        (1540, 1.5, "easeInOut"), (1740, 0, "sine"), (2300, 0, "linear")),
                  track("bodyPivot", "rotation", (0, 0), (1700, 0, "linear"), (2020, 1.5, "sine"), (2300, 0, "sine")),
                  track("shadow", "scale", (0, 1.0), (140, 1.02, "easeInOut"), (380, 0.92, "easeOut"), (580, 1.0, "easeIn"),
                        (680, 1.03, "easeOut"), (960, 0.88, "easeOut"), (1220, 1.0, "easeIn"), (1320, 1.03, "easeOut"),
                        (1540, 1.0, "easeInOut"), (2300, 1.0, "linear")),
                  track("shadow", "alpha", (0, 1.0), (140, 1.0, "linear"), (380, 0.8, "easeOut"), (580, 1.0, "easeIn"),
                        (680, 1.0, "linear"), (960, 0.7, "easeOut"), (1220, 1.0, "easeIn"), (2300, 1.0, "linear"))],
}
REDUCED = {
    "idle": [], "greet": [pose((0, "happy"))], "pet": [pose((0, "pet"))], "celebrate": [pose((0, "celebrate"), (700, "happy"))],
    "cheer": [pose((0, "happy"))], "settle": [pose((0, "idle"))], "doze": [], "milestone": [pose((0, "celebrate"), (1260, "happy"))],
}
# Heart spawn points sit in the empty corners around the celebrate pose (measured from the texture's alpha) and stay
# below the frame top even after rising. They pop on the beats: just before the first apex, on the first landing,
# just before the second (bigger) apex, and all are gone before the clip ends.
HEARTS = {"spawnAtMs": [330, 600, 920], "lifeMs": 1000, "riseUnits": 80, "max": 3,
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
        for stale in ("timeline", "note"):          # docs/04 parts-rig timing notes no longer describe these tracks
            clip.pop(stale, None)
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
