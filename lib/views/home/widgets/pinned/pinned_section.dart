import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// Up to three courses the user pinned, each with where they are in it.
/// Hidden when nothing is pinned.
class PinnedSection extends ConsumerWidget {
  const PinnedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(pinnedCoursesProvider);
    if (ids.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(l10n.homePinnedTitle),
        for (final (i, id) in ids.indexed)
          Padding(
            padding: EdgeInsets.fromLTRB(
              kHomeGutter,
              i == 0 ? 0 : kHomeGap / 2,
              kHomeGutter,
              0,
            ),
            child: PinnedCourseTile(key: ValueKey('pinned_$id'), id: id),
          ),
      ],
    );
  }
}

class PinnedCourseTile extends ConsumerWidget {
  const PinnedCourseTile({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = ref.watch(packProvider(packId: id)).value;
    final entries = ref.watch(libraryEntriesProvider).value;
    final entry = entries?.where((e) => e.sourceId == id).firstOrNull;
    final title = entry?.displayTitle ?? pack?.title ?? id;
    // Even an unavailable course keeps an Unpin control, so stale pins cannot
    // consume the three slots forever.
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    // As the course page counts: a session its source has lost is not one.
    final playable = pack?.playableTracks ?? const [];
    final total = playable.length;
    final done = playable.where((i) => i.isCompleted == true).length;

    final scheme = theme.colorScheme;
    final type = context.typography;
    void open() => handleNavigation(
      TypeConstants.pack,
      [id, '/packs/$id'],
      context,
      ref: ref,
    );

    return HomePressable(
      color: scheme.surfaceContainer,
      radius: kHomeCardRadius,
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(kHomeArtRadius),
              child: SizedBox.square(
                dimension: 56,
                child: NetworkImageWidget(
                  url: pack?.coverUrl ?? '',
                  art: courseArt(id),
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
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.emphasized.titleMedium,
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: done / total,
                            borderRadius: BorderRadius.circular(4),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          l10n.upNextProgress(done, total),
                          style: type.baseline.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.unpinCourse,
              onPressed: () =>
                  ref.read(pinnedCoursesProvider.notifier).unpin(id),
              icon: Icon(Icons.push_pin_rounded, color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}
