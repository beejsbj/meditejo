#!/usr/bin/env python3
"""Build practice-figures-r<N>.html: a round (2 or later) of the practice
figures, one self-contained page (scripts, data and font subsets inlined).

    python build_r2.py [--round N] [--fonts DIR] [--out PATH ...]

Round N reads rN.json and rN-recommend.html; every round's figures file
that exists (figures-r2.js, figures-r3.js) is inlined.

Same needs as build.py (fontTools, brotli; the same font sources).
"""
import argparse
import json
import re
from pathlib import Path

from build import HERE, ROOT, face, woff2


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--fonts', default='/tmp/cat2/fonts')
    ap.add_argument('--round', type=int, default=2)
    ap.add_argument('--out', nargs='*')
    a = ap.parse_args()
    out = a.out or [f'/tmp/meditejo-runbooks/practice-figures-r{a.round}.html']
    read = lambda f: (HERE / f).read_text(encoding='utf-8') if (HERE / f).exists() else ''
    data = json.loads(read(f'r{a.round}.json'))
    page, app = read('page-r2.html'), read('app-r2.js')
    rec = read(f'r{a.round}-recommend.html')
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
            .replace('/*@TITLE@*/', data['title'])
            .replace('/*@LEDE@*/', data['lede'])
            .replace('/*@RECOMMEND@*/', rec)
            .replace('/*@CORE@*/', read('engine/core.js'))
            .replace('/*@GROUNDS@*/', read('engine/grounds.js'))
            .replace('/*@PRIMS@*/', read('engine/prims.js'))
            .replace('/*@FIGURES@*/', read('figures.js'))
            .replace('/*@FIGURES2@*/', read('figures-r2.js'))
            .replace('/*@FIGURES3@*/', read('figures-r3.js'))
            .replace('/*@APP@*/', app.replace('/*@DATA@*/{}', json.dumps(data, ensure_ascii=False))))
    assert not re.search(r'/\*@[A-Z0-9]+@\*/', html), 'unfilled placeholder'
    for o in out:
        p = Path(o)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(html, encoding='utf-8')
    print(f'{len(html.encode()) / 1024:.0f} KB -> {", ".join(out)}')


if __name__ == '__main__':
    main()
