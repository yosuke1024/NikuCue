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

# Whole-body pose textures (owner-supplied) take precedence over the layered pack and the placeholder.
poses_file = RES / "mali_poses.json"
if poses_file.exists():
    poses = _json.loads(poses_file.read_text(encoding="utf-8"))
    spec = (RES / "mali_wholebody_spec.json").read_text(encoding="utf-8")
    anims = (RES / "mali_wholebody_animations.json").read_text(encoding="utf-8")
    catalog = ROOT / "NikuCue" / "Resources" / "Assets.xcassets" / "Mali"
    variants, images = {}, {}
    for name, pose in poses["poses"].items():
        variants[name] = {"texture": pose["imageSet"], "bounds": pose["bounds"]}
        png = catalog / f"{pose['imageSet']}.imageset" / f"mali_{name}.png"
        if png.exists():
            images[pose["imageSet"]] = "data:image/png;base64," + base64.b64encode(png.read_bytes()).decode("ascii")
    pack_json = _json.dumps({"parts": {"pose": {"variants": variants}}, "pixelsPerUnit": 1, "isProductionArt": False})
    images_json = _json.dumps(images)
# Header copy per art mode (the page must not call interim art "production").
if poses_file.exists():
    title = "Mali（マリ）ポーズ・プレビュー（全身イラスト v1、暫定表示）"
    lede = ("オーナー提供の全身イラスト 6 枚（idle / happy / celebrate / pet / sleepy / sad）を、iOS アプリと同じ JSON 契約"
            "（mali_poses / mali_wholebody_spec / mali_wholebody_animations）からブラウザで描画した確認用ページです。"
            "猫をタップすると「なでる」反応、ボタンで各クリップとポーズを再生できます。部屋の「dark UI」で暗い面での見え方を確認できます。")
    notice = ("これは開発用プレビューで、iOS アプリや Simulator の録画ではありません。ポーズの切替は cross-fade と軽い動き（持ち上げ・小さな傾き・呼吸）だけで、"
              "瞬き・しっぽ・手足のアニメーションはまだありません（追加レイヤーの判断はオーナー）。<strong>製品ビジュアルの完成扱いではなく</strong>、"
              "承認（R02）までは review 表示です（docs/CHARACTER_ASSET_PIPELINE.md）。")
else:
    title = "Mali（マリ）リグ・プレビュー（プレースホルダー絵）"
    lede = ("NikuCue の猫キャラクター Mali を、iOS アプリと同じ JSON 契約（character_spec / mali_paths / animations）からブラウザで描画した確認用ページです。"
            "猫をタップすると「なでる」反応、ボタンで各クリップと表情を再生できます。")
    notice = ("これは開発用プレビューで、iOS アプリや Simulator の録画ではありません。絵は<strong>開発用プレースホルダー</strong>（コード描画）で、製品用の猫ではありません。"
              "製品用は高品質 2D イラストの画像パーツで制作します（docs/CHARACTER_ASSET_PIPELINE.md）。")
page = (here / "artifact_template.html").read_text(encoding="utf-8")
page = page.replace("__PAGE_TITLE__", title).replace("__PAGE_LEDE__", lede).replace("__PAGE_NOTICE__", notice)
page = page.replace("__CHARACTER_SPEC__", spec).replace("__MALI_PATHS__", paths).replace("__ANIMATIONS__", anims).replace("__RIG_JS__", rig_js)
page = page.replace("__TEXTURE_PACK__", pack_json).replace("__PACK_IMAGES__", images_json)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(page, encoding="utf-8")
print("wrote", out, f"{out.stat().st_size/1024:.0f} KB")
