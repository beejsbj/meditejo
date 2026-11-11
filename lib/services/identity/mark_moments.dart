import 'dart:math' as math;

import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/seeded_random.dart';

/// The mark's one-shot moments, apart from its resting breath: a deep
/// breath when it is touched, and the passage from one day's mark to the
/// next. Pure timing, in seconds, so the player (#86) and tests can share
/// it. Nothing here runs on its own: the mark's own clock drives it.
abstract final class MarkMoments {
  /// One deep breath, from the first part's swell to the last part's
  /// settling.
  static const breathSeconds = 5.5;

  /// How long after the mark's body the parts that follow it take the same
  /// breath: a pebble swells, and the line's wave rises this much later.
  static const partLag = 0.6;

  /// The part of a breath spent breathing in.
  static const _inhale = 0.4;

  /// How long one part's own breath lasts: the body's ends [partLag] before
  /// the whole does, the last part's starts [partLag] in.
  static const partSeconds = breathSeconds - partLag;

  /// How far into a deep breath a part is, [s] seconds after the mark was
  /// touched: 0 at rest, 1 at the top of its in-breath, then back to 0.
  /// The body takes it at once; a part that follows takes it [lag] seconds
  /// later (up to [partLag]). Eased at both ends, so it swells and settles
  /// rather than bounces.
  static double swellAt(double s, {double lag = 0}) {
    final u = (s - lag) / partSeconds;
    if (u <= 0 || u >= 1) return 0;
    return u < _inhale
        ? easeInOut(u / _inhale)
        : 1 - easeInOut((u - _inhale) / (1 - _inhale));
  }

  /// How far a deep breath has pushed a line's wave along by [s] seconds,
  /// in wavelengths: one whole wave over the breath, quickest at its
  /// middle, so the line is back in step when the breath ends.
  static double runAt(double s) => easeInOut(s / breathSeconds);

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

/// How fast the player's mark breathes (#86): in step with the session's
/// pulse when it has one, else the resting six breaths a minute.
abstract final class PlayerBreath {
  /// The breaths a minute when no pulse is set.
  static const restingPerMinute = 6.0;

  /// The breath a pulse's is stretched to be near, and the bounds it stays
  /// within. A beat a second is a flicker, not a breath, so a breath spans a
  /// whole number of beats. Settings keep a pulse at 20 to 120 BPM (beats of
  /// 3 to 0.5 s), which this brings to 9 to 10.5 s.
  static const targetSeconds = 60 / restingPerMinute;
  static const minSeconds = 4.0;
  static const maxSeconds = 15.0;

  /// Seconds per breath for a session with [cues], or null for a still mark
  /// (reduced motion). With a pulse it is the whole number of beats (at
  /// least one) nearest [targetSeconds]; a pulse that ramps keeps its
  /// starting rate. The breath is not anchored to a beat: it starts when the
  /// mark does.
  static double? periodSeconds(CueSettings cues, {bool reducedMotion = false}) {
    if (reducedMotion) return null;
    if (cues.pulseSound.isEmpty || cues.pulseBpm <= 0) return targetSeconds;
    final beat = 60 / cues.pulseBpm;
    final beats = math.max(1, (targetSeconds / beat).round());
    return (beats * beat).clamp(minSeconds, maxSeconds);
  }
}
