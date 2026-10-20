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

/// Peak bound for one generated layer at full volume, every voice in
/// phase: −12 dBFS. Among the editor's roots the loudest, a bright A1
/// drone, peaks at about 0.15 (−16 dBFS); a bright 40 Hz drone, the lowest
/// root saved params can hold, at about 0.185; binaural beats at about
/// 0.065 an ear.
const kLayerPeakBound = 0.25;

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
        final partials = DroneParams(rootHz: 110, timbre: timbre).partials();
        expect(partials.first.hz, 110);
        expect(partials.map((p) => p.hz), contains(220));
        expect(partials.map((p) => p.hz), contains(165));
      }
      expect(
        DroneParams(timbre: DroneTimbre.bright).partials().length,
        greaterThan(DroneParams(timbre: DroneTimbre.pure).partials().length),
      );
    });

    for (final root in ['A1', 'D2', 'A2', 'A3']) {
      test('$root plays at the target loudness, as rendered', () {
        for (final timbre in DroneTimbre.values) {
          final partials = DroneParams(
            rootHz: DroneParams.roots[root]!,
            timbre: timbre,
          ).partials();
          expect(
            renderedLufs(partials),
            closeTo(kSynthTargetLufs, 0.2),
            reason: '$root ${timbre.name}',
          );
          expect(
            worstChannelPeak(partials),
            lessThan(kLayerPeakBound),
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
          final partials = DroneParams(rootHz: hz, timbre: timbre).partials();
          expect(worstChannelPeak(partials), lessThan(kLayerPeakBound));
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
        expect(worstChannelPeak(ps), lessThan(kLayerPeakBound));
        // Each ear carries the same loudness.
        expect(
          renderedLufs([ps[0]]),
          closeTo(renderedLufs([ps[1]]), 0.1),
          reason: '$carrier Hz',
        );
      }
    });

    test('names the band and clamps to sane ranges', () {
      expect(const BinauralParams(beatHz: 2).band, 'delta');
      expect(const BinauralParams(beatHz: 6).band, 'theta');
      expect(const BinauralParams(beatHz: 10).band, 'alpha');
      expect(const BinauralParams(beatHz: 20).band, 'beta');
      final p = BinauralParams.fromJson({'carrierHz': 5000, 'beatHz': -3});
      expect(p.carrierHz, BinauralParams.maxCarrier);
      expect(p.beatHz, BinauralParams.minBeat);
    });
  });
}
