import 'dart:math' as math;

import 'package:medito/models/cues/cue_settings.dart';

enum CueType { start, interval, pulse, end }

class ScheduledCue {
  const ScheduledCue(this.at, this.type, this.sound, this.volume);
  final Duration at;
  final CueType type;
  final String sound;
  final double volume;
}

/// Pure deadline maths shared by guided audio and silent timer sessions.
/// All offsets include the optional countdown. Native execution owns clocks.
class CueSchedule {
  CueSchedule(
    this.settings, {
    required this.audioDuration,
    this.isTimer = false,
    this.seed = 1,
  });
  final CueSettings settings;
  final Duration audioDuration;
  final bool isTimer;
  final int seed;
  Duration get countdown => Duration(seconds: settings.countdownSeconds);
  Duration get practiceDuration =>
      settings.sessionDuration(audioDuration, isTimer: isTimer);
  Duration get end => countdown + practiceDuration;

  /// BPM is linear in elapsed seconds; solve the integral for beat n rather
  /// than repeatedly adding rounded intervals (which accumulates drift).
  Duration pulseAt(int beat) {
    if (beat < 1) throw ArgumentError.value(beat, 'beat', 'must be positive');
    final b0 = settings.pulseBpm;
    final b1 = settings.pulseEndBpm;
    final ramp = settings.pulseRampMinutes * 60.0;
    double seconds;
    if (ramp == 0 || b0 == b1) {
      seconds = beat * 60 / b0;
    } else {
      final rampBeats = ramp * (b0 + b1) / 120;
      if (beat > rampBeats) {
        seconds = ramp + (beat - rampBeats) * 60 / b1;
      } else {
        final slope = (b1 - b0) / ramp;
        // Rationalised quadratic formula is stable for very slow ramps.
        seconds = 120 * beat / (b0 + math.sqrt(b0 * b0 + 120 * slope * beat));
      }
    }
    return countdown + Duration(microseconds: (seconds * 1000000).round());
  }

  /// Park-Miller PRNG, deliberately reproducible in Dart/Kotlin/Swift.
  /// Integer modulo arithmetic avoids platform-specific Random sequences.
  Iterable<Duration> intervals() sync* {
    if (settings.intervalMinutes <= 0 || settings.intervalSound.isEmpty) return;
    var state = seed.abs() % 2147483647;
    if (state == 0) state = 1;
    var elapsedUs = 0;
    final low =
        math.max(1, settings.intervalMinutes - settings.randomWindowMinutes) *
        60000000;
    final high =
        (settings.intervalMinutes + settings.randomWindowMinutes) * 60000000;
    while (true) {
      state = state * 48271 % 2147483647;
      final gap = settings.randomWindowMinutes == 0
          ? settings.intervalMinutes * 60000000
          : low + ((high - low) * state / 2147483647).round();
      elapsedUs += gap;
      if (elapsedUs >= practiceDuration.inMicroseconds) return;
      yield countdown + Duration(microseconds: elapsedUs);
    }
  }

  List<ScheduledCue> events() {
    final result = <ScheduledCue>[];
    if (settings.startSound.isNotEmpty)
      result.add(
        ScheduledCue(
          countdown,
          CueType.start,
          settings.startSound,
          settings.bellVolume,
        ),
      );
    for (final at in intervals()) {
      result.add(
        ScheduledCue(
          at,
          CueType.interval,
          settings.intervalSound,
          settings.bellVolume,
        ),
      );
    }
    if (settings.pulseSound.isNotEmpty) {
      for (var beat = 1; ; beat++) {
        final at = pulseAt(beat);
        if (at >= end) break;
        result.add(
          ScheduledCue(
            at,
            CueType.pulse,
            settings.pulseSound,
            settings.pulseVolume,
          ),
        );
      }
    }
    if (settings.endSound.isNotEmpty)
      result.add(
        ScheduledCue(end, CueType.end, settings.endSound, settings.bellVolume),
      );
    result.sort((a, b) {
      final order = a.at.compareTo(b.at);
      return order == 0 ? a.type.index.compareTo(b.type.index) : order;
    });
    return result;
  }
}

/// Counts distinct media ranges actually rendered; a seek never adds coverage.
/// Native clocks provide the same bounded samples even with the screen off.
class ListeningCoverage {
  final List<(int, int)> _ranges = [];
  int? _lastPosition;
  int? _lastClock;
  bool _wasPlaying = false;
  int get heardMs => _ranges.fold(0, (sum, range) => sum + range.$2 - range.$1);
  List<List<int>> get ranges => [
    for (final r in _ranges) [r.$1, r.$2],
  ];

  void restore(List<List<int>> ranges) {
    for (final r in ranges) {
      if (r.length == 2 && r[0] >= 0 && r[1] > r[0]) _add(r[0], r[1]);
    }
  }

  void discontinuity() {
    _lastPosition = null;
    _lastClock = null;
    _wasPlaying = false;
  }

  void sample({
    required int positionMs,
    required int clockMs,
    required bool playing,
    double speed = 1,
  }) {
    final previous = _lastPosition;
    final clock = _lastClock;
    if (previous != null && clock != null && _wasPlaying) {
      final delta = positionMs - previous;
      final elapsed = clockMs - clock;
      if (delta > 0 && elapsed >= 0 && delta <= elapsed * speed + 100)
        _add(previous, positionMs);
    }
    _lastPosition = positionMs;
    _lastClock = clockMs;
    _wasPlaying = playing;
  }

  void _add(int start, int end) {
    var first = start;
    var last = end;
    final next = <(int, int)>[];
    for (final r in _ranges) {
      if (r.$2 < first || r.$1 > last) {
        next.add(r);
      } else {
        first = math.min(first, r.$1);
        last = math.max(last, r.$2);
      }
    }
    next.add((first, last));
    next.sort((a, b) => a.$1.compareTo(b.$1));
    _ranges
      ..clear()
      ..addAll(next);
  }

  bool completed(
    int durationMs, {
    bool isTimer = false,
    bool ended = false,
    bool extended = false,
  }) =>
      durationMs > 0 &&
      (isTimer ? ended : (extended && ended) || heardMs * 10 >= durationMs * 9);
}
