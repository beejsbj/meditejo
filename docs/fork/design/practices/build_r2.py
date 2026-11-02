#!/usr/bin/env python3
"""Build practice-figures-r2.html: round 2 of the practice figures, one
self-contained page (scripts, data and font subsets inlined).

    python build_r2.py [--fonts DIR] [--out PATH ...]

Same needs as build.py (fontTools, brotli; the same font sources).
"""
import argparse
import json
import re
from pathlib import Path

from build import HERE, ROOT, face, woff2

RECOMMEND = Path(HERE / 'r2-recommend.html')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--fonts', default='/tmp/cat2/fonts')
    ap.add_argument('--out', nargs='*', default=['/tmp/meditejo-runbooks/practice-figures-r2.html'])
    a = ap.parse_args()
    read = lambda f: (HERE / f).read_text(encoding='utf-8')
    data = json.loads(read('r2.json'))
    page, app = read('page-r2.html'), read('app-r2.js')
    rec = read('r2-recommend.html') if RECOMMEND.exists() else ''
    text = page + app + rec + json.dumps(data, ensure_ascii=False)
    latin_ext = list(range(0x20, 0x250)) + list(range(0x1E00, 0x1F00)) + list(range(0x2010, 0x2060)) + [0x2192, 0x00B7]
    gs = ROOT / 'assets/fonts/google-sans'
    fdir = Path(a.fonts)
    faces = [
        face('Google Sans', 400, woff2(gs / 'GoogleSans-Regular.ttf', '', latin_ext)),
        face('Google Sans', 500, woff2(gs / 'GoogleSans-Medium.ttf', '', latin_ext)),
        face('Noto Sans Devanagari', 400, woff2(fdir / 'NotoSansDevanagari-Regular.ttf', ''.join(c for c in text if 0x0900 <= ord(c) < 0x0980))),
        face('Noto Serif Tibetan', 400, woff2(fdir / 'tib.ttf', ''.join(c for c in text if 0x0F00 <= ord(c) < 0x1000))),
        face('Noto Sans SC', 400, woff2(fdir / 'sc.otf', ''.join(c for c in text if 0x4E00 <= ord(c) < 0xA000))),
    ]
    html = (page
            .replace('/*@FONTS@*/', '\n'.join(faces))
            .replace('/*@RECOMMEND@*/', rec)
            .replace('/*@CORE@*/', read('engine/core.js'))
            .replace('/*@GROUNDS@*/', read('engine/grounds.js'))
            .replace('/*@PRIMS@*/', read('engine/prims.js'))
            .replace('/*@FIGURES@*/', read('figures.js'))
            .replace('/*@FIGURES2@*/', read('figures-r2.js'))
            .replace('/*@APP@*/', app.replace('/*@DATA@*/{}', json.dumps(data, ensure_ascii=False))))
    assert not re.search(r'/\*@[A-Z0-9]+@\*/', html), 'unfilled placeholder'
    for out in a.out:
        p = Path(out)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(html, encoding='utf-8')
    print(f'{len(html.encode()) / 1024:.0f} KB -> {", ".join(a.out)}')


if __name__ == '__main__':
    main()
