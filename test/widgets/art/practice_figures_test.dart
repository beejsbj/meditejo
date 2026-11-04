import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/art/engine/compose.dart';
import 'package:medito/widgets/art/engine/figures.dart';
import 'package:medito/widgets/art/engine/place_figures.dart';
import 'package:medito/widgets/art/engine/practice_figures_r1a.dart';
import 'package:medito/widgets/art/engine/practice_figures_r1b.dart';
import 'package:medito/widgets/art/engine/practice_figures_r2.dart';
import 'package:medito/widgets/art/engine/practice_figures_r3a.dart';
import 'package:medito/widgets/art/engine/practice_figures_r3b.dart';
import 'package:medito/widgets/art/engine/practice_library_r2a.dart';
import 'package:medito/widgets/art/engine/practice_library_r2b.dart';
import 'package:medito/widgets/art/engine/practice_library_r2c.dart';
import 'package:medito/widgets/art/engine/registry.dart';

/// The practices' figures (ported from docs/fork/design/practices/, rounds
/// 1–3) and the figure library: each builds and draws, moving and still.
void main() {
  final catalogue = CategoryCatalogue.parse(
    File(categoriesAsset).readAsStringSync(),
  );
  final practice = {
    ...practiceFiguresR1a,
    ...practiceFiguresR1b,
    ...practiceFiguresR2,
    ...practiceFiguresR3a,
    ...practiceFiguresR3b,
    ...practiceLibraryR2a,
    ...practiceLibraryR2b,
    ...practiceLibraryR2c,
  };
  final roles = artRoles(IdentityPalettes.fallback);

  void drawAll(ArtComposition comp) {
    for (final (t, still) in [
      (0.0, false),
      (3.7, false),
      (14.2, false),
      (61.0, false),
      (0.0, true),
    ]) {
      final recorder = ui.PictureRecorder();
      paintArt(
        Canvas(recorder),
        const Size(170, 148),
        comp,
        roles,
        t,
        still: still,
      );
      recorder.endRecording().dispose();
    }
  }

  test('the practice figures are in the registry and shadow nothing', () {
    // 29 from rounds 1 and 2, 7 picks from round 3, 38 library variants.
    expect(practice, hasLength(74));
    final older = {...roundFourFigures.keys, ...placeFigures.keys, 'bell'};
    expect(practice.keys.toSet().intersection(older), isEmpty);
    for (final name in practice.keys) {
      expect(ArtRegistry.figures[name], same(practice[name]), reason: name);
    }
  });

  test('every practice draws, at any moment and as a still', () {
    for (final c in catalogue.categories) {
      final comp = Compose.buildPractice(
        c.id,
        ground: c.ground,
        figure: c.figure,
      );
      expect(comp.figure, isNotNull, reason: c.id);
      // Ānāpānasati and Nature keep round 4's breath and grass.
      expect(
        {...practice.keys, 'breath', 'grass'},
        contains(comp.figure!.name),
        reason: c.id,
      );
      // Built the same way twice: the art never moves.
      expect(
        Compose.buildPractice(
          c.id,
          ground: c.ground,
          figure: c.figure,
        ).freeze(),
        comp.freeze(),
        reason: c.id,
      );
      drawAll(comp);
    }
  });

  test('every library variant draws on its own ground', () {
    final pairs = [
      ...ArtMap.figureLibrary,
      for (final list in ArtMap.practiceLibrary.values) ...list,
    ];
    expect(ArtMap.figureLibrary, hasLength(33));
    for (final (ground, figure) in pairs) {
      expect(ArtRegistry.grounds, contains(ground), reason: '$figure');
      expect(ArtRegistry.figures, contains(figure), reason: figure);
      drawAll(
        Compose.buildPractice(
          'library:$figure',
          ground: ground,
          figure: figure,
        ),
      );
    }
  });

  test('generated covers draw from the library; a practice\'s own variants '
      'only for its content', () {
    final library = {for (final (_, f) in ArtMap.figureLibrary) f};
    final noting = {for (final (_, f) in ArtMap.practiceLibrary['noting']!) f};
    var fromLibrary = 0, notingWithout = 0, notingWith = 0;
    for (var i = 0; i < 400; i++) {
      final plain = Compose.buildFor('lib-course-$i', 'course')!;
      final name = plain.figure?.name;
      if (library.contains(name)) fromLibrary++;
      if (noting.contains(name)) notingWithout++;
      final labelled = Compose.buildFor(
        'lib-course-$i',
        'course',
        practice: 'noting',
      )!;
      if (noting.contains(labelled.figure?.name)) notingWith++;
    }
    // The library is most of a cover's choices now (33 beside 6 classics).
    expect(fromLibrary, greaterThan(200));
    expect(notingWithout, 0);
    expect(notingWith, greaterThan(0));
    // Only the generated covers carry a library, and build draws its extra
    // number only for a class with one: sounds, presets, places, bells and
    // teachers build exactly as before.
    expect(
      {
        for (final MapEntry(:key, :value) in ArtMap.classes.entries)
          if (value.library.isNotEmpty) key,
      },
      {'course', 'single', 'playlist'},
    );
  });

  test('an item\'s practice comes from one place, so every screen agrees', () {
    CuratedArt.instance.useJson('{"items": {}}');
    addTearDown(() => artPractices.value = const {});
    const cover = ArtSubject.cover(ArtCoverKind.course, 'lib-course-noted');
    final before = cover.key;
    artPractices.value = const {'lib-course-noted': 'noting'};
    // The same subject, wherever it is built, now draws for Noting.
    expect(cover.key, isNot(before));
    expect(cover.key, endsWith(':noting'));
    final comp = CuratedArt.instance.resolve(cover)!;
    expect(
      comp.freeze(),
      Compose.buildFor(
        'lib-course-noted',
        'course',
        practice: 'noting',
      )!.freeze(),
    );
  });

  test('the saved practices read back, and junk reads as none', () {
    expect(readArtPractices('{"lib-1": "noting", "x": 3}'), {
      'lib-1': 'noting',
    });
    expect(readArtPractices('not json'), isEmpty);
    expect(readArtPractices(null), isEmpty);
  });

  test('a teacher\'s cover never takes a practice', () {
    addTearDown(() => artPractices.value = const {});
    artPractices.value = const {'ds-teacher-1': 'noting'};
    const teacher = ArtSubject.cover(ArtCoverKind.teacher, 'ds-teacher-1');
    expect((teacher as CoverArt).drawnPractice, isNull);
  });
}
