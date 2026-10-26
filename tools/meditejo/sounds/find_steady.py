#!/usr/bin/env python3
"""Suggest a loop window for each sound in `sources.json`.

Nobody has to audition every recording to avoid the worst cuts: a loop
that holds a thunder clap, a door or a burst of voices repeats it every
lap. This scans each source in 100 ms frames (level after a 120 Hz
high-pass by default, so wind rumble doesn't dominate; see --highpass) and scores every candidate
window of `loop + crossfade` seconds:

* transients: how far the loudest frames rise above the window's median
  (95th and 99.5th percentile, in dB);
* drift: how much the 3 s average level wanders across the window, and how
  different the two ends are (the crossfade hides a little, not a lot).

The lowest score wins. It prints the suggestion and the scores; the chosen
`start` is written to `sources.json` by hand (or with --write), so the build
stays reproducible from the manifest alone.

    python3 tools/meditejo/sounds/find_steady.py [--only ID] [--write]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import process_sounds as ps  # noqa: E402

RATE = 16000
FRAME = RATE // 10


def levels(path: Path, highpass: float = 120) -> np.ndarray:
    raw = subprocess.run(
        ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-i', str(path),
         '-af', f'highpass=f={highpass:g}', '-ac', '1', '-ar', str(RATE), '-f', 'f32le', '-'],
        capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype='<f4')
    n = len(x) // FRAME
    frames = x[:n * FRAME].reshape(n, FRAME).astype(np.float64)
    return 10 * np.log10((frames ** 2).mean(axis=1) + 1e-12)


def score(db: np.ndarray, start: int, width: int, xf: int) -> dict:
    w = db[start:start + width]
    med = np.median(w)
    smooth = np.convolve(w, np.ones(30) / 30, mode='valid')
    ends = abs(np.mean(w[:xf]) - np.mean(w[-2 * xf:-xf])) if xf else 0.0
    out = {
        'p95': float(np.percentile(w, 95) - med),
        'p995': float(np.percentile(w, 99.5) - med),
        'drift': float(smooth.std()),
        'ends': float(ends),
        'median': float(med),
    }
    out['score'] = out['p95'] + 0.5 * out['p995'] + 2 * out['drift'] + out['ends']
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', action='append')
    ap.add_argument('--write', action='store_true', help='store the suggested start')
    ap.add_argument('--highpass', type=float, default=120,
                    help='Hz; lower it (30-50) for sounds whose loudness is low-frequency '
                         'rumble (trains, surf), so a thump below 120 Hz still counts')
    ap.add_argument('--cache', type=Path, default=Path.home() / '.cache/meditejo-sounds')
    args = ap.parse_args()
    manifest = json.loads(ps.SOURCES.read_text())
    for s in manifest['sounds']:
        if args.only and s['id'] not in args.only:
            continue
        src = ps.fetch(s, args.cache, pin=True)
        db = levels(src, args.highpass)
        width = round((float(s['loop']) + float(s['crossfade'])) * 10)
        xf = round(float(s['crossfade']) * 10)
        margin = 10  # skip the first and last second (handling, fades)
        last = len(db) - width - margin
        if last < margin:
            starts = [0]
            if len(db) < width:
                print(f"{s['id']}: source {len(db) / 10:.1f}s is shorter than the window "
                      f'{width / 10:.1f}s', file=sys.stderr)
                continue
        else:
            starts = range(margin, last + 1, 5)
        best = min(starts, key=lambda st: score(db, st, width, xf)['score'])
        b = score(db, best, width, xf)
        whole = score(db, 0, len(db), 0)
        print(f"{s['id']:15} start {best / 10:6.1f}s  score {b['score']:5.1f} "
              f"(p95 {b['p95']:.1f} p99.5 {b['p995']:.1f} drift {b['drift']:.2f} ends {b['ends']:.2f})  "
              f"whole-file p99.5 {whole['p995']:.1f}  level {b['median']:.0f} dB  "
              f"source {len(db) / 10:.0f}s")
        if args.write:
            s['start'] = best / 10
    if args.write:
        ps.SOURCES.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
