import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/utils/day_boundary.dart';

class AudioCompletionTracker {
  /// Checks if a track crossed the user-perceived day boundary.
  ///
  /// With `dayBoundaryOffset = Duration.zero` (default) this is the legacy
  /// midnight check. A positive offset (e.g. +4h) shifts the boundary later,
  /// so a late-night session no longer counts as "crossing".
  static bool checkTrackCrossedMidnight({
    required int endTimestamp,
    required int duration,
    Duration dayBoundaryOffset = Duration.zero,
  }) {
    var endTime = DateTime.fromMillisecondsSinceEpoch(endTimestamp);
    var startTime = DateTime.fromMillisecondsSinceEpoch(
      endTimestamp - duration,
    );

    final startDay = dayOf(startTime, dayBoundaryOffset);
    final endDay = dayOf(endTime, dayBoundaryOffset);

    return startDay.isBefore(endDay);
  }

  /// Updates stats with a new completed audio track
  static LocalAllStats updateStatsWithCompletedAudio({
    required LocalAllStats? stats,
    required LocalAudioCompleted audioCompleted,
    required int duration,
  }) {
    // tracksChecked marks catalogue tracks as done. Timer ids carry their
    // length, so each one would be a new, meaningless entry.
    final checksTrack = !isTimerSessionId(audioCompleted.id);
    if (stats == null) {
      return LocalAllStats.empty().copyWith(
        audioCompleted: [audioCompleted],
        tracksChecked: [if (checksTrack) audioCompleted.id],
        totalTracksCompleted: 1,
        totalTimeListened: duration,
        updated: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    }

    final newDuration = duration + (stats.totalTimeListened);
    final newTotalTracks = 1 + (stats.totalTracksCompleted);

    var updatedTracksCompleted = stats.tracksChecked ?? [];
    if (checksTrack && !updatedTracksCompleted.contains(audioCompleted.id)) {
      updatedTracksCompleted.add(audioCompleted.id);
    }

    return stats.copyWith(
      tracksChecked: updatedTracksCompleted,
      audioCompleted: [...?stats.audioCompleted, audioCompleted],
      totalTracksCompleted: newTotalTracks,
      updated: DateTime.now().toUtc().millisecondsSinceEpoch,
      totalTimeListened: newDuration,
    );
  }

  /// Adds the minutes of a repeated play-through (repeat once / forever).
  /// The first play-through is already recorded as the session via
  /// [updateStatsWithCompletedAudio]; repetitions only add listening time so
  /// looping one track does not inflate the session count.
  ///
  /// With [trackId], [duration] is also added to that track's most recent
  /// entry that has a recorded length, so the stats page shows it on the day
  /// of the session. No such entry (an older history, with no recorded length)
  /// leaves only the running total. If the session it repeats was deleted,
  /// the minutes go to the track's latest remaining session instead.
  ///
  /// [realDuration] is the real time the repeat took (its speed applied); it
  /// is added to the entry's real time, which an entry without one starts
  /// from its recorded length. Without it the repeat's real time is its
  /// length. With no entry to add to, only the running total (recording
  /// length) grows, so its real time reads as its length.
  static LocalAllStats addRepeatListeningTime({
    required LocalAllStats? stats,
    required int duration,
    int? realDuration,
    String? trackId,
  }) {
    final base = stats ?? LocalAllStats.empty();
    var entries = base.audioCompleted;
    if (trackId != null && entries != null) {
      var latest = -1;
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (entry.id == trackId &&
            entry.durationMs != null &&
            (latest < 0 || entry.timestamp >= entries[latest].timestamp)) {
          latest = i;
        }
      }
      if (latest >= 0) {
        entries = [...entries];
        final entry = entries[latest];
        final realMs = entry.realMs == null && realDuration == null
            ? null
            : entry.realOrDurationMs! + (realDuration ?? duration);
        entries[latest] = entry.copyWith(
          durationMs: entry.durationMs! + duration,
          realMs: realMs,
        );
      }
    }
    return base.copyWith(
      audioCompleted: entries,
      totalTimeListened: base.totalTimeListened + duration,
      updated: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }
}
