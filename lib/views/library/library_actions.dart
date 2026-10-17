import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/services/library/library_models.dart';
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

/// Moves an entry between Practice and Talks. The app's own detection stays
/// recorded, so the change can be undone.
Future<void> setLibraryGroup(
  WidgetRef ref,
  LibraryEntry entry,
  LibraryGroup group,
) => ref
    .read(libraryStoreProvider)
    .setGroup(entry.sourceId, group == entry.detectedGroup ? null : group);

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.libraryRemoveTitle),
        content: Text(l10n.libraryRemoveImported),
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
    await ref.read(libSourceProvider).remove(entry.sourceId);
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
