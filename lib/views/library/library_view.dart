import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/library/library_widgets.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/section_header.dart';

/// Everything the user has added, with Practice before Talks and followed
/// teachers apart. It is a screen of its own, reached from Home, rather than
/// a fifth tab: the tab bar stays as it is, and the library is what Home
/// already leads with.
class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sections = ref.watch(librarySectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              key: const ValueKey('library_add'),
              onPressed: () => openImport(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.libraryAdd),
            ),
          ),
        ],
      ),
      body: AdaptivePageBody(
        maxWidth: 760,
        child: sections.when(
          data: (data) => data.isEmpty
              ? _Empty(onAdd: () => openImport(context, ref))
              : _Sections(sections: data),
          error: (_, _) => _Empty(onAdd: () => openImport(context, ref)),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({required this.sections});

  final LibrarySections sections;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + padding24,
      ),
      children: [
        if (sections.practice.isNotEmpty) ...[
          SectionHeader(title: l10n.libraryPractice),
          for (final entry in sections.practice) LibraryEntryTile(entry: entry),
        ],
        if (sections.talks.isNotEmpty) ...[
          SectionHeader(title: l10n.libraryTalks),
          for (final entry in sections.talks) LibraryEntryTile(entry: entry),
        ],
        if (sections.teachers.isNotEmpty) ...[
          SectionHeader(title: l10n.libraryTeachers),
          for (final entry in sections.teachers) LibraryEntryTile(entry: entry),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(padding24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.libraryEmptyTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.libraryEmptyBody,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: padding24),
            FilledButton.icon(
              key: const ValueKey('library_empty_add'),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.importTitle),
            ),
          ],
        ),
      ),
    );
  }
}
