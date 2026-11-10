import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/engine/compose.dart';

/// The cost of animating six practice cards at once, as on Explore at the
/// S23+'s width (two carousels, about three cards each). Opt-in, since it
/// measures this machine, not the phone:
///
///     MEDITEJO_BENCH=1 flutter test test/widgets/art/practice_art_cost_test.dart
///
/// It prints, per frame of six cards: the time to paint them (the figures'
/// Dart work, recording a picture) and to rasterise them on the CPU. On the
/// phone, rasterising happens on the GPU thread, so the first number is the
/// one that competes with the UI thread's 16 ms.
void main() {
  final run = Platform.environment['MEDITEJO_BENCH'] == '1';

  test('six live practice cards per frame', () async {
    final cat = CategoryCatalogue.parse(
      File(categoriesAsset).readAsStringSync(),
    );
    final roles = artRoles(IdentityPalettes.fallback);
    const dpr = 2.8125; // S23+: 1080 px across 384 dp
    const card = Size(148 * dpr, 132 * dpr);
    final report = StringBuffer();
    // Every practice, six at a time, so each figure is measured once.
    final all = cat.categories.toList();
    for (var start = 0; start < all.length; start += 6) {
      final six = [for (var i = 0; i < 6; i++) all[(start + i) % all.length]];
      final comps = [
        for (final c in six)
          Compose.buildPractice(c.id, ground: c.ground, figure: c.figure),
      ];
      const frames = 120;
      final paint = Stopwatch(), raster = Stopwatch();
      for (var f = 0; f < frames; f++) {
        final t = 60 + f / 30;
        paint.start();
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        for (final (i, comp) in comps.indexed) {
          canvas.save();
          canvas.translate((i % 3) * card.width, (i ~/ 3) * card.height);
          paintArt(canvas, card, comp, roles, t, still: false);
          canvas.restore();
        }
        final picture = rec.endRecording();
        paint.stop();
        if (f % 10 == 0) {
          raster.start();
          final img = await picture.toImage(
            (card.width * 3).ceil(),
            (card.height * 2).ceil(),
          );
          raster.stop();
          img.dispose();
        }
        picture.dispose();
      }
      final perPaint = paint.elapsedMicroseconds / frames / 1000;
      final perRaster = raster.elapsedMicroseconds / (frames / 10) / 1000;
      report.writeln(
        '${six.map((c) => c.id).join(', ')}: '
        'paint ${perPaint.toStringAsFixed(2)} ms, '
        'CPU raster ${perRaster.toStringAsFixed(1)} ms per frame of six',
      );
    }
    // ignore: avoid_print
    print(report);
  }, skip: !run);
}
