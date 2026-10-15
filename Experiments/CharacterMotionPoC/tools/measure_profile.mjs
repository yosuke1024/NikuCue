// Measures a Spine skeleton's clips with the official spine-core runtime and writes the motion profile the
// CatBehavior engine needs to move the character without foot sliding or snapping:
//
//   locomotion (walk / run)
//     groundSpeed   how fast a planted foot travels backwards (units/s at timeScale 1) = root speed that keeps it still
//     strideLength  groundSpeed × duration: distance covered by one cycle (arrival phase depends only on distance)
//     plantPhases   cycle phases where both feet are down (or mid-stance for a run): moments it is safe to stop
//     enterPhase    cycle phase whose foot layout is closest to the idle pose (start walking from idle here)
//     stopPhases    plant phases with the cost (units) of blending from that phase into the idle pose
//   transitions (run-to-idle, idle-turn)
//     rootMotion    cumulative root displacement that keeps the pivot (most still, grounded) foot planted
//   reactions (jump)
//     airborne      [start, end] seconds where neither foot is on the ground (cannot be interrupted)
//
// Usage: node tools/measure_profile.mjs <skeleton.json> <atlas> <out.json>
// Evaluation tool, never shipped. Only bone transforms are read; no image is decoded.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(path.resolve("web/package.json"));
const spine = await import(require.resolve("@esotericsoftware/spine-core"));

const [skeletonPath, atlasPath, outPath] = process.argv.slice(2);
if (!skeletonPath || !atlasPath || !outPath) {
  console.error("usage: node tools/measure_profile.mjs <skeleton.json> <atlas> <out.json>");
  process.exit(2);
}

const atlas = new spine.TextureAtlas(fs.readFileSync(atlasPath, "utf8"));
const data = new spine.SkeletonJson(new spine.AtlasAttachmentLoader(atlas)).readSkeletonData(JSON.parse(fs.readFileSync(skeletonPath, "utf8")));

const FEET = [
  { id: "front", bone: "front-foot-tip" },
  { id: "rear", bone: "back-foot-tip" },
];
const HZ = 600;

// Setup-pose bounds give the character height; "on the ground" = within 2.5 % of it.
const setup = new spine.Skeleton(data);
setup.setupPose();
setup.updateWorldTransform(spine.Physics.none);
const bOffset = new spine.Vector2(), bSize = new spine.Vector2();
setup.getBounds(bOffset, bSize, []);
const GROUND_TOL = bSize.y * 0.025;

function sample(animationName, loop = true) {
  const skeleton = new spine.Skeleton(data);
  const animation = data.findAnimation(animationName);
  const state = new spine.AnimationState(new spine.AnimationStateData(data));
  state.setAnimation(0, animationName, loop);
  const frames = Math.max(1, Math.round(animation.duration * HZ));
  const rows = [];
  for (let i = 0; i <= frames; i++) {
    state.update(i === 0 ? 0 : 1 / HZ);
    state.apply(skeleton);
    skeleton.updateWorldTransform(spine.Physics.none);
    const row = { t: i / HZ };
    for (const f of FEET) {
      const b = skeleton.findBone(f.bone).appliedPose;
      row[f.id] = { x: b.worldX, y: b.worldY };
    }
    rows.push(row);
  }
  return { animation, rows };
}

const r2 = (v) => +v.toFixed(2);
const r4 = (v) => +v.toFixed(4);
const wrap = (m) => r4(((m % 1) + 1) % 1);

// idle frame 0: the stance every stop blends into and every start blends out of
const idleFeet = sample("idle").rows[0];

function runsOf(flags, rows, duration) {
  const runs = [];
  let a = -1;
  for (let i = 0; i <= rows.length; i++) {
    if (i < rows.length && flags[i]) { if (a < 0) a = i; continue; }
    if (a >= 0) { runs.push([rows[a].t / duration, rows[i - 1].t / duration]); a = -1; }
  }
  if (runs.length > 1 && runs[0][0] === 0 && runs[runs.length - 1][1] >= (rows.length - 1) / HZ / duration - 1e-9) {
    const last = runs.pop();
    runs[0] = [last[0] - 1, runs[0][1]];
  }
  return runs;
}

function poseCost(row) {
  // how far each foot must travel to reach the idle stance (feet can only move by sliding while blended)
  return FEET.reduce((m, f) => Math.max(m, Math.hypot(row[f.id].x - idleFeet[f.id].x, row[f.id].y - idleFeet[f.id].y)), 0);
}

function analyseLocomotion(animationName) {
  const { animation, rows } = sample(animationName);
  const duration = animation.duration;
  const feet = {};
  const speeds = [];
  for (const f of FEET) {
    const minY = Math.min(...rows.map((r) => r[f.id].y));
    const stance = rows.map((r, i) => i > 0 && r[f.id].y <= minY + GROUND_TOL && r[f.id].x - rows[i - 1][f.id].x <= 0);
    stance[0] = stance[1];
    for (let i = 1; i < rows.length; i++) if (stance[i] && stance[i - 1]) speeds.push(-(rows[i][f.id].x - rows[i - 1][f.id].x) * HZ);
    feet[f.id] = { stance, minY, lift: Math.max(...rows.map((r) => r[f.id].y)) - minY };
  }
  speeds.sort((a, b) => a - b);
  const groundSpeed = speeds[Math.floor(speeds.length / 2)];

  // worst drift of a planted foot inside the middle 60 % of each stance when the root moves at groundSpeed
  let coreSlide = 0;
  for (const f of FEET) {
    for (const [a, b] of runsOf(feet[f.id].stance, rows, duration)) {
      const ia = Math.round(Math.max(0, a) * duration * HZ), ib = Math.round(b * duration * HZ);
      const lo = Math.round(ia + (ib - ia) * 0.2), hi = Math.round(ia + (ib - ia) * 0.8);
      if (hi <= lo) continue;
      const x0 = rows[lo][f.id].x + groundSpeed * rows[lo].t;
      for (let k = lo; k <= hi; k++) coreSlide = Math.max(coreSlide, Math.abs(rows[k][f.id].x + groundSpeed * rows[k].t - x0));
    }
  }

  const both = rows.map((_, i) => feet.front.stance[i] && feet.rear.stance[i]);
  const windows = runsOf(both, rows, duration);
  const plantPhases = windows.length
    ? windows.map(([a, b]) => wrap((a + b) / 2))
    : FEET.flatMap((f) => runsOf(feet[f.id].stance, rows, duration).map(([a, b]) => wrap((a + b) / 2))).sort((a, b) => a - b);
  const rowAt = (phase) => rows[Math.min(rows.length - 1, Math.round(phase * duration * HZ))];
  const stopPhases = plantPhases.map((p) => ({ phase: p, cost: r2(poseCost(rowAt(p))) })).sort((a, b) => a.phase - b.phase);
  // entering from idle: the grounded-feet phase whose layout is closest to idle
  let enterPhase = 0, best = Infinity;
  for (let i = 0; i < rows.length - 1; i++) {
    const grounded = FEET.every((f) => rows[i][f.id].y <= feet[f.id].minY + GROUND_TOL * 2);
    if (!grounded) continue;
    const c = poseCost(rows[i]);
    if (c < best) { best = c; enterPhase = rows[i].t / duration; }
  }
  // Blend windows: phases where every grounded foot is within `WINDOW_SLIDE` (horizontally) of its idle position.
  // A foot in the air at that moment does not slide; it simply sets down during the blend.
  const slideCost = (row) => {
    let c = -1;
    for (const f of FEET) if (row[f.id].y <= feet[f.id].minY + GROUND_TOL) c = Math.max(c, Math.abs(row[f.id].x - idleFeet[f.id].x));
    return c; // -1: both feet in the air
  };
  const WINDOW_SLIDE = 30;
  let bestI = 0, bestC = Infinity;
  for (let i = 0; i < rows.length - 1; i++) { const c = slideCost(rows[i]); if (c >= 0 && c < bestC) { bestC = c; bestI = i; } }
  let lo = bestI, hi = bestI;
  while (lo > 0 && slideCost(rows[lo - 1]) >= 0 && slideCost(rows[lo - 1]) <= WINDOW_SLIDE) lo--;
  while (hi < rows.length - 2 && slideCost(rows[hi + 1]) >= 0 && slideCost(rows[hi + 1]) <= WINDOW_SLIDE) hi++;
  const blendWindow = bestC <= WINDOW_SLIDE ? [r4(rows[lo].t / duration), r4(rows[hi].t / duration)] : null;
  return {
    clip: animationName,
    duration: r4(duration),
    blendWindow,
    blendWindowMaxSlide: WINDOW_SLIDE,
    blendWindowBestSlide: r2(bestC),
    groundSpeed: r2(groundSpeed),
    strideLength: r2(groundSpeed * duration),
    plantPhases,
    plantKind: windows.length ? "doubleSupport" : "midStance",
    stopPhases,
    enterPhase: r4(enterPhase),
    enterCost: r2(best),
    coreStanceSlide: r2(coreSlide),
    footLift: Object.fromEntries(FEET.map((f) => [f.id, r2(feet[f.id].lift)])),
  };
}

// Root motion for an in-place transition clip: each frame the pivot foot is the grounded foot that moves least;
// the root moves by the opposite of its local motion so it stays planted. Sampled at 60 Hz, cumulative units.
function analyseTransition(animationName, entrySpeed = 0) {
  const { animation, rows } = sample(animationName, false);
  const out = [0];
  let pos = 0, pivotSwitches = 0, last = null, carried = 0;
  const step = HZ / 60;
  for (let i = 1; i < rows.length; i++) {
    let pivot = null, best = Infinity;
    for (const f of FEET) {
      if (rows[i][f.id].y > Math.min(rows[i].front.y, rows[i].rear.y) + GROUND_TOL) continue;
      const dx = Math.abs(rows[i][f.id].x - rows[i - 1][f.id].x);
      if (dx < best) { best = dx; pivot = f.id; }
    }
    if (pivot && rows[i][pivot].y <= GROUND_TOL * 2) {
      pos -= rows[i][pivot].x - rows[i - 1][pivot].x;
      if (last && pivot !== last) pivotSwitches++;
      last = pivot;
    } else {
      // airborne: carry the incoming speed so a stop from a run keeps its momentum until a foot lands
      pos += entrySpeed / HZ;
      carried += entrySpeed / HZ;
    }
    if (i % step === 0) out.push(r2(pos));
  }
  return { clip: animationName, duration: r4(animation.duration), sampleRate: 60, rootMotion: out, total: r2(pos), pivotSwitches, carriedWhileAirborne: r2(carried) };
}

function analyseAirborne(animationName) {
  const { animation, rows } = sample(animationName, false);
  const air = rows.map((r) => FEET.every((f) => r[f.id].y > GROUND_TOL * 2));
  const first = air.indexOf(true), last = air.lastIndexOf(true);
  const hip = []; // body drift that is not root motion (should stay small for an in-place reaction)
  return {
    clip: animationName,
    duration: r4(animation.duration),
    airborne: first < 0 ? null : [r4(rows[first].t), r4(rows[last].t)],
    peakFootHeight: r2(Math.max(...rows.map((r) => Math.min(r.front.y, r.rear.y)))),
  };
}

const durations = Object.fromEntries(data.animations.map((a) => [a.name, r4(a.duration)]));
const walk = analyseLocomotion("walk");
const run = analyseLocomotion("run");
const out = {
  generatedBy: "tools/measure_profile.mjs (spine-core 4.3.13)",
  source: path.basename(skeletonPath),
  note: "Evaluation profile of the official Spine sample 'spineboy' (non-commercial sample, not a product asset).",
  setupBounds: { x: r2(bOffset.x), y: r2(bOffset.y), width: r2(bSize.x), height: r2(bSize.y) },
  groundTolerance: r2(GROUND_TOL),
  idleFeet: Object.fromEntries(FEET.map((f) => [f.id, { x: r2(idleFeet[f.id].x), y: r2(idleFeet[f.id].y) }])),
  durations,
  locomotion: { walk, run },
  transitions: {
    runStop: analyseTransition("run-to-idle", run.groundSpeed),
    turn: analyseTransition("idle-turn"),
  },
  reactions: { jump: analyseAirborne("jump") },
};
fs.writeFileSync(outPath, JSON.stringify(out, null, 2) + "\n");
const brief = (o) => JSON.stringify(o, (k, v) => (k === "rootMotion" ? `[${v.length} samples … ${v[v.length - 1]}]` : v), 2);
console.log(brief({ walk, run, transitions: out.transitions, reactions: out.reactions, idleFeet: out.idleFeet }));
