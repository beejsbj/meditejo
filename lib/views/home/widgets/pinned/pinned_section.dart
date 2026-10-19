import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/widgets/network_image_widget.dart';
import 'package:medito/widgets/section_header.dart';

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
        SectionHeader(title: l10n.homePinnedTitle),
        for (final id in ids) PinnedCourseTile(key: ValueKey('pinned_$id'), id: id),
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
    // A pin whose course is gone (removed, or its source unavailable) stays
    // saved but is not shown.
    if (pack == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final total = pack.items.length;
    final done = pack.items.where((i) => i.isCompleted == true).length;

    return InkWell(
      onTap: () => handleNavigation(
        TypeConstants.pack,
        [id, '/packs/$id'],
        context,
        ref: ref,
      ),
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
                  url: pack.coverUrl ?? '',
                  seed: pack.title,
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
                    pack.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (total > 0)
                    Text(
                      l10n.upNextProgress(done, total),
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
