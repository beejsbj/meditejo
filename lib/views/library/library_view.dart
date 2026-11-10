import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/library/library_view_provider.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/library/library_add_sheet.dart';
import 'package:medito/views/library/library_widgets.dart';
import 'package:medito/views/you/you_button.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/course_card.dart';
import 'package:medito/widgets/cards/filter_chip_bar.dart';
import 'package:medito/widgets/cards/section_title.dart';

/// Everything the user keeps and is working through. It is the Library tab.
///
/// Its header has a "+" ([showLibraryAddSheet]: Import, New playlist) and
/// the You button; Home has no Add of its own (#62).
///
/// From the top: the filter chips (All, Practice, Talks, and Downloads once
/// something is downloaded), the user's labels (a practice's chip leads with
/// its picture), the sort and the grid or
/// list switch; then the library by form (#80): Sessions, Playlists and
/// Courses, sessions as rows, playlists and courses as cards, and saved
/// teachers last. Practice and Talks go by what a course's sessions are, so a
/// course with both shows under either ([libraryEntryKinds]). There is no In
/// progress here: Home's Continue has it.
class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final entries = ref.watch(libraryEntriesProvider);
    final titleStyle = context.typography.emphasized.titleLarge;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        titleTextStyle: titleStyle,
        actions: [
          // "+" then You: what the library can take in, then the user.
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton.filledTonal(
              key: const ValueKey('library_add'),
              tooltip: l10n.importTitle,
              onPressed: () => showLibraryAddSheet(context, ref),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: YouButton.inset),
            child: YouButton(),
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
    // A label nothing carries any more (its last item was removed or
    // unlabelled) filters nothing, rather than showing an empty library.
    final labelOptions = ref.watch(libraryLabelOptionsProvider);
    final stored = ref.watch(libraryViewOptionsProvider);
    final options = labelOptions.any((o) => o.key == stored.label)
        ? stored
        : stored.copyWith(label: () => null);
    final labels = ref.watch(libraryLabelsProvider).value ?? const {};
    final downloaded = ref.watch(libraryDownloadedIdsProvider);
    // Until the sessions are read, each entry shows under its own kind.
    final kinds = ref.watch(libraryEntryKindsProvider).value ?? const {};
    final arranged = arrangeLibrary(
      entries,
      options,
      labels: labels,
      progress: ref.watch(libraryProgressProvider),
      downloaded: downloaded,
      kinds: kinds,
    );
    final counts = libraryFilterCounts(
      entries,
      label: options.label,
      labels: labels,
      downloaded: downloaded,
      kinds: kinds,
    );
    final grid = options.layout == LibraryLayout.grid;

    return CustomScrollView(
      key: const ValueKey('library_scroll'),
      slivers: [
        const SliverPadding(padding: EdgeInsets.only(top: 8)),
        SliverToBoxAdapter(
          child: _Controls(
            labelOptions: labelOptions,
            filter: options.filter,
            counts: counts,
          ),
        ),
        if (arranged.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyFilter(
              filter: options.filter,
              labelled: options.label != null,
            ),
          ),
        for (final shelf in arranged.shelves)
          if (!shelf.isEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: SectionTitle(
                  _formName(l10n, shelf.form),
                  key: ValueKey('library_section_${shelf.form.name}'),
                ),
              ),
            ),
            if (grid && shelf.isCards)
              _CardGrid(entries: shelf.entries)
            else
              SliverList.list(
                children: [
                  for (final entry in shelf.entries)
                    LibraryEntryTile(entry: entry),
                ],
              ),
          ],
        if (arranged.teachers.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: SectionTitle(
                l10n.libraryTeachers,
                key: const ValueKey('library_section_teachers'),
              ),
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

String _formName(AppLocalizations l10n, LibraryForm form) => switch (form) {
  LibraryForm.playlists => l10n.librarySectionPlaylists,
  LibraryForm.courses => l10n.librarySectionCourses,
  LibraryForm.sessions => l10n.librarySectionSessions,
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

/// The filter chips with how much each shows, the label chips, then the
/// sort and the layout switch.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.labelOptions,
    required this.filter,
    required this.counts,
  });

  final List<LibraryLabelOption> labelOptions;
  final LibraryFilter filter;
  final Map<LibraryFilter, int> counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final options = ref.watch(libraryViewOptionsProvider);
    final notifier = ref.read(libraryViewOptionsProvider.notifier);
    final grid = options.layout == LibraryLayout.grid;
    final catalogue = ref.watch(categoryCatalogueProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterChipBar<LibraryFilter>(
          semanticsLabel: l10n.libraryFilterLabel,
          selected: filter,
          onSelected: (chosen) =>
              notifier.setFilter(chosen ?? LibraryFilter.all),
          options: [
            for (final option in LibraryFilter.values)
              // Teachers and Downloads only once there is something to show
              // (or while chosen), so the row stays short.
              if (option.group != null ||
                  option == LibraryFilter.all ||
                  (counts[option] ?? 0) > 0 ||
                  filter == option)
                FilterOption(option, switch (option) {
                  LibraryFilter.all => l10n.libraryFilterAll,
                  LibraryFilter.practice => l10n.libraryFilterCount(
                    l10n.libraryPractice,
                    counts[option] ?? 0,
                  ),
                  LibraryFilter.talks => l10n.libraryFilterCount(
                    l10n.libraryTalks,
                    counts[option] ?? 0,
                  ),
                  LibraryFilter.teachers => l10n.libraryFilterCount(
                    l10n.libraryTeachers,
                    counts[option] ?? 0,
                  ),
                  LibraryFilter.downloads => l10n.libraryFilterCount(
                    l10n.libraryFilterDownloads,
                    counts[option] ?? 0,
                  ),
                }, key: ValueKey('library_filter_${option.name}')),
          ],
        ),
        if (labelOptions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilterChipBar<String>(
              semanticsLabel: l10n.libraryLabelFilterLabel,
              selected: labelOptions.any((o) => o.key == options.label)
                  ? options.label
                  : null,
              allowDeselect: true,
              onSelected: notifier.setLabel,
              options: [
                for (final option in labelOptions)
                  FilterOption(
                    option.key,
                    option.name,
                    key: ValueKey('library_label_${option.key}'),
                    // A practice carries its picture, the one its tile has
                    // on Explore; a label of the user's own has none.
                    leading: switch (catalogue?.category(option.key)) {
                      final practice? => ArtCover(
                        subject: ArtSubject.practice(
                          practice.id,
                          ground: practice.ground,
                          figure: practice.figure,
                        ),
                      ),
                      null => null,
                    },
                  ),
              ],
            ),
          ),
        // The sort, named, at the start; the layout switch at the end.
        Padding(
          padding: const EdgeInsets.fromLTRB(kCardGutter - 8, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PopupMenuButton<LibrarySort>(
                    key: const ValueKey('library_sort'),
                    tooltip: l10n.librarySort,
                    initialValue: options.sort,
                    onSelected: notifier.setSort,
                    itemBuilder: (context) => [
                      for (final sort in LibrarySort.values)
                        CheckedPopupMenuItem(
                          key: ValueKey('library_sort_${sort.name}'),
                          value: sort,
                          checked: sort == options.sort,
                          child: Text(_sortName(l10n, sort)),
                        ),
                    ],
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort_rounded, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _sortName(l10n, options.sort),
                                style: context.typography.baseline.labelLarge,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('library_layout'),
                tooltip: grid ? l10n.libraryShowList : l10n.libraryShowGrid,
                onPressed: () => notifier.setLayout(
                  grid ? LibraryLayout.list : LibraryLayout.grid,
                ),
                icon: Icon(
                  grid ? Icons.view_agenda_rounded : Icons.grid_view_rounded,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _sortName(AppLocalizations l10n, LibrarySort sort) => switch (sort) {
  LibrarySort.recent => l10n.librarySortRecent,
  LibrarySort.title => l10n.librarySortTitle,
  LibrarySort.progress => l10n.librarySortProgress,
};

/// Opens the Explore tab, where there is something to add.
void _openExplore(WidgetRef ref) =>
    ref.read(mainTabProvider.notifier).select(MainTab.explore);

/// A message and the ways to fill the library: Explore and Add.
class _EmptyMessage extends ConsumerWidget {
  const _EmptyMessage({
    super.key,
    required this.title,
    required this.body,
    required this.addKey,
  });

  final String title;
  final String body;
  final Key addKey;

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
                  // "Import", not the header "+"'s "Add to your library",
                  // so a screen reader hears two different buttons (#62).
                  label: Text(l10n.libraryAddImport),
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

/// A filter that matches nothing: what it would show, and the ways to fill
/// the library.
class _EmptyFilter extends ConsumerWidget {
  const _EmptyFilter({required this.filter, this.labelled = false});

  final LibraryFilter filter;

  /// Whether a label is chosen: then it may be what leaves nothing, and the
  /// chip's own words would mislead.
  final bool labelled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final (title, body) = switch (labelled ? LibraryFilter.all : filter) {
      LibraryFilter.practice => (
        l10n.libraryPracticeEmpty,
        l10n.libraryPracticeEmptyBody,
      ),
      LibraryFilter.talks => (
        l10n.libraryTalksEmpty,
        l10n.libraryTalksEmptyBody,
      ),
      LibraryFilter.downloads => (
        l10n.libraryDownloadsEmpty,
        l10n.libraryDownloadsEmptyBody,
      ),
      // Everything (or the teachers), or anything narrowed by a label.
      LibraryFilter.all || LibraryFilter.teachers => (
        l10n.libraryFilterEmpty,
        l10n.libraryFilterEmptyBody,
      ),
    };
    return _EmptyMessage(
      key: ValueKey('library_empty_${labelled ? 'label' : filter.name}'),
      title: title,
      body: body,
      addKey: const ValueKey('library_filter_empty_add'),
    );
  }
}
