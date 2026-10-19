import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(SharedPreferences, ProviderContainer)> _open(
  Map<String, Object> values,
) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return (prefs, container);
}

void main() {
  group('the saved tab index from the Home · Explore · Search · Settings bar', () {
    test('Home and Explore carry over unchanged', () async {
      for (final (saved, tab) in [(0, MainTab.home), (1, MainTab.explore)]) {
        final (prefs, container) = await _open({
          SharedPreferenceConstants.lastMainTabIndex: saved,
        });
        expect(container.read(mainTabProvider), tab);
        // Rewritten in the new bar's terms, once.
        expect(prefs.getInt(SharedPreferenceConstants.mainTabLayout), 2);
        expect(prefs.getInt(SharedPreferenceConstants.lastMainTabIndex), saved);
      }
    });

    test('an index that named Search or Settings opens Home, never Library', () async {
      for (final saved in [2, 3, 4, -1, 99]) {
        final (prefs, container) = await _open({
          SharedPreferenceConstants.lastMainTabIndex: saved,
        });
        expect(container.read(mainTabProvider), MainTab.home, reason: '$saved');
        expect(prefs.getInt(SharedPreferenceConstants.lastMainTabIndex), 0);
      }
    });

    test('a fresh install opens Home', () async {
      final (_, container) = await _open({});
      expect(container.read(mainTabProvider), MainTab.home);
    });
  });

  group('the four-tab bar', () {
    test('restores Library, but never Settings', () async {
      final (_, container) = await _open({
        SharedPreferenceConstants.lastMainTabIndex: 2,
        SharedPreferenceConstants.mainTabLayout: 2,
      });
      expect(container.read(mainTabProvider), MainTab.library);

      final (_, settings) = await _open({
        SharedPreferenceConstants.lastMainTabIndex: 3,
        SharedPreferenceConstants.mainTabLayout: 2,
      });
      expect(settings.read(mainTabProvider), MainTab.home);
    });

    test('selecting remembers every tab but Settings', () async {
      final (prefs, container) = await _open({});
      final tabs = container.read(mainTabProvider.notifier);

      tabs.select(MainTab.library);
      expect(container.read(mainTabProvider), MainTab.library);
      expect(prefs.getInt(SharedPreferenceConstants.lastMainTabIndex), 2);

      tabs.select(MainTab.settings);
      expect(container.read(mainTabProvider), MainTab.settings);
      expect(prefs.getInt(SharedPreferenceConstants.lastMainTabIndex), 2);
    });
  });

  group('links that open a tab', () {
    test('map to the tab they name; search is Explore', () {
      expect(tabForLink('home'), MainTab.home);
      expect(tabForLink('explore'), MainTab.explore);
      expect(tabForLink('search'), MainTab.explore);
      expect(tabForLink('library'), MainTab.library);
      expect(tabForLink('tracks'), isNull);
      expect(tabForLink('settings'), isNull);
    });

    test('the tab order is the saved format', () {
      expect(MainTab.values.map((t) => t.name), [
        'home',
        'explore',
        'library',
        'settings',
      ]);
    });
  });
}
