#!/usr/bin/env python3
"""Inline the JSON contracts and rig.js into a single self-contained preview HTML.
Output: tools/rig-preview/dist/mali-preview.html (git-ignored build output)."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "NikuCue" / "Resources" / "Character"
here = Path(__file__).resolve().parent
spec = (RES / "character_spec.json").read_text(encoding="utf-8")
anims = (RES / "animations.json").read_text(encoding="utf-8")
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

# Whole-body pose textures (owner-supplied) take precedence over the layered pack and the placeholder.
poses_file = RES / "mali_poses.json"
if poses_file.exists():
    poses = _json.loads(poses_file.read_text(encoding="utf-8"))
    spec = (RES / "mali_wholebody_spec.json").read_text(encoding="utf-8")
    anims = (RES / "mali_wholebody_animations.json").read_text(encoding="utf-8")
    catalog = ROOT / "NikuCue" / "Resources" / "Assets.xcassets" / "Mali"
    parts, images = {"pose": {"variants": {}}}, {}
    def embed(image_set):
        folder = catalog / f"{image_set}.imageset"
        pngs = sorted(folder.glob("*.png")) if folder.exists() else []
        if pngs and image_set not in images:
            images[image_set] = "data:image/png;base64," + base64.b64encode(pngs[0].read_bytes()).decode("ascii")
    for name, pose in poses["poses"].items():
        parts["pose"]["variants"][name] = {"texture": pose["imageSet"], "bounds": pose["bounds"]}
        embed(pose["imageSet"])
        # Layer parts (e.g. the idle tail) exist only for the poses that declare them: strict variants, no fallback.
        for part, layer in pose.get("layers", {}).items():
            parts.setdefault(part, {"variants": {}})["variants"][name] = {"texture": layer["imageSet"], "bounds": layer["bounds"]}
            embed(layer["imageSet"])
    pack_json = _json.dumps({"parts": parts, "pixelsPerUnit": 1, "isProductionArt": False, "strictVariants": True})
    images_json = _json.dumps(images)
html = (here / "index.html").read_text(encoding="utf-8")
html = html.replace("__CHARACTER_SPEC__", spec)
html = html.replace("__MALI_PATHS__", (RES / "mali_paths.json").read_text(encoding="utf-8"))
html = html.replace("__ANIMATIONS__", anims)
html = html.replace("__TEXTURE_PACK__", pack_json).replace("__PACK_IMAGES__", images_json)
html = html.replace("__RIG_JS__", (here / "rig.js").read_text(encoding="utf-8").replace("</script", "<\\/script"))
out = here / "dist" / "mali-preview.html"
out.parent.mkdir(exist_ok=True)
out.write_text(html, encoding="utf-8")
print("wrote", out.relative_to(ROOT), f"{out.stat().st_size/1024:.0f} KB")
