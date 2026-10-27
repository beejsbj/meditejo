import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/bells/bell_recipe.dart';
import 'package:medito/services/bells/bell_recipes.dart';
import 'package:medito/services/bells/bell_synth.dart';
import 'package:medito/widgets/art/engine/bell.dart';

/// The shipped files behind each preset.
const _shipped = {
  'swell': 'session_bell_v2',
  'bowl_small': 'bell_bowl_small',
  'bowl_medium': 'bell_bowl_medium',
  'bowl_deep': 'bell_bowl_deep',
  'temple': 'bell_temple',
  'handbell': 'bell_handbell',
  'chime': 'bell_chime',
  'tingsha': 'bell_tingsha',
  'wood_block': 'bell_wood_block',
  'wooden_fish': 'bell_wooden_fish',
  'gong': 'bell_gong',
};

double _peak(Float64List x) => x.fold(0.0, (p, v) => math.max(p, v.abs()));

BellKnobs _knobs(
  double pitch,
  double bright,
  double ring,
  double strike,
  double shimmer,
) => BellKnobs(
  pitch: pitch,
  bright: bright,
  ring: ring,
  strike: strike,
  shimmer: shimmer,
);

void main() {
  test('every figure preset has a recipe, and the other way round', () {
    expect(bellRecipes.keys.toSet(), BellFigure.family.keys.toSet());
  });

  test("a recipe's controls sit inside the figure's ranges", () {
    for (final p in bellRecipes.keys) {
      final k = bellRecipes[p]!.knobs;
      expect(k.pitch, inInclusiveRange(80, 4000), reason: p);
      expect(k.bright, inInclusiveRange(0, 1), reason: p);
      expect(k.ring, inInclusiveRange(0.03, 8), reason: p);
      expect(k.strike, inInclusiveRange(0, 1), reason: p);
      expect(k.shimmer, inInclusiveRange(0, 8), reason: p);
    }
  });

  group('the same parameters make the same bytes', () {
    test('every shipped bell, rendered twice', () {
      for (final p in bellRecipes.keys) {
        final a = BellSynth.render(BellSpec.preset(p));
        final b = BellSynth.render(BellSpec.preset(p));
        expect(a, orderedEquals(b), reason: p);
      }
    });

    test('in an isolate, as the app renders it', () async {
      final spec = BellSpec('temple', _knobs(300, 0.4, 2, 0.3, 1.5));
      final here = BellSynth.render(spec);
      final there = await renderBellWavInBackground(spec);
      expect(there, orderedEquals(here));
    });

    test('a spec built twice is the same spec', () {
      final a = BellSpec('gong', _knobs(150, 0.5, 3, 0.2, 1));
      final b = BellSpec('gong', _knobs(150, 0.5, 3, 0.2, 1));
      expect(a, b);
      expect(a.key, b.key);
    });

    test('any control moved changes the sound', () {
      final base = _knobs(392, 0.3, 1.5, 0.5, 0.6);
      final bytes = BellSynth.render(BellSpec('bowl_medium', base));
      for (final moved in [
        base.copyWith(pitch: 440),
        base.copyWith(bright: 0.6),
        base.copyWith(ring: 2.5),
        base.copyWith(strike: 0.9),
        base.copyWith(shimmer: 3),
      ]) {
        expect(
          BellSynth.render(BellSpec('bowl_medium', moved)),
          isNot(orderedEquals(bytes)),
          reason: '$moved',
        );
      }
    });
  });

  group('a WAV the cue banks can decode', () {
    test('mono 16-bit PCM, a rate SoundPool takes, under 1 MiB', () {
      for (final p in bellRecipes.keys) {
        final wav = BellSynth.render(BellSpec.preset(p));
        final d = ByteData.sublistView(wav);
        expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF', reason: p);
        expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE', reason: p);
        expect(d.getUint16(20, Endian.little), 1, reason: '$p PCM');
        expect(d.getUint16(22, Endian.little), 1, reason: '$p mono');
        expect(d.getUint16(34, Endian.little), 16, reason: '$p 16-bit');
        final rate = d.getUint32(24, Endian.little);
        expect(rate, anyOf(22050, 44100), reason: p);
        expect(d.getUint32(40, Endian.little), wav.length - 44, reason: p);
        final seconds = (wav.length - 44) / 2 / rate;
        expect(seconds, inInclusiveRange(0.3, 12), reason: p);
        expect(wav.length, lessThan(1 << 20), reason: p);
      }
    });

    test('it opens at zero and ends at exactly zero, with no click', () {
      for (final p in bellRecipes.keys) {
        final (x, _) = BellSynth.samplesOf(
          BellSynth.render(BellSpec.preset(p)),
        );
        expect(x.first, 0, reason: p);
        expect(x.last, 0, reason: p);
        // The tail is faded: the last 5 ms hold nothing loud.
        expect(
          _peak(Float64List.sublistView(x, x.length - 100)),
          lessThan(0.02),
          reason: p,
        );
      }
    });
  });

  group('loudness is bounded', () {
    final corners = <String, BellKnobs>{
      'all low': _knobs(80, 0, 0.03, 0, 0),
      'all high': _knobs(4000, 1, 8, 1, 8),
      'low pitch, long ring, hard': _knobs(80, 0.9, 8, 1, 4),
      'high pitch, brief, soft': _knobs(4000, 0.1, 0.03, 0, 0),
      'bright and still': _knobs(500, 1, 3, 0.5, 0),
      'dark and wobbling': _knobs(250, 0, 1, 0.2, 8),
    };

    void bounded(String name, BellSpec spec) {
      final wav = BellSynth.render(spec);
      final (x, rate) = BellSynth.samplesOf(wav);
      final peak = _peak(x);
      expect(peak, greaterThan(0.05), reason: '$name is not silent');
      expect(
        peak,
        lessThanOrEqualTo(BellSynth.peakCeiling + 1 / 32768),
        reason: '$name peaks at ${20 * math.log(peak) / math.ln10} dBFS',
      );
      expect(
        BellSynth.maxMomentaryLufs(x, rate),
        lessThanOrEqualTo(BellSynth.targetMomentaryLufs + 0.1),
        reason: '$name is louder than the session bell',
      );
    }

    test('every shipped bell, as shipped', () {
      for (final p in bellRecipes.keys) {
        bounded(p, BellSpec.preset(p));
      }
    });

    for (final preset in ['swell', 'temple', 'tingsha', 'wood_block', 'gong']) {
      test('$preset at the corners of every control', () {
        for (final e in corners.entries) {
          bounded('$preset, ${e.key}', BellSpec(preset, e.value));
        }
      });
    }

    test('a tonal bell is as loud as the session bell', () {
      for (final p in ['bowl_medium', 'handbell', 'chime', 'tingsha']) {
        final (x, rate) = BellSynth.samplesOf(
          BellSynth.render(BellSpec.preset(p)),
        );
        expect(
          BellSynth.maxMomentaryLufs(x, rate),
          closeTo(BellSynth.targetMomentaryLufs, 0.2),
          reason: p,
        );
      }
    });

    test('out-of-range and non-finite controls are held to their range', () {
      final spec = BellSpec(
        'chime',
        _knobs(double.nan, 5, -3, double.infinity, 1e9),
      );
      expect(spec.knobs.pitch, inInclusiveRange(80, 4000));
      expect(spec.knobs.bright, 1);
      expect(spec.knobs.ring, 0.03);
      expect(spec.knobs.strike, inInclusiveRange(0, 1));
      expect(spec.knobs.shimmer, 8);
      bounded('wild', spec);
    });

    test('an unknown preset is refused', () {
      expect(
        () => BellSpec('kazoo', bellRecipes['gong']!.knobs),
        throwsArgumentError,
      );
    });
  });

  group('a bell started from a shipped one is that bell', () {
    // Not byte-equal (the phases and the mallet's noise come from Python's
    // generator), but the same ring: its length, peak and loudness.
    test('re-rendered as shipped, near the shipped file', () {
      for (final e in _shipped.entries) {
        final (mine, myRate) = BellSynth.samplesOf(
          BellSynth.render(BellSpec.preset(e.key)),
        );
        final (ref, refRate) = BellSynth.samplesOf(
          File('assets/audio/${e.value}.wav').readAsBytesSync(),
        );
        expect(
          BellSynth.maxMomentaryLufs(mine, myRate),
          closeTo(BellSynth.maxMomentaryLufs(ref, refRate), 0.6),
          reason: e.key,
        );
        expect(
          mine.length / myRate,
          closeTo(
            ref.length / refRate,
            math.max(2.5, 0.5 * ref.length / refRate),
          ),
          reason: e.key,
        );
      }
    });
  });

  group('the controls move the sound as named', () {
    double zeroCrossingsPerSecond(Float64List x, int rate, double seconds) {
      var n = 0;
      final end = math.min(x.length, (rate * seconds).round());
      for (var i = 1; i < end; i++) {
        if ((x[i - 1] < 0) != (x[i] < 0)) n++;
      }
      return n / seconds;
    }

    test('pitch: a higher pitch crosses zero more often', () {
      double rate(double pitch) {
        final (x, r) = BellSynth.samplesOf(
          BellSynth.render(
            BellSpec('bowl_medium', _knobs(pitch, 0.1, 1, 0.5, 0)),
          ),
        );
        return zeroCrossingsPerSecond(x, r, 0.4);
      }

      expect(rate(600), greaterThan(rate(300)));
    });

    test('ring: a longer ring is a longer sound', () {
      int length(double ring) => BellSynth.render(
        BellSpec('bowl_medium', _knobs(392, 0.2, ring, 0.5, 0.5)),
      ).length;
      expect(length(3), greaterThan(length(0.5)));
    });

    test('strike: a harder strike opens brighter', () {
      // The first 30 ms of a soft mallet is mostly low; a hard one is full
      // of high frequencies, so it crosses zero more often.
      double open(double strike) {
        final (x, r) = BellSynth.samplesOf(
          BellSynth.render(
            BellSpec('bowl_medium', _knobs(392, 0.01, 1, strike, 0.5)),
          ),
        );
        return zeroCrossingsPerSecond(x, r, 0.03);
      }

      expect(open(1), greaterThan(open(0)));
    });

    test('brightness: more of the energy is up in the upper modes', () {
      final dark = BellSynth.modes(
        BellSpec('temple', _knobs(196, 0.05, 3.2, 0.2, 1.3)),
      );
      final bright = BellSynth.modes(
        BellSpec('temple', _knobs(196, 0.8, 3.2, 0.2, 1.3)),
      );
      // Measured against the bell's own loudest mode (196 Hz), which the
      // brighter bell's upper modes may out-shout.
      double share(List<BellMode> modes) {
        double e(BellMode m) => m.a * m.a * m.tau;
        final total = modes.fold(0.0, (s, m) => s + e(m));
        final upper = modes
            .where((m) => m.f > 196 * 1.05)
            .fold(0.0, (s, m) => s + e(m));
        return upper / total;
      }

      expect(share(bright), closeTo(0.8, 0.001));
      expect(share(dark), closeTo(0.05, 0.001));
    });

    test('shimmer: every mode beats in proportion', () {
      final still = BellSynth.modes(
        BellSpec('bowl_medium', _knobs(392, 0.2, 1.45, 0.5, 0)),
      );
      final fast = BellSynth.modes(
        BellSpec('bowl_medium', _knobs(392, 0.2, 1.45, 0.5, 4)),
      );
      expect(still.every((m) => m.beat == 0), isTrue);
      expect(fast.first.beat, closeTo(4, 1e-9));
      expect(fast.last.beat, greaterThan(fast.first.beat));
    });

    test('unmoved controls leave the shipped modes as they are', () {
      for (final p in bellRecipes.keys) {
        final recipe = bellRecipes[p]!;
        final moved = BellSynth.modes(BellSpec.preset(p));
        for (var i = 0; i < moved.length; i++) {
          expect(moved[i].f, closeTo(recipe.modes[i].f, 1e-9), reason: p);
          expect(moved[i].a, closeTo(recipe.modes[i].a, 1e-6), reason: p);
          expect(moved[i].tau, closeTo(recipe.modes[i].tau, 1e-9), reason: p);
        }
      }
    });
  });
}
