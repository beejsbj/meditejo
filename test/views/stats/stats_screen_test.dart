import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/views/stats/widgets/daily_bars.dart';
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
  Widget page, {
  LocalAllStats? stats,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 3200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        statsProvider.overrideWith(() => _Stats(stats ?? fixtureStats())),
        practiceClockProvider.overrideWithValue(() => fixtureNow),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The text of the figure labelled [label] (the figure sits above its label).
String _figure(WidgetTester tester, String label) {
  final semantics = find.bySemanticsLabel(RegExp('^$label: '));
  final text = tester.widget<Semantics>(semantics.first).properties.label!;
  return text.substring(label.length + 2);
}

void main() {
  testWidgets('shows today, this week, this month and all time', (
    tester,
  ) async {
    await _pump(tester, const StatsScreen());
    expect(_figure(tester, 'Today'), '1 h 10 min');
    expect(_figure(tester, 'This week'), '1 h 30 min');
    expect(_figure(tester, 'This month'), '2 h 15 min');
    expect(_figure(tester, 'All time'), '3 h 20 min');
    expect(
      find.text('These numbers are feedback, not a score.'),
      findsOneWidget,
    );
    // The earlier session with no recorded length is said so.
    expect(find.textContaining('count as days practised'), findsOneWidget);
  });

  testWidgets('the chart switches between 7 and 30 days', (tester) async {
    await _pump(tester, const StatsScreen());
    final readout = find.byKey(const ValueKey('daily_bars_readout'));
    // Last 7 days (15th to 21st): 20 + 70 + 30 minutes, on 3 days.
    expect(
      tester.widget<Text>(readout).data,
      '2 h in all, practised on 3 of 7 days',
    );
    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    // 135 this month + the 5 of the old timer, on 5 days.
    expect(
      tester.widget<Text>(readout).data,
      '2 h 20 min in all, practised on 5 of 30 days',
    );
  });

  testWidgets('touching a bar reads that day', (tester) async {
    await _pump(tester, const StatsScreen());
    final readout = find.byKey(const ValueKey('daily_bars_readout'));
    final chart = find.descendant(
      of: find.byType(DailyBars),
      matching: find.byType(GestureDetector),
    );
    // The right-most seventh of the chart is today.
    final box = tester.getRect(chart.first);
    await tester.tapAt(Offset(box.right - 4, box.center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(readout).data, 'Wed, Oct 21 · 1 h 10 min');
    // And the first is six days before.
    await tester.tapAt(Offset(box.left + 4, box.center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(readout).data, 'Thu, Oct 15 · 0 min');
  });

  testWidgets('splits Practice and Talks and ranks courses and sources', (
    tester,
  ) async {
    await _pump(tester, const StatsScreen());
    // Practice: 10 + 20 + 30 + 5. Talks: 60 + 15.
    expect(find.bySemanticsLabel('Practice: 1 h 5 min, 46%'), findsOneWidget);
    expect(find.bySemanticsLabel('Talks: 1 h 15 min, 54%'), findsOneWidget);
    // The split bar has a height (a bare ColoredBox in a Row has none).
    expect(tester.getSize(find.byKey(const ValueKey('split_bar'))).height, 16);
    for (final row in [
      'Practising the Jhānas: 1 h',
      'Added by hand: 30 min',
      'Metta: 20 min',
      'Timer: 15 min',
      'YouTube: 15 min',
    ]) {
      expect(find.bySemanticsLabel(row), findsOneWidget, reason: row);
    }
  });

  testWidgets('the month shows days practised, and steps back', (tester) async {
    await _pump(tester, const StatsScreen());
    expect(find.textContaining('October 2026 · 4 days'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Tue, Oct 20, 20 min')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Fri, Oct 2, Not meditated')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.textContaining('September 2026 · 1 day'), findsOneWidget);
    // Nothing before the first session.
    final back = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    expect(back.onPressed, isNull);
  });

  testWidgets('streak and consistency are worded as feedback', (tester) async {
    await _pump(tester, const StatsScreen());
    expect(_figure(tester, 'Current Streak'), '2 days');
    expect(_figure(tester, 'Longest Streak'), '9 days');
    expect(
      find.text('You practised on 5 of the last 30 days.'),
      findsOneWidget,
    );
  });

  testWidgets('an empty history says so', (tester) async {
    await _pump(tester, const StatsScreen(), stats: LocalAllStats.empty());
    expect(find.byKey(const ValueKey('stats_empty')), findsOneWidget);
  });

  testWidgets('History is still a tab, for adding and deleting sessions', (
    tester,
  ) async {
    await _pump(tester, const StatsScreen(initialTabIndex: 1));
    expect(find.text('Today'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('stats_tabs')),
        matching: find.text('Stats'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('the You summary shows three figures and opens Stats', (
    tester,
  ) async {
    await _pump(tester, const Scaffold(body: StatsSummaryCard()));
    expect(
      find.bySemanticsLabel(
        'Stats, This week: 1 h 30 min, Total time: 3 h 20 min, '
        'Current Streak: 2 days',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('you_stats_card')));
    await tester.pumpAndSettle();
    expect(find.byType(StatsScreen), findsOneWidget);
  });
}
