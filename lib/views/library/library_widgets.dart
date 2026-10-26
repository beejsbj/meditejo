import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/library/library_view_provider.dart';
import 'package:medito/providers/meditation/downloaded_track_ids_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/views/home/widgets/continue/continue_section.dart';
import 'package:medito/views/library/library_actions.dart';
import 'package:medito/views/library/library_format.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/widgets/cards/card_art.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/course_card.dart';
import 'package:medito/widgets/cards/session_row.dart';
import 'package:medito/widgets/cards/section_title.dart';
import 'package:medito/widgets/cards/teacher_tiles.dart';

/// Where a library entry came from, as its card's overline: "Dharma Seed",
/// "YouTube", "Playlist" (what the user made) or "Imported" (a link or files
/// of their own). Null when the source is not known.
String? librarySourceLabel(AppLocalizations l10n, String id) {
  if (isMyCourseId(id)) return l10n.playlistKind;
  if (id.startsWith(dharmaSeedPrefix)) return 'Dharma Seed';
  if (id.startsWith('yt-')) return 'YouTube';
  if (id.startsWith(libPrefix)) return l10n.librarySourceImported;
  return null;
}

/// "3 of 12" with its bar, for a course the user has started; null otherwise.
CardProgress? libraryProgress(
  WidgetRef ref,
  AppLocalizations l10n,
  LibraryEntry entry,
) {
  if (entry.kind != LibraryKind.course) return null;
  final p = ref.watch(libraryProgressProvider)[entry.sourceId];
  if (p == null) return null;
  return CardProgress.of(p.done, p.total, l10n.upNextProgress(p.done, p.total));
}

/// A mark on a course pinned to Home.
class _PinMark extends StatelessWidget {
  const _PinMark({this.disc = false});

  final bool disc;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(
      Icons.push_pin_rounded,
      size: 18,
      color: scheme.primary,
      semanticLabel: AppLocalizations.of(context)!.libraryPinned,
    );
    if (!disc) {
      return Padding(padding: const EdgeInsets.only(left: 4), child: icon);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
      child: Padding(padding: const EdgeInsets.all(6), child: icon),
    );
  }
}

/// One thing in the library, in the list layout: a course or playlist as a
/// wide card with its source and progress, a single as a compact row, a
/// teacher as a row with their photo. Each keeps its menu; tapping opens it.
class LibraryEntryTile extends ConsumerWidget {
  const LibraryEntryTile({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    void open() => openLibraryEntry(context, ref, entry);
    final menu = LibraryEntryMenu(entry: entry);
    final key = ValueKey('library_${entry.sourceId}');

    switch (entry.kind) {
      case LibraryKind.course:
        final pinned = ref
            .watch(pinnedCoursesProvider)
            .contains(entry.sourceId);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            kCardGutter,
            0,
            kCardGutter,
            kCardGap / 2,
          ),
          child: CourseRowCard(
            key: key,
            title: entry.displayTitle,
            overline: librarySourceLabel(l10n, entry.sourceId),
            detail: entry.subtitle,
            progress: libraryProgress(ref, l10n, entry),
            art: CardArt(
              url: entry.coverUrl,
              seed: entry.displayTitle,
              portrait: hasPortraitCover(entry.sourceId),
              avatarSize: 28,
            ),
            onTap: open,
            trailing: [if (pinned) const _PinMark(), menu],
          ),
        );
      case LibraryKind.single:
        final played = {
          ...?ref.watch(statsProvider).value?.tracksChecked,
        }.contains(entry.sourceId);
        return SessionRow(
          key: key,
          title: entry.displayTitle,
          detail: entry.subtitle,
          artUrl: entry.coverUrl,
          artSeed: entry.displayTitle,
          portrait: hasPortraitCover(entry.sourceId),
          completed: played,
          downloaded: ref
              .watch(downloadedTrackIdsProvider)
              .contains(entry.sourceId),
          onTap: open,
          trailing: [menu],
        );
      case LibraryKind.teacher:
        return TeacherRow(
          key: key,
          name: entry.displayTitle,
          photoUrl: entry.coverUrl,
          detail: entry.subtitle,
          onTap: open,
          trailing: [menu],
        );
    }
  }
}

/// A course or playlist in the grid layout: art, source, name, detail and
/// progress, with its menu on the art.
class LibraryEntryCard extends ConsumerWidget {
  const LibraryEntryCard({super.key, required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pinned = ref.watch(pinnedCoursesProvider).contains(entry.sourceId);
    return CourseCard(
      key: ValueKey('library_${entry.sourceId}'),
      title: entry.displayTitle,
      overline: librarySourceLabel(l10n, entry.sourceId),
      detail: entry.subtitle,
      progress: libraryProgress(ref, l10n, entry),
      art: CardArt(
        url: entry.coverUrl,
        seed: entry.displayTitle,
        portrait: hasPortraitCover(entry.sourceId),
        avatarSize: 32,
      ),
      onTap: () => openLibraryEntry(context, ref, entry),
      action: LibraryEntryMenu(entry: entry),
      badge: pinned ? const _PinMark(disc: true) : null,
    );
  }
}

/// Something in progress, as a large card: the session, its course, how far
/// along, and Play. Tapping anywhere starts it, as on Home.
class InProgressCard extends ConsumerWidget {
  const InProgressCard({super.key, required this.item});

  final ContinueItem item;

  static const width = 280.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final resume = item.resume;
    final left = resume != null && resume.durationMs > resume.positionMs
        ? l10n.homeContinueTimeLeft(
            formatClock(resume.durationMs - resume.positionMs),
          )
        : null;
    final total = item.sessionTotal ?? 0;
    final progress =
        CardProgress.of(
          item.completedSessions,
          total,
          l10n.upNextProgress(item.completedSessions, total),
        ) ??
        (resume == null || resume.durationMs <= 0 || left == null
            ? null
            : CardProgress(resume.positionMs / resume.durationMs, left));
    final label = resume != null
        ? l10n.homeContinueResume
        : l10n.homeContinueStart;
    void start() => startContinueItem(context, ref, item);
    final courseId = item.courseId;

    return SizedBox(
      width: width,
      child: CourseCard(
        key: ValueKey('in_progress_${item.trackId}'),
        size: CourseCardSize.large,
        title: item.title,
        overline: item.courseTitle,
        detail: [
          if (item.sessionNumber != null && item.sessionTotal != null)
            l10n.homeContinueSessionOf(item.sessionNumber!, item.sessionTotal!),
          if (left != null && progress?.label != left) left,
        ].join(' · '),
        progress: progress,
        art: CardArt(
          url: item.coverUrl,
          seed: item.courseTitle.isEmpty ? item.title : item.courseTitle,
          portrait: hasPortraitCover(courseId ?? item.trackId),
        ),
        onTap: start,
        action: IconButton(
          key: ValueKey('in_progress_play_${item.trackId}'),
          tooltip: label,
          onPressed: start,
          icon: const Icon(Icons.play_arrow_rounded),
        ),
      ),
    );
  }
}

/// The Library's In progress: everything started and not finished, as a
/// strip of large cards. Hidden when nothing is in progress.
class InProgressStrip extends ConsumerWidget {
  const InProgressStrip({super.key, required this.items});

  final List<ContinueItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(l10n.libraryInProgress),
        SizedBox(
          height: CourseCard.heightFor(
            context,
            width: InProgressCard.width,
            size: CourseCardSize.large,
            progress: true,
          ),
          child: ListView.separated(
            key: const ValueKey('library_in_progress'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: kCardGutter),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: kCardGap),
            itemBuilder: (context, i) => InProgressCard(item: items[i]),
          ),
        ),
      ],
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
