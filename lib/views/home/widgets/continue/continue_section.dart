import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/library/library_format.dart';
import 'package:medito/views/player/start_session.dart';
import 'package:medito/widgets/network_image_widget.dart';
import 'package:medito/widgets/section_header.dart';

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
        SectionHeader(title: l10n.upNextTitle),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: padding16),
            child: Text(
              l10n.homeContinueEmpty,
              key: const ValueKey('continue_empty'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          for (final item in items) ContinueTile(item: item),
      ],
    );
  }
}

class ContinueTile extends ConsumerWidget {
  const ContinueTile({super.key, required this.item});

  final ContinueItem item;

  String _subtitle(AppLocalizations l10n) {
    final parts = [
      if (item.courseTitle.isNotEmpty) item.courseTitle,
      if (item.sessionNumber != null && item.sessionTotal != null)
        l10n.homeContinueSessionOf(item.sessionNumber!, item.sessionTotal!),
      if (item.resume != null && item.resume!.durationMs > item.resume!.positionMs)
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
    Future<void> start() async {
      // The course Continue shows it under, for its cue scope and for where
      // it counts: written before the session starts, which reads it.
      final courseId = item.courseId;
      if (courseId != null) {
        try {
          await ref
              .read(libraryStoreProvider)
              .noteSessionContext(item.trackId, courseId);
        } catch (e, st) {
          AppLogger.e('HOME', 'Could not note the course of a session', e, st);
        }
      }
      if (!context.mounted) return;
      await startSession(context, ref, trackId: item.trackId, path: item.path);
    }

    return Semantics(
      button: true,
      label: '$label: ${item.title}. $subtitle',
      excludeSemantics: true,
      onTap: start,
      child: InkWell(
        key: ValueKey('continue_${item.trackId}'),
        onTap: start,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: padding16,
            vertical: padding8,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 56,
                  child: NetworkImageWidget(
                    url: item.coverUrl,
                    seed: item.courseTitle.isEmpty
                        ? item.title
                        : item.courseTitle,
                    shouldCache: true,
                  ),
                ),
              ),
              const SizedBox(width: padding16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: padding8),
              FilledButton.tonal(
                key: ValueKey('continue_play_${item.trackId}'),
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
