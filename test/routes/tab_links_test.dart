import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;
  late BuildContext context;
  late WidgetRef widgetRef;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          navigatorKey: navigatorKey,
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

  testWidgets('meditejo://sounds and you select their tab; settings is You', (
    tester,
  ) async {
    await pump(tester);

    await handleNavigation('sounds', [''], context, ref: widgetRef);
    expect(container.read(mainTabProvider), MainTab.sounds);

    await handleNavigation('you', [''], context, ref: widgetRef);
    expect(container.read(mainTabProvider), MainTab.you);

    await handleNavigation('home', [''], context, ref: widgetRef);
    await handleNavigation('settings', [''], context, ref: widgetRef);
    expect(container.read(mainTabProvider), MainTab.you);
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
}
