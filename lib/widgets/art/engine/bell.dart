// The page's names (L, R, W, Hh, V) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// A bell that ships with the app (`P.bell.SHIPPED`): its curated id, its
/// title, the sound asset it plays, and the preset of the five controls
/// its figure is drawn from.
@immutable
class ShippedBell {
  const ShippedBell(this.id, this.title, String file, this.preset)
    : asset = 'assets/audio/$file.wav';

  /// The curated id (`bell-temple`), as `curated_art.json` keys it.
  final String id;

  final String title;

  /// The sound's asset path (`assets/audio/bell_temple.wav`).
  final String asset;

  /// The preset in the bell data (`temple`).
  final String preset;

  /// The figure's family ([BellFigure.family] of [preset]).
  String get kind => BellFigure.family[preset]!;
}

/// The range of one control (`KNOBS`): [min] to [max], in [unit], on a
/// linear or logarithmic [scale] (`lin` or `log`).
typedef BellKnob = ({double min, double max, String unit, String scale});

/// A bell figure for each bell that ships (`places.js` `P.bell`), drawn
/// from the five controls of its sound (`bells.json`), the same five a
/// custom-bell editor would expose:
///
///   pitch   -> size and proportions      bright  -> rim, ink and highlight
///   ring    -> how long the motion lasts strike  -> how hard it is knocked
///   shimmer -> the rim's oscillation, at the sound's own beat rate.
///
/// The family (bowl, temple bell, gong...) is the shape. It is still until
/// struck: `t` is seconds since the strike, then it moves as it sounds and
/// settles; `still` draws it at rest.
class BellFigure extends Figure {
  const BellFigure();

  /// Each preset's family, the figure's shape (`FAMILY`). Its keys, in
  /// order, are every preset there is.
  static const Map<String, String> family = {
    'swell': 'swell',
    'bowl_small': 'bowl',
    'bowl_medium': 'bowl',
    'bowl_deep': 'bowl',
    'temple': 'temple',
    'handbell': 'hand',
    'chime': 'chime',
    'tingsha': 'tingsha',
    'wood_block': 'block',
    'wooden_fish': 'fish',
    'gong': 'gong',
  };

  /// The five controls and their ranges (`KNOBS`).
  static const Map<String, BellKnob> knobs = {
    'pitch': (min: 80, max: 4000, unit: 'Hz', scale: 'log'),
    'bright': (min: 0, max: 1, unit: '', scale: 'lin'),
    'ring': (min: 0.03, max: 8, unit: 's', scale: 'log'),
    'strike': (min: 0, max: 1, unit: '', scale: 'lin'),
    'shimmer': (min: 0, max: 8, unit: 'Hz', scale: 'lin'),
  };

  /// [v] clamped to control [name]'s range (`clampKnob`).
  static double clampKnob(String name, double v) {
    final k = knobs[name]!;
    return clamp(v, k.min, k.max);
  }

  /// The bells that ship (`SHIPPED`; `cueBellSounds` in
  /// `lib/models/cues/cue_settings.dart`), each a preset of the five
  /// controls.
  static const List<ShippedBell> shipped = [
    ShippedBell('bell-swell', 'Swell bell', 'session_bell_v2', 'swell'),
    ShippedBell(
      'bell-bowl-small',
      'Singing bowl, small',
      'bell_bowl_small',
      'bowl_small',
    ),
    ShippedBell(
      'bell-bowl-medium',
      'Singing bowl',
      'bell_bowl_medium',
      'bowl_medium',
    ),
    ShippedBell(
      'bell-bowl-deep',
      'Singing bowl, deep',
      'bell_bowl_deep',
      'bowl_deep',
    ),
    ShippedBell('bell-temple', 'Temple bell', 'bell_temple', 'temple'),
    ShippedBell('bell-handbell', 'Hand bell', 'bell_handbell', 'handbell'),
    ShippedBell('bell-chime', 'Chime', 'bell_chime', 'chime'),
    ShippedBell('bell-tingsha', 'Tingsha', 'bell_tingsha', 'tingsha'),
    ShippedBell(
      'bell-wood-block',
      'Wood block',
      'bell_wood_block',
      'wood_block',
    ),
    ShippedBell(
      'bell-wooden-fish',
      'Wooden fish',
      'bell_wooden_fish',
      'wooden_fish',
    ),
    ShippedBell('bell-gong', 'Gong', 'bell_gong', 'gong'),
  ];

  /// The shipped bell with curated [id] (`bell-temple`), or null.
  static ShippedBell? byId(String id) {
    for (final b in shipped) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// The shipped bell that plays [asset] (`assets/audio/bell_temple.wav`),
  /// or null.
  static ShippedBell? byAsset(String asset) {
    for (final b in shipped) {
      if (b.asset == asset) return b;
    }
    return null;
  }

  /// The preset a shipped bell's [id] pins its figure to (`presetFor`).
  static String? presetFor(String id) => byId(id)?.preset;

  @override
  String get label => 'bell';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) {
    final pinned = place['preset'] as String?;
    final preset = truthy(pinned) ? pinned! : r.pick(family.keys.toList());
    final d = _bellKnobs[preset];
    return {
      ...place,
      'preset': preset,
      'kind': family[preset],
      'knobs': {...(d ?? _defaultKnobs)},
      'tilt': r.range(-0.06, 0.06),
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final L = _Look(p, k), kn = p.sub('knobs'), cx = p.d('cx'), cy = p.d('cy');
    final sh = L.sh(t, still), e = L.e(t, still), body = L.body;
    final kind = p.s('kind');
    final s = kind == 'bowl' || kind == 'chime' ? p.d('s') : p.d('s') * L.sc;
    switch (kind) {
      case 'swell':
        // The app's own bell: its tone swells, so its glow does.
        glow(
          ctx,
          cx,
          cy,
          s * (1.1 + 0.9 * e),
          k.glow,
          (0.18 + 0.32 * e) * (0.6 + 0.4 * L.hi),
        );
        ctx.save();
        ctx.translate(cx, cy + s * 0.55);
        ctx.rotate(0.05 * L.amp * e * math.sin(tau * t / 2.4));
        _bellShape(ctx, s * 1.25, s * 1.2);
        fillWith(ctx, body);
        _sheen(ctx, -s * 0.28, -s * 0.85, -s * 0.12, s * 0.1, L);
        ctx.beginPath();
        ctx.arc(0, -s * 1.22, s * 0.1, 0, tau);
        strokeWith(ctx, body, s * 0.05);
        ctx.beginPath();
        ctx.ellipse(0, 0, s * 0.72, s * 0.08, 0, 0, math.pi);
        strokeWith(ctx, L.rim, s * 0.045 * L.rw, (0.55 + 0.45 * e) * sh);
        ctx.restore();
        _waves(ctx, cx, cy, s * 0.9, L, k, t, still);
      case 'bowl':
        // A singing bowl on its cushion: lower bowls are wider and deeper;
        // the rim shimmers at the beat.
        final u = clamp(
          math.log(700 / kn.d('pitch')) / math.log(700 / 180),
          -0.25,
          1.25,
        );
        final w = s * (0.92 + 0.3 * u), h = s * (0.4 + 0.38 * u);
        final rim = cy - h * 0.35;
        ctx.beginPath();
        ctx.ellipse(cx, rim + h + s * 0.06, w * 0.75, s * 0.14, 0, 0, tau);
        fillWith(ctx, k.alt, 0.8);
        ctx.beginPath();
        ctx.moveTo(cx - w, rim);
        ctx.bezierCurveTo(
          cx - w,
          rim + h * 0.8,
          cx - w * 0.55,
          rim + h,
          cx,
          rim + h,
        );
        ctx.bezierCurveTo(
          cx + w * 0.55,
          rim + h,
          cx + w,
          rim + h * 0.8,
          cx + w,
          rim,
        );
        ctx.closePath();
        fillWith(ctx, body);
        ctx.beginPath();
        ctx.ellipse(cx, rim, w, s * 0.11, 0, 0, tau);
        fillWith(ctx, k.line);
        ctx.beginPath();
        ctx.ellipse(cx, rim, w, s * 0.11, 0, 0, tau);
        strokeWith(ctx, L.rim, s * 0.035 * L.rw, (0.45 + 0.55 * e) * sh);
        _sheen(ctx, cx - w * 0.55, rim + h * 0.15, rim + h * 0.8, s * 0.12, L);
        if (e > 0.01) {
          final a = tau * L.rate * (t - L.hit) + 0.6;
          ctx.beginPath();
          ctx.ellipse(cx, rim, w, s * 0.11, 0, a, a + 1.1);
          strokeWith(ctx, Rgb.white, s * 0.04, L.hi * e * sh);
        }
        _spark(ctx, cx + w, rim + h * 0.35, s, L, k, t, still);
        _waves(ctx, cx, rim, w * 1.05, L, k, t, still, 0.3);
        _mallet(
          ctx,
          cx + w * 1.15,
          rim + h * 1.05,
          math.pi - 0.5 - 0.7 * L.amp * L.toward(t, still),
          s * 0.9,
          k,
          L.soft,
        );
      case 'temple':
        // A bonshō, struck by a hung log, sways once.
        final a = 0.06 * L.amp * e * math.sin(tau * (t - L.hit) / 2.6);
        final top = cy - s * 1.05;
        ctx.beginPath();
        ctx.moveTo(cx - s * 1.1, top);
        ctx.lineTo(cx + s * 1.1, top);
        strokeWith(ctx, k.line, s * 0.08);
        ctx.save();
        ctx.translate(cx, top);
        ctx.rotate(a);
        _rr(ctx, -s * 0.06, 0, s * 0.12, s * 0.18, s * 0.03);
        fillWith(ctx, k.line);
        final W = s * 0.62, Hh = s * 1.75;
        ctx.beginPath();
        ctx.moveTo(-W * 0.85, s * 0.18 + W * 0.3);
        ctx.quadraticCurveTo(-W * 0.85, s * 0.18, 0, s * 0.18);
        ctx.quadraticCurveTo(W * 0.85, s * 0.18, W * 0.85, s * 0.18 + W * 0.3);
        ctx.lineTo(W, Hh);
        ctx.quadraticCurveTo(0, Hh + s * 0.08, -W, Hh);
        ctx.closePath();
        fillWith(ctx, body);
        _sheen(ctx, -W * 0.55, s * 0.3, Hh * 0.95, s * 0.12, L);
        for (final v in const [0.6, 1.25]) {
          ctx.beginPath();
          ctx.moveTo(-W * 0.92, s * v);
          ctx.lineTo(W * 0.92, s * v);
          strokeWith(ctx, k.line, s * 0.025, 0.7);
        }
        for (var i = 0; i < 3; i++) {
          for (var j = 0; j < 3; j++) {
            circle(
              ctx,
              -W * 0.45 + i * W * 0.45,
              s * 0.36 + j * s * 0.08,
              s * 0.025,
            );
            fillWith(ctx, k.line, 0.8);
          }
        }
        ctx.beginPath();
        ctx.moveTo(-W, Hh);
        ctx.quadraticCurveTo(0, Hh + s * 0.08, W, Hh);
        strokeWith(ctx, L.rim, s * 0.04, (0.45 + 0.55 * e) * sh);
        circle(ctx, W * 0.42, s * 1.45, s * 0.1);
        fillWith(ctx, L.rim);
        ctx.restore();
        final lx = -s * 0.45 * L.amp * L.toward(t, still);
        ctx.beginPath();
        ctx.moveTo(cx + s * 0.9 + lx, top);
        ctx.lineTo(cx + s * 0.9 + lx, cy + s * 0.35);
        ctx.moveTo(cx + s * 1.45 + lx, top);
        ctx.lineTo(cx + s * 1.45 + lx, cy + s * 0.35);
        strokeWith(ctx, k.line, 0.003, 0.7);
        _rr(
          ctx,
          cx + s * 0.62 + lx,
          cy + s * 0.33,
          s * 0.95,
          s * 0.14,
          s * 0.07,
        );
        fillWith(ctx, k.alt);
        _spark(ctx, cx + s * 0.5, cy + s * 0.4, s, L, k, t, still);
        _waves(ctx, cx, cy + s * 0.4, s * 0.8, L, k, t, still);
      case 'hand':
        // A hand bell that sways from its handle; the clapper lags behind.
        final a =
            0.34 *
            L.amp *
            (still
                ? 0
                : t < L.hit
                ? -0.4 * (1 - L.toward(t, still))
                : e * math.cos(tau * (t - L.hit) / 1.5));
        final pivot = cy - s * 1.05;
        ctx.save();
        ctx.translate(cx, pivot);
        ctx.rotate(a);
        _rr(ctx, -s * 0.1, -s * 0.1, s * 0.2, s * 0.78, s * 0.09);
        fillWith(ctx, k.alt);
        circle(ctx, math.sin(-a * 1.8) * s * 0.25, s * 1.88, s * 0.11);
        fillWith(ctx, k.line);
        ctx.save();
        ctx.translate(0, s * 1.85);
        _bellShape(ctx, s * 1.25, s * 1.3);
        fillWith(ctx, body);
        _sheen(ctx, -s * 0.28, -s * 0.92, -s * 0.12, s * 0.1, L);
        ctx.beginPath();
        ctx.ellipse(0, 0, s * 0.72, s * 0.08, 0, 0, math.pi);
        strokeWith(ctx, L.rim, s * 0.045 * L.rw, (0.55 + 0.45 * e) * sh);
        ctx.restore();
        ctx.restore();
        _waves(ctx, cx, cy + s * 0.6, s * 0.8, L, k, t, still);
      case 'chime':
        // Tubes on a bar; a lower pitch hangs longer tubes (a bar's pitch
        // falls with its length squared).
        final bar = cy - s * 1.1;
        const n = 4;
        final lk = clamp(math.sqrt(1568 / kn.d('pitch')), 0.7, 1.35);
        ctx.beginPath();
        ctx.moveTo(cx - s * 0.95, bar);
        ctx.lineTo(cx + s * 0.95, bar);
        strokeWith(ctx, k.line, s * 0.08);
        for (var i = 0; i < n; i++) {
          final x = cx + (i - (n - 1) / 2) * s * 0.42;
          final len = math.min(s * (1.7 - i * 0.22) * lk, s * 2.25);
          final ei = still || t < L.hit + 0.1 * i
              ? 0.0
              : e * math.exp(-0.1 * i);
          final a =
              0.14 *
              L.amp *
              ei *
              math.sin(tau * (t - L.hit) / (1.3 + i * 0.12) + i);
          ctx.save();
          ctx.translate(x, bar);
          ctx.rotate(a);
          ctx.beginPath();
          ctx.moveTo(0, 0);
          ctx.lineTo(0, s * 0.2);
          strokeWith(ctx, k.line, 0.003);
          _rr(ctx, -s * 0.07, s * 0.2, s * 0.14, len, s * 0.06);
          fillWith(ctx, body);
          ctx.beginPath();
          ctx.moveTo(-s * 0.03, s * 0.28);
          ctx.lineTo(-s * 0.03, s * 0.2 + len * 0.9);
          strokeWith(
            ctx,
            L.rim,
            s * 0.025 * L.rw,
            (0.3 + 0.6 * ei) * L.hi * sh + 0.15,
          );
          ctx.restore();
        }
        final sx = cx + s * 0.95,
            sy = bar + s * 0.75,
            back = L.toward(t, still);
        circle(ctx, sx + s * 0.35 * L.amp * back, sy, s * 0.07);
        fillWith(ctx, k.alt);
      case 'tingsha':
        // Two small cymbals, face on, hanging from one cord: they swing in,
        // meet edge to edge once, part, and tremble at the beat.
        final close = still
            ? 0.0
            : t < L.hit
            ? 1 - L.toward(t, still)
            : math.max(0.0, 1 - (t - L.hit) / 0.5);
        final R = s * 0.46, knot = cy - s * 1.05;
        final d =
            R * (1.2 - 0.2 * close * (0.6 + 0.4 * L.amp)) +
            (still ? 0 : s * 0.035 * e * math.sin(tau * L.rate * (t - L.hit)));
        final y = cy + s * 0.3;
        ctx.beginPath();
        ctx.moveTo(cx - d, y);
        ctx.quadraticCurveTo(cx - d * 0.5, knot + s * 0.1, cx, knot);
        ctx.quadraticCurveTo(cx + d * 0.5, knot + s * 0.1, cx + d, y);
        strokeWith(ctx, k.line, s * 0.035);
        circle(ctx, cx, knot, s * 0.06);
        fillWith(ctx, k.line);
        for (final sd in const [-1, 1]) {
          final x = cx + sd * d;
          circle(ctx, x, y, R);
          fillWith(ctx, body);
          circle(ctx, x, y, R * 0.36);
          fillWith(ctx, k.alt);
          circle(ctx, x, y, R * 0.92);
          strokeWith(ctx, L.rim, s * 0.035 * L.rw, (0.45 + 0.55 * e) * sh);
          ctx.beginPath();
          ctx.arc(x, y, R * 0.62, math.pi * 1.1, math.pi * 1.45);
          strokeWith(
            ctx,
            Rgb.white,
            s * 0.03,
            0.15 + 0.5 * L.hi * (0.3 + 0.7 * e) * sh,
          );
        }
        _spark(ctx, cx, y, s, L, k, t, still);
        _waves(ctx, cx, y, R * 2.1, L, k, t, still, 0.6);
      case 'block':
      case 'fish':
        // Struck wood: a mallet knocks once.
        final knock = L.e(t, still), y = cy + s * 0.15;
        ctx.save();
        ctx.translate(cx, y + knock * s * 0.04 * L.amp);
        if (kind == 'block') {
          cutPoly(
            ctx,
            [
              (-s * 0.95, -s * 0.38),
              (s * 0.95, -s * 0.38),
              (s * 1.02, s * 0.42),
              (-s * 1.02, s * 0.42),
            ],
            SeededRandom('block'),
            0.004,
          );
          fillWith(ctx, body);
          _rr(ctx, -s * 0.7, -s * 0.05, s * 1.4, s * 0.08, s * 0.04);
          fillWith(ctx, k.line);
          ctx.beginPath();
          ctx.moveTo(-s * 0.9, -s * 0.3);
          ctx.lineTo(s * 0.9, -s * 0.3);
          strokeWith(ctx, L.rim, 0.004, 0.4 + 0.4 * L.hi);
        } else {
          ctx.beginPath();
          ctx.ellipse(0, s * 0.62, s * 1.0, s * 0.14, 0, 0, tau);
          fillWith(ctx, k.alt, 0.8);
          ctx.beginPath();
          ctx.ellipse(0, 0, s * 0.95, s * 0.68, 0, 0, tau);
          fillWith(ctx, body);
          ctx.beginPath();
          ctx.ellipse(0, s * 0.1, s * 0.7, s * 0.1, 0, 0.15, math.pi - 0.15);
          strokeWith(ctx, k.line, s * 0.09);
          for (var i = 0; i < 3; i++) {
            ctx.beginPath();
            ctx.arc(
              -s * 0.2 + i * s * 0.25,
              -s * 0.25,
              s * 0.14,
              math.pi * 1.15,
              math.pi * 1.85,
            );
            strokeWith(ctx, L.rim, 0.004, 0.4 + 0.4 * L.hi);
          }
          circle(ctx, -s * 0.62, -s * 0.18, s * 0.05);
          fillWith(ctx, k.line);
        }
        ctx.restore();
        final after = still || t < L.hit
            ? 0.0
            : math.min(1.0, (t - L.hit) / 0.5);
        _mallet(
          ctx,
          cx + s * 0.85,
          y - s * 0.95,
          math.pi * 0.62 - 0.9 * L.amp * L.toward(t, still) - 0.45 * after,
          s * 1.05,
          k,
          L.soft,
        );
        _spark(ctx, cx + s * 0.3, y - s * 0.45, s, L, k, t, still);
      case 'gong':
        // Ripples open from the boss across the face, as long as it rings;
        // the upper modes bloom late.
        final a = 0.03 * L.amp * e * math.sin(tau * (t - L.hit) / 3);
        final R = s * 0.82;
        ctx.beginPath();
        ctx.moveTo(cx - s * 1.15, cy + s * 1.25);
        ctx.lineTo(cx - s * 1.15, cy - s * 1.1);
        ctx.lineTo(cx + s * 1.15, cy - s * 1.1);
        ctx.lineTo(cx + s * 1.15, cy + s * 1.25);
        strokeWith(ctx, k.line, s * 0.08);
        ctx.save();
        ctx.translate(cx, cy - s * 1.1);
        ctx.rotate(a);
        ctx.beginPath();
        ctx.moveTo(-R * 0.5, 0);
        ctx.lineTo(-R * 0.35, s * 0.32);
        ctx.moveTo(R * 0.5, 0);
        ctx.lineTo(R * 0.35, s * 0.32);
        strokeWith(ctx, k.line, 0.003);
        final gy = s * 0.32 + R;
        circle(ctx, 0, gy, R);
        fillWith(ctx, body);
        circle(ctx, 0, gy, R * 0.94);
        strokeWith(ctx, L.rim, s * 0.035 * L.rw, (0.35 + 0.65 * e) * sh);
        ctx.beginPath();
        ctx.arc(0, gy, R * 0.7, math.pi * 1.05, math.pi * 1.45);
        strokeWith(ctx, Rgb.white, s * 0.08, 0.05 + 0.35 * L.bv);
        circle(ctx, 0, gy, R * 0.28);
        fillWith(ctx, k.alt);
        if (!still && t > L.hit) {
          final span = L.V * 0.7;
          for (var i = 0; i < 5; i++) {
            final u = (t - L.hit) / span - i * 0.16;
            if (u > 0 && u < 1) {
              circle(ctx, 0, gy, R * (0.3 + u * 0.62));
              strokeWith(ctx, k.glow, 0.006, (0.4 + 0.5 * L.hi) * (1 - u) * sh);
            }
          }
        }
        ctx.restore();
        _spark(ctx, cx, cy - s * 0.78 + R, s, L, k, t, still);
        // The page passes `{ ...L, hit: L.hit + 0.4 }`: only the hit moves;
        // `L.sh` still closes over the bell's own.
        _waves(
          ctx,
          cx,
          cy - s * 0.78 + R,
          R * 1.05,
          L,
          k,
          t,
          still,
          1,
          L.hit + 0.4,
        );
        _mallet(
          ctx,
          cx + s * 1.35,
          cy + s * 1.0,
          math.pi + 0.75 + 0.8 * L.amp * L.toward(t, still),
          s * 0.75,
          k,
          L.soft,
        );
    }
  }
}

/// The knobs a preset starts from (`BellData[preset].knobs`, from
/// `bells.json`): `build` copies them, and `look` reads the preset's pitch
/// as the reference size.
const Map<String, Map<String, double>> _bellKnobs = {
  'swell': {
    'pitch': 220.7,
    'bright': 0.03463,
    'ring': 1.228,
    'shimmer': 0.24,
    'strike': 0.0,
  },
  'bowl_small': {
    'pitch': 640.0,
    'bright': 0.1961,
    'ring': 1.05,
    'shimmer': 0.9118,
    'strike': 0.511,
  },
  'bowl_medium': {
    'pitch': 392.0,
    'bright': 0.1961,
    'ring': 1.45,
    'shimmer': 0.6112,
    'strike': 0.511,
  },
  'bowl_deep': {
    'pitch': 196.0,
    'bright': 0.1961,
    'ring': 2.0,
    'shimmer': 0.3377,
    'strike': 0.511,
  },
  'temple': {
    'pitch': 196.0,
    'bright': 0.5023,
    'ring': 3.2,
    'shimmer': 1.3,
    'strike': 0.2416,
  },
  'handbell': {
    'pitch': 1318.0,
    'bright': 0.2063,
    'ring': 1.2,
    'shimmer': 1.1,
    'strike': 0.8543,
  },
  'chime': {
    'pitch': 1568.0,
    'bright': 0.0548,
    'ring': 1.7,
    'shimmer': 0.7,
    'strike': 0.97,
  },
  'tingsha': {
    'pitch': 3120.0,
    'bright': 0.1153,
    'ring': 1.6,
    'shimmer': 5.5,
    'strike': 0.97,
  },
  'wood_block': {
    'pitch': 1180.0,
    'bright': 0.1789,
    'ring': 0.032,
    'shimmer': 0.0,
    'strike': 0.7006,
  },
  'wooden_fish': {
    'pitch': 520.0,
    'bright': 0.06816,
    'ring': 0.12,
    'shimmer': 0.0,
    'strike': 0.459,
  },
  'gong': {
    'pitch': 118.0,
    'bright': 0.6498,
    'ring': 4.2,
    'shimmer': 0.8,
    'strike': 0.1156,
  },
};

/// The knobs of a preset the bell data doesn't know.
const Map<String, double> _defaultKnobs = {
  'pitch': 400,
  'bright': 0.2,
  'ring': 1.5,
  'strike': 0.5,
  'shimmer': 0.6,
};

/// How the knobs read on the page (`look`). The reference is the preset
/// the bell started from, so a shipped bell draws at its family's own size.
class _Look {
  factory _Look(P p, Inks k) {
    final kn = p.sub('knobs');
    final refPitch = _bellKnobs[p.sOr('preset')]?['pitch'] ?? kn.d('pitch');
    final bright = kn.d('bright'), ring = kn.d('ring');
    final strike = kn.d('strike'), shimmer = kn.d('shimmer');
    final bv = math.pow(clamp(bright / 0.65, 0, 1), 0.6).toDouble();
    return _Look._(
      sc: clamp(
        math.pow(refPitch / kn.d('pitch'), 0.22).toDouble(),
        0.72,
        1.28,
      ),
      V: clamp(0.45 + 1.25 * ring, 0.45, 10),
      amp: 0.3 + 0.7 * strike,
      hit: lerp(0.6, 0.25, strike),
      rise: 0.03 + 0.6 * math.pow(1 - strike, 3),
      rate: math.min(shimmer, 7.0),
      depth: shimmer > 0 ? clamp(0.3 + shimmer / 2.5, 0, 1) : 0,
      body: mix(mix(k.main, k.line, 0.45), mix(k.main, k.glow, 0.28), bv),
      rim: mix(k.alt, k.glow, bv),
      hi: 0.2 + 0.8 * bv,
      rw: 0.7 + 0.9 * bv,
      soft: 1 - strike,
      bv: bv,
    );
  }

  _Look._({
    required this.sc,
    required this.V,
    required this.amp,
    required this.hit,
    required this.rise,
    required this.rate,
    required this.depth,
    required this.body,
    required this.rim,
    required this.hi,
    required this.rw,
    required this.soft,
    required this.bv,
  });

  final double sc, V, amp, hit, rise, rate, depth, hi, rw, soft, bv;
  final Rgb body, rim;

  /// The envelope: 0 until the hit, then rises and rings away.
  double e(double t, bool still) => still || t < hit
      ? 0
      : (1 - math.exp(-(t - hit) / rise)) * math.exp(-(t - hit) / V);

  /// The shimmer: 1, dipping at the beat rate.
  double sh(double t, bool still) => still || depth == 0
      ? 1
      : 1 - depth * 0.5 * (1 - math.cos(tau * rate * math.max(0, t - hit)));

  /// 1 at the back of the swing, 0 at contact.
  double toward(double t, bool still) =>
      still || t >= hit ? 0 : math.sin(math.pi / 2 * (1 - t / hit));
}

/// Sound leaving the instrument: rings open while it rings; more and wider
/// the longer it rings (`waves`). [hit] stands in for the page's
/// `{ ...L, hit }`.
void _waves(
  Ctx ctx,
  double x,
  double y,
  double r0,
  _Look L,
  Inks k,
  double t,
  bool still, [
  double sq = 1,
  double? hit,
]) {
  final h = hit ?? L.hit;
  if (still || t < h) return;
  final n = (clamp(1 + L.V / 1.5, 1, 5) + 0.5).floor(), span = L.V * 0.9;
  for (var i = 0; i < n; i++) {
    final u = (t - h) / span - i * 0.22;
    if (u <= 0 || u >= 1) continue;
    ctx.beginPath();
    ctx.ellipse(x, y, r0 * (1 + u * 1.3), r0 * (1 + u * 1.3) * sq, 0, 0, tau);
    strokeWith(
      ctx,
      k.glow,
      0.006 * (1 - u) + 0.002,
      (0.45 + 0.35 * L.bv) * (1 - u) * L.sh(t, false),
    );
  }
}

/// A classic bell, mouth at y = 0, crown at y = -h (`bellShape`).
void _bellShape(Ctx ctx, double w, double h) {
  ctx.beginPath();
  ctx.moveTo(-w * 0.58, 0);
  ctx.bezierCurveTo(
    -w * 0.45,
    -h * 0.12,
    -w * 0.32,
    -h * 0.4,
    -w * 0.32,
    -h * 0.72,
  );
  ctx.bezierCurveTo(
    -w * 0.32,
    -h * 1.02,
    w * 0.32,
    -h * 1.02,
    w * 0.32,
    -h * 0.72,
  );
  ctx.bezierCurveTo(w * 0.32, -h * 0.4, w * 0.45, -h * 0.12, w * 0.58, 0);
  ctx.quadraticCurveTo(0, h * 0.09, -w * 0.58, 0);
  ctx.closePath();
}

/// The mallet shows the strike: a soft one has a big felt head, a hard one
/// a small bare tip (`mallet`).
void _mallet(
  Ctx ctx,
  double x,
  double y,
  double a,
  double len,
  Inks k, [
  double soft = 0.5,
]) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(a);
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(len, 0);
  strokeWith(ctx, k.line, len * 0.06);
  circle(ctx, len, 0, len * (0.07 + 0.12 * soft));
  fillWith(ctx, mix(k.line, k.alt, 0.25 + 0.75 * soft));
  ctx.restore();
}

/// Brightness as a sheen down the body (`sheen`).
void _sheen(Ctx ctx, double x, double y0, double y1, double w, _Look L) {
  ctx.beginPath();
  ctx.moveTo(x, y0);
  ctx.quadraticCurveTo(x - w, (y0 + y1) / 2, x, y1);
  strokeWith(ctx, Rgb.white, w * 0.9, 0.05 + 0.4 * L.bv);
}

/// A short glint where the bell is struck, sized by the strike (`spark`).
void _spark(
  Ctx ctx,
  double x,
  double y,
  double s,
  _Look L,
  Inks k,
  double t,
  bool still,
) {
  if (still || t < L.hit) return;
  final u = (t - L.hit) / 0.45;
  if (u >= 1) return;
  for (var i = 0; i < 5; i++) {
    final a = -math.pi / 2 + (i - 2) * 0.5;
    final r0 = s * (0.12 + u * 0.25 * L.amp);
    final r1 = r0 + s * 0.16 * L.amp * (1 - u);
    ctx.beginPath();
    ctx.moveTo(x + math.cos(a) * r0, y + math.sin(a) * r0);
    ctx.lineTo(x + math.cos(a) * r1, y + math.sin(a) * r1);
    strokeWith(ctx, k.glow, 0.004, (1 - u) * (0.4 + 0.6 * L.amp));
  }
}

/// `rr`: a fresh path holding one rounded rectangle.
void _rr(Ctx ctx, double x, double y, double w, double h, double r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}
