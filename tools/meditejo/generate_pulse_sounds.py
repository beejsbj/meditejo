#!/usr/bin/env python3
"""Reproducible original pulse cues. No recordings or third-party samples.

Outputs are dedicated to the public domain under CC0-1.0; see assets/audio/NOTICE.
The generator is part of Meditejo and distributed under the repository's AGPL.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / 'assets' / 'audio'


def tone(t, hz, decay, attack=0.002):
    return math.sin(2 * math.pi * hz * t) * math.exp(-t / decay) * min(1, t / attack)


def generate():
    rng = random.Random(6)
    durations = {'click': 0.045, 'heartbeat': 0.22, 'chirp': 0.10, 'footstep': 0.10}
    for name, seconds in durations.items():
        frames = []
        for n in range(round(RATE * seconds)):
            t = n / RATE
            if name == 'click':
                value = tone(t, 1100, 0.008) * 0.32
            elif name == 'heartbeat':
                value = tone(t, 82, 0.025) * 0.48
                if t >= 0.105:
                    value += tone(t - 0.105, 65, 0.025) * 0.32
            elif name == 'chirp':
                value = math.sin(2 * math.pi * (800 * t + 1800 * t * t)) * math.sin(math.pi * t / seconds) ** 2 * 0.24
            else:
                value = rng.uniform(-1, 1) * math.exp(-t / 0.018) * min(1, t / 0.003) * 0.23
                value += tone(t, 140, 0.022) * 0.18
            # Fade out to an exact zero endpoint to avoid truncation clicks.
            value *= min(1, (seconds - t) / 0.005)
            frames.append(struct.pack('<h', round(max(-1, min(1, value)) * 32767)))
        with wave.open(str(OUT / f'pulse_{name}.wav'), 'wb') as wav:
            wav.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
            wav.writeframes(b''.join(frames))


if __name__ == '__main__':
    generate()
