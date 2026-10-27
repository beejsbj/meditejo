import 'dart:math' as math;
import 'dart:typed_data';

import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/seeded_random.dart';

/// The stroke engine and pebbles of `core.js`, ported call for call (see
/// [SeededRandom] on why the order matters).
typedef Pt = (double, double);

/// A polyline builder for centrelines: lines, arcs and curves, densely
/// sampled (`core.js` `pen`).
class Pen {
  Pen(double x, double y) : pts = [(x, y)];

  final List<Pt> pts;

  Pt get _last => pts.last;

  Pen line(double x2, double y2, [int n = 40]) {
    final (x1, y1) = _last;
    for (var i = 1; i <= n; i++) {
      pts.add((lerp(x1, x2, i / n), lerp(y1, y2, i / n)));
    }
    return this;
  }

  Pen quad(double cx, double cy, double x2, double y2, [int n = 60]) {
    final (x1, y1) = _last;
    for (var i = 1; i <= n; i++) {
      final t = i / n, u = 1 - t;
      pts.add((
        u * u * x1 + 2 * u * t * cx + t * t * x2,
        u * u * y1 + 2 * u * t * cy + t * t * y2,
      ));
    }
    return this;
  }

  Pen cubic(
    double c1x,
    double c1y,
    double c2x,
    double c2y,
    double x2,
    double y2, [
    int n = 80,
  ]) {
    final (x1, y1) = _last;
    for (var i = 1; i <= n; i++) {
      final t = i / n, u = 1 - t;
      pts.add((
        u * u * u * x1 +
            3 * u * u * t * c1x +
            3 * u * t * t * c2x +
            t * t * t * x2,
        u * u * u * y1 +
            3 * u * u * t * c1y +
            3 * u * t * t * c2y +
            t * t * t * y2,
      ));
    }
    return this;
  }

  Pen arc(
    double cx,
    double cy,
    double rx,
    double ry,
    double a0,
    double a1, [
    int n = 90,
  ]) {
    for (var i = 1; i <= n; i++) {
      final a = lerp(a0, a1, i / n);
      pts.add((cx + rx * math.cos(a), cy + ry * math.sin(a)));
    }
    return this;
  }
}

double _hypot(double x, double y) => math.sqrt(x * x + y * y);

({List<Pt> pts, double len}) _resample(List<Pt> raw, int n) {
  final m = raw.length, cum = Float64List(m);
  for (var i = 1; i < m; i++) {
    cum[i] =
        cum[i - 1] +
        _hypot(raw[i].$1 - raw[i - 1].$1, raw[i].$2 - raw[i - 1].$2);
  }
  final total = cum[m - 1];
  final out = <Pt>[];
  var j = 0;
  for (var i = 0; i < n; i++) {
    final d = total * i / (n - 1);
    while (j < m - 2 && cum[j + 1] < d) {
      j++;
    }
    var seg = cum[j + 1] - cum[j];
    if (seg == 0) seg = 1;
    final u = clamp01((d - cum[j]) / seg);
    out.add((
      lerp(raw[j].$1, raw[j + 1].$1, u),
      lerp(raw[j].$2, raw[j + 1].$2, u),
    ));
  }
  return (pts: out, len: total);
}

(Float64List, Float64List) _normals(List<Pt> pts, [int span = 1]) {
  final n = pts.length, nx = Float64List(n), ny = Float64List(n);
  for (var i = 0; i < n; i++) {
    final a = pts[math.max(i - span, 0)], b = pts[math.min(i + span, n - 1)];
    final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
    var l = _hypot(dx, dy);
    if (l == 0) l = 1;
    nx[i] = -dy / l;
    ny[i] = dx / l;
  }
  return (nx, ny);
}

/// A stroke's width along its length, by kind of pen.
double _profile(String kind, double s) => switch (kind) {
  'brush' =>
    (0.66 + 0.34 * smooth(0, 0.05, s)) *
            (1 - 0.8 * math.pow(smooth(0.4, 1, s), 1.25)) +
        0.05,
  'grow' => (0.42 + 0.58 * smooth(0, 0.5, s)) * (1 - 0.45 * smooth(0.86, 1, s)),
  'swell' =>
    0.5 +
        0.5 *
            math
                .pow(math.sin(math.pi * clamp01(s * 1.04 - 0.02)), 0.7)
                .toDouble(),
  'fade' => (0.8 + 0.2 * smooth(0, 0.06, s)) * (1 - 0.7 * smooth(0.6, 1, s)),
  _ => (0.74 + 0.26 * smooth(0, 0.05, s)) * (1 - 0.36 * smooth(0.88, 1, s)),
};

/// A centreline becomes a hand-drawn ribbon: even spacing, slow wobble,
/// pressure, optional nib, and a pen clock that slows in tight curves.
MarkStroke makeStroke(
  List<Pt> raw,
  SeededRandom rng, {
  required String taper,
  required double width,
  required double wobble,
  required double pressure,
  double nib = 0,
  int samples = 420,
}) {
  final n = samples;
  var pts = _resample(raw, n).pts;
  var (nx, ny) = _normals(pts, 2);
  final wob = rng.noise(3), wf = rng.range(3, 6);
  pts = [
    for (var i = 0; i < n; i++)
      (
        pts[i].$1 + nx[i] * wobble * wob((i / (n - 1)) * wf),
        pts[i].$2 + ny[i] * wobble * wob((i / (n - 1)) * wf),
      ),
  ];
  final r = _resample(pts, n);
  pts = r.pts;
  (nx, ny) = _normals(pts, 2);
  final pn = rng.noise(2), pf = rng.range(4, 8), nibA = rng.range(0, math.pi);
  final x = Float64List(n), y = Float64List(n);
  final w = Float64List(n), cost = Float64List(n);
  final ds = r.len / (n - 1);
  var prev = 0.0;
  for (var i = 0; i < n; i++) {
    final s = i / (n - 1);
    x[i] = pts[i].$1;
    y[i] = pts[i].$2;
    final ang = math.atan2(-nx[i], ny[i]);
    var ww = width * _profile(taper, s) * (1 + pressure * pn(s * pf));
    if (nib != 0) {
      ww *= 1 - nib + nib * (0.3 + 0.7 * math.sin(ang - nibA).abs());
    }
    w[i] = ww;
    if (i > 0) {
      var da = (ang - prev).abs();
      if (da > math.pi) da = tau - da;
      cost[i] = cost[i - 1] + ds + 0.014 * da;
    }
    prev = ang;
  }
  for (var i = 0; i < n; i++) {
    cost[i] /= cost[n - 1];
  }
  return MarkStroke(
    x: x,
    y: y,
    nx: nx,
    ny: ny,
    w: w,
    cost: cost,
    length: r.len,
  );
}

List<Pt> jitterPoints(List<Pt> pts, SeededRandom rng, double amount) {
  final nz = rng.noise(2), nz2 = rng.noise(2);
  return [
    for (var i = 0; i < pts.length; i++)
      (pts[i].$1 + amount * nz(i * 0.05), pts[i].$2 + amount * nz2(i * 0.05)),
  ];
}

/// A pebble at ([cx], [cy]) of radius [r]; [rough] scales its harmonics.
MarkBlob makeBlob(
  SeededRandom rng,
  double cx,
  double cy,
  double r, [
  double rough = 1,
  double cut = 0,
]) {
  final rot = rng.range(0, tau), asp = rng.range(0.9, 1.08);
  final a = [
    rng.range(0.03, 0.08) * rough,
    rng.range(0.015, 0.045) * rough,
    rng.range(0, 0.018) * rough,
  ];
  final p = [rng.range(0, tau), rng.range(0, tau), rng.range(0, tau)];
  final cp = [rng.range(0, tau), rng.range(0, tau)];
  final ck = [rng.integer(7, 10), rng.integer(12, 17)];
  return MarkBlob(
    cx: cx,
    cy: cy,
    r: r,
    rot: rot,
    asp: asp,
    a: a,
    p: p,
    cut: cut,
    cp: cp,
    ck: ck,
  );
}
