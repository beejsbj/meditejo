#!/usr/bin/env python3
"""Reproducible original pulse cues, and the record of the sampled ones.

"Soft click" is mathematical synthesis: no recordings or third-party samples.
Heartbeat, Chirp and Footstep were synthesised here too until meditejo#76;
their shipped files are now generated samples, recorded in
tools/meditejo/cue_samples.json (model, prompt, take, SHA-256). They are
marked SAMPLED below and this script never writes them; their old formulas
stay in value() as the record of what they replaced.

    python3 tools/meditejo/generate_pulse_sounds.py          # write the synthesised pulse
    python3 tools/meditejo/generate_pulse_sounds.py --check  # compare with assets/audio

Outputs are dedicated to the public domain under CC0-1.0; see assets/audio/NOTICE.
The generator is part of Meditejo and distributed under the repository's AGPL.
"""
import hashlib
import io
import json
import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / 'assets' / 'audio'
SAMPLES = Path(__file__).resolve().parent / 'cue_samples.json'
DURATIONS = {'click': 0.045, 'heartbeat': 0.22, 'chirp': 0.10, 'footstep': 0.10}
# Shipped as samples (cue_samples.json), not as this synthesis.
SAMPLED = {'heartbeat', 'chirp', 'footstep'}


def tone(t, hz, decay, attack=0.002):
    return math.sin(2 * math.pi * hz * t) * math.exp(-t / decay) * min(1, t / attack)


def value(name, t, seconds, rng):
    if name == 'click':
        return tone(t, 1100, 0.008) * 0.32
    if name == 'heartbeat':
        value = tone(t, 82, 0.025) * 0.48
        if t >= 0.105:
            value += tone(t - 0.105, 65, 0.025) * 0.32
        return value
    if name == 'chirp':
        return (math.sin(2 * math.pi * (800 * t + 1800 * t * t))
                * math.sin(math.pi * t / seconds) ** 2 * 0.24)
    return (rng.uniform(-1, 1) * math.exp(-t / 0.018) * min(1, t / 0.003) * 0.23
            + tone(t, 140, 0.022) * 0.18)


def generate():
    """{filename: WAV bytes} of every pulse that is synthesised."""
    rng = random.Random(6)
    files = {}
    for name, seconds in DURATIONS.items():
        if name in SAMPLED:
            continue
        frames = []
        for n in range(round(RATE * seconds)):
            t = n / RATE
            # Fade out to an exact zero endpoint to avoid truncation clicks.
            v = value(name, t, seconds, rng) * min(1, (seconds - t) / 0.005)
            frames.append(struct.pack('<h', round(max(-1, min(1, v)) * 32767)))
        buf = io.BytesIO()
        with wave.open(buf, 'wb') as wav:
            wav.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
            wav.writeframes(b''.join(frames))
        files[f'pulse_{name}.wav'] = buf.getvalue()
    return files


def check():
    files = generate()
    recorded = {f['file']: f['sha256']
                for f in json.loads(SAMPLES.read_text())['samples']}
    bad = [f'differs or missing: {name}' for name, data in files.items()
           if not (OUT / name).exists() or (OUT / name).read_bytes() != data]
    for name in sorted(f'pulse_{n}.wav' for n in SAMPLED):
        if name not in recorded:
            bad.append(f'sampled, but not in {SAMPLES.name}: {name}')
        elif (not (OUT / name).exists() or
              hashlib.sha256((OUT / name).read_bytes()).hexdigest() != recorded[name]):
            bad.append(f'sample differs from {SAMPLES.name}: {name}')
    known = set(files) | {f'pulse_{n}.wav' for n in SAMPLED}
    bad += [f'neither generated nor sampled: {p.name}'
            for p in sorted(OUT.glob('pulse_*.wav')) if p.name not in known]
    for line in bad:
        print(line, file=sys.stderr)
    if bad:
        return 1
    print(f'{len(files)} pulse regenerates byte-identically; '
          f'{len(SAMPLED)} sampled files match their recorded hashes')
    return 0


def main():
    if '--check' in sys.argv[1:]:
        return check()
    for name, data in generate().items():
        (OUT / name).write_bytes(data)
        print(OUT / name, len(data))
    return 0


if __name__ == '__main__':
    sys.exit(main())
