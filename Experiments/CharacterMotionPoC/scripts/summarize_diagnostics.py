#!/usr/bin/env python3
"""Summarizes MotionLab / browser-harness diagnostics JSON files into a Markdown table.

    python3 -I scripts/summarize_diagnostics.py <dir-with-diagnostics-*.json> [--height 686.2]

Foot slide is reported in stage units and as a share of the character height (spineboy: 686.2 units).
Standard library only.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path


def fmt(v: float, digits: int = 1) -> str:
    return f"{v:.{digits}f}"


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    folder = Path(args[0])
    height = float(args[args.index("--height") + 1]) if "--height" in args else 686.2
    files = sorted(folder.glob("diagnostics-*.json"))
    if not files:
        print(f"no diagnostics in {folder}")
        sys.exit(1)
    rows = []
    for f in files:
        d = json.loads(f.read_text())
        extra = d.get("extra", {})
        slide = d.get("footSlide", {})
        walk = slide.get("walk", {})
        blends = {k: v for k, v in slide.items() if k.startswith("blend")}
        blend = max(blends.values(), key=lambda v: v.get("maxOccurrence", 0), default={})
        turn = slide.get("turn", {})
        stand = slide.get("stand", {})
        mem = d.get("memoryMB", {})
        fi = d.get("frameInterval", {})
        lat = d.get("stimulusLatency", {})
        lat_all = sorted(x for v in lat.values() for x in v)
        rows.append({
            "file": f.name,
            "scenario": extra.get("scenario", "?"),
            "renderer": extra.get("renderer", "?"),
            "reduce": f"{extra.get('reduceMotion', '?')} (system {extra.get('systemReduceMotion', '?')})",
            "frames": d.get("frames", 0),
            "fps": f"{1 / fi['median']:.0f}" if fi.get("median") else "-",
            "p95ms": fmt(fi.get("p95", 0) * 1000),
            "walkSlide": f"{fmt(walk.get('maxRunDrift', 0))} ({fmt(100 * walk.get('maxRunDrift', 0) / height, 2)}%)",
            "walkOcc": fmt(walk.get("maxOccurrence", 0)),
            "walkStep": fmt(walk.get("maxStep", 0), 2),
            "blendSlide": fmt(blend.get("maxOccurrence", 0)),
            "turnSlide": fmt(turn.get("maxOccurrence", 0)),
            "standSlide": fmt(stand.get("maxRunDrift", 0), 2),
            "rootStep": fmt(d.get("maxRootStep", 0), 2),
            "flips": d.get("facingFlipsOutsideTurn", 0),
            "drift": fmt(d.get("maxClipDriftWalking", 0) * 1000, 2),
            "mem": f"{fmt(mem.get('min', 0))}–{fmt(mem.get('max', 0))}",
            "activities": ", ".join(f"{k}×{v}" for k, v in sorted(d.get("activities", {}).items())),
            "latency": f"{lat_all[len(lat_all) // 2]:.2f}/{lat_all[-1]:.2f}" if lat_all else "-",
            "lifecycle": d.get("lifecycle", []),
            "blends": blends,
        })
    print("| scenario | renderer | Reduce Motion | frames | fps (median) | frame p95 ms | walk foot drift per stance max (units, % height) | walk max step | worst blend (total slide) | worst turn (total slide) | standing slide | max root step | facing flips outside turn | clip drift ms | memory MB | reaction latency median/max s |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        print(f"| {r['scenario']} | {r['renderer']} | {r['reduce']} | {r['frames']} | {r['fps']} | {r['p95ms']} | {r['walkSlide']} | {r['walkStep']} | {r['blendSlide']} | {r['turnSlide']} | {r['standSlide']} | {r['rootStep']} | {r['flips']} | {r['drift']} | {r['mem']} | {r['latency']} |")
    print()
    print()
    print("Foot slide during clip blends (stage units; occurrence = one blend, total grounded-foot movement of both feet):")
    print()
    print("| scenario | renderer | transition | grounded frames | max step | worst occurrence (total slide) | mean per frame |")
    print("|---|---|---|---|---|---|---|")
    for r in rows:
        for k, v in sorted(r["blends"].items(), key=lambda kv: -kv[1].get("maxOccurrence", 0)):
            print(f"| {r['scenario']} | {r['renderer']} | {k[6:]} | {v.get('frames', 0)} | {fmt(v.get('maxStep', 0), 2)} | {fmt(v.get('maxOccurrence', 0))} | {fmt(v.get('meanPerFrame', 0), 2)} |")
    print()
    for r in rows:
        print(f"- **{r['scenario']} / {r['renderer']}** activities: {r['activities'] or '-'}")
        for ev in r["lifecycle"]:
            print(f"  - lifecycle {ev.get('phase')}: engineTime={ev.get('engineTime')} x={ev.get('x')} paused={ev.get('paused')} wall={ev.get('wallClock')}")


if __name__ == "__main__":
    main()
