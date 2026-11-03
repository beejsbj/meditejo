// The page's names (S, BR, B) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'package:medito/services/identity/seeded_random.dart'
    show easeInOut, easeOut;
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/practice_helpers.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 3 of the practice figures, first half (`docs/fork/design/practices/`
/// `figures-r3.js`, `PracticesR3`): the Headless Way, Caṅkama · Kinhin
/// (walking), Forgiveness and Karuṇā, ported line for line. Same contract as
/// round 4's figures; every one loops without a seam and has a calm still
/// frame.
const Map<String, Figure> practiceFiguresR3a = {
  'headless_passing': HeadlessPassingFigure(),
  'headless_capacity': HeadlessCapacityFigure(),
  'headless_tube': HeadlessTubeFigure(),
  'walk_arcs': WalkArcsFigure(),
  'walk_stones': WalkStonesFigure(),
  'forgive_mend': ForgiveMendFigure(),
  'forgive_knot': ForgiveKnotFigure(),
  'karuna_breath': KarunaBreathFigure(),
  'karuna_hold': KarunaHoldFigure(),
  'karuna_rise': KarunaRiseFigure(),
};

const double _breath = breathPeriod;

// ---------- private helpers (figures-r3.js) ----------

double _easeIn(double u) => u * u;

/// JS `mod`: `((x % m) + m) % m`.
double _mod(double x, double m) => (x.remainder(m) + m).remainder(m);

/// `PUFFS.slice(0, 5)`.
const _puffs5 = <(double, double, double)>[
  (0, 0, 1),
  (-0.42, 0.07, 0.72),
  (0.4, 0.08, 0.78),
  (0.14, -0.12, 0.8),
  (-0.2, -0.06, 0.7),
];

/// Blobs the JS caches on `p._b`.
final Expando<Map<String, Object?>> _blobCache = Expando('karunaBlob');

// ---------- Headless Way ----------

/// Capacity: one clear space with no edge, and the world in it — sky, a
/// passing cloud, a sun, hills, near ground. Nothing else; it breathes.
///
/// The Headless Way: here, no head — a clear space without an edge, full of
/// the world.
class HeadlessCapacityFigure extends Figure {
  const HeadlessCapacityFigure();

  @override
  String get label => 'capacity';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'ph': r.next(), 'hp': r.range(0, tau)};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final ph = p.d('ph'), hp = p.d('hp');
    final b = BR(t, still),
        x = cx,
        y = cy - s * 0.05,
        R = s * 0.8 * (0.97 + 0.03 * b);
    final clear = pIsLight(k)
        ? mix(k.paper, Rgb.white, 0.62)
        : mix(k.paper, k.main, 0.14);
    final g = ctx.createRadialGradient(x, y, 0, x, y, R * 1.14)
      ..addColorStop(0, css(clear, 0.96))
      ..addColorStop(0.78, css(clear, 0.92))
      ..addColorStop(1, css(clear, 0));
    ctx.fillStyle = g;
    pDot(ctx, x, y, R * 1.14);
    ctx.fill();
    ctx.save();
    pDot(ctx, x, y, R * 1.02);
    ctx.clip();
    final hy = y + R * 0.2, u = still ? ph : frac(t / (4 * _breath) + ph);
    pSoft(ctx, x - R * 0.32, hy - R * 0.36, R * 0.5, k.glow, 0.5);
    pDot(ctx, x - R * 0.32, hy - R * (0.36 + 0.04 * b), R * 0.1);
    pFill(ctx, k.alt);
    pCloud(
      ctx,
      x + R * lerp(-1.7, 1.7, u),
      y - R * 0.5,
      R * 0.42,
      mix(clear, k.main, 0.16),
      0.85 * fade(u),
      _puffs5,
    );
    ctx.beginPath();
    ctx.moveTo(x - R * 1.1, hy + R);
    for (var i = 0; i <= 40; i++) {
      final v = i / 40;
      ctx.lineTo(
        x + R * lerp(-1.1, 1.1, v),
        hy - R * 0.16 * math.pow(math.sin(math.pi * v * 1.4 + hp), 2),
      );
    }
    ctx.lineTo(x + R * 1.1, hy + R);
    ctx.closePath();
    pFill(ctx, k.line, 0.32);
    ctx.beginPath();
    ctx.moveTo(x - R * 1.1, y + R * 1.1);
    for (var i = 0; i <= 40; i++) {
      final v = i / 40;
      ctx.lineTo(
        x + R * lerp(-1.1, 1.1, v),
        hy + R * (0.22 + 0.05 * math.sin(tau * v * 1.2 + hp)),
      );
    }
    ctx.lineTo(x + R * 1.1, y + R * 1.1);
    ctx.closePath();
    pFill(ctx, k.main, 0.4);
    ctx.restore();
  }
}

/// An open ring that is nothing of its own. The sun crosses the sky; while
/// it passes through, the ring is full of its light; then empty again.
///
/// The Headless Way: an open space with nothing of its own, filled by
/// whatever is there.
class HeadlessPassingFigure extends Figure {
  const HeadlessPassingFigure();

  @override
  String get label => 'full of what passes';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final v = still ? 0.47 : frac(t / (3 * _breath)),
        th = math.pi * (1 - v),
        hy = cy + s * 0.6,
        sx = cx + s * 1.3 * math.cos(th),
        sy = hy - s * 1.12 * math.sin(th),
        a = math.pow(fade(v), 0.5).toDouble();
    final rx = cx, ry = cy - s * 0.3, R = s * 0.46;
    final inside =
        (1 -
            ss(
              R * 0.6,
              R * 1.15,
              math.sqrt((sx - rx) * (sx - rx) + (sy - ry) * (sy - ry)),
            )) *
        a;
    ctx.save();
    pDot(ctx, rx, ry, R);
    ctx.clip();
    pSoft(ctx, sx, sy, R * 1.8, k.glow, 0.75 * inside);
    ctx.restore();
    pDot(ctx, rx, ry, R);
    pStroke(ctx, k.main, 0.005, 0.35 + 0.35 * inside);
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.3, hy);
    ctx.lineTo(cx + s * 1.3, hy);
    pStroke(ctx, k.main, 0.005, 0.45);
    pSoft(ctx, sx, sy, s * 0.3, k.glow, 0.5 * a);
    pDot(ctx, sx, sy, s * 0.08);
    pFill(ctx, k.alt, a);
  }
}

/// Harding's tube: at the far end, a face; at this end, no end at all — the
/// tube opens out past every edge.
///
/// The Headless Way: at the far end of the tube a face; at this end, no
/// edge — open space.
class HeadlessTubeFigure extends Figure {
  const HeadlessTubeFigure();

  @override
  String get label => 'the tube';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'n': 7};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), n = p.i('n');
    final b = BR(t, still);
    for (var i = 0; i < 8; i++) {
      final a = tau * (i + 0.5) / 8;
      ctx.beginPath();
      ctx.moveTo(cx + math.cos(a) * s * 0.18, cy + math.sin(a) * s * 0.18);
      ctx.lineTo(cx + math.cos(a) * s * 2, cy + math.sin(a) * s * 2);
      pStroke(ctx, k.main, 0.003, 0.14);
    }
    for (var i = 0; i < n; i++) {
      final u = still ? (i + 0.5) / n : frac(t / (2 * _breath) + i / n),
          r = s * 0.17 * math.exp(3.1 * u);
      pDot(ctx, cx, cy, r);
      pStroke(
        ctx,
        k.main,
        0.003 + 0.012 * u,
        0.6 * ss(0, 0.15, u) * (1 - ss(0.5, 0.92, u)),
      );
    }
    pSoft(ctx, cx, cy, s * 0.35, k.glow, 0.45 + 0.1 * b);
    pDot(ctx, cx, cy, s * 0.1);
    pFill(ctx, k.alt);
  }
}

// ---------- Caṅkama · Kinhin ----------

/// Kinhin's half step to a breath: each step drawn as one slow arc —
/// lifting, moving, placing — the trail of earlier steps drifting behind.
///
/// Kinhin: one slow step to each half breath — lifting, moving, placing —
/// then the next.
class WalkArcsFigure extends Figure {
  const WalkArcsFigure();

  @override
  String get label => 'one step, then the next';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final ST = _breath / 2,
        L = s * 0.52,
        H = s * 0.34,
        base = cy + s * 0.32,
        tt = still ? ST * 6.62 : t,
        c = (tt / ST).floor(),
        f = tt / ST - c;
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.3, base);
    ctx.lineTo(cx + s * 1.3, base);
    pStroke(ctx, k.main, 0.004, 0.25);
    for (var j = c - 7; j <= c; j++) {
      final sx = cx + (j - tt / ST) * L,
          prog = j < c ? 1.0 : easeInOut(f),
          edge = ss(cx - s * 1.45, cx - s * 0.9, sx + L * 0.5),
          a = (j == c ? 1.0 : 0.85 * (1 - (c - j) / 8)) * edge;
      ctx.beginPath();
      for (var i = 0; i <= 30; i++) {
        final v = prog * i / 30;
        final x = sx + v * L, y = base - H * math.sin(math.pi * v);
        if (i != 0) {
          ctx.lineTo(x, y);
        } else {
          ctx.moveTo(x, y);
        }
      }
      pStroke(ctx, mix(k.main, k.alt, 1 - ss(1, 1.8, tt / ST - j)), 0.014, a);
      if (j < c) {
        pDot(ctx, sx + L, base, s * 0.03);
        pFill(ctx, k.main, a);
      }
    }
    final hx = cx - f * L,
        v = easeInOut(f),
        tx = hx + v * L,
        ty = base - H * math.sin(math.pi * v);
    if (f < 0.3) {
      pDot(ctx, hx, base, s * (0.04 + 0.22 * f / 0.3));
      pStroke(ctx, k.alt, 0.005, 0.6 * (1 - f / 0.3));
    }
    pSoft(ctx, tx, ty, s * 0.3, k.glow, 0.6);
    pDot(ctx, tx, ty, s * 0.065);
    pFill(ctx, k.alt);
  }
}

/// Stepping stones going away across still water: a light steps from one to
/// the next, each placing a small ring on the water.
///
/// Walking: one stone, then the next — each step placed fully before the
/// next is lifted.
class WalkStonesFigure extends Figure {
  const WalkStonesFigure();

  @override
  String get label => 'stepping stones';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'st': [
      for (var i = 0; i < 6; i++)
        () {
          final z = i / 5, sc = lerp(1, 0.38, z);
          return <String, Object?>{
            'x': (i % 2 != 0 ? 1 : -1) * 0.2 * sc + r.range(-0.04, 0.04),
            'y': lerp(0.85, -0.7, math.pow(z, 0.85).toDouble()),
            'sc': sc,
          };
        }(),
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final st = p.list('st');
    final ST = 4.0,
        tt = still ? ST * 2.55 : t,
        c = _mod((tt / ST).floorToDouble(), 7).toInt(),
        f = tt / ST - (tt / ST).floorToDouble();
    (double, double, double) at(int i) {
      final q = st[i];
      return (cx + q.d('x') * s, cy + q.d('y') * s, q.d('sc'));
    }

    for (var i = 0; i < st.length; i++) {
      final (x, y, sc) = at(i);
      ctx.beginPath();
      ctx.ellipse(x, y, s * 0.27 * sc, s * 0.085 * sc, 0, 0, tau);
      pFill(ctx, k.main, 0.32);
      pStroke(ctx, k.main, 0.004, 0.45);
    }
    double x, y, sc;
    var a = 1.0, lift = 0.0;
    if (c < 5) {
      final (ax, ay, a0) = at(c);
      final (bx, by, b0) = at(c + 1);
      final v = easeInOut(f);
      x = lerp(ax, bx, v);
      y = lerp(ay, by, v);
      sc = lerp(a0, b0, v);
      lift = math.sin(math.pi * f);
    } else if (c == 5) {
      (x, y, sc) = at(5);
      a = 1 - ss(0.2, 1, f);
    } else {
      (x, y, sc) = at(0);
      a = ss(0, 0.8, f);
    }
    if (c < 5 && f < 0.3 && c > 0) {
      final (lx, ly, ls) = at(c);
      ctx.beginPath();
      ctx.ellipse(
        lx,
        ly,
        s * (0.3 + 0.35 * f / 0.3) * ls,
        s * (0.1 + 0.12 * f / 0.3) * ls,
        0,
        0,
        tau,
      );
      pStroke(ctx, k.glow, 0.005, 0.7 * (1 - f / 0.3));
    }
    final wy = y - s * (0.07 + 0.18 * lift) * sc;
    pSoft(ctx, x, wy, s * 0.3 * sc, k.glow, 0.6 * a);
    pDot(ctx, x, wy, s * 0.07 * sc);
    pFill(ctx, k.alt, a);
  }
}

// ---------- Forgiveness ----------

/// Mended with gold: a bowl that broke, the break filled with gold. It
/// stays one bowl; the seam glows on the breath.
///
/// Forgiveness: what broke is mended, and the mending made precious, not
/// hidden.
class ForgiveMendFigure extends Figure {
  const ForgiveMendFigure();

  @override
  String get label => 'mended with gold';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final cx = pNum(pl, 'cx'), cy = pNum(pl, 'cy'), s = pNum(pl, 's');
    final a0 = -math.pi / 2 - 0.35, R = s * 0.78;
    final pts = <List<double>>[];
    for (var i = 0; i <= 7; i++) {
      final v = i / 7,
          x = lerp(math.cos(a0), -math.cos(a0), v) * R * 1.02,
          y = lerp(math.sin(a0), -math.sin(a0), v) * R * 1.02;
      pts.add([
        cx + x + (i > 0 && i < 7 ? r.range(-0.12, 0.12) * R : 0),
        cy + y,
      ]);
    }
    const bi = 3;
    final br = <List<double>>[
      pts[bi],
      [pts[bi][0] + R * 0.32, pts[bi][1] + R * 0.12],
      [pts[bi][0] + R * 0.62, pts[bi][1] + R * 0.06],
    ];
    return {...pl, 'R': R, 'pts': pts, 'br': br};
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), R = p.d('R');
    List<List<double>> pairs(String key) => [
      for (final e in p.raw(key))
        [for (final v in e as List) (v as num).toDouble()],
    ];
    final b = BR(t, still);
    pSoft(ctx, cx, cy, s * 1.25, k.glow, 0.15 + 0.12 * b);
    pDot(ctx, cx, cy, R);
    pFill(ctx, k.main, 0.88);
    pDot(ctx, cx, cy, R * 0.8);
    pStroke(ctx, k.paper, 0.004, 0.25);
    ctx.save();
    pDot(ctx, cx, cy, R);
    ctx.clip();
    final lines = [pairs('pts'), pairs('br')];
    for (var j = 0; j < lines.length; j++) {
      final line = lines[j];
      void trace() {
        ctx.beginPath();
        for (var i = 0; i < line.length; i++) {
          if (i != 0) {
            ctx.lineTo(line[i][0], line[i][1]);
          } else {
            ctx.moveTo(line[i][0], line[i][1]);
          }
        }
      }

      trace();
      pStroke(ctx, k.glow, j != 0 ? 0.014 : 0.022, 0.25 + 0.3 * b);
      trace();
      pStroke(ctx, mix(k.alt, k.glow, 0.35 * b), j != 0 ? 0.005 : 0.008);
    }
    ctx.restore();
  }
}

/// Round 1's knot, with a body: a thick rope that winds round itself when
/// held tight and lies as one easy wave when let go.
///
/// Forgiveness loosens what has been held tight.
class ForgiveKnotFigure extends Figure {
  const ForgiveKnotFigure();

  @override
  String get label => 'a knot loosening';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final L = still ? 0.22 : 0.5 + 0.5 * S(t, 2 * _breath, -math.pi / 2),
        M = 260,
        loops = lerp(2.5, 0, L),
        R = s * lerp(0.62, 0.9, L);
    pSoft(ctx, cx, cy, s * (0.45 + 0.6 * L), k.glow, 0.15 + 0.35 * L);
    ctx.beginPath();
    for (var i = 0; i <= M; i++) {
      final u = i / M,
          x0 = cx + s * lerp(-1.15, 1.15, u),
          env = math.sin(math.pi * u),
          a = tau * (loops + 0.5) * u;
      final x = x0 - R * 0.95 * env * env * math.sin(a) * (1 - L * 0.85),
          y =
              cy +
              R * 0.6 * env * env * math.cos(a) * (1 - L) +
              s * 0.18 * L * math.sin(tau * u);
      if (i != 0) {
        ctx.lineTo(x, y);
      } else {
        ctx.moveTo(x, y);
      }
    }
    pStroke(
      ctx,
      k.main,
      0.026,
    ); // the same line twice: the rope, then its sheen
    ctx.lineWidth = 0.007;
    ctx.strokeStyle = css(mix(k.main, k.glow, 0.55), 0.55);
    ctx.stroke();
    for (final sd in const [-1.0, 1.0]) {
      pDot(ctx, cx + sd * s * 1.15, cy, s * 0.06);
      pFill(ctx, k.alt);
    }
  }
}

// ---------- Karuṇā ----------

/// Tonglen without the eye: on the in-breath, dark motes drawn in to a warm
/// heart, where they vanish; on the out-breath, a ring of ease goes out.
///
/// Karuṇā as tonglen: breathing in what hurts, breathing out ease.
class KarunaBreathFigure extends Figure {
  const KarunaBreathFigure();

  @override
  String get label => 'taking in, sending out';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'm': [
      for (var i = 0; i < 14; i++)
        <String, Object?>{
          'a': tau * i / 14 + r.range(-0.2, 0.2),
          'd': r.range(0.9, 1.3),
          'z': r.range(0.03, 0.05),
        },
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final ph = still ? 0.3 : frac(t / _breath),
        inhale = ph < 0.5,
        u = inhale ? ph * 2 : (ph - 0.5) * 2,
        b = BR(t, still);
    pSoft(ctx, cx, cy, s * 0.6, k.glow, 0.4 + 0.2 * b);
    if (inhale) {
      for (final m in p.list('m')) {
        final r = s * lerp(m.d('d') * 1.15, 0.12, _easeIn(u)),
            a = m.d('a') + u * 0.4;
        pDot(
          ctx,
          cx + math.cos(a) * r,
          cy + math.sin(a) * r,
          s * m.d('z') * (1 - 0.6 * u),
        );
        pFill(ctx, k.main, 0.75 * fade(u));
      }
    } else {
      pDot(ctx, cx, cy, s * lerp(0.25, 1.3, easeOut(u)));
      pStroke(ctx, k.glow, 0.022 * (1 - u) + 0.004, 0.85 * fade(u));
      pSoft(ctx, cx, cy, s * lerp(0.3, 1.2, u), k.glow, 0.3 * (1 - u));
    }
    final blob = _blobCache[p.m] ??= makeBlob(
      rngOf('karuna'),
      cx,
      cy,
      s * 0.15,
      0.8,
      0,
    );
    blobPath(ctx, P(blob), imperf: 0.6, grow: 0.95 + 0.1 * b);
    pFill(ctx, k.alt);
  }
}

/// Held: something small and trembling, cradled by a wide warm curve; on
/// each out-breath it trembles less and warms.
///
/// Karuṇā: suffering held with care, and easing in the holding.
class KarunaHoldFigure extends Figure {
  const KarunaHoldFigure();

  @override
  String get label => 'held';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'blob': makeBlob(
      r,
      pNum(pl, 'cx'),
      pNum(pl, 'cy') + pNum(pl, 's') * 0.12,
      pNum(pl, 's') * 0.2,
      2.2,
      0,
    ),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still),
        calm = 1 - b,
        lift = s * 0.03 * b,
        jit = still ? 0.0 : (1 - calm) * s * 0.012 * S(t, 0.6);
    pSoft(
      ctx,
      cx,
      cy + s * 0.1,
      s * (0.75 + 0.1 * b),
      k.glow,
      0.35 + 0.15 * calm,
    );
    for (final (rr, w, a) in const [(0.82, 0.024, 1.0), (0.68, 0.01, 0.5)]) {
      ctx.beginPath();
      ctx.arc(cx, cy - s * 0.28 - lift, s * rr, math.pi * 0.18, math.pi * 0.82);
      pStroke(ctx, k.alt, w, a);
    }
    blobPath(
      ctx,
      p.sub('blob'),
      dx: jit,
      dy: -lift,
      imperf: 0.4 + 0.6 * b,
      grow: 0.95 + 0.05 * calm,
    );
    pFill(ctx, mix(k.main, k.glow, 0.25 + 0.5 * calm));
  }
}

/// Dark rising into a warm heart, and light rising out of it: the whole
/// practice as one quiet, unending flow.
///
/// Karuṇā: what is dark taken into the heart, and coming out as light.
class KarunaRiseFigure extends Figure {
  const KarunaRiseFigure();

  @override
  String get label => 'dark into light';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'm': [
      for (var i = 0; i < 20; i++)
        <String, Object?>{
          'ox': r.range(-0.7, 0.7),
          'ph': i / 20 + r.range(-0.02, 0.02),
          'z': r.range(0.022, 0.04),
        },
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still);
    pSoft(ctx, cx, cy, s * (0.6 + 0.08 * b), k.glow, 0.5);
    for (final m in p.list('m')) {
      final u = still
              ? frac(m.d('ph') + 0.02)
              : frac(t / (1.6 * _breath) + m.d('ph')),
          y = cy + s * lerp(1.15, -1.15, u),
          lower = u < 0.5;
      final x =
              cx +
              m.d('ox') *
                  s *
                  (lower ? 1 - _easeIn(u * 2) : easeOut((u - 0.5) * 2) * 1.2),
          a = fade(u) * ss(0.03, 0.14, (u - 0.5).abs());
      pDot(ctx, x, y, s * m.d('z'));
      pFill(ctx, mix(k.main, k.glow, ss(0.4, 0.6, u)), a);
    }
    pDot(ctx, cx, cy, s * (0.16 + 0.02 * b));
    pFill(ctx, k.alt);
  }
}
