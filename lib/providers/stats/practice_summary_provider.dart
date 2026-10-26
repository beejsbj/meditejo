import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/day_boundary_offset_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/stats/practice_summary.dart';

/// The clock the stats page reads "today" from; tests replace it.
final practiceClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Bumped by the app (once a minute while it is open, and when it comes back
/// to the foreground) so [practiceSummaryProvider] reads the clock again and
/// Today and This week turn over at the day boundary. Held here, not as a
/// timer in the provider, so a test holding the provider has no timer pending.
final practiceTickProvider = NotifierProvider<PracticeTick, int>(
  PracticeTick.new,
);

class PracticeTick extends Notifier<int> {
  @override
  int build() => 0;

  void tick() => state++;
}

/// The stats page's numbers, from the local history and the user's day
/// boundary. Null until the history has loaded.
final practiceSummaryProvider = Provider<PracticeSummary?>((ref) {
  final stats = ref.watch(statsProvider).value;
  if (stats == null) return null;
  ref.watch(practiceTickProvider);
  return PracticeSummary.from(
    stats,
    now: ref.watch(practiceClockProvider)(),
    dayOffset: Duration(hours: ref.watch(dayBoundaryOffsetProvider).value ?? 0),
  );
});
