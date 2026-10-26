import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/services/stats_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/utils/audio_completion_tracker.dart';
import 'package:medito/services/home_widget_service.dart';
import 'package:medito/utils/consistency_score_history.dart';
import 'package:medito/utils/day_boundary.dart';
import 'package:medito/utils/logger.dart';

class StatsManager {
  static final StatsManager _instance = StatsManager._internal();
  factory StatsManager() => _instance;

  late StatsService _statsService;
  late SharedPreferences _prefs;
  LocalAllStats? _allStats;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  DateTime? _testDate;
  Duration _dayBoundaryOffset = Duration.zero;
  Future<void> _mutationTail = Future<void>.value();

  StatsManager._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    _initCompleter = Completer<void>();
    try {
      _prefs = await SharedPreferences.getInstance();
      _statsService = StatsService(prefs: _prefs);
      _loadDayBoundaryOffset(_prefs);
      _isInitialized = true;
      _initCompleter!.complete();
    } catch (e) {
      AppLogger.e('STATS_MANAGER', 'Initialization failed', e);
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  /// Refreshes derived stats from the on-device history. Kept as `sync` for
  /// existing lifecycle callers; `force` no longer triggers a network request.
  Future<void> sync({bool force = false}) => _mutate(() async {
    _allStats = calculateStreak(_allStats!);
    final score = calculateConsistencyScore(_allStats!);
    _allStats = _allStats!.copyWith(consistencyScore: score);
    await _saveLocalAllStatsToSharedPrefs();
    await saveConsistencyScoreHistory(score);
    HomeWidgetService.updateWidgetFromStats(_allStats!).catchError((e) {
      // Widget updates are not critical to local stats persistence.
    });
  });

  Future<LocalAllStats> get localAllStats => _serialize(() async {
    await initialize();
    await _ensureStatsLoaded();
    return _allStats!;
  });

  // ⚠️ KEEP IN SYNC: ported to Kotlin in
  // android/app/src/main/kotlin/meditofoundation/medito/widget/StreakCalculator.kt
  // so the Android home-screen widget can recompute the current streak
  // on-device (including the day-boundary offset). If this algorithm
  // changes, update that copy too.
  LocalAllStats calculateStreak(LocalAllStats allStats) {
    final offset = _dayBoundaryOffset;
    final now = _getCurrentDate();
    final today = dayOf(now, offset);
    var longestStreak = allStats.streakLongest;

    // Any day with an entry (real session, freeze audio entry, or legacy
    // freeze date) counts toward the streak. The freeze feature is retired, so
    // we no longer distinguish freeze vs real — preserving legacy streaks for
    // users who accrued them under the old "freeze = +1" rule.
    final activityDates = <DateTime>{};

    for (final entry in allStats.audioCompleted ?? []) {
      final date = DateTime.fromMillisecondsSinceEpoch(entry.timestamp);
      final day = dayOf(date, offset);
      if (day.isAfter(today)) continue;
      activityDates.add(day);
    }

    for (final ts in allStats.freezeUsageDates) {
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      final day = dayOf(date, offset);
      if (!day.isAfter(today)) activityDates.add(day);
    }

    if (activityDates.isEmpty) {
      return allStats.copyWith(streakCurrent: 0, streakLongest: longestStreak);
    }

    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final hasActivityToday = activityDates.contains(today);
    final hasActivityYesterday = activityDates.contains(yesterday);

    if (!hasActivityToday && !hasActivityYesterday) {
      return allStats.copyWith(streakCurrent: 0, streakLongest: longestStreak);
    }

    var streak = hasActivityToday ? 1 : 0;
    var checkDate = yesterday;

    while (activityDates.contains(checkDate)) {
      streak++;
      checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day - 1);
    }

    if (streak > longestStreak) longestStreak = streak;

    return allStats.copyWith(
      streakCurrent: streak,
      streakLongest: longestStreak,
    );
  }

  Future<void> _saveLocalAllStatsToSharedPrefs() async {
    if (_allStats != null) {
      await _statsService.saveStats(_allStats!);
    }
  }

  /// One stats writer at a time, including refreshes and checked-track edits.
  /// Keep a private working copy so failed edits cannot mutate the last good
  /// snapshot through shared lists. Readers wait until the write is settled.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _mutationTail.then((_) => operation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _mutate(
    Future<void> Function() operation, {
    bool loadStats = true,
  }) => _serialize(() async {
    await initialize();
    if (loadStats) await _ensureStatsLoaded();
    final before = _allStats;
    if (before != null) {
      _allStats = before.copyWith(
        tracksChecked: [...?before.tracksChecked],
        audioCompleted: [...?before.audioCompleted],
        freezeUsageDates: [...before.freezeUsageDates],
        completionReceipts: [...before.completionReceipts],
      );
    }
    try {
      await operation();
    } catch (_) {
      _allStats = before;
      try {
        // StatsService repairs the preferences cache after failed writes.
        // Also handles an ambiguous error after the platform committed.
        _allStats = await _statsService.loadStats();
      } catch (_) {
        // Do not reuse a potentially uncommitted preferences cache.
        _allStats = null;
      }
      rethrow;
    }
  });

  /// Load the persisted history before a first mutation, including histories
  /// containing only checked tracks or legacy counters.
  Future<void> _ensureStatsLoaded() async {
    if (_allStats != null) return;
    final storedStats = await _statsService.loadStats();
    _allStats ??= storedStats;
  }

  Future<void> addAudioCompleted(
    LocalAudioCompleted audioCompleted,
    int duration, {
    bool updateWidget = true,
    String? completionId,
    String? kind,
    String? courseId,
    String? courseTitle,
  }) => _mutate(() async {
    // The history keeps how long each session ran, and what it was (Practice
    // or Talks, and which course), for the stats page. Recorded from here on.
    audioCompleted = audioCompleted.copyWith(
      durationMs: duration,
      kind: kind,
      courseId: courseId,
      courseTitle: courseTitle,
    );
    if (AudioCompletionTracker.checkTrackCrossedMidnight(
      endTimestamp: audioCompleted.timestamp,
      duration: duration,
    )) {
      audioCompleted = audioCompleted.copyWith(
        timestamp: audioCompleted.timestamp - duration,
      );
    }

    if (completionId != null) {
      if (_allStats!.completionReceipts.contains(completionId)) return;
      // Upgrade a replay from before receipts existed without counting it
      // twice. Match the attributed history timestamp, including midnight.
      final alreadyRecorded = (_allStats!.audioCompleted ?? []).any(
        (entry) =>
            entry.id == audioCompleted.id &&
            entry.timestamp == audioCompleted.timestamp,
      );
      _allStats = _allStats!.copyWith(
        completionReceipts: [..._allStats!.completionReceipts, completionId],
      );
      if (alreadyRecorded) {
        await _saveLocalAllStatsToSharedPrefs();
        return;
      }
    }

    // Update stats with the completed audio
    _allStats = AudioCompletionTracker.updateStatsWithCompletedAudio(
      stats: _allStats,
      audioCompleted: audioCompleted,
      duration: duration,
    );

    // Calculate streak and consistency score, then save stats
    if (_allStats != null) {
      _allStats = calculateStreak(_allStats!);
      final newConsistencyScore = calculateConsistencyScore(_allStats!);
      _allStats = _allStats!.copyWith(consistencyScore: newConsistencyScore);
      await _saveLocalAllStatsToSharedPrefs();
      await saveConsistencyScoreHistory(newConsistencyScore);

      // Batched manual inserts refresh the widget once in the caller.
      if (!updateWidget) return;

      // Update home widget (fire-and-forget to avoid blocking)
      HomeWidgetService.updateWidgetFromStats(_allStats!).catchError((e) {
        // Silently fail - widget updates are not critical
      });
    }
  });

  /// Adds the listening time of a repeated play-through without recording a
  /// new session. See [AudioCompletionTracker.addRepeatListeningTime].
  ///
  /// With [trackId], the repeat's minutes are also added to that track's most
  /// recent session, so the day it was sat shows them in the stats page.
  Future<void> addRepeatListeningTime(
    int duration, {
    String? completionId,
    String? trackId,
  }) => _mutate(() async {
    if (completionId != null) {
      if (_allStats!.completionReceipts.contains(completionId)) return;
      _allStats = _allStats!.copyWith(
        completionReceipts: [..._allStats!.completionReceipts, completionId],
      );
    }

    _allStats = AudioCompletionTracker.addRepeatListeningTime(
      stats: _allStats,
      duration: duration,
      trackId: trackId,
    );
    await _saveLocalAllStatsToSharedPrefs();

    HomeWidgetService.updateWidgetFromStats(_allStats!).catchError((e) {
      // Silently fail - widget updates are not critical
    });
  });

  Future<void> removeAudioCompleted(LocalAudioCompleted session) =>
      _mutate(() async {
        if (_allStats == null) return;

        final currentList = _allStats!.audioCompleted ?? [];
        final updatedList = currentList
            .where(
              (a) => !(a.id == session.id && a.timestamp == session.timestamp),
            )
            .toList();

        if (updatedList.length == currentList.length) {
          // Nothing matched — don't write an update
          return;
        }

        final newTotalTracks = (_allStats!.totalTracksCompleted - 1).clamp(
          0,
          1 << 31,
        );

        // Take back the minutes the entry recorded (an older entry recorded
        // none, and its minutes stay in the total as they always did).
        final removed = currentList.firstWhere(
          (a) => a.id == session.id && a.timestamp == session.timestamp,
        );
        final newTotalTime =
            (_allStats!.totalTimeListened - (removed.durationMs ?? 0)).clamp(
              0,
              9007199254740991,
            );

        _allStats = _allStats!.copyWith(
          audioCompleted: updatedList,
          totalTimeListened: newTotalTime,
          totalTracksCompleted: newTotalTracks,
          updated: _getCurrentDate().millisecondsSinceEpoch,
        );

        _allStats = calculateStreak(_allStats!);
        final newConsistencyScore = calculateConsistencyScore(_allStats!);
        _allStats = _allStats!.copyWith(consistencyScore: newConsistencyScore);
        await _saveLocalAllStatsToSharedPrefs();
        await saveConsistencyScoreHistory(newConsistencyScore);

        HomeWidgetService.updateWidgetFromStats(_allStats!).catchError((e) {
          // Silently fail - widget updates are not critical
        });
      });

  Future<void> addTrackChecked(String? id) => _mutate(() async {
    assert(id != null, 'Track ID cannot be null');

    var updatedTracksChecked = _allStats?.tracksChecked ?? [];
    if (!updatedTracksChecked.contains(id)) {
      updatedTracksChecked.add(id!);

      _allStats = _allStats?.copyWith(
        tracksChecked: updatedTracksChecked,
        updated: _getCurrentDate().millisecondsSinceEpoch,
      );

      await _saveLocalAllStatsToSharedPrefs();
    }
  });

  /// Bulk variant of [addTrackChecked]/[removeTrackChecked] used by the
  /// pack screen's "mark all" action. Applies every change in a single local save.
  Future<void> setTracksChecked(List<String> ids, {required bool checked}) =>
      _mutate(() async {
        var updatedTracksChecked = _allStats?.tracksChecked ?? [];
        var changed = false;
        if (checked) {
          for (final id in ids) {
            if (!updatedTracksChecked.contains(id)) {
              updatedTracksChecked.add(id);
              changed = true;
            }
          }
        } else {
          for (final id in ids) {
            if (updatedTracksChecked.remove(id)) {
              changed = true;
            }
          }
        }

        if (changed) {
          _allStats = _allStats?.copyWith(
            tracksChecked: updatedTracksChecked,
            updated: _getCurrentDate().millisecondsSinceEpoch,
          );

          await _saveLocalAllStatsToSharedPrefs();
        }
      });

  Future<void> removeTrackChecked(String trackId) => _mutate(() async {
    var updatedTracksChecked = _allStats?.tracksChecked ?? [];
    if (updatedTracksChecked.remove(trackId)) {
      _allStats = _allStats?.copyWith(
        tracksChecked: updatedTracksChecked,
        updated: _getCurrentDate().millisecondsSinceEpoch,
      );

      await _saveLocalAllStatsToSharedPrefs();
    }
  });

  Future<void> clearAllStats() => _mutate(() async {
    _allStats = LocalAllStats.empty();
    await _statsService.clearStats();
  }, loadStats: false);

  bool get isInitialized => _isInitialized;

  Future<bool> hasLocalStats() async =>
      (await localAllStats).audioCompleted?.isNotEmpty == true;

  // ⚠️ KEEP IN SYNC: ported to Kotlin in
  // android/app/src/main/kotlin/meditofoundation/medito/widget/ConsistencyWidget.kt
  // (calculateConsistencyScore) so the Android home-screen widget can recompute
  // the percentage on-device. If this algorithm changes, update that copy too.
  double calculateConsistencyScore(LocalAllStats allStats) {
    // MUST bucket days the same way `calculateStreak` does (via `dayOf` with
    // the day-boundary offset), otherwise the score and the calendar disagree
    // with the streak for users with a nonzero offset who meditate inside the
    // offset window.
    final offset = _dayBoundaryOffset;
    var now = _getCurrentDate();
    var today = dayOf(now, offset);

    if (allStats.audioCompleted == null || allStats.audioCompleted!.isEmpty) {
      return 0.0;
    }

    var audioDates = allStats.audioCompleted!.map((audio) {
      var date = DateTime.fromMillisecondsSinceEpoch(audio.timestamp);
      return dayOf(date, offset);
    }).toList();

    audioDates = audioDates
        .where((date) => !date.isAfter(today))
        .toSet()
        .toList();

    var freezeDates = allStats.freezeUsageDates.map((timestamp) {
      var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return dayOf(date, offset);
    }).toList();

    freezeDates = freezeDates
        .where((date) => !date.isAfter(today) && !audioDates.contains(date))
        .toSet()
        .toList();

    var allActivityDates = {...audioDates, ...freezeDates}.toList();

    if (allActivityDates.isEmpty) {
      return 0.0;
    }

    allActivityDates.sort();
    var firstSessionDate = allActivityDates.first;
    // Count calendar days, not elapsed 24-hour periods. Local midnights can
    // be 23 or 25 hours apart across daylight-saving changes.
    var daysSinceFirstSession =
        DateTime.utc(today.year, today.month, today.day)
            .difference(
              DateTime.utc(
                firstSessionDate.year,
                firstSessionDate.month,
                firstSessionDate.day,
              ),
            )
            .inDays +
        1;

    DateTime calendarDaysAfter(DateTime date, int days) =>
        DateTime(date.year, date.month, date.day + days);

    if (daysSinceFirstSession == 1) {
      return allActivityDates.any((date) => date.isAtSameMomentAs(today))
          ? 1.0
          : 0.0;
    }

    // Bootstrap phase: simple ratio for the first 30 days
    if (daysSinceFirstSession < 30) {
      return (allActivityDates.length / daysSinceFirstSession).clamp(0.0, 1.0);
    }

    // EMA phase: replay history day by day starting from day 30,
    // seeding with the ratio at day 29.
    const alpha = 0.1;
    const gracePenalty = 0.5; // value used for a single isolated missed day

    var day29 = calendarDaysAfter(firstSessionDate, 28);
    var activeDaysAtDay29 = allActivityDates
        .where((d) => !d.isAfter(day29))
        .length;
    var ema = activeDaysAtDay29 / 29.0;

    var day30 = calendarDaysAfter(firstSessionDate, 29);
    var currentDay = day30;

    while (!currentDay.isAfter(today)) {
      var hadActivity = allActivityDates.any(
        (d) =>
            d.year == currentDay.year &&
            d.month == currentDay.month &&
            d.day == currentDay.day,
      );

      double dayValue;
      if (hadActivity) {
        dayValue = 1.0;
      } else {
        var prevDay = calendarDaysAfter(currentDay, -1);
        var nextDay = calendarDaysAfter(currentDay, 1);
        var prevActive = allActivityDates.any(
          (d) =>
              d.year == prevDay.year &&
              d.month == prevDay.month &&
              d.day == prevDay.day,
        );
        var nextActive = nextDay.isAfter(today)
            ? false
            : allActivityDates.any(
                (d) =>
                    d.year == nextDay.year &&
                    d.month == nextDay.month &&
                    d.day == nextDay.day,
              );
        // Single isolated miss gets half penalty; consecutive misses get full penalty
        dayValue = (prevActive || nextActive) ? gracePenalty : 0.0;
      }

      ema = alpha * dayValue + (1 - alpha) * ema;
      currentDay = calendarDaysAfter(currentDay, 1);
    }

    return ema.clamp(0.0, 1.0);
  }

  // Test helpers
  @visibleForTesting
  void setStatsForTesting(LocalAllStats stats) {
    _allStats = stats;
  }

  @visibleForTesting
  LocalAllStats? get currentStats => _allStats;

  void setCurrentDateForTesting(DateTime date) {
    _testDate = date;
  }

  /// Sets the day-boundary offset used by `calculateStreak` and persists it.
  /// `Duration.zero` (default) preserves legacy midnight behaviour.
  ///
  /// If stats are already loaded and the offset actually changed, the streak
  /// and consistency score are recomputed straight away. The calendar
  /// re-buckets from the raw sessions as soon as the offset changes, so
  /// leaving the stored streak until the next refresh made the two disagree.
  Future<void> setDayBoundaryOffset(Duration offset) => _mutate(() async {
    await initialize();
    final changed = offset != _dayBoundaryOffset;
    _dayBoundaryOffset = offset;
    try {
      await _prefs.setInt(
        SharedPreferenceConstants.dayBoundaryOffsetHours,
        offset.inHours,
      );
    } catch (e) {
      AppLogger.e('STATS_MANAGER', 'Failed to persist day boundary offset', e);
    }

    if (!changed || _allStats == null) return;

    _allStats = calculateStreak(_allStats!);
    final newConsistencyScore = calculateConsistencyScore(_allStats!);
    _allStats = _allStats!.copyWith(consistencyScore: newConsistencyScore);
    await _saveLocalAllStatsToSharedPrefs();
  });

  void _loadDayBoundaryOffset(SharedPreferences prefs) {
    try {
      final hours = prefs.getInt(
        SharedPreferenceConstants.dayBoundaryOffsetHours,
      );
      if (hours != null) _dayBoundaryOffset = Duration(hours: hours);
    } catch (e) {
      _dayBoundaryOffset = Duration.zero;
    }
  }

  Duration get dayBoundaryOffset => _dayBoundaryOffset;

  @visibleForTesting
  void setDayBoundaryOffsetForTesting(Duration offset) {
    _dayBoundaryOffset = offset;
  }

  @visibleForTesting
  void resetForTesting() {
    _mutationTail = Future<void>.value();
    _allStats = null;
    _isInitialized = false;
    _initCompleter = null;
    _testDate = null;
    _dayBoundaryOffset = Duration.zero;
  }

  DateTime _getCurrentDate() {
    return _testDate ?? DateTime.now();
  }

  /// Honours [setCurrentDateForTesting]. Callers outside of StatsManager
  /// should prefer this over `DateTime.now()` for any logic that interacts
  /// with stats (streak math, manual-session backfills, etc.) so tests can
  /// pin the clock.
  DateTime get currentDate => _getCurrentDate();

  @visibleForTesting
  Future<void> initializeForTesting() => initialize();
}
