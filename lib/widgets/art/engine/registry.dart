import 'package:medito/widgets/art/engine/bell.dart';
import 'package:medito/widgets/art/engine/figures.dart';
import 'package:medito/widgets/art/engine/grounds.dart';
import 'package:medito/widgets/art/engine/place_figures.dart';
import 'package:medito/widgets/art/engine/place_grounds.dart';
import 'package:medito/widgets/art/engine/practice_figures_r1a.dart';
import 'package:medito/widgets/art/engine/practice_figures_r1b.dart';
import 'package:medito/widgets/art/engine/practice_figures_r2.dart';
import 'package:medito/widgets/art/engine/practice_figures_r3a.dart';
import 'package:medito/widgets/art/engine/practice_figures_r3b.dart';
import 'package:medito/widgets/art/engine/practice_library_r2a.dart';
import 'package:medito/widgets/art/engine/practice_library_r2b.dart';
import 'package:medito/widgets/art/engine/practice_library_r2c.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

export 'package:medito/widgets/art/engine/primitives.dart';

/// Every ground and figure by name, as the meaning map and the frozen
/// compositions refer to them.
abstract final class ArtRegistry {
  static final Map<String, Ground> grounds = {
    ...roundFourGrounds,
    ...placeGrounds,
  };

  static final Map<String, Figure> figures = {
    ...roundFourFigures,
    ...placeFigures,
    'bell': const BellFigure(),
    // The ways to practise (docs/fork/design/practices/, rounds 1–3).
    ...practiceFiguresR1a,
    ...practiceFiguresR1b,
    ...practiceFiguresR2,
    ...practiceFiguresR3a,
    ...practiceFiguresR3b,
    // The figure library: variants not picked for their practice, drawn
    // for generated covers (ArtMap.figureLibrary, ArtMap.practiceLibrary).
    ...practiceLibraryR2a,
    ...practiceLibraryR2b,
    ...practiceLibraryR2c,
  };

  static Ground ground(String name) =>
      grounds[name] ?? (throw ArgumentError.value(name, 'ground'));

  static Figure figure(String name) =>
      figures[name] ?? (throw ArgumentError.value(name, 'figure'));

  /// The bell preset a shipped bell's id pins its figure to
  /// (`Prims.bell.presetFor`), or null.
  static String? bellPresetFor(String id) => BellFigure.presetFor(id);
}
