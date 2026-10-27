"""Render reference PNGs of the generated art with the identity page's own code.

    python3 -I tools/meditejo/art/reference/render_reference.py SPECS.json OUT_DIR

SPECS.json is a list of cards to draw. Each names one composition, either
frozen (as curated_art.json holds them) or built by the page from an id:

    {"name": "rain-terrace", "frozen": {...}}
    {"name": "user-course", "build": {"id": "my-course-1", "kind": "course"}}
    {"name": "mix", "preset": {"id": "p", "layers": [["rain-car", 0.7], ...]}}
    {"name": "c", "cls": "course", "seed": "x#3"}

and optionally "t" (seconds, default 60), "still" (default true), "H"
(height / width, default 1), "scrim", "only" ("ground", or "figure" for
the figures on flat paper), "px" (default 256) and "pal" (default "tide"). For each card it writes NAME.png and NAME.json, the
frozen composition it drew, so the Dart port can be checked against both
(test/widgets/art/art_reference_test.dart).

Needs Google Chrome (headless). The page sources here are copies from
fork/mark-explore (a15aefda): round 2's core.js and marks.js live in
tools/meditejo/branding/reference/; grounds.js and prims.js are round 4's,
places.js, compose.js and bells.json round 5's.
"""
import argparse
import concurrent.futures
import base64
import html
import json
import pathlib
import re
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
BRANDING = HERE.parent.parent / 'branding' / 'reference'

PAGE = """<!doctype html><html><body style="margin:0">
<script>var BellData = %(bells)s;</script>
<script src="%(core)s"></script><script src="%(marks)s"></script>
<script src="%(grounds)s"></script><script src="%(prims)s"></script>
<script src="%(places)s"></script><script src="%(compose)s"></script>
<script>
const SPECS = %(specs)s;
const thaw = (e) => ({ cls: e.cls, seed: e.seed, ground: { name: e.ground.name, p: e.ground.params }, figure: e.figure && { name: e.figure.name, kind: e.figure.kind, layout: e.figure.layout, p: e.figure.params }, accent: e.accent && { name: e.accent.name, kind: e.accent.kind, p: e.accent.params }, inkSeed: e.inkSeed, mis: e.misregister });
const out = [];
for (const s of SPECS) {
  let comp;
  if (s.frozen) comp = thaw(JSON.parse(JSON.stringify(s.frozen)));
  else if (s.build) comp = Compose.buildFor(s.build.id, s.build.kind, s.build.seed);
  else if (s.preset) comp = Compose.buildPreset(s.preset, s.preset.seed);
  else comp = Compose.build(s.cls, s.seed);
  const px = s.px || 256, H = s.H || 1, cv = document.createElement('canvas');
  cv.width = px; cv.height = Math.round(px * H);
  const ctx = cv.getContext('2d'); ctx.scale(px, px);
  Compose.draw(ctx, comp, Marks.PAL[s.pal || 'tide'], s.t ?? 60, { still: s.still ?? true, px, H, scrim: !!s.scrim, only: s.only });
  out.push(s.name + ' ' + cv.toDataURL('image/png') + ' ' + btoa(unescape(encodeURIComponent(JSON.stringify(Compose.freeze(comp))))));
}
const pre = document.createElement('pre'); pre.id = 'out'; pre.textContent = out.join('\\n'); document.body.appendChild(pre);
</script></body></html>
"""


def render(specs, out):
    page = PAGE % {
        'bells': (HERE / 'bells.json').read_text(),
        'core': (BRANDING / 'core.js').as_uri(),
        'marks': (BRANDING / 'marks.js').as_uri(),
        'grounds': (HERE / 'grounds.js').as_uri(),
        'prims': (HERE / 'prims.js').as_uri(),
        'places': (HERE / 'places.js').as_uri(),
        'compose': (HERE / 'compose.js').as_uri(),
        'specs': json.dumps(specs),
    }
    with tempfile.TemporaryDirectory() as tmp:
        page_file = pathlib.Path(tmp) / 'render.html'
        page_file.write_text(page)
        # Headless Chrome now and then hangs under load: give each run a
        # deadline and try again.
        for attempt in range(3):
            try:
                dom = subprocess.run(['google-chrome', '--headless=new', '--disable-gpu', '--allow-file-access-from-files',
                                      f'--user-data-dir={tmp}/profile{attempt}', '--dump-dom', page_file.as_uri()],
                                     capture_output=True, text=True, check=True, timeout=120).stdout
                break
            except subprocess.TimeoutExpired:
                if attempt == 2:
                    raise
    found = re.search(r'<pre id="out">(.*?)</pre>', dom, re.S)
    if not found:
        raise SystemExit('the page drew nothing; open it in a browser to see the error')
    names = []
    for line in html.unescape(found.group(1)).strip().splitlines():
        name, png, frozen = line.split(' ', 2)
        (out / f'{name}.png').write_bytes(base64.b64decode(png.split(',', 1)[1]))
        (out / f'{name}.json').write_text(json.dumps(json.loads(base64.b64decode(frozen)), indent=1) + '\n')
        names.append(name)
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('specs')
    ap.add_argument('out')
    ap.add_argument('--batch', type=int, default=60, help='cards per browser run')
    ap.add_argument('--jobs', type=int, default=3, help='browser runs at once')
    a = ap.parse_args()
    specs = json.loads(pathlib.Path(a.specs).read_text())
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    batches = [specs[i:i + a.batch] for i in range(0, len(specs), a.batch)]
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as pool:
        for names in pool.map(lambda b: render(b, out), batches):
            print(f'{len(names)} cards: {names[0]} .. {names[-1]}', flush=True)


if __name__ == '__main__':
    main()
