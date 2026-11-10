// The page's names (S, BR, B) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'package:medito/services/identity/seeded_random.dart'
    show easeInOut, easeOut;
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/figures.dart';
import 'package:medito/widgets/art/engine/practice_helpers.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 2 of the practice figures (`docs/fork/design/practices/`
/// `figures-r2.js`, `PracticesR2`): the picked ones, ported line for line.
/// Same contract as round 4's figures; every one loops without a seam and
/// has a calm still frame.
const Map<String, Figure> practiceFiguresR2 = {
  'dialogue_ripples': DialogueRipplesFigure(),
  'noting_rise': NotingRiseFigure(),
  'glimpse_part': GlimpsePartFigure(),
  'body_sweep': BodySweepFigure(),
  'energy_field': EnergyFieldFigure(),
  'focus_unfurl': FocusUnfurlFigure(),
  'nidra_waves': NidraWavesFigure(),
  'dzogchen_mirror': DzogchenMirrorFigure(),
  'mahamudra_waves': MahamudraWavesFigure(),
  'trataka_after': TratakaAfterFigure(),
  'kasina_fire': KasinaFireFigure(),
};

const double _breath = breathPeriod;

final Rgb _black = Rgb.hex('#000000');

// ---------- private helpers (figures-r2.js) ----------

// ---------- Insight Dialogue ----------

/// Two sources take turns; neither ring set is the point. Where a ring from
/// one meets a ring from the other, a light appears: those meeting points
/// slide along still curves between them, a shape neither makes alone.
///
/// Insight Dialogue: each speaks and listens in turn; what arises lives
/// where the two meet.
class DialogueRipplesFigure extends Figure {
  const DialogueRipplesFigure();

  @override
  String get label => 'two voices, one field';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'n': 5};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), n = p.i('n');
    final d = s * 0.6,
        per = 1.2 * _breath,
        turn = still ? 0.0 : S(t, 2 * _breath),
        D = 2 * d,
        xL = cx - d,
        xR = cx + d,
        y = cy;
    List<(double, double)> set(double off, double v) => [
      for (var i = 0; i < n; i++)
        () {
          final u = still ? (i + 0.5 + off) / n : frac(t / per + (i + off) / n);
          return (s * (0.06 + 1.3 * u), fade(u) * v);
        }(),
    ];
    final vL = 0.3 + 0.7 * (0.5 + 0.5 * turn),
        vR = 0.3 + 0.7 * (0.5 - 0.5 * turn);
    final L = set(0, vL), R = set(0.5, vR);
    pSoft(ctx, cx, y, s * 0.7, k.glow, 0.18 + 0.12 * BR(t, still));
    for (final q in L) {
      pDot(ctx, xL, y, q.$1);
      pStroke(ctx, k.main, 0.005, 0.55 * q.$2);
    }
    for (final q in R) {
      pDot(ctx, xR, y, q.$1);
      pStroke(ctx, k.main, 0.005, 0.55 * q.$2);
    }
    for (final a in L) {
      for (final b in R) {
        final x = (D * D - b.$1 * b.$1 + a.$1 * a.$1) / (2 * D),
            h2 = a.$1 * a.$1 - x * x;
        if (h2 <= 0) continue;
        final h = math.sqrt(h2), w = math.min(1.0, 1.8 * a.$2 * b.$2);
        for (final sd in const [-1.0, 1.0]) {
          pSoft(ctx, xL + x, y + sd * h, s * 0.12, k.glow, 0.5 * w);
          pDot(ctx, xL + x, y + sd * h, s * 0.034);
          pFill(ctx, k.alt, w);
        }
      }
    }
    for (final (x, v) in [(xL, vL), (xR, vR)]) {
      pSoft(ctx, x, y, s * 0.25, k.glow, 0.5 * v);
      pDot(ctx, x, y, s * 0.06);
      pFill(ctx, k.main);
    }
  }
}

// ---------- Noting ----------

/// A wave of breath scrolls past a mark; as each slope's midpoint reaches
/// the moment of now, it gets its note, pinned to the slope, then fades.
///
/// Noting: “rising… falling…” — each movement of the breath named as it
/// passes.
class NotingRiseFigure extends Figure {
  const NotingRiseFigure();

  @override
  String get label => 'rising, falling';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final lam = s * 1.5,
        kk = tau / lam,
        A = s * 0.36,
        ph = still ? 0.6 : tau * t / _breath,
        x0 = cx - s * 1.25,
        x1 = cx + s * 1.25;
    double yAt(double x) => cy + A * math.sin(kk * (x - cx) + ph);
    ctx.beginPath();
    ctx.moveTo(cx, cy - s * 0.75);
    ctx.lineTo(cx, cy + s * 0.75);
    pStroke(ctx, k.line, 0.005, 0.3);
    for (var x = x0; x < x1; x += 0.004) {
      ctx.beginPath();
      ctx.moveTo(x, yAt(x));
      ctx.lineTo(x + 0.0045, yAt(x + 0.0045));
      pStroke(
        ctx,
        k.main,
        0.012,
        0.95 *
            math.min(1.0, math.min((x - x0) / (s * 0.5), (x1 - x) / (s * 0.5))),
      );
    }
    // slope midpoints sit where the phase is a multiple of π
    final j0 = ((kk * (x0 - cx) + ph) / math.pi).ceil(),
        j1 = ((kk * (cx - cx) + ph) / math.pi).floor();
    for (var j = j0; j <= j1; j++) {
      final x = cx + (j * math.pi - ph) / kk,
          y = yAt(x),
          passed = cx - x,
          born = easeOut(clamp(passed / (s * 0.1), 0, 1)),
          a = born * math.min(1.0, 1 - (passed - s * 0.1) / (s * 1.2));
      final slope = A * kk * math.cos(j * math.pi),
          ang = math.atan(slope),
          rising = slope < 0;
      if (a <= 0) continue;
      if (passed < s * 0.4) {
        pSoft(
          ctx,
          x + math.sin(ang) * s * 0.2 * (rising ? 1 : -1),
          y - math.cos(ang) * s * 0.2 * (rising ? 1 : -1),
          s * 0.3,
          k.glow,
          0.5 * (1 - passed / (s * 0.4)),
        );
      }
      final off = s * 0.2,
          nx = math.sin(ang),
          ny = -math.cos(ang),
          side = rising ? 1.0 : -1.0;
      pPill(
        ctx,
        x + nx * off * side,
        y + ny * off * side,
        s * 0.32 * born,
        s * 0.12,
        ang,
      );
      pFill(ctx, rising ? k.alt : k.main, a);
    }
  }
}

// ---------- Effortless mindfulness ----------

/// Soft veils part to show the clear light that was behind them all along.
///
/// Effortless mindfulness: the clouds part for a moment, and the clear
/// light was there all along.
class GlimpsePartFigure extends Figure {
  const GlimpsePartFigure();

  @override
  String get label => 'a parting cloud';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'cl': [
      for (final (sd, y, w) in const [
        (-1.0, -0.32, 0.95),
        (-1.0, 0.3, 0.8),
        (1.0, -0.22, 0.85),
        (1.0, 0.36, 0.95),
      ])
        {'sd': sd, 'y': y, 'w': w, 'ph': r.range(0, tau)},
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final u = still ? 0.5 : frac(t / (2 * _breath)),
        open = math.pow(fade(u), 1.4).toDouble(),
        veil = pVeil(k);
    pSoft(ctx, cx, cy, s * (0.55 + 0.6 * open), k.glow, 0.25 + 0.5 * open);
    pDot(ctx, cx, cy, s * 0.09 * (0.4 + 0.6 * open));
    pFill(ctx, k.alt, 0.4 + 0.6 * open);
    for (final c in p.list('cl')) {
      final x =
          cx +
          c.d('sd') * s * (0.3 + 0.62 * open) +
          (still ? 0 : s * 0.03 * S(t, 17, c.d('ph')));
      pCloud(ctx, x, cy + c.d('y') * s, s * c.d('w'), veil, 0.78);
    }
  }
}

// ---------- Kāyagatāsati ----------

/// A field of points, not a body: a soft band of attention sweeps down and
/// back up, and each point it passes wakes, then settles.
///
/// Kāyagatāsati: attention sweeping through the body, waking each part as
/// it passes.
class BodySweepFigure extends Figure {
  const BodySweepFigure();

  @override
  String get label => 'a slow sweep';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    final pts = <Map<String, Object?>>[];
    const sp = 0.15;
    for (var row = -8; row <= 8; row++) {
      for (var col = -8; col <= 8; col++) {
        final x = (col + (row.isOdd ? 0.5 : 0)) * sp + r.range(-0.03, 0.03),
            y = row * sp * 0.87 + r.range(-0.03, 0.03),
            d = math.sqrt((x / 0.92) * (x / 0.92) + (y / 1.08) * (y / 1.08));
        if (d < 1) pts.add({'x': x, 'y': y, 'd': d, 'z': r.range(0.75, 1.25)});
      }
    }
    return {...pl, 'pts': pts};
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final u = still ? 0.38 : 0.5 - 0.5 * math.cos(tau * t / (3 * _breath)),
        band = lerp(-1.15, 1.15, u);
    pSoftE(ctx, cx, cy + band * s, s * 1.2, s * 0.3, k.glow, 0.35);
    for (final q in p.list('pts')) {
      final wake = math.exp(-math.pow((q.d('y') - band) / 0.16, 2)),
          edge = 1 - ss(0.82, 1, q.d('d'));
      pDot(
        ctx,
        cx + q.d('x') * s,
        cy + q.d('y') * s,
        s * 0.026 * q.d('z') * (1 + 1.1 * wake),
      );
      pFill(
        ctx,
        mix(k.main, k.alt, ss(0.25, 0.7, wake)),
        (0.38 + 0.62 * wake) * edge,
      );
    }
  }
}

// ---------- Prāṇa · Qì ----------

/// Field lines of one breathing field: light rises through the centre,
/// spills over and returns from below, every line meeting at one point.
///
/// Prāṇa and qì: energy circling through one field that opens and closes
/// with the breath.
class EnergyFieldFigure extends Figure {
  const EnergyFieldFigure();

  @override
  String get label => 'the field';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'L': const [0.42, 0.68, 0.94, 1.2],
    'motes': [
      for (var i = 0; i < 32; i++)
        {
          'li': i % 4,
          'sd': (i >> 2) % 2 != 0 ? 1.0 : -1.0,
          'ph': r.next(),
          'sp': r.range(0.85, 1.15),
        },
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), sc = s * (0.9 + 0.1 * b), sy = 1.75;
    (double, double) at(double L, double th, double sd) {
      final r2 = L * math.pow(math.sin(th), 2);
      return (
        cx + sd * sc * r2 * math.sin(th),
        cy - sc * sy * r2 * math.cos(th),
      );
    }

    final lines = p.nums('L');
    pSoft(ctx, cx, cy, s * (0.8 + 0.3 * b), k.glow, 0.28);
    for (var li = 0; li < lines.length; li++) {
      for (final sd in const [-1.0, 1.0]) {
        ctx.beginPath();
        for (var i = 0; i <= 80; i++) {
          final (x, y) = at(lines[li], 0.02 + (math.pi - 0.04) * i / 80, sd);
          if (i != 0) {
            ctx.lineTo(x, y);
          } else {
            ctx.moveTo(x, y);
          }
        }
        pStroke(ctx, k.main, 0.005, 0.22 + 0.1 * li);
      }
    }
    for (final m in p.list('motes')) {
      final v = still
          ? m.d('ph')
          : frac(t / (2 * _breath) * m.d('sp') + m.d('ph'));
      final (x, y) = at(lines[m.i('li')], math.pi * v, m.d('sd'));
      final a = fade(v);
      pDot(ctx, x, y, s * 0.03 * (0.6 + 0.4 * a));
      pFill(ctx, m.i('li') % 2 != 0 ? k.alt : k.glow, 0.95 * a);
    }
    pSoft(ctx, cx, cy, s * 0.3, k.glow, 0.6 + 0.3 * b);
    pDot(ctx, cx, cy, s * 0.06);
    pFill(ctx, k.alt);
  }
}

// ---------- Focusing ----------

/// A fern's crozier: tightly curled, it unrolls a little with each breath
/// and a long way at the shift, then gathers again. Carrying forward.
///
/// Focusing: the felt shift, something curled up in the body loosening and
/// unfolding.
class FocusUnfurlFigure extends Figure {
  const FocusUnfurlFigure();

  @override
  String get label => 'unfurling';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'lean': r.range(-0.1, 0.05)};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final open = still
        ? 0.35
        : easeInOut(0.5 - 0.5 * math.cos(tau * t / (3 * _breath))) * 0.8 +
              0.2 * BR(t, still);
    const N = 150;
    final Lw = s * 2.6, ds = Lw / N, turn = lerp(3.4, 1.1, open) * math.pi;
    var x = cx - s * 0.3, y = cy + s * 1.15, h = -math.pi / 2 + p.d('lean');
    final pts = <(double, double)>[(x, y)];
    for (var i = 1; i <= N; i++) {
      final v = i / N;
      h += turn * 3.4 * math.pow(v, 2.4) / N;
      x += math.cos(h) * ds;
      y += math.sin(h) * ds;
      pts.add((x, y));
    }
    final tip = pts[N];
    pSoft(
      ctx,
      tip.$1,
      tip.$2,
      s * (0.35 + 0.3 * open),
      k.glow,
      0.3 + 0.35 * open,
    );
    for (var i = 0; i < N; i++) {
      ctx.beginPath();
      ctx.moveTo(pts[i].$1, pts[i].$2);
      ctx.lineTo(pts[i + 1].$1, pts[i + 1].$2);
      pStroke(
        ctx,
        k.main,
        s * lerp(0.16, 0.035, math.pow(i / N, 0.8).toDouble()),
      );
    }
    pDot(ctx, tip.$1, tip.$2, s * 0.05);
    pFill(ctx, k.alt);
  }
}

// ---------- Yoga nidrā ----------

/// One line from waking to sleep: quick small waves slow into long deep
/// ones. A point of awareness rides it all the way and stays bright.
///
/// Yoga nidrā: the mind’s waves slowing towards sleep, with awareness
/// riding them.
class NidraWavesFigure extends Figure {
  const NidraWavesFigure();

  @override
  String get label => 'into the slow waves';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    const N = 220;
    final x0 = cx - s * 1.25,
        x1 = cx + s * 1.25,
        scroll = still ? 0.0 : tau * t / _breath;
    final pts = <(double, double)>[];
    var ph = 0.0;
    for (var i = 0; i <= N; i++) {
      final v = i / N;
      ph += tau * lerp(9, 1.1, math.pow(v, 0.6).toDouble()) / N;
      pts.add((
        lerp(x0, x1, v),
        cy + s * lerp(0.05, 0.42, v) * math.sin(ph - scroll),
      ));
    }
    for (var i = 0; i < N; i++) {
      final v = i / N;
      ctx.beginPath();
      ctx.moveTo(pts[i].$1, pts[i].$2);
      ctx.lineTo(pts[i + 1].$1, pts[i + 1].$2);
      pStroke(
        ctx,
        k.main,
        0.009,
        0.9 * math.min(1.0, math.min(v * 6, (1 - v) * 6)),
      );
    }
    final u = still ? 0.62 : frac(t / (2 * _breath)),
        j = (easeInOut(u) * N).round(),
        a = fade(u);
    final (x, y) = pts[j];
    pSoft(ctx, x, y, s * 0.35, k.glow, 0.65 * a);
    pDot(ctx, x, y, s * 0.055);
    pFill(ctx, k.alt, a);
  }
}

// ---------- Dzogchen and Mahāmudrā ----------

/// The mirror: lights pass before it and show in it, vivid while they are
/// there; the mirror takes nothing and keeps nothing.
///
/// Dzogchen: like a mirror, the mind shows everything and is stained by
/// nothing.
class DzogchenMirrorFigure extends Figure {
  const DzogchenMirrorFigure();

  @override
  String get label => 'the mirror';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'lights': [
      for (var i = 0; i < 5; i++)
        {
          'y': r.range(-0.6, 0.6),
          'ph': i / 5 + r.range(-0.03, 0.03),
          'z': r.range(0.08, 0.14),
          'ci': i,
        },
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still), R = s * 0.85, five = pFive(k);
    pSoft(ctx, cx, cy, R * 1.5, k.glow, 0.2 + 0.08 * b);
    pClearDisc(ctx, cx, cy, R, k, b);
    ctx.save();
    pDot(ctx, cx, cy, R * 0.98);
    ctx.clip();
    for (final l in p.list('lights')) {
      final u = still
              ? frac(l.d('ph') + 0.1)
              : frac(t / (4 * _breath) + l.d('ph')),
          x = cx + s * lerp(-1.3, 1.3, u),
          y = cy + l.d('y') * s,
          col = five[l.i('ci')];
      pSoft(ctx, x, y, s * l.d('z') * 2.6, col, 0.75 * fade(u));
      pDot(ctx, x, y, s * l.d('z') * 0.6);
      pFill(ctx, col, 0.9 * fade(u));
    }
    ctx.restore();
  }
}

/// Waves and water: in the clear disc, waves rise and fall back. They are
/// never anything but the water.
///
/// Mahāmudrā: thoughts rise like waves and fall back; they were never
/// other than the water.
class MahamudraWavesFigure extends Figure {
  const MahamudraWavesFigure();

  @override
  String get label => 'waves are water';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'ph': r.range(0, tau)};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s'), pph = p.d('ph');
    final b = BR(t, still),
        R = s * 0.85,
        rise = still
            ? 0.7
            : math.pow(fade(frac(t / (2 * _breath))), 1.5).toDouble(),
        lvl = cy + s * 0.08;
    pClearDisc(ctx, cx, cy, R, k, b);
    ctx.save();
    pDot(ctx, cx, cy, R * 0.99);
    ctx.clip();
    ctx.beginPath();
    ctx.moveTo(cx - R, cy + R);
    for (var j = 0; j <= 80; j++) {
      final v = j / 80,
          x = cx + (v - 0.5) * 2 * R,
          crest = math.exp(-math.pow((v - 0.5) / 0.3, 2));
      ctx.lineTo(
        x,
        lvl -
            s *
                (0.03 + 0.2 * rise * crest) *
                (0.5 +
                    0.5 *
                        math.cos(
                          tau * (v - 0.5) * 2.5 + (still ? 0 : t * 0.3),
                        )) +
            s * 0.02 * math.sin(tau * v * 3 + pph + (still ? 0 : t * 0.5)),
      );
    }
    ctx.lineTo(cx + R, cy + R);
    ctx.closePath();
    pFill(ctx, mix(k.main, k.paper, 0.45), 0.85);
    ctx.restore();
    pDot(ctx, cx, cy, R);
    pStroke(ctx, k.main, 0.006, 0.5);
  }
}

// ---------- Trāṭaka and Kasiṇa ----------

/// Gazing at the flame without blinking; then the dark closes in, and the
/// flame is still there inside, pale and cool, drifting, fading.
///
/// Trāṭaka: gazing at one flame, then holding its afterimage, pale and
/// cool, within.
class TratakaAfterFigure extends Figure {
  const TratakaAfterFigure();

  @override
  String get label => 'flame, then afterimage';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final u = still ? 0.3 : frac(t / (2 * _breath)),
        shut = ss(0.44, 0.62, u) * (1 - ss(0.84, 1, u)),
        ghost = ss(0.58, 0.68, u) * (1 - ss(0.76, 0.9, u));
    final flick = still
            ? 0.0
            : (0.015 * S(t, 2.3) + 0.008 * S(t, 0.9)) * (1 - shut),
        fy = cy - s * 0.12,
        fx = cx + flick * s;
    final seen = 1 - shut; // eyes closed, the flame itself is gone
    pSoft(ctx, cx, fy, s * 1.0, k.glow, 0.5 * seen);
    pTear(ctx, fx, fy, s * 0.52, s * 0.21);
    pFill(ctx, k.alt, seen);
    pTear(ctx, fx, fy + s * 0.09, s * 0.26, s * 0.09);
    pFill(ctx, k.glow, seen);
    ctx.beginPath();
    ctx.moveTo(cx, fy + s * 0.16);
    ctx.lineTo(cx, fy + s * 0.3);
    pStroke(ctx, k.line, 0.008, seen);
    ctx.beginPath();
    ctx.roundRect(cx - s * 0.15, fy + s * 0.3, s * 0.3, s * 0.72, s * 0.03);
    pFill(ctx, k.main, 0.9 * seen);
    pCloseIn(ctx, cx, cy, s, mix(k.paper, _black, 0.45), shut * 0.96);
    if (ghost > 0) {
      final gy = fy - s * 0.12 * (u - 0.6), cool = mix(k.main, k.paper, 0.15);
      pSoft(ctx, cx, gy, s * 0.6, cool, 0.3 * ghost);
      pTear(ctx, cx, gy, s * 0.48, s * 0.2);
      pFill(ctx, cool, 0.6 * ghost);
    }
  }
}

/// The fire kasiṇa as the texts set it up: a mat with a round hole, and
/// the fire seen only through the hole, a disc of flame.
///
/// Kasiṇa: fire seen through a round hole in a mat, so the eye holds only
/// a disc of flame.
class KasinaFireFigure extends Figure {
  const KasinaFireFigure();

  @override
  String get label => 'fire through the hole';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'fire': {
      ...const FireFigure().build(r, {
        'cx': pNum(pl, 'cx'),
        'cy': pNum(pl, 'cy') - pNum(pl, 's') * 0.1,
        's': pNum(pl, 's') * 0.48,
      }, slot),
      'kind': 'tongues',
      'log': false,
    },
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final R = s * 0.52, b = BR(t, still);
    ctx.save();
    pDot(ctx, cx, cy, R);
    ctx.clip();
    ctx.fillStyle = css(mix(k.alt, k.paper, 0.35));
    ctx.fillRect(cx - R, cy - R, 2 * R, 2 * R);
    const FireFigure().draw(
      ctx,
      p.sub('fire'),
      k.copyWith(main: k.alt, alt: mix(k.glow, Rgb.white, 0.3), line: k.alt),
      t,
      still,
    );
    ctx.restore();
    pSoft(ctx, cx, cy, R * (1.6 + 0.1 * b), k.glow, 0.28);
    cutPoly(
      ctx,
      [
        (cx - s * 1.0, cy - s * 0.95),
        (cx + s * 1.02, cy - s * 0.98),
        (cx + s * 0.98, cy + s * 0.96),
        (cx - s * 1.03, cy + s * 0.98),
      ],
      SeededRandom('mat'),
      0.006,
    );
    ctx.moveTo(cx + R, cy);
    // The page's `arc(cx, cy, R, 0, TAU, true)`: a full anticlockwise turn.
    // Canvas 2D takes (0, TAU) anticlockwise as a whole circle; Ctx.arc reads
    // it as no sweep, so the end angle is -TAU, the same circle spelled so
    // Ctx draws it.
    ctx.arc(cx, cy, R, 0, -tau, true);
    pFill(ctx, mix(k.paper, k.main, 0.22), 0.96);
    pDot(ctx, cx, cy, R);
    pStroke(ctx, k.glow, 0.008, 0.5 + 0.2 * b);
  }
}
