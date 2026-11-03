import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The five tabs, in bar order.
enum MainTab { home, explore, sounds, library, you }

/// The tab on screen. Any screen can move it (Home's "See all", a deep link);
/// the main screen listens and does the rest. The app always opens on Home.
final mainTabProvider = NotifierProvider<MainTabNotifier, MainTab>(
  MainTabNotifier.new,
);

class MainTabNotifier extends Notifier<MainTab> {
  @override
  MainTab build() => MainTab.home;

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
