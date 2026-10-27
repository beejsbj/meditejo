import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A small HTML Canvas 2D context over a Flutter [Canvas], so the identity
/// exploration's drawing code (`docs/fork/design/identity/round4`–`round5`
/// on `fork/mark-explore`) ports line for line and draws the same art.
///
/// It keeps the browser's semantics where they differ from Flutter's:
///
/// - **Paths live in user space at the time each point is added.** A
///   transform applied mid-path (or a `restore`) moves only the points that
///   follow, as in the browser; Flutter would move the whole path.
/// - `lineTo` (and the curves) on an empty path start a subpath there,
///   instead of drawing from the origin.
/// - `arc` and `ellipse` join the current point with a line, and take the
///   browser's angle and direction rules.
/// - `save`/`restore` carry the styles (fill, stroke, alpha, composite,
///   line settings and dash) as well as the transform and clip.
/// - The miter limit is the browser's 10.
class Ctx {
  Ctx(this.canvas);

  final Canvas canvas;

  // ---------- state ----------

  /// A [Color], a [CtxGradient] or a [CtxPattern].
  Object fillStyle = const Color(0xFF000000);

  /// A [Color], a [CtxGradient] or a [CtxPattern].
  Object strokeStyle = const Color(0xFF000000);
  double _lineWidth = 1;
  StrokeCap lineCap = StrokeCap.butt;
  StrokeJoin lineJoin = StrokeJoin.miter;
  double _globalAlpha = 1;
  BlendMode globalCompositeOperation = BlendMode.srcOver;
  List<double> _dash = const [];

  double get lineWidth => _lineWidth;

  /// Zero, negative and non-finite widths are ignored, as in the browser.
  set lineWidth(double w) {
    if (w.isFinite && w > 0) _lineWidth = w;
  }

  double get globalAlpha => _globalAlpha;

  /// Values outside 0–1 are ignored, as in the browser.
  set globalAlpha(double a) {
    if (a.isFinite && a >= 0 && a <= 1) _globalAlpha = a;
  }

  void setLineDash(List<double> dash) {
    if (dash.any((d) => !d.isFinite || d < 0)) return;
    _dash = dash.length.isOdd ? [...dash, ...dash] : List.of(dash);
  }

  final _stack = <_State>[];

  // The current transform, relative to the canvas's when this Ctx was made.
  _Affine _m = _Affine.identity;

  void save() {
    _stack.add(
      _State(
        fillStyle,
        strokeStyle,
        _lineWidth,
        lineCap,
        lineJoin,
        _globalAlpha,
        globalCompositeOperation,
        _dash,
        _m,
      ),
    );
    canvas.save();
  }

  void restore() {
    if (_stack.isEmpty) return;
    final s = _stack.removeLast();
    fillStyle = s.fillStyle;
    strokeStyle = s.strokeStyle;
    _lineWidth = s.lineWidth;
    lineCap = s.lineCap;
    lineJoin = s.lineJoin;
    _globalAlpha = s.globalAlpha;
    globalCompositeOperation = s.composite;
    _dash = s.dash;
    canvas.restore();
    _moveTo(s.m);
  }

  // ---------- transforms ----------

  void translate(double x, double y) {
    canvas.translate(x, y);
    _moveTo(_m.times(_Affine(1, 0, 0, 1, x, y)));
  }

  void scale(double x, double y) {
    canvas.scale(x, y);
    _moveTo(_m.times(_Affine(x, 0, 0, y, 0, 0)));
  }

  void rotate(double a) {
    canvas.rotate(a);
    final c = math.cos(a), s = math.sin(a);
    _moveTo(_m.times(_Affine(c, s, -s, c, 0, 0)));
  }

  /// The current transform's horizontal scale (`getTransform().a`).
  double get transformA => _m.a;

  // Re-expresses the path built so far in the new user space, so its points
  // stay where they were drawn.
  void _moveTo(_Affine next) {
    if (_path != null && !_m.equals(next)) {
      final delta = next.inverse().times(_m);
      _path = _path!.transform(delta.storage);
      if (_cur != null) _cur = delta.apply(_cur!);
      if (_start != null) _start = delta.apply(_start!);
    }
    _m = next;
  }

  // ---------- paths ----------

  Path? _path;
  Offset? _cur, _start;

  Path get _p => _path ??= Path();

  void beginPath() {
    _path = null;
    _cur = _start = null;
  }

  void moveTo(double x, double y) {
    _p.moveTo(x, y);
    _cur = _start = Offset(x, y);
  }

  void lineTo(double x, double y) {
    if (_cur == null) return moveTo(x, y);
    _p.lineTo(x, y);
    _cur = Offset(x, y);
  }

  void closePath() {
    if (_path == null || _cur == null) return;
    _p.close();
    _cur = _start;
  }

  void quadraticCurveTo(double cx, double cy, double x, double y) {
    if (_cur == null) moveTo(cx, cy);
    _p.quadraticBezierTo(cx, cy, x, y);
    _cur = Offset(x, y);
  }

  void bezierCurveTo(
    double c1x,
    double c1y,
    double c2x,
    double c2y,
    double x,
    double y,
  ) {
    if (_cur == null) moveTo(c1x, c1y);
    _p.cubicTo(c1x, c1y, c2x, c2y, x, y);
    _cur = Offset(x, y);
  }

  void rect(double x, double y, double w, double h) {
    moveTo(x, y);
    _p
      ..lineTo(x + w, y)
      ..lineTo(x + w, y + h)
      ..lineTo(x, y + h)
      ..close();
  }

  /// `roundRect` with one radius for every corner.
  void roundRect(double x, double y, double w, double h, double r) {
    final rr = RRect.fromLTRBR(
      math.min(x, x + w),
      math.min(y, y + h),
      math.max(x, x + w),
      math.max(y, y + h),
      Radius.circular(math.min(r.abs(), math.min(w.abs(), h.abs()) / 2)),
    );
    _p.addRRect(rr);
    _cur = _start = Offset(x, y);
  }

  void arc(
    double x,
    double y,
    double r,
    double a0,
    double a1, [
    bool anticlockwise = false,
  ]) => ellipse(x, y, r, r, 0, a0, a1, anticlockwise);

  void ellipse(
    double x,
    double y,
    double rx,
    double ry,
    double rotation,
    double a0,
    double a1, [
    bool anticlockwise = false,
  ]) {
    rx = math.max(rx, 0);
    ry = math.max(ry, 0);
    const tau = math.pi * 2;
    double sweep;
    if (!anticlockwise && a1 - a0 >= tau) {
      sweep = tau;
    } else if (anticlockwise && a0 - a1 >= tau) {
      sweep = -tau;
    } else if (!anticlockwise) {
      sweep = (a1 - a0) % tau;
    } else {
      sweep = -((a0 - a1) % tau);
    }
    final cr = math.cos(rotation), sr = math.sin(rotation);
    Offset at(double a) {
      final ux = rx * math.cos(a), uy = ry * math.sin(a);
      return Offset(x + ux * cr - uy * sr, y + ux * sr + uy * cr);
    }

    final s = at(a0);
    if (_cur == null) {
      moveTo(s.dx, s.dy);
    } else {
      _p.lineTo(s.dx, s.dy);
    }
    if (sweep == 0 || (rx == 0 && ry == 0)) {
      _cur = s;
      return;
    }
    if (rotation == 0) {
      // Flutter's arcTo, in halves at most, so a full turn isn't lost.
      final oval = Rect.fromLTRB(x - rx, y - ry, x + rx, y + ry);
      final n = sweep.abs() > math.pi ? 2 : 1;
      for (var i = 0; i < n; i++) {
        _p.arcTo(oval, a0 + sweep * i / n, sweep / n, false);
      }
    } else {
      final n = math.max(8, (sweep.abs() / tau * 96).ceil());
      for (var i = 1; i <= n; i++) {
        final q = at(a0 + sweep * i / n);
        _p.lineTo(q.dx, q.dy);
      }
    }
    _cur = at(a0 + sweep);
  }

  // ---------- drawing ----------

  void fill([PathFillType rule = PathFillType.nonZero]) {
    final path = _path;
    if (path == null) return;
    path.fillType = rule;
    canvas.drawPath(path, _paint(fillStyle));
  }

  void stroke() {
    final path = _path;
    if (path == null) return;
    canvas.drawPath(_dash.isEmpty ? path : _dashed(path), _strokePaint());
  }

  void clip([PathFillType rule = PathFillType.nonZero]) {
    final path = _path;
    if (path == null) {
      canvas.clipRect(Rect.zero);
      return;
    }
    path.fillType = rule;
    canvas.clipPath(path);
  }

  void fillRect(double x, double y, double w, double h) {
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), _paint(fillStyle));
  }

  /// `drawImage(image, x, y, w, h)`, with the image's full source rect.
  void drawImage(ui.Image image, double x, double y, double w, double h) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(x, y, w, h),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, _globalAlpha)
        ..blendMode = globalCompositeOperation
        ..filterQuality = FilterQuality.low,
    );
  }

  /// Paints [draw] into a layer of its own, then lays that down with the
  /// current alpha and composite: what drawing to a scratch canvas and
  /// `drawImage`-ing it does on the page.
  void layer(void Function() draw) {
    final alpha = _globalAlpha, mode = globalCompositeOperation;
    save();
    canvas.saveLayer(
      null,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, alpha)
        ..blendMode = mode,
    );
    _globalAlpha = 1;
    globalCompositeOperation = BlendMode.srcOver;
    draw();
    canvas.restore();
    restore();
  }

  // ---------- styles ----------

  CtxGradient createLinearGradient(
    double x0,
    double y0,
    double x1,
    double y1,
  ) => CtxGradient._linear(x0, y0, x1, y1);

  CtxGradient createRadialGradient(
    double x0,
    double y0,
    double r0,
    double x1,
    double y1,
    double r1,
  ) => CtxGradient._radial(x0, y0, r0, x1, y1, r1);

  Paint _paint(Object style) {
    final paint = Paint()
      ..isAntiAlias = true
      ..blendMode = globalCompositeOperation;
    switch (style) {
      case Color c:
        paint.color = c.withValues(alpha: c.a * _globalAlpha);
      case CtxGradient g:
        final shader = g._shader();
        if (shader == null) {
          paint.color = const Color(0x00000000);
        } else {
          paint
            ..color = Color.fromRGBO(0, 0, 0, _globalAlpha)
            ..shader = shader;
        }
      case CtxPattern p:
        paint
          ..color = Color.fromRGBO(0, 0, 0, _globalAlpha)
          ..shader = ImageShader(
            p.image,
            TileMode.repeated,
            TileMode.repeated,
            p.transform,
            filterQuality: FilterQuality.low,
          );
      default:
        throw ArgumentError.value(style, 'style');
    }
    return paint;
  }

  Paint _strokePaint() => _paint(strokeStyle)
    ..style = PaintingStyle.stroke
    ..strokeWidth = _lineWidth
    ..strokeCap = lineCap
    ..strokeJoin = lineJoin
    ..strokeMiterLimit = 10;

  Path _dashed(Path source) {
    final out = Path();
    final total = _dash.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return source;
    for (final metric in source.computeMetrics()) {
      var d = 0.0, i = 0;
      while (d < metric.length) {
        final len = _dash[i % _dash.length];
        if (i.isEven) out.addPath(metric.extractPath(d, d + len), Offset.zero);
        d += len;
        i++;
      }
    }
    return out;
  }
}

/// A canvas gradient: linear, or radial between two circles.
class CtxGradient {
  CtxGradient._linear(this._x0, this._y0, this._x1, this._y1)
    : _r0 = null,
      _r1 = null;

  CtxGradient._radial(
    this._x0,
    this._y0,
    double r0,
    this._x1,
    this._y1,
    double r1,
  ) : _r0 = r0,
      _r1 = r1;

  final double _x0, _y0, _x1, _y1;
  final double? _r0, _r1;
  final _stops = <(double, Color)>[];

  void addColorStop(double offset, Color color) {
    if (!offset.isFinite || offset < 0 || offset > 1) {
      throw RangeError.range(offset, 0, 1, 'offset');
    }
    // After every stop at the same offset or before it, as in the browser.
    var i = _stops.length;
    while (i > 0 && _stops[i - 1].$1 > offset) {
      i--;
    }
    _stops.insert(i, (offset, color));
  }

  ui.Shader? _shader() {
    if (_stops.isEmpty) return null;
    final stops = _stops.length == 1 ? [_stops[0], _stops[0]] : _stops;
    final colors = [for (final s in stops) s.$2];
    final offsets = [for (final s in stops) s.$1];
    final r0 = _r0, r1 = _r1;
    if (r0 == null || r1 == null) {
      if (_x0 == _x1 && _y0 == _y1) return null;
      return ui.Gradient.linear(
        Offset(_x0, _y0),
        Offset(_x1, _y1),
        colors,
        offsets,
      );
    }
    if (r1 <= 0 && r0 <= 0) return null;
    if (_x0 == _x1 && _y0 == _y1) {
      // Concentric: map the stops onto r0..r1 of one circle.
      final outer = math.max(r0, r1);
      if (r0 <= r1) {
        return ui.Gradient.radial(Offset(_x1, _y1), outer, colors, [
          for (final o in offsets) (r0 + (r1 - r0) * o) / outer,
        ]);
      }
    }
    return ui.Gradient.radial(
      Offset(_x1, _y1),
      math.max(r1, 1e-9),
      colors,
      offsets,
      TileMode.clamp,
      null,
      Offset(_x0, _y0),
      r0,
    );
  }
}

/// A repeating image fill, with its own transform (`pattern.setTransform`).
class CtxPattern {
  CtxPattern(this.image, [Float64List? transform])
    : transform = transform ?? _Affine.identity.storage;

  final ui.Image image;
  final Float64List transform;

  /// `new DOMMatrix().translate(tx, ty).scale(s)`.
  static Float64List translateScale(double tx, double ty, double s) =>
      _Affine(s, 0, 0, s, tx, ty).storage;
}

class _State {
  _State(
    this.fillStyle,
    this.strokeStyle,
    this.lineWidth,
    this.lineCap,
    this.lineJoin,
    this.globalAlpha,
    this.composite,
    this.dash,
    this.m,
  );

  final Object fillStyle, strokeStyle;
  final double lineWidth, globalAlpha;
  final StrokeCap lineCap;
  final StrokeJoin lineJoin;
  final BlendMode composite;
  final List<double> dash;
  final _Affine m;
}

/// A 2-D affine transform in the canvas's (a, b, c, d, e, f) form:
/// x' = a·x + c·y + e, y' = b·x + d·y + f.
class _Affine {
  const _Affine(this.a, this.b, this.c, this.d, this.e, this.f);

  static const identity = _Affine(1, 0, 0, 1, 0, 0);

  final double a, b, c, d, e, f;

  /// This, then [o] (o is applied to points first).
  _Affine times(_Affine o) => _Affine(
    a * o.a + c * o.b,
    b * o.a + d * o.b,
    a * o.c + c * o.d,
    b * o.c + d * o.d,
    a * o.e + c * o.f + e,
    b * o.e + d * o.f + f,
  );

  _Affine inverse() {
    final det = a * d - b * c;
    if (det == 0) return identity;
    return _Affine(
      d / det,
      -b / det,
      -c / det,
      a / det,
      (c * f - d * e) / det,
      (b * e - a * f) / det,
    );
  }

  Offset apply(Offset p) =>
      Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  bool equals(_Affine o) =>
      a == o.a && b == o.b && c == o.c && d == o.d && e == o.e && f == o.f;

  Float64List get storage => Float64List.fromList([
    a, b, 0, 0, //
    c, d, 0, 0,
    0, 0, 1, 0,
    e, f, 0, 1,
  ]);
}
