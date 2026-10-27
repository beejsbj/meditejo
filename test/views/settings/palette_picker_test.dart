import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/views/settings/widgets/identity_tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app as main.dart builds it: the theme follows the active palette.
class _App extends ConsumerWidget {
  const _App(this.brightness);

  final Brightness brightness;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: meditejoTheme(brightness, ref.watch(activePaletteProvider)),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(
      body: Column(children: [PaletteTile(), HomeMarkTile()]),
    ),
  );
}

Future<SharedPreferences> _pump(
  WidgetTester tester, [
  Brightness brightness = Brightness.light,
]) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: _App(brightness),
    ),
  );
  return prefs;
}

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(PaletteTile))).colorScheme;

void main() {
  setUp(() {
    identityClock = () => DateTime(2026, 10, 27, 9);
  });
  tearDown(() {
    identityClock = DateTime.now;
  });

  testWidgets('Tidewater by default; choosing a palette themes the app', (
    tester,
  ) async {
    final prefs = await _pump(tester);
    final tide = IdentityPalettes.byId('tide');
    expect(
      find.textContaining('Tidewater', findRichText: true),
      findsOneWidget,
    );
    expect(_scheme(tester).surface, Color(tide.light.bg));

    await tester.tap(find.byKey(const ValueKey('settings_palette')));
    await tester.pumpAndSettle();
    // Daily first, then every palette.
    expect(find.byKey(const ValueKey('palette_daily')), findsOneWidget);
    for (final p in IdentityPalettes.all.take(4)) {
      expect(find.byKey(ValueKey('palette_${p.id}')), findsOneWidget);
    }
    final dusk = find.byKey(const ValueKey('palette_dusk'));
    expect(
      tester.getSemantics(dusk).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    await tester.tap(dusk);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(dusk).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(prefs.getString(SharedPreferenceConstants.identityPalette), 'dusk');

    await tester.pageBack();
    await tester.pumpAndSettle();
    final scheme = _scheme(tester);
    final palette = Theme.of(
      tester.element(find.byType(PaletteTile)),
    ).extension<MeditejoPalette>()!;
    expect(palette.palette.id, 'dusk');
    expect(scheme.surface, Color(IdentityPalettes.byId('dusk').light.bg));
    expect(find.textContaining('Dusk', findRichText: true), findsOneWidget);
  });

  testWidgets('Daily lets the date choose, and says which', (tester) async {
    final prefs = await _pump(tester, Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('settings_palette')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette_daily')));
    await tester.pumpAndSettle();
    expect(prefs.getString(SharedPreferenceConstants.identityPalette), 'daily');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Daily · Lotus Riso today', findRichText: true),
      findsOneWidget,
    );
    expect(
      _scheme(tester).surface,
      Color(IdentityPalettes.byId('riso').dark.bg),
    );
  });

  testWidgets('every board renders in light and dark', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, b);
      await tester.tap(find.byKey(const ValueKey('settings_palette')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('palette_ember')),
        200,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('boards fit a narrow phone at large text', (tester) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(360, 1400);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings_palette')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('palette_ember')),
      200,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pin sheet scrolls rather than overflow in landscape', (
    tester,
  ) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(780, 360);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings_home_mark')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('home_mark_pin')),
      100,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(const ValueKey('home_mark_pin')), findsOneWidget);
  });
}
