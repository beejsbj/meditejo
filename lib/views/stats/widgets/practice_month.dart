import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/services/stats/practice_summary.dart';
import 'package:medito/views/stats/stats_format.dart';

/// How dark a day is drawn: 0 none, 1 to 4 by minutes sat. A day with a
/// session of no recorded length is level 1.
int practiceLevel(Duration? time, {required bool practised}) {
  if (!practised) return 0;
  final minutes = time?.inMinutes ?? 0;
  if (minutes < 10) return 1;
  if (minutes < 20) return 2;
  if (minutes < 40) return 3;
  return 4;
}

/// One month of days practised, as a heat-map: a grid of days, the colour
/// deepening with the minutes. Arrows step between months back to the first
/// day with a session.
class PracticeMonth extends StatefulWidget {
  const PracticeMonth({super.key, required this.summary, required this.today});

  final PracticeSummary summary;

  /// Local midnight of today (the user's day boundary applied).
  final DateTime today;

  @override
  State<PracticeMonth> createState() => _PracticeMonthState();
}

class _PracticeMonthState extends State<PracticeMonth> {
  late DateTime _month = DateTime(widget.today.year, widget.today.month);

  DateTime get _earliest {
    final first = widget.summary.firstDay ?? widget.today;
    return DateTime(first.year, first.month);
  }

  bool get _canGoBack => _month.isAfter(_earliest);
  bool get _canGoForward =>
      _month.isBefore(DateTime(widget.today.year, widget.today.month));

  void _step(int by) => setState(() {
    _month = DateTime(_month.year, _month.month + by);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final material = MaterialLocalizations.of(context);

    final summary = widget.summary;
    final count = summary.practisedIn(_month);
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    // Monday first: DateTime.monday is 1.
    final lead = DateTime(_month.year, _month.month).weekday - DateTime.monday;
    final rows = ((lead + daysInMonth) / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.previousMonth,
              onPressed: _canGoBack ? () => _step(-1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '${DateFormat.yMMMM(locale).format(_month)} · '
                  '${l10n.statsDaysPractised(count)}',
                  textAlign: TextAlign.center,
                  style: type.baseline.titleSmall,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.nextMonth,
              onPressed: _canGoForward ? () => _step(1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(
                    // narrowWeekdays starts on Sunday.
                    material.narrowWeekdays[(i + 1) % 7],
                    textAlign: TextAlign.center,
                    style: type.baseline.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _cell(context, r * 7 + c - lead + 1)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        ExcludeSemantics(child: _Legend(l10n: l10n)),
      ],
    );
  }

  Widget _cell(BuildContext context, int dayOfMonth) {
    if (dayOfMonth < 1 ||
        dayOfMonth > DateUtils.getDaysInMonth(_month.year, _month.month)) {
      return const SizedBox(height: 40);
    }
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateTime(_month.year, _month.month, dayOfMonth);
    final future = date.isAfter(widget.today);
    final practised = widget.summary.daysPractised.contains(date);
    final time = widget.summary.timeByDay[date];
    final level = future ? 0 : practiceLevel(time, practised: practised);
    final isToday = date == widget.today;

    final fill = level == 0
        ? (future ? Colors.transparent : scheme.surfaceContainerHighest)
        : scheme.primary.withValues(
            alpha: const <double>[0, 0.28, 0.5, 0.75, 1][level],
          );
    final onFill = level >= 3 ? scheme.onPrimary : scheme.onSurface;

    final label = future
        ? formatDay(date, locale)
        : practised
        ? '${formatDay(date, locale)}, ${time == null || time == Duration.zero ? l10n.statsPractised : formatPractice(time, l10n)}'
        : '${formatDay(date, locale)}, ${l10n.dayNotMeditated}';

    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            key: ValueKey('day_${date.month}_$dayOfMonth'),
            height: 36,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: fill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(MeditejoShapes.medium),
                side: isToday
                    ? BorderSide(color: scheme.primary, width: 2)
                    : BorderSide.none,
              ),
            ),
            child: Text(
              '$dayOfMonth',
              style: context.typography.baseline.labelMedium?.copyWith(
                color: future ? scheme.onSurfaceVariant : onFill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = context.typography.baseline.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(l10n.statsLess, style: style),
        const SizedBox(width: 6),
        for (final level in [0, 1, 2, 3, 4])
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: level == 0
                  ? scheme.surfaceContainerHighest
                  : scheme.primary.withValues(
                      alpha: const <double>[0, 0.28, 0.5, 0.75, 1][level],
                    ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        const SizedBox(width: 6),
        Text(l10n.statsMore, style: style),
      ],
    );
  }
}
