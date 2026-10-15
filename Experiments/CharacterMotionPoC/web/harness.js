// Browser verification harness: the CatBehavior engine (WebAssembly build of the same Swift sources) drives the
// official Spine sample "spineboy" through the official spine-webgl 4.3.13 runtime. It mirrors MotionLab's
// SpineDriver (iOS) and Diagnostics so the numbers are comparable. Labelled everywhere as a browser render: it is
// NOT an iOS Simulator or device recording.
//
// Time is virtual: `advance(frames, dt)` steps engine + skeleton deterministically and renders the last frame, so a
// capture script can screenshot every frame without dropped frames or real-time jitter.
import { loadEngine } from "./engine.js";

const params = new URLSearchParams(location.search);
const SCENARIO = params.get("scenario") || "interactive";
const SEED = Number(params.get("seed") || 7);
const STAGE_W = 1800, STAGE_H = 1500, FLOOR_DEPTH = 140;
const GROUND_TOL = 17.2; // 2.5 % of the character height, same as Diagnostics.swift / measure_profile.mjs

const glCanvas = document.getElementById("gl");
const roomCanvas = document.getElementById("room");
const hudEl = document.getElementById("hud");
const ringsEl = document.getElementById("rings");

const engine = await loadEngine(await (await fetch("./build/catbehavior.wasm")).arrayBuffer());
engine.create(SEED, STAGE_W, STAGE_H, STAGE_W * 0.4, 1);

// ---------- Spine ----------
const ctx = new spine.ManagedWebGLRenderingContext(glCanvas, { alpha: true, premultipliedAlpha: false });
const renderer = new spine.SceneRenderer(glCanvas, ctx);
const assets = new spine.AssetManager(ctx, "./samples/");
assets.loadBinary("spineboy-pro.skel");
assets.loadTextureAtlas("spineboy-pma.atlas");
await assets.loadAll();
const atlas = assets.require("spineboy-pma.atlas");
const data = new spine.SkeletonBinary(new spine.AtlasAttachmentLoader(atlas)).readSkeletonData(assets.require("spineboy-pro.skel"));
const skeleton = new spine.Skeleton(data);
skeleton.setupPose();
const stateData = new spine.AnimationStateData(data);
stateData.defaultMix = 0.2;
const animState = new spine.AnimationState(stateData);
const crosshair = skeleton.findBone("crosshair");
const crosshairSlot = skeleton.findSlot("crosshair");
const feet = [["front", skeleton.findBone("front-foot-tip")], ["rear", skeleton.findBone("back-foot-tip")]];
const footTargets = [skeleton.findBone("front-foot-target"), skeleton.findBone("rear-foot-target")];
const FOOT_LOCK = params.get("footLock") !== "0";

let current = engine.step(0);
animState.setAnimation(0, current.base.clip, current.base.loop);
let lastBaseSerial = current.base.serial, lastLookSerial = -1, lookActive = false;
let reduceMotionApp = params.get("reduceMotion") === "1";
const mql = matchMedia("(prefers-reduced-motion: reduce)");

// ---------- Diagnostics (same definitions as MotionLab/Diagnostics.swift) ----------
const diag = {
  frames: 0, maxRootStep: 0, facingFlipsOutsideTurn: 0, maxClipDriftWalking: 0,
  slide: {}, feetPrev: {}, segment: {}, serialStart: {}, serialFrom: {}, occurrence: {}, prev: null,
  activities: {}, log: [], latency: {}, pendingStimuli: [], lifecycle: [],
};
function context(s) {
  const since = s.time - (diag.serialStart[s.base.serial] ?? -1);
  if (since < s.base.mix + 1e-6) return `blend:${diag.serialFrom[s.base.serial] || "?"}>${s.base.clip}`;
  return { walking: "walk", turning: "turn", hopping: "hop" }[s.mode] || "stand";
}
function recordFrame(s) {
  diag.frames++;
  const p = diag.prev;
  if (p) {
    diag.maxRootStep = Math.max(diag.maxRootStep, Math.abs(s.x - p.x));
    if (s.facing !== p.facing && !(s.base.serial !== p.base.serial && s.mode === "turning")) diag.facingFlipsOutsideTurn++;
  }
  if (!p || p.base.serial !== s.base.serial) {
    diag.serialStart[s.base.serial] = s.time;
    diag.serialFrom[s.base.serial] = p ? p.base.clip : "start";
  }
  diag.prev = s;
}
function recordFeet(s) {
  const ctxName = context(s);
  for (const [id, bone] of feet) {
    const pos = { x: bone.appliedPose.worldX, y: bone.appliedPose.worldY };
    const q = diag.feetPrev[id];
    diag.feetPrev[id] = pos;
    if (!q) continue;
    if (pos.y <= GROUND_TOL && q.y <= GROUND_TOL) {
      const d = Math.abs(pos.x - q.x);
      const st = (diag.slide[ctxName] ||= { frames: 0, total: 0, maxStep: 0, maxRunDrift: 0, maxOccurrence: 0 });
      st.frames++; st.total += d; st.maxStep = Math.max(st.maxStep, d);
      // one occurrence = one clip blend / one turn / one walk: total grounded-foot slide inside it (both feet)
      const key = `${ctxName}#${s.base.serial}`;
      diag.occurrence[key] = (diag.occurrence[key] || 0) + d;
      st.maxOccurrence = Math.max(st.maxOccurrence || 0, diag.occurrence[key]);
      // a stance that spans a walk, a blend and standing is split there (same as Diagnostics.swift)
      const open = diag.segment[id];
      if (open && open.context !== ctxName) closeSegment(id, q.x);
      if (!diag.segment[id]) diag.segment[id] = { x: q.x, context: ctxName };
    } else {
      closeSegment(id, q.x);
    }
  }
  const e = animState.getTrack(0);
  if (e && s.mode === "walking") diag.maxClipDriftWalking = Math.max(diag.maxClipDriftWalking, Math.abs(e.trackTime - s.baseClipTime));
}
function closeSegment(id, endX) {
  const open = diag.segment[id];
  if (!open) return;
  delete diag.segment[id];
  const st = (diag.slide[open.context] ||= { frames: 0, total: 0, maxStep: 0, maxRunDrift: 0, maxOccurrence: 0 });
  st.maxRunDrift = Math.max(st.maxRunDrift, Math.abs(endX - open.x));
}
function recordEvents(list) {
  for (const [t, d] of list) {
    const [kind, arg] = d.split(" ");
    if (kind === "activity") diag.activities[arg] = (diag.activities[arg] || 0) + 1;
    if (kind === "received") diag.pendingStimuli.push([arg, t]);
    if (kind === "applied") {
      const i = diag.pendingStimuli.findIndex(([k]) => k === arg);
      if (i >= 0) { (diag.latency[arg] ||= []).push(t - diag.pendingStimuli[i][1]); diag.pendingStimuli.splice(i, 1); }
    }
    // a glance only (cooldown / busy): the input just received gets no body reaction
    if (kind === "glance") {
      const i = diag.pendingStimuli.map(([k]) => k).lastIndexOf(arg);
      if (i >= 0) diag.pendingStimuli.splice(i, 1);
    }
    // dropped: the oldest waiting one (replaced or discarded by a pause); a same-kind replacement stays pending
    if (kind === "dropped") {
      const i = diag.pendingStimuli.findIndex(([k]) => k === arg);
      if (i >= 0) diag.pendingStimuli.splice(i, 1);
    }
    if (!["clip", "finished", "received", "walk", "stopRequested"].includes(kind)) {
      diag.log.push(`${t.toFixed(2).padStart(6)}s ${d}`);
      if (diag.log.length > 400) diag.log.shift();
    }
  }
}

// ---------- Scripted input (same timeline as MotionLab/ScriptedInput.swift) ----------
const scripts = {
  interaction: [[8, "tapCharacter"], [16, "tapFloor", 0.9], [26, "celebrate"], [27.5, "tapSpam", 10, 2.0], [36, "tapBehind"],
    [46, "rest"], [55, "celebrate"], [55.4, "celebrate"], [70, "tapFloor", 0.12], [80, "tapCharacter"]],
  reducedMotion: [[12, "tapCharacter"], [20, "celebrate"], [30, "tapFloor", 0.85]],
};
let timeline = (scripts[SCENARIO] || []).slice();
let spam = null;
const rings = [];
function tap(x, y, scripted) {
  rings.push({ x, y, scripted, born: virtualTime });
  const hopExtra = current.mode === "hopping" ? 700 : 0;
  const onCharacter = Math.abs(x - current.x) < 210 * 0.9 && y > -40 && y < 686.2 * 1.1 + hopExtra;
  if (onCharacter) engine.send("pet", x, y); else engine.send("call", x, Math.max(0, y));
}
const tapCharacter = () => tap(current.x, current.mode === "hopping" ? 700 : 420, true);
function fireScript(elapsed) {
  if (spam && elapsed >= spam.next) { tapCharacter(); spam.remaining--; spam.next += spam.interval; if (spam.remaining <= 0) spam = null; }
  while (timeline.length && elapsed >= timeline[0][0]) {
    const [, action, a, b] = timeline.shift();
    if (action === "tapCharacter") tapCharacter();
    else if (action === "tapFloor") tap(STAGE_W * a, 0, true);
    else if (action === "tapBehind") tap(Math.min(Math.max(current.x - current.facing * 650, 100), STAGE_W - 100), 0, true);
    else if (action === "celebrate") engine.send("celebrate");
    else if (action === "rest") engine.send("rest");
    else if (action === "tapSpam") spam = { remaining: a, interval: b / a, next: elapsed };
  }
}

// ---------- Frame ----------
let virtualTime = 0, paused = false;
function applyState(s, dtScale) {
  animState.timeScale = dtScale;
  if (s.base.serial !== lastBaseSerial) {
    if (s.base.freezePrevious) { const cur = animState.getTrack(0); if (cur) cur.timeScale = 0; }
    const entry = animState.setAnimation(0, s.base.clip, s.base.loop);
    entry.mixDuration = s.base.mix;
    entry.trackTime = s.base.startTime;
    lastBaseSerial = s.base.serial;
  }
  const cur = animState.getTrack(0);
  if (cur) cur.timeScale = s.baseTimeScale;
  skeleton.x = s.x;
  skeleton.y = 0;
  skeleton.scaleX = s.facing;
  if (s.look) {
    if (!lookActive || s.look.serial !== lastLookSerial) {
      let entry;
      if (animState.getTrack(1)) entry = animState.setAnimation(1, s.look.clip, true);
      else { animState.setEmptyAnimation(1, 0); entry = animState.addAnimation(1, s.look.clip, true, 0); }
      entry.mixDuration = s.look.mixIn;
      entry.alpha = s.look.alpha;
      lastLookSerial = s.look.serial;
      lookActive = true;
    }
    crosshair.pose.x = (s.look.target.x - s.x) * s.facing;
    crosshair.pose.y = s.look.target.y;
  } else if (lookActive) {
    animState.setEmptyAnimation(1, s.lookOutMix);
    lookActive = false;
  }
}

// Foot planting (same as MotionLab's SpineDriver): the leg IK targets are children of the root, so their world x
// is skeleton.x + facing × local x. Override, recompute world transforms, then restore the animated pose so the
// next frame starts from the animation again.
function plantFeet(s) {
  const animated = footTargets.map((b) => ({ x: s.x + s.facing * b.pose.x, y: b.pose.y }));
  const planted = engine.plant(animated[0], animated[1]);
  footTargets.forEach((b, i) => { b.pose.x = (planted[i].x - s.x) * s.facing; b.pose.y = planted[i].y; });
  skeleton.updateWorldTransform(spine.Physics.pose);
  footTargets.forEach((b, i) => { b.pose.x = (animated[i].x - s.x) * s.facing; b.pose.y = animated[i].y; });
}

function frame(dt) {
  // a frame of `dt` seconds of wall clock; the engine integrates at most maxStep and the skeleton follows it
  const engineDt = Math.min(dt, engine.tables.maxStep);
  engine.setReducedMotion(reduceMotionApp || mql.matches);
  fireScript(virtualTime);
  current = engine.step(dt);
  recordFrame(current);
  recordEvents(engine.events());
  applyState(current, dt > 0 ? engineDt / dt : 1);
  animState.update(dt);
  animState.apply(skeleton);
  skeleton.update(engineDt);
  skeleton.updateWorldTransform(spine.Physics.update);
  if (FOOT_LOCK) plantFeet(current);
  if (crosshairSlot) crosshairSlot.appliedPose.color.a = 0; // the sample's aim pose shows a crosshair; a look-at should not
  recordFeet(current);
  virtualTime += dt;
}

// ---------- Drawing ----------
const CSS_W = glCanvas.clientWidth, CSS_H = glCanvas.clientHeight;
const viewScale = CSS_W / STAGE_W;
function toView(p) { return { x: p.x * viewScale, y: CSS_H - (p.y + FLOOR_DEPTH) * viewScale }; }
function drawRoom() {
  const dpr = devicePixelRatio || 1;
  roomCanvas.width = CSS_W * dpr; roomCanvas.height = CSS_H * dpr;
  const g = roomCanvas.getContext("2d");
  g.scale(dpr, dpr);
  const floorY = toView({ x: 0, y: 0 }).y;
  g.fillStyle = "rgb(255,242,219)"; g.fillRect(0, 0, CSS_W, floorY);
  g.fillStyle = "rgb(235,214,184)"; g.fillRect(0, floorY, CSS_W, CSS_H - floorY);
  g.strokeStyle = "rgb(199,168,133)"; g.beginPath(); g.moveTo(0, floorY); g.lineTo(CSS_W, floorY); g.stroke();
  const s = viewScale;
  const win = toView({ x: STAGE_W * 0.02, y: STAGE_H * 0.78 });
  g.fillStyle = "rgb(204,230,247)"; g.strokeStyle = "rgb(158,133,107)"; g.lineWidth = 2;
  g.beginPath(); g.roundRect(Math.max(4, win.x - 10), win.y - 160 * s, 300 * s, 360 * s, 8); g.fill(); g.stroke();
  const cushion = toView({ x: STAGE_W * 0.84, y: 0 });
  g.fillStyle = "rgb(214,158,140)"; g.beginPath(); g.ellipse(cushion.x, cushion.y + 5 * s, 230 * s, 35 * s, 0, 0, Math.PI * 2); g.fill();
  const toy = toView({ x: STAGE_W * 0.68, y: 0 });
  g.fillStyle = "rgb(242,140,102)"; g.beginPath(); g.arc(toy.x, toy.y - 34 * s, 34 * s, 0, Math.PI * 2); g.fill();
}
drawRoom();

function render() {
  renderer.resize(spine.ResizeMode.Expand);
  ctx.gl.clearColor(0, 0, 0, 0);
  ctx.gl.clear(ctx.gl.COLOR_BUFFER_BIT);
  const zoom = STAGE_W / glCanvas.width;
  renderer.camera.zoom = zoom;
  renderer.camera.position.x = STAGE_W / 2;
  renderer.camera.position.y = (STAGE_H + FLOOR_DEPTH) / 2 - FLOOR_DEPTH;
  renderer.camera.update();
  renderer.begin();
  renderer.drawSkeleton(skeleton);
  renderer.end();
  // tap rings (purple = scripted, labelled; blue = real mouse taps)
  ringsEl.innerHTML = "";
  for (const r of rings.filter((r) => virtualTime - r.born < 0.9)) {
    const v = toView(r), u = (virtualTime - r.born) / 0.9, size = 18 + 36 * u;
    const el = document.createElement("div");
    el.className = "ring" + (r.scripted ? " scripted" : "");
    Object.assign(el.style, { left: `${v.x - size / 2}px`, top: `${v.y - size / 2}px`, width: `${size}px`, height: `${size}px`, opacity: 1 - u });
    if (r.scripted) el.dataset.label = "scripted tap";
    ringsEl.appendChild(el);
  }
  const s = current;
  hudEl.textContent = `${s.activity} · ${s.mode} · x ${s.x.toFixed(0)} · facing ${s.facing > 0 ? "→" : "←"} · t ${virtualTime.toFixed(1)}s`
    + `${s.reducedMotion ? " · Reduce Motion" : ""}${paused ? " · PAUSED (background)" : ""}\n`
    + diag.log.slice(-4).join("\n");
}

function nextPaint() { return new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); }

// ---------- API for the capture script and for live use ----------
window.harness = {
  scenario: SCENARIO,
  async advance(frames, dt = 1 / 60) {
    for (let i = 0; i < frames; i++) frame(paused ? 0 : dt);
    render();
    await nextPaint();
    return { t: virtualTime, activity: current.activity, mode: current.mode, x: current.x };
  },
  /** Simulates the app going to the background for `seconds`: engine paused, nothing renders, then resume. */
  background(seconds) {
    engine.setPaused(true);
    diag.lifecycle.push({ phase: "inactive", engineTime: current.time, x: current.x, virtualTime });
    paused = true;
    recordEvents(engine.events());
  },
  resume(firstFrameDelta) {
    engine.setPaused(false);
    paused = false;
    const before = { x: current.x, time: current.time };
    frame(firstFrameDelta);            // the first frame after resume reports the whole time away
    diag.lifecycle.push({ phase: "active", engineTime: current.time, x: current.x, virtualTime,
      firstFrameDelta, engineAdvanced: current.time - before.time, rootMoved: Math.abs(current.x - before.x) });
  },
  setReduceMotion(on) { reduceMotionApp = on; },
  tap(x, y) { tap(x, y, true); },
  summary() {
    for (const id of Object.keys(diag.segment)) closeSegment(id, diag.feetPrev[id].x);   // feet still planted at the end
    const mem = performance.memory ? { usedJSHeapMB: performance.memory.usedJSHeapSize / 1048576 } : {};
    const pageBytes = atlas.pages.reduce((n, p) => n + (p.texture ? p.texture.getImage().width * p.texture.getImage().height * 4 : 0), 0);
    return {
      extra: { scenario: SCENARIO, renderer: FOOT_LOCK ? "spine-webgl (browser)" : "spine-webgl (browser, no foot planting)", seed: String(SEED), reduceMotion: String(current.reducedMotion),
        systemReduceMotion: String(mql.matches), note: "browser render (Chromium + SwiftShader), not an iOS Simulator or device" },
      // virtual time: every frame is exactly 1/60 s by construction (nothing measured, unlike MotionLab)
      frames: diag.frames, frameInterval: { virtualSeconds: 1 / 60 },
      maxRootStep: diag.maxRootStep, facingFlipsOutsideTurn: diag.facingFlipsOutsideTurn, maxClipDriftWalking: diag.maxClipDriftWalking,
      footSlide: Object.fromEntries(Object.entries(diag.slide).map(([k, v]) => [k, { ...v, meanPerFrame: v.frames ? v.total / v.frames : 0 }])),
      memoryMB: { atlasTextureMB: pageBytes / 1048576, ...mem },
      activities: diag.activities, stimulusLatency: diag.latency, lifecycle: diag.lifecycle.map((l) => Object.fromEntries(Object.entries(l).map(([k, v]) => [k, String(v)]))),
      log: diag.log,
    };
  },
};

// live mode: real time + mouse taps
if (!params.has("capture")) {
  let last = performance.now();
  const loop = (now) => { const dt = Math.min((now - last) / 1000, 0.25); last = now; frame(dt); render(); requestAnimationFrame(loop); };
  requestAnimationFrame(loop);
  document.getElementById("stage").addEventListener("click", (ev) => {
    const r = glCanvas.getBoundingClientRect();
    const x = (ev.clientX - r.left) / viewScale, y = (CSS_H - (ev.clientY - r.top)) / viewScale - FLOOR_DEPTH;
    tap(x, y, false);
  });
  document.addEventListener("visibilitychange", () => { if (document.hidden) engine.setPaused(true); else { engine.setPaused(false); last = performance.now(); } });
  document.getElementById("celebrate").onclick = () => engine.send("celebrate");
  document.getElementById("rest").onclick = () => engine.send("rest");
  document.getElementById("rm").onchange = (e) => { reduceMotionApp = e.target.checked; };
}
render();
window.harnessReady = true;
