// The page's names (H, R) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 5's place grounds (`places.js`): the modern places, each a ground
/// that fills the whole card (unit wide, H tall). A pinned `variant` in the
/// build options picks a balcony's or a terrace's way of being there.
final Map<String, Ground> placeGrounds = {
  'window': const WindowGround(),
  'balcony': const BalconyGround(),
  'terrace': const TerraceGround(),
  'car': const CarGround(),
  'metro': const MetroGround(),
  'room': const RoomGround(),
};

// ---------- helpers (private copies; the figures keep their own) ----------

void _rr(Ctx ctx, double x, double y, double w, double h, double r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

/// A droplet on glass: body, a darker lower rim, one highlight.
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

double _fr(double x) => x - x.floorToDouble();

double _hsh(double n) => _fr(math.sin(n * 127.1 + 311.7) * 43758.5453);

/// A soft puddle outline.
void _pond(
  Ctx ctx,
  double x,
  double y,
  double R,
  List<List<double>> harm, [
  double sq = 1,
]) {
  ctx.beginPath();
  for (var i = 0; i <= 48; i++) {
    final a = (i / 48) * tau;
    var r = R;
    for (final h in harm) {
      r += R * h[1] * math.sin(h[0] * a + h[2]);
    }
    final px = x + math.cos(a) * r, py = y + math.sin(a) * r * sq;
    if (i != 0) {
      ctx.lineTo(px, py);
    } else {
      ctx.moveTo(px, py);
    }
  }
  ctx.closePath();
}

/// Rain rings: each slot opens a ring, fades, and reappears elsewhere in
/// its puddle while unseen. [x], [y], [R] and [seed] are the puddle's.
void _rainRings(
  Ctx ctx,
  double qx,
  double qy,
  double qr,
  double seed,
  int n,
  Rgb col,
  double t,
  bool still, [
  double sq = 1,
  double speed = 1,
]) {
  if (still) return;
  for (var i = 0; i < n; i++) {
    final per = 1.6 + _hsh(seed + i) * 1.4,
        raw = t * speed / per + _hsh(seed * 3 + i),
        cyc = raw.floorToDouble(),
        u = raw - cyc;
    final a = _hsh(seed + i * 7 + cyc * 13) * tau,
        d = math.sqrt(_hsh(seed + i * 5 + cyc * 17)) * qr * 0.65;
    final x = qx + math.cos(a) * d,
        y = qy + math.sin(a) * d * sq,
        rr0 = qr * (0.05 + 0.3 * u);
    ctx.beginPath();
    ctx.ellipse(x, y, rr0, rr0 * sq, 0, 0, tau);
    strokeWith(ctx, col, 0.005, 0.9 * math.pow(1 - u, 1.5));
    if (u > 0.25) {
      final r1 = qr * (0.05 + 0.3 * (u - 0.25));
      ctx.beginPath();
      ctx.ellipse(x, y, r1, r1 * sq, 0, 0, tau);
      strokeWith(ctx, col, 0.0035, 0.65 * math.pow(1 - u, 1.5));
    }
  }
}

void _potFromAbove(
  Ctx ctx,
  double x,
  double y,
  double R,
  int leaves,
  ArtRoles c,
  double t,
  bool still,
  double ph,
) {
  circle(ctx, x + R * 0.12, y + R * 0.14, R * 1.05);
  fillWith(ctx, c.deep, 0.3);
  circle(ctx, x, y, R);
  fillWith(ctx, mix(c.accent, c.deep, 0.3));
  circle(ctx, x, y, R * 0.82);
  fillWith(ctx, mix(c.deep, c.form, 0.15));
  final sw = still ? 0.0 : 0.04 * S(t, 7, ph);
  for (var i = 0; i < leaves; i++) {
    final a = (i / leaves) * tau + ph + sw * (i.isOdd ? 1 : -1),
        L = R * (1.15 + 0.35 * _hsh(ph * 10 + i));
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(a);
    ctx.beginPath();
    ctx.ellipse(L * 0.55, 0, L * 0.55, R * 0.22, 0, 0, tau);
    fillWith(ctx, mix(c.form, c.deep, 0.35 + 0.25 * (i % 2)));
    ctx.beginPath();
    ctx.moveTo(R * 0.1, 0);
    ctx.lineTo(L * 0.95, 0);
    strokeWith(ctx, c.light, 0.002, 0.25);
    ctx.restore();
  }
}

/// A list of `[a, b, c]` number triples held in params.
List<List<double>> _triples(P p, String key) => [
  for (final e in p.raw(key))
    [for (final v in e! as List) (v as num).toDouble()],
];

// ---------- grounds ----------

/// Looking out through a window from a dim room: the frame, blurred lights
/// outside, rain beading and trickling down the glass.
class WindowGround extends Ground {
  const WindowGround();

  @override
  String get label => 'window';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'x': r.range(0.12, 0.18),
    'y': r.range(0.1, 0.15),
    'w': r.range(0.64, 0.74),
    'h': r.range(0.66, 0.74),
    'mull': r.pick(const ['cross', 'vertical', 'none']),
    'out': r.pick(const ['grey', 'dusk', 'night']),
    'lights': [
      for (var i = 0; i < 9; i++)
        {
          'x': r.next(),
          'y': r.range(0.35, 0.95),
          'r': r.range(0.03, 0.08),
          'ph': r.range(0, tau),
          'role': r.pick(const ['accent', 'light', 'accent']),
        },
    ],
    'beads': [
      for (var i = 0; i < 34; i++)
        {'x': r.next(), 'y': r.next(), 'r': r.range(0.004, 0.012)},
    ],
    'runs': [
      for (var i = 0; i < 6; i++)
        {
          'x': r.next(),
          'y': r.next(),
          'v': r.range(0.025, 0.05),
          'len': r.range(0.06, 0.16),
        },
    ],
  };

  @override
  Rgb tone(ArtRoles c, P p) => switch (p.s('out')) {
    'grey' => mix(c.tile, c.form, 0.45),
    'dusk' => mix(c.accent, c.deep, 0.45),
    _ => mix(c.deep, c.form, 0.25),
  };

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    vgradFill(ctx, H, [
      (0, mix(c.deep, c.form, 0.15), 1),
      (1, mix(c.deep, c.accent, 0.1), 1),
    ]);
    glow(ctx, 0.1, H * 0.95, 0.5, c.accent, 0.22);
    final x0 = p.d('x'), y0 = p.d('y') * H, w = p.d('w'), h = p.d('h') * H;
    ctx.save();
    _rr(ctx, x0, y0, w, h, 0.02);
    ctx.clip();
    ctx.fillStyle = vgradient(ctx, y0, y0 + h, [
      (0, mix(tone(c, p), c.tile, 0.15), 1),
      (1, tone(c, p), 1),
    ]);
    ctx.fillRect(x0, y0, w, h);
    for (final L in p.list('lights')) {
      glow(
        ctx,
        x0 + L.d('x') * w,
        y0 + L.d('y') * h,
        L.d('r'),
        c.role(L.s('role')),
        0.45 * (still ? 1 : 0.8 + 0.2 * S(t, 10, L.d('ph'))),
      );
    }
    for (final b in p.list('beads')) {
      _bead(
        ctx,
        x0 + b.d('x') * w,
        y0 + b.d('y') * h,
        b.d('r'),
        c.light,
        c.deep,
        0.9,
      );
    }
    for (final q in p.list('runs')) {
      final u = still ? q.d('y') : jsMod(q.d('y') + t * q.d('v'), 1),
          y = y0 + u * h,
          x = x0 + q.d('x') * w;
      ctx.beginPath();
      ctx.moveTo(x, y - q.d('len') * h * 0.6);
      ctx.lineTo(x + 0.002, y);
      strokeWith(ctx, c.light, 0.003, 0.35 * fade(u));
      _bead(ctx, x, y, 0.009, c.light, c.deep, fade(u));
    }
    ctx.restore();
    final frame = mix(c.deep, c.tile, 0.22), mull = p.s('mull');
    _rr(ctx, x0, y0, w, h, 0.02);
    strokeWith(ctx, frame, 0.03);
    ctx.beginPath();
    if (mull != 'none') {
      ctx.moveTo(x0 + w / 2, y0);
      ctx.lineTo(x0 + w / 2, y0 + h);
    }
    if (mull == 'cross') {
      ctx.moveTo(x0, y0 + h * 0.45);
      ctx.lineTo(x0 + w, y0 + h * 0.45);
    }
    strokeWith(ctx, frame, 0.018);
    ctx.fillStyle = css(mix(frame, c.light, 0.15));
    ctx.fillRect(x0 - 0.03, y0 + h + 0.01, w + 0.06, 0.03);
  }
}

/// A balcony railing against a rainy or dusk sky, with a far skyline. Its
/// "terrace" variant (a parapet over a floor with puddles) was too close to
/// the balcony; no class uses it now, and the terrace has its own ground
/// below. It stays so the variant field in frozen params keeps its meaning.
class BalconyGround extends Ground {
  const BalconyGround();

  @override
  String get label => 'balcony or terrace';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'variant': truthy(o['variant'])
        ? o['variant']
        : r.pick(const ['balcony', 'terrace']),
    'sky': r.pick(const ['rain', 'rain', 'dusk']),
    'rail': r.range(0.6, 0.68),
    'bal': r.integer(7, 12),
    'city': [
      for (var i = 0, n = r.integer(8, 14); i < n; i++)
        {
          'w': r.range(0.05, 0.12),
          'h': r.range(0.08, 0.28),
          'lit': [
            for (var j = 0; j < 4; j++) [r.next(), r.next(), r.range(0, tau)],
          ],
        },
    ],
    'drops': [
      for (var i = 0; i < 45; i++)
        {
          'x': r.range(-0.1, 1.1),
          'y': r.next(),
          'l': r.range(0.04, 0.09),
          'v': r.range(0.06, 0.1),
          'a': r.range(0.15, 0.4),
        },
    ],
    'pud': [
      for (var i = 0; i < 3; i++)
        {
          'x': r.range(0.2, 0.8),
          'w': r.range(0.12, 0.24),
          'ph': r.range(0, tau),
        },
    ],
  };

  @override
  Rgb tone(ArtRoles c, P p) => p.s('sky') == 'dusk'
      ? mix(c.accent, c.form, 0.5)
      : mix(c.tile, c.form, 0.5);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final dusk = p.s('sky') == 'dusk';
    final sky0 = dusk ? mix(c.form, c.deep, 0.3) : mix(c.form, c.deep, 0.25),
        sky1 = dusk ? mix(c.accent, c.tile, 0.3) : mix(c.tile, c.form, 0.35);
    vgradFill(ctx, H, [(0, sky0, 1), (0.6, sky1, 1), (1, sky1, 1)]);
    final rail = p.d('rail');
    final horizon = rail * H - 0.02;
    var x = -0.02;
    for (final b in p.list('city')) {
      final bw = b.d('w');
      final top = horizon - b.d('h') * H;
      ctx.fillStyle = css(mix(c.form, c.deep, 0.45), 0.8);
      ctx.fillRect(x, top, bw, horizon - top + 0.05);
      for (final l in _triples(b, 'lit')) {
        ctx.fillStyle = css(c.accent, still ? 0.6 : 0.4 + 0.3 * S(t, 9, l[2]));
        ctx.fillRect(
          x + l[0] * (bw - 0.012),
          top + l[1] * (horizon - top) * 0.8,
          0.008,
          0.01,
        );
      }
      x += bw + 0.005;
    }
    ctx.lineCap = StrokeCap.round;
    ctx.lineWidth = 0.003;
    if (p.s('sky') == 'rain') {
      for (final d in p.list('drops')) {
        final y =
            (jsMod(d.d('y') + (still ? 0 : t * d.d('v')), 1.15) - 0.1) * H;
        ctx.strokeStyle = css(c.light, d.d('a'));
        ctx.beginPath();
        ctx.moveTo(d.d('x'), y);
        ctx.lineTo(d.d('x') - d.d('l') * 0.1, y + d.d('l') * H);
        ctx.stroke();
      }
    }
    final ink = mix(c.deep, c.form, 0.1), ry = rail * H;
    if (p.s('variant') == 'balcony') {
      final bal = p.i('bal');
      ctx.fillStyle = css(ink);
      ctx.fillRect(-0.05, ry, 1.1, 0.022);
      ctx.fillRect(-0.05, H - 0.07, 1.1, 0.07);
      for (var i = 0; i < bal; i++) {
        final bx = (i + 0.5) / bal;
        ctx.fillRect(bx - 0.006, ry, 0.012, H - ry - 0.06);
      }
      for (var i = 0; i < bal * 2; i++) {
        _bead(
          ctx,
          (i + 0.3) / (bal * 2),
          ry + 0.026,
          0.005,
          c.light,
          c.deep,
          0.8,
        );
      }
    } else {
      ctx.fillStyle = css(ink);
      ctx.fillRect(-0.05, ry, 1.1, 0.07);
      ctx.fillStyle = vgradient(ctx, ry + 0.07, H, [
        (0, mix(c.form, c.deep, 0.55), 1),
        (1, mix(c.form, c.deep, 0.35), 1),
      ]);
      ctx.fillRect(0, ry + 0.07, 1, H);
      ctx.strokeStyle = css(c.light, 0.12);
      ctx.lineWidth = 0.003;
      for (var i = 1; i < 6; i++) {
        final y = ry + 0.07 + (H - ry - 0.07) * math.pow(i / 6, 1.4);
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(1, y);
        ctx.stroke();
      }
      for (final q in p.list('pud')) {
        ctx.beginPath();
        ctx.ellipse(q.d('x'), H * 0.9, q.d('w'), 0.02, 0, 0, tau);
        ctx.fillStyle = css(
          mix(sky1, c.light, 0.2),
          still ? 0.45 : 0.35 + 0.15 * S(t, 8, q.d('ph')),
        );
        ctx.fill();
      }
    }
  }
}

/// A terrace, its own place (round 5 follow-up; balcony keeps the skyline).
/// Three ways to be there:
///
/// - tiles: looking down on wet stone or terracotta, puddles with rings
///   opening in them, a potted plant or two;
/// - eave: under the eave, drops running off its edge in a line, a garden
///   beyond in the rain;
/// - court: a walled roof garden at evening, rain on the paving, a lamp's
///   warm light in it.
class TerraceGround extends Ground {
  const TerraceGround();

  @override
  String get label => 'terrace';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) {
    final variant = truthy(o['variant'])
        ? o['variant']
        : r.pick(const ['tiles', 'eave', 'court']);
    return {
      'variant': variant,
      'stone': r.chance(0.5),
      'n': r.integer(4, 6),
      'ang': r.range(-0.22, 0.22),
      'shade': [for (var i = 0; i < 64; i++) r.range(-1, 1)],
      'pud': [
        for (var i = 0, n = r.integer(2, 3); i < n; i++)
          {
            'x': r.range(0.2, 0.8),
            'y': r.range(0.25, 0.85),
            'r': r.range(0.1, 0.17),
            'seed': r.range(1, 99) + i,
            'harm': [
              [2, r.range(0.06, 0.14), r.range(0, tau)],
              [3, r.range(0.04, 0.1), r.range(0, tau)],
              [5, r.range(0.02, 0.05), r.range(0, tau)],
            ],
          },
      ],
      'pots': [
        for (var i = 0; i < 2; i++)
          {
            'x': i != 0 ? r.range(0.74, 0.84) : r.range(0.16, 0.26),
            'y': i != 0 ? r.range(0.72, 0.82) : r.range(0.16, 0.26),
            'r': i != 0 ? r.range(0.07, 0.09) : r.range(0.1, 0.13),
            'leaves': r.integer(7, 11),
            'ph': r.range(0, tau),
          },
      ],
      'eave': r.range(0.2, 0.26),
      'drips': r.integer(11, 16),
      'dseed': r.range(1, 99),
      'beam': r.chance(0.5),
      'hedge': [
        for (var i = 0; i < 7; i++)
          {'x': r.next(), 'w': r.range(0.12, 0.26), 'h': r.range(0.06, 0.16)},
      ],
      'trees': [
        for (var i = 0, n = r.integer(2, 3); i < n; i++)
          {
            'x': r.range(0.1, 0.9),
            'r': r.range(0.08, 0.14),
            'h': r.range(0.12, 0.22),
          },
      ],
      'drops': [
        for (var i = 0; i < 40; i++)
          {
            'x': r.next(),
            'y': r.next(),
            'l': r.range(0.03, 0.07),
            'v': r.range(0.07, 0.11),
            'a': r.range(0.12, 0.3),
          },
      ],
      'wall': r.range(0.5, 0.58),
      'lamp': r.range(0.25, 0.75),
      'cypress': r.range(0.1, 0.3),
      'bushes': [
        for (var i = 0; i < 4; i++) {'x': r.next(), 'r': r.range(0.04, 0.07)},
      ],
    };
  }

  @override
  Rgb tone(ArtRoles c, P p) => switch (p.s('variant')) {
    'tiles' =>
      p.b('stone') ? mix(c.tile, c.form, 0.45) : mix(c.accent, c.deep, 0.35),
    'court' => mix(c.accent, c.form, 0.45),
    _ => mix(c.tile, c.form, 0.45),
  };

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final ink = mix(c.deep, c.form, 0.1), variant = p.s('variant');
    if (variant == 'tiles') {
      _tiles(ctx, p, c, t, still, H);
    } else if (variant == 'eave') {
      _eave(ctx, p, c, t, still, H, ink);
    } else {
      _court(ctx, p, c, t, still, H);
    }
  }

  void _tiles(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final n = p.i('n'), stone = p.b('stone');
    final base = stone ? mix(c.tile, c.form, 0.45) : mix(c.accent, c.deep, 0.3),
        grout = mix(base, c.deep, 0.45),
        ts = 1 / n;
    ctx.fillStyle = css(grout);
    ctx.fillRect(0, 0, 1, H);
    ctx.save();
    ctx.translate(0.5, H / 2);
    ctx.rotate(p.d('ang'));
    ctx.translate(-0.5, -H / 2);
    var k = 0;
    final shade = p.nums('shade');
    for (var iy = -2; iy < n * H + 2; iy++) {
      for (var ix = -2; ix < n + 2; ix++) {
        final v = shade[(k++) % shade.length],
            off = !stone && iy.remainder(2) != 0 ? ts / 2 : 0.0,
            x = ix * ts + off,
            y = iy * ts;
        _rr(ctx, x + 0.004, y + 0.004, ts - 0.008, ts - 0.008, 0.006);
        ctx.fillStyle = css(
          mix(base, v > 0 ? c.light : c.deep, v.abs() * 0.12),
        );
        ctx.fill();
      }
    }
    ctx.restore();
    // the wet sheen: a slow broad light across the tiles
    final g = ctx.createLinearGradient(0, 0, 1, H)
      ..addColorStop(0, css(c.light, 0))
      ..addColorStop(0.45 + (still ? 0 : 0.05 * S(t, 12)), css(c.light, 0.12))
      ..addColorStop(0.7, css(c.light, 0));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 1, H);
    for (final q in p.list('pud')) {
      final qx = q.d('x'), qy = q.d('y') * H, qr = q.d('r');
      final harm = _triples(q, 'harm');
      _pond(ctx, qx, qy, qr, harm);
      fillWith(ctx, mix(base, c.deep, 0.4), 0.55);
      _pond(ctx, qx, qy, qr * 0.9, harm);
      fillWith(ctx, mix(c.tile, c.light, 0.35), 0.4);
      _pond(ctx, qx, qy, qr, harm);
      strokeWith(ctx, mix(base, c.deep, 0.5), 0.004, 0.5);
      ctx.save();
      _pond(ctx, qx, qy, qr, harm);
      ctx.clip();
      _rainRings(ctx, qx, qy, qr, q.d('seed'), 3, c.light, t, still);
      ctx.restore();
    }
    // a few splashes on the open tiles
    if (!still) {
      for (var i = 0; i < 10; i++) {
        final raw = t / 0.9 + _hsh(i + 3.3),
            cyc = raw.floorToDouble(),
            u = raw - cyc,
            x = _hsh(i * 9 + cyc * 3.7),
            y = _hsh(i * 4 + cyc * 5.1) * H;
        ctx.beginPath();
        ctx.arc(x, y, 0.004 + 0.012 * u, 0, tau);
        strokeWith(ctx, c.light, 0.002, 0.45 * (1 - u));
      }
    }
    for (final q in p.list('pots')) {
      _potFromAbove(
        ctx,
        q.d('x'),
        q.d('y') * H,
        q.d('r'),
        q.i('leaves'),
        c,
        t,
        still,
        q.d('ph'),
      );
    }
  }

  void _eave(
    Ctx ctx,
    P p,
    ArtRoles c,
    double t,
    bool still,
    double H,
    Rgb ink,
  ) {
    final eY = p.d('eave') * H,
        floor = H * 0.8,
        haze = mix(c.tile, c.form, 0.4);
    ctx.fillStyle = vgradient(ctx, 0, H, [
      (0, mix(c.tile, c.form, 0.55), 1),
      (0.75, haze, 1),
      (1, haze, 1),
    ]);
    ctx.fillRect(0, 0, 1, H);
    for (final tr in p.list('trees')) {
      final y = H * 0.7, th = tr.d('h');
      ctx.beginPath();
      ctx.moveTo(tr.d('x'), y);
      ctx.lineTo(tr.d('x'), y - th * H);
      strokeWith(ctx, mix(c.form, c.deep, 0.5), 0.008, 0.6);
      ctx.beginPath();
      ctx.ellipse(
        tr.d('x'),
        y - th * H * 1.3,
        tr.d('r'),
        th * H * 0.7,
        0,
        0,
        tau,
      );
      fillWith(ctx, mix(c.form, c.deep, 0.3), 0.6);
    }
    for (final h in p.list('hedge')) {
      ctx.beginPath();
      ctx.ellipse(h.d('x'), H * 0.7, h.d('w'), h.d('h') * H, 0, math.pi, tau);
      fillWith(ctx, mix(c.form, c.deep, 0.4), 0.75);
    }
    ctx.fillStyle = css(mix(c.form, c.deep, 0.45));
    ctx.fillRect(0, H * 0.7 - 0.002, 1, floor - H * 0.7);
    ctx.lineCap = StrokeCap.round;
    for (final d in p.list('drops')) {
      final y =
          eY + jsMod(d.d('y') + (still ? 0 : t * d.d('v')), 1) * (floor - eY);
      ctx.strokeStyle = css(c.light, d.d('a') * 0.8);
      ctx.lineWidth = 0.002;
      ctx.beginPath();
      ctx.moveTo(d.d('x'), y);
      ctx.lineTo(d.d('x') - 0.004, y + d.d('l') * H * 0.6);
      ctx.stroke();
    }
    // the terrace floor, wet, in perspective
    ctx.fillStyle = vgradient(ctx, floor, H, [
      (0, mix(c.deep, c.form, 0.35), 1),
      (1, mix(c.deep, c.form, 0.15), 1),
    ]);
    ctx.fillRect(0, floor, 1, H - floor);
    for (var i = -6; i <= 6; i++) {
      ctx.beginPath();
      ctx.moveTo(0.5 + i * 0.05, floor);
      ctx.lineTo(0.5 + i * 0.28, H);
      strokeWith(ctx, c.light, 0.002, 0.12);
    }
    for (var i = 1; i < 4; i++) {
      final y = floor + (H - floor) * math.pow(i / 4, 1.6);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(1, y);
      strokeWith(ctx, c.light, 0.002, 0.12);
    }
    // the eave and its line of drops
    ctx.fillStyle = css(ink);
    ctx.fillRect(-0.05, 0, 1.1, eY);
    if (p.b('beam')) {
      for (var i = 0; i < 6; i++) {
        ctx.beginPath();
        ctx.moveTo((i + 0.5) / 6, 0);
        ctx.lineTo((i + 0.5) / 6, eY - 0.01);
        strokeWith(ctx, mix(ink, c.light, 0.12), 0.012);
      }
    }
    ctx.fillStyle = css(mix(ink, c.light, 0.2));
    ctx.fillRect(-0.05, eY - 0.03, 1.1, 0.03);
    ctx.beginPath();
    ctx.moveTo(-0.05, eY - 0.03);
    ctx.lineTo(1.05, eY - 0.03);
    strokeWith(ctx, c.light, 0.003, 0.35);
    final drips = p.i('drips'), dseed = p.d('dseed');
    for (var i = 0; i < drips; i++) {
      final x = (i + 0.5 + (_hsh(dseed + i) - 0.5) * 0.5) / drips,
          per = 1.1 + _hsh(dseed + i * 3) * 1.2,
          raw = (still ? 0.3 : t / per) + _hsh(dseed * 2 + i),
          u = _fr(raw);
      _bead(
        ctx,
        x,
        eY + 0.008,
        0.005 + 0.006 * math.min(1, u / 0.6),
        c.light,
        c.deep,
      );
      if (!still && u > 0.6) {
        final f = (u - 0.6) / 0.4, y = eY + 0.012 + f * f * (floor - eY + 0.06);
        ctx.beginPath();
        ctx.moveTo(x, y - 0.07 * f);
        ctx.lineTo(x, y);
        strokeWith(ctx, c.light, 0.004, 0.85);
        _bead(ctx, x, y, 0.006, c.light, c.deep);
      }
      if (!still && u < 0.25) {
        final f = u / 0.25;
        ctx.beginPath();
        ctx.ellipse(
          x,
          floor + 0.06,
          0.006 + 0.04 * f,
          (0.006 + 0.04 * f) * 0.3,
          0,
          0,
          tau,
        );
        strokeWith(ctx, c.light, 0.003, 0.7 * (1 - f));
      }
    }
  }

  void _court(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final wy = p.d('wall') * H, warm = mix(c.accent, c.light, 0.3);
    ctx.fillStyle = vgradient(ctx, 0, wy, [
      (0, mix(c.form, c.deep, 0.35), 1),
      (1, mix(c.accent, c.form, 0.4), 1),
    ]);
    ctx.fillRect(0, 0, 1, wy);
    ctx.lineCap = StrokeCap.round;
    for (final d in p.list('drops')) {
      final y = jsMod(d.d('y') + (still ? 0 : t * d.d('v')), 1) * H;
      ctx.strokeStyle = css(c.light, d.d('a') * 0.7);
      ctx.lineWidth = 0.002;
      ctx.beginPath();
      ctx.moveTo(d.d('x'), y);
      ctx.lineTo(d.d('x') - 0.006, y + d.d('l') * H * 0.6);
      ctx.stroke();
    }
    // a cypress and shrubs behind the low wall
    ctx.beginPath();
    ctx.ellipse(p.d('cypress'), wy - 0.2, 0.045, 0.24, 0, 0, tau);
    fillWith(ctx, mix(c.form, c.deep, 0.55));
    for (final b in p.list('bushes')) {
      circle(ctx, b.d('x'), wy - b.d('r') * 0.4, b.d('r'));
      fillWith(ctx, mix(c.form, c.deep, 0.45));
    }
    // the low wall with its coping, and a lamp on it
    ctx.fillStyle = css(mix(c.deep, c.accent, 0.2));
    ctx.fillRect(0, wy, 1, 0.12);
    ctx.fillStyle = css(mix(c.deep, c.light, 0.18));
    ctx.fillRect(0, wy - 0.012, 1, 0.014);
    final lx = p.d('lamp'), br = still ? 1.0 : 0.9 + 0.1 * BR(t, false);
    glow(ctx, lx, wy - 0.035, 0.22 * br, warm, 0.45);
    _rr(ctx, lx - 0.016, wy - 0.06, 0.032, 0.048, 0.006);
    fillWith(ctx, warm, 0.95);
    // wet paving with the lamp's reflection
    final fy = wy + 0.12;
    ctx.fillStyle = vgradient(ctx, fy, H, [
      (0, mix(c.deep, c.form, 0.3), 1),
      (1, mix(c.deep, c.accent, 0.12), 1),
    ]);
    ctx.fillRect(0, fy, 1, H - fy);
    for (var i = 1; i < 5; i++) {
      final y = fy + (H - fy) * math.pow(i / 5, 1.5);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(1, y);
      strokeWith(ctx, c.light, 0.002, 0.1);
    }
    for (var i = -5; i <= 5; i++) {
      ctx.beginPath();
      ctx.moveTo(0.5 + i * 0.08, fy);
      ctx.lineTo(0.5 + i * 0.3, H);
      strokeWith(ctx, c.light, 0.002, 0.1);
    }
    for (var j = 0; j < 9; j++) {
      final y = fy + 0.02 + j * (H - fy) / 10,
          w = 0.02 + 0.006 * j,
          a =
              0.35 *
              (1 - j / 10) *
              (still ? 1 : 0.8 + 0.2 * S(t, 2.5, j * 1.0));
      ctx.fillStyle = css(warm, a);
      ctx.fillRect(
        lx - w / 2 + (still ? 0 : 0.004 * S(t, 1.7, j * 1.3)),
        y,
        w,
        0.008,
      );
    }
    _rainRings(
      ctx,
      1 - lx * 0.8,
      fy + (H - fy) * 0.55,
      0.12,
      p.d('dseed'),
      4,
      c.light,
      t,
      still,
      0.3,
    );
  }
}

/// The view from a parked car in the rain: the roof's dark edge, the
/// dashboard's curve, lights blurred beyond the glass, beads sliding.
class CarGround extends Ground {
  const CarGround();

  @override
  String get label => 'car in the rain';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'lights': [
      for (var i = 0; i < 10; i++)
        {
          'x': r.next(),
          'y': r.range(0.3, 0.7),
          'r': r.range(0.03, 0.09),
          'ph': r.range(0, tau),
          'role': r.pick(const ['accent', 'accent', 'light']),
        },
    ],
    'beads': [
      for (var i = 0; i < 40; i++)
        {'x': r.next(), 'y': r.range(0.18, 0.78), 'r': r.range(0.004, 0.011)},
    ],
    'runs': [
      for (var i = 0; i < 7; i++)
        {
          'x': r.next(),
          'y': r.next(),
          'v': r.range(0.02, 0.04),
          'a': r.range(-0.6, -0.2),
        },
    ],
    'dash': r.range(0.78, 0.84),
  };

  @override
  Rgb tone(ArtRoles c, P p) => mix(c.deep, c.form, 0.2);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    vgradFill(ctx, H, [
      (0, mix(c.deep, c.form, 0.1), 1),
      (0.55, mix(c.deep, c.form, 0.35), 1),
      (1, c.deep, 1),
    ]);
    for (final L in p.list('lights')) {
      glow(
        ctx,
        L.d('x'),
        L.d('y') * H,
        L.d('r'),
        c.role(L.s('role')),
        0.5 * (still ? 1 : 0.8 + 0.2 * S(t, 11, L.d('ph'))),
      );
    }
    for (final b in p.list('beads')) {
      _bead(ctx, b.d('x'), b.d('y') * H, b.d('r'), c.light, c.deep, 0.85);
    }
    for (final q in p.list('runs')) {
      final u = still ? q.d('y') : jsMod(q.d('y') + t * q.d('v'), 1),
          x = q.d('x') + u * 0.12,
          y = H * (0.75 - u * 0.55);
      _bead(ctx, x, y, 0.01, c.light, c.deep, fade(u));
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x - 0.03, y + 0.06);
      strokeWith(ctx, c.light, 0.002, 0.25 * fade(u));
    }
    final dash = p.d('dash');
    ctx.beginPath();
    ctx.moveTo(-0.05, 0);
    ctx.lineTo(1.05, 0);
    ctx.lineTo(1.05, H * 0.12);
    ctx.quadraticCurveTo(0.5, H * 0.22, -0.05, H * 0.12);
    ctx.closePath();
    fillWith(ctx, c.deep);
    ctx.beginPath();
    ctx.moveTo(-0.05, H);
    ctx.lineTo(-0.05, H * (dash - 0.04));
    ctx.quadraticCurveTo(0.5, H * (dash - 0.1), 1.05, H * (dash - 0.04));
    ctx.lineTo(1.05, H);
    ctx.closePath();
    fillWith(ctx, c.deep);
    ctx.beginPath();
    ctx.moveTo(0.05, H * (dash - 0.05));
    ctx.quadraticCurveTo(0.5, H * (dash - 0.11), 0.95, H * (dash - 0.05));
    strokeWith(ctx, c.light, 0.003, 0.18);
  }
}

/// Inside a carriage: the window band with lights streaming past, wall
/// panels, a rail and a pole; the whole car sways a little.
class MetroGround extends Ground {
  const MetroGround();

  @override
  String get label => 'metro carriage';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'by': r.range(0.3, 0.38),
    'bh': r.range(0.24, 0.3),
    'lights': [
      for (var i = 0; i < 12; i++)
        {
          'x': r.next(),
          'y': r.next(),
          'len': r.range(0.08, 0.3),
          'v': r.range(0.12, 0.3),
          'role': r.pick(const ['accent', 'light', 'accent', 'form']),
        },
    ],
    'pole': r.range(0.18, 0.82),
    'day': r.chance(0.3),
  };

  @override
  Rgb tone(ArtRoles c, P p) => mix(c.tile, c.form, 0.45);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final sway = still ? 0.0 : 0.004 * S(t, 4.3);
    final by = p.d('by'), bh = p.d('bh'), day = p.b('day');
    ctx.save();
    ctx.translate(0, sway);
    ctx.fillStyle = css(mix(c.tile, c.form, 0.3));
    ctx.fillRect(0, -0.02, 1, H + 0.04);
    ctx.fillStyle = css(mix(c.form, c.deep, 0.35));
    ctx.fillRect(0, (by + bh + 0.06) * H, 1, H);
    final y0 = by * H, h = bh * H;
    ctx.save();
    _rr(ctx, 0.04, y0, 0.92, h, 0.03);
    ctx.clip();
    ctx.fillStyle = vgradient(ctx, y0, y0 + h, [
      (0, day ? mix(c.tile, c.form, 0.4) : c.deep, 1),
      (1, day ? mix(c.form, c.tile, 0.3) : mix(c.deep, c.form, 0.25), 1),
    ]);
    ctx.fillRect(0, y0, 1, h);
    ctx.lineCap = StrokeCap.round;
    for (final L in p.list('lights')) {
      final len = L.d('len'), col = c.role(L.s('role'));
      final x = 1.3 - jsMod(L.d('x') + (still ? 0 : t * L.d('v')), 1.6),
          y = y0 + h * (0.15 + 0.7 * L.d('y'));
      final g = ctx.createLinearGradient(x, 0, x + len, 0)
        ..addColorStop(0, css(col, 0))
        ..addColorStop(0.3, css(col, 0.75))
        ..addColorStop(1, css(col, 0));
      ctx.strokeStyle = g;
      ctx.lineWidth = 0.008;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + len, y);
      ctx.stroke();
    }
    ctx.restore();
    _rr(ctx, 0.04, y0, 0.92, h, 0.03);
    strokeWith(ctx, mix(c.tile, c.light, 0.3), 0.012);
    ctx.beginPath();
    ctx.moveTo(0.5, y0);
    ctx.lineTo(0.5, y0 + h);
    strokeWith(ctx, mix(c.tile, c.light, 0.3), 0.01);
    ctx.beginPath();
    ctx.moveTo(-0.05, H * 0.1);
    ctx.lineTo(1.05, H * 0.1);
    strokeWith(ctx, mix(c.light, c.form, 0.3), 0.014);
    ctx.beginPath();
    ctx.moveTo(p.d('pole'), H * 0.1);
    ctx.lineTo(p.d('pole'), H + 0.1);
    strokeWith(ctx, mix(c.light, c.form, 0.25), 0.016);
    ctx.restore();
  }
}

/// A room at evening: a wall, a floor line, a lamp's warm pool.
class RoomGround extends Ground {
  const RoomGround();

  @override
  String get label => 'room';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'lx': r.range(0.2, 0.8),
    'ly': r.range(0.3, 0.5),
    'floor': r.range(0.74, 0.82),
    'pic': r.chance(0.5),
    'px': r.range(0.15, 0.6),
    'warm': r.range(0.12, 0.28),
  };

  @override
  Rgb tone(ArtRoles c, P p) =>
      mix(darkOf(c, 0.35), c.accent, p.d('warm') * 0.6);

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final wall = mix(darkOf(c, 0.4), c.accent, p.d('warm')),
        floor = p.d('floor');
    ctx.fillStyle = vgradient(ctx, 0, H, [
      (0, mix(wall, c.deep, 0.25), 1),
      (floor, wall, 1),
      (floor + 0.001, mix(c.deep, c.form, 0.2), 1),
      (1, c.deep, 1),
    ]);
    ctx.fillRect(0, 0, 1, H);
    glow(
      ctx,
      p.d('lx'),
      p.d('ly') * H,
      0.6 * (still ? 1 : 0.95 + 0.05 * BR(t, false)),
      c.accent,
      0.32,
    );
    if (p.b('pic')) {
      _rr(ctx, p.d('px'), H * 0.22, 0.2, H * 0.16, 0.006);
      strokeWith(ctx, mix(wall, c.light, 0.25), 0.006, 0.6);
    }
    ctx.beginPath();
    ctx.moveTo(0, floor * H);
    ctx.lineTo(1, floor * H);
    strokeWith(ctx, mix(wall, c.light, 0.2), 0.004, 0.5);
  }
}
