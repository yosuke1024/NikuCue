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
# Optional production texture pack: embed manifest + PNGs as data URIs so the page stays self-contained.
import base64, json as _json
pack_file = RES / "mali_texture_pack.json"
pack_json, images_json = "null", "{}"
if pack_file.exists():
    pack = _json.loads(pack_file.read_text(encoding="utf-8"))
    atlas = ROOT / "NikuCue" / "Resources" / "Assets.xcassets" / f"{pack.get('atlas', 'MaliParts')}.spriteatlas"
    folder = RES / pack["folder"] if pack.get("folder") else atlas
    images = {}
    for part in pack["parts"].values():
        for d in (part["variants"].values() if "variants" in part else [part]):
            png = folder / f"{d['texture']}.png"
            if png.exists():
                images[d["texture"]] = "data:image/png;base64," + base64.b64encode(png.read_bytes()).decode("ascii")
    pack_json, images_json = _json.dumps(pack), _json.dumps(images)
page = (here / "artifact_template.html").read_text(encoding="utf-8")
page = page.replace("__CHARACTER_SPEC__", spec).replace("__MALI_PATHS__", paths).replace("__ANIMATIONS__", anims).replace("__RIG_JS__", rig_js)
page = page.replace("__TEXTURE_PACK__", pack_json).replace("__PACK_IMAGES__", images_json)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(page, encoding="utf-8")
print("wrote", out, f"{out.stat().st_size/1024:.0f} KB")
