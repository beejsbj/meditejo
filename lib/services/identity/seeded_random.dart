import 'dart:math' as math;

/// Seeded randomness, ported from the identity exploration's `core.js`
/// (round 2, `docs/fork/design/identity/round2/` on `fork/mark-explore`) so a
/// seed draws the same mark here as on the page.
///
/// Everything is computed in 32-bit unsigned arithmetic, as JavaScript's
/// `Math.imul`, `^` and `>>>` do. **The order of calls is part of the
/// output:** adding, removing or reordering a call changes every mark drawn
/// after it. Pinned marks are stored as frozen geometry for that reason.
abstract final class SeededHash {
  static const _mask = 0xFFFFFFFF;

  static int _imul(int a, int b) => (a * b) & _mask;

  /// `core.js` `hash`: a 32-bit string hash (UTF-16 code units).
  static int of(String str) {
    var h = (1779033703 ^ str.length) & _mask;
    for (var i = 0; i < str.length; i++) {
      h = _imul(h ^ str.codeUnitAt(i), 3432918353);
      h = ((h << 13) | (h >> 19)) & _mask;
    }
    h = _imul(h ^ (h >> 16), 2246822507);
    h = _imul(h ^ (h >> 13), 3266489909);
    return (h ^ (h >> 16)) & _mask;
  }
}

/// `core.js` `makeRng`: mulberry32 seeded by [SeededHash.of].
class SeededRandom {
  SeededRandom(String seed) : _a = SeededHash.of(seed);

  static const _mask = 0xFFFFFFFF;
  int _a;

  /// A number in [0, 1).
  double next() {
    _a = (_a + 0x6d2b79f5) & _mask;
    var t = ((_a ^ (_a >> 15)) * (1 | _a)) & _mask;
    t = ((t + (((t ^ (t >> 7)) * (61 | t)) & _mask)) & _mask) ^ t;
    return ((t ^ (t >> 14)) & _mask) / 4294967296;
  }

  double range(double lo, double hi) => lo + (hi - lo) * next();

  int integer(int lo, int hi) => (lo + (hi - lo + 1) * next()).floor();

  T pick<T>(List<T> items) => items[(next() * items.length).floor()];

  double sign() => next() < 0.5 ? -1 : 1;

  bool chance(double p) => next() < p;

  /// One key of [weights], in its insertion order, as `core.js` walks an
  /// object's keys.
  String weighted(Map<String, double> weights) {
    var sum = 0.0;
    for (final w in weights.values) {
      sum += w;
    }
    var x = next() * sum;
    for (final e in weights.entries) {
      x -= e.value;
      if (x <= 0) return e.key;
    }
    return weights.keys.last;
  }

  /// `core.js` `noise1`: a smooth 1-D noise of [octaves] sines, in [-1, 1].
  double Function(double) noise([int octaves = 3]) {
    final f = <double>[], p = <double>[], a = <double>[];
    var tot = 0.0;
    for (var i = 0; i < octaves; i++) {
      f.add(range(0.8, 1.5) * math.pow(2.13, i));
      p.add(range(0, tau));
      a.add(math.pow(0.5, i).toDouble());
      tot += a[i];
    }
    return (x) {
      var s = 0.0;
      for (var i = 0; i < octaves; i++) {
        s += a[i] * math.sin(f[i] * x + p[i]);
      }
      return s / tot;
    };
  }
}

const tau = math.pi * 2;

double clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

double clampTo(double x, double lo, double hi) => math.max(lo, math.min(hi, x));

double lerp(double a, double b, double t) => a + (b - a) * t;

/// Smoothstep from [a] to [b].
double smooth(double a, double b, double x) {
  final t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

double easeOut(double t) => 1 - math.pow(1 - clamp01(t), 3).toDouble();

double easeInOut(double t) => -(math.cos(math.pi * clamp01(t)) - 1) / 2;

/// Progress of [t] through an animation that starts at [start] and lasts
/// [duration], in [0, 1].
double progress(double t, double start, double duration) =>
    clamp01((t - start) / duration);

/// Seconds per breath: six a minute, a resting pace.
const breathSeconds = 10.0;

/// 0 at full exhale, 1 at full inhale; at rest (0) until [start].
double breathAt(double t, [double start = 0]) =>
    t < start ? 0 : 0.5 - 0.5 * math.cos(tau * (t - start) / breathSeconds);
