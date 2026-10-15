#!/usr/bin/env python3
"""Extracts REVIEW_FRAME blocks from a saved GitHub Actions job log into JPEG files.
Usage: python3 -I scripts/decode_review_frames.py <job-log.txt> <out-dir>
"""
import base64
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
for m in re.finditer(r"REVIEW_FRAME_BEGIN (\S+) \S+\n(.*?)REVIEW_FRAME_END", text, re.S):
    lines = [re.sub(r"^\S+Z ", "", line).strip() for line in m.group(2).splitlines()]
    data = base64.b64decode("".join(lines))
    (out / (Path(m.group(1)).stem + ".jpg")).write_bytes(data)
    print("wrote", out / (Path(m.group(1)).stem + ".jpg"))
