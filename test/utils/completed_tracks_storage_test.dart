import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/services/stats_service.dart';
import 'package:medito/utils/completed_tracks_storage.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:medito/utils/stats_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/stats_preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late StatsPreferencesStore store;
  late CompletedTracksStorage storage;
  final now = DateTime(2026, 10, 15, 12);
  const queueKey = CompletedTracksStorage.completedTracksKey;

  Map<String, dynamic> payload(String id) => {
    TypeConstants.trackIdKey: id,
    TypeConstants.timestampIdKey: now.millisecondsSinceEpoch,
    TypeConstants.durationIdKey: 600000,
  };

  setUp(() async {
    StatsManager().resetForTesting();
    StatsManager().setCurrentDateForTesting(now);
    store = StatsPreferencesStore.install({});
    prefs = await SharedPreferences.getInstance();
    storage = CompletedTracksStorage(prefs);
    healthSyncOverride = (_) async {};
  });

  tearDown(() {
    healthSyncOverride = null;
    StatsManager().resetForTesting();
  });

  test(
    'overlapping enqueues from different instances preserve both entries',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var blocked = false;
      store.onWrite = (key, value, persist) async {
        if (key == 'flutter.$queueKey' && !blocked) {
          blocked = true;
          entered.complete();
          await release.future;
        }
        return persist();
      };
      final first = storage.addCompletedTrack(payload('first'));
      await entered.future;
      final second = CompletedTracksStorage(
        prefs,
      ).addCompletedTrack(payload('second'));
      release.complete();
      await Future.wait([first, second]);
      await prefs.reload();
      expect(storage.getPendingTracks(), [
        jsonEncode(payload('first')),
        jsonEncode(payload('second')),
      ]);
    },
  );

  test(
    'drain removes only its successes and preserves enqueues during awaits',
    () async {
      await storage.addCompletedTrack(payload('first'));
      // Unreadable pending entries must remain available for recovery.
      await prefs.setStringList(queueKey, [
        ...storage.getPendingTracks(),
        '{bad',
      ]);
      final entered = Completer<void>();
      final release = Completer<void>();
      healthSyncOverride = (_) async {
        entered.complete();
        await release.future;
      };
      final draining = processPendingCompletedTracks(prefs);
      await entered.future;
      await CompletedTracksStorage(prefs).addCompletedTrack(payload('new'));
      release.complete();
      expect(await draining, 1);
      await prefs.reload();
      expect(storage.getPendingTracks(), ['{bad', jsonEncode(payload('new'))]);
      expect((await StatsManager().localAllStats).totalTracksCompleted, 1);
    },
  );

  test(
    'failed acknowledgement keeps pending entries and receipt prevents recount',
    () async {
      await storage.addCompletedTrack(payload('first'));
      store.onWrite = (key, value, persist) async {
        if (key == 'flutter.$queueKey') return false;
        return persist();
      };
      expect(await processPendingCompletedTracks(prefs), 0);
      expect(storage.getPendingTracks(), [jsonEncode(payload('first'))]);
      expect((await StatsManager().localAllStats).totalTracksCompleted, 1);
      store.onWrite = null;
      StatsManager().resetForTesting();
      expect(await processPendingCompletedTracks(prefs), 1);
      expect(storage.getPendingTracks(), isEmpty);
      expect((await StatsManager().localAllStats).totalTracksCompleted, 1);
    },
  );

  test(
    'failed enqueue restores original cache and propagates failure',
    () async {
      await storage.addCompletedTrack(payload('old'));
      final original = storage.getPendingTracks();
      store.onWrite = (key, value, persist) async {
        if (key == 'flutter.$queueKey') throw StateError('Disk write failed');
        return persist();
      };
      await expectLater(
        storage.addCompletedTrack(payload('failed')),
        throwsStateError,
      );
      expect(storage.getPendingTracks(), original);
      store.onWrite = null;
      await CompletedTracksStorage(prefs).addCompletedTrack(payload('new'));
      await prefs.reload();
      expect(storage.getPendingTracks(), [
        jsonEncode(payload('old')),
        jsonEncode(payload('new')),
      ]);
    },
  );

  test('acknowledgement removes only snapshot occurrences', () async {
    final event = payload('same');
    await storage.addCompletedTrack(event);
    final snapshot = await storage.loadPendingTracks();
    await storage.addCompletedTrack(event);
    await storage.removeCompletedTracks(snapshot);
    expect(storage.getPendingTracks(), [jsonEncode(event)]);
  });

  test(
    'failed history save cannot reload over an overlapping pending enqueue',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var queueWrites = 0;
      store.onWrite = (key, value, persist) async {
        if (key == 'flutter.${SharedPreferenceConstants.localAllStatsKey}') {
          entered.complete();
          await release.future;
          return false;
        }
        if (key == 'flutter.$queueKey') queueWrites++;
        return persist();
      };
      final save = StatsService(prefs: prefs).saveStats(LocalAllStats.empty());
      final failure = expectLater(save, throwsStateError);
      await entered.future;
      final enqueue = storage.addCompletedTrack(payload('new'));
      expect(queueWrites, 0);
      release.complete();
      await failure;
      await enqueue;
      expect(storage.getPendingTracks(), [jsonEncode(payload('new'))]);
      await prefs.reload();
      expect(storage.getPendingTracks(), [jsonEncode(payload('new'))]);
    },
  );
}
