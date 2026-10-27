import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/favorites/favorites_provider.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/my_courses/my_course_edit_view.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/network_image_widget.dart';
import 'package:medito/widgets/snackbar_widget.dart';

/// Opens a course page.
Future<void> openCourse(BuildContext context, WidgetRef ref, String id) =>
    handleNavigation(TypeConstants.pack, [id, '/packs/$id'], context, ref: ref);

/// Opens the edit screen for a personal course.
Future<void> openMyCourseEditor(BuildContext context, String id) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MyCourseEditView(courseId: id)),
    );

/// Asks for a name and a kind, makes the course, and returns its ID; null
/// when the user cancels.
Future<String?> createMyCourse(
  BuildContext context,
  WidgetRef ref, {
  List<MyItemDraft> items = const [],
}) async {
  final l10n = AppLocalizations.of(context)!;
  final answer = await showDialog<(String, LibraryGroup)>(
    context: context,
    builder: (_) => const _NewCourseDialog(),
  );
  if (answer == null) return null;
  final (title, group) = answer;
  return ref
      .read(myCourseSourceProvider)
      .create(
        title: title.trim().isEmpty ? l10n.myCourseDefaultTitle : title,
        group: group,
        lines: [for (final item in items) MyCourseLine.session(item)],
      );
}

/// The Library tab's "New course": make one, then open it.
Future<void> newMyCourse(BuildContext context, WidgetRef ref) async {
  final id = await createMyCourse(context, ref);
  if (id != null && context.mounted) await openCourse(context, ref, id);
}

/// "Add to course…" for a session or a whole course with ID [id]. Lists the
/// user's courses and a new one. [fallback] describes a session in case its
/// source cannot be read just now.
Future<void> showAddToCourse(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  MyItemDraft? fallback,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final source = ref.read(myCourseSourceProvider);
  final List<MyItemDraft> items;
  try {
    items = await source.itemsFor(id, fallback: fallback);
  } catch (e, st) {
    AppLogger.e('MY_COURSES', 'Could not read $id to add it', e, st);
    if (context.mounted) showSnackBar(context, l10n.myCourseAddFailed);
    return;
  }
  if (!context.mounted) return;
  if (items.isEmpty) {
    showSnackBar(context, l10n.myCourseNothingToAdd);
    return;
  }
  final courses = await source.courses(
    containing: [for (final item in items) item.id],
  );
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _AddToCourseSheet(
      // Adding a course to itself is no use.
      courses: [
        for (final course in courses)
          if (course.id != id) course,
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  try {
    if (choice.newCourse) {
      final created = await createMyCourse(context, ref, items: items);
      if (created == null || !context.mounted) return;
      final title =
          (await ref.read(libraryStoreProvider).entry(created))?.displayTitle;
      if (context.mounted) {
        _addedSnack(context, l10n, items.length, title ?? '', created, ref);
      }
      return;
    }
    final course = choice.course!;
    final added = await source.addItems(course.id, items);
    if (!context.mounted) return;
    if (added == 0) {
      showSnackBar(context, l10n.myCourseAlreadyIn(course.title));
    } else {
      _addedSnack(context, l10n, added, course.title, course.id, ref);
    }
  } catch (e, st) {
    AppLogger.e('MY_COURSES', 'Could not add $id', e, st);
    if (context.mounted) showSnackBar(context, l10n.myCourseAddFailed);
  }
}

void _addedSnack(
  BuildContext context,
  AppLocalizations l10n,
  int count,
  String title,
  String courseId,
  WidgetRef ref,
) => showSnackBar(
  context,
  count == 1
      ? l10n.myCourseAddedSnack(title)
      : l10n.myCourseAddedCountSnack(count, title),
  actionLabel: l10n.open,
  onActionPressed: () => openCourse(context, ref, courseId),
);

/// Copies the course [packId] into a new personal course and opens it for
/// editing; the original is left as it is.
Future<void> duplicateAsMyCourse(
  BuildContext context,
  WidgetRef ref, {
  required String packId,
  required String title,
}) async {
  final l10n = AppLocalizations.of(context)!;
  try {
    final id = await ref
        .read(myCourseSourceProvider)
        .duplicate(packId, title: l10n.myCourseCopyTitle(title));
    if (!context.mounted) return;
    // The page opens under the editor, so Back from the editor lands on the
    // copy. Awaiting the page would hold the editor until it was closed.
    unawaited(openCourse(context, ref, id));
    await openMyCourseEditor(context, id);
  } catch (e, st) {
    AppLogger.e('MY_COURSES', 'Could not copy $packId', e, st);
    if (context.mounted) showSnackBar(context, l10n.myCourseDuplicateFailed);
  }
}

/// Asks, then deletes a personal course. Returns whether it was deleted.
Future<bool> deleteMyCourse(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.myCourseDeleteTitle),
      content: Text(l10n.myCourseDeleteBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('my_course_delete_confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.myCourseDelete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await ref.read(myCourseSourceProvider).delete(id);
  await ref.read(pinnedCoursesProvider.notifier).unpin(id);
  try {
    await ref.read(favoritesNotifierProvider.notifier).removeFromFavorites(id);
  } catch (e, st) {
    AppLogger.e('MY_COURSES', 'Could not unfavourite $id', e, st);
  }
  if (context.mounted) showSnackBar(context, l10n.myCourseDeletedSnack);
  return true;
}

/// What a row's "⋮" or a page's actions sheet offers for [id].
enum ContentAction { edit, addToCourse, duplicate, removeFromCourse, delete }

/// The actions for [id], in menu order. A personal course can be edited and
/// deleted; any course can be copied into a personal one; a session listed
/// in the personal course [inCourse] can be taken out of it.
List<ContentAction> contentActionsFor(String id, {String? inCourse}) => [
  if (isMyCourseId(id)) ContentAction.edit,
  ContentAction.addToCourse,
  if (isCourseId(id)) ContentAction.duplicate,
  if (inCourse != null && isMyCourseId(inCourse))
    ContentAction.removeFromCourse,
  if (isMyCourseId(id)) ContentAction.delete,
];

String _actionLabel(AppLocalizations l10n, ContentAction action) =>
    switch (action) {
      ContentAction.edit => l10n.myCourseEdit,
      ContentAction.addToCourse => l10n.myCourseAddTo,
      ContentAction.duplicate => l10n.myCourseDuplicate,
      ContentAction.removeFromCourse => l10n.myCourseRemoveRow,
      ContentAction.delete => l10n.myCourseDelete,
    };

IconData _actionIcon(ContentAction action) => switch (action) {
  ContentAction.edit => Icons.edit_rounded,
  ContentAction.addToCourse => Icons.playlist_add_rounded,
  ContentAction.duplicate => Icons.copy_all_rounded,
  ContentAction.removeFromCourse => Icons.playlist_remove_rounded,
  ContentAction.delete => Icons.delete_outline_rounded,
};

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  ContentAction action, {
  required String id,
  required String title,
  MyItemDraft? fallback,
  String? inCourse,
}) async {
  switch (action) {
    case ContentAction.edit:
      return openMyCourseEditor(context, id);
    case ContentAction.addToCourse:
      return showAddToCourse(context, ref, id: id, fallback: fallback);
    case ContentAction.duplicate:
      return duplicateAsMyCourse(context, ref, packId: id, title: title);
    case ContentAction.removeFromCourse:
      final l10n = AppLocalizations.of(context)!;
      await ref.read(myCourseSourceProvider).removeItem(inCourse!, id);
      if (context.mounted) showSnackBar(context, l10n.myCourseRemovedSnack);
    case ContentAction.delete:
      if (await deleteMyCourse(context, ref, id) && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
  }
}

/// A row's "⋮": Add to course…, and more for a course (see
/// [contentActionsFor]).
class ContentActionsButton extends ConsumerWidget {
  const ContentActionsButton({
    super.key,
    required this.id,
    this.title = '',
    this.fallback,
    this.inCourse,
  });

  final String id;

  /// The course's title, for its copy's name.
  final String title;

  /// Describes a session in case its source cannot be read when adding it.
  final MyItemDraft? fallback;

  /// The personal course this row is listed in, if any.
  final String? inCourse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<ContentAction>(
      key: ValueKey('content_actions_$id'),
      tooltip: l10n.myCourseMore,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) => _run(
        context,
        ref,
        action,
        id: id,
        title: title,
        fallback: fallback,
        inCourse: inCourse,
      ),
      itemBuilder: (context) => [
        for (final action in contentActionsFor(id, inCourse: inCourse))
          PopupMenuItem(
            key: ValueKey('content_action_${action.name}'),
            value: action,
            child: Text(_actionLabel(l10n, action)),
          ),
      ],
    );
  }
}

/// The same actions as a bottom sheet, for a course or session page.
Future<void> showContentActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  String title = '',
  MyItemDraft? fallback,
}) async {
  final actions = contentActionsFor(id);
  if (actions.length == 1) {
    return _run(
      context,
      ref,
      actions.single,
      id: id,
      title: title,
      fallback: fallback,
    );
  }
  final l10n = AppLocalizations.of(context)!;
  final action = await showModalBottomSheet<ContentAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            ListTile(
              key: ValueKey('sheet_${action.name}'),
              leading: Icon(_actionIcon(action)),
              title: Text(_actionLabel(l10n, action)),
              onTap: () => Navigator.pop(context, action),
            ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  return _run(context, ref, action, id: id, title: title, fallback: fallback);
}

class _Choice {
  const _Choice.course(MyCourseSummary this.course) : newCourse = false;
  const _Choice.newCourse() : course = null, newCourse = true;

  final MyCourseSummary? course;
  final bool newCourse;
}

class _AddToCourseSheet extends StatelessWidget {
  const _AddToCourseSheet({required this.courses});

  final List<MyCourseSummary> courses;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.myCourseAddToTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            ListTile(
              key: const ValueKey('add_to_new_course'),
              leading: const SizedBox.square(
                dimension: 48,
                child: Icon(Icons.add_rounded),
              ),
              title: Text(l10n.myCourseNew),
              subtitle: courses.isEmpty ? Text(l10n.myCourseNoneYet) : null,
              onTap: () => Navigator.pop(context, const _Choice.newCourse()),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final course in courses)
                    ListTile(
                      key: ValueKey('add_to_${course.id}'),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox.square(
                          dimension: 48,
                          child: NetworkImageWidget(
                            url: course.coverUrl,
                            art: courseArt(course.id),
                          ),
                        ),
                      ),
                      title: Text(
                        course.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(l10n.librarySessions(course.sessionCount)),
                      trailing: course.contains
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () =>
                          Navigator.pop(context, _Choice.course(course)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _NewCourseDialog extends StatefulWidget {
  const _NewCourseDialog();

  @override
  State<_NewCourseDialog> createState() => _NewCourseDialogState();
}

class _NewCourseDialogState extends State<_NewCourseDialog> {
  final _controller = TextEditingController();
  var _group = LibraryGroup.practice;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, (_controller.text, _group));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.myCourseNew),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('new_course_name'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: l10n.myCourseNameHint),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          MyCourseKindPicker(
            value: _group,
            onChanged: (group) => setState(() => _group = group),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('new_course_create'),
          onPressed: _submit,
          child: Text(l10n.myCourseCreate),
        ),
      ],
    );
  }
}

/// Practice or Talks, Practice first.
class MyCourseKindPicker extends StatelessWidget {
  const MyCourseKindPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LibraryGroup value;
  final ValueChanged<LibraryGroup> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SegmentedButton<LibraryGroup>(
      key: const ValueKey('my_course_kind'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: LibraryGroup.practice,
          label: Text(l10n.libraryPractice),
        ),
        ButtonSegment(
          value: LibraryGroup.talks,
          label: Text(l10n.libraryTalks),
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
