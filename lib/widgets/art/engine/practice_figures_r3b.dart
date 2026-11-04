// The page's names (S, BR, P, R, L, J, N, Y) are kept so the port reads line
// for line.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:medito/services/identity/seeded_random.dart' show easeInOut;
import 'package:medito/services/identity/stroke_engine.dart' show Pen;
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/figures.dart';
import 'package:medito/widgets/art/engine/practice_helpers.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 3 of the practice figures (`docs/fork/design/practices/`
/// `figures-r3.js`, `PracticesR3`), second half: The Mind Illuminated,
/// Anussati and Jhāna. Same contract as round 4's figures; every one loops
/// without a seam and has a calm still frame.
const Map<String, Figure> practiceFiguresR3b = {
  'tmi_climb': TmiClimbFigure(),
  'tmi_steady': TmiSteadyFigure(),
  'tmi_petals': TmiPetalsFigure(),
  'tmi_switchback': TmiSwitchbackFigure(),
  'jewels_gem': JewelsGemFigure(),
  'jewels_lights': JewelsLightsFigure(),
  'jewels_weave': JewelsWeaveFigure(),
  'jhana_gather': JhanaGatherFigure(),
  'jhana_spring': JhanaSpringFigure(),
  'jhana_lotus': JhanaLotusFigure(),
};

const double _breath = breathPeriod;

// ---------- private helpers (figures-r3.js) ----------

/// A petal from ([x], [y]) out along [ang] (`petal`).
void _petal(Ctx ctx, double x, double y, double len, double wid, double ang) {
  final c = math.cos(ang), s = math.sin(ang);
  (double, double) pp(double u, double v) =>
      (x + u * c - v * s, y + u * s + v * c);
  final (ax, ay) = pp(len, 0);
  final (l1x, l1y) = pp(len * 0.35, wid);
  final (l2x, l2y) = pp(len * 0.8, wid * 0.6);
  final (r1x, r1y) = pp(len * 0.35, -wid);
  final (r2x, r2y) = pp(len * 0.8, -wid * 0.6);
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.bezierCurveTo(l1x, l1y, l2x, l2y, ax, ay);
  ctx.bezierCurveTo(r2x, r2y, r1x, r1y, x, y);
  ctx.closePath();
}

/// `core.js` `resample`: [raw] re-spaced to [n] points of even arc length.
List<(double, double)> _resample(List<(double, double)> raw, int n) {
  final m = raw.length, cum = Float64List(m);
  for (var i = 1; i < m; i++) {
    cum[i] =
        cum[i - 1] +
        math.sqrt(
          (raw[i].$1 - raw[i - 1].$1) * (raw[i].$1 - raw[i - 1].$1) +
              (raw[i].$2 - raw[i - 1].$2) * (raw[i].$2 - raw[i - 1].$2),
        );
  }
  final total = cum[m - 1];
  final out = <(double, double)>[];
  var j = 0;
  for (var i = 0; i < n; i++) {
    final d = total * i / (n - 1);
    while (j < m - 2 && cum[j + 1] < d) {
      j++;
    }
    var seg = cum[j + 1] - cum[j];
    if (seg == 0) seg = 1;
    final u = clamp((d - cum[j]) / seg, 0, 1);
    out.add((
      lerp(raw[j].$1, raw[j + 1].$1, u),
      lerp(raw[j].$2, raw[j + 1].$2, u),
    ));
  }
  return out;
}

/// Steadying upwards: one path climbs; low down the line wavers, scattered,
/// and it steadies as it rises, smooth and bright near the top. Ten stage
/// marks sit along it and a light climbs it (`climbDraw`).
void _climbDraw(Ctx ctx, P p, Inks k, double t, bool still) {
  final s = p.d('s');
  final pts = p.raw('pts'), nx = p.nums('nx'), ny = p.nums('ny');
  final ph = p.nums('ph');
  double px(int i) => ((pts[i]! as List)[0]! as num).toDouble();
  double py(int i) => ((pts[i]! as List)[1]! as num).toDouble();
  final N = pts.length, tt = still ? 3.0 : t;
  double off(double v) =>
      s *
      0.1 *
      math.pow(1 - v, 1.7) *
      (0.6 * math.sin(37 * v + tt * 1.4 + ph[0]) +
          0.4 * math.sin(61 * v - tt * 2.1 + ph[1]));
  (double, double) at(int i) {
    final v = i / (N - 1), o = off(v);
    return (px(i) + nx[i] * o, py(i) + ny[i] * o);
  }

  final u = still ? 0.62 : frac(t / (4 * _breath)),
      h = math.min(1.0, u / 0.88),
      lit = (still ? 1.0 : ss(0, 0.03, u)) * (1 - ss(0.9, 1, u));
  pSoft(
    ctx,
    px(N - 1),
    py(N - 1),
    s * 0.5,
    k.glow,
    0.15 + 0.45 * ss(0.85, 1, h) * lit,
  );
  var prev = at(0);
  for (var i = 1; i < N; i++) {
    final v = i / (N - 1), q = at(i);
    ctx.beginPath();
    ctx.moveTo(prev.$1, prev.$2);
    ctx.lineTo(q.$1, q.$2);
    pStroke(
      ctx,
      mix(k.main, k.glow, ss(0.35, 1, v)),
      0.007 + 0.006 * v,
      0.55 + 0.45 * v,
    );
    prev = q;
  }
  for (var j = 0; j < 10; j++) {
    final v = (j + 0.5) / 10, i = (v * (N - 1)).round();
    final (mx, my) = at(i);
    final on = ss(v - 0.02, v + 0.02, h) * lit;
    pDot(ctx, mx, my, s * 0.03);
    pFill(ctx, mix(k.main, k.glow, ss(0.35, 1, v)), 0.4 + 0.6 * on);
  }
  final (x, y) = at((easeInOut(h) * (N - 1)).round());
  pSoft(ctx, x, y, s * 0.25, k.glow, 0.6 * lit);
  pDot(ctx, x, y, s * 0.055);
  pFill(ctx, k.alt, lit);
}

/// A raw centreline becomes the climb's params (`climbPath`).
Map<String, Object?> _climbPath(
  List<(double, double)> raw,
  Map<String, Object?> pl,
  SeededRandom r,
) {
  final pts = _resample(raw, 240);
  final nm = normals(pts, 2);
  return {
    ...pl,
    'pts': [
      for (final q in pts) [q.$1, q.$2],
    ],
    'nx': nm.nx,
    'ny': nm.ny,
    'ph': [r.range(0, tau), r.range(0, tau)],
  };
}

// ---------- The Mind Illuminated ----------

/// One trail up a hillside: a long, gently winding climb from low left to
/// high right over a soft hill, steadying as it goes.
///
/// The Mind Illuminated: one long climb through ten stages, from a
/// scattered start to steady, bright attention.
class TmiClimbFigure extends Figure {
  const TmiClimbFigure();

  @override
  String get label => 'the long climb';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final q = P(pl);
    final cx = q.d('cx'), cy = q.d('cy'), s = q.d('s');
    final raw = Pen(cx - s * 1.25, cy + s * 0.85)
        .cubic(
          cx - s * 0.1,
          cy + s * 0.95,
          cx - s * 0.9,
          cy + s * 0.1,
          cx + s * 0.1,
          cy - s * 0.05,
          90,
        )
        .cubic(
          cx + s * 1.0,
          cy - s * 0.2,
          cx + 0.1 * s,
          cy - s * 0.75,
          cx + s * 0.85,
          cy - s * 0.85,
          90,
        )
        .pts;
    return _climbPath(raw, pl, r);
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.8, cy + s * 1.2);
    ctx.bezierCurveTo(
      cx - s * 0.6,
      cy + s * 0.6,
      cx + s * 0.2,
      cy - s * 1.05,
      cx + s * 0.95,
      cy - s * 0.98,
    );
    ctx.bezierCurveTo(
      cx + s * 1.3,
      cy - s * 0.95,
      cx + s * 1.6,
      cy - s * 0.6,
      cx + s * 1.8,
      cy - s * 0.4,
    );
    ctx.lineTo(cx + s * 1.8, cy + s * 1.2);
    ctx.closePath();
    pFill(ctx, k.main, 0.08);
    _climbDraw(ctx, p, k, t, still);
  }
}

/// From scattered to steady: one line in ten lengths, restless at the
/// start and calmer each stage, until the last is still and bright.
///
/// The Mind Illuminated: attention steadying stage by stage, from scattered
/// to still and bright.
class TmiSteadyFigure extends Figure {
  const TmiSteadyFigure();

  @override
  String get label => 'scattered to steady';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'ph': [r.range(0, tau), r.range(0, tau)],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final ph = p.nums('ph');
    final x0 = cx - s * 1.2, x1 = cx + s * 1.2, M = 200, tt = still ? 3.0 : t;
    double Y(double v) =>
        cy +
        s *
            0.24 *
            math.pow(1 - v, 1.6) *
            (0.6 * math.sin(23 * v + tt * 1.3 + ph[0]) +
                0.4 * math.sin(41 * v - tt * 1.9 + ph[1]));
    for (var i = 1; i < 10; i++) {
      final x = lerp(x0, x1, i / 10);
      ctx.beginPath();
      ctx.moveTo(x, cy - s * 0.42);
      ctx.lineTo(x, cy - s * 0.34);
      pStroke(ctx, k.main, 0.004, 0.35);
    }
    for (var i = 0; i < M; i++) {
      final v = i / M, w = (i + 1) / M;
      ctx.beginPath();
      ctx.moveTo(lerp(x0, x1, v), Y(v));
      ctx.lineTo(lerp(x0, x1, w), Y(w));
      pStroke(
        ctx,
        mix(k.main, k.alt, ss(0.5, 1, v)),
        0.008 + 0.006 * v,
        0.55 + 0.45 * v,
      );
    }
    pSoft(ctx, x1, cy, s * 0.45, k.glow, 0.5);
    final u = still ? 0.7 : frac(t / (4 * _breath)),
        v = easeInOut(u),
        x = lerp(x0, x1, v);
    pSoft(ctx, x, Y(v), s * 0.22, k.glow, 0.6 * fade(u));
    pDot(ctx, x, Y(v), s * 0.05);
    pFill(ctx, k.alt, fade(u));
  }
}

/// A ten-petalled flower opening one petal at a time, from the top round;
/// when all ten are open it rests, then closes, and begins again.
///
/// The Mind Illuminated: ten stages unfolding one after another, like
/// petals.
class TmiPetalsFigure extends Figure {
  const TmiPetalsFigure();

  @override
  String get label => 'ten petals opening';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final u = still ? 0.62 : frac(t / (4 * _breath)),
        close = 1 - ss(0.86, 1, u);
    var n = 0.0;
    for (var i = 0; i < 10; i++) {
      final o = ss(i * 0.075, i * 0.075 + 0.1, u) * close,
          a = -math.pi / 2 + tau * i / 10;
      n += o;
      _petal(
        ctx,
        cx + math.cos(a) * s * 0.16,
        cy + math.sin(a) * s * 0.16,
        s * (0.25 + 0.68 * o),
        s * (0.07 + 0.11 * o),
        a,
      );
      pFill(ctx, mix(k.main, k.alt, o), 0.3 + 0.6 * o);
    }
    pSoft(ctx, cx, cy, s * (0.3 + 0.05 * n), k.glow, 0.3 + 0.04 * n);
    pDot(ctx, cx, cy, s * 0.12);
    pFill(ctx, k.alt);
  }
}

/// A rounded switchback, five legs of even width, ten marks along it.
///
/// The Mind Illuminated: ten stages up one winding path, the line wavering
/// low down and steadying as it climbs.
class TmiSwitchbackFigure extends Figure {
  const TmiSwitchbackFigure();

  @override
  String get label => 'steadying upwards';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final q = P(pl);
    final cx = q.d('cx'), cy = q.d('cy'), s = q.d('s');
    const legs = 5;
    final W = s * 0.72,
        y0 = cy + s * 0.95,
        y1 = cy - s * 0.9,
        dy = (y0 - y1) / legs,
        R = dy * 0.32,
        pen = Pen(cx - W, y0);
    for (var i = 0; i < legs; i++) {
      final dir = i % 2 != 0 ? -1.0 : 1.0,
          yEnd = y0 - (i + 1) * dy + (i < legs - 1 ? R : 0),
          xEnd = cx + dir * W;
      pen.cubic(
        cx - dir * W * 0.3,
        y0 - i * dy - dy * 0.15,
        cx + dir * W * 0.3,
        yEnd + dy * 0.15,
        xEnd,
        yEnd,
        70,
      );
      if (i < legs - 1) {
        // round the bend, bottom to top
        pen.arc(
          xEnd,
          yEnd - R,
          R,
          R,
          math.pi / 2,
          dir > 0 ? -math.pi / 2 : math.pi * 1.5,
          40,
        );
      }
    }
    return _climbPath(pen.pts, pl, r);
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) =>
      _climbDraw(ctx, p, k, t, still);
}

// ---------- Anussati ----------

/// Three soft lights, recollected one after another; each warms in turn.
///
/// Anussati: the Buddha, the Dhamma and the Saṅgha, recollected one by one,
/// each warming in turn.
class JewelsLightsFigure extends Figure {
  const JewelsLightsFigure();

  @override
  String get label => 'three lights';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    const lights = <(double, double)>[(0, -0.46), (-0.52, 0.38), (0.52, 0.38)];
    for (var i = 0; i < lights.length; i++) {
      final (dx, dy) = lights[i];
      final x = cx + dx * s,
          y = cy + dy * s,
          on = still
              ? (i == 0 ? 1.0 : 0.3)
              : 0.3 +
                    0.7 *
                        math
                            .pow(fade(frac(t / (3 * _breath) - i / 3) * 1.5), 2)
                            .toDouble(),
          R = s * 0.17;
      pSoft(ctx, x, y, s * 0.55, k.glow, 0.6 * on);
      final g = ctx.createRadialGradient(x - R * 0.3, y - R * 0.3, 0, x, y, R)
        ..addColorStop(0, css(mix(k.glow, Rgb.white, 0.55)))
        ..addColorStop(1, css(k.alt));
      ctx.globalAlpha = 0.45 + 0.55 * on;
      ctx.fillStyle = g;
      pDot(ctx, x, y, R);
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  }
}

/// The triple gem as the tradition draws it: three jewels, two below and
/// one above, in a halo of flame; the light passes over each in turn.
///
/// Anussati: the three jewels, one refuge — recollected one by one.
class JewelsGemFigure extends Figure {
  const JewelsGemFigure();

  @override
  String get label => 'the triple gem';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), R = s * 0.26;
    const J = <(double, double)>[(0, -0.26), (-0.26, 0.19), (0.26, 0.19)];
    final fl = still ? 0.0 : 0.02 * S(t, 3.1);
    pSoft(ctx, cx, cy, s * 1.1, k.glow, 0.3 + 0.1 * b);
    pTear(ctx, cx, cy + s * 0.2, s * (1.12 + fl), s * 0.82);
    pFill(ctx, k.glow, 0.22);
    pStroke(ctx, k.alt, 0.006, 0.6);
    for (var i = 0; i < J.length; i++) {
      final (dx, dy) = J[i];
      final x = cx + dx * s,
          y = cy + dy * s,
          on = still
              ? (i == 0 ? 1.0 : 0.35)
              : 0.35 +
                    0.65 *
                        math
                            .pow(fade(frac(t / (3 * _breath) - i / 3) * 1.5), 2)
                            .toDouble();
      final g = ctx.createRadialGradient(x - R * 0.35, y - R * 0.35, 0, x, y, R)
        ..addColorStop(0, css(mix(k.glow, Rgb.white, 0.3 + 0.4 * on)))
        ..addColorStop(0.55, css(mix(k.alt, k.glow, 0.3 * on)))
        ..addColorStop(1, css(mix(k.alt, k.main, 0.35)));
      ctx.fillStyle = g;
      pDot(ctx, x, y, R);
      ctx.fill();
    }
  }
}

/// Three rings, each through the other two, none of them free alone: the
/// three refuges as one. Each brightens in turn.
///
/// Anussati: three refuges, each held by the other two, recollected one by
/// one.
class JewelsWeaveFigure extends Figure {
  const JewelsWeaveFigure();

  @override
  String get label => 'three as one';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final R = s * 0.5, d = s * 0.32;
    final cols = [k.glow, k.alt, mix(k.main, k.glow, 0.3)];
    final C3 = <(double, double)>[
      for (var i = 0; i < 3; i++)
        () {
          final a = -math.pi / 2 + tau * i / 3;
          return (cx + math.cos(a) * d, cy + math.sin(a) * d);
        }(),
    ];
    double on(int i) => still
        ? (i == 0 ? 1.0 : 0.4)
        : 0.4 +
              0.6 *
                  math
                      .pow(fade(frac(t / (3 * _breath) - i / 3) * 1.5), 2)
                      .toDouble();
    pSoft(ctx, cx, cy, s * 0.4, k.glow, 0.5);
    void arc(int i, double a0, double a1, double w, Rgb col, double al) {
      ctx.beginPath();
      ctx.arc(C3[i].$1, C3[i].$2, R, a0, a1);
      pStroke(ctx, col, w, al);
    }

    for (var i = 0; i < 3; i++) {
      arc(i, 0, tau, 0.022, cols[i], 0.55 + 0.45 * on(i));
    }
    // each ring passes over the next at both crossings: 0 over 1, 1 over 2,
    // 2 over 0
    for (final (i, j) in const [(0, 1), (1, 2), (2, 0)]) {
      final (ax, ay) = C3[i];
      final (bx, by) = C3[j];
      final D = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)),
          x = D / 2,
          h = math.sqrt(R * R - x * x),
          ux = (bx - ax) / D,
          uy = (by - ay) / D;
      for (final sd in const [-1.0, 1.0]) {
        final px = ax + ux * x - uy * h * sd,
            py = ay + uy * x + ux * h * sd,
            a = math.atan2(py - ay, px - ax);
        arc(i, a - 0.28, a + 0.28, 0.04, k.paper, 1);
        arc(i, a - 0.3, a + 0.3, 0.022, cols[i], 0.55 + 0.45 * on(i));
      }
    }
  }
}

// ---------- Jhāna ----------

/// Round 1's gathering, without the rays: joy scattered about gathers into
/// one soft light with no edge.
///
/// Jhāna: scattered joy gathers into one soft, still light.
class JhanaGatherFigure extends Figure {
  const JhanaGatherFigure();

  @override
  String get label => 'light gathering in';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'motes': <Map<String, Object?>>[
      for (var i = 0; i < 30; i++)
        {
          'a': r.range(0, tau),
          'd': r.range(0.7, 1.3),
          'ph': r.next(),
          'sz': r.range(0.02, 0.04),
        },
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), core = mix(k.glow, Rgb.white, 0.5);
    for (final m in p.list('motes')) {
      final u = still ? m.d('ph') : frac(t / (2 * _breath) + m.d('ph')),
          rr = s * m.d('d') * (1 - easeInOut(u) * 0.85),
          a = m.d('a') + u * 0.6;
      pDot(
        ctx,
        cx + math.cos(a) * rr,
        cy + math.sin(a) * rr,
        s * m.d('sz') * (1 - 0.5 * u),
      );
      pFill(ctx, k.alt, 0.85 * fade(u));
    }
    pSoft(ctx, cx, cy, s * (0.85 + 0.12 * b), k.glow, 0.45);
    final g = ctx.createRadialGradient(cx, cy, 0, cx, cy, s * (0.42 + 0.04 * b))
      ..addColorStop(0, css(core, 1))
      ..addColorStop(0.45, css(core, 0.9))
      ..addColorStop(1, css(k.glow, 0));
    ctx.fillStyle = g;
    pDot(ctx, cx, cy, s * 0.5);
    ctx.fill();
  }
}

/// The second jhāna's simile: a lake fed from a spring beneath, cool water
/// welling up until no part of it is not pervaded.
///
/// Jhāna: like a lake fed by a spring below, cool water welling up until it
/// fills every part.
class JhanaSpringFigure extends Figure {
  const JhanaSpringFigure();

  @override
  String get label => 'a spring-fed lake';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), R = s * 0.98, cool = mix(k.glow, Rgb.white, 0.45);
    pDot(ctx, cx, cy, R);
    pFill(ctx, mix(k.main, k.paper, 0.55), 0.7);
    ctx.save();
    pDot(ctx, cx, cy, R);
    ctx.clip();
    for (var i = 0; i < 4; i++) {
      final u = still ? (i + 0.4) / 4 : frac(t / (3 * _breath) + i / 4),
          rr = R * 1.1 * u,
          w = R * 0.22,
          a = 0.45 * fade(u);
      final g =
          ctx.createRadialGradient(cx, cy, math.max(0, rr - w), cx, cy, rr + w)
            ..addColorStop(0, css(cool, 0))
            ..addColorStop(0.5, css(cool, a))
            ..addColorStop(1, css(cool, 0));
      ctx.fillStyle = g;
      pDot(ctx, cx, cy, rr + w);
      ctx.fill();
    }
    pSoft(ctx, cx, cy, R, cool, 0.12 + 0.18 * b);
    ctx.restore();
    pDot(ctx, cx, cy, R);
    pStroke(ctx, k.main, 0.006, 0.45);
    pDot(ctx, cx, cy, s * 0.05);
    pFill(ctx, cool);
  }
}

/// The third jhāna's simile: lotuses that grow in the water and never rise
/// out of it, drenched with cool water from root to tip.
///
/// Jhāna: like lotuses under water, drenched in coolness from root to tip.
class JhanaLotusFigure extends Figure {
  const JhanaLotusFigure();

  @override
  String get label => 'lotuses in the water';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final s = P(pl).d('s');
    final L = <Map<String, Object?>>[
      for (final (dx, ls) in const [(-0.62, 0.42), (0.06, 0.56), (0.68, 0.38)])
        {
          'dx': dx,
          'ls': ls,
          'p': {
            ...const LotusFigure().build(r, {
              'cx': 0.0,
              'cy': 0.0,
              's': ls * s,
            }, slot),
            'water': false,
            'tiers': 1,
          },
        },
    ];
    final bub = <Map<String, Object?>>[
      for (var i = 0; i < 10; i++)
        {'x': r.range(-1.1, 1.1), 'ph': r.next(), 'z': r.range(0.012, 0.025)},
    ];
    return {...pl, 'L': L, 'bub': bub};
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final wl = cy - s * 0.5,
        bot = cy + s * 1.0,
        cool = mix(k.glow, Rgb.white, 0.4);
    final Ls = p.list('L');
    for (var i = 0; i < Ls.length; i++) {
      final l = Ls[i];
      final base = cy + s * 0.9,
          ls = l.d('ls') * s,
          sway = still ? 0.0 : 0.05 * S(t, 7 + i * 1.7, i.toDouble());
      final qcx = cx + l.d('dx') * s, qcy = base - 0.55 * ls;
      // the lotus params at their place this frame (the JS moves them in
      // place)
      final q = <String, Object?>{...l.sub('p').m, 'cx': qcx, 'cy': qcy};
      ctx.save();
      ctx.translate(qcx, base);
      ctx.rotate(sway);
      ctx.translate(-qcx, -base);
      ctx.beginPath();
      ctx.moveTo(qcx, base);
      ctx.lineTo(qcx, bot + s * 0.3);
      pStroke(ctx, k.main, 0.006, 0.6);
      const LotusFigure().draw(
        ctx,
        P(q),
        k.copyWith(main: mix(k.alt, k.main, 0.25), alt: k.glow),
        t,
        still,
      );
      ctx.restore();
    }
    final wg = ctx.createLinearGradient(0, wl, 0, bot)
      ..addColorStop(0, css(mix(k.paper, Rgb.white, 0.5), 0.45))
      ..addColorStop(1, css(mix(k.paper, cool, 0.3), 0.15));
    ctx.fillStyle = wg;
    ctx.fillRect(cx - s * 2, wl, s * 4, s * 3);
    ctx.beginPath();
    ctx.moveTo(cx - s * 2, wl);
    ctx.lineTo(cx + s * 2, wl);
    pStroke(ctx, k.main, 0.006, 0.5);
    for (final q in p.list('bub')) {
      final u = still ? q.d('ph') : frac(t / (2.4 * _breath) + q.d('ph'));
      pDot(ctx, cx + q.d('x') * s, lerp(bot, wl + s * 0.05, u), s * q.d('z'));
      pFill(ctx, cool, 0.8 * fade(u));
    }
    for (var i = 0; i < 2; i++) {
      pPill(
        ctx,
        cx +
            s * (i != 0 ? 0.5 : -0.4) +
            (still ? 0 : s * 0.05 * S(t, 9 + i * 3)),
        wl + s * 0.05,
        s * 0.4,
        s * 0.025,
        0,
      );
      pFill(ctx, cool, 0.6);
    }
  }
}
