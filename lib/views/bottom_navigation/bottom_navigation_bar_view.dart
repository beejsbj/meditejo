import 'package:medito/widgets/adaptive/adaptive_content.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_sidebar.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/utils/pending_end_screen.dart';
import 'package:medito/views/end_screen/end_screen_view.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_nav_bar.dart';
import 'package:medito/views/explore/widgets/explore_view.dart';
import 'package:medito/views/library/share_intake_host.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/settings/settings_screen.dart';

class BottomNavigationBarView extends ConsumerStatefulWidget {
  const BottomNavigationBarView({super.key});

  @override
  ConsumerState<BottomNavigationBarView> createState() =>
      _BottomNavigationBarViewState();
}

class _BottomNavigationBarViewState
    extends ConsumerState<BottomNavigationBarView> {
  // Nav destination index == MainTab index == page index in _pages: Home,
  // Explore, Library, Settings. Search lives inside Explore; You (stats and
  // history) is a page opened from Home, Library and Settings; Sounds is a
  // sheet over any of them.
  final _exploreViewKey = GlobalKey<ExploreViewState>();
  late final List<Widget> _pages;
  bool _restoringEndScreen = false;

  @override
  void initState() {
    super.initState();
    _pages = [for (final tab in MainTab.values) _page(tab)];

    _initializeStats();
    _trackPlaybackPositions();
    // Completions replayed by the platform after launch arrive late (Android
    // pushes them from onResume), so listen as well as check now.
    PendingEndScreen.completions.addListener(_restorePendingEndScreen);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restorePendingEndScreen(),
    );
  }

  /// Remembers where the user is in each session, for Resume.
  void _trackPlaybackPositions() {
    final tracker = ref.read(playbackPositionTrackerProvider);
    ref.listenManual(audioStateProvider, (_, state) {
      tracker.onState(
        trackId: state.track.id,
        fileId: state.track.fileId,
        positionMs: state.position,
        durationMs: state.duration,
        isPlaying: state.isPlaying,
        isCompleted: state.isCompleted,
      );
    });
  }

  @override
  void dispose() {
    PendingEndScreen.completions.removeListener(_restorePendingEndScreen);
    super.dispose();
  }

  /// Shows the end screen of a session that finished while the app was in the
  /// background and was killed before that end screen could open. Rebuilt in
  /// place, without a route transition, as if it had been there all along.
  Future<void> _restorePendingEndScreen() async {
    if (_restoringEndScreen || PendingEndScreen.hasLivePlayer) return;
    _restoringEndScreen = true;
    try {
      final pending = await PendingEndScreen.takeCompleted(
        ref.read(sharedPreferencesProvider),
      );
      if (pending == null || !mounted) return;
      AppLogger.d(
        'END_SCREEN',
        'Restoring end screen: ${pending.request.fileId}',
      );

      unawaited(
        Navigator.of(context).push(
          PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => EndScreenView(
              request: pending.request,
              priorStats: pending.priorStats,
              restoredFrom: pending.completedAt,
            ),
          ),
        ),
      );
    } finally {
      _restoringEndScreen = false;
    }
  }

  Future<void> _initializeStats() async {
    await ref.read(statsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentTab = ref.watch(mainTabProvider);
    final currentIndex = currentTab.index;
    ref.listen(mainTabProvider, (_, next) => _onTabChanged(next));
    // Which library items carry a practice with its own figure variants,
    // for their covers on every screen (art_subject.dart, artPractices).
    ref.listen(libraryLabelsProvider, (_, next) {
      final labels = next.value;
      if (labels == null) return;
      final practices = <String, String>{
        for (final MapEntry(:key, :value) in labels.entries)
          key: ?artPractice(value),
      };
      // Only a real change refreshes covers; it is saved so the next launch
      // draws the same covers from its first frame (main.dart).
      if (mapEquals(practices, artPractices.value)) return;
      artPractices.value = practices;
      unawaited(
        ref
            .read(sharedPreferencesProvider)
            .setString(
              SharedPreferenceConstants.artPractices,
              jsonEncode(practices),
            ),
      );
    });
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboardInset > 0;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 700;
    final items = [for (final tab in MainTab.values) _navItem(tab, l10n)];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: wide
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainer,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: ShareIntakeHost(
        child: PopScope(
          canPop: currentTab == MainTab.home,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _onDestinationSelected(MainTab.home.index);
          },
          child: Scaffold(
            // The nav bar is lifted to sit just above the keyboard (via the
            // bottom-inset padding below) rather than hiding behind it, so a tap
            // aimed at the Search tab hits the icon instead of the keyboard's
            // spacebar. resizeToAvoidBottomInset stays false so the Scaffold
            // doesn't also inset the body — padding the bar already reserves the
            // keyboard's height, shrinking the body to sit above it.
            resizeToAvoidBottomInset: false,
            bottomNavigationBar: wide
                ? null
                : Padding(
                    padding: EdgeInsets.only(bottom: keyboardInset),
                    // While the keyboard is open the bar sits directly on top of it, so
                    // drop the bar's bottom safe-area (home-indicator) inset — otherwise
                    // it leaves a gap between the tabs and the keyboard.
                    child: MediaQuery.removePadding(
                      context: context,
                      removeBottom: keyboardOpen,
                      child: MeditoNavBar(
                        selectedIndex: currentIndex,
                        onSelected: _onDestinationSelected,
                        items: items,
                      ),
                    ),
                  ),
            body: Padding(
              padding: EdgeInsets.only(bottom: wide ? keyboardInset : 0),
              child: Row(
                children: [
                  if (wide)
                    MeditoSidebar(
                      extended: width >= 1100,
                      items: items,
                      selectedIndex: currentIndex,
                      onSelected: _onDestinationSelected,
                    ),
                  Expanded(
                    key: const ValueKey('main-content'),
                    child: AdaptiveContent(
                      child: IndexedStack(
                        index: currentIndex,
                        children: _pages,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // A tab is a MainTab value plus one arm in each switch below; the bar and
  // the sidebar take any number of destinations.
  Widget _page(MainTab tab) => switch (tab) {
    MainTab.home => const HomeView(),
    MainTab.explore => ExploreView(key: _exploreViewKey),
    MainTab.library => const LibraryView(),
    MainTab.settings => const SettingsScreen(),
  };

  static MeditoNavItem _navItem(MainTab tab, AppLocalizations l10n) =>
      switch (tab) {
        MainTab.home => MeditoNavItem(
          icon: Symbols.home_rounded,
          label: l10n.home,
        ),
        MainTab.explore => MeditoNavItem(
          icon: Symbols.search_rounded,
          label: l10n.explore,
        ),
        MainTab.library => MeditoNavItem(
          icon: Symbols.library_books_rounded,
          label: l10n.navLibrary,
        ),
        MainTab.settings => MeditoNavItem(
          icon: Symbols.settings_rounded,
          label: l10n.navSettings,
        ),
      };

  void _onDestinationSelected(int index) =>
      ref.read(mainTabProvider.notifier).select(MainTab.values[index]);

  void _onTabChanged(MainTab tab) {
    // Leaving a tab dismisses its keyboard so it doesn't linger over another.
    FocusManager.instance.primaryFocus?.unfocus();

    // Opening Explore is when the Dharma Seed catalogue catches up with what
    // changed since the bundled copy; never at startup.
    if (tab == MainTab.explore) {
      _exploreViewKey.currentState?.loadData();
      catchUpCatalogues(ref);
    }
  }
}
