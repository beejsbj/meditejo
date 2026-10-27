// The page's names (S, BR, H, R) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/identity/seeded_random.dart';
import 'package:medito/widgets/art/engine/canvas2d.dart';

export 'package:medito/services/identity/seeded_random.dart'
    show SeededRandom, tau, lerp, breathSeconds;
export 'package:medito/widgets/art/engine/canvas2d.dart';

/// The shared helpers of the art engine: `core.js` (round 2) as the round 4
/// and 5 art uses it, on `fork/mark-explore`.

// ---------- colour ----------

/// A colour as the page keeps it: three 0–255 channels as doubles, so
/// mixes compound exactly as `core.js` `mix` does. Channels are truncated
/// only when painted ([css]), as `core.js` `css` does.
@immutable
class Rgb {
  const Rgb(this.r, this.g, this.b);

  factory Rgb.argb(int argb) => Rgb(
    ((argb >> 16) & 0xFF) * 1.0,
    ((argb >> 8) & 0xFF) * 1.0,
    (argb & 0xFF) * 1.0,
  );

  /// `#rrggbb`.
  factory Rgb.hex(String hex) {
    final h = hex.replaceFirst('#', '');
    return Rgb(
      int.parse(h.substring(0, 2), radix: 16) * 1.0,
      int.parse(h.substring(2, 4), radix: 16) * 1.0,
      int.parse(h.substring(4, 6), radix: 16) * 1.0,
    );
  }

  static const white = Rgb(255, 255, 255);

  final double r, g, b;

  /// `core.js` `hex`: rounded, `#rrggbb`.
  String get hex =>
      '#${[r, g, b].map((x) => x.round().toRadixString(16).padLeft(2, '0')).join()}';

  @override
  bool operator ==(Object other) =>
      other is Rgb && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'Rgb($r, $g, $b)';
}

/// `core.js` `mix`.
Rgb mix(Rgb a, Rgb b, double t) =>
    Rgb(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t));

int _ch(double x) => x.isFinite ? x.toInt().clamp(0, 255) : 0;

/// `core.js` `css`: the colour at [alpha], channels truncated. Alpha is
/// clamped, as the browser clamps an `rgba()` alpha.
Color css(Rgb c, [double alpha = 1]) => Color.fromARGB(
  (clampTo(alpha.isNaN ? 0 : alpha, 0, 1) * 255).round(),
  _ch(c.r),
  _ch(c.g),
  _ch(c.b),
);

/// `core.js` `lum`: WCAG relative luminance, from the unrounded channels.
double lum(Rgb c) {
  double ch(double x) {
    x /= 255;
    return x <= 0.03928
        ? x / 12.92
        : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// `core.js` `contrast`.
double contrast(Rgb a, Rgb b) {
  final x = lum(a), y = lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// The roles every generator paints with (`core.js` `roles`): the
/// palette's four, plus the darker and lighter of tile and stroke.
@immutable
class ArtRoles {
  ArtRoles({
    required this.tile,
    required this.form,
    required this.stroke,
    required this.accent,
  }) : deep = lum(tile) < lum(stroke) ? tile : stroke,
       light = lum(tile) < lum(stroke) ? stroke : tile,
       lightPaper = lum(tile) > 0.35;

  factory ArtRoles.of(IdentityPalette p) => ArtRoles(
    tile: Rgb.argb(p.tile),
    form: Rgb.argb(p.form),
    stroke: Rgb.argb(p.stroke),
    accent: Rgb.argb(p.accent),
  );

  final Rgb tile, form, stroke, accent, deep, light;
  final bool lightPaper;

  /// `c[name]`.
  Rgb role(String name) => switch (name) {
    'tile' => tile,
    'form' => form,
    'stroke' => stroke,
    'accent' => accent,
    'deep' => deep,
    'light' => light,
    _ => throw ArgumentError.value(name, 'role'),
  };

  @override
  bool operator ==(Object other) =>
      other is ArtRoles &&
      other.tile == tile &&
      other.form == form &&
      other.stroke == stroke &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(tile, form, stroke, accent);
}

/// The inks a figure draws with (`compose.js` `inks`): the paper under it,
/// a main and an alternate ink, a line ink and a glow. [light] and [dark]
/// are only set where the page passes them (`{ light, dark }` for beads).
@immutable
class Inks {
  const Inks({
    required this.paper,
    required this.main,
    required this.alt,
    required this.line,
    required this.glow,
    this.light,
    this.dark,
  });

  final Rgb paper, main, alt, line, glow;
  final Rgb? light, dark;

  Inks copyWith({Rgb? paper, Rgb? main, Rgb? alt, Rgb? line, Rgb? glow}) =>
      Inks(
        paper: paper ?? this.paper,
        main: main ?? this.main,
        alt: alt ?? this.alt,
        line: line ?? this.line,
        glow: glow ?? this.glow,
        light: light,
        dark: dark,
      );
}

// ---------- parameters ----------

/// A primitive's parameters: plain JSON-like data, as the page builds them
/// and as `curated_art.json` freezes them. Builders write maps; painters
/// read them through this view, so a frozen composition and a freshly
/// built one draw through the same code.
extension type P(Map<String, Object?> m) {
  /// A number (frozen JSON may hold an int).
  double d(String key) => (m[key]! as num).toDouble();

  /// A number, or [fallback] when absent (`p.x ?? fallback`, `p.x || 0`).
  double dOr(String key, double fallback) =>
      (m[key] as num?)?.toDouble() ?? fallback;

  int i(String key) => (m[key]! as num).toInt();

  String s(String key) => m[key]! as String;

  String? sOr(String key) => m[key] as String?;

  /// JavaScript truthiness of the field.
  bool b(String key) => truthy(m[key]);

  bool has(String key) => m[key] != null;

  Object? operator [](String key) => m[key];

  P sub(String key) => P((m[key]! as Map).cast<String, Object?>());

  List<P> list(String key) => [
    for (final e in m[key]! as List) P((e as Map).cast<String, Object?>()),
  ];

  List<double> nums(String key) => [
    for (final e in m[key]! as List) (e as num).toDouble(),
  ];

  List<Object?> raw(String key) => m[key]! as List;
}

/// JavaScript truthiness: false for null, false, 0, NaN and ''.
bool truthy(Object? v) => switch (v) {
  null => false,
  bool b => b,
  num n => n != 0 && !n.isNaN,
  String s => s.isNotEmpty,
  _ => true,
};

/// `String(n)` as JavaScript writes a number: integral values without a
/// decimal point. Seeds built from numbers (`makeRng(p.nzSeed)`) need it.
String jsNum(num n) {
  if (n is int) return '$n';
  if (n.isFinite && n == n.truncateToDouble() && n.abs() < 1e21) {
    return n.toInt().toString();
  }
  return n.toString();
}

/// `core.js` `makeRng(String(x))`.
SeededRandom rngOf(Object seed) =>
    SeededRandom(seed is num ? jsNum(seed) : seed.toString());

// ---------- maths and motion ----------

/// `core.js` `clamp` (`Math.max(a, Math.min(b, x))`).
double clamp(double x, double a, double b) => math.max(a, math.min(b, x));

/// A slow, seamless sine: `S(t, period, phase)`.
double S(double t, double period, [double ph = 0]) =>
    math.sin(tau * t / period + ph);

/// Breath, 0–1, on the 10 s breath (`BR`); 0.5 when [still].
double BR(double t, bool still, [double ph = 0]) =>
    still ? 0.5 : 0.5 - 0.5 * math.cos(tau * t / breathSeconds + ph);

/// 0 at both ends of a wrapping phase, so wraps never pop (`fade`).
double fade(double u) => math.sin(math.pi * clamp(u, 0, 1));

/// `core.js` `ss` (smoothstep).
double ss(double a, double b, double x) {
  final t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

/// JavaScript's `%`: the sign of the dividend (Dart's `%` is never
/// negative). Use for `(a + t * v) % 1` and the like.
double jsMod(double a, double b) => a.remainder(b);

// ---------- shapes ----------

/// `core.js` `circle`: a fresh path holding one circle.
void circle(Ctx ctx, double x, double y, double r) {
  ctx.beginPath();
  ctx.arc(x, y, math.max(r, 0), 0, tau);
}

/// `core.js` `makeBlob`: a pebble's parameters, as plain data.
Map<String, Object?> makeBlob(
  SeededRandom rng,
  double cx,
  double cy,
  double R, [
  double rough = 1,
  double cut = 0,
]) => {
  'cx': cx,
  'cy': cy,
  'R': R,
  'rot': rng.range(0, tau),
  'asp': rng.range(0.9, 1.08),
  'a': [
    rng.range(0.03, 0.08) * rough,
    rng.range(0.015, 0.045) * rough,
    rng.range(0, 0.018) * rough,
  ],
  'p': [rng.range(0, tau), rng.range(0, tau), rng.range(0, tau)],
  'cut': cut,
  'cp': [rng.range(0, tau), rng.range(0, tau)],
  'ck': [rng.integer(7, 10), rng.integer(12, 17)],
};

/// `core.js` `blobPath`: imperf 0 is a true circle, 1 the full pebble.
void blobPath(
  Ctx ctx,
  P b, {
  double grow = 1,
  double imperf = 1,
  double dx = 0,
  double dy = 0,
  double sx = 1,
  double sy = 1,
  bool keep = false,
}) {
  final a = b.nums('a'), ph = b.nums('p'), cp = b.nums('cp'), ck = b.nums('ck');
  final cut = b.dOr('cut', 0), R = b.d('R'), cx = b.d('cx'), cy = b.d('cy');
  final asp = lerp(1, b.d('asp'), imperf), rot = b.d('rot');
  const m = 128;
  final c = math.cos(rot), s = math.sin(rot);
  if (!keep) ctx.beginPath();
  for (var i = 0; i <= m; i++) {
    final th = i / m * tau;
    var r = 1.0;
    for (var k = 0; k < 3; k++) {
      r += imperf * a[k] * math.sin((k + 2) * th + ph[k]);
    }
    if (cut != 0) {
      r +=
          cut *
          (0.6 * math.sin(ck[0] * th + cp[0]) +
              0.4 * math.sin(ck[1] * th + cp[1]));
    }
    r *= R * grow;
    final ux = r * math.cos(th) * asp * sx, uy = r * math.sin(th) * sy;
    final px = cx + dx + ux * c - uy * s, py = cy + dy + ux * s + uy * c;
    if (i == 0) {
      ctx.moveTo(px, py);
    } else {
      ctx.lineTo(px, py);
    }
  }
  ctx.closePath();
}

/// `core.js` `normals` over a polyline.
({List<double> nx, List<double> ny}) normals(
  List<(double, double)> pts, [
  int span = 1,
]) {
  final n = pts.length;
  final nx = List<double>.filled(n, 0), ny = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final a = pts[math.max(i - span, 0)], b = pts[math.min(i + span, n - 1)];
    final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
    var l = math.sqrt(dx * dx + dy * dy);
    if (l == 0) l = 1;
    nx[i] = -dy / l;
    ny[i] = dx / l;
  }
  return (nx: nx, ny: ny);
}

/// `core.js` `cutPoly`: a polygon with its edges roughened like scissors
/// on paper. Consumes [rng] as the page does.
void cutPoly(
  Ctx ctx,
  List<(double, double)> pts,
  SeededRandom rng, [
  double amt = 0.004,
]) {
  final dense = <(double, double)>[];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
    final n = math.max(2, (math.sqrt(dx * dx + dy * dy) / 0.01).ceil());
    for (var j = 0; j < n; j++) {
      dense.add((lerp(a.$1, b.$1, j / n), lerp(a.$2, b.$2, j / n)));
    }
  }
  final nz = rng.noise(3), nm = normals(dense, 1);
  ctx.beginPath();
  for (var i = 0; i < dense.length; i++) {
    final d = amt * nz(i * 0.3);
    final x = dense[i].$1 + nm.nx[i] * d, y = dense[i].$2 + nm.ny[i] * d;
    if (i == 0) {
      ctx.moveTo(x, y);
    } else {
      ctx.lineTo(x, y);
    }
  }
  ctx.closePath();
}

// ---------- the page's drawing helpers ----------
// The same small helpers grounds.js, prims.js and places.js each declare.

/// Fill the current path in [col] at alpha [a] (`fill`).
void fillWith(Ctx ctx, Rgb col, [double a = 1]) {
  ctx.globalAlpha = a;
  ctx.fillStyle = css(col);
  ctx.fill();
  ctx.globalAlpha = 1;
}

/// Stroke the current path, round caps and joins (`stroke`).
void strokeWith(Ctx ctx, Rgb col, double w, [double a = 1]) {
  ctx.globalAlpha = a;
  ctx.strokeStyle = css(col);
  ctx.lineWidth = w;
  ctx.lineCap = StrokeCap.round;
  ctx.lineJoin = StrokeJoin.round;
  ctx.stroke();
  ctx.globalAlpha = 1;
}

/// A soft disc of light, fading out at half radius (`glow`).
void glow(Ctx ctx, double x, double y, double r, Rgb col, double a) {
  final g = ctx.createRadialGradient(x, y, 0, x, y, r)
    ..addColorStop(0, css(col, a))
    ..addColorStop(0.5, css(col, a * 0.35))
    ..addColorStop(1, css(col, 0));
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, tau);
  ctx.fill();
}

/// A vertical gradient of `[offset, colour, alpha?]` stops from [y0] to
/// [y1] (places.js `vgrad`, which returns the gradient).
CtxGradient vgradient(
  Ctx ctx,
  double y0,
  double y1,
  List<(double, Rgb, double)> stops,
) {
  final g = ctx.createLinearGradient(0, y0, 0, y1);
  for (final (k, col, a) in stops) {
    g.addColorStop(k, css(col, a));
  }
  return g;
}

/// grounds.js `vgrad`: fill the whole card, 0 to [H], with a vertical
/// gradient.
void vgradFill(Ctx ctx, double H, List<(double, Rgb, double)> stops) {
  ctx.fillStyle = vgradient(ctx, 0, H, stops);
  ctx.fillRect(0, 0, 1, H);
}

/// `dark(c, k)`: the deep colour toward the form.
Rgb darkOf(ArtRoles c, double k) => mix(c.deep, c.form, k);
