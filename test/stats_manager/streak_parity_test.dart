// Runs the shared fixture in test/fixtures/streak_score_fixtures.json against
// the Dart implementation (the source of truth). The same fixture is consumed
// by the Kotlin unit test (android/app/src/test/kotlin/.../
// StreakCalculatorParityTest.kt) that exercises the on-device widget port —
// keeping both suites pointed at one fixture file means drift between the two
// implementations shows up as a CI failure instead of relying on the
// sync-reminder comments alone.
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

  final fixtureFile = File('test/fixtures/streak_score_fixtures.json');
  final fixture =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final referenceInstant = DateTime.parse(
    fixture['referenceInstant'] as String,
  );
  final cases = fixture['cases'] as List<dynamic>;

  DateTime atHourOffset(num offsetHours) {
    final instant = referenceInstant.add(
      Duration(milliseconds: (offsetHours * 3600000).round()),
    );
    // Kotlin evaluates these fixture clock readings in UTC. Recreate the
    // same calendar fields locally for Dart, whose session timestamps are
    // decoded in the host timezone. Do not mix UTC "now" with local sessions.
    return DateTime(
      instant.year,
      instant.month,
      instant.day,
      instant.hour,
      instant.minute,
      instant.second,
      instant.millisecond,
    );
  }

  group('Streak parity fixture', () {
    for (final rawCase in cases) {
      final testCase = rawCase as Map<String, dynamic>;
      final name = testCase['name'] as String;
      final nowOffsetHours = testCase['nowOffsetHours'] as num;
      final meditationOffsets =
          (testCase['meditationOffsetHours'] as List<dynamic>).cast<num>();
      final freezeOffsets = (testCase['freezeOffsetHours'] as List<dynamic>)
          .cast<num>();
      final dayBoundaryOffsetHours = testCase['dayBoundaryOffsetHours'] as int;
      final expectedStreak = testCase['expectedStreak'] as int;

      test(name, () {
        final now = atHourOffset(nowOffsetHours);
        statsManager.setCurrentDateForTesting(now);
        statsManager.setDayBoundaryOffsetForTesting(
          Duration(hours: dayBoundaryOffsetHours),
        );

        final audioCompleted = meditationOffsets
            .map(
              (offset) => LocalAudioCompleted(
                id: 'audio-$offset',
                timestamp: atHourOffset(offset).millisecondsSinceEpoch,
              ),
            )
            .toList();

        if (name == 'future_ignored') {
          final localDates = audioCompleted.map((entry) {
            final date = DateTime.fromMillisecondsSinceEpoch(entry.timestamp);
            return DateTime(date.year, date.month, date.day);
          }).toSet();
          expect(localDates, {
            DateTime(now.year, now.month, now.day),
            DateTime(now.year, now.month, now.day + 1),
          }, reason: 'The fixture must contain today and a future local day');
        }

        final stats = LocalAllStats.empty().copyWith(
          audioCompleted: audioCompleted,
          freezeUsageDates: freezeOffsets
              .map((offset) => atHourOffset(offset).millisecondsSinceEpoch)
              .toList(),
        );

        final result = statsManager.calculateStreak(stats);

        expect(
          result.streakCurrent,
          expectedStreak,
          reason: 'fixture case "$name" expected streak $expectedStreak',
        );
      });
    }
  });
}
