#!/usr/bin/env python3
"""Rebuilds low-resolution copies of the Simulator recordings from a saved job log (lines written by
scripts/extract_video_frames.swift). Needs ffmpeg for the .mp4; the JPEG frames are written either way.
Usage: python3 -I scripts/decode_video_frames.py <job-log.txt> <out-dir>
"""
import base64
import re
import shutil
import subprocess
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
out = Path(sys.argv[2])
rates = {m.group(1): float(m.group(2)) for m in re.finditer(r"VIDEO_FRAMES_BEGIN (\S+) fps=([\d.]+)", text)}
counts = {}
for m in re.finditer(r"^(?:\S+Z )?VF (\S+) (\d+) ([\d.]+) (\S+)$", text, re.M):
    name, index = m.group(1), int(m.group(2))
    folder = out / f"{name}_frames"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{index:05d}.jpg").write_bytes(base64.b64decode(m.group(4)))
    counts[name] = counts.get(name, 0) + 1
for name, n in sorted(counts.items()):
    print(f"{name}: {n} frames")
    if shutil.which("ffmpeg"):
        video = out / f"simulator_{name}_lowres.mp4"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(rates.get(name, 4)), "-pattern_type", "glob",
                        "-i", str(out / f"{name}_frames" / "*.jpg"), "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p",
                        "-c:v", "libx264", "-crf", "20", str(video)], check=True)
        print("wrote", video)
