// Seam check: paint every round 2 tile (light) at 1/30 s steps over 60 s
// and report the biggest frame-to-frame change against its typical change.
// A pop (a phase wrapping while visible) shows as a ratio far above the rest.
//   node check_r2.mjs <page.html>
import { pathToFileURL } from 'node:url';
const PW = process.env.PLAYWRIGHT || '/home/admin/.t3/worktrees/T3code/sync-upstream-2026-10-19/node_modules/.pnpm/playwright@1.60.0/node_modules/playwright/index.mjs';
const { chromium } = await import(PW);
const b = await chromium.launch({ headless: true, executablePath: process.env.CHROME || '/usr/bin/google-chrome' });
const p = await b.newPage();
await p.goto(pathToFileURL(process.argv[2]).href + '?t=0');
await p.waitForFunction(() => window.__ready === true);
const rows = await p.evaluate(() => {
  const out = [];
  for (const cv of document.querySelectorAll('.row.light canvas.art')) {
    const v = JSON.parse(cv.dataset.v), c = document.createElement('canvas'); c.width = 85; c.height = 74;
    Object.assign(c.dataset, cv.dataset);
    const g = c.getContext('2d', { willReadFrequently: true }), diffs = [];
    let prev = null;
    for (let i = 0; i <= 1800; i++) {
      window.__paint(c, i / 30, false);
      const d = g.getImageData(0, 0, 85, 74).data;
      if (prev) { let s = 0; for (let j = 0; j < d.length; j += 4) s += Math.abs(d[j] - prev[j]) + Math.abs(d[j + 1] - prev[j + 1]) + Math.abs(d[j + 2] - prev[j + 2]); diffs.push([s / (85 * 74), i / 30]); }
      prev = d;
    }
    const sorted = diffs.map((x) => x[0]).sort((a, b) => a - b), med = sorted[sorted.length >> 1], max = diffs.reduce((m, x) => (x[0] > m[0] ? x : m));
    out.push({ fig: v.figure, med: +med.toFixed(3), max: +max[0].toFixed(2), at: +max[1].toFixed(2), ratio: +(max[0] / Math.max(med, 0.05)).toFixed(1) });
  }
  return out;
});
await b.close();
rows.sort((a, b) => b.ratio - a.ratio).forEach((r) => console.log(`${r.ratio.toString().padStart(6)}  ${r.fig.padEnd(22)} max ${r.max} at ${r.at}s, median ${r.med}`));
