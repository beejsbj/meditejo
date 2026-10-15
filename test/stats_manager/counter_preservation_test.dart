import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A first completion in a fresh engine must load the on-device history
/// before incrementing its counters. No server can recover an overwritten copy.
void main() {
  final today = DateTime(2026, 9, 6, 12);
  final manager = StatsManager();

  LocalAllStats historyStats() => LocalAllStats.empty().copyWith(
    totalTracksCompleted: 1353,
    totalTimeListened: 200 * 60 * 60 * 1000,
    streakLongest: 312,
    audioCompleted: List.generate(
      300,
      (i) => LocalAudioCompleted(
        id: 'track-$i',
        timestamp: today.subtract(Duration(days: i)).millisecondsSinceEpoch,
      ),
    ),
    tracksChecked: ['existing-track'],
  );

  Future<void> boot(LocalAllStats stats) async {
    manager.resetForTesting();
    SharedPreferences.setMockInitialValues({
      SharedPreferenceConstants.localAllStatsKey: jsonEncode(stats.toJson()),
    });
    manager.setCurrentDateForTesting(today);
  }

  Future<LocalAllStats> restart() async {
    manager.resetForTesting();
    manager.setCurrentDateForTesting(today);
    return manager.localAllStats;
  }

  tearDown(manager.resetForTesting);

  test('first completion preserves lifetime counters and history', () async {
    final history = historyStats();
    await boot(history);
    await manager.addAudioCompleted(
      LocalAudioCompleted(
        id: 'new-track',
        timestamp: today.millisecondsSinceEpoch,
      ),
      600000,
    );

    final stored = await restart();
    expect(stored.totalTracksCompleted, 1354);
    expect(stored.totalTimeListened, history.totalTimeListened + 600000);
    expect(stored.audioCompleted, hasLength(301));
    expect(stored.streakLongest, 312);
    expect(stored.tracksChecked, containsAll(['existing-track', 'new-track']));
  });

  test(
    'refresh recalculates streak while preserving lifetime counters',
    () async {
      final history = historyStats();
      await boot(history);
      await manager.sync(force: true);
      var stored = await restart();
      expect(stored.totalTracksCompleted, 1353);
      expect(stored.totalTimeListened, history.totalTimeListened);
      expect(stored.streakCurrent, 300);
      expect(stored.streakLongest, 312);

      manager.setCurrentDateForTesting(today.add(const Duration(days: 2)));
      await manager.sync();
      stored = await restart();
      expect(stored.streakCurrent, 0);
      expect(stored.streakLongest, 312);
      expect(stored.audioCompleted, hasLength(300));
    },
  );

  test(
    'timer sessions persist and do not mark catalogue tracks checked',
    () async {
      await boot(LocalAllStats.empty());
      await manager.addAudioCompleted(
        LocalAudioCompleted(
          id: 'timer-600',
          timestamp: today.millisecondsSinceEpoch,
        ),
        600000,
      );
      final stored = await restart();
      expect(stored.totalTracksCompleted, 1);
      expect(stored.totalTimeListened, 600000);
      expect(stored.audioCompleted!.single.id, 'timer-600');
      expect(stored.streakCurrent, 1);
      expect(stored.tracksChecked, isEmpty);
    },
  );

  test(
    'deleting the final session persists an empty completion history',
    () async {
      final session = LocalAudioCompleted(
        id: 'manual2',
        timestamp: today.millisecondsSinceEpoch,
      );
      await boot(
        LocalAllStats.empty().copyWith(
          totalTracksCompleted: 1,
          audioCompleted: [session],
        ),
      );
      await manager.removeAudioCompleted(session);
      final stored = await restart();
      expect(stored.totalTracksCompleted, 0);
      expect(stored.audioCompleted, isEmpty);
      expect(stored.streakCurrent, 0);
    },
  );

  test(
    'checked tracks survive bulk edits with no completed sessions',
    () async {
      await boot(LocalAllStats.empty().copyWith(tracksChecked: ['old']));
      await manager.setTracksChecked(['ds-1', 'ds-2'], checked: true);
      await manager.removeTrackChecked('old');
      final stored = await restart();
      expect(stored.tracksChecked, ['ds-1', 'ds-2']);
      expect(stored.totalTracksCompleted, 0);
    },
  );

  test('cleared history stays empty after refreshing and restarting', () async {
    await boot(historyStats());
    await manager.sync();
    await manager.clearAllStats();
    await manager.sync(force: true);
    final stored = await restart();
    expect(stored.totalTracksCompleted, 0);
    expect(stored.audioCompleted, isEmpty);
  });
}
