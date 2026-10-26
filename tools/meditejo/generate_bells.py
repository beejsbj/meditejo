#!/usr/bin/env python3
"""Reproducible original bowls, bells, chimes, woods and a gong for the cues.

Every sound is modal synthesis, with no recordings and no third-party
samples. A struck bowl, bell, bar or board is a handful of resonant modes,
each a decaying sine at its own (usually inharmonic) frequency, and that is all
this does: partial ratios, per-mode decay, a little beating between the two
nearly degenerate halves of a mode, and a short strike transient. Parameters,
the noise seed and the output rate are fixed, so the files regenerate
byte-for-byte.

Outputs are dedicated to the public domain under CC0-1.0; see
assets/audio/NOTICE. The generator is part of Meditejo and distributed under
the repository's AGPL.

    python3 tools/meditejo/generate_bells.py            # write assets/audio/bell_*.wav
    python3 tools/meditejo/generate_bells.py --check    # regenerate in memory, compare
    python3 tools/meditejo/generate_bells.py --measure FILE.wav

Loudness: each file is scaled so its loudest momentary (400 ms, K-weighted,
ITU-R BS.1770) block equals the one of Medito's session bell
(assets/audio/session_bell_v2.wav), then held under a -1 dBFS peak ceiling.
Impulsive woods hit that ceiling first, so they sit a little below the bell
in momentary loudness and not above it in peak level.
"""
import argparse
import math
import random
import struct
import sys
import wave
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / 'assets' / 'audio'

# Momentary-loudness target (LUFS, K-weighted 400 ms) measured on
# assets/audio/session_bell_v2.wav with measure(); see bells_report.py.
TARGET_MOMENTARY_LUFS = -9.84
PEAK_CEILING = 10 ** (-1 / 20)  # -1 dBFS
TWO_PI = 2 * math.pi


class Mode:
    """One resonance: a sine at [f] Hz that decays with time constant [tau].

    [rise] > 0 lets the mode swell in (a gong's upper modes bloom after the
    strike). [beat] > 0 splits it into two sines [beat] Hz apart, as the two
    halves of a slightly asymmetric bowl or bell do, which wobbles the
    amplitude at that rate; [split] is the second half's share of the energy.
    [glide] is (fractional drop, tau) of a pitch that settles after a strike.
    """

    def __init__(self, f, a, tau, rise=0.0, beat=0.0, split=0.45,
                 phase=0.0, glide=None):
        self.f, self.a, self.tau, self.rise = f, a, tau, rise
        self.beat, self.split, self.phase, self.glide = beat, split, phase, glide


def render(rate, seconds, modes):
    n = round(rate * seconds)
    out = [0.0] * n
    nyquist_guard = rate * 0.46
    for m in modes:
        if m.f >= nyquist_guard:
            continue
        halves = ([(m.f, m.a)] if m.beat == 0 else
                  [(m.f - m.beat / 2, m.a * (1 - m.split)),
                   (m.f + m.beat / 2, m.a * m.split)])
        decay = 1 / (rate * m.tau)
        grow = 1 / (rate * m.rise) if m.rise else 0.0
        # Past ~ -100 dB nothing is audible: stop instead of adding zeros.
        last = min(n, int(13.8 * m.tau * rate) + 1)
        for f, amp in halves:
            w = TWO_PI * f / rate
            for i in range(last):
                env = amp * math.exp(-i * decay)
                if grow:
                    env *= 1 - math.exp(-i * grow)
                if m.glide:
                    drop, gt = m.glide
                    t = i / rate
                    arg = w * i + TWO_PI * f * drop * gt * (1 - math.exp(-t / gt))
                else:
                    arg = w * i
                out[i] += env * math.sin(arg + m.phase)
    return out


def strike(rate, seconds, rng, lowpass_hz, tau, level, attack=0.0005):
    """A short noise burst: the mallet, clapper or stick meeting the metal."""
    n = round(rate * seconds)
    k = 1 - math.exp(-TWO_PI * lowpass_hz / rate)
    out, y, z = [0.0] * n, 0.0, 0.0
    for i in range(n):
        y += k * (rng.uniform(-1, 1) - y)
        z += k * (y - z)  # two poles: less hiss above the cutoff
        t = i / rate
        out[i] = z * 1.6 * math.exp(-t / tau) * min(1.0, t / attack) * level
    return out


def mix(*layers):
    n = max(len(layer) for layer in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def pad(layer, n):
    return layer + [0.0] * (n - len(layer))


# --- The sounds -----------------------------------------------------------

def bowl(rate, seconds, f0, tau, beat, seed):
    """A singing bowl struck with a soft mallet.

    Partials follow a metal bowl's 1 : 2.71 : 5.12 : 8.24 : 11.7. Upper modes
    die faster and beat faster; the fundamental wobbles slowly, the "wah" of a
    bowl that is not quite round.
    """
    rng = random.Random(seed)
    ratios = [1.0, 2.71, 5.12, 8.24, 11.7]
    amps = [1.0, 0.62, 0.30, 0.13, 0.05]
    shares = [1.0, 0.55, 0.32, 0.20, 0.12]
    modes = [Mode(f0 * r, a, tau * s,
                  rise=0.004 + 0.01 * i,
                  beat=beat * r * rng.uniform(0.9, 1.15),
                  split=0.28, phase=rng.uniform(0, TWO_PI))
             for i, (r, a, s) in enumerate(zip(ratios, amps, shares))]
    thud = strike(rate, 0.05, rng, 1800, 0.006, 0.20)
    return mix(render(rate, seconds, modes), thud)


def temple_bell(rate, seconds):
    """A large temple bell: a bell's hum, prime, tierce, quint and nominal
    (1 : 1.19 : 1.5 : 2 above the prime) with a slow beat in the lowest modes
    and a dull wooden thud for the strike."""
    rng = random.Random(1)  # of 59 tried, the phases with the lowest opening peak
    prime = 196.0
    table = [  # ratio to prime, amplitude, tau (s), beat (Hz)
        (0.5, 0.30, 4.4, 0.9), (1.0, 1.00, 3.2, 1.3), (1.19, 0.68, 2.6, 1.7),
        (1.5, 0.52, 2.1, 2.1), (2.0, 0.92, 1.9, 2.6), (2.5, 0.34, 1.2, 3.0),
        (2.66, 0.28, 1.0, 3.4), (3.0, 0.18, 0.8, 3.9), (4.17, 0.11, 0.5, 5.0),
        (5.43, 0.06, 0.35, 6.1),
    ]
    modes = [Mode(prime * r, a, tau, rise=0.002, beat=beat, split=0.30,
                  phase=rng.uniform(0, TWO_PI)) for r, a, tau, beat in table]
    thud = strike(rate, 0.08, rng, 700, 0.012, 0.10, attack=0.002)
    return mix(render(rate, seconds, modes), thud)


def small_bell(rate, seconds):
    """A small hand bell: bright, a clear "ting"."""
    rng = random.Random(31)
    f0 = 1318.5
    table = [(1.0, 1.00, 1.2, 1.1), (2.0, 0.55, 0.8, 1.6), (2.43, 0.28, 0.56, 2.0),
             (3.0, 0.22, 0.44, 2.4), (4.07, 0.12, 0.28, 3.1), (5.4, 0.06, 0.18, 4.0)]
    modes = [Mode(f0 * r, a, tau, rise=0.0008, beat=b, split=0.30,
                  phase=rng.uniform(0, TWO_PI)) for r, a, tau, b in table]
    tick = strike(rate, 0.02, rng, 6000, 0.002, 0.10, attack=0.0003)
    return mix(render(rate, seconds, modes), tick)


def chime(rate, seconds):
    """A struck metal bar, the free-free bar ratios 1 : 2.757 : 5.404 : 8.933,
    glassy and quiet at the top."""
    rng = random.Random(41)
    f0 = 1568.0
    table = [(1.0, 1.00, 1.7, 0.7), (2.757, 0.34, 0.8, 1.5),
             (5.404, 0.12, 0.4, 2.6), (8.933, 0.04, 0.2, 4.0)]
    modes = [Mode(f0 * r, a, tau, rise=0.001, beat=b, split=0.30,
                  phase=rng.uniform(0, TWO_PI)) for r, a, tau, b in table]
    tick = strike(rate, 0.015, rng, 9000, 0.0015, 0.05, attack=0.0003)
    return mix(render(rate, seconds, modes), tick)


def tingsha(rate, seconds):
    """Two small cymbals touched together. Two near-identical rings beat
    against each other, a few times a second."""
    rng = random.Random(51)
    table = [(3120.0, 1.00, 1.6, 5.5), (3880.0, 0.35, 0.9, 7.0),
             (7260.0, 0.34, 0.8, 9.0), (9190.0, 0.12, 0.4, 11.0)]
    modes = [Mode(f, a, tau, rise=0.0006, beat=b, split=0.42,
                  phase=rng.uniform(0, TWO_PI)) for f, a, tau, b in table]
    clink = strike(rate, 0.02, rng, 9000, 0.002, 0.12, attack=0.0002)
    return mix(render(rate, seconds, modes), clink)


def wood_block(rate, seconds):
    """A wood block: a bright, dry knock."""
    rng = random.Random(61)
    table = [(1180.0, 1.00, 0.032), (2160.0, 0.55, 0.020),
             (3420.0, 0.28, 0.011), (5200.0, 0.10, 0.006)]
    modes = [Mode(f, a, tau, phase=rng.uniform(0, TWO_PI)) for f, a, tau in table]
    click = strike(rate, 0.01, rng, 3500, 0.0015, 0.18, attack=0.0002)
    return mix(render(rate, seconds, modes), click)


def wooden_fish(rate, seconds):
    """A wooden fish (mokugyo): a hollow, rounded "poku" whose pitch settles
    a few percent in the first few milliseconds."""
    rng = random.Random(71)
    table = [(520.0, 1.00, 0.12), (1390.0, 0.34, 0.07), (2450.0, 0.14, 0.035)]
    modes = [Mode(f, a, tau, glide=(0.06, 0.012), phase=rng.uniform(0, TWO_PI))
             for f, a, tau in table]
    knock = strike(rate, 0.015, rng, 1500, 0.002, 0.14, attack=0.0004)
    return mix(render(rate, seconds, modes), knock)


def gong(rate, seconds):
    """A tam-tam. Dozens of inharmonic modes: the low ones sound at once, the
    upper ones swell in over a few tenths of a second (the gong's bloom) and
    then fade faster, plus a soft wash of noise."""
    rng = random.Random(81)
    base = 118.0
    modes = [Mode(base * 1.0, 1.0, 4.2, rise=0.03, beat=0.8, split=0.3, phase=0.3),
             Mode(base * 1.5, 0.70, 3.9, rise=0.05, beat=1.1, split=0.3, phase=1.1),
             Mode(base * 2.04, 0.60, 3.5, rise=0.07, beat=1.4, split=0.3, phase=2.0)]
    ratio = 2.3
    while ratio < 38:
        ratio *= rng.uniform(1.07, 1.16)
        modes.append(Mode(
            base * ratio,
            rng.uniform(0.45, 1.0) * ratio ** -0.62 * 1.3,
            3.7 * ratio ** -0.42,
            rise=0.04 + 0.05 * ratio ** 0.8 * rng.uniform(0.6, 1.2) / 3,
            beat=rng.uniform(0.6, 3.0), split=rng.uniform(0.15, 0.35),
            phase=rng.uniform(0, TWO_PI)))
    wash = render(rate, seconds, [])
    k = 1 - math.exp(-TWO_PI * 1400 / rate)
    y = z = 0.0
    for i in range(len(wash)):
        y += k * (rng.uniform(-1, 1) - y)
        z += k * (y - z)
        t = i / rate
        wash[i] = z * 0.26 * (1 - math.exp(-t / 0.25)) * math.exp(-t / 1.6)
    thud = strike(rate, 0.12, rng, 450, 0.025, 0.30, attack=0.003)
    return mix(render(rate, seconds, modes), wash, thud)


class Sound:
    def __init__(self, slug, rate, seconds, fade, build, trim_db=0.0):
        self.slug, self.rate, self.seconds, self.fade = slug, rate, seconds, fade
        self.build, self.trim_db = build, trim_db

    @property
    def filename(self):
        return f'bell_{self.slug}.wav'


# Lengths are the audible ring plus a cosine fade to an exact zero; the fade
# only ever starts where the ring is already ~40 dB down. Tonal sounds whose
# partials stay under ~9 kHz use 22.05 kHz to keep the set small; the two
# bright metals (chime, tingsha) keep 44.1 kHz.
SOUNDS = [
    Sound('bowl_small', 22050, 4.5, 1.2,
          lambda r, s: bowl(r, s, 640.0, 1.05, 0.9, 11)),
    Sound('bowl_medium', 22050, 6.0, 1.5,
          lambda r, s: bowl(r, s, 392.0, 1.45, 0.6, 12)),
    Sound('bowl_deep', 22050, 8.0, 2.0,
          lambda r, s: bowl(r, s, 196.0, 2.0, 0.35, 13)),
    Sound('temple', 22050, 9.0, 2.2, lambda r, s: temple_bell(r, s)),
    Sound('handbell', 22050, 3.5, 1.0, lambda r, s: small_bell(r, s)),
    Sound('chime', 44100, 5.0, 1.4, lambda r, s: chime(r, s)),
    Sound('tingsha', 44100, 5.0, 1.4, lambda r, s: tingsha(r, s)),
    Sound('wood_block', 44100, 0.30, 0.10, lambda r, s: wood_block(r, s)),
    Sound('wooden_fish', 22050, 0.90, 0.25, lambda r, s: wooden_fish(r, s)),
    Sound('gong', 22050, 12.0, 3.0, lambda r, s: gong(r, s)),
]


# --- Loudness (ITU-R BS.1770 K-weighting, momentary blocks) -----------------

def _biquad(x, b, a):
    b0, b1, b2 = b
    a1, a2 = a
    x1 = x2 = y1 = y2 = 0.0
    out = [0.0] * len(x)
    for i, v in enumerate(x):
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out[i] = y
        x2, x1, y2, y1 = x1, v, y1, y
    return out


def k_weight(x, rate):
    # Stage 1: the head-related high shelf. Stage 2: the RLB high-pass.
    f0, gain, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    k = math.tan(math.pi * f0 / rate)
    vh = 10 ** (gain / 20)
    vb = vh ** 0.4996667741545416
    d = 1 + k / q + k * k
    shelf_b = ((vh + vb * k / q + k * k) / d, 2 * (k * k - vh) / d,
               (vh - vb * k / q + k * k) / d)
    shelf_a = (2 * (k * k - 1) / d, (1 - k / q + k * k) / d)
    f0, q = 38.13547087602444, 0.5003270373238773
    k = math.tan(math.pi * f0 / rate)
    d = 1 + k / q + k * k
    hp_a = (2 * (k * k - 1) / d, (1 - k / q + k * k) / d)
    return _biquad(_biquad(x, shelf_b, shelf_a), (1.0, -2.0, 1.0), hp_a)


def momentary_lufs(x, rate):
    """Loudness of each 400 ms block, hop 100 ms, in LUFS. [x] is zero-padded
    to at least one block."""
    w = k_weight(x, rate)
    block, hop = round(0.4 * rate), round(0.1 * rate)
    w = w + [0.0] * max(0, block - len(w))
    out = []
    for start in range(0, len(w) - block + 1, hop):
        ms = sum(v * v for v in w[start:start + block]) / block
        out.append(-0.691 + 10 * math.log10(ms) if ms > 0 else -math.inf)
    return out


def integrated_lufs(x, rate):
    """Gated integrated loudness (absolute -70 LUFS, relative -10 LU), for
    comparison with ffmpeg's ebur128."""
    blocks = momentary_lufs(x, rate)
    keep = [v for v in blocks if v > -70]
    mean = lambda vs: -0.691 + 10 * math.log10(
        sum(10 ** ((v + 0.691) / 10) for v in vs) / len(vs))
    keep = [v for v in keep if v > mean(keep) - 10]
    return mean(keep)


def measure(path):
    """(samples scaled to -1..1, rate) of a mono 16-bit WAV."""
    with wave.open(str(path), 'rb') as wav:
        assert wav.getnchannels() == 1 and wav.getsampwidth() == 2
        rate = wav.getframerate()
        raw = wav.readframes(wav.getnframes())
    return [v / 32768 for v in struct.unpack(f'<{len(raw) // 2}h', raw)], rate


# --- Assembly ---------------------------------------------------------------

def finish(sound):
    x = sound.build(sound.rate, sound.seconds)
    n = round(sound.rate * sound.seconds)
    x = pad(x, n)[:n]
    # A raised-cosine fade to an exact zero ends the file without a click, and
    # a 1 ms ramp opens it the same way.
    fade = round(sound.rate * sound.fade)
    for i in range(fade):
        x[n - fade + i] *= 0.5 * (1 + math.cos(math.pi * i / (fade - 1)))
    x[-1] = 0.0
    ramp = max(2, round(sound.rate * 0.001))
    for i in range(ramp):
        x[i] *= 0.5 * (1 - math.cos(math.pi * i / ramp))
    peak = max(abs(v) for v in x)
    loud = max(momentary_lufs(x, sound.rate))
    gain = 10 ** ((TARGET_MOMENTARY_LUFS - loud + sound.trim_db) / 20)
    gain = min(gain, PEAK_CEILING / peak)
    return sound.rate, b''.join(struct.pack('<h', round(v * gain * 32767)) for v in x)


def wav_bytes(rate, frames):
    import io
    buf = io.BytesIO()
    with wave.open(buf, 'wb') as wav:
        wav.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
        wav.writeframes(frames)
    return buf.getvalue()


def generate():
    return {s.filename: wav_bytes(*finish(s)) for s in SOUNDS}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--check', action='store_true',
                        help='regenerate in memory and compare with assets/audio')
    parser.add_argument('--measure', metavar='WAV',
                        help='print the momentary and integrated LUFS of a WAV')
    args = parser.parse_args()
    if args.measure:
        x, rate = measure(args.measure)
        print(f'momentary max {max(momentary_lufs(x, rate)):.2f} LUFS, '
              f'integrated {integrated_lufs(x, rate):.2f} LUFS')
        return 0
    files = generate()
    if args.check:
        bad = [name for name, data in files.items()
               if not (OUT / name).exists() or (OUT / name).read_bytes() != data]
        stray = sorted(p.name for p in OUT.glob('bell_*.wav') if p.name not in files)
        for name in bad:
            print(f'differs or missing: {name}', file=sys.stderr)
        for name in stray:
            print(f'not generated by this script: {name}', file=sys.stderr)
        if bad or stray:
            return 1
        print(f'{len(files)} files regenerate byte-identically')
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        (OUT / name).write_bytes(data)
        print(OUT / name, len(data))
    return 0


if __name__ == '__main__':
    sys.exit(main())
