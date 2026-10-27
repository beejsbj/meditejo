// The page's names (H, R) are kept so the port reads line for line.
// ignore_for_file: non_constant_identifier_names

import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// Round 4's grounds (`grounds.js`), with the noise texture as round 5
/// redraws it (`places.js`): round 2's atmospheres rebuilt as grounds that
/// figures sit on. Each fills the whole card (unit wide, H tall), moves
/// slowly and loops without a seam.
final Map<String, Ground> roundFourGrounds = {'paper': const PaperGround()};

/// Flat paper in one of three value keys: the quietest ground.
class PaperGround extends Ground {
  const PaperGround();

  @override
  String get label => 'paper';

  @override
  Map<String, Object?> build(SeededRandom r, Map<String, Object?> o) => {
    'key': o['key'] ?? r.pick(const ['light', 'light', 'mid']),
    'k': r.range(0, 0.12),
  };

  @override
  Rgb tone(ArtRoles c, P p) => switch (p.s('key')) {
    'light' => mix(c.tile, c.accent, p.d('k')),
    'mid' => mix(c.form, c.tile, 0.35),
    _ => darkOf(c, 0.2),
  };

  @override
  void draw(Ctx ctx, P p, ArtRoles c, double t, bool still, double H) {
    final b = tone(c, p);
    vgradFill(ctx, H, [(0, b, 1), (1, mix(b, c.deep, 0.06), 1)]);
  }
}
