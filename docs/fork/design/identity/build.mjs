// Inline generator.js and curated.js into page.html -> mark-explore.html.
// Run from anywhere: node docs/fork/design/identity/build.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const html = read('page.html')
  .replace('/*@GENERATOR@*/', () => read('generator.js'))
  .replace('/*@CURATED@*/', () => read('curated.js'));
writeFileSync(join(here, 'mark-explore.html'), html);
console.log(`mark-explore.html ${(Buffer.byteLength(html) / 1024).toFixed(1)} KB`);
