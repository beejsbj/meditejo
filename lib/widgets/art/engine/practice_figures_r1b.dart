// The page's names (S, BR, H, R) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names

import 'dart:math' as math;

import 'package:medito/services/identity/seeded_random.dart' show easeInOut;
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/figures.dart';
import 'package:medito/widgets/art/engine/practice_helpers.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 1's practice figures, second half (`figures.js`, `F.<name>`):
/// inquiry, flow, coil, wheels, chant, mala, offering, image, soul.

/// Noise functions are rebuilt from a stored seed, so params stay plain
/// data; cached per params map (`nz`).
final Expando<double Function(double)> _nzCache = Expando('nz');

double Function(double) _nzOf(P p) =>
    _nzCache[p.m] ??= rngOf(p['nzSeed']!).noise(2);

// ---------------- awareness ----------------

/// Ātma-vicāra: “Who am I?” — following attention back to its source.
class InquiryFigure extends Figure {
  const InquiryFigure();

  @override
  String get label => 'turning inward';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final per = 2 * breathPeriod,
        u = still ? 0.55 : frac(t / per),
        turns = 2.6,
        M = 220;
    ctx.beginPath();
    for (var i = 0; i <= M; i++) {
      final v = i / M,
          a = -tau * turns * v - (still ? 0 : t * 0.15),
          rr = s * 1.0 * math.pow(1 - v, 1.15);
      final x = cx + math.cos(a) * rr, y = cy + math.sin(a) * rr;
      if (i != 0) {
        ctx.lineTo(x, y);
      } else {
        ctx.moveTo(x, y);
      }
    }
    pStroke(ctx, k.main, 0.01, 0.75);
    final v = easeInOut(u),
        a = -tau * turns * v - (still ? 0 : t * 0.15),
        rr = s * math.pow(1 - v, 1.15);
    pDot(ctx, cx + math.cos(a) * rr, cy + math.sin(a) * rr, s * 0.06);
    pFill(ctx, k.alt, fade(u));
    pSoft(ctx, cx, cy, s * 0.35, k.glow, 0.3 + 0.4 * math.pow(u, 3));
  }
}

// ---------------- body & energy ----------------

/// Qìgōng and yoga: slow movement, breath and attention as one line.
class FlowFigure extends Figure {
  const FlowFigure();

  @override
  String get label => 'a flowing line';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final per = 2 * breathPeriod, M = 90, head = still ? 0.4 : t / per;
    for (var i = 0; i < M; i++) {
      final v = head - i / M * 0.55, a = tau * v;
      final x = cx + math.sin(a) * s * 0.95,
          y = cy + math.sin(2 * a) * s * 0.42;
      pDot(ctx, x, y, s * 0.06 * (1 - i / M));
      pFill(ctx, i < 3 ? k.alt : k.main, 0.9 * (1 - i / M));
    }
    ctx.beginPath();
    for (var i = 0; i <= 120; i++) {
      final a = tau * i / 120,
          x = cx + math.sin(a) * s * 0.95,
          y = cy + math.sin(2 * a) * s * 0.42;
      if (i != 0) {
        ctx.lineTo(x, y);
      } else {
        ctx.moveTo(x, y);
      }
    }
    pStroke(ctx, k.line, 0.004, 0.3);
  }
}

/// Kuṇḍalinī: the coiled energy at the base, rising up the spine.
class CoilFigure extends Figure {
  const CoilFigure();

  @override
  String get label => 'uncoiling upward';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final base = cy + s * 0.85,
        top = cy - s * 0.95,
        per = 2 * breathPeriod,
        u = still ? 0.6 : 0.5 - 0.5 * math.cos(tau * t / per),
        reach = lerp(base, top, u);
    ctx.beginPath();
    ctx.moveTo(cx, base);
    ctx.lineTo(cx, top);
    pStroke(ctx, k.line, 0.006, 0.35);
    ctx.beginPath();
    for (var i = 0; i <= 80; i++) {
      final v = i / 80, a = tau * 2.2 * v, rr = s * 0.3 * (1 - v * 0.6);
      final x = cx + math.cos(a) * rr,
          y = base - s * 0.08 + math.sin(a) * rr * 0.35 - v * s * 0.12;
      if (i != 0) {
        ctx.lineTo(x, y);
      } else {
        ctx.moveTo(x, y);
      }
    }
    pStroke(ctx, k.main, 0.014, 0.85);
    ctx.beginPath();
    for (var i = 0; i <= 80; i++) {
      final v = i / 80, y = lerp(base - s * 0.2, reach, v);
      final x =
          cx +
          s *
              0.16 *
              math.sin(v * tau * 2.5 - (still ? 0 : t * 0.8)) *
              (1 - v * 0.4);
      if (i != 0) {
        ctx.lineTo(x, y);
      } else {
        ctx.moveTo(x, y);
      }
    }
    pStroke(ctx, k.alt, 0.016, 0.9);
    pSoft(ctx, cx, reach, s * 0.35, k.glow, 0.7);
    pDot(ctx, cx, reach, s * 0.06);
    pFill(ctx, k.glow);
  }
}

/// Cakra: wheels of energy along the body’s centre, attended one by one.
class WheelsFigure extends Figure {
  const WheelsFigure();

  @override
  String get label => 'seven wheels';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final per = 3.5 * breathPeriod, at = still ? 3.4 : jsMod(t / per * 7, 7);
    ctx.beginPath();
    ctx.moveTo(cx, cy - s * 1.0);
    ctx.lineTo(cx, cy + s * 1.0);
    pStroke(ctx, k.line, 0.005, 0.35);
    for (var i = 0; i < 7; i++) {
      final y = cy + s * (0.92 - 1.84 * i / 6),
          lit = math.max(0.0, 1 - (at - i).abs() * 0.9),
          r = s * (0.11 + 0.04 * lit),
          rot = (still ? 0 : t * 0.25) * (i.isOdd ? 1 : -1);
      if (lit > 0) pSoft(ctx, cx, y, r * 3.2, k.glow, 0.6 * lit);
      pDot(ctx, cx, y, r);
      pStroke(ctx, lit > 0.5 ? k.alt : k.main, 0.01, 0.6 + 0.4 * lit);
      for (var j = 0; j < 6; j++) {
        final a = rot + tau * j / 6;
        ctx.beginPath();
        ctx.moveTo(cx, y);
        ctx.lineTo(cx + math.cos(a) * r, y + math.sin(a) * r);
        pStroke(ctx, k.main, 0.005, 0.45 + 0.4 * lit);
      }
    }
  }
}

// ---------------- sound & devotion ----------------

/// Chanting: the voice carried out in rhythm, together.
class ChantFigure extends Figure {
  const ChantFigure();

  @override
  String get label => 'voice in rhythm';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final beat = 1.4, x0 = cx - s * 0.7;
    pSoft(ctx, x0, cy, s * 0.35, k.glow, 0.5);
    pDot(ctx, x0, cy, s * 0.1);
    pFill(ctx, k.alt);
    for (var i = 0; i < 5; i++) {
      final u = still ? 0.15 + i * 0.18 : frac(t / (beat * 4) + i / 5),
          r = s * (0.2 + 1.6 * u),
          w = 0.7 - 0.25 * u;
      ctx.beginPath();
      ctx.arc(x0, cy, r, -w, w);
      pStroke(ctx, k.main, 0.012 * (1 - u) + 0.004, fade(u) * 0.95);
    }
  }
}

/// Mantra and japa: one repetition, one bead, round and round.
class MalaFigure extends Figure {
  const MalaFigure();

  @override
  String get label => 'beads of a mālā';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'n': 27};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final n = p.i('n');
    final at = still ? 9.0 : jsMod((t / 1.25).floorToDouble(), n.toDouble()),
        R = s * 0.85;
    for (var i = 0; i < n; i++) {
      final a = math.pi / 2 + tau * (i + 0.5) / (n + 1),
          x = cx + math.cos(a) * R,
          y = cy - s * 0.05 + math.sin(a) * R * 0.95,
          cur = i == at;
      if (cur) pSoft(ctx, x, y, s * 0.22, k.glow, 0.7);
      pDot(ctx, x, y, s * (cur ? 0.085 : 0.06));
      pFill(ctx, cur ? k.alt : k.main, i <= at ? 1 : 0.55);
    }
    final gy = cy - s * 0.05 + R * 0.95;
    pDot(ctx, cx, gy + s * 0.02, s * 0.1);
    pFill(ctx, k.alt);
    ctx.beginPath();
    ctx.moveTo(cx, gy + s * 0.1);
    ctx.lineTo(cx - s * 0.06, gy + s * 0.32);
    ctx.lineTo(cx + s * 0.06, gy + s * 0.32);
    ctx.closePath();
    pFill(ctx, k.alt, 0.8);
  }
}

/// Bhakti and pūjā: an offering made, and incense rising.
class OfferingFigure extends Figure {
  const OfferingFigure();

  @override
  String get label => 'an offering';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {...pl, 'nzSeed': r.next()};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final by = cy + s * 0.55, n = _nzOf(p);
    ctx.beginPath();
    ctx.moveTo(cx - s * 0.55, by - s * 0.1);
    ctx.quadraticCurveTo(cx, by + s * 0.45, cx + s * 0.55, by - s * 0.1);
    ctx.closePath();
    pFill(ctx, k.main);
    ctx.beginPath();
    ctx.ellipse(cx, by + s * 0.28, s * 0.2, s * 0.04, 0, 0, tau);
    pFill(ctx, k.main);
    const dxs = [-0.22, 0.0, 0.22];
    for (var i = 0; i < dxs.length; i++) {
      pDot(
        ctx,
        cx + dxs[i] * s,
        by - s * (0.16 + (i == 1 ? 0.06 : 0)),
        s * 0.1,
      );
      pFill(ctx, i == 1 ? k.alt : mix(k.alt, k.main, 0.4));
    }
    ctx.beginPath();
    ctx.moveTo(cx + s * 0.42, by - s * 0.08);
    ctx.lineTo(cx + s * 0.52, by - s * 0.85);
    pStroke(ctx, k.line, 0.008);
    final tipX = cx + s * 0.52, tipY = by - s * 0.85;
    pDot(ctx, tipX, tipY, s * 0.025);
    pFill(ctx, k.glow);
    ctx.beginPath();
    for (var i = 0; i <= 60; i++) {
      final v = i / 60, y = tipY - v * s * 1.0;
      final x =
          tipX +
          s * 0.18 * v * math.sin(v * 5 - (still ? 0 : t * 0.6)) +
          s * 0.08 * n(v * 3 + (still ? 0 : t * 0.05));
      if (i != 0) {
        ctx.lineTo(x, y);
      } else {
        ctx.moveTo(x, y);
      }
    }
    pStroke(ctx, k.main, 0.006, 0.55);
  }
}

// ---------------- imagination ----------------

/// Visualisation: an image gathered from light, held, and let go.
class ImageFigure extends Figure {
  const ImageFigure();

  @override
  String get label => 'an image forming';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'lotus': const LotusFigure().build(r, {
      ...pl,
      's': pNum(pl, 's') * 0.85,
    }, slot),
    'motes': [
      for (var i = 0; i < 30; i++)
        <String, Object?>{
          'a': r.range(0, tau),
          'd': r.range(0.3, 1.1),
          'ph': r.next(),
        },
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final per = 3 * breathPeriod,
        u = still ? 0.5 : frac(t / per),
        form = math.pow(fade(u), 0.7).toDouble();
    for (final m in p.list('motes')) {
      final rr = s * m.d('d') * (1.3 - form),
          a = m.d('a') + (still ? 0 : t * 0.05);
      pDot(ctx, cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.8, s * 0.025);
      pFill(ctx, k.alt, 0.8 * (1 - form) + 0.1);
    }
    pSoft(ctx, cx, cy, s * 0.9, k.glow, 0.35 * form);
    ctx.save();
    ctx.globalAlpha = form;
    const LotusFigure().draw(ctx, p.sub('lotus'), k, t, still);
    ctx.restore();
  }
}

/// Soulmaking: an imaginal doorway, warm with meaning, that changes how
/// things look.
class SoulFigure extends Figure {
  const SoulFigure();

  @override
  String get label => 'an image with soul';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> pl,
    String slot,
  ) => {
    ...pl,
    'petals': [
      for (var i = 0; i < 9; i++)
        <String, Object?>{
          'x': r.range(-0.4, 0.4),
          'ph': r.next(),
          'per': r.range(8, 14),
          'sz': r.range(0.04, 0.07),
        },
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final cx = p.d('cx'), cy = p.d('cy'), s = p.d('s');
    final b = BR(t, still),
        w = s * 0.62,
        h = s * 1.6,
        x0 = cx - w / 2,
        y0 = cy - h / 2 + s * 0.08;
    void arch() {
      ctx.beginPath();
      ctx.moveTo(x0, y0 + h);
      ctx.lineTo(x0, y0 + w / 2);
      ctx.arc(cx, y0 + w / 2, w / 2, math.pi, 0);
      ctx.lineTo(x0 + w, y0 + h);
      ctx.closePath();
    }

    arch();
    pFill(ctx, k.main, 0.22);
    ctx.save();
    arch();
    ctx.clip();
    pSoft(ctx, cx, y0 + h * 0.42, s * (0.55 + 0.15 * b), k.glow, 0.85);
    pDot(ctx, cx, y0 + h * 0.42, s * (0.14 + 0.02 * b));
    pFill(ctx, k.alt);
    for (final q in p.list('petals')) {
      final u = still ? q.d('ph') : frac(t / q.d('per') + q.d('ph')),
          x = cx + q.d('x') * s + s * 0.08 * math.sin(u * tau * 1.5),
          y = y0 + h * (0.05 + 0.95 * u);
      ctx.beginPath();
      ctx.ellipse(x, y, s * q.d('sz'), s * q.d('sz') * 0.5, u * 4, 0, tau);
      pFill(ctx, k.alt, 0.8 * fade(u));
    }
    ctx.restore();
    arch();
    pStroke(ctx, k.line, 0.012, 0.9);
  }
}

/// Round 1's second half of the practice figures, by their JS names.
const Map<String, Figure> practiceFiguresR1b = {
  'inquiry': InquiryFigure(),
  'flow': FlowFigure(),
  'coil': CoilFigure(),
  'wheels': WheelsFigure(),
  'chant': ChantFigure(),
  'mala': MalaFigure(),
  'offering': OfferingFigure(),
  'image': ImageFigure(),
  'soul': SoulFigure(),
};
