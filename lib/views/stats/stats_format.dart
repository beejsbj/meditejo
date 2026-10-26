import 'package:intl/intl.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/timer/timer_format.dart';

/// `0 min`, `20 min`, `1 h` or `1 h 30 min`: a stretch of practice, to the
/// minute. Under a minute reads `0 min`, as a session under a minute is not
/// recorded.
String formatPractice(Duration time, AppLocalizations l10n) =>
    formatTimerLength(time, l10n);

/// `Tue 20 Oct`.
String formatDay(DateTime day, String locale) =>
    DateFormat.MMMEd(locale).format(day);

/// The top of the chart's scale for a busiest day of [peak] minutes: a round
/// number at or above it, never below 10.
int chartCeilingMinutes(int peak) {
  const steps = [10, 20, 30, 45, 60, 90, 120, 180, 240, 360, 480];
  for (final step in steps) {
    if (peak <= step) return step;
  }
  return ((peak + 119) ~/ 120) * 120;
}
