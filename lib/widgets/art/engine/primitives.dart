import 'package:medito/widgets/art/engine/art_core.dart';

/// A ground: fills the whole card (unit wide, [H] tall), moves slowly and
/// loops without a seam, and reports its [tone] so the composition can
/// choose inks that read on it (`grounds.js`, `places.js`).
abstract class Ground {
  const Ground();

  String get label;

  /// Seeded parameters, as plain data. [opts] carries pinned choices
  /// (`colour` for noise, `variant` for a place's variant).
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> opts);

  Rgb tone(ArtRoles c, P p);

  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H);
}

/// A figure: drawn at a place `{cx, cy, s}` in the unit square, in a
/// composition's inks, moving gracefully; [still] is the calm frame for
/// lists and reduced motion (`prims.js`, `places.js`).
abstract class Figure {
  const Figure();

  String get label;

  /// Seeded parameters, as plain data. [place] holds `cx`, `cy` and `s`
  /// (and any pinned extras, such as a bell's `preset`); [slot] is
  /// `figure` or `accent`.
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  );

  void draw(Ctx ctx, P p, Inks k, double t, bool still);
}
