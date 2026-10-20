import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/enums/home_widget_type.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/home/widget_order_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/home_widget_service.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/views/home/widgets/continue/continue_section.dart';
import 'package:medito/views/home/widgets/header/home_header_widget.dart';
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';
import 'package:medito/views/home/widgets/quick_links/quick_links_section.dart';
import 'package:medito/views/home/widgets/update_notice.dart';
import 'package:medito/widgets/adaptive/adaptive_home_sections.dart';

/// Home is a launchpad: what is in progress, a few one-tap starts, and the
/// courses the user pinned. Browsing lives in Explore and everything added in
/// Library. The user chooses which sections show and in what order.
class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView>
    with AutomaticKeepAliveClientMixin {
  String? _lastWidgetSignature;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final order = ref.watch(homeWidgetOrderProvider);
    final hidden = ref.watch(homeHiddenWidgetsProvider);
    ref.listen(continueItemsProvider, (_, next) => _updateWidget(next.value));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    padding16,
                    padding16,
                    padding8,
                    0,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: HomeHeaderWidget(greeting: l10n.home)),
                      TextButton(
                        key: const ValueKey('home_customize'),
                        onPressed: () => handleNavigation(
                          TypeConstants.route,
                          [TypeConstants.customiseHomeLayout],
                          context,
                          ref: ref,
                        ),
                        child: Text(l10n.homeCustomize),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: UpdateNotice()),
              SliverToBoxAdapter(
                child: AdaptiveHomeSections(
                  children: [
                    for (final type in order)
                      if (!hidden.contains(type))
                        Padding(
                          key: ValueKey(type),
                          padding: const EdgeInsets.only(
                            top: padding16,
                            bottom: kHomeSectionGap - padding16,
                          ),
                          child: _buildSection(type),
                        ),
                  ],
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + padding16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(HomeWidgetType type) => switch (type) {
    HomeWidgetType.upNext => const ContinueSection(),
    HomeWidgetType.quickLinks => const QuickLinksSection(),
    HomeWidgetType.pinned => const PinnedSection(),
  };

  Future<void> _onRefresh() async {
    ref.invalidate(continueItemsProvider);
    await Future.wait([
      ref.read(statsProvider.notifier).refresh(),
      ref.read(continueItemsProvider.future),
    ]);
  }

  /// Keeps the Android home-screen widget on the first Continue item.
  void _updateWidget(List<ContinueItem>? items) {
    final first = items?.firstOrNull;
    final signature = first == null
        ? ''
        : '${first.trackId}|${first.completedSessions}/${first.sessionTotal}|${first.title}|${first.subtitle}|${first.courseTitle}';
    if (signature == _lastWidgetSignature) return;
    _lastWidgetSignature = signature;
    HomeWidgetService.updateUpNextWidget(
      title: first?.title ?? '',
      packTitle: first?.courseTitle ?? '',
      trackId: first?.trackId ?? '',
      subtitle: first?.subtitle ?? '',
      completed: first?.completedSessions ?? 0,
      total: first?.sessionTotal ?? 0,
    ).ignore();
  }

  @override
  bool get wantKeepAlive => true;
}
