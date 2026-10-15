// Prints x / mode / clip each second for 90 s from the wasm engine (seed 7, 1800-unit room), for comparison with
// the native build (CatBehaviorTests "testTraceForCrossCheck" prints the same lines).
import fs from "node:fs";
import { loadEngine } from "./engine.js";
const e = await loadEngine(fs.readFileSync(new URL("./build/catbehavior.wasm", import.meta.url)));
e.create(7, 1800, 1500, 720, 1);
const lines = [];
for (let i = 1; i <= 90 * 60; i++) {
  if (i === 30 * 60) e.send("pet", 900, 400);
  if (i === 50 * 60) e.send("celebrate");
  const s = e.step(1 / 60);
  if (i % 60 === 0) lines.push(`${(i / 60).toFixed(0)} ${s.x.toFixed(6)} ${s.mode} ${s.base.clip} ${s.base.serial} ${s.activity}`);
}
console.log(lines.join("\n"));
