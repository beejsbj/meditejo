import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/art/engine/art_textures.dart';

void main() {
  final curated = File('assets/art/curated_art.json').readAsStringSync();
  setUp(() => CuratedArt.instance.useJson(curated));
  tearDown(ArtRasters.instance.clear);

  testWidgets('a mounted tile survives its raster leaving the cache', (
    tester,
  ) async {
    await tester.runAsync(() => ArtTextures.instance.load());
    ArtRasters.instance.clear();
    const subject = ArtSubject.sound('rain-terrace');
    late StateSetter rebuild;
    Widget app() => MaterialApp(
      theme: meditejoTheme(Brightness.light),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              // Not const: the rebuild has to reach the tile.
              // ignore: prefer_const_constructors
              return SizedBox(
                width: 120,
                height: 120,
                // ignore: prefer_const_constructors
                child: ArtCover(subject: subject),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    for (var i = 0; i < 50 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(RawImage), findsOneWidget);

    // What a full cache does to the oldest raster: disposes it.
    ArtRasters.instance.clear();

    // The tile rebuilds (a toggle elsewhere in its list) and still draws.
    rebuild(() {});
    await tester.pump();
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(image.debugDisposed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
