import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The stats page needs each session's length and kind. They are recorded from
/// now on and read back; history from before them is left as it was.
void main() {
  final now = DateTime(2026, 10, 21, 14);
  final manager = StatsManager();

  Future<void> boot([LocalAllStats? stats]) async {
    manager.resetForTesting();
    SharedPreferences.setMockInitialValues({
      if (stats != null)
        SharedPreferenceConstants.localAllStatsKey: jsonEncode(stats.toJson()),
    });
    manager.setCurrentDateForTesting(now);
  }

  Future<LocalAllStats> restart() async {
    manager.resetForTesting();
    manager.setCurrentDateForTesting(now);
    return manager.localAllStats;
  }

  tearDown(manager.resetForTesting);

  test('records length, kind and course, and they survive a restart', () async {
    await boot();
    await manager.addAudioCompleted(
      LocalAudioCompleted(
        id: 'ds-talk-1',
        timestamp: now.millisecondsSinceEpoch,
      ),
      3600000,
      kind: 'talks',
      courseId: 'ds-retreat-4496',
      courseTitle: 'Practising the Jhānas',
    );
    final entry = (await restart()).audioCompleted!.single;
    expect(entry.durationMs, 3600000);
    expect(entry.kind, 'talks');
    expect(entry.courseId, 'ds-retreat-4496');
    expect(entry.courseTitle, 'Practising the Jhānas');
  });

  test('a session recorded with no label still keeps its length', () async {
    await boot();
    await manager.addAudioCompleted(
      LocalAudioCompleted(id: 'x', timestamp: now.millisecondsSinceEpoch),
      60000,
    );
    final entry = (await restart()).audioCompleted!.single;
    expect(entry.durationMs, 60000);
    expect(entry.kind, isNull);
    expect(entry.courseId, isNull);
  });

  test('history from before lengths were recorded reads back unchanged', () {
    final old = LocalAudioCompleted.fromJson({'timestamp': 5, 'id': 'a'});
    expect(old.durationMs, isNull);
    expect(old.kind, isNull);
    expect(old.courseId, isNull);
    expect(old.courseTitle, isNull);
  });

  test(
    'a repeat pass adds its minutes to that track\'s latest session',
    () async {
      await boot();
      final first = LocalAudioCompleted(
        id: 'lib-track-a',
        timestamp: now.millisecondsSinceEpoch,
      );
      await manager.addAudioCompleted(first, 600000, kind: 'practice');
      await manager.addRepeatListeningTime(600000, trackId: 'lib-track-a');
      await manager.addRepeatListeningTime(600000, trackId: 'lib-track-a');
      final stored = await restart();
      expect(stored.audioCompleted, hasLength(1));
      expect(stored.audioCompleted!.single.durationMs, 1800000);
      expect(stored.totalTimeListened, 1800000);
      expect(stored.totalTracksCompleted, 1);
    },
  );

  test(
    'a repeat of a session with no recorded length only moves the total',
    () async {
      await boot(
        LocalAllStats.empty().copyWith(
          totalTimeListened: 100,
          audioCompleted: [
            LocalAudioCompleted(
              id: 'old',
              timestamp: now.millisecondsSinceEpoch,
            ),
          ],
        ),
      );
      await manager.addRepeatListeningTime(5000, trackId: 'old');
      final stored = await restart();
      expect(stored.audioCompleted!.single.durationMs, isNull);
      expect(stored.totalTimeListened, 5100);
    },
  );

  test('deleting a session takes back the minutes it recorded', () async {
    await boot();
    final a = LocalAudioCompleted(
      id: 'a',
      timestamp: now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
    );
    final b = LocalAudioCompleted(
      id: 'b',
      timestamp: now.millisecondsSinceEpoch,
    );
    await manager.addAudioCompleted(a, 600000);
    await manager.addAudioCompleted(b, 300000);
    await manager.removeAudioCompleted(b);
    final stored = await restart();
    expect(stored.totalTimeListened, 600000);
    expect(stored.audioCompleted!.single.id, 'a');
  });

  test(
    'deleting an older session leaves the total it never recorded',
    () async {
      final old = LocalAudioCompleted(
        id: 'old',
        timestamp: now.millisecondsSinceEpoch,
      );
      await boot(
        LocalAllStats.empty().copyWith(
          totalTracksCompleted: 1,
          totalTimeListened: 900000,
          audioCompleted: [old],
        ),
      );
      await manager.removeAudioCompleted(old);
      expect((await restart()).totalTimeListened, 900000);
    },
  );
}
