import 'dart:math' as math;

/// Real time for the stats: the recording length at the speeds it was heard
/// at (a 60-minute talk heard at 2x is 30 minutes). Not a clock reading: it
/// keeps the mix of speeds playback used and scales the length by it.
///
/// iOS plays in Dart, so the mix is kept here; Android keeps the same in its
/// player service (`ListeningTracker` in CueMath.kt), with the same rules:
/// only playback that walks through the media in small steps counts, each
/// step weighing its speed by the media it covered. A pause or a seek changes
/// nothing. A stretch heard twice just weighs its speed in again.
class PlayedTime {
  PlayedTime({this.maxStepMs = 5000});

  /// The largest media step between samples that is still playback at 1x;
  /// faster playback widens it in proportion (as on Android).
  final int maxStepMs;

  int _last = -1;
  double _mediaMs = 0;
  double _realMs = 0;

  /// Media walked through by playback so far.
  double get playedMediaMs => _mediaMs;

  /// That media over the speed each step played at.
  double get playedRealMs => _realMs;

  /// A new track: nothing played yet.
  void reset() {
    _last = -1;
    _mediaMs = 0;
    _realMs = 0;
  }

  /// One sample of the player: where it is, whether it is audibly playing,
  /// and at what speed.
  void sample(int positionMs, {required bool playing, required double speed}) {
    if (!playing || positionMs < 0) {
      _last = -1;
      return;
    }
    final from = _last;
    _last = positionMs;
    if (from < 0) return;
    final step = positionMs - from;
    if (step <= 0 || step > maxStepMs * math.max(speed, 1.0)) return;
    _mediaMs += step;
    _realMs += step / math.max(speed, 0.05);
  }

  /// Real time a [durationMs] play-through takes at the speeds played so far;
  /// see [realDurationMs].
  int realMs(int durationMs, {required double speed}) => realDurationMs(
    durationMs,
    playedMediaMs: _mediaMs,
    playedRealMs: _realMs,
    speed: speed,
  );
}

/// Real time a whole session took, for "your time": the recording at the
/// speeds it was heard at ([recordingRealMs]), plus what no speed shortens:
/// the silence sat in ([silenceMs]: Extend and the ending bell's own) and the
/// countdown before the start. Mirrors `CueMath.sessionRealMs` on Android.
int sessionRealMs(
  int recordingRealMs, {
  int silenceMs = 0,
  int countdownMs = 0,
}) {
  int atLeastZero(int ms) => ms < 0 ? 0 : ms;
  return atLeastZero(recordingRealMs) +
      atLeastZero(silenceMs) +
      atLeastZero(countdownMs);
}

/// The [durationMs] recording's length scaled by the real time playback took
/// over the media it covered. Nothing played yet takes the [speed] in force.
/// Mirrors `CueMath.realDurationMs` on Android.
int realDurationMs(
  int durationMs, {
  required double playedMediaMs,
  required double playedRealMs,
  required double speed,
}) {
  if (durationMs <= 0) return math.max(0, durationMs);
  final ratio = playedMediaMs > 0 && playedRealMs > 0
      ? playedRealMs / playedMediaMs
      : 1 / math.max(speed, 0.05);
  return (durationMs * ratio).round();
}
