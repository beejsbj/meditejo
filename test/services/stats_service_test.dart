import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/services/stats_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/stats_preferences_store.dart';

void main() {
  late SharedPreferences prefs;
  late StatsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = StatsService(prefs: prefs);
  });

  test('a new device has empty stats without an account', () async {
    final stats = await service.loadStats();
    expect(stats.totalTracksCompleted, 0);
    expect(stats.audioCompleted, isEmpty);
  });

  test(
    'saves and reloads all practice data using the existing local key',
    () async {
      final stats = LocalAllStats.empty().copyWith(
        streakCurrent: 2,
        streakLongest: 12,
        totalTracksCompleted: 80,
        totalTimeListened: 1234000,
        tracksChecked: ['lib-course-session'],
        audioCompleted: [
          LocalAudioCompleted(id: 'timer-600', timestamp: 1792065600000),
        ],
        freezeUsageDates: [1791979200000],
        consistencyScore: 0.7,
      );

      await service.saveStats(stats);
      final restored = await StatsService(prefs: prefs).loadStats();

      expect(jsonEncode(restored.toJson()), jsonEncode(stats.toJson()));
      final persisted = jsonDecode(
        prefs.getString(SharedPreferenceConstants.localAllStatsKey)!,
      );
      expect(persisted['totalTracksCompleted'], 80);
      expect(prefs.getKeys(), {SharedPreferenceConstants.localAllStatsKey});
    },
  );

  test(
    'persists checked tracks before any session has been completed',
    () async {
      await service.saveStats(
        LocalAllStats.empty().copyWith(tracksChecked: ['ds-123']),
      );
      expect((await service.loadStats()).tracksChecked, ['ds-123']);
    },
  );

  test('empty history replaces a previously completed session', () async {
    await service.saveStats(
      LocalAllStats.empty().copyWith(totalTracksCompleted: 1),
    );
    await service.saveStats(LocalAllStats.empty());
    expect((await service.loadStats()).totalTracksCompleted, 0);
  });

  test(
    'clear removes practice history and preserves other preferences',
    () async {
      await prefs.setString('themePreference', 'dark');
      await service.saveStats(LocalAllStats.empty());
      await service.clearStats();
      expect(
        prefs.getString(SharedPreferenceConstants.localAllStatsKey),
        isNull,
      );
      expect(prefs.getString('themePreference'), 'dark');
      expect((await service.loadStats()).audioCompleted, isEmpty);
    },
  );

  test('unreadable history is reported without replacing it', () async {
    await prefs.setString(SharedPreferenceConstants.localAllStatsKey, '{bad');
    await expectLater(service.loadStats(), throwsFormatException);
    expect(prefs.getString(SharedPreferenceConstants.localAllStatsKey), '{bad');
  });

  test(
    'legacy JSON without receipts loads with an empty receipt list',
    () async {
      final json = LocalAllStats.empty().toJson()..remove('completionReceipts');
      await prefs.setString(
        SharedPreferenceConstants.localAllStatsKey,
        jsonEncode(json),
      );
      expect((await service.loadStats()).completionReceipts, isEmpty);
    },
  );

  test(
    'receipt identities survive normal generated JSON serialization',
    () async {
      final receipts = [
        jsonEncode(['completion', 'track@one', 1792065600000]),
        jsonEncode(['repeat', 'track@one', 1792065600000]),
      ];
      await service.saveStats(
        LocalAllStats.empty().copyWith(completionReceipts: receipts),
      );
      final restored = await service.loadStats();
      expect(restored.completionReceipts, receipts);
      expect(
        jsonDecode(
          prefs.getString(SharedPreferenceConstants.localAllStatsKey)!,
        )['completionReceipts'],
        receipts,
      );
    },
  );

  test(
    'rejected clear reloads the original history into the preferences cache',
    () async {
      final original = jsonEncode(
        LocalAllStats.empty().copyWith(totalTracksCompleted: 5).toJson(),
      );
      final store = StatsPreferencesStore.install({
        SharedPreferenceConstants.localAllStatsKey: original,
      });
      prefs = await SharedPreferences.getInstance();
      service = StatsService(prefs: prefs);
      store.onRemove = (_, _) async => false;
      await expectLater(service.clearStats(), throwsStateError);
      expect(
        prefs.getString(SharedPreferenceConstants.localAllStatsKey),
        original,
      );
      expect((await service.loadStats()).totalTracksCompleted, 5);
    },
  );
}
