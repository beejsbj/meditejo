import 'package:flutter/foundation.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/utils/day_boundary.dart';

/// Where a ranked slice of practice time came from, when it has no course.
enum PracticeSource {
  course,
  timer,
  addedByHand,
  dharmaSeed,
  youtube,
  imported,
  other,
}

/// Time spent on one course, or on one kind of source.
@immutable
class SourceTotal {
  const SourceTotal({
    required this.source,
    required this.time,
    required this.sessions,
    this.courseId,
    this.courseTitle,
  });

  final PracticeSource source;
  final Duration time;
  final int sessions;

  /// Set for [PracticeSource.course]; the title as recorded when it was sat.
  final String? courseId;
  final String? courseTitle;
}

/// One calendar day of the chart.
@immutable
class DayTotal {
  const DayTotal(this.day, this.time, {required this.practised});

  /// Local midnight of the day (the user's day boundary applied).
  final DateTime day;
  final Duration time;

  /// A session was recorded on this day, even one with no recorded length.
  final bool practised;
}

/// What the stats page shows, computed from the local history alone. Pure:
/// give it the history, the time and the user's day boundary, and it gives the
/// same answer, so it can be tested on fixed fixtures.
///
/// Minutes come from each entry's recorded length (`durationMs`, or a timer's
/// own length in its id). Entries from before lengths were recorded have none:
/// they count as days practised and towards the streak, never as minutes, and
/// [untimedSessions] says how many. [allTime] is the running total the history
/// has always kept, which does include them.
class PracticeSummary {
  PracticeSummary._({
    required this.today,
    required this.thisWeek,
    required this.thisMonth,
    required this.allTime,
    required this.days,
    required this.daysPractised,
    required this.timeByDay,
    required this.practiceTime,
    required this.talksTime,
    required this.otherTime,
    required this.sources,
    required this.untimedSessions,
    required this.sessions,
    required this.streakCurrent,
    required this.streakLongest,
    required this.practisedLast30,
    required this.practisedThisWeek,
    required this.firstDay,
  });

  /// How many days the chart can show.
  static const chartDays = 30;

  final Duration today;

  /// Monday to today.
  final Duration thisWeek;

  /// The first of the month to today.
  final Duration thisMonth;
  final Duration allTime;

  /// The last [chartDays] days, oldest first, ending today.
  final List<DayTotal> days;

  /// Every day with a session, for the calendar.
  final Set<DateTime> daysPractised;

  /// Recorded minutes on each day that has any, for the calendar's shading.
  final Map<DateTime, Duration> timeByDay;

  /// Time with a recorded length, by kind. [otherTime] is sessions whose kind
  /// is not known.
  final Duration practiceTime;
  final Duration talksTime;
  final Duration otherTime;

  /// Courses and sources by time, most first.
  final List<SourceTotal> sources;
  final int untimedSessions;
  final int sessions;
  final int streakCurrent;
  final int streakLongest;
  final int practisedLast30;
  final int practisedThisWeek;

  /// The first day with a session, or null for an empty history.
  final DateTime? firstDay;

  bool get isEmpty => sessions == 0 && allTime == Duration.zero;

  /// The last [count] days of [days] (7 or 30), oldest first.
  List<DayTotal> lastDays(int count) =>
      days.sublist((days.length - count).clamp(0, days.length));

  Duration get recordedTime => practiceTime + talksTime + otherTime;

  /// Days practised in the calendar month of [month].
  int practisedIn(DateTime month) => daysPractised
      .where((d) => d.year == month.year && d.month == month.month)
      .length;

  static Duration? lengthOf(LocalAudioCompleted entry) {
    final recorded = entry.durationMs;
    if (recorded != null) return Duration(milliseconds: recorded);
    // A timer sat before lengths were recorded kept its length in its id.
    return timerSessionDuration(entry.id);
  }

  static String? kindOf(LocalAudioCompleted entry) {
    final kind = entry.kind;
    if (kind == LocalAudioCompleted.kindPractice ||
        kind == LocalAudioCompleted.kindTalks) {
      return kind;
    }
    if (isTimerSessionId(entry.id) || _isManual(entry.id)) {
      return LocalAudioCompleted.kindPractice;
    }
    return null;
  }

  static bool _isManual(String id) =>
      id == 'manual1' || id == 'manual2' || id == 'manual3' || id == 'manual4';

  static PracticeSource _sourceOf(LocalAudioCompleted entry) {
    final id = entry.id;
    if (entry.courseId != null) return PracticeSource.course;
    if (isTimerSessionId(id)) return PracticeSource.timer;
    if (_isManual(id)) return PracticeSource.addedByHand;
    if (id.startsWith('ds-')) return PracticeSource.dharmaSeed;
    if (id.startsWith('yt-')) return PracticeSource.youtube;
    if (id.startsWith('lib-')) return PracticeSource.imported;
    return PracticeSource.other;
  }

  factory PracticeSummary.from(
    LocalAllStats stats, {
    required DateTime now,
    Duration dayOffset = Duration.zero,
  }) {
    final today = dayOf(now, dayOffset);
    DateTime back(int n) => DateTime(today.year, today.month, today.day - n);
    final weekStart = back(today.weekday - DateTime.monday);
    final monthStart = DateTime(today.year, today.month);
    final windowStart = back(chartDays - 1);

    final perDay = <DateTime, int>{};
    final practised = <DateTime>{};
    var todayMs = 0, weekMs = 0, monthMs = 0;
    var practiceMs = 0, talksMs = 0, otherMs = 0;
    var untimed = 0, sessions = 0;
    final groups = <String, _Group>{};

    for (final entry in stats.audioCompleted ?? const <LocalAudioCompleted>[]) {
      final day = dayOf(
        DateTime.fromMillisecondsSinceEpoch(entry.timestamp),
        dayOffset,
      );
      if (day.isAfter(today)) continue;
      practised.add(day);
      sessions++;

      final length = lengthOf(entry);
      if (length == null) {
        untimed++;
        continue;
      }
      final ms = length.inMilliseconds;
      perDay[day] = (perDay[day] ?? 0) + ms;
      if (day == today) todayMs += ms;
      if (!day.isBefore(weekStart)) weekMs += ms;
      if (!day.isBefore(monthStart)) monthMs += ms;

      switch (kindOf(entry)) {
        case LocalAudioCompleted.kindPractice:
          practiceMs += ms;
        case LocalAudioCompleted.kindTalks:
          talksMs += ms;
        default:
          otherMs += ms;
      }

      final source = _sourceOf(entry);
      final key = source == PracticeSource.course
          ? 'course:${entry.courseId}'
          : source.name;
      final group = groups.putIfAbsent(
        key,
        () => _Group(source, entry.courseId),
      );
      group.ms += ms;
      group.sessions++;
      // The newest title wins, in case the course was renamed.
      if (entry.courseTitle != null && entry.courseTitle!.isNotEmpty) {
        group.title = entry.courseTitle;
      }
    }

    final ranked =
        [
          for (final g in groups.values)
            SourceTotal(
              source: g.source,
              time: Duration(milliseconds: g.ms),
              sessions: g.sessions,
              courseId: g.courseId,
              courseTitle: g.title,
            ),
        ]..sort((a, b) {
          final byTime = b.time.compareTo(a.time);
          return byTime != 0
              ? byTime
              : (a.courseTitle ?? a.source.name).compareTo(
                  b.courseTitle ?? b.source.name,
                );
        });

    final chart = [
      for (var i = chartDays - 1; i >= 0; i--)
        DayTotal(
          back(i),
          Duration(milliseconds: perDay[back(i)] ?? 0),
          practised: practised.contains(back(i)),
        ),
    ];

    final sorted = practised.toList()..sort();
    return PracticeSummary._(
      today: Duration(milliseconds: todayMs),
      thisWeek: Duration(milliseconds: weekMs),
      thisMonth: Duration(milliseconds: monthMs),
      allTime: Duration(milliseconds: stats.totalTimeListened),
      days: chart,
      daysPractised: practised,
      timeByDay: {
        for (final e in perDay.entries) e.key: Duration(milliseconds: e.value),
      },
      practiceTime: Duration(milliseconds: practiceMs),
      talksTime: Duration(milliseconds: talksMs),
      otherTime: Duration(milliseconds: otherMs),
      sources: ranked,
      untimedSessions: untimed,
      sessions: sessions,
      streakCurrent: stats.streakCurrent,
      streakLongest: stats.streakLongest,
      practisedLast30: practised.where((d) => !d.isBefore(windowStart)).length,
      practisedThisWeek: practised.where((d) => !d.isBefore(weekStart)).length,
      firstDay: sorted.isEmpty ? null : sorted.first,
    );
  }
}

class _Group {
  _Group(this.source, this.courseId);
  final PracticeSource source;
  final String? courseId;
  String? title;
  int ms = 0;
  int sessions = 0;
}
