// Estimates the texture memory a flipbook (pre-rendered frames) of the same clips needs, from the skeleton's real
// per-frame bounds, versus the Spine atlas. Evaluation tool, never shipped.
//   node tools/estimate_flipbook.mjs <skeleton.json> <atlas> [pixelsPerUnit=0.655] [fps=24]
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const require = createRequire(path.resolve("web/package.json"));
const spine = await import(require.resolve("@esotericsoftware/spine-core"));
const [skelPath, atlasPath, ppuArg, fpsArg] = process.argv.slice(2);
const ppu = Number(ppuArg || 0.655), fps = Number(fpsArg || 24);
const atlasText = fs.readFileSync(atlasPath, "utf8");
const atlas = new spine.TextureAtlas(atlasText);
const data = new spine.SkeletonJson(new spine.AtlasAttachmentLoader(atlas)).readSkeletonData(JSON.parse(fs.readFileSync(skelPath, "utf8")));
const clips = ["idle", "walk", "idle-turn", "jump"];
let fullBytes = 0, trimmedBytes = 0, frames = 0;
const rows = [];
for (const name of clips) {
  const anim = data.findAnimation(name);
  const n = Math.max(1, Math.round(anim.duration * fps));
  let union = null, trimmedArea = 0;
  for (let i = 0; i < n; i++) {
    const sk = new spine.Skeleton(data); sk.setupPose();
    const st = new spine.AnimationState(new spine.AnimationStateData(data));
    st.setAnimation(0, name, true); st.update(i / fps); st.apply(sk); sk.updateWorldTransform(spine.Physics.update);
    const o = new spine.Vector2(), z = new spine.Vector2(); sk.getBounds(o, z, []);
    trimmedArea += Math.ceil(z.x * ppu) * Math.ceil(z.y * ppu);
    union = union ? { x0: Math.min(union.x0, o.x), y0: Math.min(union.y0, o.y), x1: Math.max(union.x1, o.x + z.x), y1: Math.max(union.y1, o.y + z.y) } : { x0: o.x, y0: o.y, x1: o.x + z.x, y1: o.y + z.y };
  }
  const full = n * Math.ceil((union.x1 - union.x0) * ppu) * Math.ceil((union.y1 - union.y0) * ppu) * 4;
  fullBytes += full; trimmedBytes += trimmedArea * 4; frames += n;
  rows.push({ clip: name, frames: n, frameBoxUnits: [Math.round(union.x1 - union.x0), Math.round(union.y1 - union.y0)], fullMB: +(full / 1048576).toFixed(1), trimmedMB: +(trimmedArea * 4 / 1048576).toFixed(1) });
}
const page = atlasText.match(/size:\s*(\d+),\s*(\d+)/);
const scale = Number((atlasText.match(/scale:\s*([\d.]+)/) || [0, 1])[1]);
const atlasBytes = page ? Number(page[1]) * Number(page[2]) * 4 : 0;
// an atlas drawn 1:1 at this density would be (ppu / atlas scale)² larger
const atlasAtDensity = atlasBytes * Math.pow(ppu / scale, 2);
const out = { pixelsPerUnit: ppu, fps, clips: rows, frames,
  flipbookFullFramesMB: +(fullBytes / 1048576).toFixed(1), flipbookTrimmedMB: +(trimmedBytes / 1048576).toFixed(1),
  spineAtlasMB: +(atlasBytes / 1048576).toFixed(2), spineAtlasScale: scale, spineAtlasAtSameDensityMB: +(atlasAtDensity / 1048576).toFixed(2) };
console.log(JSON.stringify(out, null, 2));
