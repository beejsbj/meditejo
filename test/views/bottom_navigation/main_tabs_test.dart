import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/views/bottom_navigation/bottom_navigation_bar_view.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/settings/settings_screen.dart';
import 'package:medito/views/soundscape/sounds_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/soundscape_fakes.dart';

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Map<String, int> savedPrefs = const {},
  }) async {
    // Settings' reminder row asks for the notification permission's
    // status.
    const permissions = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissions, (_) async => 1);
    addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
    final app = await LibraryTestApp.create(tester);
    await tester.runAsync(() async {
      for (final entry in savedPrefs.entries) {
        await app.prefs.setInt(entry.key, entry.value);
      }
    });
    await app.pump(
      tester,
      // Still, so Home's mark lets the frames settle.
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: const BottomNavigationBarView(),
        ),
      ),
      overrides: [
        continueItemsProvider.overrideWith((ref) async => []),
        ...soundscapeTestOverrides(FakeSoundscapeEngine()),
      ],
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(BottomNavigationBarView)),
    );
  }

  Future<void> settle(WidgetTester tester) =>
      DharmaSeedTestApp.settle(tester, rounds: 2);

  bool onScreen(WidgetTester tester, Type type) =>
      find.byType(type).hitTestable().evaluate().isNotEmpty;

  testWidgets('four tabs, and Sounds is not one of them', (tester) async {
    final container = await pump(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(4));
    expect(MainTab.values, hasLength(4));
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Sounds'),
      ),
      findsNothing,
    );
    expect(find.byType(SoundsView, skipOffstage: false), findsNothing);
    for (final label in ['Home', 'Explore', 'Library', 'Settings']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }

    // Each destination is its tab, in bar order.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Library'),
      ),
    );
    await settle(tester);
    expect(container.read(mainTabProvider), MainTab.library);
    expect(onScreen(tester, LibraryView), isTrue);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await settle(tester);
    expect(container.read(mainTabProvider), MainTab.settings);
    expect(onScreen(tester, SettingsScreen), isTrue);
    // The settings themselves, and no stats: those are on the You page.
    expect(
      find.byKey(const ValueKey('settings_practice')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('you_stats_card')), findsNothing);
  });

  testWidgets('a cold start opens Home, even with another tab saved', (
    tester,
  ) async {
    // Keys an earlier build saved the last tab under: Sounds in that bar,
    // Library in this one.
    final container = await pump(
      tester,
      savedPrefs: const {'last_main_tab_index': 2, 'main_tab_layout': 3},
    );
    await settle(tester);
    expect(container.read(mainTabProvider), MainTab.home);
    expect(onScreen(tester, LibraryView), isFalse);
    expect(find.byType(BottomNavigationBarView), findsOneWidget);
  });

  testWidgets('Home\'s Sounds tile opens the Sounds sheet over the tabs; back '
      'closes it and stays on Home', (tester) async {
    final container = await pump(tester);
    await settle(tester);
    final tile = find.byKey(const ValueKey('shortcut_sounds'));
    await tester.ensureVisible(tile);
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(onScreen(tester, SoundsView), isTrue);
    expect(container.read(mainTabProvider), MainTab.home);
    // The tabs are still there, under it.
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(SoundsView), findsNothing);
    expect(container.read(mainTabProvider), MainTab.home);
    expect(find.byType(BottomNavigationBarView), findsOneWidget);
  });
}
