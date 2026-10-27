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
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';
import 'package:medito/views/home/widgets/shortcuts/shortcuts_section.dart';
import 'package:medito/views/home/widgets/update_notice.dart';
import 'package:medito/widgets/adaptive/adaptive_home_sections.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/widgets/branding/home_mark_sheet.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

/// Home is a launchpad: the Meditejo mark, then what is in progress, a few
/// one-tap starts, and the courses the user pinned. Browsing lives in
/// Explore and everything added in Library. The user chooses which sections
/// show and in what order; the mark always leads. The mark is today's (a
/// new one each day) unless the user pinned one; a long-press on it opens
/// [HomeMarkSheet] to pin or unpin it.
class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView>
    with AutomaticKeepAliveClientMixin {
  String? _lastWidgetSignature;
  bool _markInView = true;

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
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: _onScroll,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 28, bottom: 12),
                        child: Center(child: _HomeMark(animate: _markInView)),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          key: const ValueKey('home_customize'),
                          tooltip: l10n.homeCustomize,
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: () => handleNavigation(
                            TypeConstants.route,
                            [TypeConstants.customiseHomeLayout],
                            context,
                            ref: ref,
                          ),
                        ),
                      ),
                    ],
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
                              top: kHomeSectionGap / 2,
                              bottom: kHomeSectionGap / 2,
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
      ),
    );
  }

  /// The mark rests once Home is scrolled past it.
  bool _onScroll(ScrollUpdateNotification notification) {
    if (notification.depth != 0) return false;
    final inView = notification.metrics.pixels < kHomeMarkSize + 40;
    if (inView != _markInView) setState(() => _markInView = inView);
    return false;
  }

  Widget _buildSection(HomeWidgetType type) => switch (type) {
    HomeWidgetType.upNext => const ContinueSection(),
    HomeWidgetType.homeShortcuts => const ShortcutsSection(),
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

/// Today's (or the pinned) mark. A long-press opens the pin sheet; a pinned
/// mark carries a small pin, the one hint on Home that it won't change.
class _HomeMark extends ConsumerWidget {
  const _HomeMark({required this.animate});

  final bool animate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pinned = ref.watch(pinnedMarkProvider) != null;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('home_mark'),
      label: l10n.homeMarkTitle,
      value: pinned ? l10n.homeMarkPinned : l10n.homeMarkToday,
      onLongPressHint: l10n.homeMarkPinHint,
      child: GestureDetector(
        onLongPress: () => showHomeMarkSheet(context),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            MeditejoMark(
              mark: ref.watch(homeMarkProvider),
              size: kHomeMarkSize,
              animate: animate,
            ),
            if (pinned)
              Positioned(
                right: 0,
                bottom: 0,
                child: Icon(
                  Icons.push_pin_rounded,
                  key: const ValueKey('home_mark_pinned'),
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
