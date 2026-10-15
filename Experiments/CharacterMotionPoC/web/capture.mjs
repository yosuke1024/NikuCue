// Records the browser harness scenarios frame by frame (virtual time, 30 fps output) and writes the diagnostics.
// Browser render only (Chromium + SwiftShader): NOT an iOS Simulator or device recording.
//
//   node web/capture.mjs [outDir] [scenario ...]      (run from Experiments/CharacterMotionPoC, after build_wasm.sh)
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";

const here = path.dirname(new URL(import.meta.url).pathname);
const out = path.resolve(process.argv[2] || path.join(here, "../captures/browser"));
const wanted = process.argv.slice(3);
const scenarios = [
  { name: "autonomous", seconds: 90, seed: 7 },
  { name: "interaction", seconds: 90, seed: 11 },
  { name: "lifecycle", seconds: 45, seed: 5, background: { at: 15, seconds: 10 } },
  { name: "reducedMotion", seconds: 40, seed: 3, media: "reduce" },
].filter((s) => !wanted.length || wanted.includes(s.name));

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
  await page.goto(`http://127.0.0.1:${port}/harness.html?scenario=${sc.name}&seed=${sc.seed}&capture=1`);
  await page.waitForFunction(() => window.harnessReady || window.harnessError, null, { timeout: 60000 });
  const err = await page.evaluate(() => window.harnessError);
  if (err) throw new Error(err);
  const frames = path.join(out, `${sc.name}_frames`);
  fs.rmSync(frames, { recursive: true, force: true });
  fs.mkdirSync(frames);
  const clip = { x: 0, y: 0, width: 632, height: 690 };
  let n = 0;
  const shot = async () => { await page.screenshot({ path: path.join(frames, `${String(n++).padStart(5, "0")}.png`), clip }); };
  const started = Date.now();
  for (let f = 0; f < sc.seconds * 30; f++) {
    const t = f / 30;
    if (sc.background && Math.abs(t - sc.background.at) < 1e-9) {
      await page.evaluate((s) => window.harness.background(s), sc.background.seconds);
      for (let k = 0; k < 30; k++) { await page.evaluate(() => window.harness.advance(0)); await shot(); }  // 1 s of "away" in the video
      await page.evaluate((s) => window.harness.resume(s), sc.background.seconds);
    }
    await page.evaluate(() => window.harness.advance(2, 1 / 60));
    await shot();
    if (f % 300 === 0) console.log(`${sc.name}: ${t.toFixed(0)} s (${((Date.now() - started) / 1000).toFixed(0)} s wall)`);
  }
  const summary = await page.evaluate(() => window.harness.summary());
  fs.writeFileSync(path.join(out, `diagnostics-${sc.name}-browser.json`), JSON.stringify(summary, null, 2));
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
