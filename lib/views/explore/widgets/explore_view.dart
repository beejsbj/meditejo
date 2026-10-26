import 'dart:async';

import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/explore/explore_list_item.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_widgets.dart';
import 'package:medito/views/explore/widgets/kind_chips.dart';
import 'package:medito/views/explore/widgets/library_state_card.dart';
import 'package:medito/views/explore/widgets/pack_grid_sliver.dart';
import 'package:medito/views/home/widgets/header/home_header_widget.dart';
import 'package:medito/views/tags/widgets/tag_chips.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/my_courses/playlist_label.dart';
import 'package:medito/views/search/search_results.dart';
import 'package:medito/widgets/filter_pill.dart';
import 'package:medito/widgets/medito_icon.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/widgets/section_header.dart';
import 'package:medito/widgets/widgets.dart';

/// A few starting points shown beside the empty search field. They are
/// Burooj's own material (see docs/fork/BRIEF.md), not a ranking of Dharma
/// Seed.
const searchSuggestions = ['Rob Burbea', 'metta', 'jhana', 'emptiness'];

/// The Explore tab: find something to add. A search field sits at the top.
/// With nothing typed it browses: Practice and Talks chips, the library's
/// courses, Dharma Seed retreats as courses, the teachers behind them and,
/// once a chip is chosen, the latest single sessions. Typing replaces that
/// with grouped results (Teachers, Courses, Talks), the user's library first.
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
                  padding16,
                  padding16,
                  padding16,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: HomeHeaderWidget(
                    greeting: AppLocalizations.of(context)!.explore,
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        padding16,
        padding16,
        padding16,
        padding8,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) => MeditoTextField(
          key: const ValueKey('explore_search_field'),
          controller: _controller,
          focusNode: _focusNode,
          hintText: l10n.exploreSearchHint,
          textInputAction: TextInputAction.search,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: MeditoIcon(
              assetName: MeditoIcons.search,
              color: onSurface.withOpacityValue(0.6),
              size: 18,
            ),
          ),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.clearSearch,
                  iconSize: 20,
                  onPressed: _clear,
                  icon: Icon(
                    Icons.cancel,
                    color: onSurface.withOpacityValue(0.6),
                  ),
                ),
          onChanged: _onChanged,
        ),
      ),
    );
  }

  /// Nothing typed: the chips, suggestions and what there is to add.
  Widget _browse() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          const SliverToBoxAdapter(child: ExploreKindChips()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                padding16,
                padding8,
                padding16,
                0,
              ),
              child: Wrap(
                spacing: padding8,
                runSpacing: padding8,
                children: [
                  for (final suggestion in searchSuggestions)
                    FilterPill(
                      key: ValueKey('suggestion_$suggestion'),
                      label: suggestion,
                      selected: false,
                      onTap: () => _useSuggestion(suggestion),
                    ),
                ],
              ),
            ),
          ),
          // Browse-by-tag strip, hidden when the local catalog has no tags.
          const SliverToBoxAdapter(
            child: ExploreTagChips(padding: EdgeInsets.only(top: padding8)),
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
    final libraryHeading = library.isEmpty
        ? const <Widget>[]
        : [
            SliverToBoxAdapter(
              child: SectionHeader(title: l10n.exploreLibraryHeading),
            ),
            PackGridSliver(
              packs: [
                for (final entry in library)
                  PackItem(
                    id: entry.sourceId,
                    title: entry.displayTitle,
                    subtitle:
                        playlistAwareDetail(
                          l10n,
                          entry.sourceId,
                          entry.subtitle,
                        ) ??
                        '',
                    coverUrl: entry.coverUrl,
                    path: '/packs/${entry.sourceId}',
                  ),
              ],
            ),
          ];

    if (explore.isEmpty) {
      return [
        ...libraryHeading,
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: explore.hasCatalogue
                ? Padding(
                    padding: const EdgeInsets.all(padding24),
                    child: Text(
                      AppLocalizations.of(context)!.exploreNothingInGroup,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : const LibraryStateCard(),
          ),
        ),
      ];
    }

    return [
      ...libraryHeading,
      if (explore.courses.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(title: l10n.exploreCourses)),
        PackGridSliver(packs: _packs(explore.courses)),
      ],
      if (explore.savedTeachers.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(title: l10n.exploreSavedTeachers),
        ),
        SliverToBoxAdapter(
          child: TeacherStrip(teachers: explore.savedTeachers),
        ),
      ],
      if (explore.teachers.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(title: l10n.exploreTeachers)),
        SliverToBoxAdapter(child: TeacherStrip(teachers: explore.teachers)),
      ],
      if (explore.talks.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            title: group == DsContentGroup.practice
                ? l10n.exploreLatestPractice
                : l10n.exploreLatestTalks,
          ),
        ),
        SessionRowsSliver(items: explore.talks),
      ],
    ];
  }

  List<PackItem> _packs(List<PackItemsModel> items) => [
    for (final item in items)
      PackItem(
        id: item.id,
        title: item.title,
        subtitle: item.subtitle ?? '',
        coverUrl: item.coverUrl ?? '',
        path: item.path,
      ),
  ];
}
