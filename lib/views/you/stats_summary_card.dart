import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/views/stats/stats_format.dart';
import 'package:medito/views/stats/stats_screen.dart';

/// Three numbers from the stats page (this week, all time, the streak) on the
/// You tab. Tapping opens the full page.
class StatsSummaryCard extends ConsumerWidget {
  const StatsSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final summary = ref.watch(practiceSummaryProvider);
    final streak = ref.watch(
      statsProvider.select((s) => s.value?.streakCurrent),
    );

    final figures = [
      (
        summary == null ? '–' : formatPractice(summary.thisWeek, l10n),
        l10n.statsThisWeek,
      ),
      (
        summary == null ? '–' : formatPractice(summary.allTime, l10n),
        l10n.statsTotalTime,
      ),
      (
        streak == null ? '–' : '$streak ${streak == 1 ? l10n.day : l10n.days}',
        l10n.currentStreak,
      ),
    ];

    return Semantics(
      button: true,
      label: [
        l10n.stats,
        for (final (value, label) in figures) '$label: $value',
      ].join(', '),
      child: ExcludeSemantics(
        child: HomePressable(
          color: scheme.primaryContainer,
          radius: MeditejoShapes.extraLarge,
          onTap: () => Navigator.of(
            context,
          ).push<void>(MaterialPageRoute(builder: (_) => const StatsScreen())),
          child: Padding(
            key: const ValueKey('you_stats_card'),
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 20),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: scheme.onPrimaryContainer),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.stats,
                          style: type.emphasized.titleMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onPrimaryContainer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (value, label) in figures)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  value,
                                  style: type.emphasized.titleLarge?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                Text(
                                  label,
                                  style: type.baseline.bodySmall?.copyWith(
                                    color: scheme.onPrimaryContainer.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
