#!/usr/bin/env python3
"""Prints a few Simulator screenshots as small base64 JPEGs between markers, so a reviewer who can read the job
log but not download artifacts can still see what the Simulator showed (decode with scripts/decode_review_frames.py).
Usage: python3 -I scripts/review_frames.py <ci-results-dir>
"""
import base64
import io
import sys
from pathlib import Path

from PIL import Image

folder = Path(sys.argv[1])
for name in ["autonomous_t30s.png", "interaction_t30s.png", "flipbook_t30s.png", "reducedMotion_t30s.png"]:
    p = folder / name
    if not p.exists():
        continue
    im = Image.open(p).convert("RGB")
    im.thumbnail((360, 780))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=62, optimize=True)
    print(f"REVIEW_FRAME_BEGIN {name} {im.size[0]}x{im.size[1]}")
    data = base64.b64encode(buf.getvalue()).decode()
    for i in range(0, len(data), 4000):
        print(data[i:i + 4000])
    print(f"REVIEW_FRAME_END {name}")
