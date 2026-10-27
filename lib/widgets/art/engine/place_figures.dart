// The page's names (R, L) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 5's place figures (`places.js`): the things that sit in the
/// modern places (window, balcony, terrace, car, metro carriage, room).
/// Same contract as round 4's figures: drawn at `{cx, cy, s}`, in the
/// composition's inks.
final Map<String, Figure> placeFigures = {
  'lamp': const LampFigure(),
  'window': const WindowFigure(),
  'cup': const CupFigure(),
  'porthole': const PortholeFigure(),
  'fan': const FanFigure(),
  'umbrella': const UmbrellaFigure(),
  'railing': const RailingFigure(),
  'droplets': const DropletsFigure(),
  'strap': const StrapFigure(),
  'doorway': const DoorwayFigure(),
};

/// A droplet on glass: body, a darker lower rim, one highlight (`bead`).
/// [light] and [dark] are the page's `k.light || k.glow` and
/// `k.dark || k.line`; every caller here passes both.
void _bead(
  Ctx ctx,
  double x,
  double y,
  double r,
  Rgb light,
  Rgb dark, [
  double a = 1,
]) {
  circle(ctx, x, y, r);
  fillWith(ctx, light, 0.28 * a);
  ctx.beginPath();
  ctx.arc(x, y, r, 0.2, math.pi - 0.2);
  strokeWith(ctx, dark, r * 0.35, 0.45 * a);
  circle(ctx, x - r * 0.35, y - r * 0.35, r * 0.28);
  fillWith(ctx, Rgb.white, 0.55 * a);
}

/// `rr`: a fresh path holding one rounded rectangle.
void _rr(Ctx ctx, double x, double y, double w, double h, double r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

/// Lamp: its light breathes; a pendant sways a little.
class LampFigure extends Figure {
  const LampFigure();

  @override
  String get label => 'lamp';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => {
    ...place,
    'kind': r.pick(const ['table', 'pendant']),
    'shade': r.range(0.8, 1.1),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final b = BR(t, still), s = p.d('s'), cx = p.d('cx'), cy = p.d('cy');
    final shade = p.d('shade');
    if (p.s('kind') == 'table') {
      final top = cy - s * 0.55, bot = cy + s * 0.75;
      glow(ctx, cx, top + s * 0.4, s * 1.8, k.glow, 0.3 + 0.12 * b);
      ctx.beginPath();
      ctx.ellipse(cx, bot, s * 0.4, s * 0.08, 0, 0, tau);
      fillWith(ctx, k.line);
      ctx.beginPath();
      ctx.moveTo(cx, bot);
      ctx.lineTo(cx, top + s * 0.4);
      strokeWith(ctx, k.line, s * 0.06);
      cutPoly(
        ctx,
        [
          (cx - s * 0.32 * shade, top),
          (cx + s * 0.32 * shade, top),
          (cx + s * 0.6 * shade, top + s * 0.5),
          (cx - s * 0.6 * shade, top + s * 0.5),
        ],
        SeededRandom('shade'),
        0.003,
      );
      fillWith(ctx, k.main);
      ctx.beginPath();
      ctx.ellipse(cx, top + s * 0.5, s * 0.6 * shade, s * 0.05, 0, 0, tau);
      fillWith(ctx, k.glow, 0.7 + 0.3 * b);
    } else {
      final a = still ? 0.0 : 0.035 * S(t, 7.5), top = cy - s * 1.3;
      ctx.save();
      ctx.translate(cx, top);
      ctx.rotate(a);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(0, s * 0.9);
      strokeWith(ctx, k.line, s * 0.025);
      final g = ctx.createLinearGradient(0, s * 1.2, 0, s * 2.6)
        ..addColorStop(0, css(k.glow, 0.35 + 0.15 * b))
        ..addColorStop(1, css(k.glow, 0));
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.moveTo(-s * 0.42, s * 1.25);
      ctx.lineTo(s * 0.42, s * 1.25);
      ctx.lineTo(s * 1.0, s * 2.6);
      ctx.lineTo(-s * 1.0, s * 2.6);
      ctx.closePath();
      ctx.fill();
      ctx.beginPath();
      ctx.arc(0, s * 1.25, s * 0.45 * shade, math.pi, tau);
      ctx.closePath();
      fillWith(ctx, k.main);
      circle(ctx, 0, s * 1.28, s * 0.12);
      fillWith(ctx, k.glow, 0.85 + 0.15 * b);
      ctx.restore();
    }
  }
}

/// Window: rain runs down it, or a moon glows in it.
class WindowFigure extends Figure {
  const WindowFigure();

  @override
  String get label => 'window';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => {
    ...place,
    'view': r.pick(const ['rain', 'rain', 'moon']),
    'mull': r.pick(const ['cross', 'vertical']),
    'drops': [
      for (var i = 0; i < 18; i++)
        {'x': r.next(), 'y': r.next(), 'v': r.range(0.05, 0.09)},
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final ps = p.d('s'), cx = p.d('cx'), cy = p.d('cy');
    final w = ps * 1.5, h = ps * 1.9, x0 = cx - w / 2, y0 = cy - h / 2;
    glow(ctx, cx, cy, ps * 1.6, k.glow, 0.18 + 0.08 * BR(t, still));
    ctx.save();
    _rr(ctx, x0, y0, w, h, ps * 0.08);
    ctx.clip();
    ctx.fillStyle = vgradient(ctx, y0, y0 + h, [
      (0, mix(k.alt, k.paper, 0.5), 1),
      (1, k.alt, 1),
    ]);
    ctx.fillRect(x0, y0, w, h);
    if (p.s('view') == 'moon') {
      circle(ctx, x0 + w * 0.68, y0 + h * 0.3, ps * 0.2);
      fillWith(ctx, k.glow, 0.9);
    } else {
      for (final d in p.list('drops')) {
        final u = still ? d.d('y') : jsMod(d.d('y') + t * d.d('v'), 1);
        final x = x0 + d.d('x') * w, y = y0 + u * h;
        ctx.beginPath();
        ctx.moveTo(x, y - 0.03);
        ctx.lineTo(x, y);
        strokeWith(ctx, k.paper, 0.004, 0.7 * fade(u));
      }
    }
    ctx.restore();
    _rr(ctx, x0, y0, w, h, ps * 0.08);
    strokeWith(ctx, k.main, ps * 0.1);
    ctx.beginPath();
    ctx.moveTo(cx, y0);
    ctx.lineTo(cx, y0 + h);
    if (p.s('mull') == 'cross') {
      ctx.moveTo(x0, cy - h * 0.05);
      ctx.lineTo(x0 + w, cy - h * 0.05);
    }
    strokeWith(ctx, k.main, ps * 0.06);
    _rr(
      ctx,
      x0 - ps * 0.12,
      y0 + h + ps * 0.04,
      w + ps * 0.24,
      ps * 0.1,
      0.004,
    );
    fillWith(ctx, k.main);
  }
}

/// Cup with steam: steam curls up and thins away.
class CupFigure extends Figure {
  const CupFigure();

  @override
  String get label => 'cup with steam';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => {
    ...place,
    'wisps': [
      for (var i = 0; i < 3; i++)
        {'dx': (i - 1) * 0.22, 'ph': r.range(0, tau), 'per': r.range(5, 8)},
    ],
    'handle': r.sign(),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final s = p.d('s'), cx = p.d('cx'), cy = p.d('cy'), handle = p.d('handle');
    final top = cy + s * 0.05, bot = cy + s * 0.7, w = s * 0.62;
    ctx.beginPath();
    ctx.ellipse(cx, bot + s * 0.02, s * 0.95, s * 0.14, 0, 0, tau);
    fillWith(ctx, k.alt);
    ctx.beginPath();
    ctx.arc(
      cx + handle * w * 0.98,
      top + s * 0.28,
      s * 0.2,
      -math.pi / 2,
      math.pi / 2,
      handle < 0,
    );
    strokeWith(ctx, k.main, s * 0.09);
    ctx.beginPath();
    ctx.moveTo(cx - w, top);
    ctx.bezierCurveTo(cx - w, bot - s * 0.1, cx - w * 0.75, bot, cx, bot);
    ctx.bezierCurveTo(cx + w * 0.75, bot, cx + w, bot - s * 0.1, cx + w, top);
    ctx.closePath();
    fillWith(ctx, k.main);
    ctx.beginPath();
    ctx.ellipse(cx, top, w, s * 0.1, 0, 0, tau);
    fillWith(ctx, k.line);
    for (final q in p.list('wisps')) {
      ctx.beginPath();
      for (var i = 0; i <= 40; i++) {
        final u = i / 40, y = top - s * 0.15 - u * s * 1.2;
        final x =
            cx +
            q.d('dx') * s +
            s *
                0.12 *
                u *
                math.sin(
                  tau * u * 1.2 -
                      (still ? 0 : tau * t / q.d('per')) +
                      q.d('ph'),
                );
        if (i != 0) {
          ctx.lineTo(x, y);
        } else {
          ctx.moveTo(x, y);
        }
      }
      final g = ctx.createLinearGradient(0, top - s * 0.15, 0, top - s * 1.35)
        ..addColorStop(0, css(k.line, 0.55))
        ..addColorStop(1, css(k.line, 0));
      ctx.strokeStyle = g;
      ctx.lineWidth = s * 0.05;
      ctx.lineCap = StrokeCap.round;
      ctx.stroke();
    }
  }
}

/// Washing-machine porthole: the drum turns slowly, the water rocking.
class PortholeFigure extends Figure {
  const PortholeFigure();

  @override
  String get label => 'washing-machine porthole';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => {
    ...place,
    'clothes': [
      for (var i = 0; i < 3; i++)
        {
          'a': r.range(0, tau),
          'd': r.range(0.25, 0.55),
          'r': r.range(0.18, 0.3),
          'role': r.pick(const ['alt', 'glow', 'paper']),
        },
    ],
    'per': r.range(10, 14),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final s = p.d('s'), pcx = p.d('cx'), pcy = p.d('cy'), per = p.d('per');
    final R = s * 0.62, cy = pcy + s * 0.08;
    _rr(ctx, pcx - s * 0.95, pcy - s * 0.95, s * 1.9, s * 1.95, s * 0.12);
    fillWith(ctx, k.main);
    ctx.beginPath();
    ctx.moveTo(pcx - s * 0.95, pcy - s * 0.62);
    ctx.lineTo(pcx + s * 0.95, pcy - s * 0.62);
    strokeWith(ctx, k.line, 0.004, 0.6);
    for (final u in const [0.55, 0.7]) {
      circle(ctx, pcx + s * u, pcy - s * 0.78, s * 0.06);
      fillWith(ctx, k.line);
    }
    circle(ctx, pcx, cy, R * 1.18);
    fillWith(ctx, k.line);
    ctx.save();
    circle(ctx, pcx, cy, R);
    ctx.clip();
    ctx.fillStyle = css(mix(k.alt, k.paper, 0.4));
    ctx.fillRect(pcx - R, cy - R, R * 2, R * 2);
    final rot = still ? 0.0 : tau * t / per;
    for (final q in p.list('clothes')) {
      final a = q.d('a') + rot;
      final x = pcx + math.cos(a) * R * q.d('d');
      final y = cy + math.sin(a) * R * q.d('d');
      ctx.beginPath();
      ctx.ellipse(x, y, R * q.d('r'), R * q.d('r') * 0.6, a, 0, tau);
      fillWith(ctx, _role(k, q.s('role')), 0.85);
    }
    final wl = cy + R * (0.25 + (still ? 0 : 0.06 * S(t, per / 2)));
    ctx.beginPath();
    ctx.moveTo(pcx - R, wl);
    for (var x = -R; x <= R; x += R / 12) {
      ctx.lineTo(
        pcx + x,
        wl + R * 0.05 * math.sin(x / R * 5 + (still ? 0 : t)),
      );
    }
    ctx.lineTo(pcx + R, cy + R);
    ctx.lineTo(pcx - R, cy + R);
    ctx.closePath();
    fillWith(ctx, k.alt, 0.45);
    circle(ctx, pcx - R * 0.4, cy - R * 0.45, R * 0.18);
    fillWith(ctx, Rgb.white, 0.25);
    ctx.restore();
    circle(ctx, pcx, cy, R);
    strokeWith(ctx, k.glow, s * 0.05, 0.7);
  }

  /// `k[q.role]`.
  static Rgb _role(Inks k, String role) => switch (role) {
    'alt' => k.alt,
    'glow' => k.glow,
    'paper' => k.paper,
    'main' => k.main,
    'line' => k.line,
    _ => throw ArgumentError.value(role, 'role'),
  };
}

/// Fan: the blades turn slowly behind the guard.
class FanFigure extends Figure {
  const FanFigure();

  @override
  String get label => 'fan';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => {
    ...place,
    'n': r.pick(const [3, 4, 5]),
    'per': r.range(6, 9),
    'stand': r.chance(0.6),
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final s = p.d('s'), cx = p.d('cx'), cy = p.d('cy'), n = p.i('n');
    final R = s * 0.85, rot = still ? 0.3 : tau * t / p.d('per');
    if (p.b('stand')) {
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx, cy + s * 1.35);
      strokeWith(ctx, k.line, s * 0.07);
      ctx.beginPath();
      ctx.ellipse(cx, cy + s * 1.38, s * 0.5, s * 0.08, 0, 0, tau);
      fillWith(ctx, k.line);
    }
    for (var i = 0; i < n; i++) {
      final a = rot + i / n * tau;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.bezierCurveTo(
        cx + math.cos(a - 0.5) * R * 0.5,
        cy + math.sin(a - 0.5) * R * 0.5,
        cx + math.cos(a - 0.35) * R * 0.95,
        cy + math.sin(a - 0.35) * R * 0.95,
        cx + math.cos(a) * R * 0.92,
        cy + math.sin(a) * R * 0.92,
      );
      ctx.bezierCurveTo(
        cx + math.cos(a + 0.25) * R * 0.8,
        cy + math.sin(a + 0.25) * R * 0.8,
        cx + math.cos(a + 0.3) * R * 0.3,
        cy + math.sin(a + 0.3) * R * 0.3,
        cx,
        cy,
      );
      fillWith(ctx, k.main, 0.92);
    }
    circle(ctx, cx, cy, R * 0.16);
    fillWith(ctx, k.alt);
    circle(ctx, cx, cy, R * 1.05);
    strokeWith(ctx, k.line, s * 0.025, 0.8);
    for (var i = 0; i < 16; i++) {
      final a = i / 16 * tau;
      ctx.beginPath();
      ctx.moveTo(cx + math.cos(a) * R * 0.2, cy + math.sin(a) * R * 0.2);
      ctx.lineTo(cx + math.cos(a) * R * 1.05, cy + math.sin(a) * R * 1.05);
      strokeWith(ctx, k.line, 0.002, 0.35);
    }
    circle(ctx, cx, cy, R * 0.6);
    strokeWith(ctx, k.line, 0.002, 0.35);
  }
}

/// Umbrella: sways under the rain; drips fall from the ribs.
class UmbrellaFigure extends Figure {
  const UmbrellaFigure();

  @override
  String get label => 'umbrella';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => {
    ...place,
    'ribs': r.integer(5, 7),
    'drops': [
      for (var i = 0; i < 16; i++)
        {'x': r.range(-1.6, 1.6), 'y': r.next(), 'v': r.range(0.07, 0.11)},
    ],
    'drips': [
      for (var i = 0; i < 4; i++)
        {'i': r.next(), 'y': r.next(), 'v': r.range(0.05, 0.08)},
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final s = p.d('s'), cx = p.d('cx'), cy = p.d('cy'), ribs = p.i('ribs');
    final R = s * 1.05, top = cy - s * 0.35, a = still ? 0.0 : 0.05 * S(t, 8);
    for (final d in p.list('drops')) {
      final u = still ? d.d('y') : jsMod(d.d('y') + t * d.d('v'), 1);
      final x = cx + d.d('x') * s, y = cy - s * 1.5 + u * s * 3;
      if ((x - cx).abs() < R && y > top - R * 0.5 && y < top + s * 0.1) {
        continue;
      }
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x - 0.004, y + 0.035);
      strokeWith(ctx, k.line, 0.003, 0.6 * fade(u));
    }
    ctx.save();
    ctx.translate(cx, top);
    ctx.rotate(a);
    ctx.beginPath();
    ctx.moveTo(0, -R * 0.62);
    ctx.lineTo(0, s * 1.15);
    ctx.arc(-s * 0.13, s * 1.15, s * 0.13, 0, math.pi);
    strokeWith(ctx, k.line, s * 0.05);
    ctx.beginPath();
    ctx.moveTo(-R, 0);
    ctx.bezierCurveTo(-R, -R * 0.75, R, -R * 0.75, R, 0);
    for (var i = ribs; i > 0; i--) {
      final x1 = -R + (2 * R) * (i - 1) / ribs, x2 = -R + (2 * R) * i / ribs;
      ctx.quadraticCurveTo((x1 + x2) / 2, -R * 0.08, x1, 0);
    }
    ctx.closePath();
    fillWith(ctx, k.main);
    for (var i = 1; i < ribs; i++) {
      final x = -R + (2 * R) * i / ribs;
      ctx.beginPath();
      ctx.moveTo(0, -R * 0.58);
      ctx.quadraticCurveTo(x * 0.6, -R * 0.45, x, 0);
      strokeWith(ctx, k.alt, 0.003, 0.6);
    }
    for (final q in p.list('drips')) {
      final u = still ? q.d('y') : jsMod(q.d('y') + t * q.d('v'), 1);
      final x = -R + 2 * R * (q.d('i') * ribs + 0.5).floor() / ribs;
      circle(ctx, x, u * s * 0.9, 0.007);
      fillWith(ctx, k.line, fade(u) * 0.8);
    }
    ctx.restore();
  }
}

/// Railing: beads gather on the rail and drip.
class RailingFigure extends Figure {
  const RailingFigure();

  @override
  String get label => 'railing';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => {
    ...place,
    'n': r.integer(5, 8),
    'beads': [
      for (var i = 0; i < 10; i++) {'x': r.next(), 'r': r.range(0.005, 0.01)},
    ],
    'drips': [
      for (var i = 0; i < 4; i++)
        {'x': r.next(), 'y': r.next(), 'v': r.range(0.06, 0.1)},
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final s = p.d('s'), cx = p.d('cx'), cy = p.d('cy'), n = p.i('n');
    final x0 = cx - s * 1.3, x1 = cx + s * 1.3;
    final y0 = cy - s * 0.3, y1 = cy + s * 0.8;
    ctx.fillStyle = css(k.main);
    ctx.fillRect(x0, y0, x1 - x0, s * 0.09);
    ctx.fillRect(x0, y1, x1 - x0, s * 0.07);
    for (var i = 0; i <= n; i++) {
      final x = lerp(x0 + s * 0.05, x1 - s * 0.05, i / n);
      ctx.fillRect(x - s * 0.025, y0, s * 0.05, y1 - y0);
    }
    for (final b in p.list('beads')) {
      _bead(
        ctx,
        lerp(x0, x1, b.d('x')),
        y0 + s * 0.11,
        b.d('r'),
        k.paper,
        k.line,
      );
    }
    for (final d in p.list('drips')) {
      final u = still ? d.d('y') : jsMod(d.d('y') + t * d.d('v'), 1);
      final x = lerp(x0, x1, d.d('x'));
      circle(ctx, x, y0 + s * 0.12 + u * s * 1.2, 0.006);
      fillWith(ctx, k.line, fade(u) * 0.8);
    }
  }
}

/// Droplets: beads sit; a few slide down, leaving a trail.
class DropletsFigure extends Figure {
  const DropletsFigure();

  @override
  String get label => 'droplets';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) {
    final n = r.integer(24, 36);
    return {
      ...place,
      'beads':
          [
            for (var i = 0; i < n; i++)
              {
                'x': r.range(-1, 1),
                'y': r.range(-1, 1),
                'r': r.range(0.006, 0.018),
              },
          ].where((b) {
            final x = b['x']!, y = b['y']!;
            return x * x + y * y < 1.1;
          }).toList(),
      'runs': [
        for (var i = 0; i < 4; i++)
          {'x': r.range(-0.8, 0.8), 'y': r.next(), 'v': r.range(0.03, 0.05)},
      ],
    };
  }

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final s = p.d('s') * 1.15, cx = p.d('cx'), cy = p.d('cy');
    for (final b in p.list('beads')) {
      _bead(
        ctx,
        cx + b.d('x') * s,
        cy + b.d('y') * s,
        b.d('r') * 1.3,
        k.main,
        k.line,
      );
    }
    for (final q in p.list('runs')) {
      final u = still ? q.d('y') : jsMod(q.d('y') + t * q.d('v'), 1);
      final x = cx + q.d('x') * s, y = cy - s + u * s * 2;
      ctx.beginPath();
      ctx.moveTo(x, y - s * 0.4 * u);
      ctx.lineTo(x + 0.002, y);
      strokeWith(ctx, k.main, 0.004, 0.4 * fade(u));
      _bead(ctx, x, y, 0.016, k.main, k.line, fade(u));
    }
  }
}

/// Handrail straps: the straps swing gently with the carriage.
class StrapFigure extends Figure {
  const StrapFigure();

  @override
  String get label => 'handrail straps';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => {
    ...place,
    'n': r.integer(2, 4),
    'kind': r.pick(const ['ring', 'triangle']),
    'straps': [
      for (var i = 0; i < 4; i++)
        {'ph': r.range(0, tau), 'len': r.range(0.75, 1.05)},
    ],
  };

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final s = p.d('s'), cx = p.d('cx'), cy = p.d('cy'), n = p.i('n');
    final bar = cy - s * 0.9, straps = p.list('straps');
    ctx.beginPath();
    ctx.moveTo(cx - s * 1.5, bar);
    ctx.lineTo(cx + s * 1.5, bar);
    strokeWith(ctx, k.line, s * 0.07);
    for (var i = 0; i < n; i++) {
      final q = straps[i], x = cx + (i - (n - 1) / 2) * s * 0.9;
      final a = still ? 0.0 : 0.09 * S(t, 4.3, q.d('ph') * 0.2);
      final L = s * q.d('len') * 1.1;
      ctx.save();
      ctx.translate(x, bar);
      ctx.rotate(a);
      _rr(ctx, -s * 0.07, 0, s * 0.14, L, s * 0.04);
      fillWith(ctx, k.main);
      ctx.beginPath();
      if (p.s('kind') == 'ring') {
        ctx.arc(0, L + s * 0.2, s * 0.2, 0, tau);
      } else {
        ctx.moveTo(0, L - s * 0.02);
        ctx.lineTo(s * 0.24, L + s * 0.36);
        ctx.lineTo(-s * 0.24, L + s * 0.36);
        ctx.closePath();
      }
      strokeWith(ctx, k.alt, s * 0.07);
      ctx.restore();
    }
  }
}

/// Doorway with light: the light inside breathes and spills on the floor.
class DoorwayFigure extends Figure {
  const DoorwayFigure();

  @override
  String get label => 'doorway with light';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => {...place, 'arch': r.chance(0.4), 'ajar': r.range(0.2, 0.5)};

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {
    final s = p.d('s'), cx = p.d('cx'), cy = p.d('cy'), b = BR(t, still);
    final arch = p.b('arch'), ajar = p.d('ajar');
    final w = s * 0.9, h = s * 1.7, x0 = cx - w / 2, y0 = cy - h / 2;
    final bot = y0 + h;
    final g = ctx.createLinearGradient(0, bot, 0, bot + s * 0.8)
      ..addColorStop(0, css(k.glow, 0.45 + 0.15 * b))
      ..addColorStop(1, css(k.glow, 0));
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.moveTo(x0, bot);
    ctx.lineTo(x0 + w, bot);
    ctx.lineTo(x0 + w * 1.6, bot + s * 0.8);
    ctx.lineTo(x0 - w * 0.5, bot + s * 0.8);
    ctx.closePath();
    ctx.fill();
    void door() {
      ctx.beginPath();
      ctx.moveTo(x0, bot);
      if (arch) {
        ctx.lineTo(x0, y0 + w / 2);
        ctx.arc(cx, y0 + w / 2, w / 2, math.pi, 0);
      } else {
        ctx.lineTo(x0, y0);
        ctx.lineTo(x0 + w, y0);
      }
      ctx.lineTo(x0 + w, bot);
      ctx.closePath();
    }

    door();
    ctx.fillStyle = vgradient(ctx, y0, bot, [
      (0, mix(k.glow, k.paper, 0.2), 1),
      (1, k.glow, 1),
    ]);
    ctx.globalAlpha = 0.75 + 0.25 * b;
    ctx.fill();
    ctx.globalAlpha = 1;
    door();
    strokeWith(ctx, k.main, s * 0.08);
    ctx.beginPath();
    ctx.moveTo(x0 + w, bot);
    ctx.lineTo(x0 + w - w * ajar, bot - s * 0.06);
    ctx.lineTo(x0 + w - w * ajar, y0 + (arch ? w * 0.3 : s * 0.06));
    ctx.lineTo(x0 + w, y0 + (arch ? w / 2 : 0));
    ctx.closePath();
    fillWith(ctx, k.main, 0.9);
  }
}
