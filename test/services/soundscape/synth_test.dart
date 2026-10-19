import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/services/soundscape/synth/noise_generator.dart';

/// BS.1770 loudness measured the long way: filter the loop through the
/// K-weighting biquads in the time domain (twice round, keeping the second
/// lap so the filters are in their periodic steady state) and average.
double measureLufs(Float64List left, Float64List right) {
  double weighted(Float64List x) {
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

  return -0.691 + 10 * math.log(weighted(left) + weighted(right)) / math.ln10;
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
    double meanSquare(List<OscillatorPartial> ps) =>
        ps.fold(0.0, (s, p) => s + p.gain * p.gain / 2);

    test('is a chord on the root at the target loudness', () {
      for (final timbre in DroneTimbre.values) {
        final partials = DroneParams(rootHz: 110, timbre: timbre).partials();
        expect(partials.first.hz, 110);
        expect(partials.map((p) => p.hz), contains(220));
        expect(partials.map((p) => p.hz), contains(165));
        final lufs = -0.691 + 10 * math.log(meanSquare(partials)) / math.ln10;
        expect(lufs, closeTo(kSynthTargetLufs, 0.01), reason: timbre.name);
      }
      expect(
        DroneParams(timbre: DroneTimbre.bright).partials().length,
        greaterThan(DroneParams(timbre: DroneTimbre.pure).partials().length),
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
      final ms = ps.fold(0.0, (s, p) => s + p.gain * p.gain / 2);
      expect(
        -0.691 + 10 * math.log(ms) / math.ln10,
        closeTo(kSynthTargetLufs, 0.01),
      );
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
