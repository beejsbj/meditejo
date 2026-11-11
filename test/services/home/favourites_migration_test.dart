import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/home/favourites_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A favourite as Medito saved it.
Map<String, Object?> _fav(String id, String type, [int? at]) => {
  'id': id,
  'title': 'Title of $id',
  'subtitle': null,
  'coverUrl': null,
  'path': null,
  'type': type,
  'timestamp': ?at,
};

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

List<String>? _pins(SharedPreferences prefs) =>
    prefs.getStringList(SharedPreferenceConstants.pinnedCourseIds);

List<String>? _sessions(SharedPreferences prefs) =>
    prefs.getStringList(SharedPreferenceConstants.pinnedSessionIds);

bool _migrated(SharedPreferences prefs) =>
    prefs.getBool(SharedPreferenceConstants.favouritesMigrated) ?? false;

void main() {
  group('favourites become pins', () {
    test('after what is pinned, in saved order, no repeats', () async {
      final favourites = jsonEncode([
        // Saved order wins, whatever the timestamps say (or lack).
        _fav('lib-course-c', 'pack', 3000),
        _fav('ds-talk-7', 'track'),
        // Already pinned: keeps its place, is not added again.
        _fav('yt-a', 'pack', 2000),
        _fav('yt-video-1', 'track', 1000),
      ]);
      final prefs = await _prefs({
        SharedPreferenceConstants.pinnedCourseIds: ['ds-retreat-1', 'yt-a'],
        SharedPreferenceConstants.legacyFavorites: favourites,
      });

      await migrateFavouritesToPins(prefs);

      expect(_pins(prefs), [
        'ds-retreat-1',
        'yt-a',
        'lib-course-c',
        'ds-talk-7',
        'yt-video-1',
      ]);
      expect(_sessions(prefs), unorderedEquals(['ds-talk-7', 'yt-video-1']));
      expect(_migrated(prefs), isTrue);
      // The favourites stay, for a build without pins.
      expect(
        prefs.getString(SharedPreferenceConstants.legacyFavorites),
        favourites,
      );
    });

    test('reads a type in any case', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.legacyFavorites: jsonEncode([
          _fav('a', 'Pack'),
          _fav('b', 'PACK'),
          _fav('t', 'Track'),
        ]),
      });
      await migrateFavouritesToPins(prefs);
      expect(_pins(prefs), ['a', 'b', 't']);
      expect(_sessions(prefs), ['t']);
    });

    test('runs once: an unpinned favourite does not come back', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.legacyFavorites: jsonEncode([
          _fav('a', 'pack'),
          _fav('t', 'track'),
        ]),
      });
      await migrateFavouritesToPins(prefs);
      expect(_pins(prefs), ['a', 't']);
      expect(_sessions(prefs), ['t']);

      await prefs.setStringList(SharedPreferenceConstants.pinnedCourseIds, [
        't',
      ]);
      await migrateFavouritesToPins(prefs);
      expect(_pins(prefs), ['t']);
    });

    test('with no favourites it only marks itself done', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.pinnedCourseIds: ['a'],
      });
      await migrateFavouritesToPins(prefs);
      expect(_pins(prefs), ['a']);
      expect(_sessions(prefs), isNull);
      expect(_migrated(prefs), isTrue);

      final empty = await _prefs({});
      await migrateFavouritesToPins(empty);
      expect(empty.getKeys(), {SharedPreferenceConstants.favouritesMigrated});
    });

    test('an empty or unreadable list leaves the pins as they were', () async {
      for (final raw in ['[]', '{not json']) {
        final prefs = await _prefs({
          SharedPreferenceConstants.pinnedCourseIds: ['a'],
          SharedPreferenceConstants.legacyFavorites: raw,
        });
        await migrateFavouritesToPins(prefs);
        expect(_pins(prefs), ['a'], reason: raw);
        expect(_migrated(prefs), isTrue, reason: raw);
        expect(
          prefs.getString(SharedPreferenceConstants.legacyFavorites),
          raw,
          reason: raw,
        );
      }
    });

    test('entries without an ID are skipped', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.legacyFavorites: jsonEncode([
          {'title': 'no id', 'type': 'track', 'timestamp': 1},
          'not a map',
          _fav('b', 'pack', 2),
        ]),
      });
      await migrateFavouritesToPins(prefs);
      expect(_pins(prefs), ['b']);
    });

    test('start from the course Home used to continue', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.upNextPackId: 'lib-course-old',
        SharedPreferenceConstants.legacyFavorites: jsonEncode([
          _fav('t', 'track', 1),
        ]),
      });
      await migrateFavouritesToPins(prefs);
      expect(_pins(prefs), ['lib-course-old', 't']);
    });

    test('the pins read them back: sessions, and saved titles', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.legacyFavorites: jsonEncode([
          _fav('course', 'pack', 1),
          _fav('talk', 'track', 2),
        ]),
      });
      await migrateFavouritesToPins(prefs);
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(pinnedCoursesProvider), ['course', 'talk']);
      final pins = container.read(pinnedCoursesProvider.notifier);
      expect(pins.isSession('talk'), isTrue);
      expect(pins.isSession('course'), isFalse);
      expect(pins.savedTitle('talk'), 'Title of talk');
      expect(pins.savedTitle('course'), 'Title of course');
      expect(pins.savedTitle('other'), isNull);
    });
  });
}
