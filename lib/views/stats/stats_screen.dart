import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/stats/practice_summary.dart';
import 'package:medito/views/home/widgets/bottom_sheet/stats/meditation_calendar_widget.dart';
import 'package:medito/views/stats/stats_format.dart';
import 'package:medito/views/stats/widgets/daily_bars.dart';
import 'package:medito/views/stats/widgets/practice_breakdown.dart';
import 'package:medito/views/stats/widgets/practice_month.dart';
import 'package:medito/views/stats/widgets/stats_card.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/dialogs/medito_dialog.dart';
import 'package:medito/widgets/dialogs/medito_dialog_buttons.dart';
import 'package:share_plus/share_plus.dart';

/// Time practised, a chart of the days, the month, where the time went, and
/// the streak, all from the history kept on this device. A second tab holds
/// the history itself, where sessions are added and deleted.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  late int _tab = widget.initialTabIndex.clamp(0, 1);

  void _showConsistencyScoreInfo() {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => MeditoDialog(
        title: l10n.consistencyScoreInfoTitle,
        content: MeditoDialogBody(l10n.consistencyScoreInfoMessage),
        actions: [
          MeditoDialogPrimaryButton(
            label: l10n.gotIt,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final statsAsync = ref.watch(statsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.stats,
          style: context.typography.emphasized.titleLarge,
        ),
        backgroundColor: scheme.surface,
      ),
      body: AdaptivePageBody(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            kStatsGutter,
            4,
            kStatsGutter,
            kStatsGutter * 2,
          ),
          children: [
            SegmentedButton<int>(
              key: const ValueKey('stats_tabs'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, label: Text(l10n.stats)),
                ButtonSegment(value: 1, label: Text(l10n.history)),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: kStatsGap + 4),
            ..._body(context, statsAsync),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, AsyncValue<LocalAllStats> async) {
    final stats = async.value;
    if (stats == null) {
      if (async.hasError) {
        return [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: TextButton.icon(
                onPressed: () => ref.read(statsProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(AppLocalizations.of(context)!.refresh),
              ),
            ),
          ),
        ];
      }
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }
    if (_tab == 1) {
      return [if (stats.updated != 0) MeditationCalendarWidget(stats: stats)];
    }
    final summary = ref.watch(practiceSummaryProvider);
    return summary == null ? const [] : _statsTab(context, stats, summary);
  }

  List<Widget> _statsTab(
    BuildContext context,
    LocalAllStats stats,
    PracticeSummary summary,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    String time(Duration d) => formatPractice(d, l10n);
    String days(int n) => '$n ${n == 1 ? l10n.day : l10n.days}';

    final note = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        l10n.statsFeedbackNote,
        style: type.baseline.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    if (summary.isEmpty) {
      return [
        note,
        const SizedBox(height: kStatsGap + 4),
        StatsCard(
          title: l10n.statsTimePractised,
          child: Text(
            l10n.statsEmpty,
            key: const ValueKey('stats_empty'),
            style: type.baseline.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }

    return [
      note,
      const SizedBox(height: kStatsGap + 4),
      StatsCard(
        title: l10n.statsTimePractised,
        caption: summary.untimedSessions == 0
            ? null
            : l10n.statsUntimedNote(summary.untimedSessions),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatFigure(
                    value: time(summary.today),
                    label: l10n.statsToday,
                  ),
                ),
                Expanded(
                  child: StatFigure(
                    value: time(summary.thisWeek),
                    label: l10n.statsThisWeek,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatFigure(
                    value: time(summary.thisMonth),
                    label: l10n.statsThisMonth,
                  ),
                ),
                Expanded(
                  child: StatFigure(
                    value: time(summary.allTime),
                    label: l10n.statsAllTime,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: kStatsGap),
      _ChartCard(summary: summary),
      const SizedBox(height: kStatsGap),
      StatsCard(
        title: l10n.statsDaysPracticedTitle,
        child: PracticeMonth(summary: summary, today: summary.days.last.day),
      ),
      const SizedBox(height: kStatsGap),
      StatsCard(
        title: l10n.statsBreakdown,
        child: PracticeBreakdown(summary: summary),
      ),
      const SizedBox(height: kStatsGap),
      StatsCard(
        title: l10n.statsStreakTitle,
        caption: l10n.statsLast30Days(summary.practisedLast30),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatFigure(
                    value: days(stats.streakCurrent),
                    label: l10n.currentStreak,
                  ),
                ),
                Expanded(
                  child: StatFigure(
                    value: days(stats.streakLongest),
                    label: l10n.longestStreak,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatFigure(
                    value: '${stats.totalTracksCompleted}',
                    label: l10n.totalTracksCompleted,
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: StatFigure(
                          value: '${(stats.consistencyScore * 100).round()}%',
                          label: l10n.statsConsistency,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.consistencyScoreInfoTitle,
                        visualDensity: VisualDensity.compact,
                        onPressed: _showConsistencyScoreInfo,
                        icon: const Icon(Icons.info_outline_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: kStatsGap),
      Align(
        child: TextButton.icon(
          onPressed: () =>
              SharePlus.instance.share(ShareParams(text: l10n.shareStatsText)),
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(l10n.share),
        ),
      ),
    ];
  }
}

/// Minutes a day over the last 7 or 30 days, with the switch between them.
class _ChartCard extends StatefulWidget {
  const _ChartCard({required this.summary});

  final PracticeSummary summary;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int _range = 7;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StatsCard(
      title: l10n.statsDailyMinutes,
      trailing: SegmentedButton<int>(
        key: const ValueKey('chart_range'),
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          ButtonSegment(value: 7, label: Text(l10n.statsRange7)),
          ButtonSegment(value: 30, label: Text(l10n.statsRange30)),
        ],
        selected: {_range},
        onSelectionChanged: (s) => setState(() => _range = s.first),
      ),
      child: DailyBars(days: widget.summary.lastDays(_range)),
    );
  }
}
