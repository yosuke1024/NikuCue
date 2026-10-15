// Diagnostic probe (not part of the evidence pipeline): replays a scenario many times with different frame-time
// jitter and hitch placement, the way real frame clocks shift when scripted inputs land, and reports the worst
// foot slide per transition for each variant.
//   node web/probe_timing.mjs <scenario> <seed> <variants>
import { chromium } from "playwright";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const [scenario = "interaction", seed = "11", variants = "24"] = process.argv.slice(2);
const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".wasm": "application/wasm",
  ".json": "application/json", ".png": "image/png", ".atlas": "text/plain", ".skel": "application/octet-stream" };
const server = http.createServer((req, res) => {
  const file = path.join(here, decodeURIComponent(req.url.split("?")[0]));
  if (!file.startsWith(here)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err, body) => { if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream" }); res.end(body); });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
const out = [];
for (let v = 0; v < Number(variants); v++) {
  const page = await browser.newPage({ viewport: { width: 632, height: 690 } });
  await page.goto(`http://127.0.0.1:${server.address().port}/harness.html?scenario=${scenario}&seed=${seed}&capture=1&footLock=1`);
  await page.waitForFunction(() => window.harnessReady || window.harnessError, null, { timeout: 60000 });
  const summary = await page.evaluate((v) => {
    // deterministic per variant: dt = 1/60 · (1 ± 20 %), and a hitch of 0.05–0.3 s about every 1.5–4 s
    let x = 1234567 + v * 7919;
    const rnd = () => ((x = (x * 1103515245 + 12345) % 2147483648) / 2147483648);
    let t = 0, nextHitch = 1 + rnd() * 3;
    const dts = [];
    while (t < 90) {
      let dt = (1 + (rnd() - 0.5) * 0.4) / 60;
      if (t >= nextHitch) { dt = 0.05 + rnd() * 0.25; nextHitch = t + 1.5 + rnd() * 2.5; }
      dts.push(dt);
      t += dt;
    }
    window.harness.steps(dts);
    return window.harness.summary();
  }, v);
  const worst = Object.fromEntries(Object.entries(summary.footSlide).filter(([k]) => k.startsWith("blend") || k === "turn")
    .map(([k, s]) => [k, Math.round(s.maxOccurrence * 10) / 10]));
  out.push({ v, worst, flips: summary.facingFlipsOutsideTurn, maxRootStep: summary.maxRootStep, log: summary.log });
  console.log(v, JSON.stringify(worst));
  await page.close();
}
fs.writeFileSync(process.env.PROBE_OUT || "probe.json", JSON.stringify(out, null, 1));
await browser.close();
server.close();
