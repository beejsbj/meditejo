import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/services/stats/practice_summary.dart';

import '../../helpers/stats_fixtures.dart';

final _now = fixtureNow;
final _entry = fixtureEntry;
LocalAllStats _history() => fixtureStats();

void main() {
  final summary = PracticeSummary.from(_history(), now: _now);
  Duration m(int minutes) => Duration(minutes: minutes);

  test('today, this week (from Monday), this month and all time', () {
    expect(summary.today, m(70));
    // Monday 19th to today: Tuesday's 20 and today's 70. Sunday is last week.
    expect(summary.thisWeek, m(90));
    expect(summary.thisMonth, m(135));
    // The running total the history has always kept, legacy sessions included.
    expect(summary.allTime, m(200));
  });

  test('the Practice / Talks split counts recorded lengths only', () {
    // timer 10 + guided 20 + by hand 30 + the old timer's 5, read from its id.
    expect(summary.practiceTime, m(65));
    // the talk 60 + the YouTube single 15.
    expect(summary.talksTime, m(75));
    expect(summary.otherTime, Duration.zero);
    expect(summary.recordedTime, m(140));
  });

  test('ranks courses and sources by time', () {
    expect(
      [for (final s in summary.sources) (s.source, s.courseTitle, s.time)],
      [
        (PracticeSource.course, 'Practising the Jhānas', m(60)),
        (PracticeSource.addedByHand, null, m(30)),
        (PracticeSource.course, 'Metta', m(20)),
        // 15 minutes each: the tie breaks by name.
        (PracticeSource.timer, null, m(15)),
        (PracticeSource.youtube, null, m(15)),
      ],
    );
    expect(summary.sources.first.sessions, 1);
    expect(summary.sources[3].sessions, 2); // both timers
  });

  test('a session with no recorded length is a day, not minutes', () {
    expect(summary.untimedSessions, 1);
    expect(summary.sessions, 7);
    expect(summary.daysPractised, contains(DateTime(2026, 9, 28)));
    expect(summary.firstDay, DateTime(2026, 9, 28));
  });

  test('the chart has the last 30 days, oldest first, ending today', () {
    expect(summary.days, hasLength(30));
    expect(summary.days.first.day, DateTime(2026, 9, 22));
    expect(summary.days.last.day, DateTime(2026, 10, 21));
    expect(summary.days.last.time, m(70));
    final week = summary.lastDays(7);
    expect(week, hasLength(7));
    expect(week.first.day, DateTime(2026, 10, 15));
    expect(week.fold(Duration.zero, (a, d) => a + d.time), m(120));
    expect(summary.days.first.practised, isFalse);
    // 28 September: practised, with only the old timer's 5 minutes.
    final sep28 = summary.days.firstWhere((d) => d.day.day == 28);
    expect(sep28.practised, isTrue);
    expect(sep28.time, m(5));
  });

  test('days practised, this week, over the last 30 days, and by month', () {
    expect(summary.practisedThisWeek, 2);
    expect(summary.practisedLast30, 5);
    expect(summary.practisedIn(DateTime(2026, 10)), 4);
    expect(summary.practisedIn(DateTime(2026, 9)), 1);
  });

  test('keeps the streak the history holds', () {
    expect(summary.streakCurrent, 2);
    expect(summary.streakLongest, 9);
  });

  test('an empty history is empty, not an error', () {
    final empty = PracticeSummary.from(LocalAllStats.empty(), now: _now);
    expect(empty.isEmpty, isTrue);
    expect(empty.today, Duration.zero);
    expect(empty.sources, isEmpty);
    expect(empty.days, hasLength(30));
    expect(empty.firstDay, isNull);
  });

  test('a session dated after today is not counted', () {
    final stats = _history().copyWith(
      audioCompleted: [
        ..._history().audioCompleted!,
        _entry('ds-talk-1', DateTime(2026, 10, 22, 8), minutes: 99),
      ],
    );
    final s = PracticeSummary.from(stats, now: _now);
    expect(s.today, m(70));
    expect(s.sessions, 7);
  });

  test('the day starts at the user\'s boundary', () {
    final stats = LocalAllStats.empty().copyWith(
      audioCompleted: [
        // 02:00 on the 21st belongs to the 20th with a 4 a.m. day start.
        _entry('timer-1200', DateTime(2026, 10, 21, 2), minutes: 20),
        _entry('timer-600', DateTime(2026, 10, 21, 9), minutes: 10),
      ],
    );
    final s = PracticeSummary.from(
      stats,
      now: _now,
      dayOffset: const Duration(hours: 4),
    );
    expect(s.today, m(10));
    expect(s.days[s.days.length - 2].time, m(20));
    expect(s.daysPractised, {DateTime(2026, 10, 20), DateTime(2026, 10, 21)});
  });

  test('the week starts on Monday', () {
    // Monday 19th itself: the week is just today.
    final monday = PracticeSummary.from(
      _history(),
      now: DateTime(2026, 10, 19, 23),
    );
    expect(monday.thisWeek, Duration.zero);
    // Sunday the 18th is the last day of the week that began on the 12th.
    final sunday = PracticeSummary.from(
      _history(),
      now: DateTime(2026, 10, 18, 23),
    );
    expect(sunday.thisWeek, m(30));
    expect(sunday.today, m(30));
  });

  test(
    'a kind the entry does not carry is read from timers and manual ones',
    () {
      expect(
        PracticeSummary.kindOf(_entry('timer-60', _now)),
        LocalAudioCompleted.kindPractice,
      );
      expect(
        PracticeSummary.kindOf(_entry('manual4', _now)),
        LocalAudioCompleted.kindPractice,
      );
      expect(PracticeSummary.kindOf(_entry('ds-talk-5', _now)), isNull);
    },
  );
}
