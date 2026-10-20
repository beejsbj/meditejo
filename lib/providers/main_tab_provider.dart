import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';

/// The four tabs, in bar order. The index is what is saved, so the order is a
/// storage format: change it only with a new [MainTab.layout].
enum MainTab {
  home,
  explore,
  library,
  settings;

  /// The tab bar this order belongs to. The first bar (Home · Explore ·
  /// Search · Settings) never wrote a layout.
  static const layout = 2;

  /// Which tab to open on launch from what was [saved] (an index, or null) by
  /// a bar of the given [savedLayout].
  ///
  /// Settings is never restored, and a saved index that names nothing now
  /// (or, from the first bar, names Search or Settings) opens Home. The first
  /// bar saved only Home and Explore, so their indices carry over unchanged.
  static MainTab restore(int? saved, {int? savedLayout}) {
    if (saved == null || saved < 0 || saved >= values.length) return home;
    final tab = values[saved];
    if (tab == settings) return home;
    if (savedLayout == null && tab == library) return home;
    return tab;
  }
}

/// The tab on screen. Any screen can move it (Home's "See all", a deep link);
/// the main screen listens and does the rest.
final mainTabProvider = NotifierProvider<MainTabNotifier, MainTab>(
  MainTabNotifier.new,
);

class MainTabNotifier extends Notifier<MainTab> {
  @override
  MainTab build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final tab = MainTab.restore(
      prefs.getInt(SharedPreferenceConstants.lastMainTabIndex),
      savedLayout: prefs.getInt(SharedPreferenceConstants.mainTabLayout),
    );
    // Rewrite what an older bar saved in this bar's terms, once.
    if (prefs.getInt(SharedPreferenceConstants.mainTabLayout) !=
        MainTab.layout) {
      _save(tab);
    }
    return tab;
  }

  void select(MainTab tab) {
    if (state == tab) return;
    state = tab;
    _save(tab);
  }

  void _save(MainTab tab) {
    // Settings is a place to visit, not to return to.
    if (tab == MainTab.settings) return;
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setInt(SharedPreferenceConstants.mainTabLayout, MainTab.layout);
    prefs.setInt(SharedPreferenceConstants.lastMainTabIndex, tab.index);
  }
}

/// Asks Explore to put the cursor in its search field (the `meditejo://search`
/// link). Each request bumps the count.
final exploreFocusRequestProvider =
    NotifierProvider<ExploreFocusRequestNotifier, int>(
      ExploreFocusRequestNotifier.new,
    );

class ExploreFocusRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;

  void consume(int request) {
    if (state == request) state = 0;
  }
}
