#!/usr/bin/env python3
"""Build practices-identity.html: one self-contained page (scripts, data and
font subsets inlined) for the Ways-to-practise exploration.

    python build.py [--fonts DIR] [--out PATH ...]

Needs fontTools and brotli (`pip install fonttools brotli`) to subset the
fonts to the glyphs the page uses, so the tiles show every name in its own
script on any machine. Font sources (`--fonts`, default /tmp/cat2/fonts):
the app's Google Sans (assets/fonts/google-sans), Noto Sans Devanagari,
Noto Serif Tibetan, Noto Sans JP and Noto Sans SC (notofonts, OFL).
"""
import argparse
import base64
import io
import json
import re
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]

RECOMMEND = (
    '<b>What I’d build:</b> <b>B on Explore</b> (one carousel per group: the '
    'figures carry the identity, the groups teach the map, and Explore stays '
    'a front door rather than a wall of 36), with a “See all” that opens '
    '<b>A</b> as the practices page, and <b>C</b> in the Labels sheet, where '
    'density matters more than words. All three share one tile anatomy '
    '(figure, original name, tradition · script, one line), so it is one '
    'component in three sizes. The names table is ready to go into the '
    'asset; the ambiguous ones (Forgiveness, Noting, Chanting, Devotion, '
    'Movement, Visualisation) are yours to settle.'
)


def woff2(src, text, unicodes=()):
    font = TTFont(src)
    opts = subset.Options()
    opts.flavor = 'woff2'
    opts.layout_features = ['*']
    opts.name_IDs = ['*']
    opts.hinting = False
    sub = subset.Subsetter(opts)
    sub.populate(text=text, unicodes=list(unicodes))
    sub.subset(font)
    buf = io.BytesIO()
    font.flavor = 'woff2'
    font.save(buf)
    return base64.b64encode(buf.getvalue()).decode()


def face(family, weight, data):
    return (f"@font-face {{ font-family: '{family}'; font-weight: {weight}; "
            f"font-display: block; src: url(data:font/woff2;base64,{data}) format('woff2'); }}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--fonts', default='/tmp/cat2/fonts')
    ap.add_argument('--out', nargs='*', default=[str(HERE / 'practices-identity.html'), '/tmp/meditejo-runbooks/practices-identity.html'])
    a = ap.parse_args()
    read = lambda f: (HERE / f).read_text(encoding='utf-8')
    data = json.loads(read('practices.json'))
    page, figures, app = read('page.html'), read('figures.js'), read('app.js')
    text = page + figures + app + json.dumps(data, ensure_ascii=False)
    latin = range(0x20, 0x250)
    latin_ext = list(latin) + list(range(0x1E00, 0x1F00)) + list(range(0x2010, 0x2060)) + [0x2315, 0x25CF, 0x25AE]
    gs = ROOT / 'assets/fonts/google-sans'
    fdir = Path(a.fonts)
    faces = [
        face('Google Sans', 400, woff2(gs / 'GoogleSans-Regular.ttf', '', latin_ext)),
        face('Google Sans', 500, woff2(gs / 'GoogleSans-Medium.ttf', '', latin_ext)),
        face('Noto Sans Devanagari', 400, woff2(fdir / 'NotoSansDevanagari-Regular.ttf', ''.join(c for c in text if 0x0900 <= ord(c) < 0x0980))),
        face('Noto Serif Tibetan', 400, woff2(fdir / 'tib.ttf', ''.join(c for c in text if 0x0F00 <= ord(c) < 0x1000))),
        face('Noto Sans JP', 400, woff2(fdir / 'jp.otf', ''.join(c for c in text if ord(c) >= 0x3000 and c not in '气极'))),
        face('Noto Sans SC', 400, woff2(fdir / 'sc.otf', ''.join(c for c in text if c in '气功太极禅'))),
    ]
    html = (page
            .replace('/*@FONTS@*/', '\n'.join(faces))
            .replace('/*@RECOMMEND@*/', RECOMMEND)
            .replace('/*@CORE@*/', read('engine/core.js'))
            .replace('/*@GROUNDS@*/', read('engine/grounds.js'))
            .replace('/*@PRIMS@*/', read('engine/prims.js'))
            .replace('/*@FIGURES@*/', figures)
            .replace('/*@APP@*/', app.replace('/*@DATA@*/{}', json.dumps(data, ensure_ascii=False))))
    assert not re.search(r'/\*@[A-Z]+@\*/', html), 'unfilled placeholder'
    for out in a.out:
        p = Path(out)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(html, encoding='utf-8')
    print(f'{len(html.encode()) / 1024:.0f} KB -> {", ".join(a.out)}')


if __name__ == '__main__':
    main()
