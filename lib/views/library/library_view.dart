import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/library/library_view_provider.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/library/library_widgets.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/course_card.dart';
import 'package:medito/widgets/cards/filter_chip_bar.dart';
import 'package:medito/widgets/cards/section_title.dart';

/// Everything the user keeps and is working through. It is the Library tab.
///
/// From the top: what is in progress, as large cards; the kind filter (All,
/// Courses, Playlists, Singles, Teachers, Downloads); Practice or Talks, the
/// sort and the grid or list switch; then Practice before Talks (decision
/// 11), courses and playlists as cards, singles as rows, and saved teachers.
class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final entries = ref.watch(libraryEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        titleTextStyle: context.typography.emphasized.titleLarge,
        actions: [
          IconButton(
            key: const ValueKey('library_new_course'),
            tooltip: l10n.myCourseNew,
            onPressed: () => newMyCourse(context, ref),
            icon: const Icon(Icons.playlist_add_rounded),
          ),
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
        child: entries.when(
          data: (data) => data.isEmpty
              ? const _EmptyLibrary()
              : _LibraryBody(entries: data),
          error: (_, _) => const _EmptyLibrary(),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody({required this.entries});

  final List<LibraryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final options = ref.watch(libraryViewOptionsProvider);
    final inProgress = ref.watch(inProgressItemsProvider).value ?? const [];
    final arranged = arrangeLibrary(
      entries,
      options,
      progress: ref.watch(libraryProgressProvider),
      downloaded: options.filter == LibraryFilter.downloads
          ? ref.watch(libraryDownloadedIdsProvider)
          : const {},
    );
    final grid = options.layout == LibraryLayout.grid;

    return CustomScrollView(
      key: const ValueKey('library_scroll'),
      slivers: [
        const SliverPadding(padding: EdgeInsets.only(top: 8)),
        if (inProgress.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: InProgressStrip(items: inProgress),
            ),
          ),
        const SliverToBoxAdapter(child: _Controls()),
        if (arranged.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyFilter(filter: options.filter),
          ),
        for (final shelf in arranged.shelves)
          if (!shelf.isEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: SectionTitle(_groupName(l10n, shelf.group)),
              ),
            ),
            if (grid && shelf.courses.isNotEmpty)
              _CardGrid(entries: shelf.courses)
            else
              SliverList.list(
                children: [
                  for (final entry in shelf.courses)
                    LibraryEntryTile(entry: entry),
                ],
              ),
            if (shelf.singles.isNotEmpty)
              SliverList.list(
                children: [
                  if (grid && shelf.courses.isNotEmpty)
                    const SizedBox(height: kCardGap),
                  for (final entry in shelf.singles)
                    LibraryEntryTile(entry: entry),
                ],
              ),
          ],
        if (arranged.teachers.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: SectionTitle(l10n.libraryTeachers),
            ),
          ),
          SliverList.list(
            children: [
              for (final entry in arranged.teachers)
                LibraryEntryTile(entry: entry),
            ],
          ),
        ],
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 24,
          ),
        ),
      ],
    );
  }
}

String _groupName(AppLocalizations l10n, LibraryGroup group) => switch (group) {
  LibraryGroup.practice => l10n.libraryPractice,
  LibraryGroup.talks => l10n.libraryTalks,
};

/// Courses and playlists as a grid of cards, two or more across.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.entries});

  final List<LibraryEntry> entries;

  static const _minWidth = 160.0;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: kCardGutter),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final columns = ((width + kCardGap) / (_minWidth + kCardGap))
              .floor()
              .clamp(2, 4);
          final tile = (width - kCardGap * (columns - 1)) / columns;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: kCardGap,
              mainAxisSpacing: kCardGap,
              // Every card has room for a progress bar, so a row lines up.
              mainAxisExtent: CourseCard.heightFor(
                context,
                width: tile,
                progress: true,
              ),
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) => LibraryEntryCard(entry: entries[i]),
          );
        },
      ),
    );
  }
}

/// The kind chips, then Practice or Talks, the sort and the layout switch.
class _Controls extends ConsumerWidget {
  const _Controls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final options = ref.watch(libraryViewOptionsProvider);
    final notifier = ref.read(libraryViewOptionsProvider.notifier);
    final grid = options.layout == LibraryLayout.grid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterChipBar<LibraryFilter>(
          semanticsLabel: l10n.libraryFilterLabel,
          selected: options.filter,
          onSelected: (filter) =>
              notifier.setFilter(filter ?? LibraryFilter.all),
          options: [
            for (final filter in LibraryFilter.values)
              FilterOption(filter, switch (filter) {
                LibraryFilter.all => l10n.libraryFilterAll,
                LibraryFilter.courses => l10n.libraryFilterCourses,
                LibraryFilter.playlists => l10n.libraryFilterPlaylists,
                LibraryFilter.singles => l10n.libraryFilterSingles,
                LibraryFilter.teachers => l10n.libraryTeachers,
                LibraryFilter.downloads => l10n.libraryFilterDownloads,
              }, key: ValueKey('library_filter_${filter.name}')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kCardGutter, 8, 4, 0),
          // Wraps under large text: the switch keeps its line, the sort and
          // layout buttons drop below it.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              if (options.filter == LibraryFilter.teachers)
                const SizedBox.shrink()
              else
                Semantics(
                  label: l10n.libraryGroupLabel,
                  container: true,
                  child: SegmentedButton<LibraryGroup>(
                    key: const ValueKey('library_group'),
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      for (final group in LibraryGroup.values)
                        ButtonSegment(
                          value: group,
                          label: Text(
                            _groupName(l10n, group),
                            key: ValueKey('library_group_${group.name}'),
                          ),
                        ),
                    ],
                    selected: {?options.group},
                    onSelectionChanged: (selection) =>
                        notifier.setGroup(selection.firstOrNull),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<LibrarySort>(
                    key: const ValueKey('library_sort'),
                    tooltip: l10n.librarySort,
                    icon: const Icon(Icons.sort_rounded),
                    initialValue: options.sort,
                    onSelected: notifier.setSort,
                    itemBuilder: (context) => [
                      for (final sort in LibrarySort.values)
                        CheckedPopupMenuItem(
                          key: ValueKey('library_sort_${sort.name}'),
                          value: sort,
                          checked: sort == options.sort,
                          child: Text(switch (sort) {
                            LibrarySort.recent => l10n.librarySortRecent,
                            LibrarySort.title => l10n.librarySortTitle,
                            LibrarySort.progress => l10n.librarySortProgress,
                          }),
                        ),
                    ],
                  ),
                  IconButton(
                    key: const ValueKey('library_layout'),
                    tooltip: grid ? l10n.libraryShowList : l10n.libraryShowGrid,
                    onPressed: () => notifier.setLayout(
                      grid ? LibraryLayout.list : LibraryLayout.grid,
                    ),
                    icon: Icon(
                      grid
                          ? Icons.view_agenda_rounded
                          : Icons.grid_view_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens the Explore tab, where there is something to add.
void _openExplore(WidgetRef ref) =>
    ref.read(mainTabProvider.notifier).select(MainTab.explore);

/// A message and the ways to fill the library: Explore and Add.
class _EmptyMessage extends ConsumerWidget {
  const _EmptyMessage({
    required this.title,
    required this.body,
    required this.addKey,
    this.extra,
  });

  final String title;
  final String body;
  final Key addKey;
  final Widget? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final type = context.typography;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_library_outlined, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: type.emphasized.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: type.baseline.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                ?extra,
                FilledButton.tonalIcon(
                  key: const ValueKey('library_empty_explore'),
                  onPressed: () => _openExplore(ref),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(l10n.libraryEmptyExplore),
                ),
                FilledButton.icon(
                  key: addKey,
                  onPressed: () => openImport(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.importTitle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      child: _EmptyMessage(
        title: l10n.libraryEmptyTitle,
        body: l10n.libraryEmptyBody,
        addKey: const ValueKey('library_empty_add'),
      ),
    );
  }
}

/// A filter that matches nothing. Playlists can be started here.
class _EmptyFilter extends ConsumerWidget {
  const _EmptyFilter({required this.filter});

  final LibraryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _EmptyMessage(
      title: l10n.libraryFilterEmpty,
      body: l10n.libraryFilterEmptyBody,
      addKey: const ValueKey('library_filter_empty_add'),
      extra: filter == LibraryFilter.playlists
          ? OutlinedButton.icon(
              key: const ValueKey('library_filter_new_playlist'),
              onPressed: () => newMyCourse(context, ref),
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text(l10n.myCourseNew),
            )
          : null,
    );
  }
}
