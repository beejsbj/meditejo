// The page's names (S, BR, B) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'package:medito/services/identity/seeded_random.dart' show easeOut;
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/practice_helpers.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 2 figures kept for the figure library, third part: the two
/// noting label figures, two of the trāṭaka figures and two of the kasiṇa
/// figures (`docs/fork/design/practices/figures-r2.js`, `PracticesR2`).
const Map<String, Figure> practiceLibraryR2c = {
  'trataka_still': TratakaStillFigure(),
  'trataka_point': TratakaPointFigure(),
  'kasina_earth': KasinaEarthFigure(),
  'kasina_extend': KasinaExtendFigure(),
  'noting_notes': NotingNotesFigure(),
  'noting_touch': NotingTouchFigure(),
};

const double _breath = breathPeriod;

final Rgb _black = Rgb.hex('#000000');

// ---------- Noting ----------

/// Round 1's notes, bolder: each label lands in the accent, glows a moment,
/// then settles into the ink and slowly pales until its turn comes again.
///
/// Noting: a soft label for each thing as it comes — rising, falling,
/// hearing.
class NotingNotesFigure extends Figure {
  const NotingNotesFigure();

  @override
  String get label => 'light notes';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'rows': [
      for (var a = 0; a < 3; a++)
        [
          for (var b = 0; b < 6; b++)
            {'w': r.range(0.14, 0.32), 'gap': r.range(0.08, 0.12)},
        ],
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    const per = 1.8;
    const n = 18;
    final now = still ? 10.95 : jsMod(t / per, n.toDouble());
    var idx = 0;
    var ri = 0;
    for (final rowRaw in p.raw('rows')) {
      var x = cx - s * 1.1;
      final y = cy + (ri - 1) * s * 0.5;
      for (final mRaw in rowRaw! as List) {
        final m = P((mRaw! as Map).cast<String, Object?>());
        final age = jsMod(now - idx + n, n.toDouble()),
            w = m.d('w') * s,
            fits = x + w <= cx + s * 1.12;
        if (fits) {
          final grow = age < 1 ? easeOut(age * 1.6) : 1.0,
              a = age < 1 ? 1.0 : math.max(0.32, 1 - (age - 1) / 12);
          if (age < 1.5) {
            pSoft(ctx, x + w / 2, y, s * 0.3, k.glow, 0.45 * fade(age / 1.5));
          }
          pPill(
            ctx,
            x + (w * grow) / 2,
            y,
            math.max(w * grow, 0.001),
            s * 0.11,
            0,
          );
          pFill(ctx, mix(k.alt, k.main, ss(0.8, 2.2, age)), a);
        }
        x += w + m.d('gap') * s;
        idx++;
      }
      ri++;
    }
  }
}

/// Things drift through: a sound, a thought, a touch. Each one, crossing
/// the place of knowing, is touched by a light note and let go.
///
/// Noting: each thing that comes is touched by a light label as it passes,
/// and let go.
class NotingTouchFigure extends Figure {
  const NotingTouchFigure();

  @override
  String get label => 'touched and let go';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) {
    const kinds = ['dot', 'wave', 'ring', 'pair', 'dash', 'wave'];
    const ys = [-0.5, 0.12, -0.15, 0.45, -0.35, 0.28];
    return {
      ...pl,
      'items': [
        for (var i = 0; i < 6; i++)
          {
            'kind': kinds[i],
            'y': ys[i] + r.range(-0.05, 0.05),
            'ph': i / 6 + r.range(-0.03, 0.03),
          },
      ],
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final per = 2.6 * _breath, sz = s * 0.14;
    final items = p.list('items');
    ctx.beginPath();
    ctx.moveTo(cx, cy - s * 0.85);
    ctx.lineTo(cx, cy + s * 0.85);
    pStroke(ctx, k.line, 0.005, 0.35);
    for (final q in items) {
      final u = still
              ? frac(q.d('ph') + 0.5 - items[1].d('ph'))
              : frac(t / per + q.d('ph')),
          x = cx + s * lerp(1.45, -1.45, u),
          y =
              cy +
              q.d('y') * s +
              s * 0.04 * math.sin(u * tau * 2 + q.d('ph') * 9);
      final life = math.pow(fade(u), 0.6).toDouble(),
          noted = math.exp(-math.pow((u - 0.5) / 0.035, 2)),
          after = u > 0.5 ? 0.55 + 0.45 * (1 - (u - 0.5) * 2) : 1.0,
          a = life * after;
      ctx.beginPath();
      final kind = q.s('kind');
      if (kind == 'dot') {
        pDot(ctx, x, y, sz * 0.7);
        pFill(ctx, k.main, a);
      } else if (kind == 'ring') {
        pDot(ctx, x, y, sz * 0.75);
        pStroke(ctx, k.main, 0.01, a);
      } else if (kind == 'pair') {
        pDot(ctx, x - sz * 0.6, y, sz * 0.45);
        pFill(ctx, k.main, a);
        pDot(ctx, x + sz * 0.6, y, sz * 0.45);
        pFill(ctx, k.main, a);
      } else if (kind == 'dash') {
        pPill(ctx, x, y, sz * 2.2, sz * 0.55, 0);
        pFill(ctx, k.main, a);
      } else {
        for (var i = 0; i <= 24; i++) {
          final v = i / 24,
              xx = x + (v - 0.5) * sz * 3,
              yy = y + math.sin(v * tau * 1.5) * sz * 0.5;
          if (i != 0) {
            ctx.lineTo(xx, yy);
          } else {
            ctx.moveTo(xx, yy);
          }
        }
        pStroke(ctx, k.main, 0.011, a);
      }
      if (noted > 0.01) {
        pSoft(ctx, x, y, s * 0.28, k.glow, 0.55 * noted);
        pPill(
          ctx,
          x,
          y - sz * 1.6,
          sz * 1.9 * (0.6 + 0.4 * noted),
          sz * 0.5,
          0,
        );
        pFill(ctx, k.alt, noted);
      }
    }
  }
}

// ---------- Trāṭaka and Kasiṇa ----------

/// Gazing at one black point; then, eyes closed, the same point shows as
/// light in the dark: the afterimage is the negative.
///
/// Trāṭaka: gazing at one dark point, then seeing it within as a point of
/// light.
class TratakaPointFigure extends Figure {
  const TratakaPointFigure();

  @override
  String get label => 'one point, then its light';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'rays': [for (var i = 0; i < 10; i++) tau * i / 10 + r.range(-0.1, 0.1)],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final u = still ? 0.25 : frac(t / (2 * _breath)),
        shut = ss(0.42, 0.6, u) * (1 - ss(0.84, 1, u)),
        ghost = ss(0.56, 0.66, u) * (1 - ss(0.74, 0.88, u)),
        gaze = ss(0, 0.3, u);
    for (final a in p.nums('rays')) {
      final r0 = s * lerp(1.3, 0.28, gaze), r1 = s * 1.4;
      ctx.beginPath();
      ctx.moveTo(cx + math.cos(a) * r0, cy + math.sin(a) * r0);
      ctx.lineTo(cx + math.cos(a) * r1, cy + math.sin(a) * r1);
      pStroke(ctx, k.main, 0.005, 0.35 * (1 - shut));
    }
    pDot(ctx, cx, cy, s * 0.1);
    pFill(ctx, k.main);
    pCloseIn(
      ctx,
      cx,
      cy,
      s,
      pIsLight(k) ? mix(k.main, k.paper, 0.15) : mix(k.paper, _black, 0.5),
      shut * 0.97,
    );
    if (ghost > 0) {
      pSoft(ctx, cx, cy, s * 0.45, k.glow, 0.55 * ghost);
      pDot(ctx, cx, cy, s * 0.1);
      pFill(ctx, mix(k.glow, Rgb.white, 0.4), ghost);
    }
  }
}

/// The flame steadies as the gaze steadies: its sway dies away over a
/// long while, its reflection in the dark beneath goes still, then stirs.
///
/// Trāṭaka: as the gaze steadies, the flame and the mind steady together.
class TratakaStillFigure extends Figure {
  const TratakaStillFigure();

  @override
  String get label => 'a steadying flame';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final calm = still ? 1.0 : 0.5 - 0.5 * math.cos(tau * t / (3 * _breath)),
        sway =
            (1 - calm) *
            (still ? 0.0 : 0.06 * S(t, 2.1) + 0.03 * S(t, 0.77, 1)),
        fy = cy - s * 0.1,
        wy = cy + s * 0.5;
    pSoft(ctx, cx, fy, s * 0.9, k.glow, 0.45 + 0.15 * calm);
    ctx.save();
    ctx.translate(cx, fy + s * 0.3);
    ctx.rotate(sway);
    ctx.translate(-cx, -(fy + s * 0.3));
    pTear(ctx, cx, fy, s * 0.55, s * 0.2);
    pFill(ctx, k.alt);
    pTear(ctx, cx, fy + s * 0.1, s * 0.26, s * 0.085);
    pFill(ctx, k.glow);
    ctx.restore();
    ctx.beginPath();
    ctx.moveTo(cx, fy + s * 0.18);
    ctx.lineTo(cx, fy + s * 0.34);
    pStroke(ctx, k.line, 0.008);
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.2, wy);
    ctx.lineTo(cx + s * 1.2, wy);
    pStroke(ctx, k.main, 0.005, 0.4);
    for (var i = 0; i < 5; i++) {
      final y = wy + s * (0.1 + i * 0.09),
          w =
              s *
              (0.22 - i * 0.03) *
              (1 +
                  (1 - calm) *
                      (still ? 0.0 : 0.5 * S(t, 1.7 + i * 0.4, i.toDouble())));
      pPill(
        ctx,
        cx +
            (1 - calm) *
                s *
                0.06 *
                (still ? 0.0 : S(t, 2.3 + i * 0.3, i.toDouble())),
        y,
        w,
        s * 0.035,
        0,
      );
      pFill(ctx, k.alt, 0.55 - i * 0.09);
    }
  }
}

/// An earth kasiṇa, the colour of dawn: at first a copy with every flaw
/// (the learning sign), it slowly becomes the counterpart sign — smooth,
/// bright, flawless, "like the moon coming out from a cloud".
///
/// Kasiṇa: a disc of dawn-coloured clay, gazed at until its flawless bright
/// sign appears.
class KasinaEarthFigure extends Figure {
  const KasinaEarthFigure();

  @override
  String get label => 'the sign comes clear';

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
      pNum(pl, 'cy'),
      pNum(pl, 's') * 0.68,
      1.6,
      0,
    ),
    'flaws': [
      for (var i = 0; i < 70; i++)
        () {
          final a = r.range(0, tau), d = math.sqrt(r.next()) * 0.6;
          return <String, Object?>{
            'x': math.cos(a) * d,
            'y': math.sin(a) * d,
            'z': r.range(0.01, 0.03),
          };
        }(),
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final pure = still ? 0.45 : 0.5 - 0.5 * math.cos(tau * t / (3 * _breath)),
        b = BR(t, still),
        clay = mix(k.alt, k.main, 0.4),
        bright = mix(k.glow, Rgb.white, 0.45),
        col = mix(clay, bright, ss(0.2, 0.95, pure));
    pSoft(ctx, cx, cy, s * (1.0 + 0.3 * pure), k.glow, 0.15 + 0.5 * pure);
    blobPath(ctx, p.sub('blob'), imperf: 1 - pure, grow: 0.97 + 0.03 * b);
    pFill(ctx, col);
    for (final f in p.list('flaws')) {
      pDot(ctx, cx + f.d('x') * s, cy + f.d('y') * s, s * f.d('z'));
      pFill(ctx, mix(clay, k.main, 0.5), 0.75 * (1 - ss(0, 0.7, pure)));
    }
  }
}

/// The counterpart sign extended: the bright disc grows past each mark,
/// past the edge, till there is nothing but its light; then gathers.
///
/// Kasiṇa: the bright sign extended, a hand's breadth, then further, until
/// it fills everything.
class KasinaExtendFigure extends Figure {
  const KasinaExtendFigure();

  @override
  String get label => 'the sign extended';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final u = still ? 0.35 : 0.5 - 0.5 * math.cos(tau * t / (3 * _breath)),
        R = s * lerp(0.28, 3.2, math.pow(u, 1.6).toDouble()),
        col = mix(k.glow, Rgb.white, 0.35);
    for (final m in const [0.45, 0.8, 1.15]) {
      pDot(ctx, cx, cy, s * m);
      pStroke(ctx, k.main, 0.004, 0.4 * (1 - ss(m * 0.8, m * 1.05, R / s)));
    }
    final g = ctx.createRadialGradient(cx, cy, 0, cx, cy, R * 1.25)
      ..addColorStop(0, css(col, 0.98))
      ..addColorStop(0.78, css(col, 0.95))
      ..addColorStop(1, css(col, 0));
    ctx.fillStyle = g;
    pDot(ctx, cx, cy, R * 1.25);
    ctx.fill();
    pDot(ctx, cx, cy, s * 0.04);
    pFill(ctx, k.alt, 0.8);
  }
}
