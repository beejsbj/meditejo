import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/views/library/library_format.dart';
import 'package:medito/views/player/start_session.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// What is in progress, up to three, each one tap from playing. With nothing
/// started it offers the next session of a pinned or starter course.
class ContinueSection extends ConsumerWidget {
  const ContinueSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final items = ref.watch(continueItemsProvider).value;
    if (items == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(l10n.upNextTitle),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kHomeGutter + 4),
            child: Text(
              l10n.homeContinueEmpty,
              key: const ValueKey('continue_empty'),
              style: context.typography.baseline.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final (i, item) in items.indexed)
            Padding(
              padding: EdgeInsets.fromLTRB(
                kHomeGutter,
                i == 0 ? 0 : kHomeGap / 2,
                kHomeGutter,
                0,
              ),
              child: ContinueTile(item: item, lead: i == 0),
            ),
      ],
    );
  }
}

/// Plays [item] from where it stopped, or its course's next session. Home's
/// Continue and the Library's In progress both start this way.
Future<void> startContinueItem(
  BuildContext context,
  WidgetRef ref,
  ContinueItem item,
) async {
  // The course Continue shows it under, for its cue scope and for where it
  // counts: startSession writes it before the session starts, which reads it.
  // An item with no course forgets the one it was last opened from.
  await startSession(
    context,
    ref,
    trackId: item.trackId,
    path: item.path,
    courseId: item.courseId,
  );
}

/// One thing in progress, as a card. The first ([lead]) is drawn on the
/// primary container: it is what Home most expects the user to want.
class ContinueTile extends ConsumerWidget {
  const ContinueTile({super.key, required this.item, this.lead = false});

  final ContinueItem item;
  final bool lead;

  String _subtitle(AppLocalizations l10n) {
    final parts = [
      if (item.courseTitle.isNotEmpty) item.courseTitle,
      if (item.sessionNumber != null && item.sessionTotal != null)
        l10n.homeContinueSessionOf(item.sessionNumber!, item.sessionTotal!),
      if (item.resume != null &&
          item.resume!.durationMs > item.resume!.positionMs)
        l10n.homeContinueTimeLeft(
          formatClock(item.resume!.durationMs - item.resume!.positionMs),
        ),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final label = item.resume != null
        ? l10n.homeContinueResume
        : l10n.homeContinueStart;
    final subtitle = _subtitle(l10n);
    Future<void> start() => startContinueItem(context, ref, item);

    final scheme = theme.colorScheme;
    final type = context.typography;
    final fill = lead ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final onFill = lead ? scheme.onPrimaryContainer : scheme.onSurface;
    final muted = lead
        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final buttonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      visualDensity: VisualDensity.compact,
      textStyle: type.emphasized.labelLarge,
    );

    return Semantics(
      button: true,
      label: '$label: ${item.title}. $subtitle',
      excludeSemantics: true,
      onTap: start,
      child: HomePressable(
        key: ValueKey('continue_${item.trackId}'),
        color: fill,
        radius: kHomeCardRadius,
        onTap: start,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(kHomeArtRadius),
                child: SizedBox.square(
                  dimension: 64,
                  child: NetworkImageWidget(
                    url: item.coverUrl,
                    art: item.courseId != null
                        ? courseArt(item.courseId!)
                        : singleArt(item.trackId),
                    shouldCache: true,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: type.emphasized.titleMedium?.copyWith(
                        color: onFill,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: type.baseline.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              lead
                  ? FilledButton.icon(
                      key: ValueKey('continue_play_${item.trackId}'),
                      style: buttonStyle,
                      onPressed: start,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(label),
                    )
                  : FilledButton.tonal(
                      key: ValueKey('continue_play_${item.trackId}'),
                      style: buttonStyle,
                      onPressed: start,
                      child: Text(label),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
