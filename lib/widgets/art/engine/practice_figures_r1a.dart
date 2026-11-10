// The page's names (S, BR, B) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:math' as math;

import 'package:medito/services/identity/seeded_random.dart'
    show easeInOut, easeOut;
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/figures.dart';
import 'package:medito/widgets/art/engine/practice_helpers.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 1 practice figures, part a (`docs/fork/design/practices/figures.js`):
/// metta, seed, stillwater, eight, arising, empty, wane, sky, enso.
const Map<String, Figure> practiceFiguresR1a = {
  'metta': MettaFigure(),
  'seed': SeedFigure(),
  'stillwater': StillwaterFigure(),
  'eight': EightFigure(),
  'arising': ArisingFigure(),
  'empty': EmptyFigure(),
  'wane': WaneFigure(),
  'sky': SkyFigure(),
  'enso': EnsoFigure(),
};

const double _B = breathPeriod;

/// The noise of a figure, rebuilt from its stored seed and cached per
/// params map (`nz(p)`).
final Expando<double Function(double)> _nzCache = Expando('r1a-nz');

double Function(double) _nzOf(P p) =>
    _nzCache[p.m] ??= rngOf(p['nzSeed']!).noise(2);

/// Kindness starts close and widens until no one is outside it.
class MettaFigure extends Figure {
  const MettaFigure();

  @override
  String get label => 'widening rings';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'n': 5};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), n = p.i('n');
    const per = 2 * _B;
    pSoft(ctx, cx, cy, s * 0.55, k.glow, 0.55);
    for (var i = 0; i < n; i++) {
      final u = frac((still ? 0.15 : t / per) + i / n),
          r = s * (0.14 + 1.15 * easeOut(u));
      pDot(ctx, cx, cy, r);
      pStroke(ctx, k.main, 0.006 + 0.008 * (1 - u), 0.85 * fade(u * 1.05));
    }
    pDot(ctx, cx, cy, s * (0.12 + 0.02 * BR(t, still)));
    pFill(ctx, k.alt);
  }
}

/// A saṅkalpa is a seed planted in deep rest, then tended.
class SeedFigure extends Figure {
  const SeedFigure();

  @override
  String get label => 'a planted resolve';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'lean': r.range(-0.12, 0.12)};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final g = cy + s * 0.55,
        sway = still ? 0.0 : 0.05 * S(t, _B),
        grow = 0.92 + 0.08 * BR(t, still);
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.1, g);
    ctx.quadraticCurveTo(cx, g - s * 0.06, cx + s * 1.1, g);
    pStroke(ctx, k.line, 0.01, 0.7);
    ctx.beginPath();
    ctx.ellipse(cx, g + s * 0.12, s * 0.13, s * 0.09, 0.3, 0, tau);
    pFill(ctx, k.alt);
    final tx = cx + s * (p.d('lean') + sway), ty = g - s * 0.95 * grow;
    ctx.beginPath();
    ctx.moveTo(cx, g + s * 0.05);
    ctx.quadraticCurveTo(cx + s * 0.02, g - s * 0.5, tx, ty);
    pStroke(ctx, k.main, 0.014);
    for (final (sd, at) in const [(-1.0, 0.55), (1.0, 0.75)]) {
      final lx = lerp(cx, tx, at),
          ly = lerp(g, ty, at),
          a = -math.pi / 2 + sd * (0.9 + 0.1 * BR(t, still));
      ctx.save();
      ctx.translate(lx, ly);
      ctx.rotate(a + math.pi / 2);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.quadraticCurveTo(sd * s * 0.16, -s * 0.08, sd * s * 0.3, 0);
      ctx.quadraticCurveTo(sd * s * 0.16, s * 0.07, 0, 0);
      pFill(ctx, k.main);
      ctx.restore();
    }
    pSoft(ctx, tx, ty, s * 0.22, k.glow, 0.5);
  }
}

/// Samatha: the ripples calm until the water holds one clear point.
class StillwaterFigure extends Figure {
  const StillwaterFigure();

  @override
  String get label => 'water settling';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    const per = 3 * _B;
    final u = still ? 0.9 : frac(t / per), calm = easeOut(u);
    for (var i = 0; i < 4; i++) {
      final rr = s * (0.25 + 0.28 * i + 0.18 * u);
      ctx.beginPath();
      ctx.ellipse(cx, cy + s * 0.2, rr, rr * 0.28, 0, 0, tau);
      pStroke(ctx, k.main, 0.008, (1 - calm) * 0.7 * (1 - i / 4) + 0.08);
    }
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.2, cy + s * 0.2);
    ctx.lineTo(cx + s * 1.2, cy + s * 0.2);
    pStroke(ctx, k.line, 0.006, 0.3 + 0.4 * calm);
    final y = cy - s * 0.35 - s * 0.03 * (1 - calm) * S(t, 1.7);
    pSoft(ctx, cx, y, s * 0.3, k.glow, 0.35 + 0.3 * calm);
    pDot(ctx, cx, y, s * 0.08);
    pFill(ctx, k.alt);
    ctx.beginPath();
    ctx.ellipse(
      cx,
      cy + s * 0.2 + (cy + s * 0.2 - y) * 0.6,
      s * 0.06,
      s * 0.02,
      0,
      0,
      tau,
    );
    pFill(ctx, k.alt, 0.25 + 0.4 * calm);
  }
}

/// The orb of [EightFigure]'s centre, built once per params map
/// (JS `p._br`).
final Expando<Map<String, Object?>> _brCache = Expando('r1a-br');

/// MBSR: an eight-week course, practised day by day.
class EightFigure extends Figure {
  const EightFigure();

  @override
  String get label => 'eight weeks round';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    const per = 4 * _B;
    final at = still ? 5.3 : jsMod(t / per * 8, 8);
    pDot(ctx, cx, cy, s * 0.8);
    pStroke(ctx, k.line, 0.005, 0.35);
    final fl = at.floor();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + tau * i / 8,
          x = cx + math.cos(a) * s * 0.8,
          y = cy + math.sin(a) * s * 0.8,
          done = i < fl,
          cur = i == fl;
      if (cur) pSoft(ctx, x, y, s * 0.3, k.glow, 0.6 * fade(frac(at)));
      pDot(ctx, x, y, s * (cur ? 0.1 : 0.075));
      pFill(ctx, cur ? k.alt : k.main, done || cur ? 1 : 0.3);
    }
    const breath = BreathFigure();
    final br = _brCache[p.m] ??= {
      ...breath.build(rngOf('mbsr'), {
        'cx': cx,
        'cy': cy,
        's': s * 0.42,
      }, 'figure'),
      'kind': 'orb',
    };
    breath.draw(ctx, P(br), k, t, still);
  }
}

/// Vipassanā: each thing seen arising, staying a moment, passing.
class ArisingFigure extends Figure {
  const ArisingFigure();

  @override
  String get label => 'arising and passing';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'pts':
        <Map<String, Object?>>[
          for (var i = 0; i < 22; i++)
            {
              'x': r.range(-1, 1),
              'y': r.range(-0.9, 0.9),
              'ph': r.next(),
              'per': r.range(4, 9),
              'sz': r.range(0.04, 0.11),
            },
        ].where((q) {
          final x = (q['x']! as num).toDouble(),
              y = (q['y']! as num).toDouble();
          return math.sqrt(x * x + y * y) < 1.05;
        }).toList(),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final pts = p.list('pts');
    for (var i = 0; i < pts.length; i++) {
      final q = pts[i];
      final u = still ? q.d('ph') : frac(t / q.d('per') + q.d('ph')),
          life = fade(u),
          x = cx + q.d('x') * s,
          y = cy + q.d('y') * s,
          sz = q.d('sz');
      pDot(ctx, x, y, s * sz * (0.4 + 0.6 * life));
      pFill(ctx, i % 5 == 0 ? k.alt : k.main, 0.9 * life);
      if (u > 0.5) {
        pDot(ctx, x, y, s * sz * (1 + 2 * (u - 0.5)));
        pStroke(ctx, k.main, 0.004, 0.5 * (1 - u) * 2);
      }
    }
  }
}

/// Śūnyatā: a form, and the openness that it is.
class EmptyFigure extends Figure {
  const EmptyFigure();

  @override
  String get label => 'an open circle';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'gaps': <Map<String, Object?>>[
      for (var i = 0; i < 5; i++)
        {
          'a': r.range(0, tau),
          'w': r.range(0.2, 0.5),
          'sp': r.range(0.01, 0.03) * (r.chance(0.5) ? 1 : -1),
        },
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), R = s * 0.95;
    pSoft(ctx, cx, cy, R * 0.95, k.glow, 0.12 + 0.12 * b);
    const M = 240;
    final open = 0.35 + 0.4 * b, gaps = p.list('gaps');
    for (var i = 0; i < M; i++) {
      final a = tau * i / M;
      var gap = 0.0;
      for (final g in gaps) {
        final d =
            (jsMod(
                      jsMod(a - g.d('a') - (still ? 0 : t * g.d('sp')), tau) +
                          tau +
                          math.pi,
                      tau,
                    ) -
                    math.pi)
                .abs();
        gap = math.max(gap, clamp(1 - d / (g.d('w') * open), 0, 1));
      }
      if (gap > 0.95) continue;
      ctx.beginPath();
      ctx.arc(cx, cy, R, a, a + tau / M + 0.002);
      pStroke(ctx, k.main, 0.016 * (1 - gap), 1 - gap);
    }
  }
}

/// Maraṇasati: everything that lives will fall; remembering it, we wake.
class WaneFigure extends Figure {
  const WaneFigure();

  @override
  String get label => 'a leaf letting go';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'sway': r.range(0.25, 0.4)};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    const per = 3 * _B;
    final u = still ? 0.35 : frac(t / per), g = cy + s * 0.8;
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.15, cy - s * 0.85);
    ctx.quadraticCurveTo(
      cx - s * 0.4,
      cy - s * 0.98,
      cx + s * 0.2,
      cy - s * 0.82,
    );
    pStroke(ctx, k.line, 0.014, 0.8);
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.15, g);
    ctx.lineTo(cx + s * 1.15, g);
    pStroke(ctx, k.line, 0.006, 0.4);
    final y = lerp(cy - s * 0.78, g - s * 0.05, easeInOut(u)),
        x = cx + s * (0.05 + p.d('sway') * math.sin(u * tau * 1.5)),
        rot = 0.9 * math.sin(u * tau * 1.5) + u * 0.8;
    final a = u < 0.85 ? 1.0 : 1 - (u - 0.85) / 0.15;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(rot);
    ctx.beginPath();
    ctx.moveTo(-s * 0.2, 0);
    ctx.quadraticCurveTo(0, -s * 0.14, s * 0.2, 0);
    ctx.quadraticCurveTo(0, s * 0.14, -s * 0.2, 0);
    pFill(ctx, k.alt, a);
    ctx.beginPath();
    ctx.moveTo(-s * 0.24, 0);
    ctx.lineTo(s * 0.18, 0);
    pStroke(ctx, k.line, 0.004, a * 0.7);
    ctx.restore();
    if (u > 0.85) {
      pDot(ctx, x, g, s * 0.3 * (u - 0.85) / 0.15);
      pStroke(ctx, k.main, 0.004, 0.4 * (1 - (u - 0.85) / 0.15));
    }
  }
}

const _skyPuffs = <(double, double, double)>[
  (0, 0, 1),
  (-0.42, 0.07, 0.72),
  (0.4, 0.08, 0.78),
  (0.14, -0.12, 0.8),
  (-0.2, -0.06, 0.7),
];

/// Open awareness: wide space, and weather passing through it.
class SkyFigure extends Figure {
  const SkyFigure();

  @override
  String get label => 'open sky';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'clouds': <Map<String, Object?>>[
      for (var i = 0; i < 3; i++)
        {
          'y': r.range(-0.75, 0.1),
          'w': r.range(0.35, 0.6),
          'ph': r.next(),
          'per': r.range(38, 60),
        },
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final hy = cy + s * 0.62;
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.3, hy);
    ctx.lineTo(cx + s * 1.3, hy);
    pStroke(ctx, k.line, 0.006, 0.65);
    for (final c in p.list('clouds')) {
      final u = still ? c.d('ph') : frac(t / c.d('per') + c.d('ph')),
          x = cx + s * lerp(-1.6, 1.6, u),
          y = cy + c.d('y') * s,
          a = 0.75 * fade(u);
      // soft puffs, lighter than the sky: hard dark ellipses read as stones
      pCloud(ctx, x, y, c.d('w') * s, pVeil(k), a * 0.95, _skyPuffs);
    }
    pDot(ctx, cx + s * 0.75, hy - s * 0.18, s * 0.06);
    pFill(ctx, k.alt, 0.9);
  }
}

/// Zazen: one breath, one brushstroke; the circle left open.
class EnsoFigure extends Figure {
  const EnsoFigure();

  @override
  String get label => 'ensō';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'start': r.range(-0.4, 0.2), 'nzSeed': r.next()};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    const per = 3 * _B;
    final u = still ? 0.7 : frac(t / per),
        drawU = clamp(u / 0.45, 0, 1),
        hold = u < 0.85 ? 1.0 : 1 - (u - 0.85) / 0.15;
    final a0 = math.pi * 0.62 + p.d('start'),
        sweep = tau * 0.9 * easeInOut(drawU),
        n = _nzOf(p);
    const M = 160;
    for (var i = 0; i < M; i++) {
      final v = i / M;
      if (v * tau * 0.9 > sweep) break;
      final a = a0 + v * tau * 0.9, rr = s * (0.88 + 0.03 * n(v * 7));
      // the tail keeps a visible width at tile size, or the still reads as a crescent
      final w =
          s *
          (0.12 * math.pow(1 - v, 0.6) * (0.75 + 0.25 * n(v * 23 + 3)) + 0.04) *
          (v < 0.04 ? v / 0.04 : 1);
      ctx.beginPath();
      ctx.arc(cx, cy, rr, a, a + tau * 0.9 / M + 0.01);
      pStroke(ctx, k.main, w, hold * (0.92 - 0.25 * v));
    }
  }
}
