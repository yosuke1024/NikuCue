#!/usr/bin/env python3
"""Builds the shareable review page (claude.ai artifact format: body-only HTML with <title>/<style>
at the top, theme tokens, no external resources). Output goes to the path given as argv[1]."""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "NikuCue" / "Resources" / "Character"
here = Path(__file__).resolve().parent
out = Path(sys.argv[1])
rig_js = (here / "rig.js").read_text(encoding="utf-8").replace("</script", "<\\/script")
spec = (RES / "character_spec.json").read_text(encoding="utf-8")
paths = (RES / "mali_paths.json").read_text(encoding="utf-8")
anims = (RES / "animations.json").read_text(encoding="utf-8")
page = (here / "artifact_template.html").read_text(encoding="utf-8")
page = page.replace("__CHARACTER_SPEC__", spec).replace("__MALI_PATHS__", paths).replace("__ANIMATIONS__", anims).replace("__RIG_JS__", rig_js)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(page, encoding="utf-8")
print("wrote", out, f"{out.stat().st_size/1024:.0f} KB")
