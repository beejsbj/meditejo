// Frame-cost measurements for the generated art. Off by default:
//
//     MEDITEJO_ART_BENCH=1 flutter test test/widgets/art/art_benchmark_test.dart
//
// It runs on flutter_tester's software renderer on the host, so the numbers
// are relative, not a phone's. What it shows is where the cost sits: a
// live frame of each card (what a moving card costs per frame), a still
// raster at list and full-screen size (paid once, then cached), and a
// 30-card Sounds-sized grid and a long list scrolled over cached rasters
// (what scrolling costs once the stills exist).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/art/engine/art_textures.dart';

final _enabled = Platform.environment['MEDITEJO_ART_BENCH'] == '1';

double _median(List<double> xs) => (xs..sort())[xs.length ~/ 2];
double _p95(List<double> xs) => (xs..sort())[((xs.length - 1) * 0.95).round()];

void main() {
  final curated = File('assets/art/curated_art.json').readAsStringSync();
  setUp(() => CuratedArt.instance.useJson(curated));

  testWidgets('a live frame, and a still raster, per card', (tester) async {
    await tester.runAsync(() async {
      await ArtTextures.instance.load();
      final roles = artRoles(IdentityPalettes.fallback);
      final live = <String, double>{};
      final ids = CuratedArt.instance.ids.toList();
      for (final id in ids) {
        final e = CuratedArt.instance.entry(id)!;
        final subject = switch (e['kind']) {
          'sound' => ArtSubject.sound(id),
          'course' => ArtSubject.cover(ArtCoverKind.course, id),
          'single' => ArtSubject.cover(ArtCoverKind.single, id),
          'bell' => ArtSubject.bell(e['asset']! as String),
          _ => null,
        };
        if (subject == null) continue;
        final comp = CuratedArt.instance.resolve(subject)!;
        final times = <double>[];
        for (var i = 0; i < 30; i++) {
          final sw = Stopwatch()..start();
          final rec = ui.PictureRecorder();
          paintArt(
            Canvas(rec),
            const Size(168, 168),
            comp,
            roles,
            60 + i / 30,
            still: false,
          );
          final pic = rec.endRecording();
          final img = pic.toImageSync(168, 168);
          sw.stop();
          img.dispose();
          pic.dispose();
          if (i >= 5) times.add(sw.elapsedMicroseconds / 1000);
        }
        live[id] = _median(times);
      }
      final sorted = live.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print(
        'live frame at 168 px (record + raster), median per card: '
        'all ${_median(live.values.toList()).toStringAsFixed(2)} ms; '
        'heaviest ${sorted.take(5).map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(', ')}',
      );

      for (final px in [168, 420, 1080]) {
        final times = <double>[];
        ArtRasters.instance.clear();
        for (final id in ids.where(
          (id) => CuratedArt.instance.entry(id)!['kind'] == 'sound',
        )) {
          final comp = CuratedArt.instance.resolve(ArtSubject.sound(id))!;
          final sw = Stopwatch()..start();
          await ArtRasters.instance.still('bench|$id|$px', comp, roles, px, px);
          times.add(sw.elapsedMicroseconds / 1000);
        }
        // ignore: avoid_print
        print(
          'still raster at $px px: median ${_median(times).toStringAsFixed(1)} ms, '
          'p95 ${_p95(times).toStringAsFixed(1)} ms',
        );
      }
    });
  }, skip: !_enabled);

  Future<void> scroll(
    WidgetTester tester,
    String label,
    Widget Function(int i) item, {
    required int count,
    required SliverGridDelegate? grid,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => ArtTextures.instance.load());
    final list = grid == null
        ? ListView.builder(itemCount: count, itemBuilder: (_, i) => item(i))
        : GridView.builder(
            gridDelegate: grid,
            itemCount: count,
            itemBuilder: (_, i) => item(i),
          );
    await tester.pumpWidget(
      MaterialApp(
        theme: meditejoTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: list),
        ),
      ),
    );
    // Let the stills rasterise (real async work), scrolling once through.
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < 40; i++) {
        await tester.drag(find.byType(Scrollable), const Offset(0, -120));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      for (var i = 0; i < 40; i++) {
        await tester.drag(find.byType(Scrollable), const Offset(0, 120));
        await tester.pump();
      }
    }
    final frames = <double>[];
    for (var i = 0; i < 80; i++) {
      final sw = Stopwatch()..start();
      await tester.drag(find.byType(Scrollable), Offset(0, i < 40 ? -60 : 60));
      await tester.pump(const Duration(milliseconds: 16));
      sw.stop();
      frames.add(sw.elapsedMicroseconds / 1000);
    }
    // ignore: avoid_print
    print(
      '$label, scrolled over cached stills: frame median '
      '${_median(frames).toStringAsFixed(2)} ms, '
      'p95 ${_p95(frames).toStringAsFixed(2)} ms (build, layout, paint; host)',
    );
  }

  const sounds = [
    'rain-terrace', 'rain-umbrella', 'rain-window', 'rain-car', //
    'rain-indoors', 'rain-balcony', 'stream', 'river', 'waves', 'sea',
    'ocean', 'wind-trees', 'wind-grass', 'forest-birds', 'dawn-chorus',
    'evening-birds', 'forest-brook', 'wood-thrush', 'fire-crackle',
    'fire-stove', 'room-house', 'cafe', 'train', 'laundry-room', 'fan',
    'train-yamanote', 'night-meadow', 'night-insects', 'night-frogs',
    'night-shore',
  ];

  testWidgets('a 30-card Sounds grid scrolls', (tester) async {
    await scroll(
      tester,
      '30-card grid (3 across)',
      (i) => Padding(
        padding: const EdgeInsets.all(5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ArtCover(subject: ArtSubject.sound(sounds[i % 30])),
        ),
      ),
      count: 30,
      grid: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
    );
  }, skip: !_enabled);

  testWidgets('a long Library list scrolls', (tester) async {
    await scroll(
      tester,
      '200-row library list',
      (i) => ListTile(
        leading: SizedBox.square(
          dimension: 56,
          child: ArtCover(
            subject: ArtSubject.cover(ArtCoverKind.course, 'lib-course-$i'),
          ),
        ),
        title: Text('Course $i'),
      ),
      count: 200,
      grid: null,
    );
  }, skip: !_enabled);
}
