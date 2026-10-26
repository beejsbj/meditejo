import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/services/stats/practice_summary.dart';
import 'package:medito/views/stats/stats_format.dart';

/// How many courses and sources the ranking lists before it stops.
const kRankedSources = 5;

String sourceName(SourceTotal source, AppLocalizations l10n) =>
    switch (source.source) {
      PracticeSource.course =>
        (source.courseTitle?.isNotEmpty ?? false)
            ? source.courseTitle!
            : l10n.statsSourceCourse,
      PracticeSource.timer => l10n.timerTitle,
      PracticeSource.addedByHand => l10n.statsSourceByHand,
      PracticeSource.dharmaSeed => l10n.statsSourceDharmaSeed,
      PracticeSource.youtube => l10n.statsSourceYoutube,
      PracticeSource.imported => l10n.statsSourceImported,
      PracticeSource.other => l10n.statsSourceOther,
    };

/// Practice against Talks as one split bar and two rows, then the courses and
/// sources the time went to, most first. Only sessions with a recorded length
/// count here.
class PracticeBreakdown extends StatelessWidget {
  const PracticeBreakdown({super.key, required this.summary});

  final PracticeSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;

    final recorded = summary.recordedTime;
    if (recorded == Duration.zero) {
      return Text(
        l10n.statsBreakdownEmpty,
        style: type.baseline.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    final kinds = [
      (l10n.statsPractice, summary.practiceTime, scheme.primary),
      (l10n.statsTalks, summary.talksTime, scheme.tertiary),
      if (summary.otherTime > Duration.zero)
        (l10n.statsSourceOther, summary.otherTime, scheme.outline),
    ].where((k) => k.$2 > Duration.zero).toList();

    final ranked = summary.sources.take(kRankedSources).toList();
    final top = ranked.isEmpty ? Duration.zero : ranked.first.time;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The split: segments in proportion with a 2 dp gap between them.
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  for (final (i, k) in kinds.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: k.$2.inSeconds.clamp(1, 1 << 30),
                      child: ColoredBox(color: k.$3),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final k in kinds)
          Semantics(
            container: true,
            label:
                '${k.$1}: ${formatPractice(k.$2, l10n)}, '
                '${(k.$2.inSeconds * 100 / recorded.inSeconds).round()}%',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: k.$3,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(k.$1, style: type.baseline.bodyLarge)),
                    Text(
                      formatPractice(k.$2, l10n),
                      style: type.emphasized.bodyLarge,
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${(k.$2.inSeconds * 100 / recorded.inSeconds).round()}%',
                        textAlign: TextAlign.end,
                        style: type.baseline.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Divider(height: 1, color: scheme.outlineVariant),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(l10n.statsByCourse, style: type.baseline.titleSmall),
        ),
        const SizedBox(height: 8),
        for (final s in ranked)
          Semantics(
            container: true,
            label: '${sourceName(s, l10n)}: ${formatPractice(s.time, l10n)}',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sourceName(s, l10n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: type.baseline.bodyLarge,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatPractice(s.time, l10n),
                          style: type.baseline.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: top == Duration.zero
                            ? 0
                            : s.time.inSeconds / top.inSeconds,
                        minHeight: 4,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
