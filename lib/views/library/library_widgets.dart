import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/library/library_actions.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/my_courses/playlist_label.dart';
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
      ?playlistAwareDetail(l10n, entry.sourceId, entry.subtitle),
      ?progress,
    ].where((part) => part.isNotEmpty).join(' · ');

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

/// Edit or copy a course, add to a personal course, reclassify, rename, pin,
/// or remove an entry. A personal course is deleted rather than removed: it
/// exists nowhere else.
class LibraryEntryMenu extends ConsumerWidget {
  const LibraryEntryMenu({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isTeacher = entry.kind == LibraryKind.teacher;
    final mine = isMyCourseId(entry.sourceId);
    return PopupMenuButton<_Action>(
      key: ValueKey('library_menu_${entry.sourceId}'),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) => switch (action) {
        _Action.edit => openMyCourseEditor(context, entry.sourceId),
        _Action.addToCourse => showAddToCourse(
          context,
          ref,
          id: entry.sourceId,
        ),
        _Action.duplicate => duplicateAsMyCourse(
          context,
          ref,
          packId: entry.sourceId,
          title: entry.displayTitle,
        ),
        _Action.delete => deleteMyCourse(context, ref, entry.sourceId),
        _Action.toPractice => setLibraryGroup(
          ref,
          entry,
          LibraryGroup.practice,
        ),
        _Action.toTalks => setLibraryGroup(ref, entry, LibraryGroup.talks),
        _Action.rename => renameLibraryEntry(context, ref, entry),
        _Action.pin => togglePinnedCourse(context, ref, entry.sourceId),
        _Action.remove => removeFromLibrary(context, ref, entry),
      },
      itemBuilder: (context) => [
        if (mine)
          PopupMenuItem(
            key: const ValueKey('library_menu_edit'),
            value: _Action.edit,
            child: Text(l10n.myCourseEdit),
          ),
        if (!isTeacher)
          PopupMenuItem(
            key: const ValueKey('library_menu_add_to_course'),
            value: _Action.addToCourse,
            child: Text(l10n.myCourseAddTo),
          ),
        if (entry.isCourse)
          PopupMenuItem(
            key: const ValueKey('library_menu_duplicate'),
            value: _Action.duplicate,
            child: Text(l10n.myCourseDuplicate),
          ),
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
        if (entry.isCourse)
          PopupMenuItem(
            key: const ValueKey('library_menu_pin'),
            value: _Action.pin,
            child: Text(
              ref.read(pinnedCoursesProvider).contains(entry.sourceId)
                  ? l10n.unpinCourse
                  : l10n.pinCourse,
            ),
          ),
        if (mine)
          PopupMenuItem(
            key: const ValueKey('library_menu_delete'),
            value: _Action.delete,
            child: Text(l10n.myCourseDelete),
          )
        else
          PopupMenuItem(value: _Action.remove, child: Text(l10n.libraryRemove)),
      ],
    );
  }
}

enum _Action {
  edit,
  addToCourse,
  duplicate,
  toPractice,
  toTalks,
  rename,
  pin,
  remove,
  delete,
}

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
