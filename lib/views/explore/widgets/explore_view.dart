import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_widgets.dart';
import 'package:medito/views/explore/widgets/kind_chips.dart';
import 'package:medito/views/explore/widgets/library_state_card.dart';
import 'package:medito/views/library/library_actions.dart';
import 'package:medito/views/library/library_widgets.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';
import 'package:medito/views/search/search_results.dart';
import 'package:medito/views/tags/widgets/tag_chips.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/add_to_library_icon.dart';
import 'package:medito/widgets/cards/card_art.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/course_card.dart';
import 'package:medito/widgets/cards/section_title.dart';
import 'package:medito/widgets/widgets.dart';

/// A few starting points shown beside the empty search field. They are
/// Burooj's own material (see docs/fork/BRIEF.md), not a ranking of Dharma
/// Seed.
const searchSuggestions = ['Rob Burbea', 'metta', 'jhana', 'emptiness'];

/// The Explore tab: find something to add. A search field sits at the top.
/// With nothing typed it browses: Practice and Talks chips, "In your library"
/// as a strip of small cards, Dharma Seed retreats as large course cards, the
/// teachers behind them, and the latest single sessions (guided practice
/// unless Talks is chosen). Typing replaces that with grouped results
/// (Teachers, Courses, Talks), the user's library first.
class ExploreView extends ConsumerStatefulWidget {
  const ExploreView({super.key});

  @override
  ConsumerState<ExploreView> createState() => ExploreViewState();
}

class ExploreViewState extends ConsumerState<ExploreView> {
  // A broad query over the full catalogue takes about 350 ms, so wait for a
  // pause in typing rather than search on every keystroke.
  static const _searchDebounce = Duration(milliseconds: 400);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _hasLoadedData = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(exploreFocusRequestProvider, (_, request) {
      if (request == 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        focusSearch();
        ref.read(exploreFocusRequestProvider.notifier).consume(request);
      });
    }, fireImmediately: true);
  }

  bool get _searching => _query.trim().isNotEmpty;

  /// Reads the lists the first time the tab is shown.
  void loadData() {
    if (_hasLoadedData) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(dharmaSeedExploreProvider);
      _hasLoadedData = true;
    });
  }

  /// Puts the cursor in the search field.
  void focusSearch() {
    if (!mounted) return;
    if (_focusNode.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (!mounted) return;
      // The local full-text index folds diacritics itself, so the query is
      // passed through as typed ("Ñāṇavīra" works).
      setState(() => _query = value);
    });
  }

  void _useSuggestion(String text) {
    _debounce?.cancel();
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _query = text);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
    _focusNode.requestFocus();
  }

  /// Pulling down re-reads the lists and asks Dharma Seed for what changed
  /// (an incremental sync: a few requests), without waiting for it.
  Future<void> _refresh() async {
    AppLogger.d('ExploreView', 'Refreshing explore lists');
    unawaited(ref.read(dharmaSeedSyncProvider).sync(force: true));
    final group = ref.read(exploreGroupProvider);
    ref.invalidate(dharmaSeedExploreProvider(group));
    try {
      await ref.read(dharmaSeedExploreProvider(group).future);
    } catch (_) {
      // The error state below shows it.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No bottom inset: the nav bar is outside this page, and the trailing
      // sliver keeps the last row clear.
      body: AdaptivePageBody(
        maxWidth: 1200,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kCardGutter + 4,
                  kCardGutter,
                  kCardGutter,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    child: Text(
                      AppLocalizations.of(context)!.explore,
                      style: context.typography.emphasized.headlineMedium,
                    ),
                  ),
                ),
              ),
              _searchField(context),
              Expanded(
                child: _searching
                    ? SearchResults(
                        query: _query,
                        onBeforeNavigate: _focusNode.unfocus,
                      )
                    : _browse(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCardGutter, 12, kCardGutter, 8),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) => SearchBar(
          key: const ValueKey('explore_search_field'),
          controller: _controller,
          focusNode: _focusNode,
          hintText: l10n.exploreSearchHint,
          textInputAction: TextInputAction.search,
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16),
          ),
          leading: const Icon(Icons.search_rounded),
          trailing: [
            if (value.text.isNotEmpty)
              IconButton(
                tooltip: l10n.clearSearch,
                onPressed: _clear,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
          onChanged: _onChanged,
        ),
      ),
    );
  }

  /// Nothing typed: the chips and suggestions, then what there is to add.
  Widget _browse() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: ExploreKindChips(),
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                kCardGutter,
                4,
                kCardGutter,
                0,
              ),
              child: Row(
                children: [
                  for (final (i, suggestion) in searchSuggestions.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    ActionChip(
                      key: ValueKey('suggestion_$suggestion'),
                      avatar: const Icon(Icons.search_rounded),
                      label: Text(suggestion),
                      onPressed: () => _useSuggestion(suggestion),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Browse-by-tag strip, hidden when the local catalog has no tags.
          const SliverToBoxAdapter(
            child: ExploreTagChips(padding: EdgeInsets.only(top: 4)),
          ),
          ..._buildContent(),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 96,
            ),
          ),
        ],
      ),
    );
  }

  /// A section's heading, with the gap above it.
  Widget _title(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.only(top: 28),
      child: SectionTitle(text),
    ),
  );

  List<Widget> _buildContent() {
    final group = ref.watch(exploreGroupProvider);
    final async = ref.watch(dharmaSeedExploreProvider(group));
    final explore = async.value;

    if (explore == null) {
      if (async.hasError) {
        final err = async.error;
        return [
          SliverFillRemaining(
            child: MeditoErrorWidget(
              error: err is AppError ? err : const UnknownError(),
              isScaffold: false,
              onTap: () => ref.invalidate(dharmaSeedExploreProvider(group)),
            ),
          ),
        ];
      }
      return const [
        SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
      ];
    }

    // Courses in the library lead, under any chip: they are the user's own,
    // so a filter must never hide them.
    final library =
        ref
            .watch(librarySectionsProvider)
            .value
            ?.contentFirstPractice
            .where((e) => e.kind == LibraryKind.course)
            .toList() ??
        const <LibraryEntry>[];
    final l10n = AppLocalizations.of(context)!;
    final libraryStrip = library.isEmpty
        ? const <Widget>[]
        : [
            _title(l10n.exploreLibraryHeading),
            SliverToBoxAdapter(child: _LibraryStrip(entries: library)),
          ];

    if (explore.isEmpty) {
      return [
        ...libraryStrip,
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: explore.hasCatalogue
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.exploreNothingInGroup,
                      textAlign: TextAlign.center,
                      style: context.typography.baseline.bodyLarge,
                    ),
                  )
                : const LibraryStateCard(),
          ),
        ),
      ];
    }

    return [
      ...libraryStrip,
      if (explore.courses.isNotEmpty) ...[
        _title(l10n.exploreCourses),
        SliverToBoxAdapter(child: _CourseStrip(courses: explore.courses)),
      ],
      if (explore.savedTeachers.isNotEmpty) ...[
        _title(l10n.exploreSavedTeachers),
        SliverToBoxAdapter(
          child: TeacherStrip(teachers: explore.savedTeachers),
        ),
      ],
      if (explore.teachers.isNotEmpty) ...[
        _title(l10n.exploreTeachers),
        SliverToBoxAdapter(child: TeacherStrip(teachers: explore.teachers)),
      ],
      if (explore.talks.isNotEmpty) ...[
        _title(
          group == DsContentGroup.talks
              ? l10n.exploreLatestTalks
              : l10n.exploreLatestPractice,
        ),
        SessionRowsSliver(items: explore.talks),
      ],
    ];
  }
}

/// "In your library": the courses and playlists the user keeps, as a strip of
/// small cards. Each opens its page.
class _LibraryStrip extends ConsumerWidget {
  const _LibraryStrip({required this.entries});

  final List<LibraryEntry> entries;

  static const _width = 136.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: CourseCard.heightFor(
        context,
        width: _width,
        size: CourseCardSize.compact,
        detail: false,
      ),
      child: ListView.separated(
        key: const ValueKey('explore_library_strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kCardGutter),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: kCardGap),
        itemBuilder: (context, i) {
          final entry = entries[i];
          return SizedBox(
            width: _width,
            child: CourseCard(
              key: ValueKey('pack_${entry.sourceId}'),
              size: CourseCardSize.compact,
              title: entry.displayTitle,
              overline: librarySourceLabel(l10n, entry.sourceId),
              art: CardArt(
                url: entry.coverUrl,
                seed: entry.displayTitle,
                portrait: hasPortraitCover(entry.sourceId),
                avatarSize: 28,
              ),
              onTap: () => openLibraryEntry(context, ref, entry),
            ),
          );
        },
      ),
    );
  }
}

/// Dharma Seed's courses as a strip of large cards: generated art with the
/// teacher's photo, the name, "teacher · year · N talks", and a quiet Add to
/// library on the art.
class _CourseStrip extends ConsumerWidget {
  const _CourseStrip({required this.courses});

  final List<PackItemsModel> courses;

  static const _width = 288.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = ref.watch(completedPackIdsProvider);
    // Narrow phones keep a peek of the next card.
    final width = math.min(
      _width,
      MediaQuery.sizeOf(context).width - 2 * kCardGutter - 40,
    );
    return SizedBox(
      height: CourseCard.heightFor(
        context,
        width: width,
        size: CourseCardSize.large,
        overline: false,
      ),
      child: ListView.separated(
        key: const ValueKey('explore_course_strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kCardGutter),
        itemCount: courses.length,
        separatorBuilder: (_, _) => const SizedBox(width: kCardGap),
        itemBuilder: (context, i) {
          final course = courses[i];
          return SizedBox(
            width: width,
            child: CourseCard(
              key: ValueKey('pack_${course.id}'),
              size: CourseCardSize.large,
              title: course.title,
              detail: course.subtitle,
              art: CardArt(
                url: course.coverUrl ?? '',
                seed: course.title,
                portrait: hasPortraitCover(course.id),
              ),
              badge: completed.contains(course.id)
                  ? const PackCompleteBadge()
                  : null,
              action: AddToLibraryIcon(id: course.id),
              onTap: () => handleNavigation(
                TypeConstants.pack,
                [course.id, course.path],
                context,
                ref: ref,
              ),
            ),
          );
        },
      ),
    );
  }
}
