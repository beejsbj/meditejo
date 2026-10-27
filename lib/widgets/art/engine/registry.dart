import 'package:medito/widgets/art/engine/bell.dart';
import 'package:medito/widgets/art/engine/figures.dart';
import 'package:medito/widgets/art/engine/grounds.dart';
import 'package:medito/widgets/art/engine/place_figures.dart';
import 'package:medito/widgets/art/engine/place_grounds.dart';
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
  };

  static Ground ground(String name) =>
      grounds[name] ?? (throw ArgumentError.value(name, 'ground'));

  static Figure figure(String name) =>
      figures[name] ?? (throw ArgumentError.value(name, 'figure'));

  /// The bell preset a shipped bell's id pins its figure to
  /// (`Prims.bell.presetFor`), or null.
  static String? bellPresetFor(String id) => BellFigure.presetFor(id);
}
