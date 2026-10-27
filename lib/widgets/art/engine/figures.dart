// The page's names (S, BR, H, R) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 4's figures (`prims.js`): the strong primitives from round 3, three
/// new ones (flock, petals, grass) and the constellation redone as a scatter
/// of stars whose placement and brightness imply a shape.
///
/// Every figure moves gracefully: slow, eased, breath-paced where it fits
/// (BREATH = 10 s), looping without a seam (sines, or phases that wrap while
/// faded out). `still` is a calm frame for lists and reduced motion.
final Map<String, Figure> roundFourFigures = {
  'breath': const BreathFigure(),
  'fire': const FireFigure(),
  'rings': const RingsFigure(),
  'mandala': const MandalaFigure(),
  'streaks': const StreaksFigure(),
  'waves': const WavesFigure(),
  'scales': const ScalesFigure(),
  'stars': const StarsFigure(),
  'lotus': const LotusFigure(),
  'ammonite': const AmmoniteFigure(),
  'cairn': const CairnFigure(),
  'threads': const ThreadsFigure(),
  'grass': const GrassFigure(),
  'flock': const FlockFigure(),
  'petals': const PetalsFigure(),
  'moon': const MoonFigure(),
  'disc': const DiscFigure(),
};

// ---------- helpers ----------

double _num(Map<String, Object?> m, String key) => (m[key]! as num).toDouble();

/// A ring wobbled by [nz]: `wobRing`.
void _wobRing(
  Ctx ctx,
  double cx,
  double cy,
  double r,
  double ry,
  double Function(double) nz,
  double amt,
) {
  ctx.beginPath();
  final M = math.max(24, (r * 220).ceil());
  for (var i = 0; i <= M; i++) {
    final a = tau * i / M, rr = r * (1 + amt * nz(a * 1.3 + r * 9));
    final x = cx + rr * math.cos(a), y = cy + rr * ry * math.sin(a);
    if (i != 0) {
      ctx.lineTo(x, y);
    } else {
      ctx.moveTo(x, y);
    }
  }
}

/// A soft disc of light, fading out at the rim: `soft` (unlike [glow], with
/// no mid stop).
void _soft(Ctx ctx, double x, double y, double r, Rgb col, double a) {
  final g = ctx.createRadialGradient(x, y, 0, x, y, r)
    ..addColorStop(0, css(col, a))
    ..addColorStop(1, css(col, 0));
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, tau);
  ctx.fill();
}

/// A petal from (x, y) of length [len] and width [wid] towards [ang].
void _petal(
  Ctx ctx,
  double x,
  double y,
  double len,
  double wid,
  double ang, [
  double bend = 0,
]) {
  final c = math.cos(ang), s = math.sin(ang);
  (double, double) pt(double u, double v) =>
      (x + u * c - v * s, y + u * s + v * c);
  final (ax, ay) = pt(len, bend * len);
  final (l1x, l1y) = pt(len * 0.35, wid);
  final (l2x, l2y) = pt(len * 0.8, wid * 0.6 + bend * len * 0.5);
  final (r1x, r1y) = pt(len * 0.35, -wid);
  final (r2x, r2y) = pt(len * 0.8, -wid * 0.6 + bend * len * 0.5);
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.bezierCurveTo(l1x, l1y, l2x, l2y, ax, ay);
  ctx.bezierCurveTo(r2x, r2y, r1x, r1y, x, y);
  ctx.closePath();
}

/// Noise functions are rebuilt from a stored seed, so params stay plain
/// data; cached per params map.
final Expando<double Function(double)> _nzCache = Expando('nz');

double Function(double) _nzOf(P p) =>
    _nzCache[p.m] ??= rngOf(p['nzSeed']!).noise(2);

// ---------- figures ----------

/// breath: swells and settles every 10 s, the halo a beat behind.
class BreathFigure extends Figure {
  const BreathFigure();

  @override
  String get label => 'breath';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'kind': r.pick(const ['orb', 'orb', 'lobes']),
    'n': r.integer(3, 5),
    'nzSeed': r.next(),
    'blob': makeBlob(
      r,
      _num(pl, 'cx'),
      _num(pl, 'cy'),
      _num(pl, 's') * 0.55,
      0.7,
      0.003,
    ),
    'tilt': r.range(0.3, 0.55),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still);
    if (p.s('kind') == 'orb') {
      final n = p.i('n');
      for (var i = n - 1; i >= 1; i--) {
        final bi = BR(t - i * 0.8, still),
            rr = s * (0.5 + 0.5 * (i + 1) / n) * (0.86 + 0.14 * bi);
        _wobRing(ctx, cx, cy, rr, 1, _nzOf(p), 0.012);
        strokeWith(
          ctx,
          k.main,
          0.006 + 0.004 * (n - i) / n,
          0.2 + 0.5 * (1 - i / n),
        );
      }
      blobPath(ctx, p.sub('blob'), imperf: 1 - b, grow: 0.88 + 0.12 * b);
      fillWith(ctx, k.main);
    } else {
      final g = 0.88 + 0.14 * b;
      for (final sd in const [-1.0, 1.0]) {
        _petal(
          ctx,
          cx + sd * s * 0.06,
          cy - s * 0.55,
          s * 1.25 * g,
          s * 0.42 * g,
          math.pi / 2 + sd * p.d('tilt'),
          -sd * 0.12,
        );
        fillWith(ctx, k.main);
      }
      ctx.beginPath();
      ctx.moveTo(cx, cy - s * 0.95);
      ctx.lineTo(cx, cy - s * 0.45);
      strokeWith(ctx, k.line, 0.012);
    }
  }
}

/// Tongues sway on slow, unrelated clocks (3–6 s), so the fire never
/// flickers; embers rise and fade in and out.
class FireFigure extends Figure {
  const FireFigure();

  @override
  String get label => 'fire';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final kind = r.pick(const ['tongues', 'tongues', 'embers']);
    final nT = r.integer(3, 5);
    final tongues = [
      for (var i = 0; i < nT; i++)
        {
          'x': r.range(-0.45, 0.45),
          'h': r.range(0.9, 1.5),
          'w': r.range(0.28, 0.4),
          'ph': r.range(0, tau),
          'per': r.range(3.2, 5.8),
        },
    ];
    final nE = r.integer(10, 18);
    final embers = [
      for (var i = 0; i < nE; i++)
        {
          'x': r.range(-0.6, 0.6),
          'y': r.next(),
          'v': r.range(0.06, 0.11),
          'ph': r.range(0, tau),
          'z': r.range(0.006, 0.012),
        },
    ];
    final log = r.chance(0.6);
    final nC = r.integer(5, 8);
    final coals = [
      for (var i = 0; i < nC; i++)
        {
          'dx': r.range(-0.75, 0.75),
          'dy': r.range(-0.12, 0.08),
          'w': r.range(0.18, 0.32),
          'h': r.range(0.09, 0.15),
          'rot': r.range(-0.3, 0.3),
          'ph': r.range(0, tau),
          'per': r.range(4, 8),
        },
    ];
    return {
      ...pl,
      'kind': kind,
      'tongues': tongues,
      'embers': embers,
      'log': log,
      'coals': coals,
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final kind = p.s('kind');
    final base = cy + s * 0.7;
    _soft(
      ctx,
      cx,
      base - s * 0.2,
      s * 1.7,
      k.glow,
      0.32 + (still ? 0 : 0.06 * S(t, 6.1)),
    );
    if (kind == 'tongues') {
      for (final g in p.list('tongues')) {
        final per = g.d('per'), ph = g.d('ph');
        final h = s * g.d('h') * (0.9 + (still ? 0 : 0.1 * S(t, per, ph))),
            sw = still ? 0.0 : 0.06 * s * S(t, per * 1.3, ph + 1),
            x = cx + g.d('x') * s,
            w = g.d('w') * s;
        for (final (col, f) in [(k.main, 1.0), (k.alt, 0.62), (k.glow, 0.3)]) {
          ctx.beginPath();
          ctx.moveTo(x - w * f, base);
          ctx.bezierCurveTo(
            x - w * f,
            base - h * f * 0.5,
            x + sw - w * f * 0.3,
            base - h * f * 0.85,
            x + sw * 1.4,
            base - h * f,
          );
          ctx.bezierCurveTo(
            x + sw + w * f * 0.3,
            base - h * f * 0.85,
            x + w * f,
            base - h * f * 0.5,
            x + w * f,
            base,
          );
          ctx.closePath();
          fillWith(ctx, col, 0.85);
        }
      }
    } else {
      // A bed of coals: each glows from within on its own slow clock.
      _soft(
        ctx,
        cx,
        base - s * 0.1,
        s * 1.1,
        k.alt,
        0.35 + (still ? 0 : 0.1 * S(t, 7.3)),
      );
      for (final q in p.list('coals')) {
        final x = cx + q.d('dx') * s,
            y = base + q.d('dy') * s,
            g = still ? 0.6 : 0.5 + 0.5 * S(t, q.d('per'), q.d('ph'));
        final w = q.d('w'), h = q.d('h'), rot = q.d('rot');
        ctx.beginPath();
        ctx.ellipse(x, y, w * s, h * s, rot, 0, tau);
        fillWith(ctx, k.line);
        ctx.beginPath();
        ctx.ellipse(
          x,
          y - h * s * 0.15,
          w * s * 0.7,
          h * s * 0.45,
          rot,
          0,
          tau,
        );
        fillWith(ctx, k.alt, 0.35 + 0.5 * g);
        ctx.beginPath();
        ctx.ellipse(x, y - h * s * 0.2, w * s * 0.35, h * s * 0.2, rot, 0, tau);
        fillWith(ctx, k.glow, 0.3 + 0.6 * g);
      }
    }
    if (p.b('log') && kind == 'tongues') {
      cutPoly(
        ctx,
        [
          (cx - s * 0.8, base - 0.012),
          (cx + s * 0.8, base - 0.018),
          (cx + s * 0.82, base + 0.02),
          (cx - s * 0.78, base + 0.024),
        ],
        SeededRandom('log'),
        0.003,
      );
      fillWith(ctx, k.line);
    }
    for (final e in p.list('embers')) {
      final ey = e.d('y');
      final u = still ? ey : jsMod(ey + t * e.d('v'), 1),
          x = cx + e.d('x') * s * (1 + u * 0.4) + 0.015 * S(t, 5, e.d('ph')),
          y = base - u * s * 2.6;
      circle(
        ctx,
        x,
        y,
        e.d('z') * (1 - u * 0.5) * (kind == 'embers' ? 1.3 : 1),
      );
      fillWith(ctx, k.glow, fade(u) * 0.95);
    }
  }
}

/// Ripples open and fade (each ring fades in from nothing and out to
/// nothing, so the loop is seamless); a target breathes; two sources
/// interfere, their rings drifting outwards and fading at the edges.
class RingsFigure extends Figure {
  const RingsFigure();

  @override
  String get label => 'rings';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'kind': r.pick(const ['ripple', 'target', 'interference']),
    'n': r.integer(4, 8),
    'sq': r.chance(0.4) ? r.range(0.3, 0.5) : 1.0,
    'nzSeed': r.next(),
    'd': r.range(0.16, 0.3),
    'ang': r.range(0, tau),
    'w': r.range(0.005, 0.009),
    'per': r.range(10, 14),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final n = p.i('n'), sq = p.d('sq'), w = p.d('w'), per = p.d('per');
    final R = s * 1.15, nz = _nzOf(p);
    final kind = p.s('kind');
    if (kind == 'ripple') {
      for (var i = 0; i < n; i++) {
        final u = still ? (i + 0.5) / n : jsMod(t / per + i / n, 1);
        _wobRing(ctx, cx, cy, 0.015 + R * u, sq, nz, 0.012);
        strokeWith(ctx, k.main, w * (1.4 - u), fade(u) * 0.9);
      }
      circle(ctx, cx, cy, 0.012);
      fillWith(ctx, k.main);
    } else if (kind == 'target') {
      for (var i = n; i >= 1; i--) {
        _wobRing(
          ctx,
          cx,
          cy,
          R * i / n * (0.95 + 0.05 * BR(t - i * 0.3, still)),
          sq,
          nz,
          0.01,
        );
        if (i.isOdd) fillWith(ctx, i == 1 ? k.alt : k.main, i == 1 ? 1 : 0.16);
        strokeWith(ctx, k.main, w, 0.85);
      }
    } else {
      final ang = p.d('ang'), d = p.d('d');
      final ox = math.cos(ang) * d / 2,
          oy = math.sin(ang) * d / 2,
          nn = n * 2 + 4;
      final sources = [(cx - ox, cy - oy, k.main), (cx + ox, cy + oy, k.alt)];
      for (var j = 0; j < sources.length; j++) {
        final (x, y, cc) = sources[j];
        for (var i = 0; i < nn; i++) {
          final u = still
              ? (i + 0.5) / nn
              : jsMod((i + t / per * (j != 0 ? 1.13 : 1)) / nn, 1);
          _wobRing(ctx, x, y, 0.01 + R * u, sq, nz, 0.005);
          strokeWith(ctx, cc, w * 0.6, fade(u) * 0.8);
        }
      }
    }
  }
}

/// mandala: tiers turn slowly against each other and breathe.
class MandalaFigure extends Figure {
  const MandalaFigure();

  @override
  String get label => 'mandala';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final n = r.pick(const [4, 5, 6, 8, 8, 10, 12]);
    final nT = r.integer(2, 3);
    final tiers = [
      for (var i = 0; i < nT; i++)
        {
          'el': r.pick(const ['petal', 'petal', 'dot', 'arc', 'leaf']),
          'rr': lerp(0.35, 1, (i + 1) / 3) * r.range(0.85, 1.05),
          'sz': r.range(0.18, 0.32),
          'off': r.chance(0.5) ? 0.5 : 0.0,
          'dir': r.sign(),
        },
    ];
    return {
      ...pl,
      'n': n,
      'tiers': tiers,
      'core': r.range(0.08, 0.16),
      'ring': r.chance(0.6),
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), n = p.i('n');
    final rot = still ? 0.0 : t / 240 * tau, b = BR(t, still);
    final S2 = s * (0.96 + 0.04 * b);
    if (p.b('ring')) {
      circle(ctx, cx, cy, S2 * 1.08);
      strokeWith(ctx, k.line, 0.004, 0.5);
    }
    final tiers = p.list('tiers').reversed.toList();
    for (var ti = 0; ti < tiers.length; ti++) {
      final T = tiers[ti];
      final el = T.s('el'), off = T.d('off'), dir = T.d('dir');
      for (var i = 0; i < n; i++) {
        final a = (i + off) / n * tau + rot * dir - math.pi / 2,
            r0 = S2 * T.d('rr'),
            col = ti.isOdd ? k.alt : k.main;
        if (el == 'petal' || el == 'leaf') {
          _petal(
            ctx,
            cx + math.cos(a) * r0 * 0.35,
            cy + math.sin(a) * r0 * 0.35,
            r0 * 0.65 * (0.95 + 0.05 * b),
            S2 * T.d('sz') * (el == 'leaf' ? 0.25 : 0.4) * (6 / n + 0.4),
            a,
          );
          fillWith(ctx, col, 0.92);
        } else if (el == 'dot') {
          circle(
            ctx,
            cx + math.cos(a) * r0,
            cy + math.sin(a) * r0,
            S2 * T.d('sz') * 0.22,
          );
          fillWith(ctx, col);
        } else {
          ctx.beginPath();
          ctx.arc(
            cx + math.cos(a) * r0 * 0.7,
            cy + math.sin(a) * r0 * 0.7,
            r0 * 0.3,
            a - 1.2,
            a + 1.2,
          );
          strokeWith(ctx, col, 0.007);
        }
      }
    }
    circle(ctx, cx, cy, S2 * p.d('core') * (0.9 + 0.2 * b));
    fillWith(ctx, k.alt);
  }
}

/// Rain as a figure: streaks inside a soft window, each fading in at the top
/// and out at the bottom.
class StreaksFigure extends Figure {
  const StreaksFigure();

  @override
  String get label => 'streaks';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final slant = r.range(-0.22, 0.04);
    final n = r.integer(20, 32);
    return {
      ...pl,
      'slant': slant,
      'drops': [
        for (var i = 0; i < n; i++)
          {
            'x': r.next(),
            'y': r.next(),
            'l': r.range(0.05, 0.11),
            'v': r.range(0.07, 0.12),
            'a': r.range(0.45, 1),
          },
      ],
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), slant = p.d('slant');
    final s2 = p.d('s') * 1.15;
    for (final d in p.list('drops')) {
      final dy = d.d('y');
      final u = still ? dy : jsMod(dy + t * d.d('v'), 1),
          y = cy - s2 + u * s2 * 2,
          x = cx - s2 + d.d('x') * s2 * 2 + (u - 0.5) * s2 * 2 * slant;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + d.d('l') * slant, y + d.d('l'));
      strokeWith(ctx, k.main, 0.008, d.d('a') * fade(u));
    }
  }
}

/// waves: rows travel at their own speeds.
class WavesFigure extends Figure {
  const WavesFigure();

  @override
  String get label => 'waves';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'rows': r.integer(5, 9),
    'amp': r.range(0.01, 0.024),
    'f': r.range(2, 4.5),
    'dash': r.chance(0.35),
    'v': r.range(0.08, 0.14),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final rows = p.i('rows'), amp = p.d('amp'), f = p.d('f'), v = p.d('v');
    for (var i = 0; i < rows; i++) {
      final y = lerp(cy - s * 0.7, cy + s * 0.7, i / (rows - 1)),
          ph = (still ? 0 : tau * t * v * (1 + i * 0.07)) + i * 0.9,
          half = s * (1 - (i / (rows - 1) - 0.5).abs() * 0.6);
      ctx.beginPath();
      var first = true;
      for (var x = cx - half; x <= cx + half; x += 0.012) {
        final y2 = y + amp * math.sin(tau * f * x + ph);
        if (first) {
          ctx.moveTo(x, y2);
          first = false;
        } else {
          ctx.lineTo(x, y2);
        }
      }
      if (p.b('dash')) ctx.setLineDash(const [0.05, 0.03]);
      strokeWith(ctx, i.isOdd ? k.line : k.main, 0.007, 0.9);
      ctx.setLineDash(const []);
    }
  }
}

/// The page's `cached()` raster for scales: the pattern painted once at the
/// card's pixel size, with a tenth of a unit around the unit square.
class _ScalesCache {
  _ScalesCache(this.key, this.image);
  final String key;
  final ui.Image image;
}

final Expando<_ScalesCache> _scalesCache = Expando('scales');

/// scales: drifts slowly sideways and back. Painted into a raster cache and
/// `drawImage`d, as the page does: the image lands on a fractional pixel, so
/// the resampling softens the lines, as it does on the page.
class ScalesFigure extends Figure {
  const ScalesFigure();

  @override
  String get label => 'scales';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'R': r.range(0.05, 0.07), 'rings': r.integer(3, 4)};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final R = p.d('R'), rings = p.i('rings');
    void paint(Ctx g) {
      var row = 0;
      for (var y = -0.1 - R; y < 1.1 + R * 2; row++, y += R * 0.5) {
        for (var x = (row % 2) * R - R - 0.1; x < 1.1 + R; x += R * 2) {
          g.beginPath();
          g.arc(x, y, R, math.pi, tau);
          g.lineTo(x + R, y + R);
          g.lineTo(x - R, y + R);
          g.closePath();
          fillWith(g, k.paper);
          for (var i = 0; i < rings; i++) {
            g.beginPath();
            g.arc(x, y, R * (1 - i / rings), math.pi, tau);
            strokeWith(g, i != 0 ? k.line : k.main, 0.005, 0.9);
          }
        }
      }
    }

    final px = math.max(1, (ctx.canvas.getTransform()[0] + 0.5).floor());
    final key = '$px|${k.paper.hex}|${k.main.hex}|${k.line.hex}';
    var cache = _scalesCache[p.m];
    if (cache == null || cache.key != key) {
      cache?.image.dispose();
      final side = (px * 1.2 + 0.5).floor();
      final rec = ui.PictureRecorder();
      final g = Ctx(ui.Canvas(rec));
      g.translate(0.1 * px, 0.1 * px);
      g.scale(px.toDouble(), px.toDouble());
      paint(g);
      final pic = rec.endRecording();
      cache = _scalesCache[p.m] = _ScalesCache(
        key,
        pic.toImageSync(side, side),
      );
    }
    ctx.save();
    circle(ctx, p.d('cx'), p.d('cy'), p.d('s'));
    ctx.clip();
    ctx.drawImage(
      cache.image,
      -0.1 + (still ? 0 : 0.04 * S(t, 20)),
      -0.1,
      1.2,
      1.2,
    );
    ctx.restore();
  }
}

/// Stars placed to imply a shape: the shape is never drawn, only suggested
/// by where the bright stars sit; faint companions fill the space around.
final Map<String, List<(double, double, double)>> _asterisms = {
  'dipper': const [
    (-1, -0.25, 1),
    (-0.62, -0.3, 0.8),
    (-0.28, -0.12, 0.85),
    (0.02, 0, 0.7),
    (0.1, 0.38, 0.9),
    (0.62, 0.42, 1),
    (0.66, 0.02, 0.85),
  ],
  'cassiopeia': const [
    (-1, -0.3, 0.9),
    (-0.5, 0.32, 1),
    (0, -0.06, 0.8),
    (0.5, 0.36, 1),
    (1, -0.22, 0.85),
  ],
  'cross': const [
    (0, -1, 1),
    (0, 0.9, 1),
    (-0.62, -0.02, 0.85),
    (0.58, 0.12, 0.8),
    (0.28, 0.42, 0.55),
  ],
  'swan': const [
    (0, -1, 1),
    (0, -0.32, 0.9),
    (0.02, 0.3, 0.75),
    (0.04, 0.95, 0.85),
    (-0.86, -0.18, 0.8),
    (-0.42, -0.28, 0.65),
    (0.46, -0.3, 0.65),
    (0.9, -0.12, 0.8),
  ],
  'lotus': [
    for (var i = 0; i < 9; i++)
      () {
        final u = i / 8 - 0.5,
            a = -math.pi / 2 + u * 2.2,
            rr = 0.9 - u.abs() * 0.6;
        return (math.cos(a) * rr, 0.55 + math.sin(a) * rr, 1 - u.abs());
      }(),
  ],
  'ring': [
    for (var i = 0; i < 12; i++)
      (math.cos(i / 12 * tau), math.sin(i / 12 * tau), i % 3 != 0 ? 0.6 : 1.0),
  ],
};

/// stars: each star brightens and dims on its own slow clock.
class StarsFigure extends Figure {
  const StarsFigure();

  @override
  String get label => 'star shape';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final cx = _num(pl, 'cx'), cy = _num(pl, 'cy'), s = _num(pl, 's');
    final accent = slot == 'accent';
    final shape = r.pick(
      accent ? const ['ring', 'cassiopeia', 'cross'] : _asterisms.keys.toList(),
    );
    final rot = r.range(-0.35, 0.35), sc = s * r.range(0.85, 1.05);
    final main = [
      for (final (x, y, b) in _asterisms[shape]!)
        () {
          final c = math.cos(rot), sn = math.sin(rot);
          final jx = r.range(-0.05, 0.05), jy = r.range(-0.05, 0.05);
          return {
            'x': cx + ((x + jx) * c - (y + jy) * sn) * sc,
            'y': cy + ((x + jx) * sn + (y + jy) * c) * sc,
            'z': (0.007 + 0.009 * b) * (accent ? 0.7 : 1),
            'per': r.range(7, 13),
            'ph': r.range(0, tau),
            'b': b,
          };
        }(),
    ];
    final faint = <Map<String, Object?>>[];
    if (!accent) {
      final n = r.integer(10, 18);
      for (var i = 0; i < n; i++) {
        faint.add({
          'x': cx + r.range(-1.3, 1.3) * s,
          'y': cy + r.range(-1.3, 1.3) * s,
          'z': r.range(0.0015, 0.003),
          'per': r.range(6, 12),
          'ph': r.range(0, tau),
          'b': 0.3,
        });
      }
    }
    return {...pl, 'shape': shape, 'main': main, 'faint': faint};
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    for (final q in p.list('faint')) {
      circle(ctx, q.d('x'), q.d('y'), q.d('z'));
      fillWith(
        ctx,
        k.line,
        still ? 0.5 : 0.35 + 0.3 * S(t, q.d('per'), q.d('ph')),
      );
    }
    for (final q in p.list('main')) {
      final x = q.d('x'), y = q.d('y'), z = q.d('z'), b = q.d('b');
      final tw = still ? 0.8 : 0.72 + 0.28 * S(t, q.d('per'), q.d('ph'));
      _soft(ctx, x, y, z * 4.5, k.glow, 0.35 * tw * b);
      circle(ctx, x, y, z * (0.85 + 0.15 * tw));
      fillWith(ctx, k.main, 0.6 + 0.4 * tw);
      if (b > 0.85) {
        ctx.beginPath();
        ctx.moveTo(x - z * 2.6 * tw, y);
        ctx.lineTo(x + z * 2.6 * tw, y);
        ctx.moveTo(x, y - z * 2.6 * tw);
        ctx.lineTo(x, y + z * 2.6 * tw);
        strokeWith(ctx, k.main, 0.0025, 0.6 * tw);
      }
    }
  }
}

/// lotus: opens on the inhale, closes on the exhale.
class LotusFigure extends Figure {
  const LotusFigure();

  @override
  String get label => 'lotus';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'n': r.pick(const [5, 7, 9]),
    'tiers': r.integer(1, 2),
    'spread': r.range(0.9, 1.35),
    'water': r.chance(0.5),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), base = cy + s * 0.55;
    if (p.b('water')) {
      ctx.beginPath();
      ctx.ellipse(
        cx,
        base + 0.01,
        s * 1.2 * (0.97 + 0.03 * b),
        s * 0.14,
        0,
        0,
        tau,
      );
      fillWith(ctx, k.alt, 0.35);
    }
    for (var tr = p.i('tiers') - 1; tr >= 0; tr--) {
      final n = p.i('n') - tr * 2,
          sp = p.d('spread') * (0.82 + 0.18 * b) * (1 + tr * 0.25);
      for (var i = 0; i < n; i++) {
        final u = n == 1 ? 0.0 : i / (n - 1) - 0.5, a = -math.pi / 2 + u * sp;
        _petal(
          ctx,
          cx,
          base,
          s * (1.15 - u.abs() * 0.5) * (1 - tr * 0.18),
          s * 0.2,
          a,
        );
        fillWith(ctx, tr != 0 ? k.alt : k.main, 0.92);
        strokeWith(ctx, k.paper, 0.004, 0.6);
      }
    }
  }
}

/// ammonite: turns once every five minutes.
class AmmoniteFigure extends Figure {
  const AmmoniteFigure();

  @override
  String get label => 'ammonite';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'turns': r.range(2.2, 3.2),
    'k': r.range(0.16, 0.22),
    'septa': r.integer(14, 24),
    'dir': r.sign(),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final dir = p.d('dir'), pk = p.d('k'), septa = p.i('septa');
    final rot = (still ? 0 : t / 300 * tau) * dir, th1 = p.d('turns') * tau;
    double R(double th) => s * math.exp(pk * (th - th1));
    circle(ctx, cx, cy, s);
    fillWith(ctx, k.main, 0.85);
    ctx.beginPath();
    for (var i = 0; i <= 300; i++) {
      final th = th1 * i / 300, rr = R(th), a = dir * th + rot;
      if (i != 0) {
        ctx.lineTo(cx + rr * math.cos(a), cy + rr * math.sin(a));
      } else {
        ctx.moveTo(cx + rr * math.cos(a), cy + rr * math.sin(a));
      }
    }
    strokeWith(ctx, k.line, 0.007);
    for (var i = 1; i <= septa; i++) {
      final th = th1 * (0.25 + 0.75 * i / septa),
          a = dir * th + rot,
          r0 = R(th - tau),
          r1 = R(th);
      ctx.beginPath();
      ctx.moveTo(cx + r0 * math.cos(a), cy + r0 * math.sin(a));
      ctx.quadraticCurveTo(
        cx + (r0 + r1) / 2 * math.cos(a + 0.12 * dir),
        cy + (r0 + r1) / 2 * math.sin(a + 0.12 * dir),
        cx + r1 * math.cos(a),
        cy + r1 * math.sin(a),
      );
      strokeWith(ctx, k.line, 0.004, 0.7);
    }
  }
}

/// cairn: the stones settle on the breath, the top one last.
class CairnFigure extends Figure {
  const CairnFigure();

  @override
  String get label => 'cairn';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final cx = _num(pl, 'cx'), cy = _num(pl, 'cy'), s = _num(pl, 's');
    final n = r.integer(3, 5);
    var y = cy + s * 0.9;
    final st = <Map<String, Object?>>[];
    for (var i = 0; i < n; i++) {
      final rx = s * (0.75 - i * 0.12) * r.range(0.85, 1.1),
          ry = rx * r.range(0.42, 0.58);
      y -= ry;
      final b = makeBlob(r, cx + r.range(-0.12, 0.12) * s, y, 1, 0.8, 0.006);
      b['rot'] = r.range(-0.12, 0.12);
      b['rx'] = rx;
      b['ry'] = ry;
      st.add(b);
      y -= ry * 0.88;
    }
    return {...pl, 'st': st};
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final st = p.list('st');
    for (var i = 0; i < st.length; i++) {
      final stone = st[i];
      final b = BR(t - i * 0.5, still);
      blobPath(
        ctx,
        stone,
        sx: stone.d('rx'),
        sy: stone.d('ry'),
        dy: -0.004 * b * i / st.length,
      );
      fillWith(ctx, i.isOdd ? k.alt : k.main);
    }
  }
}

/// threads: flow sideways like air through a field.
class ThreadsFigure extends Figure {
  const ThreadsFigure();

  @override
  String get label => 'threads';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final n = r.integer(6, 10);
    return {
      ...pl,
      'lines': [
        for (var i = 0; i < n; i++)
          {
            'y': r.next(),
            'amp': r.range(0.02, 0.06),
            'f': r.range(0.6, 1.4),
            'ph': r.range(0, tau),
            'per': r.range(9, 16),
          },
      ],
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final lines = p.list('lines');
    for (var i = 0; i < lines.length; i++) {
      final L = lines[i];
      final y0 = cy - s * 0.6 + L.d('y') * s * 1.2,
          ph = L.d('ph') + (still ? 0 : tau * t / L.d('per')),
          amp = L.d('amp'),
          f = L.d('f');
      ctx.beginPath();
      var j = 0;
      for (var x = cx - s * 1.25; x <= cx + s * 1.25; x += 0.015, j++) {
        final y =
            y0 +
            amp * math.sin(tau * f * x + ph) +
            0.018 * math.sin(tau * 0.4 * x + ph * 0.5);
        if (j != 0) {
          ctx.lineTo(x, y);
        } else {
          ctx.moveTo(x, y);
        }
      }
      strokeWith(
        ctx,
        i % 3 != 0 ? k.line : k.main,
        0.01 - (i % 3) * 0.002,
        0.95,
      );
    }
  }
}

/// Tall grass bending together in a slow wind.
class GrassFigure extends Figure {
  const GrassFigure();

  @override
  String get label => 'grass';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final n = r.integer(26, 40);
    final blades = [
      for (var i = 0; i < n; i++)
        {
          'x': r.range(-1.1, 1.1),
          'h': r.range(0.6, 1.3),
          'w': r.range(0.004, 0.008),
          'ph': r.range(0, 0.6),
          'seed': r.chance(0.25),
        },
    ];
    return {...pl, 'blades': blades, 'lean': r.range(0.05, 0.18)};
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), lean = p.d('lean');
    final base = cy + s * 0.75;
    final blades = p.list('blades');
    for (var i = 0; i < blades.length; i++) {
      final B = blades[i];
      final bx = B.d('x'), bh = B.d('h');
      final x = cx + bx * s,
          gust = still ? 0.5 : 0.5 + 0.5 * S(t, 9, -bx * 1.6 + B.d('ph')),
          bend = s * (lean + 0.18 * gust) * bh,
          h = s * 1.4 * bh;
      ctx.beginPath();
      ctx.moveTo(x, base);
      ctx.quadraticCurveTo(x, base - h * 0.6, x + bend, base - h);
      strokeWith(ctx, i % 3 != 0 ? k.main : k.line, B.d('w'), 0.9);
      if (B.b('seed')) {
        _petal(
          ctx,
          x + bend,
          base - h,
          s * 0.12,
          s * 0.03,
          -math.pi / 2 + bend / h * 1.5,
        );
        fillWith(ctx, k.alt);
      }
    }
  }
}

/// A few birds gliding on a slow closed path, wings beating slowly.
class FlockFigure extends Figure {
  const FlockFigure();

  @override
  String get label => 'flock';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final kind = slot == 'accent'
        ? 'pair'
        : r.pick(const ['skein', 'scatter', 'pair']);
    final n = kind == 'skein'
        ? r.integer(5, 7)
        : kind == 'pair'
        ? 2
        : r.integer(4, 7);
    final birds = [
      for (var i = 0; i < n; i++)
        kind == 'skein'
            ? <String, Object?>{
                'dx': (i - (n - 1) / 2) * 0.32,
                'dy': (i - (n - 1) / 2).abs() * 0.22,
                's': 1,
              }
            : <String, Object?>{
                'dx': r.range(-1, 1),
                'dy': r.range(-0.6, 0.6),
                's': r.range(0.7, 1.1),
              },
    ];
    return {
      ...pl,
      'kind': kind,
      'birds': [
        for (final b in birds)
          {...b, 'ph': r.range(0, tau), 'per': r.range(1.8, 2.6)},
      ],
      'loop': r.range(18, 26),
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), loop = p.d('loop');
    final ox = still ? 0.0 : s * 0.18 * S(t, loop),
        oy = still ? 0.0 : s * 0.08 * S(t, loop / 2, 1),
        sz = s * (p.s('kind') == 'skein' ? 0.22 : 0.3);
    for (final b in p.list('birds')) {
      final x = cx + b.d('dx') * s + ox,
          y = cy + b.d('dy') * s + oy,
          f = still ? 0.5 : 0.5 + 0.5 * S(t, b.d('per'), b.d('ph')),
          w = sz * b.d('s');
      ctx.beginPath();
      ctx.moveTo(x - w, y - w * (0.15 + 0.45 * f));
      ctx.quadraticCurveTo(x - w * 0.45, y - w * 0.35, x, y);
      ctx.quadraticCurveTo(
        x + w * 0.45,
        y - w * 0.35,
        x + w,
        y - w * (0.15 + 0.45 * f),
      );
      strokeWith(ctx, k.main, math.max(0.004, w * 0.14), 0.95);
    }
  }
}

/// Petals drifting down, turning as they fall.
class PetalsFigure extends Figure {
  const PetalsFigure();

  @override
  String get label => 'petals';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final n = r.integer(7, 12);
    return {
      ...pl,
      'ps': [
        for (var i = 0; i < n; i++)
          {
            'x': r.range(-1, 1),
            'y': r.next(),
            'v': r.range(0.03, 0.055),
            'ph': r.range(0, tau),
            'z': r.range(0.6, 1.1),
            'spin': r.range(0.2, 0.6),
          },
      ],
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final ps = p.list('ps');
    for (var i = 0; i < ps.length; i++) {
      final q = ps[i];
      final qy = q.d('y'), ph = q.d('ph'), z = q.d('z');
      final u = still ? qy : jsMod(qy + t * q.d('v'), 1),
          x = cx + q.d('x') * s + s * 0.2 * S(t, 7, ph),
          y = cy - s * 1.1 + u * s * 2.2,
          a = ph + (still ? 0 : tau * t * q.d('spin') / 10);
      _petal(ctx, x, y, s * 0.3 * z, s * 0.1 * z, a);
      fillWith(ctx, i % 3 != 0 ? k.main : k.alt, fade(u));
    }
  }
}

/// moon: its glow breathes; the phase creeps.
class MoonFigure extends Figure {
  const MoonFigure();

  @override
  String get label => 'moon';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'ph': r.range(0.08, 0.42)};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy');
    final R = p.d('s') * 0.7,
        ph = p.d('ph') + (still ? 0 : 0.03 * S(t, 120)),
        c = math.cos(ph * tau);
    _soft(ctx, cx, cy, R * 2.4, k.glow, 0.22 + (still ? 0 : 0.06 * S(t, 10)));
    circle(ctx, cx, cy, R);
    fillWith(ctx, k.main, 0.2);
    ctx.save();
    circle(ctx, cx, cy, R);
    ctx.clip();
    ctx.beginPath();
    ctx.arc(cx, cy, R, -math.pi / 2, math.pi / 2, false);
    ctx.ellipse(cx, cy, c.abs() * R, R, 0, math.pi / 2, -math.pi / 2, c > 0);
    fillWith(ctx, k.main);
    ctx.restore();
  }
}

/// One round body: sun, lamp, moon or bindu. Breathes between true circle
/// and pebble; the rayed kind turns its rays slowly.
class DiscFigure extends Figure {
  const DiscFigure();

  @override
  String get label => 'disc';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'kind': slot == 'accent'
        ? 'plain'
        : r.pick(const ['plain', 'plain', 'rayed', 'halo']),
    'n': r.pick(const [12, 16, 24]),
    'blob': makeBlob(
      r,
      _num(pl, 'cx'),
      _num(pl, 'cy'),
      _num(pl, 's') * 0.6,
      0.7,
      0.003,
    ),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy');
    final b = BR(t, still), R = p.d('s') * 0.6, kind = p.s('kind');
    if (kind == 'halo') _soft(ctx, cx, cy, R * 2.6, k.glow, 0.3 + 0.1 * b);
    if (kind == 'rayed') {
      final n = p.i('n'), rot = still ? 0.0 : t / 200 * tau;
      for (var i = 0; i < n; i++) {
        final a = i / n * tau + rot,
            r0 = R * 1.3,
            r1 = R * (1.7 + (i.isOdd ? 0.25 : 0.5)) * (0.96 + 0.04 * b);
        ctx.beginPath();
        ctx.moveTo(cx + math.cos(a) * r0, cy + math.sin(a) * r0);
        ctx.lineTo(cx + math.cos(a) * r1, cy + math.sin(a) * r1);
        strokeWith(ctx, k.alt, 0.007);
      }
    }
    blobPath(ctx, p.sub('blob'), imperf: 1 - b, grow: 0.95 + 0.05 * b);
    fillWith(ctx, k.main);
  }
}
