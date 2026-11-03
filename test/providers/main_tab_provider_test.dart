import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The keys an earlier build saved the last tab under. Nothing reads them now.
const _savedTabKey = 'last_main_tab_index';
const _savedLayoutKey = 'main_tab_layout';

Future<ProviderContainer> _open(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a cold start opens Home, even when another tab was saved', () async {
    for (final saved in [1, 2, 3, 4]) {
      final container = await _open({_savedTabKey: saved, _savedLayoutKey: 3});
      expect(container.read(mainTabProvider), MainTab.home, reason: '$saved');
    }
  });

  test('the tab keys an earlier build saved are removed on startup', () async {
    final container = await _open({_savedTabKey: 2, _savedLayoutKey: 3});
    expect(container.read(mainTabProvider), MainTab.home);
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.containsKey(_savedTabKey), isFalse);
    expect(prefs.containsKey(_savedLayoutKey), isFalse);
  });

  test('a fresh install opens Home', () async {
    final container = await _open({});
    expect(container.read(mainTabProvider), MainTab.home);
  });

  test('selecting a tab moves to it', () async {
    final container = await _open({});
    final tabs = container.read(mainTabProvider.notifier);

    tabs.select(MainTab.sounds);
    expect(container.read(mainTabProvider), MainTab.sounds);

    tabs.select(MainTab.settings);
    expect(container.read(mainTabProvider), MainTab.settings);
  });

  group('links that open a tab', () {
    test('map to the tab they name; search is Explore', () {
      expect(tabForLink('home'), MainTab.home);
      expect(tabForLink('explore'), MainTab.explore);
      expect(tabForLink('search'), MainTab.explore);
      expect(tabForLink('sounds'), MainTab.sounds);
      expect(tabForLink('library'), MainTab.library);
      expect(tabForLink('settings'), MainTab.settings);
      // You is a page over the tabs, not a tab.
      expect(tabForLink('you'), isNull);
      expect(tabForLink('tracks'), isNull);
    });

    test('the tab order is the bar order', () {
      expect(MainTab.values.map((t) => t.name), [
        'home',
        'explore',
        'sounds',
        'library',
        'settings',
      ]);
    });
  });
}
