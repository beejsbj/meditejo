import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/services/stats/practice_summary.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:medito/utils/stats_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Each session keeps both numbers: the recording's length (audio covered)
/// and the real time it took at the speed it was played at. History from
/// before real time was recorded is left as it was and reads as its length.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 9, 14);
  final manager = StatsManager();
  const hour = 3600000;

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

  tearDown(() {
    healthSyncOverride = null;
    manager.resetForTesting();
  });

  test('a talk at 2x records an hour of audio and half an hour of real time, '
      'and both survive a restart', () async {
    await boot();
    await manager.addAudioCompleted(
      LocalAudioCompleted(
        id: 'ds-talk-1',
        timestamp: now.millisecondsSinceEpoch,
      ),
      hour,
      realDuration: hour ~/ 2,
      kind: 'talks',
    );
    final stored = await restart();
    final entry = stored.audioCompleted!.single;
    expect(entry.durationMs, hour);
    expect(entry.realMs, hour ~/ 2);
    expect(entry.realOrDurationMs, hour ~/ 2);
    // The running total stays in recording lengths, as it always was.
    expect(stored.totalTimeListened, hour);
  });

  test('a timer keeps no separate real time: it is never sped up', () async {
    await boot();
    await manager.addAudioCompleted(
      LocalAudioCompleted(
        id: 'timer-1200',
        timestamp: now.millisecondsSinceEpoch,
      ),
      1200000,
      realDuration: 600000,
    );
    final entry = (await restart()).audioCompleted!.single;
    expect(entry.realMs, isNull);
    expect(entry.realOrDurationMs, 1200000);
  });

  test('a session with no measured real time reads as its length', () async {
    await boot();
    await manager.addAudioCompleted(
      LocalAudioCompleted(id: 'lib-x', timestamp: now.millisecondsSinceEpoch),
      600000,
    );
    final entry = (await restart()).audioCompleted!.single;
    expect(entry.realMs, isNull);
    expect(entry.realOrDurationMs, 600000);
  });

  test(
    'history from before real time was recorded is read, not rewritten',
    () async {
      final old = LocalAudioCompleted.fromJson({
        'timestamp': now.millisecondsSinceEpoch,
        'id': 'ds-talk-0',
        'durationMs': hour,
        'kind': 'talks',
      });
      expect(old.realMs, isNull);
      expect(old.realOrDurationMs, hour);
      await boot(
        LocalAllStats.empty().copyWith(
          totalTimeListened: hour,
          totalTracksCompleted: 1,
          audioCompleted: [old],
        ),
      );
      await manager.addAudioCompleted(
        LocalAudioCompleted(
          id: 'ds-talk-1',
          timestamp: now.millisecondsSinceEpoch + 1,
        ),
        hour,
        realDuration: hour ~/ 2,
      );
      final stored = await restart();
      expect(stored.audioCompleted!.first.realMs, isNull);
      expect(stored.audioCompleted!.first.durationMs, hour);
    },
  );

  test('midnight is judged by the real time a session ran', () async {
    // Ended at 00:30 after 20 real minutes (a 40-minute talk at 2x): it
    // started at 00:10, today. By its recording's length it would have
    // started yesterday.
    await boot();
    final end = DateTime(2026, 11, 9, 0, 30);
    await manager.addAudioCompleted(
      LocalAudioCompleted(
        id: 'ds-talk-2',
        timestamp: end.millisecondsSinceEpoch,
      ),
      40 * 60000,
      realDuration: 20 * 60000,
    );
    expect(
      (await restart()).audioCompleted!.single.timestamp,
      end.millisecondsSinceEpoch,
    );

    // One that did start yesterday is moved back by its real time.
    await boot();
    final late = DateTime(2026, 11, 9, 0, 20);
    await manager.addAudioCompleted(
      LocalAudioCompleted(
        id: 'ds-talk-3',
        timestamp: late.millisecondsSinceEpoch,
      ),
      80 * 60000,
      realDuration: 40 * 60000,
    );
    expect(
      (await restart()).audioCompleted!.single.timestamp,
      late.subtract(const Duration(minutes: 40)).millisecondsSinceEpoch,
    );
  });

  test('a repeat adds its real time to the session it repeats', () async {
    await boot();
    final first = LocalAudioCompleted(
      id: 'lib-track-a',
      timestamp: now.millisecondsSinceEpoch,
    );
    await manager.addAudioCompleted(first, 600000, realDuration: 400000);
    await manager.addRepeatListeningTime(
      600000,
      realDuration: 400000,
      trackId: 'lib-track-a',
    );
    // A repeat replayed from before real time was saved: its length.
    await manager.addRepeatListeningTime(600000, trackId: 'lib-track-a');
    final entry = (await restart()).audioCompleted!.single;
    expect(entry.durationMs, 1800000);
    expect(entry.realMs, 1400000);
  });

  test(
    'a sped-up repeat of a session with no real time starts from its length',
    () async {
      await boot();
      await manager.addAudioCompleted(
        LocalAudioCompleted(id: 'lib-b', timestamp: now.millisecondsSinceEpoch),
        600000,
      );
      await manager.addRepeatListeningTime(600000, trackId: 'lib-b');
      expect((await restart()).audioCompleted!.single.realMs, isNull);
      await manager.addRepeatListeningTime(
        600000,
        realDuration: 300000,
        trackId: 'lib-b',
      );
      final entry = (await restart()).audioCompleted!.single;
      expect(entry.durationMs, 1800000);
      expect(entry.realMs, 1500000);
    },
  );

  test('deleting a sped-up session takes back both its audio and its real '
      'time', () async {
    await boot();
    final talk = LocalAudioCompleted(
      id: 'ds-talk-1',
      timestamp: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
    );
    final sit = LocalAudioCompleted(
      id: 'lib-sit',
      timestamp: now.millisecondsSinceEpoch,
    );
    // An hour-long talk heard at 2x, then a 20-minute sit at 1x.
    await manager.addAudioCompleted(talk, hour, realDuration: hour ~/ 2);
    await manager.addAudioCompleted(sit, 20 * 60000, realDuration: 20 * 60000);

    PracticeSummary summary(LocalAllStats stats) =>
        PracticeSummary.from(stats, now: now);
    final before = summary(await restart());
    expect(before.allTimeAudio, const Duration(minutes: 80));
    expect(before.allTime, const Duration(minutes: 50));
    expect(before.audioDiffers, isTrue);

    await manager.removeAudioCompleted(talk);
    final stored = await restart();
    expect(stored.totalTimeListened, 20 * 60000);
    final after = summary(stored);
    // Its 60 minutes of audio and its 30 of real time are both gone.
    expect(after.allTimeAudio, const Duration(minutes: 20));
    expect(after.allTime, const Duration(minutes: 20));
    expect(after.today, const Duration(minutes: 20));
    expect(after.audioDiffers, isFalse);
  });

  group('a completion payload', () {
    Map<String, dynamic> payload({int? real}) => {
      TypeConstants.trackIdKey: 'ds-talk-7',
      TypeConstants.timestampIdKey: now.millisecondsSinceEpoch,
      TypeConstants.durationIdKey: hour,
      TypeConstants.realDurationIdKey: ?real,
    };

    test('carries real time to the history and to Health', () async {
      await boot();
      final synced = <Map<String, dynamic>>[];
      healthSyncOverride = (p) async => synced.add(p);
      expect(await handleStats(payload(real: hour ~/ 2)), isTrue);
      final entry = (await restart()).audioCompleted!.single;
      expect(entry.durationMs, hour);
      expect(entry.realMs, hour ~/ 2);
      // Health is given the real half hour, ending when it was recorded.
      final interval = healthIntervalOf(synced.single);
      expect(interval.end, now);
      expect(interval.start, now.subtract(const Duration(minutes: 30)));
    });

    test('saved before real time existed replays as its length', () async {
      await boot();
      healthSyncOverride = (_) async {};
      expect(await handleStats(payload()), isTrue);
      final entry = (await restart()).audioCompleted!.single;
      expect(entry.realMs, isNull);
      expect(entry.realOrDurationMs, hour);
      expect(
        healthIntervalOf(payload()).start,
        now.subtract(const Duration(hours: 1)),
      );
    });
  });
}
