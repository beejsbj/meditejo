import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/day_boundary_offset_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/stats/practice_summary.dart';
import 'package:medito/utils/day_boundary.dart';

/// The clock the stats page reads "today" from; tests replace it.
final practiceClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The stats page's numbers, from the local history and the user's day
/// boundary. Null until the history has loaded. Rebuilt when the day turns
/// over while the app stays open, so Today and This week do not go stale.
final practiceSummaryProvider = Provider<PracticeSummary?>((ref) {
  final stats = ref.watch(statsProvider).value;
  if (stats == null) return null;
  final offset = Duration(
    hours: ref.watch(dayBoundaryOffsetProvider).value ?? 0,
  );
  final now = ref.watch(practiceClockProvider)();

  final today = dayOf(now, offset);
  final nextDay = DateTime(today.year, today.month, today.day + 1).add(offset);
  final wait = nextDay.difference(now) + const Duration(seconds: 1);
  final timer = Timer(wait, ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  return PracticeSummary.from(stats, now: now, dayOffset: offset);
});
