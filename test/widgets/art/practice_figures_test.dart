import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/engine/compose.dart';
import 'package:medito/widgets/art/engine/figures.dart';
import 'package:medito/widgets/art/engine/place_figures.dart';
import 'package:medito/widgets/art/engine/practice_figures_r1a.dart';
import 'package:medito/widgets/art/engine/practice_figures_r1b.dart';
import 'package:medito/widgets/art/engine/practice_figures_r2.dart';
import 'package:medito/widgets/art/engine/registry.dart';

/// The practices' figures (ported from docs/fork/design/practices/): each
/// practice's art builds and draws, moving and still, in light and dark.
void main() {
  final catalogue = CategoryCatalogue.parse(
    File(categoriesAsset).readAsStringSync(),
  );

  test('the practice figures are in the registry and shadow nothing', () {
    final practice = {
      ...practiceFiguresR1a,
      ...practiceFiguresR1b,
      ...practiceFiguresR2,
    };
    expect(practice, hasLength(29));
    final older = {...roundFourFigures.keys, ...placeFigures.keys, 'bell'};
    expect(practice.keys.toSet().intersection(older), isEmpty);
    for (final name in practice.keys) {
      expect(ArtRegistry.figures[name], same(practice[name]), reason: name);
    }
  });

  test('every practice draws, at any moment and as a still', () {
    for (final palette in [IdentityPalettes.fallback]) {
      final roles = artRoles(palette);
      for (final c in catalogue.categories) {
        final comp = Compose.buildPractice(
          c.id,
          ground: c.ground,
          figure: c.figure,
        );
        expect(comp.figure, isNotNull, reason: c.id);
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
    }
  });
}
