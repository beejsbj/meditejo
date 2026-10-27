// The page's names (H, R) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/art_textures.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 4's grounds (`grounds.js`), with the noise texture as round 5
/// redraws it (`places.js`): round 2's atmospheres rebuilt as grounds that
/// figures sit on. Each fills the whole card (unit wide, H tall), moves
/// slowly and loops without a seam.
final Map<String, Ground> roundFourGrounds = {
  'paper': const PaperGround(),
  'mist': const MistGround(),
  'dawn': const DawnGround(),
  'rainfield': const RainfieldGround(),
  'canopy': const CanopyGround(),
  'night': const NightGround(),
  'hearth': const HearthGround(),
  'sea': const SeaGround(),
  'bokeh': const BokehGround(),
  'grain': const GrainGround(),
};

/// Flat paper in one of three value keys: the quietest ground.
class PaperGround extends Ground {
  const PaperGround();

  @override
  String get label => 'paper';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'key': o['key'] ?? r.pick(const ['light', 'light', 'mid']),
    'k': r.range(0, 0.12),
  };

  @override
  Rgb tone(ArtRoles c, P p) => switch (p.s('key')) {
    'light' => mix(c.tile, c.accent, p.d('k')),
    'mid' => mix(c.form, c.tile, 0.35),
    _ => darkOf(c, 0.2),
  };

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final b = tone(c, p);
    vgradFill(ctx, H, [(0, b, 1), (1, mix(b, c.deep, 0.06), 1)]);
  }
}

/// Ridges in mist under a soft light; mist pools above each ridge.
class MistGround extends Ground {
  const MistGround();

  @override
  String get label => 'mist';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'sun': r.chance(0.6),
    'sx': r.range(0.25, 0.75),
    'sy': r.range(0.22, 0.38),
    'layers': [
      for (var i = 0, n = r.integer(2, 3); i < n; i++)
        {
          'y': lerp(0.62, 0.86, i / 2) + r.range(-0.02, 0.02),
          'amp': r.range(0.02, 0.045),
          'f': r.range(0.6, 1.3),
          'ph': r.range(0, tau),
          'per': r.range(34, 48),
        },
    ],
  };

  @override
  Rgb tone(ArtRoles c, P p) => mix(c.tile, c.form, 0.3);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    vgradFill(ctx, H, [
      (0, mix(c.tile, c.form, 0.18), 1),
      (0.65, mix(c.tile, c.accent, 0.12), 1),
      (1, mix(c.form, c.tile, 0.4), 1),
    ]);
    if (p.b('sun')) {
      glow(
        ctx,
        p.d('sx'),
        p.d('sy') * H,
        0.42,
        c.accent,
        0.28 + (still ? 0 : 0.06 * S(t, 10)),
      );
    }
    final layers = p.list('layers');
    final n = layers.length;
    for (var i = 0; i < n; i++) {
      final L = layers[i];
      final k = (i + 1) / n,
          drift = still ? 0.0 : 0.03 * S(t, L.d('per'), L.d('ph')),
          base = L.d('y') * H;
      final mg = ctx.createLinearGradient(0, base - 0.12, 0, base)
        ..addColorStop(0, css(c.tile, 0))
        ..addColorStop(1, css(c.tile, 0.45));
      ctx.fillStyle = mg;
      ctx.fillRect(0, base - 0.12, 1, 0.12);
      ctx.beginPath();
      ctx.moveTo(-0.1, H + 0.1);
      for (var x = -0.1; x <= 1.1001; x += 0.02) {
        ctx.lineTo(
          x,
          base -
              L.d('amp') *
                  (0.6 +
                      0.4 * math.sin(tau * L.d('f') * (x + drift) + L.d('ph'))),
        );
      }
      ctx.lineTo(1.1, H + 0.1);
      ctx.closePath();
      ctx.fillStyle = css(
        mix(mix(c.form, c.tile, 0.55 * (1 - k)), c.deep, 0.3 * k * k),
        0.9,
      );
      ctx.fill();
    }
  }
}

/// A low sun over water, its glow breathing, reflections shimmering.
class DawnGround extends Ground {
  const DawnGround();

  @override
  String get label => 'dawn';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'h': r.range(0.6, 0.7),
    'sx': r.range(0.3, 0.7),
    'warm': r.range(0.3, 0.55),
    'bars': [for (var i = 0; i < 5; i++) r.range(0, tau)],
  };

  @override
  Rgb tone(ArtRoles c, P p) => mix(c.tile, c.accent, p.d('warm') * 0.5);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final ph = p.d('h'), sx = p.d('sx');
    final h = ph * H, b = still ? 0.5 : 0.5 + 0.5 * S(t, 10);
    vgradFill(ctx, H, [
      (0, mix(c.tile, c.form, 0.2), 1),
      (ph * 0.95, mix(c.tile, c.accent, p.d('warm')), 1),
      (ph, mix(c.form, c.deep, 0.25), 1),
      (1, mix(c.form, c.deep, 0.5), 1),
    ]);
    glow(ctx, sx, h, 0.5 * (0.92 + 0.08 * b), c.accent, 0.42);
    ctx.lineCap = StrokeCap.round;
    final bars = p.nums('bars');
    for (var i = 0; i < bars.length; i++) {
      final y = h + 0.03 + i * 0.045 * H,
          w =
              0.3 *
              (1 - i * 0.15) *
              (1 + (still ? 0 : 0.18 * S(t, 7.0 + i, bars[i])));
      ctx.strokeStyle = css(mix(c.accent, c.tile, 0.3), 0.55 - i * 0.08);
      ctx.lineWidth = 0.008;
      ctx.beginPath();
      ctx.moveTo(sx - w / 2, y);
      ctx.lineTo(sx + w / 2, y);
      ctx.stroke();
    }
  }
}

/// A dim field with soft rain falling through it and one warm lamp.
class RainfieldGround extends Ground {
  const RainfieldGround();

  @override
  String get label => 'rain field';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'lx': r.range(0.2, 0.8),
    'ly': r.range(0.2, 0.5),
    'drops': [
      for (var i = 0; i < 60; i++)
        {
          'x': r.range(-0.1, 1.1),
          'y': r.next(),
          'l': r.range(0.05, 0.11),
          'v': r.range(0.05, 0.09),
          'a': r.range(0.12, 0.35),
        },
    ],
    'slant': r.range(-0.15, 0),
  };

  @override
  Rgb tone(ArtRoles c, P p) => mix(c.deep, c.tile, 0.22);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final g = mix(c.deep, c.tile, 0.2), slant = p.d('slant');
    vgradFill(ctx, H, [
      (0, mix(g, c.form, 0.25), 1),
      (1, mix(c.deep, c.form, 0.12), 1),
    ]);
    glow(
      ctx,
      p.d('lx'),
      p.d('ly') * H,
      0.45,
      c.accent,
      0.2 + (still ? 0 : 0.05 * S(t, 10)),
    );
    ctx.lineCap = StrokeCap.round;
    ctx.lineWidth = 0.003;
    for (final d in p.list('drops')) {
      final y = (jsMod(d.d('y') + (still ? 0 : t * d.d('v')), 1.2) - 0.1) * H,
          x = d.d('x') + y * slant;
      ctx.strokeStyle = css(c.light, d.d('a'));
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + d.d('l') * slant, y + d.d('l') * H);
      ctx.stroke();
    }
  }
}

/// Layered crowns of trees under a pale sky, swaying a little.
class CanopyGround extends Ground {
  const CanopyGround();

  @override
  String get label => 'canopy';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'sky': r.pick(const ['day', 'dawn', 'dusk']),
    'rows': [
      for (var i = 0; i < 3; i++)
        [
          for (var j = 0; j < 9; j++)
            {
              'x': j / 8 + r.range(-0.05, 0.05),
              'r': r.range(0.08, 0.14) * (1 + i * 0.22),
              'dy': r.range(-0.03, 0.03),
              'ph': r.range(0, tau),
            },
        ],
    ],
  };

  @override
  Rgb tone(ArtRoles c, P p) => p.s('sky') == 'dusk'
      ? mix(c.accent, c.deep, 0.4)
      : mix(c.tile, c.form, 0.3);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final skyName = p.s('sky');
    final sky = skyName == 'dawn'
        ? mix(c.tile, c.accent, 0.35)
        : skyName == 'dusk'
        ? mix(c.accent, c.deep, 0.45)
        : mix(c.tile, c.form, 0.25);
    vgradFill(ctx, H, [
      (0, mix(sky, c.deep, 0.08), 1),
      (0.6, sky, 1),
      (1, darkOf(c, 0.4), 1),
    ]);
    if (skyName != 'day') glow(ctx, 0.5, 0.6 * H, 0.5, c.accent, 0.3);
    final rows = p.raw('rows');
    for (var i = 0; i < rows.length; i++) {
      final row = [
        for (final e in rows[i]! as List) P((e as Map).cast<String, Object?>()),
      ];
      final k = (i + 1) / 3, base = H * (0.66 + i * 0.12);
      ctx.beginPath();
      ctx.moveTo(-0.1, H + 0.1);
      for (final cr in row) {
        ctx.arc(
          cr.d('x') + (still ? 0 : 0.006 * S(t, 9.0 + i * 2, cr.d('ph'))),
          base + cr.d('dy') * H,
          cr.d('r') * 0.62,
          math.pi,
          0,
        );
      }
      ctx.lineTo(1.1, H + 0.1);
      ctx.closePath();
      ctx.fillStyle = css(
        mix(mix(c.form, c.tile, 0.3 * (1 - k)), c.deep, 0.5 * k),
      );
      ctx.fill();
    }
  }
}

/// A deep field: dust of faint stars, a moon's glow, an optional skyline.
class NightGround extends Ground {
  const NightGround();

  @override
  String get label => 'night field';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'dust': [
      for (var i = 0; i < 70; i++)
        {
          'x': r.next(),
          'y': r.next() * 0.8,
          'z': r.range(0.0015, 0.004),
          'ph': r.range(0, tau),
          'per': r.range(6, 14),
        },
    ],
    'mx': r.range(0.2, 0.8),
    'moon': r.chance(0.5),
    'land': r.chance(0.5),
    'lp': r.range(0, tau),
  };

  @override
  Rgb tone(ArtRoles c, P p) => mix(c.deep, c.form, 0.15);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    vgradFill(ctx, H, [
      (0, mix(c.deep, c.tile, 0.02), 1),
      (0.8, mix(c.deep, c.form, 0.25), 1),
      (1, c.deep, 1),
    ]);
    if (p.b('moon')) glow(ctx, p.d('mx'), 0.22 * H, 0.32, c.light, 0.12);
    for (final d in p.list('dust')) {
      final a = still ? 0.6 : 0.45 + 0.4 * S(t, d.d('per'), d.d('ph'));
      circle(ctx, d.d('x'), d.d('y') * H, d.d('z'));
      ctx.fillStyle = css(c.light, a * 0.8);
      ctx.fill();
    }
    if (p.b('land')) {
      final lp = p.d('lp');
      ctx.beginPath();
      ctx.moveTo(0, H);
      for (var x = 0.0; x <= 1.001; x += 0.02) {
        ctx.lineTo(x, H * (0.88 + 0.025 * math.sin(x * 7 + lp)));
      }
      ctx.lineTo(1, H);
      ctx.closePath();
      ctx.fillStyle = css(c.deep, 0.95);
      ctx.fill();
    }
  }
}

/// A banked hearth: warm dark with a low glow that rises and falls.
class HearthGround extends Ground {
  const HearthGround();

  @override
  String get label => 'hearth glow';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'x': r.range(0.4, 0.6),
    'w': r.range(0.45, 0.6),
  };

  @override
  Rgb tone(ArtRoles c, P p) => mix(c.deep, c.form, 0.2);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    vgradFill(ctx, H, [
      (0, mix(c.deep, c.tile, 0.03), 1),
      (1, darkOf(c, 0.3), 1),
    ]);
    final f = still ? 0.5 : 0.5 + 0.3 * S(t, 5.3) + 0.2 * S(t, 8.1, 1);
    glow(
      ctx,
      p.d('x'),
      H * 0.95,
      p.d('w') * (0.9 + 0.15 * f),
      c.accent,
      0.38 + 0.12 * f,
    );
  }
}

/// Open sea: a pale sky, a horizon, swells rolling in.
class SeaGround extends Ground {
  const SeaGround();

  @override
  String get label => 'sea';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'hy': r.range(0.36, 0.46),
    'gx': r.range(0.25, 0.75),
    'rows': r.integer(4, 6),
    'ph': r.range(0, tau),
  };

  @override
  Rgb tone(ArtRoles c, P p) => mix(c.form, c.deep, 0.3);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final hyp = p.d('hy'), rows = p.i('rows');
    final hy = hyp * H;
    vgradFill(ctx, H, [
      (0, mix(c.form, c.tile, 0.5), 1),
      (hyp, mix(c.tile, c.accent, 0.4), 1),
      (hyp + 0.002, mix(c.form, c.deep, 0.25), 1),
      (1, mix(c.form, c.deep, 0.55), 1),
    ]);
    glow(ctx, p.d('gx'), hy, 0.4, c.accent, 0.35);
    for (var i = 0; i < rows; i++) {
      final k = i / (rows - 1),
          y0 = hy + (0.04 + math.pow(k, 1.3) * (H - hy - 0.04)),
          amp = (0.003 + 0.016 * k) * H,
          ph = (still ? 0 : tau * t / (14 - i)) + i * 1.3 + p.d('ph');
      ctx.beginPath();
      ctx.moveTo(-0.05, H + 0.1);
      for (var x = -0.05; x <= 1.05; x += 0.02) {
        ctx.lineTo(x, y0 + amp * math.sin(tau * x * (1.2 + i * 0.25) + ph));
      }
      ctx.lineTo(1.05, H + 0.1);
      ctx.closePath();
      ctx.fillStyle = css(mix(mix(c.form, c.deep, 0.3), c.deep, k * 0.35), 0.5);
      ctx.fill();
      ctx.strokeStyle = css(c.light, 0.3 - 0.18 * k);
      ctx.lineWidth = 0.004;
      ctx.stroke();
    }
  }
}

/// A warm room seen out of focus: soft discs drifting.
class BokehGround extends Ground {
  const BokehGround();

  @override
  String get label => 'room bokeh';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'b': [
      for (var i = 0; i < 12; i++)
        {
          'x': r.next(),
          'y': r.range(0.1, 0.9),
          'r': r.range(0.04, 0.12),
          'ph': r.range(0, tau),
          'per': r.range(14, 24),
          'role': r.pick(const ['accent', 'accent', 'light', 'form']),
          'a': r.range(0.2, 0.45),
        },
    ],
  };

  @override
  Rgb tone(ArtRoles c, P p) => mix(darkOf(c, 0.3), c.accent, 0.12);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    vgradFill(ctx, H, [
      (0, mix(darkOf(c, 0.3), c.accent, 0.14), 1),
      (1, darkOf(c, 0.15), 1),
    ]);
    for (final q in p.list('b')) {
      final ph = q.d('ph'), per = q.d('per');
      final x = q.d('x') + (still ? 0 : 0.025 * S(t, per, ph)),
          y = q.d('y') * H + (still ? 0 : 0.012 * S(t, per * 1.3, ph));
      glow(
        ctx,
        x,
        y,
        q.d('r'),
        c.role(q.s('role')),
        q.d('a') * (still ? 1 : 0.85 + 0.15 * S(t, 10, ph)),
      );
    }
  }
}

const _noiseWhite = Rgb(0xF3, 0xF1, 0xEC);
const _noisePink = Rgb(0xE6, 0xB3, 0xAA);
const _noiseBrown = Rgb(0x4F, 0x34, 0x26);
const _black = Rgb(0, 0, 0);

/// A tinted texture for the noise colours: fine and bright, mid, coarse
/// and warm. It drifts rather than flickers. Noise in its own colour (round
/// 5): a bright near-white, a soft pink, a deep brown, each leaning a
/// little toward the palette. Build is unchanged, so frozen params (the
/// Stillness preset's) stay valid.
class GrainGround extends Ground {
  const GrainGround();

  @override
  String get label => 'texture';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'colour': truthy(o['colour'])
        ? o['colour']
        : r.pick(const ['white', 'pink', 'brown']),
    'kind': r.pick(const ['even', 'bands', 'drift']),
    'tint': r.range(-0.12, 0.12),
    'bands': [for (var i = 0, n = r.integer(5, 9); i < n; i++) r.range(0, tau)],
    'ang': r.range(-0.5, 0.5),
  };

  @override
  Rgb tone(ArtRoles c, P p) {
    final colour = p.sOr('colour'), tint = p.dOr('tint', 0);
    final lean = colour == 'white'
        ? c.tile
        : colour == 'pink'
        ? c.accent
        : c.deep;
    final base = mix(
      switch (colour) {
        'white' => _noiseWhite,
        'pink' => _noisePink,
        _ => _noiseBrown,
      },
      lean,
      0.18,
    );
    return mix(
      base,
      tint > 0 ? Rgb.white : _black,
      tint.abs() * (colour == 'white' ? 0.25 : 0.4),
    );
  }

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final colour = p.s('colour');
    final base = tone(c, p),
        coarse = colour == 'brown'
            ? 2.4
            : colour == 'pink'
            ? 1.6
            : 1.0,
        dk = mix(base, _black, colour == 'white' ? 0.1 : 0.25);
    vgradFill(ctx, H, [
      (0, mix(base, Rgb.white, colour == 'brown' ? 0.04 : 0.08), 1),
      (1, dk, 1),
    ]);
    final tex = ArtTextures.instance.noiseGrain;
    if (tex != null) {
      ctx.save();
      ctx.globalCompositeOperation = colour == 'white'
          ? BlendMode.multiply
          : BlendMode.overlay;
      ctx.globalAlpha = colour == 'white'
          ? 0.16
          : colour == 'pink'
          ? 0.32
          : 0.42;
      ctx.fillStyle = CtxPattern(
        tex,
        CtxPattern.translateScale(still ? 0 : 0.05 * S(t, 30), 0, coarse / 256),
      );
      ctx.fillRect(0, 0, 1, H);
      ctx.restore();
    }
    final band = colour == 'white' ? mix(base, c.deep, 0.5) : Rgb.white;
    final bands = p.nums('bands'), kind = p.s('kind');
    if (kind == 'bands') {
      for (var i = 0; i < bands.length; i++) {
        ctx.fillStyle = css(
          band,
          0.05 + 0.025 * (still ? 0 : S(t, 12.0 + i * 2, bands[i])),
        );
        ctx.fillRect(0, H * (i + 0.5) / bands.length, 1, H * 0.035);
      }
    }
    if (kind == 'drift') {
      ctx.save();
      ctx.translate(0.5, H / 2);
      ctx.rotate(p.d('ang'));
      ctx.lineCap = StrokeCap.round;
      for (var i = 0; i < bands.length; i++) {
        final ph = bands[i];
        final y = ((i + 0.5) / bands.length - 0.5) * 1.4 * H;
        ctx.beginPath();
        for (var x = -0.8; x <= 0.8; x += 0.02) {
          ctx.lineTo(
            x,
            y +
                0.02 *
                    math.sin(tau * x * 1.3 + ph + (still ? 0 : tau * t / 24)),
          );
        }
        ctx.strokeStyle = css(band, 0.1);
        ctx.lineWidth = 0.02;
        ctx.stroke();
      }
      ctx.restore();
    }
  }
}
