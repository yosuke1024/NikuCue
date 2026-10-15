// Loads build/catbehavior.wasm (the CatBehavior Swift engine compiled to WebAssembly) and wraps its C ABI.
// Works in the browser and in Node. The engine never touches the outside world: WASI calls are stubs.

function wasiStubs(getMemory) {
  const ok = () => 0;
  return {
    args_get: ok, args_sizes_get: (argc, size) => { const v = new DataView(getMemory().buffer); v.setUint32(argc, 0, true); v.setUint32(size, 0, true); return 0; },
    environ_get: ok, environ_sizes_get: (count, size) => { const v = new DataView(getMemory().buffer); v.setUint32(count, 0, true); v.setUint32(size, 0, true); return 0; },
    fd_close: ok, fd_fdstat_get: () => 8, fd_prestat_get: () => 8, fd_prestat_dir_name: () => 8, fd_read: () => 8, fd_seek: () => 8,
    fd_write: (fd, iovs, iovsLen, nwritten) => {
      // the engine does not print; count the bytes so a stray print cannot hang
      const v = new DataView(getMemory().buffer);
      let n = 0;
      for (let i = 0; i < iovsLen; i++) n += v.getUint32(iovs + i * 8 + 4, true);
      v.setUint32(nwritten, n, true);
      return 0;
    },
    path_open: () => 8, proc_exit: (code) => { throw new Error(`proc_exit(${code})`); },
    random_get: (ptr, len) => { const b = new Uint8Array(getMemory().buffer, ptr, len); for (let i = 0; i < len; i++) b[i] = (i * 151 + 7) & 255; return 0; },
  };
}

export const STIMULUS = { pet: 0, call: 1, celebrate: 2, rest: 3 };

export async function loadEngine(bytes) {
  let memory;
  const module = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasiStubs(() => memory) });
  memory = instance.exports.memory;
  instance.exports._initialize();
  const x = instance.exports;
  const decoder = new TextDecoder();
  const text = (len) => decoder.decode(new Uint8Array(memory.buffer, x.cb_text_ptr(), len));
  const tables = JSON.parse(text(x.cb_tables()));

  return {
    tables,
    create(seed, width, height, startX, facing = 1) { x.cb_create(seed, width, height, startX, facing); },
    /** Steps the engine; returns a plain RenderState object (same fields as the Swift struct). */
    step(dt) {
      x.cb_step(dt);
      const s = new Float64Array(memory.buffer, x.cb_state_ptr(), 32);
      const lookActive = s[11] === 1;
      return {
        time: s[0], x: s[1], facing: s[2],
        base: { clip: tables.clips[s[3]], loop: s[4] === 1, startTime: s[5], mix: s[6], serial: s[7], freezePrevious: s[8] === 1 },
        baseTimeScale: s[9], baseClipTime: s[10],
        look: lookActive ? { clip: tables.clips[s[12]], alpha: s[13], mixIn: s[14], serial: s[15], target: { x: s[16], y: s[17] } } : null,
        lookOutMix: s[18], mode: tables.modes[s[19]], activity: tables.activities[s[20]],
        reducedMotion: s[21] === 1, paused: s[22] === 1,
      };
    },
    send(kind, px = 0, py = 0) { x.cb_send(STIMULUS[kind], px, py); },
    /** Foot planting (CatBehavior.FootPlanter): animated target positions in, planted positions out. */
    plant(front, rear) {
      x.cb_plant(front.x, front.y, rear.x, rear.y);
      const s = new Float64Array(memory.buffer, x.cb_state_ptr(), 32);
      return [{ x: s[24], y: s[25] }, { x: s[26], y: s[27] }];
    },
    setReducedMotion(on) { x.cb_set_reduced_motion(on ? 1 : 0); },
    setPaused(on) { x.cb_set_paused(on ? 1 : 0); },
    events() { return JSON.parse(text(x.cb_events())); },
  };
}
