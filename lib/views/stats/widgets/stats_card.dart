import 'package:flutter/material.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';

/// Gutter and gap the stats page and You share with Home's sections.
const kStatsGutter = 16.0;
const kStatsGap = 12.0;

/// A titled surface on the stats page: Expressive's 28 dp card on a tonal
/// container, a heading in the emphasized scale, and room for the content.
class StatsCard extends StatelessWidget {
  const StatsCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.caption,
  });

  final String title;
  final Widget child;

  /// A control on the heading row (the 7 / 30 day switch).
  final Widget? trailing;

  /// One quiet line under the content.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: MeditejoShapes.rounded(MeditejoShapes.extraLarge),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: type.emphasized.titleMedium),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
            if (caption != null) ...[
              const SizedBox(height: 12),
              Text(
                caption!,
                style: type.baseline.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One number with its label: a figure in the emphasized headline, the label
/// beneath in the variant colour.
class StatFigure extends StatelessWidget {
  const StatFigure({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    return Semantics(
      container: true,
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: type.emphasized.headlineSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: type.baseline.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
