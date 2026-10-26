import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/duration_preference_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/views/settings/settings_screen.dart';
import 'package:medito/views/settings/settings_sections.dart';
import 'package:medito/views/you/you_view.dart';

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
  'Default Guide Name',
  'Default Duration',
  'When my day starts',
  'Zen Mode',
  'Edit stats',
  // Sounds & cues: the Customize defaults
  'Practice sounds & cues',
  'Talks sounds & cues',
  // Library & downloads: from Help and Customisation
  'Add to your library',
  'Favorites',
  'Downloads',
  'Dharma Seed library',
  // Appearance
  'Theme',
  'App Icon',
  'Organize Home Layout',
  // About: from Advanced and About Meditejo
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
  'Add Home Screen Widget',
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
  Widget page = const YouView(),
}) async {
  final h = await UpdateHarness.create();
  final container = ProviderContainer(
    overrides: [...h.overrides, statsProvider.overrideWith(_EmptyStats.new)],
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
  testWidgets('every pre-existing setting is on the You page', (tester) async {
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

  testWidgets('the Settings screen the tab hosts shows the same page', (
    tester,
  ) async {
    await _pump(tester, page: const SettingsScreen());
    expect(_titled('Settings'), findsOneWidget);
    expect(_titled('Check for updates'), findsOneWidget);
    expect(_titled('Stats'), findsWidgets);
  });

  testWidgets('the default length can be set from Settings before any track', (
    tester,
  ) async {
    final container = await _pump(tester);
    expect(container.read(durationPreferenceProvider), isNull);
    await tester.tap(_titled('Default Duration'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
    // Opening the sheet saves nothing; moving the slider does.
    expect(container.read(durationPreferenceProvider), isNull);
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    expect(container.read(durationPreferenceProvider), isNotNull);
  });
}
