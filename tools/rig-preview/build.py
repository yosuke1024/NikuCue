#!/usr/bin/env python3
"""Inline the JSON contracts and rig.js into a single self-contained preview HTML.
Output: tools/rig-preview/dist/mali-preview.html (git-ignored build output)."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "NikuCue" / "Resources" / "Character"
here = Path(__file__).resolve().parent
html = (here / "index.html").read_text(encoding="utf-8")
html = html.replace("__CHARACTER_SPEC__", (RES / "character_spec.json").read_text(encoding="utf-8"))
html = html.replace("__MALI_PATHS__", (RES / "mali_paths.json").read_text(encoding="utf-8"))
html = html.replace("__ANIMATIONS__", (RES / "animations.json").read_text(encoding="utf-8"))
html = html.replace("__RIG_JS__", (here / "rig.js").read_text(encoding="utf-8").replace("</script", "<\\/script"))
out = here / "dist" / "mali-preview.html"
out.parent.mkdir(exist_ok=True)
out.write_text(html, encoding="utf-8")
print("wrote", out.relative_to(ROOT), f"{out.stat().st_size/1024:.0f} KB")
