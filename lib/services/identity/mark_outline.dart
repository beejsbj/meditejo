import 'dart:math' as math;

import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/seeded_random.dart';

/// Outlines of a mark's shapes, free of Flutter: the painter fills them on
/// a canvas, and the icon tool writes them as SVG and Android vector paths.

/// A pebble's outline (`core.js` `blobPath`): 129 points, the last on the
/// first. [imperf] 0 draws a true circle, 1 the full organic shape.
List<(double, double)> blobOutline(
  MarkBlob b, {
  double grow = 1,
  double imperf = 1,
  double dx = 0,
  double dy = 0,
  double sx = 1,
  double sy = 1,
}) {
  final asp = lerp(1, b.asp, imperf);
  const m = 128;
  final c = math.cos(b.rot), s = math.sin(b.rot);
  return [
    for (var i = 0; i <= m; i++)
      () {
        final th = i / m * tau;
        var r = 1.0;
        for (var k = 0; k < 3; k++) {
          r += imperf * b.a[k] * math.sin((k + 2) * th + b.p[k]);
        }
        if (b.cut != 0) {
          r +=
              b.cut *
              (0.6 * math.sin(b.ck[0] * th + b.cp[0]) +
                  0.4 * math.sin(b.ck[1] * th + b.cp[1]));
        }
        r *= b.r * grow;
        final ux = r * math.cos(th) * asp * sx, uy = r * math.sin(th) * sy;
        return (b.cx + dx + ux * c - uy * s, b.cy + dy + ux * s + uy * c);
      }(),
  ];
}

/// One filled shape of a settled mark, as SVG path data in tile units, and
/// the palette role it is filled with.
class OutlineShape {
  const OutlineShape(this.role, this.path);

  final String role;
  final String path;
}

/// A mark's settled frame (no motion, organic shapes) as filled paths, for
/// marks that can be a launcher icon: every gesture mark, and the minimal
/// shelter. Coordinates go through [map] (tile units in, anything out).
List<OutlineShape> settledOutline(
  MarkSpec m, {
  (double, double) Function((double, double) p)? map,
}) {
  final f = map ?? (p) => p;
  String n(double v) => v.toStringAsFixed(3);
  String pt((double, double) p) {
    final (x, y) = f(p);
    return '${n(x)} ${n(y)}';
  }

  String polygon(List<(double, double)> pts) =>
      'M${pt(pts.first)}${[for (final p in pts.skip(1)) 'L${pt(p)}'].join()}Z';

  String circle(double cx, double cy, double r) {
    // Two arcs; the radius is mapped by its effect on x.
    final (x0, y0) = f((cx - r, cy));
    final (x1, _) = f((cx + r, cy));
    final rr = n((x1 - x0) / 2);
    return 'M${n(x0)} ${n(y0)}A$rr $rr 0 1 0 ${n(x1)} ${n(y0)}'
        'A$rr $rr 0 1 0 ${n(x0)} ${n(y0)}Z';
  }

  (double, double) scaled((double, double) p) =>
      (0.5 + (p.$1 - 0.5) * m.fit, 0.5 + (p.$2 - 0.5) * m.fit);

  switch (m) {
    case GestureMark(:final blob, :final stroke):
      final st = stroke;
      final left = <(double, double)>[], right = <(double, double)>[];
      for (var i = 0; i < st.n; i++) {
        final hw = st.w[i] / 2;
        left.add(scaled((st.x[i] + st.nx[i] * hw, st.y[i] + st.ny[i] * hw)));
        right.add(scaled((st.x[i] - st.nx[i] * hw, st.y[i] - st.ny[i] * hw)));
      }
      final ribbon = [...left, ...right.reversed];
      final last = st.n - 1;
      final (sx, sy) = scaled((st.x[0], st.y[0]));
      final (ex, ey) = scaled((st.x[last], st.y[last]));
      return [
        OutlineShape(
          'form',
          polygon([for (final p in blobOutline(blob)) scaled(p)]),
        ),
        OutlineShape(
          'stroke',
          polygon(ribbon) +
              circle(sx, sy, st.w[0] / 2 * m.fit) +
              circle(ex, ey, st.w[last] / 2 * m.fit),
        ),
      ];
    case MinimalMark(type: 'shelter'):
      final roof = shelterRoofCommands(m);
      final r1 = m.roles.first;
      return [
        OutlineShape('stroke', _commandsToSvg(roof, pt)),
        OutlineShape(
          r1 == 'stroke' ? 'form' : r1,
          polygon(blobOutline(m.blobs['sitter']!)),
        ),
      ];
    default:
      throw UnsupportedError(
        '${m.seed} (${m.family.name} ${m.type}) has no icon outline',
      );
  }
}

/// A path as move, line and quadratic commands, so both Flutter and SVG can
/// draw it: (`M`, x, y), (`L`, x, y), (`Q`, cx, cy, x, y).
typedef PathCommand = (String, List<double>);

/// The minimal shelter's roof, [open] of the way spread (1 when settled).
///
/// Two optional values fold the apex into an M (tile units; absent or 0 is
/// the roof as first shipped): `notch`, how far the apex folds down below
/// its two shoulders, and `nw`, how far each shoulder sits from the centre.
/// The slopes stay the shipped ones; they stop at the shoulders and meet in
/// a sharp V. This is the Clear V house mark (decision 21, round 6). Round 6's
/// `soft` and `gap` are not read: a mark carrying them draws as a sharp V.
List<PathCommand> shelterRoofCommands(MinimalMark m, [double open = 1]) {
  const ax = 0.5, thick = 0.07;
  final ay = m['ay'], ey = m['ey'];
  final w = m['w'] * (0.85 + 0.15 * open);
  final notch = m.values['notch'] ?? 0, nw = m.values['nw'] ?? 0;
  if (notch == 0 || nw == 0) {
    return [
      ('M', [ax - w, ey]),
      ('Q', [ax - w * 0.35, ay + 0.04, ax, ay]),
      ('Q', [ax + w * 0.35, ay + 0.04, ax + w, ey]),
      ('L', [ax + w - 0.05, ey]),
      ('Q', [ax + w * 0.3, ay + 0.1, ax, ay + 0.07]),
      ('Q', [ax - w * 0.3, ay + 0.1, ax - w + 0.05, ey]),
    ];
  }
  (double, double) mirror((double, double) p) => (1 - p.$1, p.$2);
  List<double> xy(List<(double, double)> ps) => [
    for (final p in ps) ...[p.$1, p.$2],
  ];
  final oL = (ax - w, ey), oC = (ax - w * 0.35, ay + 0.04), oA = (ax, ay);
  final iL = (ax - w + 0.05, ey), iC = (ax - w * 0.3, ay + 0.1);
  final iA = (ax, ay + 0.07);
  // The shoulders: each slope up to nw from the centre.
  final (oc, oS) = _quadHead(oL, oC, oA, _quadTAtX(oL, oC, oA, ax - nw));
  final oN = (ax, oS.$2 + notch);
  // The inside follows at the roof's thickness: under a V its notch is
  // lower by the thickness across the V's arm.
  final arm = math.sqrt(nw * nw + notch * notch) / nw;
  final (ic, iS) = _quadHead(iL, iC, iA, _quadTAtX(iL, iC, iA, ax - nw));
  final iN = (ax, oN.$2 + thick * arm);
  return [
    ('M', xy([oL])),
    ('Q', xy([oc, oS])),
    ('L', xy([oN])),
    ('L', xy([mirror(oS)])),
    ('Q', xy([mirror(oc), mirror(oL)])),
    ('L', xy([mirror(iL)])),
    ('Q', xy([mirror(ic), mirror(iS)])),
    ('L', xy([iN])),
    ('L', xy([iS])),
    ('Q', xy([ic, iL])),
  ];
}

/// The t in [0, 1] where a quadratic's x is [x].
double _quadTAtX(
  (double, double) p0,
  (double, double) c,
  (double, double) p2,
  double x,
) {
  final a = p0.$1 - 2 * c.$1 + p2.$1, b = 2 * (c.$1 - p0.$1), k = p0.$1 - x;
  if (a.abs() < 1e-12) return -k / b;
  final d = math.sqrt(math.max(0.0, b * b - 4 * a * k));
  final r1 = (-b + d) / (2 * a), r2 = (-b - d) / (2 * a);
  return r1 >= 0 && r1 <= 1 ? r1 : r2;
}

/// The part of a quadratic from p0 to [t]: its control point and its end.
((double, double), (double, double)) _quadHead(
  (double, double) p0,
  (double, double) c,
  (double, double) p2,
  double t,
) {
  final q0 = (lerp(p0.$1, c.$1, t), lerp(p0.$2, c.$2, t));
  final q1 = (lerp(c.$1, p2.$1, t), lerp(c.$2, p2.$2, t));
  return (q0, (lerp(q0.$1, q1.$1, t), lerp(q0.$2, q1.$2, t)));
}

String _commandsToSvg(
  List<PathCommand> cmds,
  String Function((double, double)) pt,
) {
  final b = StringBuffer();
  for (final (op, v) in cmds) {
    b.write(op);
    for (var i = 0; i < v.length; i += 2) {
      if (i > 0) b.write(' ');
      b.write(pt((v[i], v[i + 1])));
    }
  }
  return '${b}Z';
}
