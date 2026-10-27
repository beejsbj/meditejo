import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/branding/mark_textures.dart';

/// The art's rasters, made once from fixed seeds:
///
/// - the **noise grain** the noise ground tiles (`places.js` `grainTex`,
///   seed `noise-grain-5`);
/// - the **print finish** (`compose.js` `grainFor`): paper tooth, ink
///   speckle and a vignette, baked into one transparent image per (tile,
///   size), laid over a card with a single `drawImage`. Round 3 measured
///   the baked raster at 34–62 fps against 7–11 for live pattern fills.
///
/// Both are made asynchronously; [load] starts them and listeners hear
/// when they're ready. Until then a card draws without them.
class ArtTextures extends ChangeNotifier {
  ArtTextures._();

  static final instance = ArtTextures._();

  ui.Image? _noise;
  Uint8List? _paper;
  Future<void>? _loading;

  /// The noise ground's 128 px grain, or null until [load] finishes.
  ui.Image? get noiseGrain => _noise;

  bool get ready => _noise != null && _paper != null;

  Future<void> load() => _loading ??= _load().catchError((Object e) {
    _loading = null;
    AppLogger.e('ART', 'Art textures failed', e);
  });

  Future<void> _load() async {
    await MarkTextures.instance.load();
    final paper = MarkTextures.instance.paper;
    if (paper == null) throw StateError('no paper texture');
    final bytes = await paper.toByteData(format: ui.ImageByteFormat.rawRgba);
    _paper = bytes!.buffer.asUint8List();
    _noise = await _fromPixels(_noisePixels(), 128, 128);
    notifyListeners();
  }

  static Uint8List _noisePixels() {
    const n = 128;
    final r = SeededRandom('noise-grain-5');
    final d = Uint8List(n * n * 4);
    for (var i = 0; i < d.length; i += 4) {
      final v = clampedByte(r.next() * 255);
      d[i] = d[i + 1] = d[i + 2] = v;
      d[i + 3] = 255;
    }
    return d;
  }

  // ---------- the print finish ----------

  final _finishes = <String, ui.Image>{};
  final _pending = <String, Future<ui.Image?>>{};

  static const _maxFinishes = 24;

  /// The finish's pixel size for a card [px] wide: the next power of two
  /// from 128 to 1024, so cards of similar sizes share one.
  static int finishSize(double px) {
    var n = 128;
    while (n < px && n < 1024) {
      n *= 2;
    }
    return n;
  }

  static String _key(ArtRoles c, int px, int ph) => '${c.tile.hex}|$px|$ph';

  /// The finish for a card [px] pixels wide and [H] tall (as a share of
  /// its width), if it has been made. Use [finishFor] to make it.
  ui.Image? finish(ArtRoles c, int px, double H) {
    final key = _key(c, px, (px * H).round());
    final image = _finishes.remove(key);
    if (image != null) _finishes[key] = image;
    return image;
  }

  /// Makes (or returns) the finish; null if the paper isn't ready.
  Future<ui.Image?> finishFor(ArtRoles c, int px, double H) {
    final ph = (px * H).round();
    final key = _key(c, px, ph);
    final have = finish(c, px, H);
    if (have != null) return SynchronousFuture(have);
    return _pending[key] ??= () async {
      try {
        await load();
        final paper = _paper;
        if (paper == null) return null;
        final image = await _fromPixels(finishPixels(c, px, H, paper), px, ph);
        _finishes[key] = image;
        while (_finishes.length > _maxFinishes) {
          _finishes.remove(_finishes.keys.first);
        }
        notifyListeners();
        return image;
      } finally {
        _pending.remove(key);
      }
    }();
  }

  /// `compose.js` `grainFor`, pixel for pixel: paper tooth (light where the
  /// paper is light, the deep colour where it's dark), a vignette, and a
  /// few flecks in the tile's colour. [paper] is the 256 px paper texture's
  /// RGBA.
  @visibleForTesting
  static Uint8List finishPixels(ArtRoles c, int px, double H, Uint8List paper) {
    final ph = (px * H).round();
    final d = Uint8List(px * ph * 4);
    final r = SeededRandom('grain4');
    final tile = c.tile, deep = c.deep, light = lum(c.tile) > 0.35;
    final tr = clampedByte(tile.r), tg = clampedByte(tile.g);
    final tb = clampedByte(tile.b);
    final dr = clampedByte(deep.r), dg = clampedByte(deep.g);
    final db = clampedByte(deep.b);
    for (var y = 0; y < ph; y++) {
      for (var x = 0; x < px; x++) {
        final i = (y * px + x) * 4;
        final hx = x / px - 0.5, hy = (y / ph - 0.5) * H;
        final vig = math.max(0, math.sqrt(hx * hx + hy * hy) - 0.38) / 0.4;
        if (r.next() < 0.004) {
          d[i] = tr;
          d[i + 1] = tg;
          d[i + 2] = tb;
          d[i + 3] = 110;
          continue;
        }
        final v = (paper[((y & 255) * 256 + (x & 255)) * 4] - 128) / 128;
        if (v > 0) {
          d[i] = d[i + 1] = d[i + 2] = 255;
          d[i + 3] = clampedByte(v * (light ? 38 : 22));
        } else {
          d[i] = dr;
          d[i + 1] = dg;
          d[i + 2] = db;
          d[i + 3] = clampedByte(-v * (light ? 32 : 40) + vig * 26);
        }
      }
    }
    return d;
  }

  static Future<ui.Image> _fromPixels(Uint8List pixels, int w, int h) {
    final done = Completer<ui.Image>();
    // The page's ImageData is unpremultiplied RGBA; raw pixels here are
    // taken as premultiplied, as the canvas stores them.
    for (var i = 0; i < pixels.length; i += 4) {
      final a = pixels[i + 3];
      if (a == 255) continue;
      for (var k = 0; k < 3; k++) {
        pixels[i + k] = (pixels[i + k] * a / 255).round();
      }
    }
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
}

/// A `Uint8ClampedArray` store: clamped to 0–255, rounded half to even.
int clampedByte(double v) {
  if (v.isNaN || v <= 0) return 0;
  if (v >= 255) return 255;
  final f = v.floorToDouble(), diff = v - f;
  if (diff > 0.5) return f.toInt() + 1;
  if (diff < 0.5) return f.toInt();
  return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
}
