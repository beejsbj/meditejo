import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/views/you/stats_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/stats_fixtures.dart';

class _Stats extends StatsNotifier {
  _Stats(this.stats);
  final LocalAllStats stats;
  @override
  Future<LocalAllStats> build() async => stats;
}

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  LocalAllStats stats, {
  Locale locale = const Locale('en'),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(411, 3200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        statsProvider.overrideWith(() => _Stats(stats)),
        practiceClockProvider.overrideWithValue(() => fixtureNow),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Four hours of talks, heard at 1.5x and 1.25x: 3 h 10 min of real time.
LocalAllStats _spedUp() {
  final today = DateTime(fixtureNow.year, fixtureNow.month, fixtureNow.day);
  LocalAudioCompleted talk(int hour, int realMinutes) => LocalAudioCompleted(
    id: 'ds-talk-$hour',
    timestamp: today.add(Duration(hours: hour)).millisecondsSinceEpoch,
    durationMs: 60 * minuteMs,
    realMs: realMinutes * minuteMs,
    kind: 'talks',
  );
  return LocalAllStats.empty().copyWith(
    audioCompleted: [talk(6, 40), talk(8, 40), talk(10, 48), talk(12, 62)],
    totalTimeListened: 240 * minuteMs,
    totalTracksCompleted: 4,
    streakCurrent: 1,
    updated: 1,
  );
}

const _line = ValueKey('you_stats_audio_line');

void main() {
  testWidgets('time practised is real time; the audio covered is a quiet '
      'line beneath', (tester) async {
    await _pump(tester, const Scaffold(body: StatsSummaryCard()), _spedUp());
    expect(find.text('3 h 10 min'), findsNWidgets(2)); // this week, total
    expect(find.byKey(_line), findsOneWidget);
    expect(find.text('4 h of audio · 3 h 10 min of your time'), findsOneWidget);
    // Read out with the figures.
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'Current streak: 1 day, 4 h of audio · 3 h 10 min of your time$',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no line when sessions played at their own speed', (
    tester,
  ) async {
    await _pump(
      tester,
      const Scaffold(body: StatsSummaryCard()),
      fixtureStats(),
    );
    expect(find.byKey(_line), findsNothing);
    expect(find.textContaining('of audio'), findsNothing);
  });

  testWidgets('German and Spanish say it too', (tester) async {
    await _pump(
      tester,
      const Scaffold(body: StatsSummaryCard()),
      _spedUp(),
      locale: const Locale('de'),
    );
    expect(
      find.text('4 Std. Audio · 3 Std. 10 Min. deiner Zeit'),
      findsOneWidget,
    );
    await _pump(
      tester,
      const Scaffold(body: StatsSummaryCard()),
      _spedUp(),
      locale: const Locale('es'),
    );
    expect(find.text('4 h de audio · 3 h 10 min de tu tiempo'), findsOneWidget);
  });

  testWidgets('the stats page says the same under its totals', (tester) async {
    await _pump(tester, const StatsScreen(), _spedUp());
    expect(find.text('4 h of audio · 3 h 10 min of your time'), findsOneWidget);
  });
}
