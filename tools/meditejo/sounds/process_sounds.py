#!/usr/bin/env python3
"""Build Meditejo's bundled sound library from `sources.json`.

For each sound: download the original (pinned by SHA-256), cut a loop,
bake a seamless crossfade into it, normalise its loudness, and encode it as
Ogg Opus into `assets/sounds/`. Then write `assets/sounds/sounds.json` (the
licence-as-data the app reads), `assets/sounds/NOTICE`, and
`tools/meditejo/sounds/commands.log` (every ffmpeg command run, exactly).

    python3 tools/meditejo/sounds/process_sounds.py            # all sounds
    python3 tools/meditejo/sounds/process_sounds.py --only rain-light
    python3 tools/meditejo/sounds/process_sounds.py --pin       # record new hashes
    python3 tools/meditejo/sounds/process_sounds.py --recheck-licences  # ask Freesound again

Requires ffmpeg/ffprobe (with libopus) on PATH and numpy. Downloads are
cached outside the repo (`--cache`, default ~/.cache/meditejo-sounds) and are
treated as data: only ffmpeg reads them.

Sources. A sound with `downloadUrl` is fetched over HTTP. A sound with
`"freesound": <id>` is a Freesound original, which needs an account:
on a cache miss it asks `meditejo-freesound-fetch info` for the live licence
and refuses anything that is not what sources.json declares (only CC0 and
CC BY 3.0/4.0 are known; CC BY entries must carry author, originalTitle and
pageUrl for their credit), then `meditejo-freesound-fetch get` for the file,
a few seconds apart because Freesound rate-limits. The tool holds the OAuth
tokens; this script never sees them. Where the tool is missing (CI, other
machines) a cached, pinned original still works, and anything else stops
with a message saying so. Either way the SHA-256 pins the bytes.

The loop. A segment of `loop + crossfade` seconds is cut from `start`. Its
first `crossfade` seconds are blended (equal power) with the `crossfade`
seconds that follow the loop's end, and the tail is dropped. The last sample
of the loop is then followed, on wrap-around, by what originally came after
it, so the seam is continuous by construction.

Loudness. ffmpeg `loudnorm` measures the loop (EBU R128). A single static
gain then moves it to `targetLufs`. A static gain keeps the loop seamless (a
dynamic normaliser would leave different gain at its two ends). Where that
gain would push the true peak over `truePeakCeiling`, a peak limiter takes
up to `maxLimitDb` (default 6) off the peaks, run over the loop padded
circularly so its state matches across the seam; beyond that the gain is
held back and the sound stays quieter than the target. The encoded file is
measured again and both measurements are recorded. If the codec pushes its
true peak more than 0.25 dB over the ceiling (spiky sounds can), the excess is
taken off the static gain and the loop is encoded again, twice at most.

The seam. `seam_metrics` decodes the shipped Opus file and compares the half
second before the loop point with the half second after it (they are
neighbours on wrap-around): level change in dB, and RMS difference across
third-octave bands. Each is recorded next to its own 95th percentile at every
other point in the loop, so the seam can be read against how much the loop
changes anywhere. A seam at or under that p95 is ordinary.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCES = HERE / 'sources.json'
COMMANDS_LOG = HERE / 'commands.log'
OUT_DIR = ROOT / 'assets/sounds'
RATE = 48000

LICENSES = {
    'CC0-1.0': ('CC0 1.0', 'https://creativecommons.org/publicdomain/zero/1.0/'),
    'CC-BY-3.0': ('CC BY 3.0', 'https://creativecommons.org/licenses/by/3.0/'),
    'CC-BY-4.0': ('CC BY 4.0', 'https://creativecommons.org/licenses/by/4.0/'),
    'PD': ('Public domain', ''),
}
CATEGORIES = ('rain', 'water', 'wind', 'forest', 'fire', 'room', 'night')

# Freesound originals need an account. `meditejo-freesound-fetch` (installed on
# Burooj's machines only) holds the OAuth tokens and is the only way this script
# touches Freesound; it never gets to read or print them.
FREESOUND_TOOL = 'meditejo-freesound-fetch'
FREESOUND_PAUSE_S = 4.0  # Freesound rate-limits; downloads go serially, apart
# Freesound's licence URL (scheme and trailing slash dropped) -> our SPDX id.
# Anything not listed (NC, SA, Sampling+, ...) is refused outright.
FREESOUND_LICENSES = {
    'creativecommons.org/publicdomain/zero/1.0': 'CC0-1.0',
    'creativecommons.org/licenses/by/3.0': 'CC-BY-3.0',
    'creativecommons.org/licenses/by/4.0': 'CC-BY-4.0',
}

commands: list[str] = []


def run(cmd: list[str], *, capture_stderr: bool = False) -> str:
    commands.append(shlex.join(cmd))
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr[-4000:])
        raise SystemExit(f'command failed: {shlex.join(cmd)}')
    return proc.stderr if capture_stderr else proc.stdout


def run_bytes(cmd: list[str]) -> bytes:
    commands.append(shlex.join(cmd))
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode(errors='replace')[-4000:])
        raise SystemExit(f'command failed: {shlex.join(cmd)}')
    return proc.stdout


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def freesound_tool() -> str:
    tool = shutil.which(FREESOUND_TOOL)
    if not tool:
        raise SystemExit(
            f'{FREESOUND_TOOL} is not on PATH. Freesound originals can only be '
            'downloaded where Burooj has authorised the Freesound app. On other '
            'machines (CI included) the original must already be in the cache '
            '(--cache), pinned by sha256; the sources that use plain URLs are '
            'unaffected (use --only to skip the Freesound ones).')
    return tool


def freesound_info(sound: dict) -> dict:
    proc = subprocess.run([freesound_tool(), 'info', str(sound['freesound'])],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr[-2000:])
        raise SystemExit(f"{sound['id']}: {FREESOUND_TOOL} info {sound['freesound']} failed")
    return json.loads(proc.stdout)


def check_freesound_licence(sound: dict, info: dict) -> None:
    """Refuse a sound whose live Freesound record disagrees with the manifest.
    Only CC0, and CC BY where the credit path carries it, can get this far."""
    url = str(info.get('license', '')).split('://', 1)[-1].rstrip('/')
    actual = FREESOUND_LICENSES.get(url)
    if actual is None:
        raise SystemExit(f"{sound['id']}: Freesound {sound['freesound']} is under "
                         f"{info.get('license')!r}, which Meditejo does not accept")
    if actual != sound['license']:
        raise SystemExit(f"{sound['id']}: Freesound says {actual}, sources.json says "
                         f"{sound['license']}; check the page and fix the manifest")
    if info.get('username') != sound['author']:
        raise SystemExit(f"{sound['id']}: Freesound author is {info.get('username')!r}, "
                         f"sources.json says {sound['author']!r}")
    print(f"  licence {actual} confirmed by {FREESOUND_TOOL} info")


def freesound_download(sound: dict, cache: Path) -> Path:
    n = sound['freesound']
    for hit in sorted(cache.glob(f'freesound-{n}.*')):
        if not hit.name.endswith('.part'):
            return hit
    info = freesound_info(sound)
    check_freesound_licence(sound, info)
    path = cache / f"freesound-{n}.{info.get('type') or 'bin'}"
    part = path.with_name(path.name + '.part')
    print(f'  downloading Freesound {n} ({int(info.get("filesize", 0)) / 1048576:.1f} MiB)')
    proc = subprocess.run([freesound_tool(), 'get', str(n), str(part)], capture_output=True, text=True)
    if proc.returncode != 0 or not part.exists():
        sys.stderr.write(proc.stderr[-2000:])
        part.unlink(missing_ok=True)
        raise SystemExit(f"{sound['id']}: {FREESOUND_TOOL} get {n} failed")
    part.rename(path)
    time.sleep(FREESOUND_PAUSE_S)
    return path


def fetch(sound: dict, cache: Path, pin: bool) -> Path:
    cache.mkdir(parents=True, exist_ok=True)
    if 'freesound' in sound:
        if not sound.get('sha256') and any(cache.glob(f"freesound-{sound['freesound']}.*")):
            # About to pin a file found in the cache: ask Freesound about it
            # first, since the cache hit would skip the check.
            check_freesound_licence(sound, freesound_info(sound))
        path = freesound_download(sound, cache)
    else:
        url = sound['downloadUrl']
        name = hashlib.sha256(url.encode()).hexdigest()[:16] + '-' + Path(url.split('?')[0]).name
        path = cache / name
        if not path.exists():
            print(f'  downloading {url}')
            req = urllib.request.Request(url, headers={'User-Agent': 'meditejo-sound-builder/1'})
            with urllib.request.urlopen(req, timeout=120) as resp, open(path.with_suffix('.part'), 'wb') as f:
                while chunk := resp.read(1 << 16):
                    f.write(chunk)
            path.with_suffix('.part').rename(path)
    digest = sha256_of(path)
    expected = sound.get('sha256')
    if expected and expected != digest:
        raise SystemExit(f"{sound['id']}: source changed: sha256 {digest} != pinned {expected}")
    if not expected:
        if not pin:
            raise SystemExit(f"{sound['id']}: no pinned sha256; rerun with --pin to record {digest}")
        sound['sha256'] = digest
    member = sound.get('archiveMember')
    if member:
        # Read one named member as bytes; nothing in the archive is executed
        # or extracted by its own path.
        extracted = cache / f'{path.name}--{Path(member).name}'
        if not extracted.exists():
            with zipfile.ZipFile(path) as archive:
                extracted.write_bytes(archive.read(member))
        return extracted
    return path


def decode(src: Path, sound: dict, workdir: Path) -> np.ndarray:
    channels = int(sound['channels'])
    start, loop, xf = float(sound['start']), float(sound['loop']), float(sound['crossfade'])
    raw = workdir / f"{sound['id']}.src.f32"
    af = ['aresample=filter_size=64:phase_shift=10:cutoff=0.97']
    if sound.get('filters'):
        af.insert(0, sound['filters'])
    run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
         '-ss', f'{start}', '-t', f'{loop + xf}', '-i', str(src),
         '-af', ','.join(af), '-ac', str(channels), '-ar', str(RATE),
         '-f', 'f32le', str(raw)])
    data = np.fromfile(raw, dtype='<f4').reshape(-1, channels)
    raw.unlink()
    need = round((loop + xf) * RATE)
    if len(data) < need - RATE // 100:
        raise SystemExit(f"{sound['id']}: source too short for start+loop+crossfade "
                         f'({len(data) / RATE:.1f}s < {need / RATE:.1f}s)')
    return data


def bake_loop(seg: np.ndarray, loop_s: float, xf_s: float) -> np.ndarray:
    n_loop, n_xf = round(loop_s * RATE), round(xf_s * RATE)
    n_xf = min(n_xf, len(seg) - n_loop)
    out = seg[:n_loop].astype(np.float64).copy()
    t = (np.arange(n_xf) + 0.5) / n_xf
    fade_in, fade_out = np.sin(t * np.pi / 2)[:, None], np.cos(t * np.pi / 2)[:, None]
    out[:n_xf] = seg[:n_xf] * fade_in + seg[n_loop:n_loop + n_xf] * fade_out
    return out


def seam_rank(loop: np.ndarray) -> float:
    """Percentile of the wrap-around step among all sample steps. A seamless
    loop's seam is an ordinary step (anywhere from 0 to 100, typically
    middling); a click would sit at 100."""
    steps = np.abs(np.diff(loop, axis=0)).mean(axis=1)
    seam = np.abs(loop[0] - loop[-1]).mean()
    return float((steps < seam).mean() * 100)


SEAM_WINDOW_S = 0.5
SEAM_HOP_S = 0.25
# Third-octave band edges, 63 Hz to 16 kHz: where ambience carries its character.
SEAM_BANDS = [63.0 * 2 ** (i / 3) for i in range(0, 25) if 63.0 * 2 ** (i / 3) <= 16000]


def _band_db(window: np.ndarray) -> np.ndarray:
    """Mean power per third-octave band of a window (channels averaged), dB."""
    n = len(window)
    spec = np.abs(np.fft.rfft(window * np.hanning(n)[:, None], axis=0)) ** 2
    power = spec.mean(axis=1)
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    out = []
    for lo, hi in zip(SEAM_BANDS[:-1], SEAM_BANDS[1:]):
        sel = (freqs >= lo) & (freqs < hi)
        out.append(power[sel].mean() if sel.any() else 1e-20)
    return 10 * np.log10(np.array(out) + 1e-20)


def seam_metrics(loop: np.ndarray) -> dict:
    """How different the half second after the loop point is from the half
    second before it (they are neighbours on wrap-around), against how
    different any two neighbouring half-seconds are inside the loop.

    * rmsStepDb: level change in dB across the seam; rmsStepP95Db is the 95th
      percentile of the same change at every other point (hop 0.25 s).
    * spectralDb: RMS difference in dB across third-octave bands (63 Hz to
      16 kHz) across the seam; spectralP95Db is the 95th percentile elsewhere.
    A seam at or under the loop's own p95 is as ordinary as the rest of it.
    """
    w, hop = round(SEAM_WINDOW_S * RATE), round(SEAM_HOP_S * RATE)
    n = len(loop)
    if n < 2 * w:
        raise SystemExit(f'loop of {n / RATE:.2f} s is too short to measure a seam '
                         f'(needs {2 * SEAM_WINDOW_S:g} s)')

    def step(before: np.ndarray, after: np.ndarray) -> tuple[float, float]:
        level = 10 * np.log10((after ** 2).mean() + 1e-20) - 10 * np.log10((before ** 2).mean() + 1e-20)
        spectral = float(np.sqrt(((_band_db(after) - _band_db(before)) ** 2).mean()))
        return abs(float(level)), spectral

    rms_seam, spec_seam = step(loop[n - w:], loop[:w])
    inner = [step(loop[p - w:p], loop[p:p + w]) for p in range(w, n - w + 1, hop)]
    rms_in, spec_in = (np.array(c) for c in zip(*inner))
    return {
        'rmsStepDb': round(rms_seam, 2),
        'rmsStepP95Db': round(float(np.percentile(rms_in, 95)), 2),
        'spectralDb': round(spec_seam, 2),
        'spectralP95Db': round(float(np.percentile(spec_in, 95)), 2),
    }


def decode_asset(path: Path, channels: int) -> np.ndarray:
    """The shipped Opus file back to float samples, for measuring the seam as
    the app will play it."""
    raw = run_bytes(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-i', str(path),
                     '-f', 'f32le', '-ar', str(RATE), '-ac', str(channels), '-'])
    return np.frombuffer(raw, dtype='<f4').reshape(-1, channels).astype(np.float64)


def limit_circular(loop: np.ndarray, ceiling_db: float, workdir: Path, sid: str) -> np.ndarray:
    """Peak-limit [loop] as if it repeated forever: limit tail+loop+head and
    keep the middle, so the limiter's state matches on both sides of the
    seam."""
    pad = 2 * RATE
    channels = loop.shape[1]
    padded = np.concatenate([loop[-pad:], loop, loop[:pad]])
    src, dst = workdir / f'{sid}.lim-in.f32', workdir / f'{sid}.lim-out.f32'
    padded.astype('<f4').tofile(src)
    limit = 10 ** (ceiling_db / 20)
    run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
         '-f', 'f32le', '-ar', str(RATE), '-ac', str(channels), '-i', str(src),
         '-af', f'alimiter=limit={limit:.6f}:attack=5:release=80:level=disabled:latency=1',
         '-f', 'f32le', str(dst)])
    out = np.fromfile(dst, dtype='<f4').reshape(-1, channels).astype(np.float64)
    src.unlink()
    dst.unlink()
    return out[pad:pad + len(loop)]


def loudness(path: Path, channels: int, *, raw: bool, target: float, ceiling: float) -> dict:
    fmt = ['-f', 'f32le', '-ar', str(RATE), '-ac', str(channels)] if raw else []
    err = run(['ffmpeg', '-nostdin', '-hide_banner', '-nostats', *fmt, '-i', str(path),
               '-af', f'loudnorm=I={target}:TP={ceiling}:LRA=20:print_format=json',
               '-f', 'null', '-'], capture_stderr=True)
    blob = err[err.rindex('{'):err.rindex('}') + 1]
    m = json.loads(blob)
    return {'lufs': round(float(m['input_i']), 2), 'truePeak': round(float(m['input_tp']), 2),
            'lra': round(float(m['input_lra']), 2)}


def process(sound: dict, src: Path, workdir: Path, target: float, ceiling: float) -> dict:
    sid, channels = sound['id'], int(sound['channels'])
    loop = bake_loop(decode(src, sound, workdir), float(sound['loop']), float(sound['crossfade']))
    pre = workdir / f'{sid}.loop.f32'
    loop.astype('<f4').tofile(pre)
    before = loudness(pre, channels, raw=True, target=target, ceiling=ceiling)
    out = OUT_DIR / f'{sid}.opus'
    bitrate = int(sound.get('bitrate', 64 if channels == 2 else 40))
    max_limit = float(sound.get('maxLimitDb', 6))
    base, extra = loop, 0.0
    for attempt in range(3):
        gain = target - before['lufs'] - extra
        # Peaky sounds (crackle, drips) would need more peak room than the
        # ceiling allows. A limiter takes up to maxLimitDb off the peaks; past
        # that the gain is held back and the sound stays under the target.
        over = before['truePeak'] + gain - ceiling
        limiting = 0.0
        if over > 0:
            limiting = min(over, max_limit)
            gain -= over - limiting
        loop = base * 10 ** (gain / 20)
        if limiting > 0:
            # Sample-peak limiter, 1 dB under the true-peak ceiling for the
            # inter-sample overs it can't see.
            loop = limit_circular(loop, ceiling - 1, workdir, sid)
        loop.astype('<f4').tofile(pre)
        run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
             '-f', 'f32le', '-ar', str(RATE), '-ac', str(channels), '-i', str(pre),
             '-c:a', 'libopus', '-b:a', f'{bitrate}k', '-vbr', 'on', '-compression_level', '10',
             '-application', 'audio', '-frame_duration', '20',
             '-map_metadata', '-1', '-fflags', '+bitexact', '-flags:a', '+bitexact', str(out)])
        after = loudness(out, channels, raw=False, target=target, ceiling=ceiling)
        # Spiky sounds can overshoot the ceiling again in the codec. Take the
        # excess off the (static) gain and encode again, twice at most.
        if after['truePeak'] <= ceiling + 0.25:
            break
        extra += after['truePeak'] - ceiling
    else:
        # The limiter holds sample peaks at a fixed level whatever the gain, so
        # lowering the gain cannot always bring the codec's overshoot down.
        sys.stderr.write(f"warning: {sid}: true peak {after['truePeak']} dBTP is still over "
                         f'the {ceiling} dBTP ceiling after {attempt + 1} encodes\n')
    pre.unlink()
    probe = json.loads(run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                            '-of', 'json', str(out)]))
    return {
        'gainDb': round(gain, 2),
        'limiterDb': round(limiting, 2),
        'measuredBefore': before,
        'measuredAfter': after,
        'seamRank': round(seam_rank(loop), 1),
        # Measured on the encoded file, decoded: the loop as the app plays it.
        'seam': seam_metrics(decode_asset(out, channels)),
        'bitrateKbps': bitrate,
        'bytes': out.stat().st_size,
        'durationMs': round(float(probe['format']['duration']) * 1000),
    }


def modifications(sound: dict, rec: dict) -> str:
    ch = 'stereo' if int(sound['channels']) == 2 else 'mono'
    xf = float(sound['crossfade'])
    parts = [f"excerpt of {sound['loop']:g} s from {sound['start']:g} s",
             f"looped with a {xf:g} s crossfade" if xf else 'already a seamless loop, used without a crossfade',
             f"gain {rec['gainDb']:+.1f} dB"
             + (f", peaks limited by up to {rec['limiterDb']:.1f} dB" if rec['limiterDb'] else '')
             + f" (to about {rec['measuredAfter']['lufs']:.0f} LUFS)",
             f"{ch} Opus {rec['bitrateKbps']} kbps"]
    if sound.get('filters'):
        parts.insert(1, f"filtered ({sound['filters']})")
    if sound.get('extraChanges'):
        parts.insert(0, sound['extraChanges'])
    return '; '.join(parts)


def notice(entries: list[dict]) -> str:
    lines = [
        'Meditejo sound library: third-party recordings',
        '',
        'The recordings in this directory are separate works bundled with',
        'Meditejo. Each keeps its own licence, listed below. They are not',
        'covered by the AGPL-3.0 licence of the Meditejo source code.',
        '',
        'Every file was modified: cut to a loop (crossfaded at the seam unless',
        'the original was already a seamless loop), gain-adjusted, and',
        're-encoded. The changes are listed per file.',
        'Generated by tools/meditejo/sounds/process_sounds.py; do not edit.',
        '',
    ]
    for e in entries:
        lic = e['license']
        lines += [
            f"{Path(e['asset']).name}: \"{e['title']}\"",
            f"  Original: \"{e['originalTitle']}\" by {e['author']}"
            + (f" ({e['authorUrl']})" if e['authorUrl'] else ''),
            f"  Source: {e['sourceUrl']}",
            f"  Licence: {lic['name']}" + (f" ({lic['url']})" if lic['url'] else ''),
            f"  Changes: {e['modifications']}",
            '',
        ]
    return '\n'.join(lines)


def validate(sounds: list[dict]) -> None:
    ids = [s['id'] for s in sounds]
    if len(ids) != len(set(ids)):
        raise SystemExit('duplicate sound ids')
    for s in sounds:
        if s['license'] not in LICENSES:
            raise SystemExit(f"{s['id']}: licence {s['license']} is not allowed")
        if s['category'] not in CATEGORIES:
            raise SystemExit(f"{s['id']}: unknown category {s['category']}")
        if s['license'].startswith('CC-BY'):
            # CC BY needs the credit in NOTICE and in the app: who, what,
            # where, under which licence, and what was changed.
            for key in ('author', 'originalTitle', 'pageUrl'):
                if not s.get(key):
                    raise SystemExit(f"{s['id']}: {s['license']} needs {key} for its credit")
        if 'freesound' in s and not isinstance(s['freesound'], int):
            raise SystemExit(f"{s['id']}: freesound must be the numeric sound id")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', action='append', help='process only this id (repeatable)')
    ap.add_argument('--pin', action='store_true', help='record sha256 for unpinned sources')
    ap.add_argument('--cache', type=Path, default=Path.home() / '.cache/meditejo-sounds')
    ap.add_argument('--recheck-licences', action='store_true',
                    help='ask Freesound (via meditejo-freesound-fetch info) about every '
                         'Freesound source, even when its original is already cached')
    ap.add_argument('--budget-mb', type=float, default=15.0)
    args = ap.parse_args()

    manifest = json.loads(SOURCES.read_text())
    target, ceiling = float(manifest['targetLufs']), float(manifest['truePeakCeiling'])
    sounds = manifest['sounds']
    ids = [s['id'] for s in sounds]
    validate(sounds)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    previous = {}
    if (OUT_DIR / 'sounds.json').exists():
        previous = {e['id']: e for e in json.loads((OUT_DIR / 'sounds.json').read_text())['sounds']}

    entries = []
    with tempfile.TemporaryDirectory(prefix='meditejo-sounds-') as tmp:
        for s in sounds:
            if args.only and s['id'] not in args.only:
                if s['id'] in previous:
                    entries.append(previous[s['id']])
                continue
            print(f"{s['id']}:")
            if args.recheck_licences and 'freesound' in s:
                check_freesound_licence(s, freesound_info(s))
            src = fetch(s, args.cache, args.pin)
            rec = process(s, src, Path(tmp), target, ceiling)
            name, url = LICENSES[s['license']]
            entries.append({
                'id': s['id'],
                'title': s['title'],
                'category': s['category'],
                'asset': f"assets/sounds/{s['id']}.opus",
                'durationMs': rec['durationMs'],
                'channels': int(s['channels']),
                'bytes': rec['bytes'],
                'originalTitle': s['originalTitle'],
                'author': s['author'],
                'authorUrl': s.get('authorUrl', ''),
                'sourceUrl': s['pageUrl'],
                'license': {'spdx': s['license'], 'name': name, 'url': url},
                'licenseVerifiedOn': s['licenseVerifiedOn'],
                'licenseCheckedAt': s['licenseCheckedAt'],
                'assurance': s.get('assurance', 'high'),
                'modifications': modifications(s, rec),
                'processing': {
                    'sourceSha256': s['sha256'],
                    'start': s['start'], 'loop': s['loop'], 'crossfade': s['crossfade'],
                    'filters': s.get('filters', ''),
                    **rec,
                },
            })
            print(f"  {rec['measuredBefore']['lufs']} -> {rec['measuredAfter']['lufs']} LUFS, "
                  f"TP {rec['measuredAfter']['truePeak']}, limit {rec['limiterDb']} dB, "
                  f"seam rank {rec['seamRank']}, seam {rec['seam']}, "
                  f"{rec['bytes'] / 1024:.0f} KiB")

    order = {sid: i for i, sid in enumerate(ids)}
    entries.sort(key=lambda e: order[e['id']])
    for stale in OUT_DIR.glob('*.opus'):
        if stale.stem not in order:
            stale.unlink()
    total = sum(e['bytes'] for e in entries)
    if total > args.budget_mb * 1024 * 1024:
        raise SystemExit(f'library is {total / 1048576:.2f} MiB, over the {args.budget_mb} MB budget')

    library = {
        'version': 1,
        'targetLufs': target,
        'generatedBy': 'tools/meditejo/sounds/process_sounds.py',
        'totalBytes': total,
        'sounds': entries,
    }
    (OUT_DIR / 'sounds.json').write_text(json.dumps(library, indent=2, ensure_ascii=False) + '\n')
    (OUT_DIR / 'NOTICE').write_text(notice(entries))
    if args.pin:
        SOURCES.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
    if not args.only:
        COMMANDS_LOG.write_text('\n'.join(
            c.replace(str(args.cache), '$CACHE').replace(tempfile.gettempdir(), '$TMP')
            for c in commands) + '\n')
    print(f'{len(entries)} sounds, {total / 1048576:.2f} MiB')


if __name__ == '__main__':
    main()
