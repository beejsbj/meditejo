"""Render reference PNGs of marks from the exploration page's generator.

    python3 -I tools/meditejo/branding/reference/render_reference.py OUT_DIR \
        --seeds g-1kq,m-2026-10-26 [--pal tide] [--px 256] [--t 60 --moving]
        [--values notch=0.045,nw=0.065 --suffix -clearv]

Needs Google Chrome (headless). Each seed is drawn on a tile, without the
paper finish for gesture and minimal marks (the page's `finish: false`);
atmospheric marks always carry it. The Dart port is checked against these
in test/widgets/branding/mark_reference_test.dart.
"""
import argparse
import base64
import html
import pathlib
import re
import subprocess
import urllib.parse

HERE = pathlib.Path(__file__).resolve().parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--seeds', required=True)
    ap.add_argument('--pal', default='tide')
    ap.add_argument('--px', default='256')
    ap.add_argument('--t', default='60')
    ap.add_argument('--moving', action='store_true', help='draw frame t, not the still frame')
    ap.add_argument('--suffix', default='')
    ap.add_argument('--values', default='', help='numbers to set on each mark, e.g. notch=0.045,nw=0.065')
    a = ap.parse_args()
    query = urllib.parse.urlencode({'seeds': a.seeds, 'pal': a.pal, 'px': a.px, 't': a.t, 'still': '0' if a.moving else '1',
                                   'values': a.values.replace('=', ':')})
    url = (HERE / 'render.html').as_uri() + '?' + query
    dom = subprocess.run(['google-chrome', '--headless=new', '--disable-gpu', '--dump-dom', url],
                         capture_output=True, text=True, check=True).stdout
    pre = html.unescape(re.search(r'<pre id="out">(.*?)</pre>', dom, re.S).group(1))
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for line in pre.strip().splitlines():
        seed, data = line.split(' ', 1)
        path = out / f'{seed}{a.suffix}.png'
        path.write_bytes(base64.b64decode(data.split(',', 1)[1]))
        print(path)


if __name__ == '__main__':
    main()
