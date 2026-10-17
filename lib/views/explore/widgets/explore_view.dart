import 'dart:async';

import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/explore/explore_list_item.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_widgets.dart';
import 'package:medito/views/explore/widgets/kind_chips.dart';
import 'package:medito/views/explore/widgets/library_state_card.dart';
import 'package:medito/views/explore/widgets/pack_grid_sliver.dart';
import 'package:medito/views/home/widgets/header/home_header_widget.dart';
import 'package:medito/views/tags/widgets/tag_chips.dart';
import 'package:medito/widgets/section_header.dart';
import 'package:medito/widgets/widgets.dart';

/// The Explore tab: Dharma Seed retreats as courses, with Practice and Talks
/// chips, the teachers behind them and, once a chip is chosen, the latest
/// single sessions. Search lives on its own tab.
class ExploreView extends ConsumerStatefulWidget {
  const ExploreView({super.key});

  @override
  ConsumerState<ExploreView> createState() => ExploreViewState();
}

class ExploreViewState extends ConsumerState<ExploreView> {
  bool _hasLoadedData = false;

  /// Reads the lists the first time the tab is shown.
  void loadData() {
    if (_hasLoadedData) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(dharmaSeedExploreProvider);
      _hasLoadedData = true;
    });
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
      // No bottom inset: the floating nav pill sits over the content, which
      // scrolls underneath it. The trailing sliver keeps the last row clear.
      body: AdaptivePageBody(
        maxWidth: 1200,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      padding16,
                      padding16,
                      padding16,
                      0,
                    ),
                    child: HomeHeaderWidget(
                      greeting: AppLocalizations.of(context)!.explore,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: ExploreKindChips()),
                // Browse-by-tag strip, hidden when the local catalog has no tags.
                const SliverToBoxAdapter(
                  child: ExploreTagChips(
                    padding: EdgeInsets.only(top: padding8),
                  ),
                ),
                ..._buildContent(),
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 96,
                  ),
                ),
              ],
            ),
          ),
        ),
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

    if (explore.isEmpty) {
      return [
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

    final l10n = AppLocalizations.of(context)!;
    return [
      if (explore.saved.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(title: l10n.exploreSavedCourses),
        ),
        PackGridSliver(packs: _packs(explore.saved)),
      ],
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
