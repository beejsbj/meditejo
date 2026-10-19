import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/library/library_widgets.dart';

/// The top of Home: what the user has added, practice first, with the one
/// Add button. Empty, it is an invitation to add the first thing.
class HomeLibrarySection extends ConsumerWidget {
  const HomeLibrarySection({super.key});

  static const _railLimit = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sections = ref.watch(librarySectionsProvider).value;
    if (sections == null) return const SizedBox.shrink();
    final entries = sections.contentFirstPractice;

    return Padding(
      padding: const EdgeInsets.only(top: padding16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: padding16),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.libraryTitle,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                ),
                if (!sections.isEmpty)
                  TextButton(
                    key: const ValueKey('library_see_all'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const LibraryView()),
                    ),
                    child: Text(l10n.librarySeeAll),
                  ),
                FilledButton.tonalIcon(
                  key: const ValueKey('home_library_add'),
                  onPressed: () => openImport(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.libraryAdd),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (sections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: padding16),
              child: Text(
                l10n.libraryEmptyHome,
                style: theme.textTheme.bodyMedium,
              ),
            )
          else if (entries.isNotEmpty)
            SizedBox(
              height: 214,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: padding16),
                itemCount: entries.length.clamp(0, _railLimit),
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    LibraryRailCard(entry: entries[index]),
              ),
            ),
        ],
      ),
    );
  }
}
