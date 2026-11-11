import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
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
import 'package:medito/views/home/widgets/home_mark_layout.dart';
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';
import 'package:medito/views/home/widgets/shortcuts/shortcuts_section.dart';
import 'package:medito/views/home/widgets/update_notice.dart';
import 'package:medito/views/you/you_button.dart';
import 'package:medito/widgets/adaptive/adaptive_home_sections.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/mark_moments.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home is a launchpad: the Meditejo mark, large and with air around it (up
/// to about the top half of the screen, less when what is below needs the
/// room; see `HomeMarkLayout`), then what is in progress, a few one-tap
/// starts, and the courses the user pinned. Browsing lives in
/// Explore and everything added in Library. The user chooses which sections
/// show and in what order; the mark always leads. The mark is today's (a
/// new one each day), and a tap sends a breath through its parts.
class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView>
    with AutomaticKeepAliveClientMixin {
  String? _lastWidgetSignature;
  bool _markInView = true;
  final _fold = HomeFold();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final order = ref.watch(homeWidgetOrderProvider);
    final hidden = ref.watch(homeHiddenWidgetsProvider);
    ref.listen(continueItemsProvider, (_, next) => _updateWidget(next.value));

    final shown = [
      for (final type in order)
        if (!hidden.contains(type)) type,
    ];
    // The fold is the first row of tiles; with those hidden, the first
    // section.
    final foldOnFirst = !shown.contains(HomeWidgetType.homeShortcuts);
    final screen = MediaQuery.sizeOf(context);
    // No taller than the mark can fill: it is never wider than the screen.
    final maxHeader = math.min(
      screen.height * kHomeMarkMaxShare,
      screen.width + kHomeMarkTop,
    );
    final animate = !MediaQuery.disableAnimationsOf(context);

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
                HomeFoldScope(
                  fold: _fold,
                  child: HomeMarkLayout(
                    fold: _fold,
                    minHeader: screen.height * kHomeMarkMinShare,
                    maxHeader: maxHeader,
                    animate: animate,
                    header: Stack(
                      fit: StackFit.expand,
                      children: [
                        _HomeMark(animate: _markInView),
                        // Where an app bar's actions sit on Library and
                        // Settings, so the You button is in the same place.
                        Positioned(
                          top: YouButton.inset,
                          right: YouButton.inset,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
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
                              const YouButton(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    rest: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const UpdateNotice(),
                        AdaptiveHomeSections(
                          children: [
                            for (final (i, type) in shown.indexed)
                              Padding(
                                key: ValueKey(type),
                                padding: const EdgeInsets.only(
                                  top: kHomeSectionGap / 2,
                                  bottom: kHomeSectionGap / 2,
                                ),
                                child: foldOnFirst && i == 0
                                    ? HomeFoldMarker(child: _buildSection(type))
                                    : _buildSection(type),
                              ),
                          ],
                        ),
                      ],
                    ),
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
    final inView = notification.metrics.pixels < _fold.headerHeight;
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
///
/// At rest its parts keep a slow motion of their own; it is most alive in
/// two moments. A tap sends one deep breath through its parts. And the first time Home is seen on a new day, the last daily mark
/// seen (usually yesterday's) un-draws as today's draws itself in, and
/// today's name shows for a few seconds (once a day, and never for a pinned
/// mark). The day it was last seen is kept in preferences.
class _HomeMark extends ConsumerStatefulWidget {
  const _HomeMark({required this.animate});

  final bool animate;

  @override
  ConsumerState<_HomeMark> createState() => _HomeMarkState();
}

class _HomeMarkState extends ConsumerState<_HomeMark> {
  final _mark = GlobalKey<MeditejoMarkState>();

  /// The turn's clock, kept by the mark itself: today's name rides on it,
  /// so it holds and carries on with the turn when Home is covered, on a
  /// hidden tab, scrolled away or in the background.
  final _turn = ValueNotifier<double>(0);

  /// The kind of mark whose name shows.
  String? _named;

  /// Whether today's name has been announced.
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    _turn.addListener(_onTurn);
  }

  /// Announces today's name as it starts to show (so only when it is
  /// seen), and lets it go once the turn is over.
  void _onTurn() {
    final named = _named;
    if (named == null || !mounted) return;
    final s = _turn.value;
    if (!_announced && s >= MarkMoments.nameFrom) {
      _announced = true;
      final l10n = AppLocalizations.of(context)!;
      SemanticsService.sendAnnouncement(
        View.of(context),
        l10n.homeMarkTodayIs(l10n.homeMarkName(named)),
        Directionality.of(context),
      ).ignore();
    }
    if (s >= MarkMoments.nameSeconds) setState(() => _named = null);
  }

  /// The last day's mark, built once per stored day.
  (String, MarkSpec)? _lastDay;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  String get _today => DailyMark.dayKey(ref.read(identityDayProvider));

  /// The daily mark seen last, when it was another day's.
  MarkSpec? _arrivingFrom() {
    final seen = _prefs.getString(SharedPreferenceConstants.homeMarkSeenDay);
    if (seen == null || seen == _today) return null;
    final cached = _lastDay;
    if (cached != null && cached.$1 == seen) return cached.$2;
    final day = DateTime.tryParse(seen);
    if (day == null) return null;
    final mark = MarkGenerator.build(DailyMark.forDay(day).seed);
    _lastDay = (seen, mark);
    return mark;
  }

  /// Notes today as seen. Says whether a day was seen before, and it was
  /// another: a new day to greet.
  bool _noteSeen() {
    final today = _today;
    final seen = _prefs.getString(SharedPreferenceConstants.homeMarkSeenDay);
    if (seen == today) return false;
    _prefs.setString(SharedPreferenceConstants.homeMarkSeenDay, today).ignore();
    return seen != null;
  }

  /// The mark was seen: on a new day, say today's name. Not on the very
  /// first Home (no day before to turn from; the intro has just shown the
  /// mark).
  void _onSeen() {
    if (!_noteSeen()) return;
    setState(() {
      _named = ref.read(homeMarkProvider).type;
      _announced = false;
    });
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.watch(identityDayProvider);
    final scheme = Theme.of(context).colorScheme;
    final named = _named;
    final mark = Semantics(
      key: const ValueKey('home_mark'),
      label: l10n.homeMarkTitle,
      value: l10n.homeMarkToday,
      child: GestureDetector(
        // The breath is felt, not announced: no action for TalkBack.
        excludeFromSemantics: true,
        onTap: () => _mark.currentState?.breathe(),
        // A hold is not a tap: it does nothing, rather than breathe on
        // release.
        onLongPress: () {},
        child: MeditejoMark(
          key: _mark,
          mark: ref.watch(homeMarkProvider),
          // As large as the square it is given.
          size: null,
          animate: widget.animate,
          from: _arrivingFrom(),
          onSeen: _onSeen,
          turnClock: _turn,
        ),
      ),
    );
    // Today's name has a line of its own under the mark, kept whether or
    // not it shows: it never covers what follows (an update notice, the
    // first section) and nothing moves as it comes and goes, at any text
    // size.
    final style = context.typography.baseline.labelLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final name = IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          width: double.infinity,
          child: named == null
              ? Text(' ', style: style, maxLines: 1)
              : ValueListenableBuilder<double>(
                  valueListenable: _turn,
                  builder: (context, s, child) => Opacity(
                    opacity: MarkMoments.nameOpacityAt(s),
                    child: child,
                  ),
                  child: Text(
                    l10n.homeMarkName(named),
                    key: const ValueKey('home_mark_name'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: style,
                  ),
                ),
        ),
      ),
    );
    // The mark is as large as its block lets it be: a square in the
    // block's height (which gives way to what is below), less the top
    // margin and the name's line, and never wider than the screen less its
    // gutters.
    return Padding(
      padding: const EdgeInsets.only(top: kHomeMarkTop),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kHomeMarkMaxSize,
                    maxHeight: kHomeMarkMaxSize,
                  ),
                  child: AspectRatio(aspectRatio: 1, child: mark),
                ),
              ),
            ),
          ),
          name,
        ],
      ),
    );
  }
}
