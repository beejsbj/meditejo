import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/views/bottom_navigation/bottom_navigation_bar_view.dart';
import 'package:medito/views/settings/settings_screen.dart';
import 'package:medito/views/soundscape/sounds_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/soundscape_fakes.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    // You shows Settings, whose reminder row asks for the notification
    // permission's status.
    const permissions = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissions, (_) async => 1);
    addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
    final app = await LibraryTestApp.create(tester);
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

  testWidgets('five tabs; Sounds is the Sounds screen, You is Settings', (
    tester,
  ) async {
    final container = await pump(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(5));
    for (final label in ['Home', 'Explore', 'Sounds', 'Library', 'You']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Sounds'),
      ),
    );
    await settle(tester);
    expect(container.read(mainTabProvider), MainTab.sounds);
    expect(onScreen(tester, SoundsView), isTrue);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('You'),
      ),
    );
    await settle(tester);
    expect(container.read(mainTabProvider), MainTab.you);
    expect(onScreen(tester, SettingsScreen), isTrue);
  });

  testWidgets('back folds an open mix on the Sounds tab, then goes Home', (
    tester,
  ) async {
    final container = await pump(tester);
    container.read(mainTabProvider.notifier).select(MainTab.sounds);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
    await settle(tester);
    expect(find.byKey(const ValueKey('sounds_volume')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(container.read(mainTabProvider), MainTab.sounds);
    expect(find.byKey(const ValueKey('sounds_volume')), findsNothing);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(container.read(mainTabProvider), MainTab.home);
  });
}
