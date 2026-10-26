import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/day_boundary_offset_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/stats/practice_summary.dart';

/// The clock the stats page reads "today" from; tests replace it.
final practiceClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The stats page's numbers, from the local history and the user's day
/// boundary. Null until the history has loaded.
final practiceSummaryProvider = Provider<PracticeSummary?>((ref) {
  final stats = ref.watch(statsProvider).value;
  if (stats == null) return null;
  final hours = ref.watch(dayBoundaryOffsetProvider).value ?? 0;
  return PracticeSummary.from(
    stats,
    now: ref.watch(practiceClockProvider)(),
    dayOffset: Duration(hours: hours),
  );
});
