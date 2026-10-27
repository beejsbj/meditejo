// Build identity-round6.html: shelter.js, the shipped house mark and the
// variants, in one self-contained page.
// Run from anywhere: node docs/fork/design/identity/round6/build.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const html = read('page.html')
  .replace('/*@SHELTER@*/', () => read('shelter.js'))
  .replace('/*@BASE@*/{}', () => read('base_house_mark.json').trim())
  .replace('/*@VARIANTS@*/[]', () => JSON.stringify(JSON.parse(read('variants.json'))));
writeFileSync(join(here, 'identity-round6.html'), html);
console.log(`identity-round6.html ${(Buffer.byteLength(html) / 1024).toFixed(1)} KB`);
