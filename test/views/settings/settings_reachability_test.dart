import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/updates/update_providers.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/views/intro/intro_view.dart';
import 'package:medito/views/settings/battery_optimization_screen.dart';
import 'package:medito/views/settings/settings_screen.dart';
import 'package:medito/views/settings/settings_sections.dart';

import '../../helpers/update_fakes.dart';

class _EmptyStats extends StatsNotifier {
  @override
  Future<LocalAllStats> build() async => LocalAllStats.empty();
}

/// Everything the old Settings screen, its Advanced screen and About screen
/// offered, by the title a person reads. Rows only on a phone (Silence phone,
/// Health sync, Home Screen widget) are checked with the platform given.
const _everywhere = {
  // Notifications & reminders
  'Daily reminder',
  // Practice: from Manage defaults, Advanced and Customisation
  'When my day starts',
  'Zen mode',
  // Sounds & cues: the Customize defaults
  'Practice sounds & cues',
  'Talks sounds & cues',
  // Library & downloads: from Help and Customisation
  'Add to your library',
  'Downloads',
  'Dharma Seed library',
  // Appearance
  'Theme',
  'Organize Home layout',
  // About: from Advanced and About Meditejo
  'What Meditejo is',
  'Check for updates',
  'Source code',
  'Upstream project',
  'Sound credits',
  'Open-source licences',
  'Debug info',
};
const _phoneOnly = {
  'Silence phone during meditation',
  'Sync with Apple Health', // "Health Connect" when the tests run on Android
  'Add Home screen widget',
};
const _groups = [
  'Practice',
  'Sounds & cues',
  'Library & downloads',
  'Appearance',
  'Notifications & reminders',
  'About',
];

/// The row or heading titled [title]: the first line of some text on the page
/// (a row's subtitle is on the lines after its title).
Finder _titled(String title) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().split('\n').first == title,
  description: 'text titled "$title"',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool phone = false,
  Widget page = const SettingsScreen(),
  bool batteryGuidanceNeeded = false,
}) async {
  final h = await UpdateHarness.create();
  final container = ProviderContainer(
    overrides: [
      ...h.overrides,
      statsProvider.overrideWith(_EmptyStats.new),
      batteryGuidanceNeededProvider.overrideWith(
        (_) async => batteryGuidanceNeeded,
      ),
    ],
  );
  addTearDown(container.dispose);
  // Tall, so the whole page is built.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 5000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: phone
            ? Scaffold(
                body: SingleChildScrollView(
                  child: const SettingsSections(
                    isMobile: true,
                    isAndroid: true,
                  ),
                ),
              )
            : page,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('every pre-existing setting is on the Settings tab', (
    tester,
  ) async {
    await _pump(tester);
    for (final title in _everywhere) {
      expect(_titled(title), findsOneWidget, reason: title);
    }
    // The old screens' own entry points are gone, not just hidden.
    expect(_titled('Advanced'), findsNothing);
    expect(_titled('Manage Defaults'), findsNothing);
    expect(_titled('About Meditejo'), findsNothing);
  });

  testWidgets('the phone-only settings are there on a phone', (tester) async {
    await _pump(tester, phone: true);
    for (final title in _phoneOnly) {
      expect(_titled(title), findsOneWidget, reason: title);
    }
    for (final title in _everywhere) {
      expect(_titled(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('and not on the desktop, which cannot use them', (tester) async {
    await _pump(tester);
    for (final title in _phoneOnly) {
      expect(_titled(title), findsNothing, reason: title);
    }
  });

  testWidgets('settings are grouped by what a person is doing', (tester) async {
    await _pump(tester);
    final tops = [
      for (final name in _groups) tester.getTopLeft(_titled(name).first).dy,
    ];
    // In the order a person would reach for them.
    expect(tops, orderedEquals([...tops]..sort()));
    expect(tops.toSet(), hasLength(_groups.length));
  });

  testWidgets(
    'Check for updates is a row on the main screen, with the version',
    (tester) async {
      await _pump(tester);
      expect(
        find.widgetWithText(OutlinedButton, 'Check for updates'),
        findsOneWidget,
      );
      expect(_titled('Version 0.1.0-dev (26101701)'), findsOneWidget);
      expect(
        find.textContaining('GNU Affero General Public License'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the Settings tab has no stats, history or favourites', (
    tester,
  ) async {
    await _pump(tester);
    expect(_titled('Settings'), findsOneWidget);
    expect(_titled('Check for updates'), findsOneWidget);
    // Those are on the You page.
    expect(_titled('Stats'), findsNothing);
    expect(_titled('Session history'), findsNothing);
    expect(_titled('Favorites'), findsNothing);
  });

  testWidgets('the Medito leftovers are gone from Settings', (tester) async {
    await _pump(tester);
    for (final title in [
      'Default Guide Name',
      'Default Duration',
      'App Icon',
      // Medito's questionnaire (#87); the intro replaced it.
      'Onboarding',
    ]) {
      expect(_titled(title), findsNothing, reason: title);
    }
  });

  testWidgets('the automatic update check is a switch, on by default', (
    tester,
  ) async {
    final container = await _pump(tester);
    final tile = find.byKey(const ValueKey('settings_auto_update_check'));
    expect(tile, findsOneWidget);
    expect(_titled('Check for updates automatically'), findsOneWidget);
    expect(container.read(autoUpdateCheckProvider), isTrue);
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: tile, matching: find.byType(Switch)),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.descendant(of: tile, matching: find.byType(Switch)));
    await tester.pumpAndSettle();

    expect(container.read(autoUpdateCheckProvider), isFalse);
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: tile, matching: find.byType(Switch)),
          )
          .value,
      isFalse,
    );
    // The manual path stays.
    expect(
      find.widgetWithText(OutlinedButton, 'Check for updates'),
      findsOneWidget,
    );
  });

  testWidgets('About opens the intro again', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('about_intro')));
    // The intro's mark keeps moving, so pump a while rather than settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(IntroView), findsOneWidget);
    expect(find.text('One calm place for your practice.'), findsOneWidget);
    // Opened from About it is a page to read, not the first-launch flow.
    expect(find.byKey(const ValueKey('intro_start')), findsNothing);
  });

  testWidgets('no battery row where the phone lets Meditejo run', (
    tester,
  ) async {
    await _pump(tester, phone: true);
    expect(find.byKey(const ValueKey('settings_battery')), findsNothing);
  });

  testWidgets('the battery row shows on phones that need it', (tester) async {
    await _pump(tester, phone: true, batteryGuidanceNeeded: true);
    final row = find.byKey(const ValueKey('settings_battery'));
    expect(row, findsOneWidget);
    expect(_titled('Keep Meditejo running'), findsOneWidget);
    // It sits with the reminders it keeps working.
    expect(
      tester.getTopLeft(row).dy,
      greaterThan(tester.getTopLeft(_titled('Daily reminder')).dy),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(BatteryOptimizationScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('battery_open')), findsOneWidget);
  });
}
