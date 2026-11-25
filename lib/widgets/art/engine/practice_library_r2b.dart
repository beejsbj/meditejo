// The page's names (S, BR, B) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/practice_helpers.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 2's library figures, second batch (`docs/fork/design/practices/`
/// `figures-r2.js`, `PracticesR2`): yoga nidrā, the Headless Way, Dzogchen
/// and Mahāmudrā, ported line for line.
const Map<String, Figure> practiceLibraryR2b = {
  'nidra_sheaths': NidraSheathsFigure(),
  'nidra_moon': NidraMoonFigure(),
  'headless_eye': HeadlessEyeFigure(),
  'headless_face': HeadlessFaceFigure(),
  'headless_point': HeadlessPointFigure(),
  'dzogchen_thigle': DzogchenThigleFigure(),
  'dzogchen_rainbow': DzogchenRainbowFigure(),
  'mahamudra_recognise': MahamudraRecogniseFigure(),
  'mahamudra_taste': MahamudraTasteFigure(),
};

const double _breath = breathPeriod;

// ---------- Yoga nidrā ----------

/// Five sheaths, outermost first, settle from restless waves to stillness,
/// one after another; above them, one point of awareness stays lit.
///
/// Yoga nidrā: layer after layer settles into rest, and awareness stays
/// awake.
class NidraSheathsFigure extends Figure {
  const NidraSheathsFigure();

  @override
  String get label => 'five sheaths settling';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'ph': [for (var i = 0; i < 5; i++) r.range(0, tau)],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), phs = p.nums('ph');
    final depth = still ? 0.55 : 0.5 - 0.5 * math.cos(tau * t / (3 * _breath)),
        b = BR(t, still),
        ay = cy - s * 0.92;
    for (var i = 0; i < 5; i++) {
      final settle = ss(i * 0.12, i * 0.12 + 0.45, depth),
          y = cy + s * (0.92 - i * 0.34 + 0.05 * settle),
          A = s * (0.13 * (1 - settle) + 0.008);
      ctx.beginPath();
      for (var j = 0; j <= 60; j++) {
        final v = j / 60, x = cx + s * lerp(-1.15, 1.15, v);
        final yy =
            y +
            A *
                math.sin(
                  tau * v * (1.6 + 0.3 * i) + phs[i] + (still ? 0 : t * 0.35),
                ) *
                fade(v);
        if (j == 0) {
          ctx.moveTo(x, yy);
        } else {
          ctx.lineTo(x, yy);
        }
      }
      pStroke(ctx, k.main, 0.008, 0.35 + 0.45 * (1 - i / 5));
    }
    pSoft(
      ctx,
      cx,
      ay,
      s * (0.3 + 0.25 * depth + 0.05 * b),
      k.glow,
      0.5 + 0.3 * depth,
    );
    pDot(ctx, cx, ay, s * 0.06);
    pFill(ctx, k.alt);
  }
}

/// A level line, lying down; the moon sinks towards it and rises again;
/// on the line one small light keeps watch the whole night.
///
/// Yoga nidrā: lying level at the edge of sleep, with one light that stays
/// awake.
class NidraMoonFigure extends Figure {
  const NidraMoonFigure();

  @override
  String get label => 'the edge of sleep';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'bars': [for (var i = 0; i < 4; i++) r.range(0, tau)],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), bars = p.nums('bars');
    final hy = cy + s * 0.38,
        sink = still ? 0.45 : 0.5 - 0.5 * math.cos(tau * t / (3 * _breath)),
        mx = cx + s * 0.45,
        my = lerp(cy - s * 0.75, hy - s * 0.28, sink),
        R = s * 0.2;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, 1, hy);
    ctx.clip();
    pSoft(ctx, mx, my, s * 0.6, k.glow, 0.35);
    ctx.beginPath();
    ctx.arc(mx, my, R, 0, tau);
    // The page's `arc(..., 0, TAU, true)`: a full anticlockwise circle, which
    // cuts the crescent (nonzero winding). Ctx.arc takes it as -TAU.
    ctx.arc(mx + R * 0.42, my - R * 0.22, R * 0.86, 0, -tau, true);
    pFill(ctx, k.alt);
    ctx.restore();
    for (var i = 0; i < bars.length; i++) {
      final ph = bars[i],
          y = hy + s * (0.1 + i * 0.1),
          w =
              s *
              (0.36 - i * 0.06) *
              (1 + (still ? 0 : 0.2 * S(t, 6.0 + i, ph)));
      pPill(ctx, mx, y, w, s * 0.035, 0);
      pFill(ctx, k.alt, (0.5 - i * 0.1) * (1 - 0.5 * sink));
    }
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.25, hy);
    ctx.lineTo(cx + s * 1.25, hy);
    pStroke(ctx, k.main, 0.008, 0.75);
    final lx = cx - s * 0.55;
    pSoft(ctx, lx, hy, s * (0.3 + 0.05 * BR(t, still)), k.glow, 0.7);
    pDot(ctx, lx, hy - s * 0.02, s * 0.05);
    pFill(ctx, k.glow);
  }
}

// ---------- Headless Way ----------

/// The single eye: the world, vivid inside a wide open space with no
/// edge, fading to nothing all round. The space breathes.
///
/// The Headless Way: looking out from no head — one wide open space, full
/// of the world.
class HeadlessEyeFigure extends Figure {
  const HeadlessEyeFigure();

  @override
  String get label => 'the single eye';

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
        rx = s * (1.6 + 0.12 * b),
        ry = s * 1.05 * (1 + 0.05 * b);
    pDot(ctx, cx + s * 0.35, cy - s * 0.2, s * 0.1);
    pFill(ctx, k.alt);
    pSoft(ctx, cx + s * 0.35, cy - s * 0.2, s * 0.4, k.glow, 0.45);
    ctx.save();
    ctx.translate(cx, cy);
    ctx.scale(1, ry / rx);
    final g = ctx.createRadialGradient(0, 0, 0, 0, 0, rx)
      ..addColorStop(0, css(k.paper, 0))
      ..addColorStop(0.62, css(k.paper, 0))
      ..addColorStop(0.95, css(k.paper, 0.92))
      ..addColorStop(1, css(k.paper, 1));
    ctx.fillStyle = g;
    ctx.fillRect(-2, -4, 4, 8);
    ctx.restore();
  }
}

/// Face to no-face: over there, a face, solid; here, no face — open space
/// with that face, and the world, in it.
///
/// The Headless Way: there, a face; here, no face — open space, with the
/// world in it.
class HeadlessFaceFigure extends Figure {
  const HeadlessFaceFigure();

  @override
  String get label => 'face to no-face';

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
        R = s * 0.46,
        lx = cx - s * 0.56,
        rx = cx + s * 0.6,
        y = cy;
    pDot(ctx, rx, y, R);
    pFill(ctx, k.main);
    pSoft(ctx, lx, y, R * (1.5 + 0.15 * b), k.glow, 0.45 + 0.1 * b);
    ctx.save();
    pDot(ctx, lx, y, R * 1.06);
    ctx.clip();
    pSoft(
      ctx,
      lx,
      y,
      R * 1.15,
      mix(k.paper, Rgb.white, pIsLight(k) ? 0.6 : 0.1),
      0.95,
    );
    ctx.beginPath();
    ctx.moveTo(lx - R * 1.2, y + R * 0.42);
    ctx.quadraticCurveTo(lx, y + R * 0.3, lx + R * 1.2, y + R * 0.46);
    ctx.lineTo(lx + R * 1.2, y + R * 1.2);
    ctx.lineTo(lx - R * 1.2, y + R * 1.2);
    ctx.closePath();
    pFill(ctx, k.line, 0.22);
    pDot(ctx, lx - R * 0.45, y - R * 0.38, R * 0.14);
    pFill(ctx, k.alt);
    pDot(ctx, lx + R * 0.22, y - R * 0.02, R * (0.36 + 0.03 * b));
    pFill(ctx, k.main, 0.9);
    ctx.restore();
    ctx.setLineDash([0.006, 0.012]);
    pDot(ctx, lx, y, R * 1.06);
    pStroke(ctx, k.main, 0.004, 0.45);
    ctx.setLineDash([]);
  }
}

/// Pointing at things: each is solid, a thing. Then pointing back here,
/// where the head should be — and finding open space, full of the things.
///
/// The Headless Way: point at things, each a thing; point back here, and
/// find open space.
class HeadlessPointFigure extends Figure {
  const HeadlessPointFigure();

  @override
  String get label => 'pointing back';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'things': <Map<String, Object?>>[
      {'x': -0.95, 'y': 0.42, 'z': 0.11},
      {'x': -0.62, 'y': -0.32, 'z': 0.09},
      {'x': 0.92, 'y': 0.18, 'z': 0.12},
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final things = p.list('things');
    final px = cx, py = cy + s * 0.72, top = (cx, cy - s * 0.62), R = s * 0.34;
    final targets = [
      for (final q in things) (cx + q.d('x') * s, cy + q.d('y') * s),
      top,
    ];
    final ang = [for (final (x, y) in targets) math.atan2(y - py, x - px)];
    final h = still ? 3.0 : frac(t / (3 * _breath)) * 4,
        i = h.floor(),
        f = ss(0.6, 1, h - i),
        a = lerp(ang[i], ang[(i + 1) % 4], f);
    double on(int j) => j == i
        ? 1 - f
        : j == (i + 1) % 4
        ? f
        : 0;
    final back = on(3);
    pSoft(
      ctx,
      top.$1,
      top.$2,
      R * (1.4 + 0.5 * back),
      k.glow,
      0.15 + 0.5 * back,
    );
    pDot(ctx, top.$1, top.$2, R);
    pStroke(ctx, k.main, 0.006, 0.35 + 0.4 * back);
    for (var j = 0; j < things.length; j++) {
      final x = things[j].d('x'), y = things[j].d('y'), z = things[j].d('z');
      final tx = cx + x * s, ty = cy + y * s;
      if (on(j) > 0.01) pSoft(ctx, tx, ty, s * 0.3, k.glow, 0.45 * on(j));
      pDot(ctx, tx, ty, s * z);
      pFill(ctx, k.main);
      pDot(ctx, top.$1 + x * R * 0.42, top.$2 + y * R * 0.42, s * z * 0.35);
      pFill(ctx, k.main, 0.75 * back);
    }
    final L = s * 0.55, ex = px + math.cos(a) * L, ey = py + math.sin(a) * L;
    ctx.beginPath();
    ctx.moveTo(px, py);
    ctx.lineTo(ex, ey);
    pStroke(ctx, k.alt, 0.012);
    ctx.beginPath();
    ctx.moveTo(ex + math.cos(a) * s * 0.09, ey + math.sin(a) * s * 0.09);
    ctx.lineTo(
      ex + math.cos(a + 2.4) * s * 0.07,
      ey + math.sin(a + 2.4) * s * 0.07,
    );
    ctx.lineTo(
      ex + math.cos(a - 2.4) * s * 0.07,
      ey + math.sin(a - 2.4) * s * 0.07,
    );
    ctx.closePath();
    pFill(ctx, k.alt);
    pDot(ctx, px, py, s * 0.05);
    pFill(ctx, k.alt);
  }
}

// ---------- Dzogchen and Mahāmudrā ----------

/// The thigle: a sphere of five lights, open at the centre, its light
/// welling outward from nowhere, ring after ring, on the breath.
///
/// Dzogchen: the mind’s nature, open at the centre, its light arising by
/// itself.
class DzogchenThigleFigure extends Figure {
  const DzogchenThigleFigure();

  @override
  String get label => 'a sphere of five lights';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), five = pFive(k);
    pSoft(ctx, cx, cy, s * 1.3, k.glow, 0.25 + 0.1 * b);
    for (var i = 0; i < 5; i++) {
      final w = still
              ? 0.6
              : 0.35 +
                    0.65 *
                        math
                            .pow(fade(frac(t / (2 * _breath) - i / 7)), 2)
                            .toDouble(),
          R = s * (0.48 + 0.14 * i) * (0.97 + 0.03 * b);
      pDot(ctx, cx, cy, R);
      pStroke(ctx, five[i], 0.011 + 0.006 * w, 0.4 + 0.55 * w);
    }
    pDot(ctx, cx, cy, s * (0.045 + 0.015 * b));
    pFill(ctx, k.glow);
  }
}

/// An empty sky; a rainbow forms in it from nothing and goes back to
/// nothing. Nothing made it, nothing holds it.
///
/// Dzogchen: like a rainbow in open sky, appearance arising by itself from
/// openness.
class DzogchenRainbowFigure extends Figure {
  const DzogchenRainbowFigure();

  @override
  String get label => 'a rainbow in open sky';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final v = still
            ? 1.0
            : math.pow(fade(frac(t / (3 * _breath))), 1.4).toDouble(),
        five = pFive(k),
        x = cx,
        y = cy + s * 0.75,
        R = s * 1.05;
    pSoft(ctx, x, y - R * 0.6, s * 1.2, k.glow, 0.2 * v);
    for (var i = 0; i < 5; i++) {
      const M = 60;
      for (var j = 0; j < M; j++) {
        final a0 = math.pi + math.pi * j / M,
            ends = math.pow(math.sin(math.pi * (j + 0.5) / M), 0.6).toDouble();
        ctx.beginPath();
        ctx.arc(x, y, R - i * s * 0.055, a0, a0 + math.pi / M + 0.01);
        pStroke(ctx, five[4 - i], s * 0.055, 0.75 * v * ends);
      }
    }
  }
}

/// Whatever arises in the disc — a wave, a scatter, a loop — shows first
/// in its own colour; recognised, it takes the disc's colour and is gone.
///
/// Mahāmudrā: whatever arises is recognised as mind itself, and settles
/// back into it.
class MahamudraRecogniseFigure extends Figure {
  const MahamudraRecogniseFigure();

  @override
  String get label => 'recognised as mind';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'dots': <Map<String, Object?>>[
      for (var i = 0; i < 7; i++)
        {'x': r.range(-0.4, 0.4), 'y': r.range(-0.3, 0.3)},
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still),
        R = s * 0.85,
        h = still ? 0.42 : frac(t / (3 * _breath)) * 3,
        i = h.floor(),
        u = h - i;
    final shown = ss(0, 0.2, u) * (1 - ss(0.7, 0.95, u)),
        known = ss(0.3, 0.55, u),
        col = mix(k.alt, mix(k.paper, k.main, 0.35), known);
    pSoft(ctx, cx, cy, R * 1.5, k.glow, 0.18 + 0.12 * known * shown);
    pClearDisc(ctx, cx, cy, R, k, b);
    pDot(ctx, cx, cy, R * (1 + 0.04 * fade((u - 0.3) / 0.35)));
    pStroke(ctx, k.glow, 0.012, 0.8 * fade((u - 0.3) / 0.35));
    final sc = s * (0.9 + 0.1 * shown);
    ctx.beginPath();
    if (i == 0) {
      for (var j = 0; j <= 40; j++) {
        final v = j / 40,
            x = cx + (v - 0.5) * sc * 1.0,
            y = cy + math.sin(v * tau * 1.5) * sc * 0.14;
        if (j == 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      pStroke(ctx, col, 0.014, shown);
    } else if (i == 1) {
      for (final q in p.list('dots')) {
        pDot(ctx, cx + q.d('x') * sc, cy + q.d('y') * sc, s * 0.045);
        pFill(ctx, col, shown);
      }
    } else {
      ctx.ellipse(cx, cy, sc * 0.32, sc * 0.2, 0.4, 0, tau);
      pStroke(ctx, col, 0.014, shown);
    }
  }
}

/// One taste: shapes of every kind and colour drift in, lose their
/// difference, and are one light at the centre.
///
/// Mahāmudrā: every kind of experience, met fully, has one taste — the
/// mind’s own.
class MahamudraTasteFigure extends Figure {
  const MahamudraTasteFigure();

  @override
  String get label => 'one taste';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'items': <Map<String, Object?>>[
      for (var i = 0; i < 6; i++)
        {'a': tau * i / 6 + r.range(-0.3, 0.3), 'ph': i / 6, 'kind': i % 3},
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), five = pFive(k), core = mix(k.glow, Rgb.white, 0.3);
    pSoft(ctx, cx, cy, s * (0.9 + 0.15 * b), k.glow, 0.45);
    final items = p.list('items');
    for (var i = 0; i < items.length; i++) {
      final q = items[i], qa = q.d('a'), qph = q.d('ph'), kind = q.i('kind');
      final u = still ? frac(qph + 0.3) : frac(t / (3 * _breath) + qph),
          d = s * 1.15 * (1 - math.pow(u, 1.6).toDouble()),
          x = cx + math.cos(qa + u * 0.8) * d,
          y = cy + math.sin(qa + u * 0.8) * d;
      final same = ss(0.35, 0.9, u),
          col = mix(five[1 + (i % 4)], core, same),
          a = ss(0, 0.12, u) * (1 - ss(0.9, 1, u)),
          z = s * 0.1 * (1 - 0.5 * same);
      ctx.beginPath();
      if (kind == 0 || same > 0.8) {
        pDot(ctx, x, y, z * 0.7);
        pFill(ctx, col, a);
      } else if (kind == 1) {
        pDot(ctx, x, y, z);
        pStroke(ctx, col, 0.01, a);
      } else {
        for (var j = 0; j <= 16; j++) {
          final v = j / 16;
          final xx = x + (v - 0.5) * z * 3 * (1 - same),
              yy = y + math.sin(v * tau) * z * 0.6 * (1 - same);
          if (j == 0) {
            ctx.moveTo(xx, yy);
          } else {
            ctx.lineTo(xx, yy);
          }
        }
        pStroke(ctx, col, 0.011, a);
      }
    }
    pDot(ctx, cx, cy, s * (0.2 + 0.03 * b));
    pFill(ctx, core, 0.95);
  }
}
