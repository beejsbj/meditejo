import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/settings/settings_screen.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/views/you/you_view.dart';
import 'package:medito/views/home/widgets/pinned/pinned_list_view.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/no_hearts.dart';
import '../../helpers/stats_fixtures.dart';

final _youButton = find.byKey(const ValueKey('you_button'));

/// Settings' reminder row asks for the notification permission's status.
void _mockPermissions() {
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(permissions, (_) async => 1);
  addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
}

/// [page] as the tab shows it, still, so Home's mark lets the frames settle.
Future<void> _pumpTab(WidgetTester tester, Widget page) async {
  _mockPermissions();
  final app = await LibraryTestApp.create(tester);
  await app.pump(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: page,
      ),
    ),
    overrides: [continueItemsProvider.overrideWith((ref) async => [])],
  );
}

class _Talk extends Tracks {
  @override
  Future<Track> build({required String trackId}) async => Track(
    id: trackId,
    title: 'Metta',
    description: '',
    coverUrl: '',
    isPublished: true,
    hasBackgroundSound: false,
    voices: const [],
  );
}

class _Stats extends StatsNotifier {
  _Stats(this.stats);
  final LocalAllStats stats;
  @override
  Future<LocalAllStats> build() async => stats;
}

/// The You page on the fixed stats history.
Future<void> _pumpYou(
  WidgetTester tester, {
  bool zen = false,
  Map<String, Object> pins = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    if (zen) SharedPreferenceConstants.zenModeEnabled: true,
    ...pins,
  });
  final prefs = await SharedPreferences.getInstance();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        statsProvider.overrideWith(() => _Stats(fixtureStats())),
        practiceClockProvider.overrideWithValue(() => fixtureNow),
        tracksProvider(trackId: 'ds-talk-1').overrideWith(_Talk.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const YouView(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the You button', () {
    final surfaces = <String, Widget>{
      'Home': const HomeView(),
      'Library': const LibraryView(),
      'Settings': const SettingsScreen(),
    };

    for (final MapEntry(key: name, value: page) in surfaces.entries) {
      testWidgets('is at the top right of $name and opens the You page', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pumpTab(tester, page);

        expect(_youButton, findsOneWidget);
        expect(find.byTooltip('You: stats and history'), findsOneWidget);
        expect(find.bySemanticsLabel('You: stats and history'), findsOneWidget);
        // The same place on all three: the rightmost control of the
        // header, 4 dp in from the edge and 4 dp down, 48 dp square.
        expect(tester.getRect(_youButton), const Rect.fromLTWH(378, 4, 48, 48));

        await tester.tap(_youButton);
        await DharmaSeedTestApp.settle(tester);

        expect(find.byType(YouView), findsOneWidget);
        expect(find.byKey(const ValueKey('you_stats_card')), findsOneWidget);
        // A pushed page: back returns to where it was opened.
        expect(find.byType(BackButton), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await DharmaSeedTestApp.settle(tester);
        expect(find.byType(YouView), findsNothing);
        expect(find.byType(page.runtimeType), findsOneWidget);
        handle.dispose();
      });
    }
  });

  group('the Settings tab', () {
    testWidgets('shows the settings and no stats', (tester) async {
      await _pumpTab(tester, const SettingsScreen());
      expect(find.text('Settings'), findsOneWidget);
      for (final key in [
        'settings_practice',
        'settings_sounds',
        'settings_library',
        'settings_sources',
        'settings_appearance',
        'settings_reminders',
        'settings_about',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const ValueKey('you_stats_card')), findsNothing);
      expect(find.text('Session history'), findsNothing);
      expect(find.byKey(const ValueKey('you_pinned')), findsNothing);
      expectNoHearts();
      // At the top of the tabs there is nothing to go back to.
      expect(find.byType(BackButton), findsNothing);
    });
  });

  group('the You page', () {
    testWidgets('shows the stats summary, history and pins', (tester) async {
      await _pumpYou(tester);
      expect(find.text('You'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Stats, This week: 1 h 30 min, Total time: 3 h 20 min, '
          'Current streak: 2 days',
        ),
        findsOneWidget,
      );
      expect(find.text('Your practice'), findsOneWidget);
      expect(find.text('Session history'), findsOneWidget);
      expect(find.text('Pinned'), findsOneWidget);
      // Pins, with a pin: nothing is a favourite any more (#79).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('you_pinned')),
          matching: find.byIcon(Icons.push_pin_outlined),
        ),
        findsOneWidget,
      );
      expectNoHearts();
      // No settings on it.
      expect(find.byKey(const ValueKey('settings_practice')), findsNothing);
      expect(find.text('Check for updates'), findsNothing);
    });

    testWidgets('the stats card opens Stats', (tester) async {
      await _pumpYou(tester);
      await tester.tap(find.byKey(const ValueKey('you_stats_card')));
      await tester.pumpAndSettle();
      expect(find.byType(StatsScreen), findsOneWidget);
      expect(
        tester.widget<StatsScreen>(find.byType(StatsScreen)).initialTabIndex,
        0,
      );
    });

    testWidgets('Session history opens Stats on its History tab', (
      tester,
    ) async {
      await _pumpYou(tester);
      await tester.tap(find.byKey(const ValueKey('you_session_history')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StatsScreen>(find.byType(StatsScreen)).initialTabIndex,
        1,
      );
    });

    testWidgets('Pinned opens the full list of pins', (tester) async {
      await _pumpYou(
        tester,
        pins: {
          SharedPreferenceConstants.pinnedCourseIds: ['ds-talk-1'],
          SharedPreferenceConstants.pinnedSessionIds: ['ds-talk-1'],
        },
      );
      await tester.tap(find.byKey(const ValueKey('you_pinned')));
      await tester.pumpAndSettle();
      expect(find.byType(PinnedListView), findsOneWidget);
      expect(find.byKey(const ValueKey('pinned_ds-talk-1')), findsOneWidget);
    });

    testWidgets('Zen mode hides the stats but keeps history', (tester) async {
      await _pumpYou(tester, zen: true);
      expect(find.byKey(const ValueKey('you_stats_card')), findsNothing);
      expect(find.text('Session history'), findsOneWidget);
    });
  });
}
