import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/library/library_actions.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// "3 of 12" for a course the user has started; null otherwise.
String? libraryProgressText(
  WidgetRef ref,
  AppLocalizations l10n,
  LibraryEntry entry,
) {
  if (entry.kind != LibraryKind.course) return null;
  final trackIds = ref.watch(packTrackIdsProvider).value?[entry.sourceId];
  final checked = ref.watch(statsProvider).value?.tracksChecked;
  if (trackIds == null || trackIds.isEmpty || checked == null) return null;
  final done = trackIds.where(checked.contains).length;
  return done == 0 ? null : l10n.upNextProgress(done, trackIds.length);
}

/// One thing in the library, as a row: artwork, name, a line of detail and a
/// menu. Tapping opens it.
class LibraryEntryTile extends ConsumerWidget {
  const LibraryEntryTile({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final progress = libraryProgressText(ref, l10n, entry);
    final detail = [
      if (entry.subtitle.isNotEmpty) entry.subtitle,
      ?progress,
    ].join(' · ');

    return Semantics(
      container: true,
      child: InkWell(
        key: ValueKey('library_${entry.sourceId}'),
        onTap: () => openLibraryEntry(context, ref, entry),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(padding16, 8, 4, 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    entry.kind == LibraryKind.teacher ? 28 : 10,
                  ),
                  child: SizedBox.square(
                    dimension: 56,
                    child: NetworkImageWidget(
                      url: entry.coverUrl,
                      shouldCache: true,
                      seed: entry.displayTitle,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                LibraryEntryMenu(entry: entry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reclassify, rename or remove an entry.
class LibraryEntryMenu extends ConsumerWidget {
  const LibraryEntryMenu({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isTeacher = entry.kind == LibraryKind.teacher;
    return PopupMenuButton<_Action>(
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) => switch (action) {
        _Action.toPractice => setLibraryGroup(
          ref,
          entry,
          LibraryGroup.practice,
        ),
        _Action.toTalks => setLibraryGroup(ref, entry, LibraryGroup.talks),
        _Action.rename => renameLibraryEntry(context, ref, entry),
        _Action.remove => removeFromLibrary(context, ref, entry),
      },
      itemBuilder: (context) => [
        if (!isTeacher && entry.group == LibraryGroup.talks)
          PopupMenuItem(
            value: _Action.toPractice,
            child: Text(l10n.libraryMoveToPractice),
          ),
        if (!isTeacher && entry.group == LibraryGroup.practice)
          PopupMenuItem(
            value: _Action.toTalks,
            child: Text(l10n.libraryMoveToTalks),
          ),
        if (!isTeacher)
          PopupMenuItem(value: _Action.rename, child: Text(l10n.libraryRename)),
        PopupMenuItem(value: _Action.remove, child: Text(l10n.libraryRemove)),
      ],
    );
  }
}

enum _Action { toPractice, toTalks, rename, remove }

/// A square card for the Home rail: artwork, name, and what it is.
class LibraryRailCard extends ConsumerWidget {
  const LibraryRailCard({super.key, required this.entry});

  final LibraryEntry entry;

  static const width = 140.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final group = entry.group == LibraryGroup.practice
        ? l10n.libraryPractice
        : l10n.libraryTalks;
    return SizedBox(
      width: width,
      child: InkWell(
        key: ValueKey('library_card_${entry.sourceId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => openLibraryEntry(context, ref, entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.square(
                dimension: width,
                child: NetworkImageWidget(
                  url: entry.coverUrl,
                  shouldCache: true,
                  seed: entry.displayTitle,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            Text(
              group,
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
