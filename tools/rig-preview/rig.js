// Mali rig preview renderer (development tool, not shipped in the app).
// Consumes the same three JSON contracts the iOS CharacterArtProvider uses:
//   character_spec.json  – node tree, positions, z-order
//   mali_paths.json      – vector art per part (M/L/C/Q/Z, design units)
//   animations.json      – clip ids, durations, keyframe tracks
// Coordinates are SpriteKit-style (origin bottom-left, y up); the canvas is flipped once.
(function (global) {
  'use strict';

  const DEFAULT_EXPRESSION_BLEND_MS = 100;   // parts rig (docs/04 §5); animations.json may state its own expressionBlendMs

  function parsePath(d) {
    const toks = d.replace(/,/g, ' ').trim().split(/\s+/);
    const cmds = [];
    let i = 0;
    while (i < toks.length) {
      const c = toks[i++];
      const num = () => parseFloat(toks[i++]);
      if (c === 'M') cmds.push({ c, x: num(), y: num() });
      else if (c === 'L') cmds.push({ c, x: num(), y: num() });
      else if (c === 'C') cmds.push({ c, x1: num(), y1: num(), x2: num(), y2: num(), x: num(), y: num() });
      else if (c === 'Q') cmds.push({ c, cx: num(), cy: num(), x: num(), y: num() });
      else if (c === 'Z') cmds.push({ c });
      else throw new Error('bad path token ' + c);
    }
    return cmds;
  }

  function toPath2D(cmds) {
    const p = new Path2D();
    for (const k of cmds) {
      if (k.c === 'M') p.moveTo(k.x, k.y);
      else if (k.c === 'L') p.lineTo(k.x, k.y);
      else if (k.c === 'C') p.bezierCurveTo(k.x1, k.y1, k.x2, k.y2, k.x, k.y);
      else if (k.c === 'Q') p.quadraticCurveTo(k.cx, k.cy, k.x, k.y);
      else if (k.c === 'Z') p.closePath();
    }
    return p;
  }

  // ---- easing -------------------------------------------------------------
  const EASE = {
    linear: t => t,
    easeIn: t => t * t,
    easeOut: t => 1 - (1 - t) * (1 - t),
    easeInOut: t => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2),
    sine: t => 0.5 - 0.5 * Math.cos(Math.PI * t),
  };

  function sampleTrack(track, tMs) {
    const kf = track.keyframes;
    if (!kf.length) return undefined;
    if (tMs <= kf[0].t) return kf[0].v;
    const last = kf[kf.length - 1];
    if (tMs >= last.t) return last.v;
    for (let i = 0; i < kf.length - 1; i++) {
      const a = kf[i], b = kf[i + 1];
      if (tMs >= a.t && tMs <= b.t) {
        if (typeof a.v === 'string') return a.v;
        const span = b.t - a.t;
        const u = span > 0 ? (tMs - a.t) / span : 1;
        const e = EASE[b.ease || 'easeInOut'] || EASE.easeInOut;
        return a.v + (b.v - a.v) * e(u);
      }
    }
    return last.v;
  }

  // ---- rig ----------------------------------------------------------------
  class Rig {
    constructor(spec, paths, anims, opts) {
      this.spec = spec; this.paths = paths; this.anims = anims;
      this.opts = Object.assign({ reduceMotion: false, seed: 1, texturePack: null, images: null }, opts || {});
      // Optional production art: { manifest, images: { textureName: HTMLImageElement } } (docs/CHARACTER_ASSET_PIPELINE.md)
      this.pack = this.opts.texturePack || null;
      this.images = this.opts.images || null;
      this.palette = Object.assign({}, spec.palette, paths.palette);
      this.nodes = {};
      this.order = [];
      for (const n of spec.nodes) {
        this.nodes[n.id] = { spec: n, children: [], rest: { x: n.position[0], y: n.position[1], s: n.scale == null ? 1 : n.scale },
          dx: 0, dy: 0, rot: 0, sx: 1, sy: 1, alpha: n.opacity == null ? 1 : n.opacity, visible: true };
      }
      for (const n of spec.nodes) if (n.parent) this.nodes[n.parent].children.push(this.nodes[n.id]);
      for (const id in this.nodes) this.nodes[id].children.sort((a, b) => a.spec.z - b.spec.z);
      this.root = this.nodes.root;
      this.compiled = {};
      for (const id in paths.parts) {
        const part = paths.parts[id];
        if (part.variants) {
          this.compiled[id] = { variants: {} };
          for (const v in part.variants) this.compiled[id].variants[v] = this._compile(part.variants[v]);
        } else this.compiled[id] = this._compile(part);
      }
      // Initial look: 'neutral' on the parts rig, the first listed pose on the whole-body rig.
      this.expression = spec.expressions.includes('neutral') ? 'neutral' : spec.expressions[0];
      this.prevExpression = null;
      this.expressionBlendStart = 0;
      this.hearts = [];
      this.clip = null;       // { id, def, start }
      this.ambientId = 'idle';
      this.ambientStart = 0;
      this.blink = { next: 0, start: -1 };
      this.rng = mulberry32(this.opts.seed);
      this.time = 0;
      this.listeners = [];
      this.blendMs = anims.expressionBlendMs || DEFAULT_EXPRESSION_BLEND_MS;
      this.settling = null;   // residual transforms easing back to rest after a clip interrupts the ambient loop
      this.linger = null;     // { until, look }: the finished reaction's look held while the ambient loop resumes
    }

    _compile(part) {
      return { bounds: part.bounds, layers: part.layers.map(l => Object.assign({}, l, { p2d: toPath2D(parsePath(l.path)) })) };
    }

    on(fn) { this.listeners.push(fn); }

    setExpression(e, now) {
      if (e === this.expression) return;
      this.prevExpression = this.expression;
      this.expression = e;
      this.expressionBlendStart = now == null ? this.time : now;
    }

    play(clipId, now) {
      const def = this.anims.clips.find(c => c.id === clipId);
      if (!def) throw new Error('unknown clip ' + clipId);
      const t = now == null ? this.time : now;
      this.linger = null;     // any new clip (reaction or ambient) cancels a pending linger, like the controller
      if (def.loop) { this.ambientId = clipId; this.ambientStart = t; this.clip = null; this.resetTransforms(); this.setExpression(def.expression, t); return; }
      this.clip = { id: clipId, def, start: t };
      // Mirrors CatRig.settle: properties the clip drives snap to rest, the rest (idle tail sway, breathing) ease back.
      const controlled = {};
      for (const tr of (this.opts.reduceMotion ? def.reducedMotionTracks : def.tracks) || []) (controlled[tr.node] = controlled[tr.node] || new Set()).add(tr.property);
      const from = {};
      for (const id in this.nodes) {
        const n = this.nodes[id], c = controlled[id] || new Set();
        const r = { dx: c.has('offsetX') ? 0 : n.dx, dy: c.has('offsetY') ? 0 : n.dy, rot: c.has('rotation') ? 0 : n.rot,
                    sx: (c.has('scale') || c.has('scaleX')) ? 0 : n.sx - 1, sy: (c.has('scale') || c.has('scaleY')) ? 0 : n.sy - 1 };
        if (Math.abs(r.dx) + Math.abs(r.dy) + Math.abs(r.rot) + Math.abs(r.sx) + Math.abs(r.sy) > 1e-4) from[id] = r;
      }
      this.settling = Object.keys(from).length ? { start: t, from } : null;
      this.resetTransforms();
      if (clipId === 'milestone' && !this.opts.reduceMotion) this.spawnHearts(t);
      if (clipId === 'milestone' && this.opts.reduceMotion) { const h = def.hearts.reducedMotion; this.hearts = [{ born: t, x: h.position[0], y: h.position[1], static: true, scale: h.scale }]; }
      this.setExpression(def.expression, t);
    }

    spawnHearts(t) {
      const h = this.anims.clips.find(c => c.id === 'milestone').hearts;
      this.hearts = h.spawnAtMs.slice(0, h.max).map((ms, i) => ({ born: t + ms, x: h.positions[i][0], y: h.positions[i][1], static: false, life: h.lifeMs, rise: h.riseUnits, scale: h.scale }));
    }

    resetTransforms() {
      for (const id in this.nodes) { const n = this.nodes[id]; n.dx = 0; n.dy = 0; n.rot = 0; n.sx = 1; n.sy = 1; n.alpha = n.spec.opacity == null ? 1 : n.spec.opacity; }
    }

    // Advance to absolute time t (ms) and compute transforms.
    update(t) {
      this.time = t;
      this.resetTransforms();
      const rm = this.opts.reduceMotion;
      let activeDef = null, elapsed = 0, loop = false;
      if (this.clip) {
        elapsed = t - this.clip.start;
        if (elapsed >= this.clip.def.durationMs) {
          const finished = this.clip.id, lingerMs = this.clip.def.lingerMs || 0; this.clip = null; this.ambientStart = t; this.hearts = [];
          const amb = this.anims.clips.find(c => c.id === this.ambientId);
          // CatSceneController.finishCurrent: the reaction's last look lingers while breathing resumes
          if (lingerMs > 0 && this.expression !== amb.expression) this.linger = { until: t + lingerMs, look: amb.expression };
          else this.setExpression(amb.expression, t);
          this.listeners.forEach(fn => fn({ type: 'clipFinished', id: finished }));
        } else { activeDef = this.clip.def; }
      }
      if (!activeDef) { activeDef = this.anims.clips.find(c => c.id === this.ambientId); elapsed = (t - this.ambientStart) % activeDef.durationMs; loop = true; }
      if (this.linger && !this.clip && t >= this.linger.until) { this.setExpression(this.linger.look, this.linger.until); this.linger = null; }
      const tracks = rm ? (activeDef.reducedMotionTracks || []) : (activeDef.tracks || []);
      for (const tr of tracks) {
        const n = this.nodes[tr.node]; if (!n) continue;
        const v = sampleTrack(tr, elapsed);
        if (v === undefined) continue;
        if (tr.property === 'expression') { this.setExpression(v, t); continue; }
        if (tr.property === 'rotation') n.rot += v;
        else if (tr.property === 'offsetX') n.dx += v;
        else if (tr.property === 'offsetY') n.dy += v;
        else if (tr.property === 'scaleX') n.sx *= v;
        else if (tr.property === 'scaleY') n.sy *= v;
        else if (tr.property === 'scale') { n.sx *= v; n.sy *= v; }
        else if (tr.property === 'alpha') n.alpha *= v;
      }
      if (this.settling) {
        const u = Math.min(1, (t - this.settling.start) / this.blendMs);
        const k = 1 - EASE.easeInOut(u);
        for (const id in this.settling.from) {
          const n = this.nodes[id]; if (!n) continue;
          const r = this.settling.from[id];
          n.dx += r.dx * k; n.dy += r.dy * k; n.rot += r.rot * k; n.sx *= 1 + r.sx * k; n.sy *= 1 + r.sy * k;
        }
        if (u >= 1) this.settling = null;
      }
      // blink: ambient only, seeded intervals from animations.json; only rigs with eye nodes and blink.enabled !== false
      // (the whole-body texture rig has neither: no fake blinks by stretching a portrait)
      const blinkSpec = this.anims.ambient && this.anims.ambient.blink;
      if (!rm && loop && this.ambientId === 'idle' && blinkSpec && blinkSpec.enabled !== false && this.nodes.eyeL && this.nodes.eyeR) {
        const b = blinkSpec;
        if (this.blink.next === 0) this.blink.next = t + b.intervalMs[0] + this.rng() * (b.intervalMs[1] - b.intervalMs[0]);
        if (this.blink.start < 0 && t >= this.blink.next) this.blink.start = t;
        if (this.blink.start >= 0) {
          const u = (t - this.blink.start) / b.durationMs;
          if (u >= 1) { this.blink.start = -1; this.blink.next = t + b.intervalMs[0] + this.rng() * (b.intervalMs[1] - b.intervalMs[0]); }
          else { const s = u < 0.5 ? 1 - u * 2 : (u - 0.5) * 2; const sy = 0.08 + 0.92 * s; this.nodes.eyeL.sy *= sy; this.nodes.eyeR.sy *= sy; }
        }
      }
    }

    // ---- drawing ----------------------------------------------------------
    draw(ctx, scale, originX, originY) {
      ctx.save();
      ctx.translate(originX, originY);
      ctx.scale(scale, -scale);           // flip once: design units are y-up
      this._drawNode(ctx, this.root, 1);
      this._drawHearts(ctx);
      ctx.restore();
    }

    _drawNode(ctx, n, parentAlpha) {
      ctx.save();
      ctx.translate(n.rest.x + n.dx, n.rest.y + n.dy);
      ctx.rotate(n.rot * Math.PI / 180);
      ctx.scale(n.sx * n.rest.s, n.sy * n.rest.s);
      const alpha = parentAlpha * n.alpha;
      const id = n.spec.id;
      // children with z < own art draw first? In SpriteKit, a node's own content is drawn before children.
      const art = this.compiled[id];
      if (n.spec.kind !== 'pivot' && (art || (this.pack && this.pack.parts[id]))) this._drawPart(ctx, id, art || { layers: [] }, alpha);
      for (const c of n.children) this._drawNode(ctx, c, alpha);
      ctx.restore();
    }

    _drawPart(ctx, id, art, alpha) {
      if (this.pack && this.images) {
        const part = this.pack.parts[id];
        if (part) { this._drawPackPart(ctx, id, part, alpha); return; }
      }
      if (art.variants) {
        const cur = art.variants[this.expression] || art.variants.neutral || art.variants[this.spec.expressions[0]];
        const blendT = Math.min(1, (this.time - this.expressionBlendStart) / this.blendMs);
        if (this.prevExpression && blendT < 1) {
          const prev = art.variants[this.prevExpression] || art.variants.neutral;
          this._drawLayers(ctx, prev.layers, alpha * (1 - blendT));
          this._drawLayers(ctx, cur.layers, alpha * blendT);
        } else this._drawLayers(ctx, cur.layers, alpha);
        return;
      }
      this._drawLayers(ctx, art.layers, alpha);
    }

    _drawPackPart(ctx, id, part, alpha) {
      // strictVariants (whole-body pack): a look without this layer draws nothing instead of falling back
      const pick = (expr) => part.variants ? (this.pack.strictVariants ? part.variants[expr] : (part.variants[expr] || part.variants.neutral || part.variants[this.spec.expressions[0]])) : part;
      const draw = (d, a) => {
        if (!d) return;
        const img = this.images[d.texture]; if (!img || !d.bounds) return;
        const [x0, y0, x1, y1] = d.bounds;
        ctx.save(); ctx.globalAlpha = a; ctx.scale(1, -1); // image rows are y-down; flip back inside the y-up rig space
        ctx.drawImage(img, x0, -y1, x1 - x0, y1 - y0);
        ctx.restore();
      };
      if (part.variants) {
        const blendT = Math.min(1, (this.time - this.expressionBlendStart) / this.blendMs);
        if (this.prevExpression && blendT < 1) { draw(pick(this.prevExpression), alpha * (1 - blendT)); draw(pick(this.expression), alpha * blendT); }
        else draw(pick(this.expression), alpha);
      } else draw(part, alpha);
    }

    _drawLayers(ctx, layers, alpha) {
      for (const l of layers) {
        ctx.globalAlpha = alpha * (l.opacity == null ? 1 : l.opacity);
        if (l.fill) { ctx.fillStyle = this.palette[l.fill] || l.fill; ctx.fill(l.p2d); }
        if (l.stroke) { ctx.strokeStyle = this.palette[l.stroke] || l.stroke; ctx.lineWidth = l.width || 4; ctx.lineCap = l.cap || 'round'; ctx.lineJoin = 'round'; ctx.stroke(l.p2d); }
      }
      ctx.globalAlpha = 1;
    }

    _drawHearts(ctx) {
      const art = this.compiled.heart; if (!art && !(this.pack && this.pack.parts.heart)) return;
      for (const h of this.hearts) {
        const age = this.time - h.born; if (age < 0) continue;
        const life = h.life || 900; if (!h.static && age > life) continue;
        const u = h.static ? 0.3 : age / life;
        const y = this.root.rest.y + h.y + (h.static ? 0 : (h.rise || 90) * u);
        const a = h.static ? 1 : (u < 0.15 ? u / 0.15 : 1 - (u - 0.15) / 0.85);
        const s = (h.scale || 1) * (h.static ? 1 : 0.6 + 0.4 * Math.min(1, u * 3));
        ctx.save(); ctx.translate(this.root.rest.x + h.x, y); ctx.scale(s, s);
        if (this.pack && this.images && this.pack.parts.heart) this._drawPackPart(ctx, 'heart', this.pack.parts.heart, Math.max(0, a));
        else this._drawLayers(ctx, art.layers, Math.max(0, a));
        ctx.restore();
      }
    }
  }

  function mulberry32(a) {
    return function () {
      let t = a += 0x6D2B79F5;
      t = Math.imul(t ^ t >>> 15, t | 1);
      t ^= t + Math.imul(t ^ t >>> 7, t | 61);
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }

  global.MaliRig = { Rig, parsePath, sampleTrack, EASE };
})(typeof window !== 'undefined' ? window : globalThis);
