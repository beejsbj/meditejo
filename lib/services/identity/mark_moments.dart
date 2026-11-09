import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/seeded_random.dart';

/// The mark's one-shot moments, apart from its resting breath: a deep
/// breath when it is touched, and the passage from one day's mark to the
/// next. Pure timing, in seconds, so the player (#86) and tests can share
/// it. Nothing here runs on its own: the mark's own clock drives it.
abstract final class MarkMoments {
  /// One deep breath: a slow swell and a longer settle.
  static const breathSeconds = 5.5;

  /// The part of [breathSeconds] spent breathing in.
  static const _inhale = 0.4;

  /// How much larger the mark is at the top of a deep breath.
  static const swellScale = 0.08;

  /// How far into a deep breath [s] seconds is: 0 at rest, 1 at the top of
  /// the in-breath, then back to 0 by [breathSeconds]. Eased at both ends,
  /// so it swells and settles rather than bounces.
  static double swellAt(double s) {
    if (s <= 0 || s >= breathSeconds) return 0;
    final u = s / breathSeconds;
    return u < _inhale
        ? easeInOut(u / _inhale)
        : 1 - easeInOut((u - _inhale) / (1 - _inhale));
  }

  /// The day's turn: yesterday's mark un-draws over [undrawSeconds] (its own
  /// draw-in, played backwards) while today's starts drawing itself in
  /// [morphLead] seconds after it began.
  static const undrawSeconds = 2.2;
  static const morphLead = 1.2;

  /// With reduced motion, the two marks' settled frames crossfade instead.
  static const crossfade = Duration(milliseconds: 1200);

  /// Where yesterday's mark is in its own life, [s] seconds into the turn:
  /// from [drawnBy] back to its first moment.
  static double undrawTimeAt(MarkSpec m, double s) =>
      drawnBy(m) * (1 - easeInOut(progress(s, 0, undrawSeconds)));

  /// Yesterday's opacity [s] seconds into the turn: whole while it un-draws,
  /// fading over the second half (a scene has a sky that never un-draws).
  static double undrawOpacityAt(double s) =>
      1 - easeInOut(progress(s, undrawSeconds * 0.45, undrawSeconds * 0.55));

  /// Seconds a mark takes to draw itself in (see `MarkRenderer.draw`).
  static double drawnBy(MarkSpec m) => switch (m) {
    GestureMark(:final duration) => 0.5 + duration,
    MinimalMark() => 2.3,
    AtmosMark() => 3.4,
  };

  /// The whole turn, today's name included: it fades in as today's mark
  /// starts drawing, rests, then fades away. The turn's clock (the mark's
  /// own, see `MeditejoMark.turnClock`) runs this long, with reduced motion
  /// too.
  static const nameSeconds = 6.0;

  /// When today's name starts to show.
  static const nameFrom = 1.0;
  static const _nameIn = (nameFrom, 1.8);
  static const _nameOut = (4.6, nameSeconds);

  /// The name's opacity [s] seconds into the turn.
  static double nameOpacityAt(double s) {
    if (s < _nameOut.$1) {
      return easeInOut(progress(s, _nameIn.$1, _nameIn.$2 - _nameIn.$1));
    }
    return 1 - easeInOut(progress(s, _nameOut.$1, _nameOut.$2 - _nameOut.$1));
  }
}
