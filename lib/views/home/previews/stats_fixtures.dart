// Stats fixtures shared by widget tests and previews.

import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';

LocalAllStats _stats({required bool doneToday}) {
  final now = DateTime.now();
  return LocalAllStats(
    streakCurrent: 12,
    streakLongest: 30,
    totalTracksCompleted: 48,
    totalTimeListened: 48 * 12 * 60,
    tracksChecked: const [],
    audioCompleted: doneToday
        ? [
            LocalAudioCompleted(
              id: 'track-3',
              timestamp: now.millisecondsSinceEpoch,
            ),
          ]
        : [
            LocalAudioCompleted(
              id: 'track-3',
              timestamp: now
                  .subtract(const Duration(days: 1))
                  .millisecondsSinceEpoch,
            ),
          ],
    updated: now.millisecondsSinceEpoch,
    freezeUsageDates: const [],
    consistencyScore: 0.82,
  );
}

final previewStats = _stats(doneToday: false);
final previewStatsDoneToday = _stats(doneToday: true);
