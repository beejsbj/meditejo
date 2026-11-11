import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';

// What earlier builds saved the last tab under. Nothing reads them now; they
// are removed on startup.
const _legacyTabIndexKey = 'last_main_tab_index';
const _legacyTabLayoutKey = 'main_tab_layout';

/// The four tabs, in bar order. Sounds is not one: it is a sheet over
/// whatever is open (`showSoundsSheet`).
enum MainTab { home, explore, library, settings }

/// The tab on screen. Any screen can move it (Home's "See all", a deep link);
/// the main screen listens and does the rest. The app always opens on Home.
final mainTabProvider = NotifierProvider<MainTabNotifier, MainTab>(
  MainTabNotifier.new,
);

class MainTabNotifier extends Notifier<MainTab> {
  @override
  MainTab build() {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.remove(_legacyTabIndexKey);
    prefs.remove(_legacyTabLayoutKey);
    return MainTab.home;
  }

  void select(MainTab tab) {
    if (state == tab) return;
    state = tab;
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
