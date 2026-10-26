#!/usr/bin/env python3
"""Per-file numbers for the bundled cue bells, and an audio sampler.

Reads the catalogue (name and asset) from `cueBellSounds` in
lib/models/cues/cue_settings.dart, so the report and the sampler cover exactly
what the app offers, in the app's order.

    python3 tools/meditejo/bells_report.py                   # Markdown table
    python3 tools/meditejo/bells_report.py --sampler out.wav  # all bells in sequence
    python3 tools/meditejo/bells_report.py --fail-on-defect   # CI: exit 1 on a click, DC offset, ...
"""
import argparse
import math
import re
import struct
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_bells import measure, momentary_lufs  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CATALOGUE = ROOT / 'lib/models/cues/cue_settings.dart'


def catalogue():
    source = CATALOGUE.read_text()
    block = re.search(r'const cueBellSounds = <String, String>\{(.*?)\};', source, re.S)
    entries = re.findall(r"'([^']*)':\s*'([^']*)'", block.group(1))
    return [(name, path) for name, path in entries if path]


def db(v):
    return 20 * math.log10(v) if v > 0 else -math.inf


def stats(path):
    x, rate = measure(ROOT / path)
    n = len(x)
    peak = max(abs(v) for v in x)
    rms = math.sqrt(sum(v * v for v in x) / n)
    window = round(rate * 0.05)
    env = [math.sqrt(sum(v * v for v in x[i:i + window]) / window)
           for i in range(0, n - window, window)]
    top = max(range(len(env)), key=env.__getitem__)
    t40 = next((i for i in range(top, len(env)) if env[i] < env[top] * 0.01), len(env))
    return {
        'seconds': n / rate, 'rate': rate, 'bytes': (ROOT / path).stat().st_size,
        'peak': db(peak), 'rms': db(rms), 'momentary': max(momentary_lufs(x, rate)),
        'first': x[0], 'last': x[-1], 'dc': sum(x) / n,
        'onset': max(abs(v) for v in x[:round(rate * 0.0005)]) / peak,
        'tail': db(math.sqrt(sum(v * v for v in x[-round(rate * 0.1):]) / round(rate * 0.1))),
        't40': (t40 - top) * 0.05,
    }


def defects(s):
    out = []
    if s['first'] != 0 or s['last'] != 0:
        out.append('does not start and end on zero')
    if abs(s['dc']) > 1e-3:
        out.append('DC offset')
    if s['onset'] > 0.25:
        out.append('does not ramp in over the first 0.5 ms')
    if s['peak'] > -0.9:
        out.append('peak above -1 dBFS')
    if s['tail'] > -40:
        out.append('tail still loud at the end')
    return out


def table(rows):
    lines = ['| Sound | File | Length | Rate | Size | Peak | RMS | Momentary max | '
             '40 dB down | End | DC |',
             '|---|---|---|---|---|---|---|---|---|---|---|']
    for name, path, s in rows:
        lines.append(
            f"| {name} | `{Path(path).name}` | {s['seconds']:.2f} s | {s['rate'] / 1000:g} kHz "
            f"| {s['bytes'] / 1024:.0f} KiB | {s['peak']:.1f} dBFS | {s['rms']:.1f} dBFS "
            f"| {s['momentary']:.1f} LUFS | {s['t40']:.2f} s "
            f"| {'0' if s['last'] == 0 else s['last']} | {s['dc']:.1e} |")
    total = sum(s['bytes'] for _, _, s in rows)
    lines.append(f'\n{len(rows)} bells, {total / 1024:.0f} KiB.')
    return '\n'.join(lines)


def sampler(rows, output):
    """Every bell in the app's order, each rung once, with a pause between.
    A 44.1 kHz mono WAV, written with the standard library alone (the 22.05 kHz
    bells are doubled by linear interpolation)."""
    out, offsets, gap = [], [], [0.0] * round(44100 * 1.2)
    for name, path, s in rows:
        x, rate = measure(ROOT / path)
        if rate == 22050:
            x = [v for a, b in zip(x, x[1:] + [0.0]) for v in (a, (a + b) / 2)]
        offsets.append(f'{int(len(out) / 44100 // 60)}:{len(out) / 44100 % 60:04.1f}  {name}')
        out += x + gap
    with wave.open(str(output), 'wb') as wav:
        wav.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
        wav.writeframes(b''.join(struct.pack('<h', round(v * 32767)) for v in out))
    return offsets


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--sampler', metavar='OUT', help='write all bells in sequence (44.1 kHz mono WAV)')
    parser.add_argument('--fail-on-defect', action='store_true')
    args = parser.parse_args()
    rows = [(name, path, stats(path)) for name, path in catalogue()]
    print(table(rows))
    bad = [(name, d) for name, _, s in rows for d in defects(s)]
    for name, d in bad:
        print(f'DEFECT {name}: {d}', file=sys.stderr)
    if args.sampler:
        print('\nSampler timeline:\n' + '\n'.join(sampler(rows, args.sampler)))
    return 1 if bad and args.fail_on_defect else 0


if __name__ == '__main__':
    sys.exit(main())
