import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart'
    show layerGain;
import 'package:medito/services/soundscape/synth/noise_generator.dart';

/// K-weighted mean square of [x] measured the long way: filter it through
/// the BS.1770 K-weighting biquads in the time domain (twice round, keeping
/// the second lap so the filters are in their periodic steady state) and
/// average.
double weightedPower(Float64List x) {
  final n = x.length;
  final y = Float64List(2 * n);
  void biquad(
    Float64List input,
    Float64List out,
    List<double> b,
    List<double> a,
  ) {
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
    for (var i = 0; i < input.length; i++) {
      final v = input[i];
      final o = b[0] * v + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2;
      x2 = x1;
      x1 = v;
      y2 = y1;
      y1 = o;
      out[i] = o;
    }
  }

  final twice = Float64List(2 * n)
    ..setRange(0, n, x)
    ..setRange(n, 2 * n, x);
  final stage1 = Float64List(2 * n);
  biquad(
    twice,
    stage1,
    [1.53512485958697, -2.69169618940638, 1.19839281085285],
    [-1.69065929318241, 0.73248077421585],
  );
  biquad(stage1, y, [1, -2, 1], [-1.99004745483398, 0.99007225036621]);
  var sum = 0.0;
  for (var i = n; i < 2 * n; i++) {
    sum += y[i] * y[i];
  }
  return sum / n;
}

double lufsOf(double power) => -0.691 + 10 * math.log(power) / math.ln10;

/// BS.1770 loudness of a stereo signal: channel powers add.
double measureLufs(Float64List left, Float64List right) =>
    lufsOf(weightedPower(left) + weightedPower(right));

/// One sample of SoLoud's waveform generator at phase [p] (0–1), as
/// flutter_soloud 4.1.7 writes it in `soloud_misc.cpp`: ±0.5, not ±1.
double soloudWave(OscillatorWave wave, double p) => switch (wave) {
  OscillatorWave.sine => math.sin(p * math.pi * 2) * 0.5,
  OscillatorWave.triangle => (p > 0.5 ? 1 - (p - 0.5) * 2 : p * 2) - 0.5,
};

/// SoLoud's channel volumes for a voice: an absolute (left, right), or the
/// constant-power pan law of `setVoicePan`.
(double, double) channelGains(OscillatorPartial p) =>
    p.left != null && p.right != null
    ? (p.left!, p.right!)
    : (
        math.cos((p.pan + 1) * math.pi / 4),
        math.sin((p.pan + 1) * math.pi / 4),
      );

/// Loudness of an oscillator layer at full volume, rendered sample by
/// sample the way SoLoud plays it. The voices are at different
/// frequencies, so over a long listen their powers add: each is rendered
/// and measured on its own (a short window of the sum would catch the
/// drone's slow beating at one point in its cycle).
double renderedLufs(List<OscillatorPartial> partials) {
  const n = 48000; // one second at the K-weighting filters' rate
  var power = 0.0;
  for (final p in partials) {
    final (l, r) = channelGains(p);
    final x = Float64List(n);
    for (var i = 0; i < n; i++) {
      final phase = (p.hz * i / n) % 1.0;
      x[i] = p.gain * soloudWave(p.wave, phase);
    }
    power += weightedPower(x) * (l * l + r * r);
  }
  return lufsOf(power);
}

/// The highest a layer can reach in one channel at full volume: every
/// voice's peak (gain × 0.5) in phase.
double worstChannelPeak(List<OscillatorPartial> partials) {
  var left = 0.0, right = 0.0;
  for (final p in partials) {
    final (l, r) = channelGains(p);
    left += p.gain * 0.5 * l;
    right += p.gain * 0.5 * r;
  }
  return math.max(left, right);
}

/// Power between [lo] and [hi] Hz, from a forward DFT (via the inverse:
/// DFT(x) = conj(IDFT(conj(x))) · n).
double bandPower(Float64List x, double lo, double hi) {
  final n = x.length;
  final re = Float64List.fromList(x);
  final im = Float64List(n);
  inverseFft(re, im);
  var p = 0.0;
  for (var k = 1; k < n ~/ 2; k++) {
    final hz = k * NoiseSpec.sampleRate / n;
    if (hz >= lo && hz < hi) p += (re[k] * re[k] + im[k] * im[k]) * n * n;
  }
  return p;
}

double db(double ratio) => 10 * math.log(ratio) / math.ln10;

void main() {
  const small = 15; // 32768 samples: quick, and 1.5 Hz resolution

  group('noise', () {
    for (final colour in NoiseColour.values) {
      test('${colour.name} comes out at the target loudness', () {
        final loop = generateNoise(
          NoiseSpec(
            params: NoiseParams(colour: colour),
            log2Length: small,
          ),
        );
        expect(loop.lufs, closeTo(kSynthTargetLufs, 0.05));
        expect(
          measureLufs(loop.left, loop.right),
          closeTo(kSynthTargetLufs, 0.3),
        );
        final peak = [
          ...loop.left,
          ...loop.right,
        ].map((v) => v.abs()).reduce(math.max);
        expect(peak, lessThanOrEqualTo(0.89));
      });
    }

    test('colours have their slopes', () {
      double tilt(NoiseColour c) {
        final loop = generateNoise(
          NoiseSpec(
            params: NoiseParams(colour: c),
            log2Length: small,
          ),
        );
        // Three octaves apart.
        return db(
          bandPower(loop.left, 2000, 4000) / bandPower(loop.left, 250, 500),
        );
      }

      expect(tilt(NoiseColour.white), closeTo(9, 1.5));
      expect(tilt(NoiseColour.pink), closeTo(0, 1.5));
      expect(tilt(NoiseColour.brown), closeTo(-9, 1.5));
    });

    test('a band slider shapes its octave and leaves loudness at target', () {
      final bands = [...NoiseParams.flat]..[3] = 0.1; // 250 Hz down 20 dB
      final shaped = generateNoise(
        NoiseSpec(
          params: NoiseParams(bands: bands),
          log2Length: small,
        ),
      );
      final flat = generateNoise(
        const NoiseSpec(params: NoiseParams(), log2Length: small),
      );
      final dip = db(
        bandPower(shaped.left, 240, 262) / bandPower(shaped.left, 1800, 2200),
      );
      final ref = db(
        bandPower(flat.left, 240, 262) / bandPower(flat.left, 1800, 2200),
      );
      expect(ref - dip, closeTo(20, 2.5));
      expect(shaped.lufs, closeTo(kSynthTargetLufs, 0.05));
    });

    test('the same seed keeps the texture: only magnitudes change', () {
      final a = generateNoise(
        const NoiseSpec(params: NoiseParams(), log2Length: 12),
      );
      final b = generateNoise(
        const NoiseSpec(params: NoiseParams(), log2Length: 12),
      );
      expect(a.left, b.left);
      final c = generateNoise(
        const NoiseSpec(params: NoiseParams(), seed: 2, log2Length: 12),
      );
      expect(c.left, isNot(a.left));
    });

    test('left and right are independent (a wide image)', () {
      final loop = generateNoise(
        const NoiseSpec(params: NoiseParams(), log2Length: small),
      );
      var lr = 0.0, ll = 0.0, rr = 0.0;
      for (var i = 0; i < loop.left.length; i++) {
        lr += loop.left[i] * loop.right[i];
        ll += loop.left[i] * loop.left[i];
        rr += loop.right[i] * loop.right[i];
      }
      expect((lr / math.sqrt(ll * rr)).abs(), lessThan(0.05));
    });

    test('the WAV is 16-bit stereo PCM at 48 kHz', () {
      final loop = generateNoise(
        const NoiseSpec(params: NoiseParams(), log2Length: 10),
      );
      final wav = encodeWav(loop);
      final bytes = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(bytes.getUint16(22, Endian.little), 2);
      expect(bytes.getUint32(24, Endian.little), 48000);
      expect(bytes.getUint16(34, Endian.little), 16);
      expect(wav.length, 44 + 1024 * 4);
    });

    test('params survive JSON and damaged values', () {
      const p = NoiseParams(
        colour: NoiseColour.brown,
        bands: [0, .1, .2, .3, .4, .5, .6, .7, .8, .9],
      );
      expect(NoiseParams.fromJson(p.toJson()).bands, p.bands);
      final broken = NoiseParams.fromJson({
        'colour': 'plaid',
        'bands': [7, 'x'],
      });
      expect(broken.colour, NoiseColour.pink);
      expect(broken.bands, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
    });
  });

  group('drone', () {
    test('is a chord on the root', () {
      for (final timbre in DroneTimbre.values) {
        final partials = DroneParams(rootsHz: [110], timbre: timbre).partials();
        expect(partials.first.hz, 110);
        expect(partials.map((p) => p.hz), contains(220));
        expect(partials.map((p) => p.hz), contains(165));
      }
      expect(
        DroneParams(timbre: DroneTimbre.bright).partials().length,
        greaterThan(DroneParams(timbre: DroneTimbre.pure).partials().length),
      );
    });

    test('a chord holds every root, and is no louder than one root', () {
      for (final timbre in DroneTimbre.values) {
        final chord = DroneParams(
          rootsHz: [55, 110, 164.81],
          timbre: timbre,
        ).partials();
        final hz = chord.map((p) => p.hz).toList();
        for (final root in [55.0, 110.0, 164.81]) {
          expect(hz, contains(closeTo(root, 0.001)));
          expect(hz, contains(closeTo(root * 2, 0.001)));
        }
        final single = DroneParams(rootsHz: [110], timbre: timbre).partials();
        // Voices on one frequency are one voice (A1's octave is A2's root).
        expect(chord.length, lessThan(single.length * 3));
        expect(chord.length, greaterThan(single.length));
        for (var i = 0; i < chord.length; i++) {
          for (var j = i + 1; j < chord.length; j++) {
            expect(
              chord[i].wave == chord[j].wave &&
                  (chord[i].hz - chord[j].hz).abs() < 0.01,
              isFalse,
              reason: '${chord[i].hz} twice',
            );
          }
        }
        expect(renderedLufs(chord), closeTo(kSynthTargetLufs, 0.2));
        expect(worstChannelPeak(chord), lessThan(kSynthPeakBound));
      }
    });

    test('no two voices of a chord share a frequency, in any timbre', () {
      for (final timbre in DroneTimbre.values) {
        for (final roots in [
          [55.0, 110.0],
          [55.0, 110.0, 220.0],
          [110.0, 220.0],
          [73.42, 146.83],
          [82.41, 164.81, 55.0],
          [55.0, 82.41, 98.0],
        ]) {
          final ps = DroneParams(rootsHz: roots, timbre: timbre).partials();
          for (var i = 0; i < ps.length; i++) {
            for (var j = i + 1; j < ps.length; j++) {
              expect(
                (ps[i].hz - ps[j].hz).abs() > 1e-4 * ps[i].hz,
                isTrue,
                reason: '$roots ${timbre.name}: ${ps[i].hz} and ${ps[j].hz}',
              );
            }
          }
          expect(
            renderedLufs(ps),
            closeTo(kSynthTargetLufs, 0.2),
            reason: '$roots ${timbre.name}',
          );
        }
      }
    });

    test('merging is deterministic: same voices and loudness every time', () {
      const chord = DroneParams(
        rootsHz: [55, 110, 220],
        timbre: DroneTimbre.bright,
      );
      final a = chord.partials(), b = chord.partials();
      // A1+A2+A3 bright: 24 voices, 8 shared.
      expect(a.length, 16);
      expect(
        [for (final p in a) (p.hz, p.gain, p.pan)],
        [for (final p in b) (p.hz, p.gain, p.pan)],
      );
      expect(renderedLufs(a), closeTo(kSynthTargetLufs, 0.2));
    });

    test('the peak bound holds for any chord, stored or chosen', () {
      final lows = [...DroneParams.roots.values, 40.0, 41.0, 42.0, 40.5, 440.0];
      for (final timbre in DroneTimbre.values) {
        // The editor's loudest chord: low roots weigh little in the
        // K-weighting, so they get the most gain.
        final worst = DroneParams(
          rootsHz: [55, 73.42, 82.41],
          timbre: timbre,
        ).partials();
        expect(worstChannelPeak(worst), lessThan(kSynthPeakBound));
        // Clustered lowest roots the clamp allows, every triple, and every
        // chord of four and five.
        for (final roots in [
          [40.0, 41.0, 42.0],
          [40.0, 40.5, 41.0],
          [40.0, 40.5, 41.0, 41.5, 42.0],
          for (var i = 0; i < lows.length; i++)
            for (var j = i + 1; j < lows.length; j++)
              for (var k = j + 1; k < lows.length; k++) ...[
                [lows[i], lows[j], lows[k]],
                for (var l = k + 1; l < lows.length; l++) ...[
                  [lows[i], lows[j], lows[k], lows[l]],
                  for (var m = l + 1; m < lows.length; m++)
                    [lows[i], lows[j], lows[k], lows[l], lows[m]],
                ],
              ],
        ]) {
          final p = DroneParams(rootsHz: roots, timbre: timbre).partials();
          expect(
            worstChannelPeak(p),
            lessThan(kSynthPeakBound),
            reason: '$roots ${timbre.name}',
          );
        }
      }
    });

    test('a chord never swells in step', () {
      final ps = const DroneParams(
        rootsHz: [55, 82.41, 110],
        timbre: DroneTimbre.bright,
        movement: 1,
      ).partials();
      expect(ps.map((p) => p.swellPeriod).toSet().length, ps.length);
      // Nor the largest there is: five bright roots sharing no frequency.
      final most = const DroneParams(
        rootsHz: [55, 73.42, 82.41, 98, 130.81],
        timbre: DroneTimbre.bright,
        movement: 1,
      ).partials();
      expect(most.length, 40);
      expect(most.map((p) => p.swellPeriod).toSet().length, 40);
    });

    group('five roots (#69, raised from three)', () {
      const chips = [55.0, 73.42, 82.41, 98.0, 110.0, 130.81, 146.83, 164.81];
      test('the cap is five, and the editor offers nine roots', () {
        expect(DroneParams.maxRoots, 5);
        expect(DroneParams.roots.values, [...chips, 220.0]);
      });

      test('a root is 4, 6 or 8 voices, so a chord is at most 40', () {
        const perRoot = {
          DroneTimbre.pure: 4,
          DroneTimbre.warm: 6,
          DroneTimbre.bright: 8,
        };
        final roots = DroneParams.roots.values.toList();
        for (final timbre in DroneTimbre.values) {
          expect(
            DroneParams(rootsHz: const [110], timbre: timbre).partials().length,
            perRoot[timbre],
          );
          var most = 0;
          for (var a = 0; a < roots.length; a++) {
            for (var b = a + 1; b < roots.length; b++) {
              for (var c = b + 1; c < roots.length; c++) {
                for (var d = c + 1; d < roots.length; d++) {
                  for (var e = d + 1; e < roots.length; e++) {
                    final n = DroneParams(
                      rootsHz: [
                        roots[a],
                        roots[b],
                        roots[c],
                        roots[d],
                        roots[e],
                      ],
                      timbre: timbre,
                    ).partials().length;
                    if (n > most) most = n;
                  }
                }
              }
            }
          }
          // No merge at all in the worst chord: five times one root.
          expect(most, 5 * perRoot[timbre]!, reason: timbre.name);
        }
      });

      test('a middle chord of five is as loud as one root', () {
        for (final timbre in DroneTimbre.values) {
          final chord = DroneParams(
            rootsHz: const [110, 130.81, 146.83, 164.81, 220],
            timbre: timbre,
          ).partials();
          final hz = chord.map((p) => p.hz).toList();
          for (final root in [110.0, 130.81, 146.83, 164.81, 220.0]) {
            expect(hz, contains(closeTo(root, 0.001)));
          }
          // A2's octave is A3's root: one voice.
          final single = DroneParams(
            rootsHz: const [110],
            timbre: timbre,
          ).partials();
          expect(chord.length, lessThan(5 * single.length));
          expect(chord.length, greaterThan(3 * single.length));
          for (var i = 0; i < chord.length; i++) {
            for (var j = i + 1; j < chord.length; j++) {
              expect(
                chord[i].wave == chord[j].wave &&
                    (chord[i].hz - chord[j].hz).abs() <= 1e-4 * chord[i].hz,
                isFalse,
                reason: '${chord[i].hz} twice',
              );
            }
          }
          expect(
            renderedLufs(chord),
            closeTo(kSynthTargetLufs, 0.2),
            reason: timbre.name,
          );
          expect(worstChannelPeak(chord), lessThan(kSynthPeakBound));
        }
      });

      test('five low bright roots are held under the peak bound, and play '
          'a little under the target for it', () {
        // The editor's worst: no shared frequency, and low roots weigh
        // least in the K-weighting, so they ask for the most gain.
        final low = const DroneParams(
          rootsHz: [55, 73.42, 82.41, 98, 130.81],
          timbre: DroneTimbre.bright,
        ).partials();
        expect(low.length, 40);
        expect(worstChannelPeak(low), lessThan(kSynthPeakBound));
        expect(worstChannelPeak(low), greaterThan(0.97 * kSynthPeakBound));
        final under = renderedLufs(low) - kSynthTargetLufs;
        // Never louder than a single root; about 1.5 dB quieter here.
        expect(under, lessThan(0));
        expect(under, closeTo(-1.52, 0.15));
        // The lowest five a stored mix may hold (the range's floor).
        final floor = const DroneParams(
          rootsHz: [40, 40.5, 41, 41.5, 42],
          timbre: DroneTimbre.bright,
        ).partials();
        expect(worstChannelPeak(floor), lessThan(kSynthPeakBound));
        expect(renderedLufs(floor), lessThan(kSynthTargetLufs));
      });

      test('chords of one to three roots are the voices they were', () {
        // Pinned from the three-root build: counts, the first voices, and
        // every swell period (the table's first 24 entries are unchanged).
        const was = [
          29, 41, 53, 67, 37, 47, 59, 71, 31, 43, 61, 73, //
          79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137,
        ];
        final three = const DroneParams(
          rootsHz: [55, 73.42, 82.41],
          timbre: DroneTimbre.bright,
          movement: 0.6,
        ).partials();
        expect(three.length, 24);
        expect(
          [for (final p in three) p.swellPeriod!.inMilliseconds],
          [for (final s in was) s * 1000],
        );
        expect(
          const DroneParams(
            rootsHz: [55, 110, 220],
            timbre: DroneTimbre.bright,
          ).partials().length,
          16,
        );
        final stored = DroneParams.fromJson({
          'rootHz': 73.42,
          'rootsHz': [73.42, 110.0, 164.81],
          'timbre': 'warm',
          'movement': 0.5,
        });
        expect(stored.rootsHz, [73.42, 110, 164.81]);
        expect(stored.toJson(), {
          'rootHz': 73.42,
          'rootsHz': [73.42, 110.0, 164.81],
          'timbre': 'warm',
          'movement': 0.5,
        });
        final ps = stored.partials();
        expect(ps.length, 18);
        expect(renderedLufs(ps), closeTo(kSynthTargetLufs, 0.2));
      });
    });

    test('a single root saves as it always did', () {
      expect(const DroneParams(rootsHz: [98]).toJson().keys.toSet(), {
        'rootHz',
        'timbre',
        'movement',
      });
      expect(const DroneParams().toJson(), {
        'rootHz': 110.0,
        'timbre': 'warm',
        'movement': 0.5,
      });
    });

    test('roots are tidied however the params were built', () {
      expect(const DroneParams(rootsHz: []).rootHz, 110);
      expect(const DroneParams(rootsHz: [220, 55]).rootHz, 55);
      expect(const DroneParams(rootsHz: [220, 55, 110, 82.41]).rootsHz, [
        55,
        82.41,
        110,
        220,
      ]);
      // A sixth and seventh are dropped from the top.
      expect(
        const DroneParams(
          rootsHz: [220, 55, 110, 82.41, 98, 146.83, 73.42],
        ).rootsHz,
        [55, 73.42, 82.41, 98, 110],
      );
    });

    test('params round-trip, and read the old single rootHz', () {
      const chord = DroneParams(rootsHz: [73.42, 110, 164.81]);
      expect(DroneParams.fromJson(chord.toJson()).rootsHz, chord.rootsHz);
      expect(chord.toJson()['rootHz'], 73.42);
      final old = DroneParams.fromJson({'rootHz': 98.0, 'timbre': 'bright'});
      expect(old.rootsHz, [98.0]);
      expect(old.timbre, DroneTimbre.bright);
      // Unsorted, duplicated, too many, junk: tidied.
      expect(
        DroneParams.fromJson({
          'rootsHz': [220, 55, 55, 110, 82.41, 'x'],
        }).rootsHz,
        [55, 82.41, 110, 220],
      );
      expect(
        DroneParams.fromJson({
          'rootsHz': [220, 55, 55, 110, 82.41, 'x', 98, 164.81, 130.81],
        }).rootsHz,
        [55, 82.41, 98, 110, 130.81],
      );
      expect(DroneParams.fromJson({'rootsHz': []}).rootsHz, [110]);
      expect(DroneParams.fromJson(const {}).rootsHz, [110]);
    });

    for (final root in ['A1', 'D2', 'A2', 'A3']) {
      test('$root plays at the target loudness, as rendered', () {
        for (final timbre in DroneTimbre.values) {
          final partials = DroneParams(
            rootsHz: [DroneParams.roots[root]!],
            timbre: timbre,
          ).partials();
          expect(
            renderedLufs(partials),
            closeTo(kSynthTargetLufs, 0.2),
            reason: '$root ${timbre.name}',
          );
          expect(
            worstChannelPeak(partials),
            lessThan(kSynthPeakBound),
            reason: '$root ${timbre.name}',
          );
        }
      });
    }

    test('every root stays under the peak bound', () {
      // The editor's roots, and the ends of the range saved params may hold
      // (40–440 Hz; a bright 40 Hz drone peaks at about 0.185).
      for (final hz in [40.0, ...DroneParams.roots.values, 440.0]) {
        for (final timbre in DroneTimbre.values) {
          final partials = DroneParams(
            rootsHz: [hz],
            timbre: timbre,
          ).partials();
          expect(worstChannelPeak(partials), lessThan(kSynthPeakBound));
        }
      }
    });

    test('Stillness sets its drone under its noise by the sliders alone', () {
      final stillness = kStarterPresets.firstWhere(
        (p) => p.id == 'starter-stillness',
      );
      final noise = stillness.mix.layer(kSynthNoiseId)!;
      final drone = stillness.mix.layer(kSynthDroneId)!;
      final loop = generateNoise(
        NoiseSpec(
          params: NoiseParams.fromJson(noise.params),
          log2Length: small,
        ),
      );
      double db20(double g) => 20 * math.log(g) / math.ln10;
      final noiseLevel =
          measureLufs(loop.left, loop.right) + db20(layerGain(noise.volume));
      final droneLevel =
          renderedLufs(DroneParams.fromJson(drone.params).partials()) +
          db20(layerGain(drone.volume));
      // Both are made at −27 LUFS, so the gap is the sliders' (0.35² against
      // 0.55², about 7.9 dB), not the generators'.
      expect(
        droneLevel - noiseLevel,
        closeTo(db20(layerGain(drone.volume) / layerGain(noise.volume)), 0.4),
      );
    });

    test('movement sets the swell; none holds still', () {
      expect(
        const DroneParams(
          movement: 0,
        ).partials().every((p) => p.swellPeriod == null),
        isTrue,
      );
      final moving = const DroneParams(movement: 1).partials();
      final periods = moving.map((p) => p.swellPeriod!).toSet();
      expect(
        periods.length,
        moving.length,
        reason: 'voices never swell in step',
      );
      expect(moving.first.swellFloor, closeTo(0.4, 1e-9));
    });
  });

  group('binaural beats', () {
    test('one tone per ear, beat apart around the carrier', () {
      final ps = const BinauralParams(carrierHz: 200, beatHz: 6).partials();
      expect(ps.map((p) => p.hz), [197, 203]);
      expect((ps[0].left, ps[0].right), (1, 0));
      expect((ps[1].left, ps[1].right), (0, 1));
    });

    test('plays at the target loudness down to an 80 Hz carrier', () {
      for (final (carrier, beat) in [
        (80.0, 4.0),
        (200.0, 6.0),
        (500.0, 30.0),
      ]) {
        final ps = BinauralParams(carrierHz: carrier, beatHz: beat).partials();
        expect(
          renderedLufs(ps),
          closeTo(kSynthTargetLufs, 0.2),
          reason: '$carrier Hz',
        );
        expect(worstChannelPeak(ps), lessThan(kSynthPeakBound));
        // Each ear carries the same loudness.
        expect(
          renderedLufs([ps[0]]),
          closeTo(renderedLufs([ps[1]]), 0.1),
          reason: '$carrier Hz',
        );
      }
    });

    test('names the band and clamps to sane ranges', () {
      expect(const BinauralParams(beatHz: 2).band, BeatBand.delta);
      expect(const BinauralParams(beatHz: 6).band, BeatBand.theta);
      expect(const BinauralParams(beatHz: 10).band, BeatBand.alpha);
      expect(const BinauralParams(beatHz: 20).band, BeatBand.beta);
      final p = BinauralParams.fromJson({'carrierHz': 5000, 'beatHz': -3});
      expect(p.carrierHz, BinauralParams.maxCarrier);
      expect(p.beatHz, BinauralParams.minBeat);
    });
  });
}
