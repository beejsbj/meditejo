import 'dart:math' as math;

import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/seeded_random.dart';
import 'package:medito/services/identity/stroke_engine.dart';

/// Builds a [MarkSpec] from a seed: a port of the build half of
/// `marks.js` (identity round 2). A seed here and on the exploration page
/// draws the same mark; `test/services/identity/` holds the references.
///
/// Every round 2 seed is hashed with an `r2:` prefix, as on the page.
abstract final class MarkGenerator {
  static final _seedPattern = RegExp(r'^[gam]-[a-z0-9-]+$');

  /// `marks.js` `normaliseSeed`: lower case, spaces to dashes, and a
  /// gesture prefix on anything without a family.
  static String normaliseSeed(String input) {
    final s = input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    return _seedPattern.hasMatch(s) ? s : 'g-${s.isEmpty ? '0' : s}';
  }

  /// The mark for [seedInput]. [type] forces a kind, as the page's
  /// `build(seed, type)` does (it skips the random pick of a kind, so the
  /// rest of the mark differs from the unforced seed).
  static MarkSpec build(String seedInput, {String? type}) {
    final seed = normaliseSeed(seedInput);
    final r = SeededRandom('r2:$seed');
    return switch (MarkFamily.ofSeed(seed)) {
      MarkFamily.gesture => _gesture(seed, r, type),
      MarkFamily.atmos => _atmos(seed, r, type),
      MarkFamily.minimal => _minimal(seed, r, type),
    };
  }

  // ---------- gesture ----------

  static const gestureWeights = {
    'doorway': 3.0,
    'cushion': 3.0,
    'horizon': 3.0,
    'hearth': 3.0,
    'path': 3.0,
    'shelter': 3.0,
    'window': 2.5,
    'step': 0.6,
    'enso': 1.0,
    'wave': 1.0,
    'loops': 0.6,
  };

  static GestureMark _gesture(String seed, SeededRandom r, String? forced) {
    final type = forced ?? r.weighted(gestureWeights);
    final g = _gestureKinds[type]!(r);
    final pts = jitterPoints(g.pts, r, 0.006);
    final width = r.range(0.036, 0.046) * (g.taper == 'brush' ? 1.35 : 1);
    final nib = r.chance(0.35) ? 0.2 : 0.0;
    final stroke = makeStroke(
      pts,
      r,
      taper: g.taper,
      width: width,
      wobble: 0.003,
      pressure: 0.12,
      nib: nib,
    );
    final (bx, by, radius) = g.blob;
    final blob = makeBlob(r, bx, by, radius, r.range(0.9, 1.4), 0.004);
    var maxd = _hypot(bx - 0.5, by - 0.5) + radius * 1.15;
    for (var i = 0; i < stroke.n; i++) {
      maxd = math.max(
        maxd,
        _hypot(stroke.x[i] - 0.5, stroke.y[i] - 0.5) + stroke.w[i] / 2,
      );
    }
    return GestureMark(
      seed: seed,
      type: type,
      fit: math.min(1, 0.44 / maxd),
      stroke: stroke,
      blob: blob,
      duration: clampTo(1.4 + 0.9 * stroke.length, 2.2, 3.6),
    );
  }

  // Each kind returns a centreline and places its pebble so the two read as
  // a place together: a sun in a doorway, a sitter on a cushion.
  static final Map<String, _Gesture Function(SeededRandom)> _gestureKinds = {
    'doorway': (r) {
      final w = r.range(0.34, 0.42), yb = r.range(0.76, 0.8);
      final yt = yb - r.range(0.5, 0.56);
      final x0 = 0.5 - w / 2 + r.range(-0.02, 0.02), x1 = x0 + w;
      final ys = yt + w / 2;
      final p = Pen(
        x0 - r.range(0.05, 0.09),
        yb + 0.004,
      ).quad(x0 - 0.01, yb, x0, yb - 0.04).line(x0, ys);
      final ry = w / 2 * r.range(1, 1.12);
      p.arc(x0 + w / 2, ys, w / 2, ry, math.pi, tau).line(x1, yb - 0.03);
      final ex = x1 + r.range(0.08, 0.13);
      p.quad(x1 + 0.005, yb, ex, yb - r.range(0, 0.02));
      final bx = x0 + w * r.range(0.45, 0.7), by = ys + r.range(0.0, 0.08);
      return _Gesture(p.pts, (bx, by, r.range(0.15, 0.19)), 'marker');
    },
    // A seat line: the pebble rests on it and presses a soft hollow.
    'cushion': (r) {
      final y0 = r.range(0.66, 0.72), cx = 0.5 + r.range(-0.06, 0.06);
      final radius = r.range(0.17, 0.21), dip = r.range(0.025, 0.04);
      final lift = r.range(0.01, 0.03);
      final out = <Pt>[];
      for (var i = 0; i <= 400; i++) {
        final u = i / 400,
            x = lerp(0.13, 0.87, u),
            k = (x - cx) / (radius * 0.9);
        out.add((
          x,
          y0 + dip * math.exp(-k * k) - lift * math.pow((u - 0.5).abs() * 2, 3),
        ));
      }
      return _Gesture(out, (
        cx,
        y0 + dip * 0.7 - radius * 0.98,
        radius,
      ), 'swell');
    },
    // A horizon with one cursive loop in it: a pause on the way.
    'horizon': (r) {
      final yh = r.range(0.6, 0.66), lx = r.range(0.56, 0.68);
      final a = r.range(0.04, 0.055), b = r.range(0.055, 0.07);
      final h = r.range(0.14, 0.18);
      final p = Pen(
        0.12,
        yh + r.range(-0.01, 0.01),
      ).quad(0.3, yh + 0.008, lx - a, yh);
      for (var i = 1; i <= 140; i++) {
        final t = (i / 140) * tau;
        p.pts.add((
          lx - a + 2 * a * (t / tau) + b * math.sin(t),
          yh - h * (1 - math.cos(t)) / 2,
        ));
      }
      p.quad(lx + a + 0.12, yh + 0.006, 0.88, yh - r.range(0, 0.025));
      final radius = r.range(0.17, 0.22);
      final bx = r.range(0.34, 0.46);
      return _Gesture(p.pts, (
        bx,
        yh - radius * r.range(0.35, 0.7),
        radius,
      ), 'marker');
    },
    'hearth': (r) {
      final bx = r.range(0.24, 0.3), y = r.range(0.74, 0.78);
      final sx = r.range(0.48, 0.54), sway = r.range(0.06, 0.1);
      final top = r.range(0.24, 0.3), cr = r.range(0.04, 0.055);
      final p = Pen(bx, y)
          .line(sx - 0.04, y)
          .quad(sx, y, sx, y - 0.06)
          .cubic(
            sx + sway,
            y - 0.18,
            sx - sway,
            top + 0.16,
            sx + 0.01,
            top + cr * 2,
          );
      final c0x = sx + 0.01 + cr, c0y = top + cr * 2;
      p.arc(c0x, c0y, cr, cr, math.pi, math.pi + tau * 0.85, 70);
      final blobX = sx + r.range(-0.03, 0.03), blobY = r.range(0.52, 0.58);
      return _Gesture(p.pts, (blobX, blobY, r.range(0.19, 0.23)), 'fade');
    },
    'path': (r) {
      final ex = r.range(0.56, 0.66), ey = r.range(0.34, 0.42);
      final lr = r.range(0.035, 0.045);
      final sx = r.range(0.14, 0.2), sy = r.range(0.84, 0.88);
      final c2y = r.range(0.62, 0.68), y1 = r.range(0.56, 0.6);
      final p = Pen(sx, sy)
          .cubic(0.5, 0.86, 0.22, c2y, 0.5, y1)
          .cubic(0.72, 0.52, ex - 0.12, ey + 0.16, ex, ey + lr);
      p.arc(ex, ey, lr, lr, math.pi / 2, math.pi / 2 + tau * 1.05, 70);
      final bx = ex + r.range(-0.04, 0.02), by = ey + r.range(0.02, 0.06);
      return _Gesture(p.pts, (bx, by, r.range(0.15, 0.19)), 'marker');
    },
    'shelter': (r) {
      final ay = r.range(0.22, 0.28), ey = r.range(0.56, 0.62);
      final w = r.range(0.33, 0.38), ax = 0.5 + r.range(-0.02, 0.02);
      final p = Pen(ax - w - 0.03, ey + 0.03)
          .quad(ax - w + 0.01, ey + 0.005, ax - w * 0.55, ey - (ey - ay) * 0.5)
          .quad(ax - 0.03, ay - 0.005, ax, ay)
          .quad(ax + 0.03, ay - 0.005, ax + w * 0.55, ey - (ey - ay) * 0.5)
          .quad(ax + w - 0.01, ey + 0.005, ax + w + 0.04, ey + 0.035);
      final radius = r.range(0.16, 0.2);
      final bx = ax + r.range(-0.04, 0.04);
      return _Gesture(p.pts, (bx, ey + radius * 0.25, radius), 'marker');
    },
    'window': (r) {
      final w = r.range(0.36, 0.42), h = r.range(0.4, 0.46);
      final x0 = 0.5 - w / 2 + r.range(-0.03, 0.01);
      final y0 = 0.5 - h / 2 + r.range(-0.02, 0.02);
      const k = 0.06;
      final p = Pen(x0 + k, y0)
          .line(x0 + w - k, y0)
          .quad(x0 + w, y0, x0 + w, y0 + k)
          .line(x0 + w, y0 + h - k)
          .quad(x0 + w, y0 + h, x0 + w - k, y0 + h)
          .line(x0 + k, y0 + h)
          .quad(x0, y0 + h, x0, y0 + h - k)
          .line(x0, y0 + k)
          .quad(x0, y0, x0 + k, y0);
      p.line(x0 + k + r.range(0.08, 0.16), y0 - 0.004);
      final bx = x0 + w * r.range(0.62, 0.85), by = y0 + h * r.range(0.2, 0.4);
      return _Gesture(p.pts, (bx, by, r.range(0.15, 0.2)), 'marker');
    },
    'step': (r) {
      final y1 = r.range(0.7, 0.74), y2 = y1 - r.range(0.12, 0.16);
      final sx = r.range(0.44, 0.52);
      final p = Pen(0.13, y1)
          .line(sx - 0.05, y1)
          .quad(sx, y1, sx, y1 - 0.05)
          .line(sx, y2 + 0.04)
          .quad(sx, y2, sx + 0.05, y2);
      p.line(0.87, y2 - r.range(0, 0.02));
      final radius = r.range(0.14, 0.18);
      final bx = sx + r.range(0.12, 0.2);
      return _Gesture(p.pts, (bx, y2 - radius * 0.95, radius), 'marker');
    },
    // Round 1's kinds stay in the pool, quietly.
    'loops': (r) {
      final n = r.pick(const [1, 2]);
      final d = r.range(2.3, 3.2), h = r.range(4.4, 5.8);
      final lead = r.range(2.2, 3.4), exit = r.range(2.4, 3.6);
      final lift = r.range(1.2, 3.4);
      final out = <Pt>[];
      final t0 = -lead, t1 = tau * n + exit;
      for (var i = 0; i <= 700; i++) {
        final t = lerp(t0, t1, i / 700);
        final env =
            smooth(t0 + 0.4, 0.4, t) *
            (1 - smooth(tau * n - 0.3, tau * n + 1.4, t));
        out.add((
          t + d * env * math.sin(t),
          -h * env * (1 - math.cos(t)) / 2 -
              lift * math.pow(smooth(tau * n - 0.6, t1, t), 1.6),
        ));
      }
      final radius = r.range(0.25, 0.3);
      final fitted = _fit(out, 0.74, 0.5, r.range(0.54, 0.6));
      return _Gesture(fitted, (
        0.5 + r.range(-0.05, 0.05),
        0.5,
        radius,
      ), 'marker');
    },
    'enso': (r) {
      final th0 = r.range(0, tau), sw = r.range(1.68, 1.9) * math.pi;
      final dir = r.sign();
      final out = <Pt>[];
      for (var i = 0; i <= 500; i++) {
        final u = i / 500, th = th0 + dir * sw * u, rr = 0.29 * (1 - 0.07 * u);
        out.add((0.5 + rr * math.cos(th), 0.5 + rr * math.sin(th)));
      }
      final bx = 0.5 + r.range(-0.05, 0.05), by = 0.5 + r.range(-0.05, 0.05);
      return _Gesture(out, (bx, by, r.range(0.19, 0.23)), 'brush');
    },
    'wave': (r) {
      final cyc = r.range(1, 1.5), amp = r.range(0.06, 0.09);
      final out = <Pt>[];
      for (var i = 0; i <= 500; i++) {
        final u = i / 500;
        final env = math.pow(math.sin(math.pi * (0.06 + 0.88 * u)), 0.6);
        out.add((
          lerp(0.14, 0.86, u),
          0.58 - amp * env * math.sin(tau * cyc * u),
        ));
      }
      final bx = 0.5 + r.range(-0.06, 0.06);
      return _Gesture(out, (bx, 0.5, r.range(0.22, 0.27)), 'swell');
    },
  };

  static List<Pt> _fit(List<Pt> raw, double width, double cx, double cy) {
    var x0 = double.infinity, x1 = -double.infinity;
    var y0 = double.infinity, y1 = -double.infinity;
    for (final (x, y) in raw) {
      x0 = math.min(x0, x);
      x1 = math.max(x1, x);
      y0 = math.min(y0, y);
      y1 = math.max(y1, y);
    }
    final s = width / (x1 - x0);
    return [
      for (final (x, y) in raw)
        (cx + (x - (x0 + x1) / 2) * s, cy + (y - (y0 + y1) / 2) * s),
    ];
  }

  // ---------- minimal ----------

  static const minimalWeights = {
    'split': 1.0,
    'arch': 1.0,
    'pebble': 1.0,
    'crescent': 1.0,
    'vesica': 1.0,
    'cairn': 0.7,
    'window': 1.2,
    'hearth': 1.2,
    'clearing': 1.2,
    'cushion': 1.4,
    'shelter': 1.2,
  };

  static const _roleSets = [
    ['form', 'stroke', 'accent'],
    ['form', 'accent', 'stroke'],
    ['accent', 'stroke', 'form'],
    ['form', 'stroke', 'stroke'],
  ];

  static MinimalMark _minimal(String seed, SeededRandom r, String? forced) {
    final type = forced ?? r.weighted(minimalWeights);
    final rough = r.range(0.5, 0.9);
    MarkBlob b(double x, double y, double radius) =>
        makeBlob(r, x, y, radius, rough, 0.003);
    final roles = r.pick(_roleSets);
    final blobs = <String, MarkBlob>{};
    final v = <String, double>{};
    var stones = <MarkBlob>[];
    var mullion = false;
    switch (type) {
      case 'split':
        final radius = r.range(0.27, 0.31);
        blobs['disc'] = b(0.5, 0.5, radius);
        v['h'] = 0.5 + radius * r.range(0.05, 0.38);
        v['gap'] = r.range(0.024, 0.034);
        v['shift'] = r.range(-0.03, 0.03);
      case 'arch':
        v['w'] = r.range(0.38, 0.46);
        v['ht'] = r.range(0.54, 0.62);
        blobs['sun'] = b(0.5, 0, r.range(0.09, 0.12));
        v['sunY'] = r.range(0, 0.3);
      case 'pebble':
        final peb = blobs['peb'] = b(
          0.5 + r.range(-0.05, 0.05),
          0.5 + r.range(-0.04, 0.04),
          r.range(0.25, 0.3),
        );
        final a = r.range(0, tau), d = r.range(0.25, 0.6);
        blobs['dot'] = b(
          peb.cx + math.cos(a) * peb.r * d,
          peb.cy + math.sin(a) * peb.r * d,
          r.range(0.045, 0.065),
        );
        if (r.chance(0.5)) {
          blobs['second'] = b(
            peb.cx - math.cos(a) * peb.r * 0.85,
            peb.cy - math.sin(a) * peb.r * 0.85,
            r.range(0.09, 0.13),
          );
        }
      case 'crescent':
        blobs['disc'] = b(0.5, 0.5, r.range(0.26, 0.3));
        final a = r.range(-2.6, -0.5) + (r.chance(0.5) ? math.pi : 0);
        v['cutX'] = math.cos(a);
        v['cutY'] = math.sin(a);
        v['cutD'] = r.range(0.13, 0.2);
        v['dot'] = r.chance(0.7) ? r.range(0.035, 0.05) : 0;
      case 'vesica':
        final a = blobs['a'] = b(0, 0.5, r.range(0.2, 0.24));
        blobs['b'] = b(0, 0.5, a.r);
        v['sep'] = r.range(0.17, 0.24);
      case 'cairn':
        var y = 0.8;
        stones = [];
        final radii = [
          r.range(0.2, 0.24),
          r.range(0.14, 0.17),
          r.range(0.08, 0.11),
        ];
        for (final rx in radii) {
          final ry = rx * r.range(0.5, 0.62);
          y -= ry;
          final s = b(0.5 + r.range(-0.03, 0.03), y, 1)
            ..rot = 0
            ..rx = rx
            ..ry = ry;
          y -= ry * 0.92;
          stones.add(s);
        }
        final shift = (1 - (0.8 - y)) / 2 - y;
        for (final s in stones) {
          s.cy += shift;
        }
      case 'window':
        v['w'] = r.range(0.4, 0.48);
        v['h'] = r.range(0.46, 0.54);
        v['rad'] = r.range(0.04, 0.1);
        blobs['sun'] = b(
          0.5 + r.range(-0.08, 0.08),
          0.5 + r.range(-0.12, 0.02),
          r.range(0.1, 0.14),
        );
        mullion = r.chance(0.6);
      case 'hearth':
        blobs['base'] = b(0.5, 0.66, r.range(0.24, 0.28));
        v['flame'] = r.range(0.1, 0.13);
        v['fy'] = r.range(0.44, 0.5);
      case 'clearing':
        blobs['ring'] = b(0.5, 0.5, r.range(0.28, 0.32));
        v['inner'] = r.range(0.55, 0.68);
        blobs['dot'] = b(
          0.5 + r.range(-0.05, 0.05),
          0.5 + r.range(-0.05, 0.05),
          r.range(0.05, 0.075),
        );
      case 'cushion':
        final cushion = blobs['cushion'] = b(0.5, r.range(0.68, 0.72), 1)
          ..rot = 0;
        cushion
          ..rx = r.range(0.24, 0.3)
          ..ry = r.range(0.07, 0.09);
        final sitter = blobs['sitter'] = b(
          0.5 + r.range(-0.02, 0.02),
          0,
          r.range(0.15, 0.19),
        );
        sitter.cy = cushion.cy - cushion.ry! - sitter.r * 0.85;
      case 'shelter':
        v['ay'] = r.range(0.2, 0.26);
        v['ey'] = r.range(0.48, 0.54);
        v['w'] = r.range(0.32, 0.38);
        final sitter = blobs['sitter'] = b(0.5, 0, r.range(0.14, 0.18));
        sitter.cy = v['ey']! + sitter.r * 0.95;
    }
    return MinimalMark(
      seed: seed,
      type: type,
      fit: 1,
      roles: roles,
      blobs: blobs,
      values: v,
      stones: stones,
      mullion: mullion,
    );
  }

  // ---------- atmospheric ----------

  static const atmosKinds = [
    'dawn',
    'ridges',
    'moonpool',
    'doorlight',
    'halo',
    'shoreline',
  ];

  static AtmosMark _atmos(String seed, SeededRandom r, String? forced) {
    final type = forced ?? r.pick<String>(atmosKinds);
    final mis = (r.range(-0.008, 0.008), r.range(0.003, 0.009));
    final sun = makeBlob(
      r,
      0.5 + r.range(-0.1, 0.1),
      r.range(0.3, 0.42),
      r.range(0.13, 0.18),
      0.45,
      0.003,
    );
    final h = r.range(0.58, 0.66);
    final count = r.integer(3, 4);
    final layers = [
      for (var i = 0; i < count; i++)
        RidgeLayer(
          y: lerp(0.52, 0.8, i / 3) + r.range(-0.02, 0.02),
          amp: r.range(0.02, 0.05),
          f: r.range(0.6, 1.4),
          ph: r.range(0, tau),
          f2: r.range(1.8, 2.8),
          ph2: r.range(0, tau),
          period: r.range(26, 40),
        ),
    ];
    final door = (r.range(0.24, 0.3), r.range(0.42, 0.5));
    MarkStroke? ring;
    if (type == 'halo') {
      final raw = <Pt>[];
      final th0 = r.range(0, tau), sw = r.range(1.7, 1.88) * math.pi;
      for (var i = 0; i <= 400; i++) {
        final u = i / 400, th = th0 + sw * u;
        final rr = r.range(0.295, 0.3) * (1 - 0.06 * u);
        raw.add((0.5 + rr * math.cos(th), 0.5 + rr * math.sin(th)));
      }
      ring = makeStroke(
        raw,
        r,
        taper: 'brush',
        width: 0.034,
        wobble: 0.003,
        pressure: 0.12,
      );
      sun
        ..cx = 0.5
        ..cy = 0.5
        ..r = sun.r * 1.15;
    }
    if (type == 'moonpool' || type == 'shoreline') sun.cy = r.range(0.24, 0.3);
    return AtmosMark(
      seed: seed,
      type: type,
      fit: 1,
      misregister: mis,
      sun: sun,
      horizon: h,
      layers: layers,
      door: door,
      ring: ring,
    );
  }
}

class _Gesture {
  const _Gesture(this.pts, this.blob, this.taper);

  final List<Pt> pts;
  final (double, double, double) blob;
  final String taper;
}

double _hypot(double x, double y) => math.sqrt(x * x + y * y);
