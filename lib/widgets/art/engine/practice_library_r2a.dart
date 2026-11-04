// The page's names (S, BR, B) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'package:medito/services/identity/mark_spec.dart' show MarkStroke;
import 'package:medito/services/identity/seeded_random.dart'
    show easeInOut, easeOut, progress;
import 'package:medito/services/identity/stroke_engine.dart'
    show Pen, makeStroke;
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/practice_helpers.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 2 of the practice figures, library batch A
/// (`docs/fork/design/practices/figures-r2.js`, `PracticesR2`): Insight
/// Dialogue, Effortless mindfulness, Kāyagatāsati, Prāṇa · Qì and Focusing,
/// two variants each, ported line for line.
const Map<String, Figure> practiceLibraryR2a = {
  'dialogue_strokes': DialogueStrokesFigure(),
  'dialogue_thread': DialogueThreadFigure(),
  'glimpse_widen': GlimpseWidenFigure(),
  'glimpse_veils': GlimpseVeilsFigure(),
  'body_pebble': BodyPebbleFigure(),
  'body_contours': BodyContoursFigure(),
  'energy_motes': EnergyMotesFigure(),
  'energy_orbit': EnergyOrbitFigure(),
  'focus_blur': FocusBlurFigure(),
  'focus_handle': FocusHandleFigure(),
};

const double _breath = breathPeriod;

// ---------- private helpers ----------

/// A ribbon drawn up to [p] of its pen clock, in the current fill style
/// (`core.js` `drawStroke`).
void _drawStroke(Ctx ctx, MarkStroke st, double p) {
  if (p <= 0) return;
  final n = st.n, x = st.x, y = st.y, nx = st.nx, ny = st.ny, w = st.w;
  final cost = st.cost;
  var k = n - 1;
  var f = 0.0;
  if (p < 1) {
    var lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cost[mid] <= p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    k = lo;
    final span = cost[hi] - cost[lo];
    f = (p - cost[lo]) / (span == 0 ? 1 : span);
  }
  final k2 = math.min(k + 1, n - 1);
  final ex = lerp(x[k], x[k2], f), ey = lerp(y[k], y[k2], f);
  final ew = lerp(w[k], w[k2], f) / 2;
  final enx = lerp(nx[k], nx[k2], f), eny = lerp(ny[k], ny[k2], f);
  ctx
    ..beginPath()
    ..moveTo(x[0] + nx[0] * w[0] / 2, y[0] + ny[0] * w[0] / 2);
  for (var i = 1; i <= k; i++) {
    ctx.lineTo(x[i] + nx[i] * w[i] / 2, y[i] + ny[i] * w[i] / 2);
  }
  ctx
    ..lineTo(ex + enx * ew, ey + eny * ew)
    ..lineTo(ex - enx * ew, ey - eny * ew);
  for (var i = k; i >= 0; i--) {
    ctx.lineTo(x[i] - nx[i] * w[i] / 2, y[i] - ny[i] * w[i] / 2);
  }
  ctx
    ..closePath()
    ..fill()
    ..beginPath()
    ..arc(x[0], y[0], w[0] / 2, 0, tau)
    ..fill()
    ..beginPath()
    ..arc(ex, ey, ew, 0, tau)
    ..fill();
}

/// The first five of `PUFFS`, which `glimpse_veils` flattens and widens.
const _puffs5 = <(double, double, double)>[
  (0, 0, 1),
  (-0.42, 0.07, 0.72),
  (0.4, 0.08, 0.78),
  (0.14, -0.12, 0.8),
  (-0.2, -0.06, 0.7),
];

// ---------- Insight Dialogue ----------

/// One hand draws half a circle and stops, listening; the other answers
/// with the other half. Only when both are there does the inside light up.
/// The two halves never quite join: the form stays open.
///
/// Insight Dialogue: one speaks, pauses, the other answers; the shape is
/// made between them.
class DialogueStrokesFigure extends Figure {
  const DialogueStrokesFigure();

  @override
  String get label => 'call and answer';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final cx = (pl['cx']! as num).toDouble(),
        cy = (pl['cy']! as num).toDouble(),
        s = (pl['s']! as num).toDouble();
    MarkStroke mk(double a0, double a1, double R, double w) {
      final raw = Pen(
        cx + R * math.cos(a0),
        cy + R * math.sin(a0),
      ).arc(cx, cy, R, R, a0, a1, 140).pts;
      return makeStroke(
        raw,
        r,
        width: w,
        wobble: 0.006,
        pressure: 0.22,
        nib: 0.35,
        taper: 'brush',
        samples: 260,
      );
    }

    return {
      ...pl,
      'left': mk(-math.pi / 2 - 0.14, -math.pi * 1.5 + 0.16, s * 0.9, 0.036),
      'right': mk(math.pi / 2 - 0.16, -math.pi / 2 + 0.2, s * 0.86, 0.032),
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final u = still ? 0.8 : frac(t / (2 * _breath)), out = 1 - ss(0.86, 1, u);
    final pl = still ? 1.0 : easeInOut(progress(u, 0.02, 0.3)),
        pr = still ? 1.0 : easeInOut(progress(u, 0.44, 0.28));
    final lit = (still ? 1.0 : ss(0.55, 0.78, u)) * out;
    pSoft(ctx, cx, cy, s * (0.6 + 0.25 * lit), k.glow, 0.55 * lit);
    pDot(ctx, cx, cy, s * 0.08 * lit);
    pFill(ctx, k.alt, lit);
    ctx
      ..globalAlpha = out
      ..fillStyle = css(k.main);
    _drawStroke(ctx, p['left']! as MarkStroke, pl);
    ctx.fillStyle = css(k.alt);
    _drawStroke(ctx, p['right']! as MarkStroke, pr);
    ctx.globalAlpha = 1;
  }
}

/// Two lights and the thread between them: a bead of light leaves each at
/// once, and where they pass in the middle, something blooms.
///
/// Insight Dialogue: two people, one thread of attention; meeting,
/// something blooms between them.
class DialogueThreadFigure extends Figure {
  const DialogueThreadFigure();

  @override
  String get label => 'the space between';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still),
        y0 = cy - s * 0.05,
        x0 = cx - s * 1.05,
        x1 = cx + s * 1.05,
        sag = s * (0.36 - 0.14 * b);
    (double, double) at(double u) {
      final v = 1 - u;
      return (v * v * x0 + 2 * v * u * cx + u * u * x1, y0 + 4 * v * u * sag);
    }

    ctx.beginPath();
    for (var i = 0; i <= 60; i++) {
      final (x, y) = at(i / 60);
      if (i != 0) {
        ctx.lineTo(x, y);
      } else {
        ctx.moveTo(x, y);
      }
    }
    pStroke(ctx, k.main, 0.008, 0.7);
    final u = still ? 0.5 : easeInOut(frac(t / _breath)),
        meet = math.exp(-math.pow((u - 0.5) / 0.1, 2));
    final (mx, my) = at(0.5);
    // the bloom: a soft light, and two rings opening from where they met
    final bloom = still ? 0.6 : frac(t / _breath - 0.5);
    pSoft(ctx, mx, my, s * (0.4 + 0.4 * meet), k.glow, 0.2 + 0.55 * meet);
    for (final d in const [0.0, 0.18]) {
      final v = clamp((bloom - d) / 0.5, 0, 1);
      if (v > 0 && v < 1) {
        pDot(ctx, mx, my, s * (0.08 + 0.5 * easeOut(v)));
        pStroke(ctx, k.alt, 0.007, 0.8 * fade(v));
      }
    }
    pDot(ctx, mx, my, s * 0.07 * (0.35 + 0.65 * meet));
    pFill(ctx, k.alt, 0.35 + 0.65 * meet);
    if (!still) {
      for (final v in [u, 1 - u]) {
        final (x, y) = at(v);
        pSoft(ctx, x, y, s * 0.14, k.glow, 0.7 * (1 - meet));
        pDot(ctx, x, y, s * 0.03);
        pFill(ctx, k.alt, 1 - meet * 0.6);
      }
    }
    for (final x in [x0, x1]) {
      pSoft(ctx, x, y0, s * 0.24, k.glow, 0.35);
      pDot(ctx, x, y0, s * 0.075);
      pFill(ctx, k.main);
    }
  }
}

// ---------- Effortless mindfulness ----------

/// Attention narrowed to a tight bright ring lets go: it widens and
/// dissolves into the soft light that was already everywhere.
///
/// Effortless mindfulness: narrow attention lets go and opens into the
/// awareness already here.
class GlimpseWidenFigure extends Figure {
  const GlimpseWidenFigure();

  @override
  String get label => 'dropping back';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final u = still ? 0.52 : frac(t / (2 * _breath)),
        w = ss(0.36, 0.86, u),
        open = w * (1 - ss(0.86, 1, u));
    pSoft(ctx, cx, cy, s * (0.9 + 0.7 * open), k.glow, 0.16 + 0.42 * open);
    final jit = (1 - w) * s * 0.012 * (still ? 0 : S(t, 1.3)),
        rr = s * lerp(0.2, 1.7, easeOut(w)) + jit;
    final a = (1 - w) * (still ? 1.0 : ss(0, 0.1, u));
    pDot(ctx, cx, cy, rr);
    pStroke(ctx, k.main, 0.004 + 0.012 * (1 - w), a);
    if (w > 0 && w < 1) {
      pDot(ctx, cx, cy, rr * 0.86);
      pStroke(ctx, k.glow, 0.02 * w, 0.5 * fade(w));
    }
    pDot(ctx, cx, cy, s * 0.055);
    pFill(ctx, k.alt);
  }
}

/// A steady light, and soft veils drifting past in front of it. The veils
/// thin on the out-breath; the light never moves.
///
/// Effortless mindfulness: veils drift past a light that never moved.
class GlimpseVeilsFigure extends Figure {
  const GlimpseVeilsFigure();

  @override
  String get label => 'already here';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    const ys = [-0.46, -0.12, 0.2, 0.5, -0.3];
    return {
      ...pl,
      'veils': <Map<String, Object?>>[
        for (var i = 0; i < 5; i++)
          {
            'y': ys[i] + r.range(-0.05, 0.05),
            'w': r.range(0.55, 0.85),
            'ph': i / 5 + r.range(-0.04, 0.04),
            'per': r.range(34, 46),
          },
      ],
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), veil = pVeil(k), ly = cy - s * 0.05;
    pSoft(ctx, cx, ly, s * 0.95, k.glow, 0.5);
    pDot(ctx, cx, ly, s * 0.2);
    pFill(ctx, k.alt);
    final puffs = [
      for (final (dx, dy, sc) in _puffs5) (dx * 1.4, dy * 0.5, sc),
    ];
    for (final v in p.list('veils')) {
      final u = still
              ? frac(v.d('ph') + 0.15)
              : frac(t / v.d('per') + v.d('ph')),
          x = cx + s * lerp(-2.0, 2.0, u);
      pCloud(
        ctx,
        x,
        cy + v.d('y') * s,
        s * v.d('w'),
        veil,
        (0.6 + 0.3 * (1 - b)) * fade(u),
        puffs,
      );
    }
  }
}

// ---------- Kāyagatāsati ----------

/// A resting pebble breathing between perfect and imperfect; the band of
/// attention passes through it and, inside the band, sensation shows.
///
/// Kāyagatāsati: attention passing slowly through the body, and sensation
/// showing where it rests.
class BodyPebbleFigure extends Figure {
  const BodyPebbleFigure();

  @override
  String get label => 'through the stone';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final cx = (pl['cx']! as num).toDouble(),
        cy = (pl['cy']! as num).toDouble(),
        s = (pl['s']! as num).toDouble();
    final blob = makeBlob(r, cx, cy + s * 0.05, s * 0.72, 0.9, 0.002);
    return {
      ...pl,
      'blob': blob,
      'grain': <Map<String, Object?>>[
        for (var i = 0; i < 150; i++)
          {
            'x': r.range(-0.8, 0.8),
            'y': r.range(-1.1, 1.1),
            'z': r.range(0.008, 0.02),
            'ph': r.range(0, tau),
          },
      ],
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still),
        u = still ? 0.4 : 0.5 - 0.5 * math.cos(tau * t / (3 * _breath)),
        band = cy + s * lerp(-1.05, 1.15, u);
    final blob = p.sub('blob');
    final imperf = 1 - 0.5 * b, grow = 0.97 + 0.03 * b;
    blobPath(ctx, blob, imperf: imperf, grow: grow, sx: 0.78, sy: 1.22);
    pFill(ctx, k.main, 0.2);
    ctx.save();
    blobPath(ctx, blob, imperf: imperf, grow: grow, sx: 0.78, sy: 1.22);
    ctx.clip();
    pSoftE(ctx, cx, band, s * 1.1, s * 0.26, k.glow, 0.75);
    for (final g in p.list('grain')) {
      final y = cy + g.d('y') * s,
          w = math.exp(-math.pow((y - band) / (s * 0.2), 2));
      if (w < 0.03) continue;
      pDot(
        ctx,
        cx + g.d('x') * s,
        y,
        g.d('z') * (still ? 1 : 0.8 + 0.4 * (0.5 + 0.5 * S(t, 2.3, g.d('ph')))),
      );
      pFill(ctx, k.alt, w);
    }
    ctx.restore();
    blobPath(ctx, blob, imperf: imperf, grow: grow, sx: 0.78, sy: 1.22);
    pStroke(ctx, k.main, 0.007, 0.75);
  }
}

/// The body as terrain: contour lines, and attention moving from the
/// outermost inward and back, one layer at a time — skin, flesh, bone.
///
/// Kāyagatāsati: the body contemplated layer by layer, from the skin
/// inward and back.
class BodyContoursFigure extends Figure {
  const BodyContoursFigure();

  @override
  String get label => 'layer by layer';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final waves = <List<double>>[
      [2, r.range(0.06, 0.1), r.range(0, tau)],
      [3, r.range(0.03, 0.06), r.range(0, tau)],
      [5, r.range(0.01, 0.025), r.range(0, tau)],
    ];
    return {
      ...pl,
      'n': 7,
      'waves': waves,
      'ox': r.range(-0.15, 0.15),
      'oy': r.range(-0.2, 0.05),
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final n = p.i('n'), ox = p.d('ox'), oy = p.d('oy');
    final waves = <(double, double, double)>[
      for (final w in p.raw('waves').map((e) => e! as List))
        (
          (w[0] as num).toDouble(),
          (w[1] as num).toDouble(),
          (w[2] as num).toDouble(),
        ),
    ];
    final at = still
            ? 2.3
            : (n - 1) * (0.5 - 0.5 * math.cos(tau * t / (3 * _breath))),
        b = BR(t, still);
    for (var i = 0; i < n; i++) {
      final f = i / (n - 1),
          x = cx + ox * s * f,
          y = cy + oy * s * f,
          R = s * lerp(1.12, 0.16, f) * (0.98 + 0.02 * b);
      final lit = math.max(0.0, 1 - (at - i).abs() * 1.1);
      final wv = [
        for (final (kk, a, ph) in waves) (kk, a * (1 - 0.5 * f), ph + f * 0.6),
      ];
      pLobed(ctx, x, y, R, wv, 1.08);
      if (lit > 0) pFill(ctx, k.glow, 0.22 * lit);
      pStroke(
        ctx,
        mix(k.main, k.alt, ss(0.2, 0.7, lit)),
        0.006 + 0.008 * lit,
        0.45 + 0.55 * lit,
      );
    }
    pDot(ctx, cx + ox * s, cy + oy * s, s * 0.05);
    pFill(ctx, k.alt);
  }
}

// ---------- Prāṇa · Qì ----------

/// No outline at all: a cloud of fine motes that widens on the in-breath,
/// gathers on the out-breath, each mote shimmering on its own clock.
///
/// Prāṇa and qì: the body felt as a shimmering field that widens with the
/// in-breath.
class EnergyMotesFigure extends Figure {
  const EnergyMotesFigure();

  @override
  String get label => 'a shimmering field';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'm': <Map<String, Object?>>[for (var i = 0; i < 120; i++) _mote(r, i)],
  };

  static Map<String, Object?> _mote(SeededRandom r, int i) {
    final d = math.min(
      1.1,
      math.sqrt(-2 * math.log(1 - r.next() * 0.96)) * 0.42,
    );
    return {
      'a': r.range(0, tau),
      'd': d,
      'ph': r.range(0, tau),
      'per': r.range(3, 7),
      'z': r.range(0.012, 0.03),
      'hot': i % 7 == 0,
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), R = s * (0.82 + 0.28 * b);
    pSoft(ctx, cx, cy, R * 1.25, k.glow, 0.22 + 0.12 * b);
    for (final m in p.list('m')) {
      final d = m.d('d');
      final a = m.d('a') + (still ? 0 : t * 0.03 * (1.2 - d)),
          tw = still
              ? 0.7
              : 0.45 +
                    0.55 *
                        (0.5 +
                            0.5 * math.sin(tau * t / m.d('per') + m.d('ph')));
      pDot(
        ctx,
        cx + math.cos(a) * d * R,
        cy + math.sin(a) * d * R * 1.12,
        s * m.d('z'),
      );
      pFill(ctx, m.b('hot') ? k.alt : k.glow, tw * (1 - 0.4 * ss(0.7, 1.1, d)));
    }
  }
}

/// The small circuit: a light rises up the back on the in-breath, pauses
/// at the crown, comes down the front on the out-breath and rests below.
///
/// Qì: a light circling up the back on the in-breath and down the front on
/// the out-breath.
class EnergyOrbitFigure extends Figure {
  const EnergyOrbitFigure();

  @override
  String get label => 'the small circuit';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final rx = s * 0.62, ry = s * 0.98, y0 = cy;
    double phiAt(double tt) {
      final h = 2 * tt / _breath;
      return math.pi / 2 + math.pi * (h.floorToDouble() + easeInOut(frac(h)));
    }

    (double, double) P_(double phi) =>
        (cx + rx * math.cos(phi), y0 + ry * math.sin(phi));
    ctx
      ..beginPath()
      ..ellipse(cx, y0, rx, ry, 0, 0, tau);
    pStroke(ctx, k.main, 0.006, 0.4);
    pSoft(ctx, cx, y0 + ry * 0.62, s * 0.42, k.glow, 0.5);
    pDot(ctx, cx, y0 + ry * 0.62, s * 0.07);
    pFill(ctx, k.alt, 0.85);
    pDot(ctx, cx, y0 - ry, s * 0.03);
    pFill(ctx, k.main, 0.6);
    final tt = still ? 3.4 : t;
    for (var i = 24; i >= 0; i--) {
      final (x, y) = P_(phiAt(tt - i * 0.07));
      pDot(ctx, x, y, s * (0.055 - 0.0016 * i));
      pFill(ctx, i != 0 ? k.glow : k.alt, i != 0 ? 0.55 * (1 - i / 25) : 1);
    }
    final (hx, hy) = P_(phiAt(tt));
    pSoft(ctx, hx, hy, s * 0.28, k.glow, 0.6);
  }
}

// ---------- Focusing ----------

/// Something vague and grey, listened to, comes slowly into focus and
/// warms; at its clearest it shifts — a release goes out — and blurs again.
///
/// Focusing: a vague felt something, listened to, comes clear, and shifts.
class FocusBlurFigure extends Figure {
  const FocusBlurFigure();

  @override
  String get label => 'coming into focus';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final cx = (pl['cx']! as num).toDouble(),
        cy = (pl['cy']! as num).toDouble(),
        s = (pl['s']! as num).toDouble();
    return {...pl, 'blob': makeBlob(r, cx, cy, s * 0.6, 2.6, 0.002)};
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final blob = p.sub('blob');
    final u = still ? 0.3 : frac(t / (2 * _breath)),
        c = 0.5 - 0.5 * math.cos(tau * u),
        col = mix(k.main, k.alt, c);
    pSoft(ctx, cx, cy, s * (1.1 - 0.3 * c), k.glow, 0.25 + 0.25 * c);
    for (var i = 6; i >= 0; i--) {
      blobPath(ctx, blob, grow: 1 + (1 - c) * 0.09 * i, imperf: 1 - 0.3 * c);
      pFill(ctx, col, 0.08 + 0.06 * c);
    }
    blobPath(ctx, blob, imperf: 1 - 0.3 * c);
    pFill(ctx, col, 0.75 * c * c);
    final v = clamp((u - 0.5) / 0.3, 0, 1);
    if (v > 0 && v < 1) {
      blobPath(ctx, blob, grow: 1 + 1.1 * easeOut(v), imperf: 1 - 0.3 * c);
      pStroke(ctx, k.alt, 0.007, 0.8 * fade(v));
    }
  }
}

/// A felt sense, and a word for it held up beside it: too big, too small,
/// closer, until it fits — and both glow, and the felt sense eases.
///
/// Focusing: trying words against the felt sense until one fits, and it
/// eases.
class FocusHandleFigure extends Figure {
  const FocusHandleFigure();

  @override
  String get label => 'a handle that fits';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final cx = (pl['cx']! as num).toDouble(),
        cy = (pl['cy']! as num).toDouble(),
        s = (pl['s']! as num).toDouble();
    return {...pl, 'blob': makeBlob(r, cx, cy, s * 0.5, 2.8, 0.002)};
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final u = still ? 0.7 : frac(t / (3 * _breath)),
        fit = ss(0.5, 0.62, u) * (1 - ss(0.88, 1, u)),
        seek = 1 - ss(0.05, 0.6, u);
    final ease = still ? 1.0 : ss(0.6, 0.8, u) * (1 - ss(0.9, 1, u));
    pSoft(ctx, cx, cy, s * (0.8 + 0.4 * fit), k.glow, 0.2 + 0.45 * fit);
    blobPath(
      ctx,
      p.sub('blob'),
      imperf: 1 - 0.55 * ease,
      grow: 1 + 0.08 * ease,
    );
    pFill(ctx, mix(k.main, k.alt, 0.2 + 0.5 * ease), 0.5 + 0.35 * ease);
    final R = s * 0.62 * (1 + 0.5 * seek * math.sin(u * tau * 2.6)),
        a = (still ? 1.0 : ss(0, 0.08, u)) * (1 - ss(0.86, 0.98, u));
    pDot(ctx, cx, cy, R);
    pStroke(ctx, mix(k.main, k.alt, fit), 0.008 + 0.006 * fit, a);
  }
}
