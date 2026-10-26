// Build identity-round4.html: round 2's core (paper, ink, randomness) and
// palettes, round 4's grounds, figures, composition, shipped list and export,
// and the committed picks from curated_art.json.
// Run from anywhere: node docs/fork/design/identity/round4/build.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const curated = JSON.parse(read('curated_art.json'));
const picks = Object.fromEntries(Object.entries(curated.items).map(([id, v]) => [id, v.pick]));
const html = read('page.html')
  .replace('/*@CORE@*/', () => read('../round2/core.js'))
  .replace('/*@MARKS@*/', () => read('../round2/marks.js'))
  .replace('/*@GROUNDS@*/', () => read('grounds.js'))
  .replace('/*@PRIMS@*/', () => read('prims.js'))
  .replace('/*@COMPOSE@*/', () => read('compose.js'))
  .replace('/*@SHIPPED@*/', () => read('shipped.js'))
  .replace('/*@EXPORT@*/', () => read('export.js'))
  .replace('/*@PICKS@*/{}', () => JSON.stringify(picks));
writeFileSync(join(here, 'identity-round4.html'), html);
console.log(`identity-round4.html ${(Buffer.byteLength(html) / 1024).toFixed(1)} KB, ${Object.keys(picks).length} curated picks`);
