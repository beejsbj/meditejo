import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/home/favourites_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A favourite as Medito saved it.
Map<String, Object?> _fav(String id, String type, int at) => {
  'id': id,
  'title': 'Title of $id',
  'subtitle': null,
  'coverUrl': null,
  'path': null,
  'type': type,
  'timestamp': at,
};

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

List<String>? _pins(SharedPreferences prefs) =>
    prefs.getStringList(SharedPreferenceConstants.pinnedCourseIds);

List<String>? _sessions(SharedPreferences prefs) =>
    prefs.getStringList(SharedPreferenceConstants.pinnedSessionIds);

void main() {
  group('favourites become pins', () {
    test('after what is pinned, oldest favourite first, no repeats', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.pinnedCourseIds: ['ds-retreat-1', 'yt-a'],
        SharedPreferenceConstants.legacyFavorites: jsonEncode([
          _fav('lib-course-c', 'pack', 3000),
          _fav('ds-talk-7', 'track', 1000),
          // Already pinned: keeps its place, is not added again.
          _fav('yt-a', 'pack', 2000),
          // Same time as the talk: their saved order breaks the tie.
          _fav('yt-video-1', 'track', 1000),
        ]),
      });

      await migrateFavouritesToPins(prefs);

      expect(_pins(prefs), [
        'ds-retreat-1',
        'yt-a',
        'ds-talk-7',
        'yt-video-1',
        'lib-course-c',
      ]);
      expect(_sessions(prefs), unorderedEquals(['ds-talk-7', 'yt-video-1']));
      expect(
        prefs.containsKey(SharedPreferenceConstants.legacyFavorites),
        isFalse,
      );
    });

    test('a second run changes nothing', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.legacyFavorites: jsonEncode([
          _fav('a', 'pack', 1),
          _fav('t', 'track', 2),
        ]),
      });
      await migrateFavouritesToPins(prefs);
      final pins = _pins(prefs);
      final sessions = _sessions(prefs);

      // The user unpins one: running again must not bring it back.
      await prefs.setStringList(SharedPreferenceConstants.pinnedCourseIds, [
        't',
      ]);
      await migrateFavouritesToPins(prefs);

      expect(pins, ['a', 't']);
      expect(sessions, ['t']);
      expect(_pins(prefs), ['t']);
    });

    test('with no favourites it touches nothing', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.pinnedCourseIds: ['a'],
      });
      await migrateFavouritesToPins(prefs);
      expect(_pins(prefs), ['a']);
      expect(_sessions(prefs), isNull);

      final empty = await _prefs({});
      await migrateFavouritesToPins(empty);
      expect(empty.getKeys(), isEmpty);
    });

    test('an empty favourites list leaves the pins as they were', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.pinnedCourseIds: ['a'],
        SharedPreferenceConstants.legacyFavorites: '[]',
      });
      await migrateFavouritesToPins(prefs);
      expect(_pins(prefs), ['a']);
      expect(_sessions(prefs), isEmpty);
      expect(
        prefs.containsKey(SharedPreferenceConstants.legacyFavorites),
        isFalse,
      );
    });

    test('unreadable favourites are dropped, the pins kept', () async {
      final prefs = await _prefs({
        SharedPreferenceConstants.pinnedCourseIds: ['a'],
        SharedPreferenceConstants.legacyFavorites: '{not json',
      });
      await migrateFavouritesToPins(prefs);
      expect(_pins(prefs), ['a']);
      expect(
        prefs.containsKey(SharedPreferenceConstants.legacyFavorites),
        isFalse,
      );
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

    test('the pins read them back, sessions as sessions', () async {
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
    });
  });
}
