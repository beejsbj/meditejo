// Freeze the curated picks into curated_art.json: for every item Meditejo
// ships, the candidate a person chose (by index into Compose.candidates),
// with its full composition (ground, figure, accent, seeds and every numeric
// parameter). The page exports the same format after changes.
// Run from anywhere: node docs/fork/design/identity/round4/curate.mjs [picks.json]
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const ctx = vm.createContext({ Math, JSON, console, document: { createElement: () => ({}) }, DOMMatrix: class {} });
vm.runInContext(['../round2/core.js', 'grounds.js', 'prims.js', 'compose.js', 'shipped.js', 'export.js'].map(read).join('\n;\n') + '\n;this.Export = Export;', ctx);
const picks = JSON.parse(read(process.argv[2] || 'picks.json'));
writeFileSync(join(here, 'curated_art.json'), JSON.stringify(ctx.Export.curated(picks), null, 1) + '\n');
console.log(`curated_art.json: ${Object.keys(picks).length} items`);
