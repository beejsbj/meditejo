import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/library/library_view_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/scaffold_messenger_key.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/library/item_actions.dart';
import 'package:medito/widgets/snackbar_widget.dart';

/// Opens a library entry on its own page: a course, a single or a teacher.
Future<void> openLibraryEntry(
  BuildContext context,
  WidgetRef ref,
  LibraryEntry entry,
) => openLibraryId(context, ref, entry.sourceId, entry.kind);

Future<void> openLibraryId(
  BuildContext context,
  WidgetRef ref,
  String id,
  LibraryKind kind,
) {
  final type = switch (kind) {
    LibraryKind.course => TypeConstants.pack,
    LibraryKind.single => TypeConstants.track,
    LibraryKind.teacher => TypeConstants.teacher,
  };
  final path = switch (kind) {
    LibraryKind.course => '/packs/$id',
    LibraryKind.single => '/tracks/$id',
    LibraryKind.teacher => id,
  };
  return handleNavigation(type, [id, path], context, ref: ref);
}

/// Moves an entry to Practice or to Talks. The choice is kept even when it
/// is what the app detected, so a course of sittings and talks can be put
/// under one chip only (#80); the detection stays recorded, and
/// [clearLibraryGroup] goes back to it.
Future<void> setLibraryGroup(
  WidgetRef ref,
  LibraryEntry entry,
  LibraryGroup group,
) => ref.read(libraryStoreProvider).setGroup(entry.sourceId, group);

/// Forgets the user's Practice or Talks for an entry: the Library shows it by
/// its sessions again, and playback goes by what the app detected.
Future<void> clearLibraryGroup(WidgetRef ref, LibraryEntry entry) =>
    ref.read(libraryStoreProvider).setGroup(entry.sourceId, null);

/// Deletes the import [id] and takes what is gone off Home: a pin of
/// something deleted would only show an ID. A course takes its sessions' pins
/// with it; a session that belongs to a course only leaves the library, so
/// its pin stays.
Future<void> deleteImport(WidgetRef ref, String id) async {
  final pins = ref.read(pinnedCoursesProvider.notifier);
  final gone = await ref.read(libSourceProvider).remove(id);
  await pins.unpinAll(gone);
}

/// Asks, then removes. Imported audio is deleted with its entry, so that asks
/// first; a catalogue item is simply taken out, with Undo.
Future<void> removeFromLibrary(
  BuildContext context,
  WidgetRef ref,
  LibraryEntry entry,
) async {
  final l10n = AppLocalizations.of(context)!;
  final imported = entry.sourceId.startsWith(libPrefix);
  final store = ref.read(libraryStoreProvider);

  if (imported) {
    final listedIn = await _personalCoursesListing(ref, entry);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.libraryRemoveTitle),
        content: Text(
          [
            l10n.libraryRemoveImported,
            if (listedIn > 0) l10n.myCourseRemoveWarning(listedIn),
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.libraryRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await deleteImport(ref, entry.sourceId);
    if (context.mounted) showSnackBar(context, l10n.libraryRemovedSnack);
    return;
  }

  await store.remove(entry.sourceId);
  if (!context.mounted) return;
  showSnackBar(
    context,
    l10n.libraryRemovedSnack,
    actionLabel: l10n.undo,
    onActionPressed: () async {
      await store.add(
        LibraryDraft(
          sourceId: entry.sourceId,
          kind: entry.kind,
          title: entry.title,
          group: entry.detectedGroup,
          subtitle: entry.subtitle,
          coverUrl: entry.coverUrl,
          itemCount: entry.itemCount,
          durationMs: entry.durationMs,
          addedAt: entry.addedAt,
        ),
      );
      if (entry.groupOverride != null) {
        await store.setGroup(entry.sourceId, entry.groupOverride);
      }
      if (entry.titleOverride != null) {
        await store.setTitle(entry.sourceId, entry.titleOverride);
      }
    },
  );
}

/// How many personal courses list the imported [entry] or one of its
/// sessions: removing it leaves them there, unavailable.
Future<int> _personalCoursesListing(WidgetRef ref, LibraryEntry entry) async {
  try {
    final ids = entry.isCourse
        ? [
            for (final item
                in (await ref
                        .read(libraryContentRouterProvider)
                        .pack(entry.sourceId))
                    .items)
              item.id,
          ]
        : [entry.sourceId];
    // A session inside an imported course stays when it is removed on its own.
    if (isLibTrackId(entry.sourceId) &&
        await ref.read(libSourceProvider).parentOf(entry.sourceId) != null) {
      return 0;
    }
    final source = ref.read(myCourseSourceProvider);
    return <String>{
      for (final id in ids) ...await source.coursesHolding(id),
    }.length;
  } catch (e) {
    AppLogger.d('LIBRARY', 'Could not check courses for ${entry.sourceId}: $e');
    return 0;
  }
}

Future<void> renameLibraryEntry(
  BuildContext context,
  WidgetRef ref,
  LibraryEntry entry,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _RenameDialog(initial: entry.displayTitle),
  );
  if (name == null) return;
  // A personal course's title is its own, not an override.
  if (isMyCourseId(entry.sourceId)) {
    if (!context.mounted) return;
    final blank = AppLocalizations.of(context)!.myCourseDefaultTitle;
    return ref
        .read(myCourseSourceProvider)
        .rename(entry.sourceId, name.trim().isEmpty ? blank : name);
  }
  // Back to the source's own title when the new name is the same or blank.
  await ref
      .read(libraryStoreProvider)
      .setTitle(entry.sourceId, name.trim() == entry.title ? null : name);
}

/// Owns its text controller, so it is disposed only once the dialog's exit
/// animation is over.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.libraryRenameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: l10n.libraryRenameHint),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.libraryRenameSave),
        ),
      ],
    );
  }
}

/// Pins a course, playlist or ([session]) single session to Home, or takes
/// it off. Home shows the first three pins; a later one says it is under
/// "See all".
Future<void> togglePin(
  BuildContext context,
  WidgetRef ref,
  String id, {
  bool session = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final pins = ref.read(pinnedCoursesProvider.notifier);
  final pinned = ref.read(pinnedCoursesProvider);
  // Everything that needs the page is done before the first wait: the change
  // can take the control that asked for it off screen (an unpin in a list).
  // The snackbar goes through the app's messenger, so it outlives the page.
  final messenger = scaffoldMessengerKey.currentState;
  // Replace rather than queue, so a quick re-tap reads the end state.
  messenger?.hideCurrentSnackBar();
  final Future<void> saving;
  if (pinned.contains(id)) {
    final wasSession = pins.isSession(id);
    saving = pins.unpin(id);
    showSnackBar(
      context,
      l10n.homeUnpinned,
      actionLabel: l10n.undo,
      onActionPressed: () => pins.pinBack(id, pinned, session: wasSession),
    );
  } else {
    final onHome = pinned.length < PinnedCoursesNotifier.homeLimit;
    saving = pins.pin(id, session: session);
    showSnackBar(
      context,
      onHome ? l10n.pinnedCourseAdded : l10n.pinnedUnderSeeAll,
    );
  }
  await saving;
}

/// Opens the one actions sheet for a library entry (its "⋮" and long-press).
Future<void> showLibraryEntryActions(
  BuildContext context,
  WidgetRef ref,
  LibraryEntry entry,
) => showItemActions(
  context,
  ref,
  ItemActionsSpec(
    id: entry.sourceId,
    title: entry.title,
    entry: entry,
    // Where the Library's chips put it, so the menu offers the other.
    entryKinds: ref.read(libraryEntryKindsProvider).value?[entry.sourceId],
  ),
);
