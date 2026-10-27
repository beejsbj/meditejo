import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:medito/services/bells/bell_recipe.dart';
import 'package:medito/services/bells/bell_recipes.dart';
import 'package:medito/widgets/art/engine/bell.dart';

/// A bell to make: a shipped bell to start from ([preset], a key of
/// [bellRecipes]) and the five controls moved from it.
class BellSpec {
  BellSpec(this.preset, BellKnobs knobs) : knobs = clampKnobs(knobs) {
    if (!bellRecipes.containsKey(preset)) {
      throw ArgumentError.value(preset, 'preset', 'not a shipped bell');
    }
  }

  /// [preset] as it ships, its controls untouched.
  factory BellSpec.preset(String preset) =>
      BellSpec(preset, bellRecipes[preset]!.knobs);

  final String preset;
  final BellKnobs knobs;

  /// Every control held to its range, and NaN or infinity to its middle.
  static BellKnobs clampKnobs(BellKnobs k) {
    double c(String name) {
      final r = BellFigure.knobs[name]!;
      final v = k[name];
      return v.isFinite ? v.clamp(r.min, r.max) : (r.min + r.max) / 2;
    }

    return BellKnobs(
      pitch: c('pitch'),
      bright: c('bright'),
      ring: c('ring'),
      strike: c('strike'),
      shimmer: c('shimmer'),
    );
  }

  /// The same spec for the same inputs, whatever the platform: a cache key.
  String get key =>
      '$preset:${knobs.pitch.toStringAsFixed(2)}:'
      '${knobs.bright.toStringAsFixed(4)}:${knobs.ring.toStringAsFixed(3)}:'
      '${knobs.strike.toStringAsFixed(4)}:${knobs.shimmer.toStringAsFixed(3)}';

  @override
  bool operator ==(Object other) => other is BellSpec && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Modal synthesis of a bell, in Dart: the model of
/// `tools/meditejo/generate_bells.py` (decaying sines at inharmonic
/// frequencies, each split in two so it beats, plus a filtered-noise strike),
/// moved by the five controls, and scaled to the loudness the shipped bells
/// have. The same [BellSpec] always gives the same bytes: no clock, no
/// platform random, no state.
///
/// What each control moves, from the bell it starts at:
///
///   pitch    every mode's frequency, by the same ratio
///   bright   the upper modes' level, until their share of the ring's energy
///            is the one asked for
///   ring     every mode's decay, by the same ratio
///   strike   the noise's low-pass (300 Hz soft mallet .. 10 kHz hard) and level
///   shimmer  every mode's beat, by the same ratio
///
/// Rendering takes a few hundred milliseconds on a phone: call
/// [renderBellWavInBackground] from the UI.
abstract final class BellSynth {
  /// Momentary loudness (LUFS, K-weighted, 400 ms) of Medito's session bell,
  /// which every bell is scaled to (`TARGET_MOMENTARY_LUFS` in the
  /// generator).
  static const targetMomentaryLufs = -9.84;

  /// No sample goes above -1 dBFS.
  static final peakCeiling = math.pow(10, -1 / 20).toDouble();

  /// The longest ring: SoundPool refuses a sound over about 1 MiB.
  static const _maxSeconds22k = 12.0, _maxSeconds44k = 10.0;

  /// Decay below this amplitude (about -34 dB re the loudest mode) is where a
  /// bell is cut and faded.
  static const _audible = 0.02;

  /// The modes of [spec]: its bell's, moved by the controls (`modesFor`).
  static List<BellMode> modes(BellSpec spec) {
    final recipe = bellRecipes[spec.preset]!;
    final ref = recipe.knobs;
    final k = spec.knobs;
    final fk = k.pitch / ref.pitch;
    final tk = k.ring / math.max(ref.ring, 1e-3);
    final moved = [
      for (final m in recipe.modes)
        m.copyWith(
          f: m.f * fk,
          tau: m.tau * tk,
          beat: ref.shimmer > 0
              ? m.beat * k.shimmer / ref.shimmer
              : k.shimmer * math.sqrt(m.f * fk / ref.pitch),
        ),
    ];
    // Brightness: the upper modes take whatever level gives them the share of
    // the ring's energy asked for.
    final main = moved.reduce((a, b) => b.a > a.a ? b : a);
    double e(BellMode m) => m.a * m.a * m.tau;
    var lo = 0.0, hi = 0.0;
    for (final m in moved) {
      if (m.f > main.f * 1.05) {
        hi += e(m);
      } else {
        lo += e(m);
      }
    }
    if (hi <= 0) return moved;
    final b = k.bright.clamp(0.001, 0.98);
    final g = math.sqrt(b * lo / ((1 - b) * hi));
    return [
      for (final m in moved)
        m.f > main.f * 1.05 ? m.copyWith(a: m.a * g) : m,
    ];
  }

  /// 44.1 kHz when the ring has something to say above 8 kHz or the strike is hard,
  /// else 22.05 kHz, as the shipped bells do.
  static int rateOf(BellSpec spec, List<BellMode> modes) {
    var top = 0.0;
    for (final m in modes) {
      if (m.a > 0.01 && m.f > top) top = m.f;
    }
    return top > 8000 || spec.knobs.strike > 0.9 ? 44100 : 22050;
  }

  /// Seconds of ring: until the slowest mode has fallen to [_audible], plus a
  /// little, between the length of a knock and the longest SoundPool takes.
  static double secondsOf(List<BellMode> modes, int rate) {
    var t = 0.0;
    for (final m in modes) {
      if (m.a > _audible) t = math.max(t, m.tau * math.log(m.a / _audible));
    }
    final cap = rate == 44100 ? _maxSeconds44k : _maxSeconds22k;
    return (t + 0.15).clamp(0.3, cap);
  }

  /// The mono 16-bit WAV of [spec].
  static Uint8List render(BellSpec spec) {
    final ms = modes(spec);
    final rate = rateOf(spec, ms);
    final seconds = secondsOf(ms, rate);
    final n = (rate * seconds).round();
    final x = Float64List(n);
    for (final m in ms) {
      _addMode(x, rate, m);
    }
    final recipe = bellRecipes[spec.preset]!;
    final tk = spec.knobs.ring / math.max(recipe.knobs.ring, 1e-3);
    final wash = recipe.wash;
    final hit = recipe.hit;
    final ref = recipe.knobs;
    // The strike: its low-pass follows the control, its level grows with it.
    final lowpass = BellRecipe.lowpassOf(spec.knobs.strike);
    final level =
        hit.level *
        (0.6 + 0.8 * spec.knobs.strike) /
        (0.6 + 0.8 * ref.strike);
    _addStrike(x, rate, hit, lowpass, level, 0x9E3779B9);
    if (wash != null) _addWash(x, rate, wash, tk);
    return _finish(x, rate);
  }

  // A mode, as the generator's render() adds it. The sine is a rotation by
  // one sample's phase, which costs a multiply and not a sin() per sample;
  // a gliding pitch has no such recurrence and takes the slow way.
  static void _addMode(Float64List out, int rate, BellMode m) {
    final n = out.length;
    if (m.f >= rate * 0.46) return;
    final halves = m.beat == 0
        ? [(m.f, m.a)]
        : [
            (m.f - m.beat / 2, m.a * (1 - m.split)),
            (m.f + m.beat / 2, m.a * m.split),
          ];
    final decay = math.exp(-1 / (rate * m.tau));
    final grow = m.rise > 0 ? math.exp(-1 / (rate * m.rise)) : 0.0;
    // Past about -120 dB nothing is audible: stop instead of adding zeros.
    final last = math.min(n, (13.8 * m.tau * rate).floor() + 1);
    for (final (f, amp) in halves) {
      if (f <= 0) continue;
      final w = 2 * math.pi * f / rate;
      var env = amp;
      var g = 1.0;
      if (m.glideDrop != 0) {
        for (var i = 0; i < last; i++) {
          final t = i / rate;
          final arg =
              w * i +
              2 *
                  math.pi *
                  f *
                  m.glideDrop *
                  m.glideTau *
                  (1 - math.exp(-t / m.glideTau));
          out[i] += env * (grow > 0 ? 1 - g : 1) * math.sin(arg + m.phase);
          env *= decay;
          g *= grow;
        }
        continue;
      }
      final c2 = 2 * math.cos(w);
      var y1 = math.sin(m.phase - w), y2 = math.sin(m.phase - 2 * w);
      for (var i = 0; i < last; i++) {
        final y = c2 * y1 - y2;
        y2 = y1;
        y1 = y;
        out[i] += env * (grow > 0 ? 1 - g : 1) * y;
        env *= decay;
        g *= grow;
      }
    }
  }

  // The mallet meeting the metal: noise through two one-pole low-passes,
  // `strike()` in the generator, from a fixed-seed generator of its own.
  static void _addStrike(
    Float64List out,
    int rate,
    BellHit hit,
    double lowpass,
    double level,
    int seed,
  ) {
    final n = math.min(out.length, (rate * hit.seconds).round());
    final k = 1 - math.exp(-2 * math.pi * lowpass / rate);
    final noise = _Noise(seed);
    var y = 0.0, z = 0.0;
    for (var i = 0; i < n; i++) {
      y += k * (noise.next() - y);
      z += k * (y - z);
      final t = i / rate;
      out[i] +=
          z *
          1.6 *
          math.exp(-t / hit.tau) *
          math.min(1.0, t / hit.attack) *
          level;
    }
  }

  static void _addWash(Float64List out, int rate, BellWash wash, double tk) {
    final k = 1 - math.exp(-2 * math.pi * wash.lowpass / rate);
    final noise = _Noise(0x85EBCA6B);
    var y = 0.0, z = 0.0;
    for (var i = 0; i < out.length; i++) {
      y += k * (noise.next() - y);
      z += k * (y - z);
      final t = i / rate;
      out[i] +=
          z *
          wash.level *
          (1 - math.exp(-t / wash.rise)) *
          math.exp(-t / (wash.tau * tk));
    }
  }

  // The generator's finish(): a raised-cosine fade to an exact zero ends the
  // file without a click, a 1 ms ramp opens it the same way, and the gain
  // makes the loudest 400 ms as loud as the session bell, held under the
  // peak ceiling.
  static Uint8List _finish(Float64List x, int rate) {
    final n = x.length;
    final fade = math.min(
      n - 1,
      (rate * (0.25 * n / rate).clamp(0.08, 3.0)).round(),
    );
    for (var i = 0; i < fade; i++) {
      x[n - fade + i] *= 0.5 * (1 + math.cos(math.pi * i / (fade - 1)));
    }
    x[n - 1] = 0;
    final ramp = math.max(2, (rate * 0.001).round());
    for (var i = 0; i < ramp && i < n; i++) {
      x[i] *= 0.5 * (1 - math.cos(math.pi * i / ramp));
    }
    var peak = 0.0;
    for (final v in x) {
      peak = math.max(peak, v.abs());
    }
    var gain = 0.0;
    if (peak > 0) {
      final loud = maxMomentaryLufs(x, rate);
      gain = math.pow(10, (targetMomentaryLufs - loud) / 20).toDouble();
      gain = math.min(gain, peakCeiling / peak);
    }
    final pcm = Int16List(n);
    for (var i = 0; i < n; i++) {
      pcm[i] = (x[i] * gain * 32767).round().clamp(-32768, 32767);
    }
    return wavBytes(pcm, rate);
  }

  /// A 44-byte-header WAV of mono 16-bit [pcm].
  static Uint8List wavBytes(Int16List pcm, int rate) {
    final bytes = ByteData(44 + pcm.length * 2);
    void tag(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    bytes.setUint32(4, 36 + pcm.length * 2, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, rate, Endian.little);
    bytes.setUint32(28, rate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    bytes.setUint32(40, pcm.length * 2, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      bytes.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  /// The samples (-1..1) and rate of a mono 16-bit WAV from [wavBytes].
  static (Float64List, int) samplesOf(Uint8List wav) {
    final data = ByteData.sublistView(wav);
    final rate = data.getUint32(24, Endian.little);
    final count = (wav.length - 44) ~/ 2;
    return (
      Float64List.fromList([
        for (var i = 0; i < count; i++)
          data.getInt16(44 + i * 2, Endian.little) / 32768,
      ]),
      rate,
    );
  }

  /// The loudest momentary loudness (LUFS) of [x] at [rate]: K-weighted
  /// (ITU-R BS.1770), over 400 ms blocks every 100 ms, [x] zero-padded to at
  /// least one block (`momentary_lufs` in the generator).
  static double maxMomentaryLufs(Float64List x, int rate) {
    final w = _kWeight(x, rate);
    final block = (0.4 * rate).round(), hop = (0.1 * rate).round();
    final len = math.max(w.length, block);
    var best = double.negativeInfinity;
    for (var start = 0; start + block <= len; start += hop) {
      var sum = 0.0;
      final end = math.min(start + block, w.length);
      for (var i = start; i < end; i++) {
        sum += w[i] * w[i];
      }
      final ms = sum / block;
      if (ms > 0) best = math.max(best, -0.691 + 10 * _log10(ms));
    }
    return best;
  }

  static double _log10(double v) => math.log(v) / math.ln10;

  static Float64List _kWeight(Float64List x, int rate) {
    // Stage 1: the head-related high shelf. Stage 2: the RLB high-pass.
    const f1 = 1681.974450955533, gain = 3.999843853973347;
    const q1 = 0.7071752369554196;
    var k = math.tan(math.pi * f1 / rate);
    final vh = math.pow(10, gain / 20).toDouble();
    final vb = math.pow(vh, 0.4996667741545416).toDouble();
    var d = 1 + k / q1 + k * k;
    final shelfB = [
      (vh + vb * k / q1 + k * k) / d,
      2 * (k * k - vh) / d,
      (vh - vb * k / q1 + k * k) / d,
    ];
    final shelfA = [2 * (k * k - 1) / d, (1 - k / q1 + k * k) / d];
    const f2 = 38.13547087602444, q2 = 0.5003270373238773;
    k = math.tan(math.pi * f2 / rate);
    d = 1 + k / q2 + k * k;
    final hpA = [2 * (k * k - 1) / d, (1 - k / q2 + k * k) / d];
    return _biquad(_biquad(x, shelfB, shelfA), const [1.0, -2.0, 1.0], hpA);
  }

  static Float64List _biquad(Float64List x, List<double> b, List<double> a) {
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
    final out = Float64List(x.length);
    for (var i = 0; i < x.length; i++) {
      final v = x[i];
      final y = b[0] * v + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2;
      out[i] = y;
      x2 = x1;
      x1 = v;
      y2 = y1;
      y1 = y;
    }
    return out;
  }
}

/// Uniform noise in -1..1 from a 32-bit xorshift: the same stream on every
/// platform, unlike a library's random.
class _Noise {
  _Noise(int seed) : _s = seed & 0xFFFFFFFF == 0 ? 1 : seed & 0xFFFFFFFF;

  int _s;

  double next() {
    _s ^= (_s << 13) & 0xFFFFFFFF;
    _s ^= _s >> 17;
    _s ^= (_s << 5) & 0xFFFFFFFF;
    return _s / 0x80000000 - 1;
  }
}

/// [BellSynth.render] off the UI thread.
Future<Uint8List> renderBellWavInBackground(BellSpec spec) =>
    Isolate.run(() => BellSynth.render(spec));
