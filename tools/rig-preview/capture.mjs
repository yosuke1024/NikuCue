// Capture stills (and optionally a video) of the Mali rig preview with Playwright/Chromium.
// Usage: node tools/rig-preview/capture.mjs [--out artifacts/P01] [--video]
// Output is a browser render of the shared JSON contracts, NOT an iOS Simulator recording.
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const outDir = resolve(args.includes('--out') ? args[args.indexOf('--out') + 1] : 'artifacts/rig-preview');
const wantVideo = args.includes('--video');
mkdirSync(outDir, { recursive: true });
const html = pathToFileURL(resolve(here, 'dist/mali-preview.html')).href;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1100, height: 760 }, deviceScaleFactor: 1 });
await page.goto(html);
await page.waitForFunction(() => window.__mali);
const canvas = page.locator('#c');

async function still(name, setup, t) {
  await page.evaluate(({ setup, t }) => {
    const m = window.__mali; m.pause(true);
    m.rig.clip = null; m.rig.hearts = []; m.rig.play('idle', 0); m.rig.prevExpression = null;
    m.setVirtual(0);
    if (setup.expression) m.setExpression(setup.expression);
    if (setup.idleLead) { m.rig.update(setup.idleLead); m.setVirtual(setup.idleLead); }   // run the ambient loop first
    if (setup.clip) m.play(setup.clip);
    if (setup.room) m.setRoom(setup.room);
    m.setVirtual(t); m.rig.prevExpression = null;
  }, { setup, t });
  await page.waitForTimeout(80);
  await canvas.screenshot({ path: resolve(outDir, name + '.png') });
  console.log('still', name);
}

await page.evaluate(() => window.__mali.pause(true));
const looks = await page.evaluate(() => JSON.parse(document.getElementById('spec').textContent).expressions);
await still('01_idle_neutral', {}, 0);
for (const e of looks) await still(`02_look_${e}_light`, { expression: e }, 300);
for (const e of looks) await still(`02_look_${e}_dark`, { expression: e, room: 'dark' }, 300);
await page.evaluate(() => window.__mali.setRoom('day'));
const celebrateTimes = [0, 140, 280, 420, 560, 680, 860, 1050, 1300, 1600];
for (const t of celebrateTimes) await still(`03_celebrate_${String(t).padStart(4, '0')}ms`, { clip: 'celebrate' }, t);
await still('04_pet_mid', { clip: 'pet' }, 450);
await still('05_greet_wave', { clip: 'greet' }, 180);
await still('06_cheer_mid', { clip: 'cheer' }, 600);
await still('07_settle_blink', { clip: 'settle' }, 520);
await still('08_doze', { clip: 'doze' }, 1200);
await still('09_milestone_hearts', { clip: 'milestone' }, 700);
await still('10_night_room_doze', { clip: 'doze', room: 'night' }, 2400);
await page.evaluate(() => window.__mali.setRoom('day'));
// idle life: breathing (3.6 s) and tail sway (4.8 s) drift against each other over the 14.4 s loop
for (const t of [0, 1200, 2400, 3600, 6000, 8400]) await still(`11_idle_${String(t).padStart(5, '0')}ms`, { clip: 'idle' }, t);
// a reaction interrupting the sway: the tail eases back instead of snapping (settle)
await still('12_greet_after_sway_0060ms', { clip: 'greet', idleLead: 1200 }, 60);
await page.evaluate(() => window.__mali.setRoom('day'));

// contact sheet of expressions + a 64px check
if (wantVideo) {
  // Record-only layout (?record=1): the 720 px room plus the bubble, driven programmatically so nothing scrolls.
  const ctx = await browser.newContext({ viewport: { width: 720, height: 800 }, recordVideo: { dir: outDir, size: { width: 720, height: 800 } } });
  const p = await ctx.newPage();
  await p.goto(html + '?record=1');
  await p.waitForFunction(() => window.__mali);
  await p.waitForTimeout(300);
  const pet = () => p.evaluate(() => document.getElementById('pet').click());
  const done = () => p.evaluate(() => document.getElementById('demoDone').click());
  const t0 = Date.now();
  const at = async (ms, fn) => { const wait = t0 + ms - Date.now(); if (wait > 0) await p.waitForTimeout(wait); await fn(); };
  // Asset README §7 review video: idle, greet, pet, completion, rest, milestone, doze on the night room, then the
  // same idle/pet on a dark surface so fringes and the shadow can be judged on light and dark backgrounds.
  await at(4500, () => p.evaluate(() => window.__mali.play('greet')));
  await at(7500, pet);
  await at(11000, done);
  await at(14500, () => p.evaluate(() => window.__mali.play('settle')));
  await at(18000, () => p.evaluate(() => window.__mali.play('milestone')));
  await at(22000, () => p.evaluate(() => { window.__mali.setRoom('night'); window.__mali.play('doze'); }));
  await at(26000, () => p.evaluate(() => { window.__mali.setRoom('dark'); window.__mali.play('idle'); }));
  await at(27500, pet);
  await at(31000, async () => {});
  const video = p.video();
  await ctx.close();
  const path = await video.path();
  console.log('video', path);
}
await browser.close();
