import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/enums/home_widget_type.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/home/home_model.dart';
import 'package:medito/providers/home/home_provider.dart';
import 'package:medito/providers/home/widget_order_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/downloads/downloads_view.dart';
import 'package:medito/views/favorites/favorites_view.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:medito/widgets/adaptive/adaptive_home_sections.dart';

import 'home_styles.dart';
import 'widgets/editorial/carousel_widget.dart';
import 'widgets/header/home_hero.dart';
import 'widgets/library/home_library_section.dart';
import 'widgets/quote/quote_widget.dart';
import 'widgets/shortcuts/shortcuts_items_widget.dart';
import 'widgets/up_next/up_next_widget.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView>
    with AutomaticKeepAliveClientMixin {
  final _upNextPrimaryAction = UpNextPrimaryAction();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Local actions remain available while catalogue content loads or fails.
    final homeData = ref.watch(fetchHomeProvider).value ?? const HomeModel();
    final hasHero = ref.watch(homeHeroCoverProvider) != null;
    final fullOrder = ref.watch(homeWidgetOrderProvider);
    final first = fullOrder.firstOrNull;
    final heroType =
        hasHero &&
            (first == HomeWidgetType.upNext || first == HomeWidgetType.quote)
        ? first
        : null;
    final order = heroType == null ? fullOrder : fullOrder.sublist(1);

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          edgeOffset: MediaQuery.paddingOf(context).top + padding16,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              HomeHero(
                onStatsButtonTap: () => handleNavigation(
                  TypeConstants.route,
                  [RouteConstants.stats],
                  context,
                  ref: ref,
                ),
                onImageTap: heroType == HomeWidgetType.upNext
                    ? _upNextPrimaryAction.trigger
                    : null,
                child: heroType == null
                    ? null
                    : _buildSection(heroType, homeData, inHero: true),
              ),
              const SliverToBoxAdapter(child: HomeLibrarySection()),
              SliverToBoxAdapter(child: _buildLocalActions(context)),
              SliverToBoxAdapter(
                child: AdaptiveHomeSections(
                  children: [
                    for (final type in order)
                      Padding(
                        key: ValueKey(type),
                        padding: const EdgeInsets.only(bottom: kHomeSectionGap),
                        child: _buildSection(type, homeData),
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

  Widget _buildLocalActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(padding16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.localHomeHeading,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: padding16),
          FilledButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push<void>(MaterialPageRoute(builder: (_) => const TimerView())),
            icon: const Icon(Icons.timer_outlined),
            label: Text(l10n.openTimer),
          ),
          const SizedBox(height: padding8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: padding16,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const FavoritesView()),
                ),
                icon: const Icon(Icons.favorite_border),
                label: Text(l10n.favorites),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const DownloadsView()),
                ),
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.downloads),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    HomeWidgetType type,
    HomeModel homeData, {
    bool inHero = false,
  }) {
    final key = ValueKey('${type.name}${inHero ? '_hero' : ''}');
    return switch (type) {
      HomeWidgetType.shortcuts =>
        homeData.shortcuts.isEmpty
            ? const SizedBox.shrink()
            : ShortcutsItemsWidget(key: key, data: homeData.shortcuts),
      HomeWidgetType.carousel =>
        homeData.carousel.isEmpty
            ? const SizedBox.shrink()
            : CarouselWidget(key: key, carouselItems: homeData.carousel),
      HomeWidgetType.quote =>
        homeData.todayQuote == null
            ? const SizedBox.shrink()
            : QuoteWidget(key: key, data: homeData.todayQuote),
      HomeWidgetType.upNext => UpNextWidget(
        key: key,
        style: inHero ? UpNextStyle.hero : UpNextStyle.card,
        primaryAction: inHero ? _upNextPrimaryAction : null,
      ),
    };
  }

  Future<void> _onRefresh() async {
    ref.invalidate(fetchHomeProvider);
    ref.invalidate(packDataProvider);
    await Future.wait([
      ref.read(statsProvider.notifier).refresh(),
      ref.read(fetchHomeProvider.future),
    ]);
  }

  @override
  bool get wantKeepAlive => true;
}
