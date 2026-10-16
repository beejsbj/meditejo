import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:medito/utils/stats_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/stats_preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manager = StatsManager();
  final now = DateTime(2026, 10, 15, 12);
  const statsKey = SharedPreferenceConstants.localAllStatsKey;
  late SharedPreferences prefs;
  late StatsPreferencesStore store;

  Map<String, dynamic> payload({
    String id = 'new',
    int? end,
    int duration = 600000,
  }) => {
    TypeConstants.trackIdKey: id,
    TypeConstants.timestampIdKey: end ?? now.millisecondsSinceEpoch,
    TypeConstants.durationIdKey: duration,
  };

  Future<void> restart() async {
    manager.resetForTesting();
    manager.setCurrentDateForTesting(now);
    await prefs.reload();
  }

  setUp(() async {
    manager.resetForTesting();
    manager.setCurrentDateForTesting(now);
    store = StatsPreferencesStore.install({});
    prefs = await SharedPreferences.getInstance();
    healthSyncOverride = (_) async {};
  });

  tearDown(() {
    healthSyncOverride = null;
    manager.resetForTesting();
  });

  test(
    'normal completion survives restart and replays exactly once across midnight',
    () async {
      final event = payload(
        end: DateTime(2026, 10, 15, 0, 3).millisecondsSinceEpoch,
      );
      expect(await handleStats(event), isTrue);
      await restart();
      expect(await handleStats(event), isTrue);
      final stats = await manager.localAllStats;
      expect(stats.totalTracksCompleted, 1);
      expect(stats.totalTimeListened, 600000);
      expect(
        stats.audioCompleted!.single.timestamp,
        DateTime(2026, 10, 14, 23, 53).millisecondsSinceEpoch,
      );
      expect(stats.completionReceipts, [
        jsonEncode(['completion', 'new', event[TypeConstants.timestampIdKey]]),
      ]);
    },
  );

  test(
    'repeated play-throughs persist distinct receipts without new sessions',
    () async {
      final event = payload();
      expect(await handleStats(event), isTrue);
      // Even identical track/timestamp values cannot collide across event kinds.
      expect(await handleRepeatPlaythrough(event), isTrue);
      await restart();
      expect(await handleRepeatPlaythrough(event), isTrue);
      final next = payload(end: now.millisecondsSinceEpoch + 600000);
      expect(await handleRepeatPlaythrough(next), isTrue);
      await restart();
      expect(await handleStats(event), isTrue);
      expect(await handleRepeatPlaythrough(next), isTrue);
      final stats = await manager.localAllStats;
      expect(stats.totalTracksCompleted, 1);
      expect(stats.audioCompleted, hasLength(1));
      expect(stats.totalTimeListened, 1800000);
      expect(stats.completionReceipts, hasLength(3));
    },
  );

  test(
    'legacy history gains a receipt without duplicating its normalized session',
    () async {
      final end = DateTime(2026, 10, 15, 0, 3).millisecondsSinceEpoch;
      final legacy =
          LocalAllStats.empty()
              .copyWith(
                totalTracksCompleted: 12,
                totalTimeListened: 9000000,
                tracksChecked: ['old', 'new'],
                audioCompleted: [
                  LocalAudioCompleted(id: 'new', timestamp: end - 600000),
                ],
              )
              .toJson()
            ..remove('completionReceipts');
      await prefs.setString(statsKey, jsonEncode(legacy));
      expect(await handleStats(payload(end: end)), isTrue);
      await restart();
      final stats = await manager.localAllStats;
      expect(stats.totalTracksCompleted, 12);
      expect(stats.totalTimeListened, 9000000);
      expect(stats.completionReceipts, hasLength(1));
      expect(stats.tracksChecked, ['old', 'new']);
    },
  );

  test(
    'deleting the final session retains its receipt against native replay',
    () async {
      final event = payload();
      await handleStats(event);
      final session = (await manager.localAllStats).audioCompleted!.single;
      await manager.removeAudioCompleted(session);
      await restart();
      expect(await handleStats(event), isTrue);
      final stats = await manager.localAllStats;
      expect(stats.audioCompleted, isEmpty);
      expect(stats.totalTracksCompleted, 0);
      expect(stats.completionReceipts, hasLength(1));
    },
  );

  for (final repeat in [false, true]) {
    test(
      '${repeat ? 'repeat' : 'normal'} callbacks join a failed write and retry without inflation',
      () async {
        final original = LocalAllStats.empty().copyWith(
          totalTracksCompleted: 7,
          totalTimeListened: 7000000,
          tracksChecked: ['old'],
        );
        final encoded = jsonEncode(original.toJson());
        await prefs.setString(statsKey, encoded);
        final started = Completer<void>();
        final release = Completer<void>();
        store.onWrite = (key, value, persist) async {
          if (key == 'flutter.$statsKey') {
            started.complete();
            await release.future;
            return false;
          }
          return persist();
        };
        final event = payload();
        final record = repeat ? handleRepeatPlaythrough : handleStats;
        final first = record(event);
        await started.future;
        final duplicate = record(event);
        expect(identical(first, duplicate), isTrue);
        release.complete();
        expect(await Future.wait([first, duplicate]), [false, false]);
        expect(prefs.getString(statsKey), encoded);
        expect(manager.currentStats!.tracksChecked, ['old']);
        expect(manager.currentStats!.completionReceipts, isEmpty);
        expect(manager.currentStats!.totalTimeListened, 7000000);
        expect((await store.getAll())['flutter.$statsKey'], encoded);

        store.onWrite = null;
        expect(await record(event), isTrue);
        await restart();
        expect(await record(event), isTrue);
        final stats = await manager.localAllStats;
        expect(stats.totalTracksCompleted, repeat ? 7 : 8);
        expect(stats.totalTimeListened, 7600000);
        expect(stats.completionReceipts, hasLength(1));
      },
    );
  }

  test(
    'commit followed by platform error reloads its receipt before retry',
    () async {
      var firstWrite = true;
      store.onWrite = (key, value, persist) async {
        final result = await persist();
        if (key == 'flutter.$statsKey' && firstWrite) {
          firstWrite = false;
          throw StateError('Reply lost after commit');
        }
        return result;
      };
      expect(await handleStats(payload()), isFalse);
      expect(await handleStats(payload()), isTrue);
      await restart();
      final stats = await manager.localAllStats;
      expect(stats.totalTracksCompleted, 1);
      expect(stats.totalTimeListened, 600000);
      expect(stats.completionReceipts, hasLength(1));
    },
  );

  test(
    'a failed write and reload block unsafe cached retries until disk recovers',
    () async {
      final original = jsonEncode(LocalAllStats.empty().toJson());
      await prefs.setString(statsKey, original);
      var attemptedWrites = 0;
      store.onWrite = (key, value, persist) async {
        if (key != 'flutter.$statsKey') return persist();
        attemptedWrites++;
        store.failReads = true;
        return false;
      };
      expect(await handleStats(payload()), isFalse);
      expect(await handleStats(payload()), isFalse);
      expect(attemptedWrites, 1);
      expect(manager.currentStats, isNull);
      store.failReads = false;
      store.onWrite = null;
      expect(await handleStats(payload()), isTrue);
      await restart();
      expect((await manager.localAllStats).totalTracksCompleted, 1);
    },
  );

  test(
    'checked edits and refresh wait behind an in-flight completion save',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var blocked = false;
      store.onWrite = (key, value, persist) async {
        if (key == 'flutter.$statsKey' && !blocked) {
          blocked = true;
          started.complete();
          await release.future;
        }
        return persist();
      };
      final completion = handleStats(payload());
      await started.future;
      final edit = manager.addTrackChecked('other');
      final refresh = manager.sync();
      release.complete();
      await Future.wait<dynamic>([completion, edit, refresh]);
      await restart();
      final stats = await manager.localAllStats;
      expect(stats.totalTracksCompleted, 1);
      expect(stats.totalTimeListened, 600000);
      expect(stats.tracksChecked, containsAll(['new', 'other']));
      expect(stats.completionReceipts, hasLength(1));
    },
  );

  test('repeat listening time is durable before waiting for Health', () async {
    final enteredHealth = Completer<void>();
    final releaseHealth = Completer<void>();
    healthSyncOverride = (_) async {
      enteredHealth.complete();
      await releaseHealth.future;
    };
    final pending = handleRepeatPlaythrough(payload());
    await enteredHealth.future;
    final stored = LocalAllStats.fromJson(
      jsonDecode(prefs.getString(statsKey)!),
    );
    expect(stored.totalTimeListened, 600000);
    expect(stored.completionReceipts, hasLength(1));
    final duplicate = handleRepeatPlaythrough(payload());
    expect(identical(pending, duplicate), isTrue);
    releaseHealth.complete();
    expect(await Future.wait([pending, duplicate]), [true, true]);
  });

  test('failed checked-track edits do not mutate the committed list', () async {
    await manager.addTrackChecked('old');
    store.onWrite = (key, value, persist) async {
      if (key == 'flutter.$statsKey') return false;
      return persist();
    };
    await expectLater(
      manager.setTracksChecked(['new'], checked: true),
      throwsStateError,
    );
    expect((await manager.localAllStats).tracksChecked, ['old']);
    await expectLater(manager.removeTrackChecked('old'), throwsStateError);
    expect((await manager.localAllStats).tracksChecked, ['old']);
    store.onWrite = null;
    await manager.addTrackChecked('good');
    await restart();
    expect((await manager.localAllStats).tracksChecked, ['old', 'good']);
  });

  test('explicit clear can discard unreadable history', () async {
    await prefs.setString(statsKey, '{bad');
    await manager.clearAllStats();
    await restart();
    expect((await manager.localAllStats).totalTracksCompleted, 0);
  });
}
