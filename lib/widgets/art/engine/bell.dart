import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/primitives.dart';

/// The bell figure (`places.js` `P.bell`). TODO(port): fill in.
class BellFigure extends Figure {
  const BellFigure();

  static String? presetFor(String id) => null;

  @override
  String get label => 'bell';

  @override
  Map<String, Object?> build(
    SeededRandom r,
    Map<String, Object?> place,
    String slot,
  ) => throw UnimplementedError();

  @override
  void draw(Ctx ctx, P p, Inks k, double t, bool still) {}
}
