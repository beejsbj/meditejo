import 'dart:math' as math;

import 'package:medito/widgets/art/engine/art_core.dart';

/// Shared helpers for the practice figures (`docs/fork/design/practices/`
/// `figures.js` and `figures-r2.js`), ported once so each figure file reads
/// like its JavaScript.

/// The fractional part, for phases that wrap.
double frac(double x) => x - x.floorToDouble();

/// Fill the current path, alpha clamped (`fill` in the practice figures).
void pFill(Ctx ctx, Rgb col, [double a = 1]) =>
    fillWith(ctx, col, clamp(a, 0, 1));

/// Stroke the current path with round caps. A width of 0 would be a
/// hairline in Flutter (and ignored in canvas), so it never goes below
/// 1e-4; alpha is clamped.
void pStroke(Ctx ctx, Rgb col, double w, [double a = 1]) =>
    strokeWith(ctx, col, math.max(w, 1e-4), clamp(a, 0, 1));

/// A soft disc of light fading out at the rim (`soft`).
void pSoft(Ctx ctx, double x, double y, double r, Rgb col, double a) {
  if (r <= 0 || a <= 0) return;
  final g = ctx.createRadialGradient(x, y, 0, x, y, r)
    ..addColorStop(0, css(col, clamp(a, 0, 1)))
    ..addColorStop(1, css(col, 0));
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, tau);
  ctx.fill();
}

/// An elliptical soft light: [pSoft] squashed (`softE`).
void pSoftE(
  Ctx ctx,
  double x,
  double y,
  double rx,
  double ry,
  Rgb col,
  double a,
) {
  if (rx <= 0 || ry <= 0 || a <= 0) return;
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(1, ry / rx);
  pSoft(ctx, 0, 0, rx, col, a);
  ctx.restore();
}

/// A circle path (`dot`, `ring`).
void pDot(Ctx ctx, double x, double y, double r) {
  ctx.beginPath();
  ctx.arc(x, y, math.max(r, 0), 0, tau);
}

/// Whether the inks sit on a light ground (`isLight`).
bool pIsLight(Inks k) => lum(k.paper) > 0.3;

/// A veil of cloud or mist: lighter than the sky by day, a pale haze by
/// night (`veilOf`).
Rgb pVeil(Inks k) =>
    pIsLight(k) ? mix(k.paper, Rgb.white, 0.72) : mix(k.paper, k.main, 0.3);

const _puffs = <(double, double, double)>[
  (0, 0, 1),
  (-0.42, 0.07, 0.72),
  (0.4, 0.08, 0.78),
  (0.14, -0.12, 0.8),
  (-0.2, -0.06, 0.7),
  (0.66, 0.12, 0.5),
  (-0.7, 0.12, 0.48),
];

/// A cloud: soft puffs, never an outline (`cloud`).
void pCloud(
  Ctx ctx,
  double x,
  double y,
  double w,
  Rgb col,
  double a, [
  List<(double, double, double)> puffs = _puffs,
]) {
  for (final (dx, dy, sc) in puffs) {
    pSoftE(ctx, x + dx * w, y + dy * w, w * 0.55 * sc, w * 0.3 * sc, col, a);
  }
}

/// A capsule centred at ([x], [y]) along angle [a] (`pill`).
void pPill(Ctx ctx, double x, double y, double len, double wid, double a) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(a);
  ctx.beginPath();
  ctx.roundRect(-len / 2, -wid / 2, len, wid, wid / 2);
  ctx.restore();
}

/// A closed curve r(θ) = R(1 + Σ aₖ sin(kθ + φₖ)) (`lobed`).
void pLobed(
  Ctx ctx,
  double x,
  double y,
  double r,
  List<(double, double, double)> waves, [
  double sy = 1,
  int m = 120,
]) {
  ctx.beginPath();
  for (var i = 0; i <= m; i++) {
    final th = tau * i / m;
    var rr = 1.0;
    for (final (kk, a, ph) in waves) {
      rr += a * math.sin(kk * th + ph);
    }
    final px = x + r * rr * math.cos(th), py = y + r * rr * sy * math.sin(th);
    if (i == 0) {
      ctx.moveTo(px, py);
    } else {
      ctx.lineTo(px, py);
    }
  }
  ctx.closePath();
}

/// A teardrop flame shape, tip up (`tear`).
void pTear(Ctx ctx, double x, double y, double h, double w) {
  ctx.beginPath();
  ctx.moveTo(x, y - h);
  ctx.bezierCurveTo(
    x + w * 0.9,
    y - h * 0.35,
    x + w,
    y + h * 0.2,
    x,
    y + h * 0.3,
  );
  ctx.bezierCurveTo(x - w, y + h * 0.2, x - w * 0.9, y - h * 0.35, x, y - h);
}

/// The dark closing in from the edges, standing for closed eyes
/// (`closeIn`).
void pCloseIn(Ctx ctx, double cx, double cy, double s, Rgb col, double a) {
  if (a <= 0) return;
  final g = ctx.createRadialGradient(cx, cy, s * 0.2, cx, cy, s * 2)
    ..addColorStop(0, css(col, clamp(a * 0.55, 0, 1)))
    ..addColorStop(0.5, css(col, clamp(a * 0.85, 0, 1)))
    ..addColorStop(1, css(col, clamp(a, 0, 1)));
  ctx.fillStyle = g;
  ctx.fillRect(cx - 2, cy - 2, 4, 4);
}

/// A number from a figure's params.
double pNum(Map<String, Object?> m, String key) => (m[key]! as num).toDouble();

/// Seconds per breath, as the figures pace themselves (`Core.BREATH`).
const breathPeriod = 10.0;

/// The clear disc (the mind's nature) Dzogchen and Mahāmudrā are drawn
/// round (`clearDisc`).
void pClearDisc(Ctx ctx, double x, double y, double R, Inks k, double b) {
  final g = ctx.createRadialGradient(x - R * 0.25, y - R * 0.3, 0, x, y, R)
    ..addColorStop(0, css(mix(k.paper, k.glow, 0.32), 0.95))
    ..addColorStop(0.7, css(mix(k.paper, k.main, 0.1), 0.85))
    ..addColorStop(1, css(mix(k.paper, k.main, 0.18), 0.85));
  ctx.fillStyle = g;
  pDot(ctx, x, y, R);
  ctx.fill();
  pDot(ctx, x, y, R);
  pStroke(ctx, k.main, 0.006, 0.5);
  ctx.beginPath();
  ctx.arc(x, y, R * 0.86, math.pi * 1.08, math.pi * (1.08 + 0.3 + 0.08 * b));
  pStroke(ctx, mix(k.glow, Rgb.white, 0.5), 0.008, 0.5);
}

/// The five lights (`FIVE`).
List<Rgb> pFive(Inks k) => [
  mix(k.glow, Rgb.white, 0.45),
  k.glow,
  k.alt,
  mix(k.alt, k.main, 0.45),
  mix(k.main, k.paper, 0.3),
];
