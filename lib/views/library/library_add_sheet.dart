import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';

enum _LibraryAdd { import, newPlaylist }

/// The "+" in the Home, Explore and Library headers: everything that adds
/// to the library or makes something new in it, in one short sheet (#62).
/// Import (a link, a feed, a YouTube playlist or files) and New playlist.
/// Home gains tiles and cards only by pinning. The sheet closes before the choice runs, so the
/// choice can open a screen or a dialog.
Future<void> showLibraryAddSheet(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final choice = await showModalBottomSheet<_LibraryAdd>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          key: const ValueKey('library_add_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.importTitle,
                  style: Theme.of(sheet).textTheme.titleMedium,
                ),
              ),
            ),
            ListTile(
              key: const ValueKey('library_add_import'),
              leading: const Icon(Icons.add_link_rounded),
              title: Text(l10n.libraryAddImport),
              subtitle: Text(l10n.libraryAddImportHint),
              onTap: () => Navigator.of(sheet).pop(_LibraryAdd.import),
            ),
            ListTile(
              key: const ValueKey('library_add_new_playlist'),
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(l10n.myCourseNew),
              subtitle: Text(l10n.libraryAddNewPlaylistHint),
              onTap: () => Navigator.of(sheet).pop(_LibraryAdd.newPlaylist),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _LibraryAdd.import:
      await openImport(context, ref);
    case _LibraryAdd.newPlaylist:
      await newMyCourse(context, ref);
  }
}

/// The headers' "+", opening [showLibraryAddSheet]. [key] tells them apart
/// (`home_add`, `explore_add`, `library_add`).
class LibraryAddButton extends ConsumerWidget {
  const LibraryAddButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton.filledTonal(
    tooltip: AppLocalizations.of(context)!.importTitle,
    onPressed: () => showLibraryAddSheet(context, ref),
    icon: const Icon(Icons.add_rounded),
  );
}
