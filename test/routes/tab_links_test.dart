import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/settings/settings_screen.dart';
import 'package:medito/views/you/you_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/update_fakes.dart';

class _EmptyStats extends StatsNotifier {
  @override
  Future<LocalAllStats> build() async => LocalAllStats.empty();

  @override
  Future<void> refresh() async {}
}

void main() {
  late ProviderContainer container;
  late BuildContext context;
  late WidgetRef widgetRef;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // The You page reads the stats.
          statsProvider.overrideWith(_EmptyStats.new),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (c, ref, _) {
              context = c;
              widgetRef = ref;
              return const Scaffold(body: Text('root'));
            },
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(context);
  }

  testWidgets('meditejo://library, explore and home select their tab', (
    tester,
  ) async {
    await pump(tester);
    expect(container.read(mainTabProvider), MainTab.home);

    await handleNavigation('library', [''], context, ref: widgetRef);
    expect(container.read(mainTabProvider), MainTab.library);

    await handleNavigation('explore', [''], context, ref: widgetRef);
    expect(container.read(mainTabProvider), MainTab.explore);

    await handleNavigation('home', [''], context, ref: widgetRef);
    expect(container.read(mainTabProvider), MainTab.home);
  });

  testWidgets('meditejo://sounds and settings select their tab', (
    tester,
  ) async {
    await pump(tester);

    await handleNavigation('sounds', [''], context, ref: widgetRef);
    expect(container.read(mainTabProvider), MainTab.sounds);

    await handleNavigation('settings', [''], context, ref: widgetRef);
    expect(container.read(mainTabProvider), MainTab.settings);
  });

  testWidgets('meditejo://you, the old You tab, opens the You page', (
    tester,
  ) async {
    await pump(tester);
    await handleNavigation('library', [''], context, ref: widgetRef);
    // Something open above the tabs closes first.
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('page'))),
    );
    await tester.pumpAndSettle();

    handleNavigation('you', [''], context, ref: widgetRef).ignore();
    await tester.pumpAndSettle();

    expect(find.text('page'), findsNothing);
    expect(find.byType(YouView), findsOneWidget);
    expect(find.byKey(const ValueKey('you_stats_card')), findsOneWidget);
    // Over the tab that was open; You is not a tab.
    expect(container.read(mainTabProvider), MainTab.library);

    // Back returns to the tabs.
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(YouView), findsNothing);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('search opens Explore and asks for the cursor', (tester) async {
    await pump(tester);
    expect(container.read(exploreFocusRequestProvider), 0);

    await handleNavigation('search', [''], context, ref: widgetRef);

    expect(container.read(mainTabProvider), MainTab.explore);
    expect(container.read(exploreFocusRequestProvider), 1);
  });

  testWidgets('a tab link closes what is open above the tabs', (tester) async {
    await pump(tester);
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('page'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);

    await handleNavigation('library', [''], context, ref: widgetRef);
    await tester.pumpAndSettle();

    expect(find.text('page'), findsNothing);
    expect(container.read(mainTabProvider), MainTab.library);
  });

  testWidgets('another *settings* link pushes Settings, with a way back', (
    tester,
  ) async {
    // Settings' reminder row asks for the notification permission.
    const permissions = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissions, (_) async => 1);
    addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
    final h = await UpdateHarness.create();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          statsProvider.overrideWith(_EmptyStats.new),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (c, ref, _) {
              context = c;
              widgetRef = ref;
              return const Scaffold(body: Text('root'));
            },
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(context);

    handleNavigation(
      'notification_settings',
      [''],
      context,
      ref: widgetRef,
    ).ignore();
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    // Pushed over the tabs, not the tab itself.
    expect(container.read(mainTabProvider), MainTab.home);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('root'), findsOneWidget);
  });
}
