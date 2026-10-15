// Runs the shared fixture in test/fixtures/consistency_score_fixtures.json
// against the Dart implementation (the source of truth). The same fixture is
// consumed by the Kotlin unit test
// (android/app/src/test/kotlin/.../ConsistencyScoreCalculatorParityTest.kt)
// that exercises the on-device widget port — keeping both in this one file
// makes drift between the two implementations show up as a CI failure
// instead of relying on the sync-reminder comments alone.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late StatsManager statsManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    statsManager = StatsManager();
    await statsManager.initializeForTesting();
  });

  tearDown(() {
    statsManager.resetForTesting();
  });

  final fixtureFile = File('test/fixtures/consistency_score_fixtures.json');
  final fixture =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final referenceDate = DateTime.parse(fixture['referenceDate'] as String);
  final cases = fixture['cases'] as List<dynamic>;

  // Day offsets describe calendar dates, not elapsed 24-hour durations.
  // In particular, subtracting 24 hours across spring-forward can skip a
  // local date and make the thirty_days_perfect fixture contain a gap.
  DateTime atDayOffset(int offset) => DateTime(
    referenceDate.year,
    referenceDate.month,
    referenceDate.day + offset,
    12,
  );

  group('Consistency score parity fixture', () {
    for (final rawCase in cases) {
      final testCase = rawCase as Map<String, dynamic>;
      final name = testCase['name'] as String;
      final audioOffsets = (testCase['audioOffsetDays'] as List<dynamic>)
          .cast<int>();
      final freezeOffsets = (testCase['freezeOffsetDays'] as List<dynamic>)
          .cast<int>();
      final expectedPercent = testCase['expectedPercent'] as int;

      test(name, () {
        statsManager.setCurrentDateForTesting(atDayOffset(0));

        final audioCompleted = audioOffsets
            .map(
              (offset) => LocalAudioCompleted(
                id: 'audio-$offset',
                timestamp: atDayOffset(offset).millisecondsSinceEpoch,
              ),
            )
            .toList();

        if (name == 'thirty_days_perfect') {
          final localDates = audioCompleted.map((entry) {
            final date = DateTime.fromMillisecondsSinceEpoch(entry.timestamp);
            return DateTime(date.year, date.month, date.day);
          }).toSet();
          expect(localDates, {
            for (var day = -29; day <= 0; day++)
              DateTime(
                referenceDate.year,
                referenceDate.month,
                referenceDate.day + day,
              ),
          }, reason: 'Perfect history must cover all 30 inclusive local dates');
        }

        final stats = LocalAllStats.empty().copyWith(
          audioCompleted: audioCompleted,
          freezeUsageDates: freezeOffsets
              .map((offset) => atDayOffset(offset).millisecondsSinceEpoch)
              .toList(),
        );

        final score = statsManager.calculateConsistencyScore(stats);
        final percent = (score * 100).round().clamp(0, 100);

        expect(
          percent,
          expectedPercent,
          reason: 'fixture case "$name" expected $expectedPercent%',
        );
      });
    }
  });
}
