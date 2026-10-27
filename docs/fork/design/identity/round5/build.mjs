// Build identity-round5.html: round 2's core and palettes, round 4's grounds,
// figures and shipped list (unchanged), round 5's places, composition,
// export, bells and synth sketch, and the committed picks from
// curated_art.json; recurated.json lists the items this round re-curated.
// Run from anywhere: node docs/fork/design/identity/round5/build.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const curated = JSON.parse(read('curated_art.json')).items;
const picks = Object.fromEntries(Object.entries(curated).map(([id, v]) => [id, v.pick]));
const recurated = JSON.parse(read('recurated.json'));
const html = read('page.html')
  .replace('/*@CORE@*/', () => read('../round2/core.js'))
  .replace('/*@MARKS@*/', () => read('../round2/marks.js'))
  .replace('/*@GROUNDS@*/', () => read('../round4/grounds.js'))
  .replace('/*@PRIMS@*/', () => read('../round4/prims.js'))
  .replace('/*@BELLS@*/{}', () => JSON.stringify(JSON.parse(read('bells.json'))))
  .replace('/*@PLACES@*/', () => read('places.js'))
  .replace('/*@COMPOSE@*/', () => read('compose.js'))
  .replace('/*@SHIPPED@*/', () => read('../round4/shipped.js'))
  .replace('/*@EXPORT@*/', () => read('export.js'))
  .replace('/*@SYNTH@*/', () => read('bellsynth.js'))
  .replace('/*@APP@*/', () => read('app.js'))
  .replace('/*@PICKS@*/{}', () => JSON.stringify(picks))
  .replace('/*@RECURATED@*/[]', () => JSON.stringify(recurated))
  .replace('/*@TERRACE_BEFORE@*/null', () => JSON.stringify(JSON.parse(read('terrace_before.json'))));
writeFileSync(join(here, 'identity-round5.html'), html);
console.log(`identity-round5.html ${(Buffer.byteLength(html) / 1024).toFixed(1)} KB, ${Object.keys(picks).length} curated picks, ${recurated.length} re-curated`);
