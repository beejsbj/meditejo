import 'dart:math' as math;
import 'dart:typed_data';

/// The Meditejo mark: everything about its shape and motion, and nothing
/// about how it is drawn. The painter (`meditejo_mark.dart`) and the static
/// SVG (`assets/branding/meditejo_mark.svg`, the source for a future app
/// icon) both read it, so they cannot drift apart.
///
/// Four shapes in a unit square, centred on (0.5, 0.5):
///   * a soft **blob** that turns once a loop and slowly changes shape;
///   * an open **ring**, an ensō-like arc, turning the other way;
///   * a small **dot** riding the ring's leading end;
///   * the **core**, a circle that breathes.
///
/// Motion is a function of the loop phase `t` in [0, 1). Every component
/// repeats a whole number of times per loop, so the loop is seamless. At
/// `t = 0` the mark is at rest: the still frame for reduced motion and the
/// SVG.
abstract final class MarkGeometry {
  /// Breaths per loop. With the 60 s loop (`MeditejoMotion.markLoop`) this is
  /// one breath every 10 s, six a minute: a slow, resting pace.
  static const breathsPerLoop = 6;

  static const center = 0.5;

  // Blob: a closed Catmull-Rom curve through [blobPoints] points.
  static const blobPoints = 6;
  static const blobRadius = 0.41;
  static const blobWobble = 0.05;
  static const _blobCycles = [1, 2, 1, 3, 2, 1];
  static const _blobPhases = [0.0, 1.9, 3.7, 0.8, 5.1, 2.6];
  // At rest the blob is not a circle: a gentle pebble.
  static const _blobRest = [1.0, 0.94, 1.03, 0.97, 1.05, 0.95];

  // Ring.
  static const ringRadius = 0.27;
  static const ringWidth = 0.034;
  static const ringSweep = 1.62 * math.pi; // 292°
  static const ringRestStart = -0.38 * math.pi;
  static const ringBreath = 0.012;

  // Dot at the ring's leading end.
  static const dotRadius = 0.034;

  // Core.
  static const coreRadius = 0.115;
  static const coreBreath = 0.14;

  /// Writes the frame at loop phase [t] into [out]. Allocates nothing.
  static void frameAt(double t, MarkFrame out) {
    final tau = 2 * math.pi;
    final breath = math.sin(tau * breathsPerLoop * t);

    // Blob: turns once a loop, each point's radius wobbling on its own
    // whole-number cycle.
    final turn = tau * t;
    final p = out._points;
    for (var i = 0; i < blobPoints; i++) {
      final angle = turn + tau * i / blobPoints;
      final wobble =
          blobWobble *
          (math.sin(tau * _blobCycles[i] * t + _blobPhases[i]) -
              math.sin(_blobPhases[i]));
      final r = blobRadius * (_blobRest[i] + wobble);
      p[2 * i] = center + r * math.cos(angle);
      p[2 * i + 1] = center + r * math.sin(angle);
    }
    // Closed Catmull-Rom to cubic Béziers: segment i runs P[i] → P[i+1].
    final b = out.blob;
    b[0] = p[0];
    b[1] = p[1];
    for (var i = 0; i < blobPoints; i++) {
      final i0 = (i - 1 + blobPoints) % blobPoints;
      final i2 = (i + 1) % blobPoints;
      final i3 = (i + 2) % blobPoints;
      final o = 2 + 6 * i;
      b[o] = p[2 * i] + (p[2 * i2] - p[2 * i0]) / 6;
      b[o + 1] = p[2 * i + 1] + (p[2 * i2 + 1] - p[2 * i0 + 1]) / 6;
      b[o + 2] = p[2 * i2] - (p[2 * i3] - p[2 * i]) / 6;
      b[o + 3] = p[2 * i2 + 1] - (p[2 * i3 + 1] - p[2 * i + 1]) / 6;
      b[o + 4] = p[2 * i2];
      b[o + 5] = p[2 * i2 + 1];
    }

    // Ring: turns once a loop the other way, breathing a little.
    out.ringRadiusNow = ringRadius + ringBreath * breath;
    out.ringStart = ringRestStart - turn;
    final head = out.ringStart + ringSweep;
    out.dotX = center + out.ringRadiusNow * math.cos(head);
    out.dotY = center + out.ringRadiusNow * math.sin(head);

    out.coreRadiusNow = coreRadius * (1 + coreBreath * breath);
  }

  /// The mark at rest as SVG, in the given colours (`#rrggbb`), on a
  /// [size]-pixel square. Coordinates are rounded to 0.01 px.
  static String svg({
    required String blob,
    required String ring,
    required String core,
    String? background,
    int size = 512,
  }) {
    final f = MarkFrame();
    frameAt(0, f);
    String n(double v) => (v * size).toStringAsFixed(2);
    final b = f.blob;
    final path = StringBuffer('M${n(b[0])} ${n(b[1])}');
    for (var i = 0; i < blobPoints; i++) {
      final o = 2 + 6 * i;
      path.write(
        ' C${n(b[o])} ${n(b[o + 1])} ${n(b[o + 2])} ${n(b[o + 3])} '
        '${n(b[o + 4])} ${n(b[o + 5])}',
      );
    }
    path.write(' Z');
    final r = f.ringRadiusNow;
    final x0 = center + r * math.cos(f.ringStart);
    final y0 = center + r * math.sin(f.ringStart);
    final large = ringSweep > math.pi ? 1 : 0;
    return [
      '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" '
          'viewBox="0 0 $size $size">',
      '  <title>Meditejo</title>',
      if (background != null)
        '  <rect width="$size" height="$size" fill="$background"/>',
      '  <path d="$path" fill="$blob"/>',
      '  <path d="M${n(x0)} ${n(y0)} A${n(r)} ${n(r)} 0 $large 1 '
          '${n(f.dotX)} ${n(f.dotY)}" fill="none" stroke="$ring" '
          'stroke-width="${n(ringWidth)}" stroke-linecap="round"/>',
      '  <circle cx="${n(f.dotX)}" cy="${n(f.dotY)}" r="${n(dotRadius)}" '
          'fill="$ring"/>',
      '  <circle cx="${n(center)}" cy="${n(center)}" '
          'r="${n(f.coreRadiusNow)}" fill="$core"/>',
      '</svg>',
      '',
    ].join('\n');
  }
}

/// One frame of the mark, in unit coordinates. Reused frame to frame.
class MarkFrame {
  final _points = Float64List(2 * MarkGeometry.blobPoints);

  /// The blob as a start point then, per segment, two control points and an
  /// end point: `x0 y0 (c1x c1y c2x c2y x y) × blobPoints`.
  final blob = Float64List(2 + 6 * MarkGeometry.blobPoints);

  double ringRadiusNow = MarkGeometry.ringRadius;
  double ringStart = MarkGeometry.ringRestStart;
  double dotX = 0;
  double dotY = 0;
  double coreRadiusNow = MarkGeometry.coreRadius;
}
