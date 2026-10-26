// Freeze the curated picks into curated_art.json, which supersedes round 4's.
// Round 4's grounds, figures and shipped list load unchanged; places.js adds
// round 5's; compose.js keeps round 4's classes and draws. Every item that
// round 5 does not re-curate must freeze byte-identically to round 4's
// curated_art.json, and this checks that it does.
// Run from anywhere: node docs/fork/design/identity/round5/curate.mjs [picks.json]
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const ctx = vm.createContext({ Math, JSON, console, document: { createElement: () => ({}) }, DOMMatrix: class {} });
const files = ['../round2/core.js', '../round4/grounds.js', '../round4/prims.js', 'places.js', 'compose.js', '../round4/shipped.js', 'export.js'];
vm.runInContext(`var BellData = ${read('bells.json')};\n` + files.map(read).join('\n;\n') + '\n;this.Export = Export;', ctx);
const picks = JSON.parse(read(process.argv[2] || 'picks.json'));
const out = ctx.Export.curated(picks);

// Parity with round 4 for everything not re-curated here.
const RECURATED = JSON.parse(read('recurated.json'));
const old = JSON.parse(read('../round4/curated_art.json')).items, same = [], moved = [];
for (const [id, v] of Object.entries(old)) {
  if (RECURATED.includes(id)) continue;
  (JSON.stringify(out.items[id]) === JSON.stringify(v) ? same : moved).push(id);
}
if (moved.length) { console.error(`changed from round 4 without being re-curated: ${moved.join(', ')}`); process.exit(1); }
writeFileSync(join(here, 'curated_art.json'), JSON.stringify(out, null, 1) + '\n');
const bells = Object.values(out.items).filter((v) => v.kind === 'bell').length;
console.log(`curated_art.json: ${Object.keys(out.items).length} items (${same.length} identical to round 4, ${RECURATED.length} re-curated, ${bells} bells)`);
