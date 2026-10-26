// Inline round 2's core (paper, ink, randomness), marks (palettes) and art
// (renamed Art2, for the side-by-side) with round 3's primitives and grammar
// into page.html -> identity-round3.html.
// Run from anywhere: node docs/fork/design/identity/round3/build.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const html = read('page.html')
  .replace('/*@CORE@*/', () => read('../round2/core.js'))
  .replace('/*@MARKS@*/', () => read('../round2/marks.js'))
  .replace('/*@ART2@*/', () => read('../round2/art.js').replace('const Art = (() => {', 'const Art2 = (() => {'))
  .replace('/*@PRIMS@*/', () => read('prims.js'))
  .replace('/*@COMPOSE@*/', () => read('compose.js'));
writeFileSync(join(here, 'identity-round3.html'), html);
console.log(`identity-round3.html ${(Buffer.byteLength(html) / 1024).toFixed(1)} KB`);
