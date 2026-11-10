// Stills of the round 2 page: one PNG per practice (light and dark rows,
// round 1 first), the fixes, and a contact sheet (sheet.png; the JPEG is
// made from it). Console errors fail the run.
//   node shoot_r2.mjs <page.html> <out dir> [ids...] [--t=S] [--anim]
// With no ids, every block on the page is shot, then the sheet.
// Calm still frames by default; --anim freezes the moving figures at t.
import { mkdirSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const PW = process.env.PLAYWRIGHT || '/home/admin/.t3/worktrees/T3code/sync-upstream-2026-10-19/node_modules/.pnpm/playwright@1.60.0/node_modules/playwright/index.mjs';
const { chromium } = await import(PW);
const args = process.argv.slice(2), flags = args.filter((a) => a.startsWith('--')), [page, out, ...only] = args.filter((a) => !a.startsWith('--'));
const t = Number((flags.find((f) => f.startsWith('--t=')) || '--t=4').slice(4)), anim = flags.includes('--anim');
mkdirSync(out, { recursive: true });
const b = await chromium.launch({ headless: true, executablePath: process.env.CHROME || '/usr/bin/google-chrome' });
const ctx = await b.newContext({ deviceScaleFactor: 2, viewport: { width: 830, height: 900 } });
let ids = only;
if (!ids.length) { const p = await ctx.newPage(); await p.goto(pathToFileURL(page).href + '?t=0'); await p.waitForFunction(() => window.__ready === true); ids = [...(await p.evaluate(() => [...document.querySelectorAll('.block')].map((e) => e.id))), 'sheet']; await p.close(); }
let bad = 0;
for (const id of ids) {
  const p = await ctx.newPage();
  p.on('console', (m) => { if (m.type() === 'error') { bad++; console.error(id, m.text()); } });
  p.on('pageerror', (e) => { bad++; console.error(id, e.message); });
  const q = `?shot=${id}&t=${t}${anim ? '' : '&still'}`;
  await p.goto(pathToFileURL(page).href + q);
  await p.waitForFunction(() => window.__ready === true, null, { timeout: 15000 }).catch(() => { bad++; console.error(id, 'never ready'); });
  await p.evaluate(() => document.fonts.ready);
  await p.locator('.shot').screenshot({ path: `${out}/${id}${anim ? `-t${t}` : ''}.png` });
  await p.close();
}
await b.close();
console.log(`shot ${ids.length} -> ${out}${bad ? `, ${bad} errors` : ''}`);
process.exit(bad ? 1 : 0);
