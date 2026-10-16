import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;
  final manager = StatsManager();
  final today = DateTime(2026, 10, 15, 12);

  setUp(() {
    manager.resetForTesting();
    manager.setCurrentDateForTesting(today);
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    manager.resetForTesting();
  });

  test('build returns empty stats without any account setup', () async {
    final stats = await container.read(statsProvider.future);
    expect(stats.totalTracksCompleted, 0);
    expect(stats.audioCompleted, isEmpty);
  });

  test('build loads persisted history and recalculates its streak', () async {
    final history = LocalAllStats.empty().copyWith(
      streakCurrent: 99,
      streakLongest: 99,
      totalTracksCompleted: 10,
      audioCompleted: [
        LocalAudioCompleted(
          id: 'lib-session',
          timestamp: today.millisecondsSinceEpoch,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      SharedPreferenceConstants.localAllStatsKey: jsonEncode(history.toJson()),
    });

    final stats = await container.read(statsProvider.future);
    expect(stats.streakCurrent, 1);
    expect(stats.streakLongest, 99);
    expect(stats.totalTracksCompleted, 10);
  });

  test(
    'refreshFromLocal includes a completion and a subsequent day change',
    () async {
      await container.read(statsProvider.future);
      await manager.addAudioCompleted(
        LocalAudioCompleted(
          id: 'timer-600',
          timestamp: today.millisecondsSinceEpoch,
        ),
        600000,
      );
      final notifier = container.read(statsProvider.notifier);
      await notifier.refreshFromLocal();
      expect(container.read(statsProvider).value!.totalTracksCompleted, 1);
      expect(container.read(statsProvider).value!.streakCurrent, 1);

      manager.setCurrentDateForTesting(today.add(const Duration(days: 2)));
      await notifier.refreshFromLocal();
      expect(container.read(statsProvider).value!.streakCurrent, 0);
      expect(container.read(statsProvider).value!.totalTracksCompleted, 1);
    },
  );
}
