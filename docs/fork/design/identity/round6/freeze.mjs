// Freeze each round 6 variant as a house_mark.json, in the format
// tools/meditejo/branding/house_mark.dart reads (fork/identity), and write
// the three SVGs that house_mark.dart then writes from it (with
// shelter_notch.patch applied), for checking.
// Run from anywhere: node docs/fork/design/identity/round6/freeze.mjs
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = dirname(fileURLToPath(import.meta.url));
const Shelter = createRequire(import.meta.url)(join(here, 'shelter.js'));
const baseText = readFileSync(join(here, 'base_house_mark.json'), 'utf8').trim(), base = JSON.parse(baseText);
const TIDE = { tile: '#E5EAEC', form: '#86A9B1', stroke: '#1E2C3A', accent: '#DE8A62' };
// MarkSpec writes numbers rounded to five places; a whole number as 1.0.
const num = (v) => { const r = Math.round(v * 1e5) / 1e5; return Number.isInteger(r) ? r.toFixed(1) : String(r); };
mkdirSync(join(here, 'marks'), { recursive: true });
for (const v of JSON.parse(readFileSync(join(here, 'variants.json'), 'utf8'))) {
  const values = { ...base.values, ...v.values };
  const text = baseText.replace(/"values":\{[^}]*\}/, `"values":{${Object.entries(values).map(([k, x]) => `"${k}":${num(x)}`).join(',')}}`);
  const m = JSON.parse(text);
  writeFileSync(join(here, 'marks', `${v.id}.json`), text + '\n');
  const s = Shelter.svgs(m, TIDE);
  writeFileSync(join(here, 'marks', `${v.id}.svg`), s.icon);
  writeFileSync(join(here, 'marks', `${v.id}_glyph.svg`), s.glyph);
  writeFileSync(join(here, 'marks', `${v.id}_square.svg`), s.square);
}
console.log('froze', readdir());
function readdir() { return JSON.parse(readFileSync(join(here, 'variants.json'), 'utf8')).map((v) => v.id).join(', '); }
