import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/services/stats/practice_summary.dart';
import 'package:medito/services/stats/real_time.dart';

import '../../helpers/stats_fixtures.dart';

Duration _m(int minutes) => Duration(minutes: minutes);

LocalAudioCompleted _entry(
  String id,
  DateTime at, {
  required int minutes,
  int? realMinutes,
  String? kind,
}) => LocalAudioCompleted(
  id: id,
  timestamp: at.millisecondsSinceEpoch,
  durationMs: minutes * minuteMs,
  realMs: realMinutes == null ? null : realMinutes * minuteMs,
  kind: kind,
);

void main() {
  group('the audio line shows only when the two differ enough', () {
    bool differs(Duration audio, Duration real) =>
        audioDiffersFromRealTime(audio: audio, real: real);

    test('the same, or within a minute, stays quiet', () {
      expect(differs(_m(60), _m(60)), isFalse);
      expect(differs(_m(10), const Duration(minutes: 9, seconds: 1)), isFalse);
    });

    test('a minute or more AND 5% or more shows it', () {
      expect(differs(_m(20), _m(19)), isTrue); // 1 min, 5.3%
      expect(differs(_m(60), _m(30)), isTrue); // a talk at 2x
      // Slowed down: more of your time than audio.
      expect(differs(_m(60), _m(100)), isTrue);
    });

    test('a minute that is under 5% of the time stays quiet', () {
      // Ten hours, one talk nudged a little faster: 4 minutes, 0.7%.
      expect(differs(_m(604), _m(600)), isFalse);
      expect(differs(_m(630), _m(600)), isTrue); // exactly 5%
      expect(differs(_m(629), _m(600)), isFalse);
    });

    test('no time spent at all but audio covered shows it', () {
      expect(differs(_m(5), Duration.zero), isTrue);
      expect(differs(Duration.zero, Duration.zero), isFalse);
    });
  });

  group('the summary counts real time', () {
    final now = fixtureNow;
    final today = DateTime(now.year, now.month, now.day, 8);

    LocalAllStats stats(List<LocalAudioCompleted> entries, {int? total}) =>
        LocalAllStats.empty().copyWith(
          audioCompleted: entries,
          totalTimeListened:
              total ?? entries.fold<int>(0, (s, e) => s + e.durationMs!),
          updated: 1,
        );

    test('today, the week, the kinds and the courses are real time', () {
      final summary = PracticeSummary.from(
        stats([
          _entry(
            'ds-talk-1',
            today,
            minutes: 60,
            realMinutes: 30,
            kind: 'talks',
          ),
          _entry('timer-1200', today, minutes: 20),
        ]),
        now: now,
      );
      expect(summary.today, _m(50));
      expect(summary.thisWeek, _m(50));
      expect(summary.talksTime, _m(30));
      expect(summary.practiceTime, _m(20));
      expect(summary.days.last.time, _m(50));
      expect(summary.allTime, _m(50));
      expect(summary.allTimeAudio, _m(80));
      expect(summary.audioDiffers, isTrue);
    });

    test('older entries with no real time count as their length', () {
      final summary = PracticeSummary.from(
        stats([
          _entry('ds-talk-0', today, minutes: 60, kind: 'talks'),
          _entry('lib-x', today, minutes: 20),
        ]),
        now: now,
      );
      expect(summary.today, _m(80));
      expect(summary.allTime, _m(80));
      expect(summary.allTimeAudio, _m(80));
      expect(summary.audioDiffers, isFalse);
    });

    test('all time keeps the minutes of sessions with no recorded length', () {
      // 100 minutes of total, 40 of them from sessions that recorded no
      // length: they stay in both totals, as real time = audio for them.
      final summary = PracticeSummary.from(
        stats([
          _entry('ds-talk-1', today, minutes: 60, realMinutes: 30),
          LocalAudioCompleted(
            id: 'old',
            timestamp: today.millisecondsSinceEpoch,
          ),
        ], total: 100 * minuteMs),
        now: now,
      );
      expect(summary.allTimeAudio, _m(100));
      expect(summary.allTime, _m(70));
    });

    test('slowed-down practice is more of your time than audio', () {
      final summary = PracticeSummary.from(
        stats([_entry('lib-sit', today, minutes: 30, realMinutes: 50)]),
        now: now,
      );
      expect(summary.allTime, _m(50));
      expect(summary.allTimeAudio, _m(30));
      expect(summary.audioDiffers, isTrue);
    });
  });
}
