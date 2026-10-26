import 'package:medito/widgets/adaptive/adaptive_content.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_sidebar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
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
  // Explore, Library, Settings. Search lives inside Explore.
  final _exploreViewKey = GlobalKey<ExploreViewState>();
  late final List<Widget> _pages;
  bool _restoringEndScreen = false;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomeView(),
      ExploreView(key: _exploreViewKey),
      const LibraryView(),
      const SettingsScreen(),
    ];

    if (ref.read(mainTabProvider) == MainTab.explore) {
      // Restored straight into Explore.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => catchUpDharmaSeed(ref),
      );
    }
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboardInset > 0;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 700;
    final items = [
      MeditoNavItem(icon: MeditoIcons.home, label: l10n.home),
      MeditoNavItem(icon: MeditoIcons.search, label: l10n.explore),
      MeditoNavItem(icon: MeditoIcons.libraries, label: l10n.libraryTitle),
      MeditoNavItem(icon: MeditoIcons.settings, label: l10n.settings),
    ];

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

  void _onDestinationSelected(int index) =>
      ref.read(mainTabProvider.notifier).select(MainTab.values[index]);

  void _onTabChanged(MainTab tab) {
    // Leaving a tab dismisses its keyboard so it doesn't linger over another.
    FocusManager.instance.primaryFocus?.unfocus();

    // Opening Explore is when the Dharma Seed catalogue catches up with what
    // changed since the bundled copy; never at startup.
    if (tab == MainTab.explore) {
      _exploreViewKey.currentState?.loadData();
      catchUpDharmaSeed(ref);
    }
  }
}
