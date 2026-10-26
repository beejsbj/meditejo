import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:medito/services/identity/mark_outline.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/identity/seeded_random.dart';
import 'package:medito/widgets/branding/mark_textures.dart';

/// The colours a mark paints with: a palette's four roles, plus the two the
/// page derives from them.
class MarkColors {
  MarkColors({
    required this.tile,
    required this.form,
    required this.stroke,
    required this.accent,
    Color? ground,
  }) : ground = ground ?? tile,
       deep = _lum(tile) < _lum(stroke) ? tile : stroke,
       light = _lum(tile) < _lum(stroke) ? stroke : tile,
       lightPaper = _lum(tile) > 0.35;

  factory MarkColors.of(IdentityPalette p) => MarkColors(
    tile: Color(p.tile),
    form: Color(p.form),
    stroke: Color(p.stroke),
    accent: Color(p.accent),
  );

  /// For a mark drawn straight on the app's [background] (no tile): a
  /// stroke under 2.2:1 against it becomes [text], as on the page.
  factory MarkColors.onBackground(
    IdentityPalette p, {
    required Color background,
    required Color text,
  }) {
    final stroke = Color(p.stroke);
    return MarkColors(
      tile: Color(p.tile),
      form: Color(p.form),
      stroke: contrastRatio(stroke, background) < 2.2 ? text : stroke,
      accent: Color(p.accent),
      ground: background,
    );
  }

  final Color tile, form, stroke, accent;

  /// What a mark's cut-outs show (a window's bars, a sun cut from an
  /// arch): the tile when the mark sits on one, else the app's background.
  final Color ground;
  final Color deep, light;

  /// Whether the tile is paper (light) rather than night (dark).
  final bool lightPaper;

  Color role(String name) => switch (name) {
    'tile' => tile,
    'form' => form,
    'stroke' => stroke,
    'accent' => accent,
    _ => throw ArgumentError(name),
  };

  @override
  bool operator ==(Object other) =>
      other is MarkColors &&
      other.tile == tile &&
      other.form == form &&
      other.stroke == stroke &&
      other.accent == accent &&
      other.ground == ground;

  @override
  int get hashCode => Object.hash(tile, form, stroke, accent, ground);
}

/// WCAG relative luminance, with the page's (WCAG 2.0) threshold.
double _lum(Color c) {
  double ch(double x) =>
      x <= 0.03928 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// `core.js` `mix`, truncated per channel as the page's `css()` does.
Color _mix(Color a, Color b, double t) => Color.fromARGB(
  255,
  lerp(a.r * 255, b.r * 255, t).floor(),
  lerp(a.g * 255, b.g * 255, t).floor(),
  lerp(a.b * 255, b.b * 255, t).floor(),
);

Color _a(Color c, double alpha) => c.withValues(alpha: clamp01(alpha));

/// Draws a [MarkSpec] into a unit square on [canvas] (scale the canvas to
/// the tile's side first), at [t] seconds into its life: it appears, draws
/// its line, then breathes. A port of the draw half of `marks.js`.
class MarkRenderer {
  MarkRenderer(this.canvas, this.colors, {this.textures, this.texel = 1 / 256});

  final Canvas canvas;
  final MarkColors colors;

  /// Paper and speckle for the print finish; without them the finish is
  /// left out.
  final MarkTextures? textures;

  /// One texture pixel, in tile units (one logical pixel).
  final double texel;

  /// [still] draws the settled frame (reduced motion). [tile] paints the
  /// tile behind gesture and minimal marks; without it they sit on whatever
  /// is below (the app's background). [finish] lays the paper finish over a
  /// tiled mark; atmospheric scenes always carry theirs. [scale] shrinks the composition about
  /// the centre (the launcher icon's safe zone).
  void draw(
    MarkSpec m,
    double t, {
    bool still = false,
    bool tile = true,
    bool finish = true,
    double scale = 1,
  }) {
    if (still) t = 60;
    final c = colors;
    if (m is AtmosMark) {
      canvas
        ..save()
        ..translate(0.5, 0.5)
        ..scale(scale)
        ..translate(-0.5, -0.5);
      _atmos(m, t, still);
      canvas.restore();
      _finish(speckle: 0.3);
      return;
    }
    if (tile) _rect(const Rect.fromLTWH(0, 0, 1, 1), c.tile);
    final sc = scale * m.fit;
    canvas
      ..save()
      ..translate(0.5, 0.5)
      ..scale(sc)
      ..translate(-0.5, -0.5);
    switch (m) {
      case GestureMark():
        _gesture(m, t, still);
      case MinimalMark():
        _minimal(m, t, still);
      case AtmosMark():
        break;
    }
    canvas.restore();
    if (tile && finish) _finish(paper: 0.1, speckle: 0.18, vignette: 0);
  }

  // ---------- primitives ----------

  void _fill(Path path, Color color, [double alpha = 1]) {
    canvas.drawPath(path, Paint()..color = _a(color, color.a * alpha));
  }

  void _rect(Rect r, Color color, [double alpha = 1]) {
    canvas.drawRect(r, Paint()..color = _a(color, color.a * alpha));
  }

  /// A pebble's outline as a path (see [blobOutline]).
  static Path blobPath(
    MarkBlob b, {
    double grow = 1,
    double imperf = 1,
    double dx = 0,
    double dy = 0,
    double sx = 1,
    double sy = 1,
    Path? into,
  }) {
    final path = into ?? Path();
    final pts = blobOutline(
      b,
      grow: grow,
      imperf: imperf,
      dx: dx,
      dy: dy,
      sx: sx,
      sy: sy,
    );
    path.moveTo(pts.first.$1, pts.first.$2);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].$1, pts[i].$2);
    }
    return path..close();
  }

  /// A ribbon drawn up to [p] of its pen clock (`core.js` `drawStroke`).
  void _stroke(MarkStroke st, double p, Color color) {
    if (p <= 0) return;
    final n = st.n, x = st.x, y = st.y, nx = st.nx, ny = st.ny, w = st.w;
    var k = n - 1;
    var f = 0.0;
    if (p < 1) {
      var lo = 0, hi = n - 1;
      while (hi - lo > 1) {
        final mid = (lo + hi) >> 1;
        if (st.cost[mid] <= p) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      k = lo;
      final span = st.cost[hi] - st.cost[lo];
      f = (p - st.cost[lo]) / (span == 0 ? 1 : span);
    }
    final k2 = math.min(k + 1, n - 1);
    final ex = lerp(x[k], x[k2], f), ey = lerp(y[k], y[k2], f);
    final ew = lerp(w[k], w[k2], f) / 2;
    final enx = lerp(nx[k], nx[k2], f), eny = lerp(ny[k], ny[k2], f);
    final path = Path()
      ..moveTo(x[0] + nx[0] * w[0] / 2, y[0] + ny[0] * w[0] / 2);
    for (var i = 1; i <= k; i++) {
      path.lineTo(x[i] + nx[i] * w[i] / 2, y[i] + ny[i] * w[i] / 2);
    }
    path
      ..lineTo(ex + enx * ew, ey + eny * ew)
      ..lineTo(ex - enx * ew, ey - eny * ew);
    for (var i = k; i >= 0; i--) {
      path.lineTo(x[i] - nx[i] * w[i] / 2, y[i] - ny[i] * w[i] / 2);
    }
    path.close();
    final paint = Paint()..color = color;
    canvas
      ..drawPath(path, paint)
      ..drawCircle(Offset(x[0], y[0]), w[0] / 2, paint)
      ..drawCircle(Offset(ex, ey), ew, paint);
  }

  static Path _circle(double x, double y, double r) => Path()
    ..addOval(Rect.fromCircle(center: Offset(x, y), radius: math.max(r, 0)));

  /// An arch: straight sides, a half-circle top (`ctx.arc(…, π, 0)`).
  static Path _arch(double x0, double w, double ys, double bot) => Path()
    ..moveTo(x0, bot)
    ..lineTo(x0, ys)
    ..arcTo(
      Rect.fromCircle(center: Offset(x0 + w / 2, ys), radius: w / 2),
      math.pi,
      math.pi,
      false,
    )
    ..lineTo(x0 + w, bot)
    ..close();

  // ---------- gesture ----------

  void _gesture(GestureMark m, double t, bool still) {
    const s0 = 0.5;
    final bStart = s0 + m.duration + 0.4;
    final b = still ? 0.0 : breathAt(t, bStart);
    final appear = easeOut(progress(t, 0, 1));
    _fill(
      blobPath(
        m.blob,
        grow: (0.92 + 0.08 * appear) * (1 + 0.025 * b),
        imperf: 1 - b,
      ),
      colors.form,
      appear,
    );
    _stroke(
      m.stroke,
      still ? 1 : easeInOut(progress(t, s0, m.duration)),
      colors.stroke,
    );
  }

  // ---------- minimal ----------

  void _minimal(MinimalMark m, double t, bool still) {
    final c = colors;
    final b = still ? 0.0 : breathAt(t, 2.4), imp = 1 - b;
    double e(double s, double d) => still ? 1 : easeOut(progress(t, s, d));
    final e1 = e(0, 1.1), e2 = e(0.6, 1.3), e3 = e(1.1, 1.2);
    final [r1, r2, r3] = m.roles;
    Color role(String r) => c.role(r);
    Path blob(
      MarkBlob bb, {
      double grow = 1,
      double dx = 0,
      double dy = 0,
      double sx = 1,
      double sy = 1,
    }) => blobPath(bb, imperf: imp, grow: grow, dx: dx, dy: dy, sx: sx, sy: sy);

    switch (m.type) {
      case 'split':
        final disc = m.blobs['disc']!;
        final h = m['h'], gap = m['gap'];
        canvas
          ..save()
          ..clipRect(Rect.fromLTWH(0, 0, 1, h - gap / 2));
        _fill(blob(disc, grow: 1 + 0.02 * b, dy: (1 - e1) * 0.12), role(r1));
        canvas
          ..restore()
          ..save()
          ..clipRect(Rect.fromLTWH(0, h + gap / 2, 1, 1));
        _fill(blob(disc, dx: m['shift'] * e2), role(r2), e2);
        canvas.restore();
      case 'arch':
        final w = m['w'], ht = m['ht'];
        final top = 0.5 - ht / 2, bot = 0.5 + ht / 2, x0 = 0.5 - w / 2;
        final ys = top + w / 2;
        final arch = _arch(x0, w, ys, bot);
        canvas
          ..save()
          ..clipRect(Rect.fromLTWH(0, lerp(bot, top, e1) - 0.01, 1, 1));
        _fill(arch, role(r1));
        canvas
          ..restore()
          ..save()
          ..clipPath(arch);
        _fill(
          blob(
            m.blobs['sun']!,
            dy: lerp(bot + 0.1, ys + ht * m['sunY'], e2) - 0.008 * b,
          ),
          r2 == 'stroke' ? c.ground : role(r2),
        );
        canvas.restore();
      case 'pebble':
        _fill(
          blob(m.blobs['peb']!, grow: (0.92 + 0.08 * e1) * (1 + 0.02 * b)),
          role(r1),
          e1,
        );
        final second = m.blobs['second'];
        if (second != null) {
          _fill(
            blob(second, grow: 0.6 + 0.4 * e3),
            r3 == r1 ? c.accent : role(r3),
            e3,
          );
        }
        _fill(
          blob(m.blobs['dot']!, grow: e2, dy: -(1 - e2) * 0.08),
          r2 == r1 ? c.stroke : role(r2),
        );
      case 'crescent':
        final disc = m.blobs['disc']!;
        final d = lerp(0.62, m['cutD'], e2) * (1 + 0.05 * b);
        final ax = m['cutX'], ay = m['cutY'];
        canvas
          ..save()
          ..clipPath(blob(disc, grow: 0.92 + 0.08 * e1));
        final cut = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(const Rect.fromLTWH(-1, -1, 3, 3))
          ..addOval(
            Rect.fromCircle(
              center: Offset(0.5 + ax * d, 0.5 + ay * d),
              radius: disc.r * 1.02,
            ),
          );
        _fill(cut, role(r1), e1);
        canvas.restore();
        final dot = m['dot'];
        if (dot != 0) {
          _fill(
            _circle(
              0.5 + ax * disc.r * 0.62,
              0.5 + ay * disc.r * 0.62,
              dot * e3,
            ),
            c.accent,
          );
        }
      case 'vesica':
        final a = m.blobs['a']!, bb = m.blobs['b']!;
        final sep = lerp(m['sep'] * 2.4, m['sep'], e1) * (1 - 0.1 * b);
        final pa = blob(a, dx: 0.5 - sep / 2 - a.cx);
        final pb = blob(bb, dx: 0.5 + sep / 2 - bb.cx);
        _fill(pa, c.form, e1);
        _fill(pb, c.accent, e1);
        canvas
          ..save()
          ..clipPath(pa);
        _fill(pb, r2 == 'form' || r2 == 'accent' ? c.stroke : role(r2), e1);
        canvas.restore();
      case 'cairn':
        const stoneRoles = ['stroke', 'form', 'accent'];
        for (var i = 0; i < 3; i++) {
          final s = m.stones[i];
          final es = still ? 1.0 : easeOut(progress(t, i * 0.45, 1));
          _fill(
            blob(
              s,
              sx: s.rx!,
              sy: s.ry!,
              dy: -(1 - es) * 0.08 - (i == 2 ? 0.006 * b : 0),
            ),
            role(stoneRoles[i]),
            es,
          );
        }
      case 'window':
        final w = m['w'], h = m['h'];
        final x0 = 0.5 - w / 2, y0 = 0.5 - h / 2;
        final rr = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x0, lerp(y0 + h, y0, e1), w, h * e1),
              Radius.circular(m['rad']),
            ),
          );
        _fill(rr, role(r1));
        canvas
          ..save()
          ..clipPath(rr);
        _fill(
          blob(
            m.blobs['sun']!,
            dy: (1 - e2) * 0.2 - 0.01 * b,
            grow: 1 + 0.03 * b,
          ),
          r1 == 'accent' ? c.form : c.accent,
        );
        if (m.mullion) {
          _rect(Rect.fromLTWH(0.5 - 0.012, y0, 0.024, h), c.ground);
          _rect(Rect.fromLTWH(x0, 0.5 - 0.012, w, 0.024), c.ground);
        }
        canvas.restore();
      case 'hearth':
        final base = m.blobs['base']!;
        canvas
          ..save()
          ..clipRect(Rect.fromLTWH(0, 0, 1, base.cy));
        _fill(
          blob(base, grow: 0.9 + 0.1 * e1),
          r1 == 'accent' ? c.form : role(r1),
        );
        canvas.restore();
        final fh = m['flame'] * (1 + 0.08 * b) * e2;
        const fx = 0.5;
        final fy = m['fy'] + (1 - e2) * 0.1;
        final flame = Path()
          ..moveTo(fx, fy - fh * 1.9)
          ..cubicTo(
            fx + fh * 1.1,
            fy - fh * 0.6,
            fx + fh * 0.9,
            fy + fh,
            fx,
            fy + fh,
          )
          ..cubicTo(
            fx - fh * 0.9,
            fy + fh,
            fx - fh * 1.1,
            fy - fh * 0.6,
            fx,
            fy - fh * 1.9,
          );
        _fill(flame, c.accent);
        _rect(
          Rect.fromLTWH(0.5 - base.r * 1.05, base.cy, base.r * 2.1 * e3, 0.03),
          c.stroke,
        );
      case 'clearing':
        final ring = m.blobs['ring']!;
        final path = blob(ring, grow: (0.9 + 0.1 * e1) * (1 + 0.02 * b));
        blobPath(
          ring,
          grow: m['inner'] * (1 - 0.04 * b),
          imperf: imp * 0.6,
          into: path,
        );
        path.fillType = PathFillType.evenOdd;
        _fill(path, role(r1), e1);
        _fill(blob(m.blobs['dot']!, grow: e2), r2 == r1 ? c.stroke : role(r2));
      case 'cushion':
        final cu = m.blobs['cushion']!;
        _fill(
          blob(cu, sx: cu.rx! * (0.9 + 0.1 * e1), sy: cu.ry!),
          r2 == 'stroke'
              ? c.stroke
              : r1 == 'stroke'
              ? c.form
              : c.stroke,
        );
        _fill(
          blob(
            m.blobs['sitter']!,
            dy: -(1 - e2) * 0.1 - 0.008 * b,
            grow: 1 + 0.02 * b,
          ),
          r1 == 'stroke' ? c.accent : role(r1),
          e2,
        );
      case 'shelter':
        _fill(shelterRoof(m, e1), c.stroke);
        _fill(
          blob(m.blobs['sitter']!, grow: e2 * (1 + 0.02 * b)),
          r1 == 'stroke' ? c.form : role(r1),
        );
    }
  }

  /// The minimal shelter's roof, [open] of the way spread (1 when settled).
  static Path shelterRoof(MinimalMark m, [double open = 1]) {
    final path = Path();
    for (final (op, v) in shelterRoofCommands(m, open)) {
      switch (op) {
        case 'M':
          path.moveTo(v[0], v[1]);
        case 'L':
          path.lineTo(v[0], v[1]);
        case 'Q':
          path.quadraticBezierTo(v[0], v[1], v[2], v[3]);
      }
    }
    return path..close();
  }

  // ---------- atmospheric ----------

  ui.Gradient _lin(double y0, double y1, List<(double, Color, double)> stops) =>
      ui.Gradient.linear(
        Offset(0, y0),
        Offset(0, y1),
        [for (final s in stops) _a(s.$2, s.$3)],
        [for (final s in stops) s.$1],
      );

  void _glow(double x, double y, double r, Color col, double a) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(x, y),
          math.max(r, 1e-6),
          [_a(col, a), _a(col, a * 0.35), _a(col, 0)],
          const [0, 0.5, 1],
        ),
    );
  }

  /// The second plate: offset by the misregistration and overprinted
  /// (multiply on paper, screen at night).
  void _plateB(AtmosMark m, void Function() draw) {
    canvas
      ..save()
      ..translate(m.misregister.$1, m.misregister.$2)
      ..saveLayer(
        null,
        Paint()
          ..blendMode = colors.lightPaper
              ? BlendMode.multiply
              : BlendMode.screen,
      );
    draw();
    canvas
      ..restore()
      ..restore();
  }

  void _atmos(AtmosMark m, double t, bool still) {
    final c = colors;
    final b = still ? 0.0 : breathAt(t, 3.2), imp = 1 - b;
    double e(double s, double d) => still ? 1 : easeOut(progress(t, s, d));
    const all = Rect.fromLTWH(0, 0, 1, 1);
    final sky = _mix(c.tile, c.accent, c.lightPaper ? 0.18 : 0.12);
    canvas.drawRect(
      all,
      Paint()
        ..shader = _lin(0, 1, [
          (0, _mix(c.tile, c.deep, c.lightPaper ? 0.06 : 0), 1),
          (0.6, sky, 1),
          (1, _mix(c.tile, c.form, 0.25), 1),
        ]),
    );
    final s = m.sun, rise = e(0.2, 3), sunDy = (1 - rise) * 0.25;

    void ridge(RidgeLayer l, int i, int n, double drift) {
      final k = (i + 1) / n, base = l.y + (1 - e(0.3 + i * 0.3, 2)) * 0.06;
      final path = Path()..moveTo(-0.1, 1.2);
      for (var x = -0.1; x <= 1.1001; x += 0.02) {
        path.lineTo(
          x,
          base +
              l.amp *
                  (0.65 * math.sin(tau * l.f * (x + drift) + l.ph) +
                      0.35 * math.sin(tau * l.f2 * (x + drift) + l.ph2)),
        );
      }
      path
        ..lineTo(1.1, 1.2)
        ..close();
      _fill(
        path,
        _mix(_mix(c.form, c.light, 0.45 * (1 - k)), c.deep, 0.6 * k * k),
      );
    }

    switch (m.type) {
      case 'dawn':
      case 'ridges':
        _glow(
          s.cx,
          s.cy + sunDy,
          s.r * 3.2 * (1 + 0.08 * b),
          c.accent,
          0.55 * rise,
        );
        _plateB(m, () => _fill(blobPath(s, imperf: imp, dy: sunDy), c.accent));
        if (m.type == 'ridges') {
          for (var i = 0; i < m.layers.length; i++) {
            final l = m.layers[i];
            final drift = still
                ? 0.0
                : 0.025 * math.sin(tau * t / l.period + l.ph);
            canvas.drawRect(
              Rect.fromLTWH(0, l.y - 0.1, 1, 0.12),
              Paint()
                ..shader = _lin(l.y - 0.1, l.y + 0.02, [
                  (0, c.light, 0),
                  (0.8, c.light, c.lightPaper ? 0.4 : 0.18),
                  (1, c.light, 0),
                ]),
            );
            ridge(l, i, m.layers.length, drift);
          }
        } else {
          _rect(Rect.fromLTWH(0, m.horizon, 1, 1), _mix(c.form, c.deep, 0.45));
          _plateB(
            m,
            () => _rect(
              Rect.fromLTWH(0, m.horizon + 0.004, 1, 1),
              _mix(c.form, c.deep, 0.15),
            ),
          );
          final re = e(1.8, 1.6);
          for (var i = 0; i < 6; i++) {
            final k = i / 6;
            final y = m.horizon + 0.035 + 0.27 * math.pow(k, 1.2);
            final sh = still ? 0.0 : 0.2 * math.sin(tau * t / 6 + i * 1.7);
            final w = s.r * 2 * (0.9 - 0.65 * k) * (1 + sh) * re;
            canvas.drawLine(
              Offset(s.cx - w / 2, y),
              Offset(s.cx + w / 2, y),
              Paint()
                ..color = _a(c.accent, (0.95 - 0.5 * k) * re)
                ..strokeWidth = 0.017 - 0.008 * k
                ..strokeCap = StrokeCap.round,
            );
          }
        }
      case 'moonpool':
      case 'shoreline':
        _glow(s.cx, s.cy, s.r * 3, c.accent, 0.45 * rise);
        _plateB(
          m,
          () => _fill(
            blobPath(s, imperf: imp, dy: sunDy * 0.5),
            _mix(c.accent, c.light, 0.2),
          ),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, m.horizon, 1, 1),
          Paint()
            ..shader = _lin(m.horizon, 1, [
              (0, _mix(c.form, c.deep, 0.35), 1),
              (1, _mix(c.form, c.deep, 0.75), 1),
            ]),
        );
        if (m.type == 'moonpool') {
          for (var i = 0; i < 4; i++) {
            final u = still ? (i + 0.5) / 4 : ((t / 10 + i / 4) % 1);
            final r = 0.04 + 0.42 * u;
            canvas.drawOval(
              Rect.fromCenter(
                center: Offset(s.cx, m.horizon + 0.18),
                width: r * 2,
                height: r * 0.26 * 2,
              ),
              Paint()
                ..style = PaintingStyle.stroke
                ..color = _a(
                  _mix(c.accent, c.light, 0.3),
                  math.pow(1 - u, 1.1) * e(1, 2),
                )
                ..strokeWidth = 0.014 * (1 - 0.5 * u),
            );
          }
        } else {
          for (var i = 0; i < 4; i++) {
            final y = m.horizon + 0.06 + i * 0.075;
            final ph = still ? 0.0 : t * 0.25 + i;
            final path = Path()..moveTo(0, y);
            for (var x = 0.0; x <= 1.001; x += 0.02) {
              path.lineTo(
                x,
                y + 0.012 * math.sin(tau * (x * (1.4 + i * 0.3)) + ph),
              );
            }
            path
              ..lineTo(1, 1)
              ..lineTo(0, 1)
              ..close();
            _fill(path, _mix(c.form, c.deep, 0.2 + i * 0.18), 0.85);
            canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..color = _a(c.light, 0.35 * (1 - i / 4))
                ..strokeWidth = 0.006,
            );
          }
        }
      case 'doorlight':
        _rect(all, _mix(c.deep, c.form, 0.25));
        final (dw, dh) = m.door;
        final x0 = 0.5 - dw / 2;
        const bot = 0.8;
        final top = bot - dh, ys = top + dw / 2, open = e(0.2, 2.4);
        final arch = _arch(x0, dw, ys, bot);
        canvas
          ..save()
          ..clipPath(arch)
          ..drawRect(
            all,
            Paint()
              ..shader = _lin(top, bot, [
                (0, _mix(c.tile, c.accent, 0.3), 1),
                (1, _mix(c.accent, c.form, 0.3), 1),
              ]),
          );
        _fill(
          blobPath(
            s,
            imperf: imp,
            dx: 0.5 - s.cx,
            dy: ys + 0.06 - s.cy + sunDy,
            grow: 0.55,
          ),
          c.accent,
        );
        canvas.restore();
        // Light falling on the floor.
        final floor = Path()
          ..moveTo(x0, bot)
          ..lineTo(x0 + dw, bot)
          ..lineTo(0.5 + dw * 1.4, 1.02)
          ..lineTo(0.5 - dw * 1.1, 1.02)
          ..close();
        canvas.drawPath(
          floor,
          Paint()
            ..shader = _lin(bot, 1, [
              (0, _mix(c.accent, c.tile, 0.4), 0.7 * open * (0.9 + 0.1 * b)),
              (1, c.accent, 0),
            ]),
        );
        _plateB(
          m,
          () => canvas.drawPath(
            arch,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.012
              ..color = _a(_mix(c.accent, c.light, 0.4), 0.7),
          ),
        );
      case 'halo':
        _rect(all, _mix(c.tile, c.deep, c.lightPaper ? 0.04 : 0));
        _glow(0.5, 0.5, 0.46 * (1 + 0.06 * b), c.accent, 0.55 * rise);
        _plateB(
          m,
          () => _fill(
            blobPath(s, imperf: imp, grow: (0.9 + 0.1 * rise) * (1 + 0.03 * b)),
            c.form,
          ),
        );
        _stroke(
          m.ring!,
          still ? 1 : easeInOut(progress(t, 0.6, 2.6)),
          _a(c.stroke, 0.92),
        );
    }
  }

  // ---------- print finish ----------

  /// Paper tooth (overlay) and ink speckle over the tile, then an optional
  /// vignette (`core.js` `finish`).
  void _finish({double? paper, double speckle = 0.5, double vignette = 0.1}) {
    final tex = textures;
    final c = colors;
    const all = Rect.fromLTWH(0, 0, 1, 1);
    final scale = Float64List.fromList([
      texel, 0, 0, 0, //
      0, texel, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
    final paperImage = tex?.paper;
    if (paperImage != null) {
      canvas.drawRect(
        all,
        Paint()
          ..blendMode = BlendMode.overlay
          ..color = _a(
            const Color(0xFF000000),
            paper ?? (c.lightPaper ? 0.16 : 0.2),
          )
          ..shader = ImageShader(
            paperImage,
            TileMode.repeated,
            TileMode.repeated,
            scale,
          ),
      );
    }
    final speckleImage = tex?.speckleFor(c.tile);
    if (speckleImage != null) {
      canvas.drawRect(
        all,
        Paint()
          ..color = _a(const Color(0xFF000000), speckle)
          ..shader = ImageShader(
            speckleImage,
            TileMode.repeated,
            TileMode.repeated,
            scale,
          ),
      );
    }
    if (vignette != 0) {
      canvas.drawRect(
        all,
        Paint()
          ..shader = ui.Gradient.radial(
            const Offset(0.5, 0.5),
            0.75,
            [_a(c.deep, 0), _a(c.deep, vignette)],
            const [0.35 / 0.75, 1],
          ),
      );
    }
  }
}
