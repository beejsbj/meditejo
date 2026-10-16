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

  group('StatsManager Streak Calculation Tests', () {
    test('calculateStreak - empty audio list returns zero streak', () {
      // Arrange
      var stats = LocalAllStats.empty();

      // Act
      var result = statsManager.calculateStreak(stats);

      // Assert
      expect(result.streakCurrent, 0);
      expect(result.streakLongest, 0);
    });

    test('calculateStreak - single day activity sets streak to 1', () {
      // Arrange
      var now = DateTime.now();
      var today = DateTime(now.year, now.month, now.day);
      statsManager.setCurrentDateForTesting(today);

      var stats = LocalAllStats.empty().copyWith(
        audioCompleted: [
          LocalAudioCompleted(id: '1', timestamp: today.millisecondsSinceEpoch),
        ],
      );

      // Act
      var result = statsManager.calculateStreak(stats);

      // Assert
      expect(result.streakCurrent, 1);
      expect(result.streakLongest, 1);
    });

    test('calculateStreak - two consecutive days sets streak to 2', () {
      // Arrange
      var now = DateTime.now();
      var today = DateTime(now.year, now.month, now.day);
      var yesterday = today.subtract(const Duration(days: 1));
      statsManager.setCurrentDateForTesting(today);

      var stats = LocalAllStats.empty().copyWith(
        audioCompleted: [
          LocalAudioCompleted(id: '1', timestamp: today.millisecondsSinceEpoch),
          LocalAudioCompleted(
            id: '2',
            timestamp: yesterday.millisecondsSinceEpoch,
          ),
        ],
      );

      // Act
      var result = statsManager.calculateStreak(stats);

      // Assert
      expect(result.streakCurrent, 2);
      expect(result.streakLongest, 2);
    });

    test('calculateStreak - missing day resets streak', () {
      // Arrange
      var now = DateTime.now();
      var today = DateTime(now.year, now.month, now.day);
      var twoDaysAgo = today.subtract(const Duration(days: 2));
      statsManager.setCurrentDateForTesting(today);

      var stats = LocalAllStats.empty().copyWith(
        audioCompleted: [
          LocalAudioCompleted(id: '1', timestamp: today.millisecondsSinceEpoch),
          LocalAudioCompleted(
            id: '2',
            timestamp: twoDaysAgo.millisecondsSinceEpoch,
          ),
        ],
      );

      // Act
      var result = statsManager.calculateStreak(stats);

      // Assert
      expect(result.streakCurrent, 1);
      expect(result.streakLongest, 1);
    });

    test('calculateStreak - streak freeze prevents streak reset', () {
      // Arrange
      var now = DateTime.now();
      var today = DateTime(now.year, now.month, now.day);
      var yesterday = today.subtract(const Duration(days: 1));
      var twoDaysAgo = today.subtract(const Duration(days: 2));
      statsManager.setCurrentDateForTesting(today);

      var stats = LocalAllStats.empty().copyWith(
        audioCompleted: [
          LocalAudioCompleted(id: '1', timestamp: today.millisecondsSinceEpoch),
          LocalAudioCompleted(
            id: '2',
            timestamp: twoDaysAgo.millisecondsSinceEpoch,
          ),
        ],
        freezeUsageDates: [yesterday.millisecondsSinceEpoch],
      );

      // Act
      var result = statsManager.calculateStreak(stats);

      // Assert
      expect(result.streakCurrent, 3);
      expect(result.streakLongest, 3);
    });

    test(
      'calculateStreak - updates longest streak when current exceeds it',
      () {
        // Arrange
        var now = DateTime.now();
        var today = DateTime(now.year, now.month, now.day);
        var yesterday = today.subtract(const Duration(days: 1));
        var twoDaysAgo = today.subtract(const Duration(days: 2));
        statsManager.setCurrentDateForTesting(today);

        var stats = LocalAllStats.empty().copyWith(
          streakLongest: 2,
          audioCompleted: [
            LocalAudioCompleted(
              id: '1',
              timestamp: today.millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '2',
              timestamp: yesterday.millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '3',
              timestamp: twoDaysAgo.millisecondsSinceEpoch,
            ),
          ],
        );

        // Act
        var result = statsManager.calculateStreak(stats);

        // Assert
        expect(result.streakCurrent, 3);
        expect(result.streakLongest, 3);
      },
    );
  });

  group('StatsManager Streak Calculation Edge Cases', () {
    test(
      'calculateStreak - multiple activities in same day only count as one day in streak',
      () {
        // Arrange
        var now = DateTime.now();
        var today = DateTime(now.year, now.month, now.day);
        statsManager.setCurrentDateForTesting(today);

        var stats = LocalAllStats.empty().copyWith(
          audioCompleted: [
            LocalAudioCompleted(
              id: '1',
              timestamp: today.millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '2',
              timestamp: today.millisecondsSinceEpoch + 3600000, // 1 hour later
            ),
          ],
        );

        // Act
        var result = statsManager.calculateStreak(stats);

        // Assert
        expect(result.streakCurrent, 1);
        expect(result.streakLongest, 1);
      },
    );

    test(
      'calculateStreak - maintains longest streak when current streak is reset',
      () {
        // Arrange
        var now = DateTime.now();
        var today = DateTime(now.year, now.month, now.day);
        var fiveDaysAgo = today.subtract(const Duration(days: 5));
        var sixDaysAgo = today.subtract(const Duration(days: 6));
        var sevenDaysAgo = today.subtract(const Duration(days: 7));
        statsManager.setCurrentDateForTesting(today);

        var stats = LocalAllStats.empty().copyWith(
          streakLongest: 3,
          audioCompleted: [
            LocalAudioCompleted(
              id: '1',
              timestamp: today.millisecondsSinceEpoch,
            ),
            // Gap of 4 days
            LocalAudioCompleted(
              id: '2',
              timestamp: fiveDaysAgo.millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '3',
              timestamp: sixDaysAgo.millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '4',
              timestamp: sevenDaysAgo.millisecondsSinceEpoch,
            ),
          ],
        );

        // Act
        var result = statsManager.calculateStreak(stats);

        // Assert
        expect(result.streakCurrent, 1);
        expect(result.streakLongest, 3); // The longest was 3 days in the past
      },
    );

    test('calculateStreak - handles multiple consecutive streak freezes', () {
      // Arrange
      var now = DateTime.now();
      var today = DateTime(now.year, now.month, now.day);
      // DST-safe date arithmetic.
      var yesterday = DateTime(today.year, today.month, today.day - 1);
      var twoDaysAgo = DateTime(today.year, today.month, today.day - 2);
      var threeDaysAgo = DateTime(today.year, today.month, today.day - 3);
      statsManager.setCurrentDateForTesting(today);

      var stats = LocalAllStats.empty().copyWith(
        audioCompleted: [
          LocalAudioCompleted(id: '1', timestamp: today.millisecondsSinceEpoch),
          LocalAudioCompleted(
            id: '2',
            timestamp: threeDaysAgo.millisecondsSinceEpoch,
          ),
        ],
        freezeUsageDates: [
          yesterday.millisecondsSinceEpoch,
          twoDaysAgo.millisecondsSinceEpoch,
        ],
      );

      // Act
      var result = statsManager.calculateStreak(stats);

      // Assert
      expect(result.streakCurrent, 4);
      expect(result.streakLongest, 4);
    });

    test(
      'calculateStreak - activity with future date does not affect streak',
      () {
        // Arrange
        var now = DateTime.now();
        var today = DateTime(now.year, now.month, now.day);
        var yesterday = today.subtract(const Duration(days: 1));
        var tomorrow = today.add(const Duration(days: 1));
        statsManager.setCurrentDateForTesting(today);

        var stats = LocalAllStats.empty().copyWith(
          audioCompleted: [
            LocalAudioCompleted(
              id: '1',
              timestamp: today.millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '2',
              timestamp: yesterday.millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '3',
              timestamp: tomorrow.millisecondsSinceEpoch, // Future date
            ),
          ],
        );

        // Act
        var result = statsManager.calculateStreak(stats);

        // Assert
        expect(result.streakCurrent, 2);
        expect(result.streakLongest, 2);
      },
    );

    test(
      'calculateStreak - streak spanning EU DST spring-forward (March 29) counts correctly',
      () {
        // Regression test: sessions on March 26-31, viewed on April 1.
        // The streak should be 6. With the Duration(days:1) bug, it returns 5
        // because March 29 is skipped when clocks spring forward.
        var apr1 = DateTime(2026, 4, 1);
        statsManager.setCurrentDateForTesting(apr1);

        var stats = LocalAllStats.empty().copyWith(
          audioCompleted: [
            LocalAudioCompleted(
              id: '1',
              timestamp: DateTime(2026, 3, 31, 21, 6).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '2',
              timestamp: DateTime(2026, 3, 30, 20, 38).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '3',
              timestamp: DateTime(2026, 3, 29, 22, 23).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '4',
              timestamp: DateTime(2026, 3, 28, 23, 9).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '5',
              timestamp: DateTime(2026, 3, 27, 20, 0).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '6',
              timestamp: DateTime(2026, 3, 26, 22, 18).millisecondsSinceEpoch,
            ),
          ],
        );

        var result = statsManager.calculateStreak(stats);

        // Must be 6, not 5.
        expect(result.streakCurrent, 6);
        expect(result.streakLongest, 6);
      },
    );

    test(
      'calculateStreak - streak spanning EU DST fall-back (October 25) counts correctly',
      () {
        // Verify autumn DST (25-hour day) does not cause double-counting.
        var oct27 = DateTime(2026, 10, 27);
        statsManager.setCurrentDateForTesting(oct27);

        var stats = LocalAllStats.empty().copyWith(
          audioCompleted: [
            LocalAudioCompleted(
              id: '1',
              timestamp: DateTime(2026, 10, 27, 8, 0).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '2',
              timestamp: DateTime(2026, 10, 26, 20, 0).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '3',
              timestamp: DateTime(2026, 10, 25, 21, 0).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '4',
              timestamp: DateTime(2026, 10, 24, 19, 30).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '5',
              timestamp: DateTime(2026, 10, 23, 22, 0).millisecondsSinceEpoch,
            ),
          ],
        );

        var result = statsManager.calculateStreak(stats);

        expect(result.streakCurrent, 5);
        expect(result.streakLongest, 5);
      },
    );
  });

  group('StatsManager Audio Completion Tests', () {
    test('addAudioCompleted - updates stats correctly', () async {
      // Arrange
      var stats = LocalAllStats.empty();
      statsManager.setStatsForTesting(stats);

      var audio = LocalAudioCompleted(
        id: '1',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Act
      await statsManager.addAudioCompleted(audio, 300);

      // Assert
      var result = statsManager.currentStats;
      expect(result?.totalTracksCompleted, 1);
      expect(result?.totalTimeListened, 300);
      expect(result?.audioCompleted?.length, 1);
      expect(result?.tracksChecked?.contains('1'), true);
    });

    test(
      'addRepeatListeningTime - adds minutes of every repetition, one session',
      () async {
        statsManager.setStatsForTesting(LocalAllStats.empty());

        final audio = LocalAudioCompleted(
          id: '1',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        // Track played three times on repeat.
        await statsManager.addAudioCompleted(audio, 300);
        await statsManager.addRepeatListeningTime(300);
        await statsManager.addRepeatListeningTime(300);

        final result = statsManager.currentStats;
        expect(result?.totalTimeListened, 900);
        expect(result?.totalTracksCompleted, 1);
        expect(result?.audioCompleted?.length, 1);
      },
    );

    test(
      'addRepeatListeningTime - persists repeat time across a restart',
      () async {
        statsManager.setStatsForTesting(
          LocalAllStats.empty().copyWith(totalTimeListened: 300),
        );

        await statsManager.addRepeatListeningTime(300);

        statsManager.resetForTesting();
        expect((await statsManager.localAllStats).totalTimeListened, 600);
      },
    );
  });

  group('StatsManager Audio Completion Edge Cases', () {
    test(
      'calculateStreak - current streak should be 0 if today is the 27th and no streak freezes used',
      () {
        // Arrange
        var today = DateTime(2025, 2, 27);
        statsManager.setCurrentDateForTesting(today);

        var stats = LocalAllStats.empty().copyWith(
          audioCompleted: [
            LocalAudioCompleted(
              id: '1',
              timestamp: DateTime.utc(2025, 2, 24).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '2',
              timestamp: DateTime.utc(2025, 2, 23).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '3',
              timestamp: DateTime.utc(2025, 2, 22).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '4',
              timestamp: DateTime.utc(2025, 2, 21).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '5',
              timestamp: DateTime.utc(2025, 2, 20).millisecondsSinceEpoch,
            ),
            LocalAudioCompleted(
              id: '6',
              timestamp: DateTime.utc(2025, 2, 19).millisecondsSinceEpoch,
            ),
          ],
          freezeUsageDates: [],
        );

        // Act
        var result = statsManager.calculateStreak(stats);

        // Assert
        expect(result.streakCurrent, 0);
      },
    );

    test(
      'addAudioCompleted - handles duplicate audio completion correctly',
      () async {
        // Arrange
        var stats = LocalAllStats.empty();
        statsManager.setStatsForTesting(stats);

        var audio = LocalAudioCompleted(
          id: '1',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        // Act
        await statsManager.addAudioCompleted(audio, 300);
        await statsManager.addAudioCompleted(
          audio,
          200,
        ); // Same ID, different duration

        // Assert
        var result = statsManager.currentStats;
        expect(
          result?.totalTracksCompleted,
          2,
        ); // Should count as two completions
        expect(result?.totalTimeListened, 500); // Should add both durations
        expect(result?.audioCompleted?.length, 2);
      },
    );

    group('StatsManager Track Checked Tests', () {
      test('addTrackChecked - adds track to checked list', () async {
        // Arrange
        var stats = LocalAllStats.empty();
        statsManager.setStatsForTesting(stats);

        // Act
        await statsManager.addTrackChecked('track1');

        // Assert
        var result = statsManager.currentStats;
        expect(result?.tracksChecked?.contains('track1'), true);
      });

      test('removeTrackChecked - removes track from checked list', () async {
        // Arrange
        var stats = LocalAllStats.empty().copyWith(
          tracksChecked: ['track1', 'track2'],
        );
        statsManager.setStatsForTesting(stats);

        // Act
        await statsManager.removeTrackChecked('track1');

        // Assert
        var result = statsManager.currentStats;
        expect(result?.tracksChecked?.contains('track1'), false);
        expect(result?.tracksChecked?.contains('track2'), true);
      });
    });

    group('StatsManager Track Checked Edge Cases', () {
      test(
        'addTrackChecked - handles adding the same track multiple times',
        () async {
          // Arrange
          var stats = LocalAllStats.empty();
          statsManager.setStatsForTesting(stats);

          // Act
          await statsManager.addTrackChecked('track1');
          await statsManager.addTrackChecked('track1'); // Add same track again

          // Assert
          var result = statsManager.currentStats;
          expect(result?.tracksChecked?.length, 1); // Should only appear once
        },
      );

      test(
        'calculateStreak should break the streak when there is a gap without a freeze',
        () {
          // Set today as March 7, 2025
          final testDate = DateTime(2025, 3, 7);
          statsManager.setCurrentDateForTesting(testDate);

          // Define dates - with a gap on March 6
          var mar1 = DateTime(2025, 3, 1);
          var mar2 = DateTime(2025, 3, 2);
          var mar3 = DateTime(2025, 3, 3);
          var mar4 = DateTime(2025, 3, 4);
          var mar5 = DateTime(2025, 3, 5);
          // Missing Mar 6
          var mar7 = DateTime(2025, 3, 7);

          var mockStats = LocalAllStats(
            tracksChecked: [],
            audioCompleted: [
              LocalAudioCompleted(
                id: '1',
                timestamp: mar7.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '2',
                timestamp: mar5.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '3',
                timestamp: mar4.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '4',
                timestamp: mar3.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '5',
                timestamp: mar2.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '6',
                timestamp: mar1.millisecondsSinceEpoch,
              ),
            ],
            streakCurrent: 0,
            streakLongest: 10,
            totalTracksCompleted: 6,
            totalTimeListened: 360,
            updated: testDate.millisecondsSinceEpoch,
            streakFreezes: 1,
            maxStreakFreezes: 2,
            freezeUsageDates: [],
          );

          var result = statsManager.calculateStreak(mockStats);

          // Streak should be 1 (just today) because the gap on Mar 6 breaks the streak
          expect(result.streakCurrent, 1);
          expect(result.streakLongest, 10);
        },
      );

      test(
        'calculateStreak should maintain streak after applying a freeze to fill a gap',
        () {
          // Set today as March 7, 2025
          final testDate = DateTime(2025, 3, 7);
          statsManager.setCurrentDateForTesting(testDate);

          // Define dates - with a freeze on March 6
          var mar1 = DateTime(2025, 3, 1);
          var mar2 = DateTime(2025, 3, 2);
          var mar3 = DateTime(2025, 3, 3);
          var mar4 = DateTime(2025, 3, 4);
          var mar5 = DateTime(2025, 3, 5);
          var mar6 = DateTime(2025, 3, 6); // Day with streak freeze
          var mar7 = DateTime(2025, 3, 7);

          var mockStats = LocalAllStats(
            tracksChecked: [],
            audioCompleted: [
              LocalAudioCompleted(
                id: '1',
                timestamp: mar7.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '2',
                timestamp: mar5.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '3',
                timestamp: mar4.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '4',
                timestamp: mar3.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '5',
                timestamp: mar2.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '6',
                timestamp: mar1.millisecondsSinceEpoch,
              ),
            ],
            streakCurrent: 0,
            streakLongest: 10,
            totalTracksCompleted: 6,
            totalTimeListened: 360,
            updated: testDate.millisecondsSinceEpoch,
            streakFreezes: 0,
            maxStreakFreezes: 1,
            freezeUsageDates: [mar6.millisecondsSinceEpoch],
          );

          var result = statsManager.calculateStreak(mockStats);

          // Streak should be 7 (Mar 1-7 with Mar 6 being a freeze day, which counts)
          expect(result.streakCurrent, 7);
          expect(result.streakLongest, 10);
        },
      );

      test(
        'calculateStreak should break streak when there are more gaps than freezes',
        () {
          // Set today as March 7, 2025
          final testDate = DateTime(2025, 3, 7);
          statsManager.setCurrentDateForTesting(testDate);

          // Define dates - with gaps on March 4 and March 6
          var mar1 = DateTime(2025, 3, 1);
          var mar2 = DateTime(2025, 3, 2);
          var mar3 = DateTime(2025, 3, 3);
          // Missing Mar 4 - no freeze
          var mar5 = DateTime(2025, 3, 5);
          var mar6 = DateTime(2025, 3, 6); // Day with streak freeze
          var mar7 = DateTime(2025, 3, 7);

          var mockStats = LocalAllStats(
            tracksChecked: [],
            audioCompleted: [
              LocalAudioCompleted(
                id: '1',
                timestamp: mar7.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '2',
                timestamp: mar5.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '3',
                timestamp: mar3.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '4',
                timestamp: mar2.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '5',
                timestamp: mar1.millisecondsSinceEpoch,
              ),
            ],
            streakCurrent: 0,
            streakLongest: 10,
            totalTracksCompleted: 5,
            totalTimeListened: 300,
            updated: testDate.millisecondsSinceEpoch,
            streakFreezes: 0,
            maxStreakFreezes: 2,
            freezeUsageDates: [mar6.millisecondsSinceEpoch],
          );

          var result = statsManager.calculateStreak(mockStats);

          // Streak should be 3 (Mar 5, Mar 6 freeze, Mar 7). Gap on Mar 4 breaks earlier run.
          expect(result.streakCurrent, 3);
          expect(result.streakLongest, 10);
        },
      );

      test(
        'calculateStreak should maintain full streak with multiple freezes filling all gaps',
        () {
          // Set today as March 7, 2025
          final testDate = DateTime(2025, 3, 7);
          statsManager.setCurrentDateForTesting(testDate);

          // Define dates - with freezes on March 4 and March 6
          var mar1 = DateTime(2025, 3, 1);
          var mar2 = DateTime(2025, 3, 2);
          var mar3 = DateTime(2025, 3, 3);
          var mar4 = DateTime(2025, 3, 4); // Day with first streak freeze
          var mar5 = DateTime(2025, 3, 5);
          var mar6 = DateTime(2025, 3, 6); // Day with second streak freeze
          var mar7 = DateTime(2025, 3, 7);

          var mockStats = LocalAllStats(
            tracksChecked: [],
            audioCompleted: [
              LocalAudioCompleted(
                id: '1',
                timestamp: mar7.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '2',
                timestamp: mar5.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '3',
                timestamp: mar3.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '4',
                timestamp: mar2.millisecondsSinceEpoch,
              ),
              LocalAudioCompleted(
                id: '5',
                timestamp: mar1.millisecondsSinceEpoch,
              ),
            ],
            streakCurrent: 0,
            streakLongest: 10,
            totalTracksCompleted: 5,
            totalTimeListened: 300,
            updated: testDate.millisecondsSinceEpoch,
            streakFreezes: 0,
            maxStreakFreezes: 2,
            freezeUsageDates: [
              mar4.millisecondsSinceEpoch,
              mar6.millisecondsSinceEpoch,
            ],
          );

          var result = statsManager.calculateStreak(mockStats);

          // Streak should be 7 (Mar 1-7; freeze days count as full days)
          expect(result.streakCurrent, 7);
          expect(result.streakLongest, 10);
        },
      );

      test('addTrackChecked - handles null or empty track IDs', () async {
        // Arrange
        var stats = LocalAllStats.empty();
        statsManager.setStatsForTesting(stats);

        // Act & Assert
        await expectLater(
          () => statsManager.addTrackChecked(null), // Null ID
          throwsAssertionError,
        );

        await statsManager.addTrackChecked(''); // Empty ID

        var result = statsManager.currentStats;
        expect(
          result?.tracksChecked?.contains(''),
          true,
        ); // Empty string should be added
      });
    });

    group('StatsManager local calendar fixtures', () {
      // Build local calendar dates rather than UTC epoch literals: UTC
      // midnight lands on the previous day in timezones such as Toronto.
      // The intended gaps are February 21 and 26 in every timezone.
      List<LocalAudioCompleted> februaryHistory() => [
        for (final day in [20, 22, 23, 24, 25, 27, 28])
          LocalAudioCompleted(
            id: 'feb-$day',
            timestamp: DateTime(2025, 2, day, 12).millisecondsSinceEpoch,
          ),
      ];

      test('calculateStreak - local date sequence with gaps', () {
        statsManager.setCurrentDateForTesting(DateTime(2025, 3, 1, 12));
        final stats = LocalAllStats.empty().copyWith(
          audioCompleted: februaryHistory(),
        );

        final result = statsManager.calculateStreak(stats);

        // February 27-28 remain active through March 1; February 26 is a gap.
        expect(result.streakCurrent, 2);
        expect(result.streakLongest, 2);
      });

      test('calculateStreak - with freeze on Feb 26', () {
        statsManager.setCurrentDateForTesting(DateTime(2025, 2, 28, 12));
        final stats = LocalAllStats.empty().copyWith(
          audioCompleted: februaryHistory(),
          freezeUsageDates: [DateTime(2025, 2, 26, 12).millisecondsSinceEpoch],
          streakFreezes: 0,
          maxStreakFreezes: 1,
        );

        final result = statsManager.calculateStreak(stats);

        // February 22-28 are contiguous; February 21 still breaks the streak.
        expect(result.streakCurrent, 7);
        expect(result.streakLongest, 7);
      });

      test('calculateStreak - with freezes on both Feb 21 and Feb 26', () {
        statsManager.setCurrentDateForTesting(DateTime(2025, 2, 28, 12));
        final stats = LocalAllStats.empty().copyWith(
          audioCompleted: februaryHistory(),
          freezeUsageDates: [
            DateTime(2025, 2, 21, 12).millisecondsSinceEpoch,
            DateTime(2025, 2, 26, 12).millisecondsSinceEpoch,
          ],
          streakFreezes: 0,
          maxStreakFreezes: 2,
        );

        final result = statsManager.calculateStreak(stats);

        // Both freezes bridge the full February 20-28 streak.
        expect(result.streakCurrent, 9);
        expect(result.streakLongest, 9);
      });
    });

    group('StatsManager addAudioCompleted Tests', () {});
  });

  group('StatsManager initialization safety', () {
    // These tests reset the singleton so we can verify methods that touch
    // SharedPreferences don't blow up with LateInitializationError when
    // called before initialize() — the OTP-verify crash that affected
    // users who signed in straight from onboarding without ever loading
    // the home screen (which is what otherwise triggers initialize()).
    test(
      'clearAllStats does not throw when called before initialize',
      () async {
        statsManager.resetForTesting();
        SharedPreferences.setMockInitialValues({});

        await expectLater(StatsManager().clearAllStats(), completes);
        expect(StatsManager().isInitialized, isTrue);
      },
    );

    test(
      'hasLocalStats does not throw when called before initialize',
      () async {
        statsManager.resetForTesting();
        SharedPreferences.setMockInitialValues({});

        await expectLater(StatsManager().hasLocalStats(), completes);
        expect(StatsManager().isInitialized, isTrue);
      },
    );
  });
}
