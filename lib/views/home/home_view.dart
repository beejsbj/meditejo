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
import 'package:medito/widgets/branding/home_mark_sheet.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home is a launchpad: the Meditejo mark, then what is in progress, a few
/// one-tap starts, and the courses the user pinned. Browsing lives in
/// Explore and everything added in Library. The user chooses which sections
/// show and in what order; the mark always leads. The mark is today's (a
/// new one each day) unless the user pinned one; a long-press on it opens
/// [HomeMarkSheet] to pin or unpin it, and a tap sends a breath through it.
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
                    // Today's name may sit just below the mark's box.
                    clipBehavior: Clip.none,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 28, bottom: 12),
                        child: Center(child: _HomeMark(animate: _markInView)),
                      ),
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
///
/// Quiet at rest; alive in two moments. A tap sends one deep breath through
/// it. And the first time Home is seen on a new day, the last daily mark
/// seen (usually yesterday's) un-draws as today's draws itself in, and
/// today's name shows for a few seconds (once a day, and never for a pinned
/// mark). The day it was last seen is kept in preferences.
class _HomeMark extends ConsumerStatefulWidget {
  const _HomeMark({required this.animate});

  final bool animate;

  @override
  ConsumerState<_HomeMark> createState() => _HomeMarkState();
}

class _HomeMarkState extends ConsumerState<_HomeMark>
    with SingleTickerProviderStateMixin {
  final _mark = GlobalKey<MeditejoMarkState>();

  /// Today's name: in, resting, out (see [MarkMoments.nameOpacityAt]).
  late final AnimationController _name = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (MarkMoments.nameSeconds * 1000).round()),
    // A fade, not motion: reduced motion keeps it.
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_onNameDone);

  void _onNameDone(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _named = null);
    }
  }

  /// The kind of mark whose name shows.
  String? _named;

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
  /// mark), and not for a pinned mark.
  void _onSeen() {
    if (!_noteSeen() || ref.read(pinnedMarkProvider) != null) return;
    final type = ref.read(homeMarkProvider).type;
    setState(() => _named = type);
    _name.forward(from: 0);
    final l10n = AppLocalizations.of(context)!;
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.homeMarkTodayIs(l10n.homeMarkName(type)),
      Directionality.of(context),
    ).ignore();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pinned = ref.watch(pinnedMarkProvider) != null;
    ref.watch(identityDayProvider);
    // Back to the daily mark: it simply draws in, as on a pin. The day
    // the pinned mark was seen counts as seen.
    ref.listen(pinnedMarkProvider, (previous, next) {
      if (previous != null && next == null) _noteSeen();
    });
    final scheme = Theme.of(context).colorScheme;
    final named = _named;
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
            GestureDetector(
              // The breath is felt, not announced: no action for TalkBack.
              excludeFromSemantics: true,
              onTap: () => _mark.currentState?.breathe(),
              child: MeditejoMark(
                key: _mark,
                mark: ref.watch(homeMarkProvider),
                size: kHomeMarkSize,
                animate: widget.animate,
                from: pinned ? null : _arrivingFrom(),
                onSeen: _onSeen,
              ),
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
            if (named != null)
              // Below the mark, in the gap above the first section, so it
              // shifts nothing as it comes and goes.
              Positioned(
                top: kHomeMarkSize + 2,
                left: -96,
                right: -96,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: _name,
                      builder: (context, child) => Opacity(
                        opacity: MarkMoments.nameOpacityAt(
                          _name.value * MarkMoments.nameSeconds,
                        ),
                        child: child,
                      ),
                      child: Text(
                        l10n.homeMarkName(named),
                        key: const ValueKey('home_mark_name'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: context.typography.baseline.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
