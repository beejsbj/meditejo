import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:medito/services/identity/seeded_random.dart';
import 'package:medito/utils/logger.dart';

/// The print finish's two textures (`core.js` `paperTex`, `speckleTex`):
/// paper tooth, laid over the art with overlay, and ink speckle in the
/// tile's colour, which only shows on ink. Made once, from fixed seeds.
///
/// Paper is decoded asynchronously ([load]); listeners hear when it is
/// ready, so a mark drawn before then repaints with its finish.
class MarkTextures extends ChangeNotifier {
  MarkTextures._();

  static final instance = MarkTextures._();

  ui.Image? _paper;
  Future<void>? _loading;
  final _speckles = <int, ui.Image>{};

  ui.Image? get paper => _paper;

  /// Starts making the paper texture, once.
  Future<void> load() => _loading ??= _makePaper().then(
    (image) {
      _paper = image;
      notifyListeners();
    },
    onError: (Object e) {
      // Without paper the marks still draw; try again on the next mark.
      _loading = null;
      AppLogger.e('IDENTITY', 'Mark paper texture failed', e);
    },
  );

  /// Speckle in [tile]'s colour, made on first use.
  ui.Image speckleFor(Color tile) =>
      _speckles[tile.toARGB32()] ??= _makeSpeckle(tile);

  static const _paperSize = 256;

  static Future<ui.Image> _makePaper() async {
    const n = _paperSize;
    final r = SeededRandom('paper');
    // Value noise at two scales, tileable.
    double Function(int, int) grid(int k) {
      final a = [for (var i = 0; i < k * k; i++) r.next()];
      return (x, y) {
        final gx = x / n * k, gy = y / n * k;
        final x0 = gx.floor(), y0 = gy.floor();
        final fx = gx - x0, fy = gy - y0;
        double v(int i, int j) => a[(j % k) * k + (i % k)];
        final sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
        return lerp(
          lerp(v(x0, y0), v(x0 + 1, y0), sx),
          lerp(v(x0, y0 + 1), v(x0 + 1, y0 + 1), sx),
          sy,
        );
      };
    }

    final big = grid(6), mid = grid(24);
    final pixels = Uint8List(n * n * 4);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final v =
            128 +
            (big(x, y) - 0.5) * 34 +
            (mid(x, y) - 0.5) * 26 +
            (r.next() - 0.5) * 46;
        final g = v.round().clamp(0, 255);
        final i = (y * n + x) * 4;
        pixels[i] = g;
        pixels[i + 1] = g;
        pixels[i + 2] = g;
        pixels[i + 3] = 255;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      n,
      n,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final base = await completer.future;

    // A few fibres.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawImage(base, Offset.zero, Paint());
    for (var i = 0; i < 70; i++) {
      final x = r.next() * n, y = r.next() * n, a = r.next() * tau;
      final l = 4 + r.next() * 14;
      final color = r.chance(0.5)
          ? const Color.fromRGBO(255, 255, 255, 0.35)
          : const Color.fromRGBO(0, 0, 0, 0.22);
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..quadraticBezierTo(
            x + math.cos(a + 0.6) * l / 2,
            y + math.sin(a + 0.6) * l / 2,
            x + math.cos(a) * l,
            y + math.sin(a) * l,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 0.6
          ..color = color,
      );
    }
    final image = recorder.endRecording().toImageSync(n, n);
    base.dispose();
    return image;
  }

  static ui.Image _makeSpeckle(Color tile) {
    const n = 128;
    final r = SeededRandom('speckle');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < 520; i++) {
      final paint = Paint()
        ..color = tile.withValues(alpha: 0.35 + r.next() * 0.6);
      final s = r.chance(0.85) ? 1.0 : 2.0;
      final x = (r.next() * n).floorToDouble(),
          y = (r.next() * n).floorToDouble();
      canvas.drawRect(Rect.fromLTWH(x, y, s, s), paint);
    }
    return recorder.endRecording().toImageSync(n, n);
  }
}
