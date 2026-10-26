// Inline the round 2 sources into page.html -> identity-round2.html.
// Run from anywhere: node docs/fork/design/identity/round2/build.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const html = read('page.html')
  .replace('/*@CORE@*/', () => read('core.js'))
  .replace('/*@MARKS@*/', () => read('marks.js'))
  .replace('/*@ART@*/', () => read('art.js'))
  .replace('/*@CURATED@*/', () => read('curated.js'));
writeFileSync(join(here, 'identity-round2.html'), html);
console.log(`identity-round2.html ${(Buffer.byteLength(html) / 1024).toFixed(1)} KB`);
