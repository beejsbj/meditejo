// Stats and pack fixtures shared by widget tests.

import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/models/pack/pack_model.dart';

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

/// Seven-session pack, three done.
final PackModel previewPack = () {
  const titles = [
    'Introduction to Meditation',
    'Breath Awareness',
    'Body Scan',
    'Noting Thoughts',
    'Working with Emotions',
    'Loving Kindness',
    'Open Awareness',
  ];
  return PackModel(
    id: 'lib-preview-course',
    title: 'A quiet practice',
    coverUrl: 'https://preview.medito.test/cover.png',
    items: List.generate(
      titles.length,
      (i) => PackItemsModel(
        type: 'track',
        id: 'track-${i + 1}',
        title: titles[i],
        subtitle: '${10 + i} min',
        coverUrl: 'https://picsum.photos/seed/track${i + 1}/400/400',
        path: 'tracks/track-${i + 1}',
        isCompleted: i < 3,
      ),
    ),
  );
}();
