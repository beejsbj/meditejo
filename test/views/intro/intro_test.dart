
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/intro/first_run_intro.dart';
import 'package:medito/views/intro/intro_view.dart';
import 'package:medito/views/splash_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the tabs, which open on Home.
const _home = Scaffold(body: Text('HOME'));

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

/// The app as it starts: the splash, then the tabs, with the intro over
/// them when it is due. The mark stands still so pages settle.
Widget _app(
  SharedPreferences prefs, {
  Widget home = const SplashView(root: _home),
}) => ProviderScope(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: home,
  ),
);

Future<void> _launch(WidgetTester tester, SharedPreferences prefs) async {
  await tester.pumpWidget(_app(prefs));
  await tester.pumpAndSettle();
}

void main() {
  group('FirstRunIntro', () {
    test('a fresh install is due the intro, even after settling', () async {
      final prefs = await _prefs();
      await FirstRunIntro.settleForExistingInstall(prefs);
      expect(FirstRunIntro.isDue(prefs), isTrue);
    });

    test('whoever answered Medito\'s questionnaire skips it', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.onboardingExperienceLevel: 1,
      });
      await FirstRunIntro.settleForExistingInstall(prefs);
      expect(FirstRunIntro.isDue(prefs), isFalse);
    });

    test('an install already in use skips it on upgrade', () async {
      for (final key in [
        SharedPreferenceConstants.installedVersionHistory,
        SharedPreferenceConstants.localAllStatsKey,
        SharedPreferenceConstants.pinnedCourseIds,
      ]) {
        final prefs = await _prefs({
          key: key == SharedPreferenceConstants.pinnedCourseIds
              ? <String>['ds-1']
              : '[]',
        });
        await FirstRunIntro.settleForExistingInstall(prefs);
        expect(FirstRunIntro.isDue(prefs), isFalse, reason: key);
      }
    });
  });

  testWidgets('first launch shows the intro once; Start lands on Home', (
    tester,
  ) async {
    final prefs = await _prefs();
    await _launch(tester, prefs);

    expect(find.byType(IntroView), findsOneWidget);
    expect(find.text('Meditejo'), findsOneWidget);
    expect(find.text('One calm place for your practice.'), findsOneWidget);
    // No tour until there is one: no button that does nothing.
    expect(find.byKey(const ValueKey('intro_tour')), findsNothing);
    expect(find.text('Take the tour'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('intro_start')));
    await tester.pumpAndSettle();
    expect(find.byType(IntroView), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
    expect(prefs.getBool(SharedPreferenceConstants.introSeen), isTrue);

    // The next launch goes straight to Home.
    await tester.pumpWidget(const SizedBox());
    await _launch(tester, prefs);
    expect(find.byType(IntroView), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('Back skips the intro too, and counts as seen', (tester) async {
    final prefs = await _prefs();
    await _launch(tester, prefs);
    expect(find.byType(IntroView), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(IntroView), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
    expect(FirstRunIntro.isDue(prefs), isFalse);
  });

  testWidgets('an upgrade from the questionnaire never sees it', (
    tester,
  ) async {
    final prefs = await _prefs({
      SharedPreferenceConstants.onboardingExperienceLevel: 2,
    });
    // What main() does before the app starts.
    await FirstRunIntro.settleForExistingInstall(prefs);
    await _launch(tester, prefs);
    expect(find.byType(IntroView), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('the tour button appears once a tour is wired in', (
    tester,
  ) async {
    final prefs = await _prefs();
    var toured = false;
    await tester.pumpWidget(
      _app(
        prefs,
        home: IntroView(firstRun: true, onTakeTour: () => toured = true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('intro_tour')));
    expect(toured, isTrue);
  });

  testWidgets('opened from About it has a back arrow, not Start, and does not '
      'touch the first-launch flag', (tester) async {
    final prefs = await _prefs();
    await tester.pumpWidget(
      _app(
        prefs,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const IntroView()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('intro_app_bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro_start')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(prefs.getBool(SharedPreferenceConstants.introSeen), isNull);
  });
}
