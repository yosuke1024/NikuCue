// Records the browser harness scenarios frame by frame (virtual time, 30 fps output) and writes the diagnostics.
// Browser render only (Chromium + SwiftShader): NOT an iOS Simulator or device recording.
//
//   node web/capture.mjs [outDir] [scenario ...]      (run from Experiments/CharacterMotionPoC, after build_wasm.sh)
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));   // decoded (paths with spaces or non-ASCII characters)
const out = path.resolve(process.argv[2] || path.join(here, "../captures/browser"));
const metricsOnlyAll = process.argv.includes("--metrics-only");
const wanted = process.argv.slice(3).filter((a) => !a.startsWith("--"));
const scenarios = [
  { name: "autonomous", seconds: 90, seed: 7 },
  { name: "interaction", seconds: 90, seed: 11 },
  { name: "lifecycle", seconds: 45, seed: 5, background: { at: 15, seconds: 10 } },
  { name: "reducedMotion", seconds: 40, seed: 3, media: "reduce" },
  // same sessions without foot planting: numbers only (no video), for the on/off comparison
  { name: "interaction-nofootlock", scenario: "interaction", seconds: 90, seed: 11, footLock: 0, metricsOnly: true },
  { name: "autonomous-nofootlock", scenario: "autonomous", seconds: 90, seed: 7, footLock: 0, metricsOnly: true },
  // the same sessions with irregular frame times and hitches like the CI Simulator's (numbers only, run on request)
  { name: "interaction-hitches", scenario: "interaction", seconds: 90, seed: 11, metricsOnly: true, hitches: true, onRequest: true },
  { name: "autonomous-hitches", scenario: "autonomous", seconds: 90, seed: 7, metricsOnly: true, hitches: true, onRequest: true },
].filter((s) => (wanted.length ? wanted.includes(s.name) : !s.onRequest)).map((s) => (metricsOnlyAll ? { ...s, metricsOnly: true } : s));

const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".wasm": "application/wasm",
  ".json": "application/json", ".png": "image/png", ".atlas": "text/plain", ".skel": "application/octet-stream" };
const server = http.createServer((req, res) => {
  const file = path.join(here, decodeURIComponent(req.url.split("?")[0]));
  if (!file.startsWith(here)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err, body) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream" });
    res.end(body);
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
fs.mkdirSync(out, { recursive: true });

for (const sc of scenarios) {
  const page = await browser.newPage({ viewport: { width: 632, height: 690 }, deviceScaleFactor: 1.5 });
  page.on("pageerror", (e) => console.error("pageerror", e.message));
  if (sc.media) await page.emulateMedia({ reducedMotion: sc.media });
  await page.goto(`http://127.0.0.1:${port}/harness.html?scenario=${sc.scenario || sc.name}&seed=${sc.seed}&capture=1&footLock=${sc.footLock ?? 1}`);
  await page.waitForFunction(() => window.harnessReady || window.harnessError, null, { timeout: 60000 });
  const err = await page.evaluate(() => window.harnessError);
  if (err) throw new Error(err);
  const frames = path.join(out, `${sc.name}_frames`);
  fs.rmSync(frames, { recursive: true, force: true });
  fs.mkdirSync(frames);
  const clip = { x: 0, y: 0, width: 632, height: 690 };
  let n = 0;
  const shot = async () => { if (!sc.metricsOnly) await page.screenshot({ path: path.join(frames, `${String(n++).padStart(5, "0")}.png`), clip }); };
  const started = Date.now();
  for (let f = 0; f < sc.seconds * 30; f++) {
    const t = f / 30;
    if (sc.background && Math.abs(t - sc.background.at) < 1e-9) {
      await page.evaluate((s) => window.harness.background(s), sc.background.seconds);
      for (let k = 0; k < 30; k++) { await page.evaluate(() => window.harness.advance(0)); await shot(); }  // 1 s of "away" in the video
      await page.evaluate((s) => window.harness.resume(s), sc.background.seconds);
    }
    if (sc.hitches) {
      // two frames of 1/60 s ± 15 %, and every ~2.5 s one 0.2 s hitch (deterministic, like the CI Simulator's worst)
      const jitter = (k) => (1 + 0.15 * Math.sin(f * 12.9898 + k * 78.233)) / 60;
      const hitch = f % 75 === 37 ? 0.2 : null;
      await page.evaluate(([a, b]) => { window.harness.advance(1, a); return window.harness.advance(1, b); }, [hitch ?? jitter(0), jitter(1)]);
    } else {
      await page.evaluate(() => window.harness.advance(2, 1 / 60));
    }
    await shot();
    if (f % 300 === 0) console.log(`${sc.name}: ${t.toFixed(0)} s (${((Date.now() - started) / 1000).toFixed(0)} s wall)`);
  }
  const summary = await page.evaluate(() => window.harness.summary());
  summary.extra.scenario = sc.name;
  fs.writeFileSync(path.join(out, `diagnostics-${sc.name}-browser.json`), JSON.stringify(summary, null, 2));
  if (sc.metricsOnly) { fs.rmSync(frames, { recursive: true, force: true }); await page.close(); console.log(`${sc.name}: metrics only`); continue; }
  const video = path.join(out, `browser_${sc.name}.mp4`);
  execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-framerate", "30", "-i", path.join(frames, "%05d.png"),
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "22", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", video]);
  for (const t of [5, 30, 60, 85]) {
    const src = path.join(frames, `${String(t * 30).padStart(5, "0")}.png`);
    if (fs.existsSync(src)) fs.copyFileSync(src, path.join(out, `browser_${sc.name}_t${t}s.png`));
  }
  fs.rmSync(frames, { recursive: true, force: true });
  console.log(`${sc.name}: wrote ${video}`);
  await page.close();
}
await browser.close();
server.close();
