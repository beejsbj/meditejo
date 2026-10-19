import 'dart:math' as math;
import 'dart:typed_data';

import '../../../models/soundscape/synth.dart';

/// Generates a coloured, band-shaped noise loop that is seamless by
/// construction: it is built as a spectrum (random phases, magnitudes from
/// the colour and the ten bands) and turned into sound by an inverse FFT, so
/// the result is exactly periodic and its end runs into its start.
///
/// Loudness is set from the spectrum itself: the ITU-R BS.1770 K-weighting
/// response is applied to each bin's power, so every colour and every band
/// setting comes out at the same [kSynthTargetLufs] as the recordings.
///
/// The phases come from [seed]: regenerating with new bands but the same
/// seed gives the same texture, so the engine can crossfade between the old
/// and new loop at the same position without a seam.
class NoiseSpec {
  const NoiseSpec({required this.params, this.seed = 1, this.log2Length = 20});

  final NoiseParams params;
  final int seed;

  /// 2^20 samples at 48 kHz: a 21.8 s loop, long enough not to be heard
  /// repeating.
  final int log2Length;

  static const sampleRate = 48000;

  int get length => 1 << log2Length;
}

class NoiseLoop {
  const NoiseLoop(this.left, this.right, this.lufs);

  final Float64List left;
  final Float64List right;

  /// Integrated loudness the loop was set to (from its spectrum).
  final double lufs;
}

/// High-pass corner: brown noise would otherwise pile up below hearing.
const _lowCut = 20.0;

/// Above this the spectrum rolls off to nothing by Nyquist.
const _highCut = 18000.0;

/// Highest sample magnitude allowed after levelling.
const _peakCeiling = 0.89; // −1 dBFS

NoiseLoop generateNoise(NoiseSpec spec) {
  final n = spec.length;
  final random = math.Random(spec.seed);
  final magnitude = Float64List(n ~/ 2 + 1);
  var weighted = 0.0;
  for (var k = 1; k < n ~/ 2; k++) {
    final hz = k * NoiseSpec.sampleRate / n;
    final m = _magnitude(spec.params, hz);
    magnitude[k] = m;
    weighted += m * m * kWeightingPower(hz);
  }

  final channels = [
    for (var c = 0; c < 2; c++) _synthesise(magnitude, n, random),
  ];

  // Mean square of a real signal from its one-sided spectrum (Parseval,
  // with this IFFT's 1/n scaling): 2·Σ|X[k]|² / n². The same holds for the
  // K-weighted spectrum, which is the BS.1770 per-channel mean square.
  final perChannel = 2 * weighted / (n.toDouble() * n);
  final loudness = -0.691 + 10 * math.log(2 * perChannel) / math.ln10;
  var gain = math.pow(10, (kSynthTargetLufs - loudness) / 20).toDouble();
  var peak = 0.0;
  for (final ch in channels) {
    for (final v in ch) {
      peak = math.max(peak, v.abs());
    }
  }
  if (peak * gain > _peakCeiling) gain = _peakCeiling / peak;
  for (final ch in channels) {
    for (var i = 0; i < n; i++) {
      ch[i] *= gain;
    }
  }
  final lufs = loudness + 20 * math.log(gain) / math.ln10;
  return NoiseLoop(channels[0], channels[1], lufs);
}

double _magnitude(NoiseParams params, double hz) {
  // Power ∝ 1/f^exponent, so amplitude ∝ f^(−exponent/2), relative to 1 kHz.
  var m = math.pow(hz / 1000, -params.colour.exponent / 2).toDouble();
  m *= params.bandGain(hz);
  if (hz < _lowCut) {
    m *= math.pow(hz / _lowCut, 2); // second-order slope below the corner
  }
  if (hz > _highCut) {
    final t = (hz - _highCut) / (NoiseSpec.sampleRate / 2 - _highCut);
    m *= math.cos(t.clamp(0.0, 1.0) * math.pi / 2);
  }
  return m;
}

Float64List _synthesise(Float64List magnitude, int n, math.Random random) {
  final re = Float64List(n);
  final im = Float64List(n);
  for (var k = 1; k < n ~/ 2; k++) {
    final phase = random.nextDouble() * 2 * math.pi;
    final m = magnitude[k];
    re[k] = m * math.cos(phase);
    im[k] = m * math.sin(phase);
    // Hermitian symmetry, so the inverse transform is real.
    re[n - k] = re[k];
    im[n - k] = -im[k];
  }
  inverseFft(re, im);
  return re;
}

/// In-place inverse FFT (radix 2), scaled by 1/n. [re] and [im] must have
/// the same power-of-two length.
void inverseFft(Float64List re, Float64List im) {
  final n = re.length;
  // Bit-reversal permutation.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var size = 2; size <= n; size <<= 1) {
    final half = size >> 1;
    final angle = 2 * math.pi / size; // positive: inverse transform
    final wr = math.cos(angle);
    final wi = math.sin(angle);
    for (var start = 0; start < n; start += size) {
      var cr = 1.0;
      var ci = 0.0;
      for (var k = 0; k < half; k++) {
        final a = start + k;
        final b = a + half;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
  final scale = 1 / n;
  for (var i = 0; i < n; i++) {
    re[i] *= scale;
    im[i] *= scale;
  }
}

/// Power response |H(f)|² of the BS.1770 K-weighting filter (the pre-filter
/// shelf and the RLB high-pass) with the standard 48 kHz coefficients.
double kWeightingPower(double hz) {
  final w = 2 * math.pi * hz / NoiseSpec.sampleRate;
  return _biquadPower(
        w,
        1.53512485958697,
        -2.69169618940638,
        1.19839281085285,
        -1.69065929318241,
        0.73248077421585,
      ) *
      _biquadPower(w, 1, -2, 1, -1.99004745483398, 0.99007225036621);
}

double _biquadPower(
  double w,
  double b0,
  double b1,
  double b2,
  double a1,
  double a2,
) {
  final c1 = math.cos(w), s1 = math.sin(w);
  final c2 = math.cos(2 * w), s2 = math.sin(2 * w);
  final nr = b0 + b1 * c1 + b2 * c2, ni = -(b1 * s1 + b2 * s2);
  final dr = 1 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2);
  return (nr * nr + ni * ni) / (dr * dr + di * di);
}

/// A 16-bit stereo PCM WAV of [loop] for SoLoud to decode into memory.
Uint8List encodeWav(NoiseLoop loop) {
  final frames = loop.left.length;
  final data = frames * 4;
  final bytes = ByteData(44 + data);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 2, Endian.little);
  bytes.setUint32(24, NoiseSpec.sampleRate, Endian.little);
  bytes.setUint32(28, NoiseSpec.sampleRate * 4, Endian.little);
  bytes.setUint16(32, 4, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, data, Endian.little);
  final random = math.Random(7);
  var at = 44;
  for (var i = 0; i < frames; i++) {
    for (final v in [loop.left[i], loop.right[i]]) {
      // TPDF dither: the quiet bands of a shaped noise stay clean.
      final dither = random.nextDouble() - random.nextDouble();
      final s = (v * 32767 + dither).round().clamp(-32768, 32767);
      bytes.setInt16(at, s, Endian.little);
      at += 2;
    }
  }
  return bytes.buffer.asUint8List();
}

/// For `compute`: spec in, WAV bytes out.
Uint8List generateNoiseWav(NoiseSpec spec) => encodeWav(generateNoise(spec));
