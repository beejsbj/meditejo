#!/usr/bin/env python3
"""Read the shipped bells' synthesis parameters, for the bell figures.

The ten synthesised bells come from tools/meditejo/generate_bells.py (on
develop since eda420ae). This imports that file, swaps its render() and
strike() for recorders, and calls each sound's build, so the modes and the
strike come straight from the generator, not from a copy of its tables. The
eleventh bell, Medito's "Swell bell" (assets/audio/session_bell_v2.wav), is a
recording, so its modes are measured from the WAV instead.

Each bell is reduced to the five controls the custom-bell editor (BJS-587)
would expose. They are what the figures draw from:

    pitch      Hz of the loudest mode                  -> size and proportions
    bright     share of ring energy (a^2 tau) above it -> rim and ink, highlight
    ring       seconds, that mode's decay constant     -> how long motion lasts
    strike     0 soft mallet .. 1 hard (log of the     -> strength of the knock
               strike's low-pass, 300 Hz .. 10 kHz)       or sway
    shimmer    Hz, that mode's beat                    -> rim oscillation rate

The modes go along too (frequency, amplitude, tau, beat, rise), so the page can
resynthesise a close sketch of each bell and of any knob change.

    uv run --with numpy python3 bell_params.py GENERATOR.py SESSION_BELL.wav > bells.json
"""
import importlib.util
import json
import math
import sys

HARD_LO, HARD_HI = 300.0, 10000.0


def hardness(lowpass):
    return max(0.0, min(1.0, math.log(lowpass / HARD_LO) / math.log(HARD_HI / HARD_LO)))


def knobs(modes):
    main = max(modes, key=lambda m: m['a'])
    energy = lambda m: m['a'] ** 2 * m['tau']
    total = sum(energy(m) for m in modes)
    upper = sum(energy(m) for m in modes if m['f'] > main['f'] * 1.05)
    return main, {'pitch': main['f'], 'bright': upper / total, 'ring': main['tau'], 'shimmer': main['beat']}


def from_generator(path):
    spec = importlib.util.spec_from_file_location('generate_bells', path)
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    seen = {}

    def render(rate, seconds, modes):
        if modes:
            seen['modes'] = seen.get('modes', []) + [
                {'f': m.f, 'a': m.a, 'tau': m.tau, 'beat': m.beat, 'rise': m.rise} for m in modes]
            return [0.0]
        return [0.0] * round(rate * seconds)  # the gong's noise wash fills this in place

    def strike(rate, seconds, rng, lowpass_hz, tau, level, attack=0.0005):
        seen['strike'] = {'lowpass': lowpass_hz, 'tau': tau, 'level': level, 'attack': attack}
        return [0.0]

    gen.render, gen.strike = render, strike
    out = {}
    for sound in gen.SOUNDS:
        seen.clear()
        sound.build(sound.rate, sound.seconds)
        modes = sorted(seen['modes'], key=lambda m: m['f'])
        _, k = knobs(modes)
        k['strike'] = hardness(seen['strike']['lowpass'])
        out[sound.slug] = {'knobs': k, 'modes': modes, 'hit': seen['strike'],
                           'seconds': sound.seconds, 'source': 'generate_bells.py'}
    return out


def from_recording(path):
    """Partials of a recorded bell: spectral peaks of the first second, each
    one's decay fitted on its magnitude over time, its beat from the wobble of
    that magnitude."""
    import wave
    import numpy as np
    with wave.open(path, 'rb') as w:
        rate = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float) / 32768
    hop, size = 512, 8192
    win = np.hanning(size)
    frames = np.array([np.abs(np.fft.rfft(x[i:i + size] * win))
                       for i in range(0, len(x) - size, hop)])
    freqs = np.fft.rfftfreq(size, 1 / rate)
    t = np.arange(len(frames)) * hop / rate + size / 2 / rate
    early = frames[(t > 0.15) & (t < 1.2)].mean(axis=0)
    bins = [i for i in range(2, len(early) - 2) if 60 < freqs[i] < 9000
            and early[i] == early[i - 2:i + 3].max() and early[i] > early.max() * 0.06]
    bins = sorted(bins, key=lambda i: -early[i])[:8]
    peak_frame = int(np.argmax(frames[:, bins[0]]))
    modes = []
    for i in sorted(bins):
        mag = frames[:, i - 1:i + 2].max(axis=1)
        top = int(np.argmax(mag))
        tail = (np.arange(len(mag)) >= top) & (mag > mag[top] * 10 ** (-36 / 20))
        slope = np.polyfit(t[tail], np.log(mag[tail]), 1)[0]
        tau = -1 / slope if slope < 0 else 8.0
        wob = mag[tail] / np.exp(np.polyval(np.polyfit(t[tail], np.log(mag[tail]), 1), t[tail])) - 1
        spec = np.abs(np.fft.rfft(wob * np.hanning(len(wob)), 8 * len(wob)))
        mf = np.fft.rfftfreq(8 * len(wob), hop / rate)
        band = (mf > 0.2) & (mf < 8)
        beat = float(mf[band][np.argmax(spec[band])]) if spec[band].max() > spec[1:].mean() * 4 else 0.0
        modes.append({'f': float(freqs[i]), 'a': float(early[i] / early[bins[0]]), 'tau': float(tau),
                      'beat': round(beat, 2), 'rise': float(max(0.002, t[top] - t[0]) / 3)})
    _, k = knobs(modes)
    attack = float(t[peak_frame])
    # A recording has no mallet setting. Its attack stands in: the swell's
    # tone builds for a long time before it peaks, which is a soft strike.
    k['strike'] = round(max(0.0, min(1.0, 0.6 - attack)), 3)
    return {'knobs': k, 'modes': modes, 'hit': {'lowpass': HARD_LO * (HARD_HI / HARD_LO) ** k['strike'],
                                                'tau': 0.02, 'level': 0.05, 'attack': attack},
            'seconds': len(x) / rate, 'source': 'measured from session_bell_v2.wav'}


def rounded(v):
    if isinstance(v, float):
        return float(f'{v:.4g}')
    if isinstance(v, dict):
        return {k: rounded(x) for k, x in v.items()}
    if isinstance(v, list):
        return [rounded(x) for x in v]
    return v


if __name__ == '__main__':
    bells = {'swell': from_recording(sys.argv[2]), **from_generator(sys.argv[1])}
    json.dump(rounded(bells), sys.stdout, indent=1)
    print()
