import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/enums/home_widget_type.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/home/widget_order_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(SharedPreferences, ProviderContainer Function())> _prefs(
  Map<String, Object> values,
) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  ProviderContainer open() {
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  return (prefs, open);
}

void main() {
  group('pinned courses', () {
    test('have no limit, keep their order and never repeat', () async {
      final (prefs, open) = await _prefs({});
      final c = open();
      final pins = c.read(pinnedCoursesProvider.notifier);

      for (final id in ['a', 'b', 'c', 'd', 'b']) {
        await pins.pin(id);
      }
      expect(c.read(pinnedCoursesProvider), ['a', 'b', 'c', 'd']);
      expect(prefs.getStringList(SharedPreferenceConstants.pinnedCourseIds), [
        'a',
        'b',
        'c',
        'd',
      ]);

      await pins.unpin('a');
      await pins.pin('e');
      expect(c.read(pinnedCoursesProvider), ['b', 'c', 'd', 'e']);
    });

    test('remember which pins are sessions, across a restart', () async {
      final (prefs, open) = await _prefs({});
      final pins = open().read(pinnedCoursesProvider.notifier);
      await pins.pin('course');
      await pins.pin('talk', session: true);
      expect(pins.isSession('talk'), isTrue);
      expect(pins.isSession('course'), isFalse);

      final again = open().read(pinnedCoursesProvider.notifier);
      expect(again.isSession('talk'), isTrue);
      expect(again.isSession('course'), isFalse);

      // Unpinned, it is forgotten; Undo brings it back as a session.
      final before = open().read(pinnedCoursesProvider);
      await again.unpin('talk');
      expect(
        prefs.getStringList(SharedPreferenceConstants.pinnedSessionIds),
        isEmpty,
      );
      await again.pinBack('talk', before, session: true);
      expect(again.isSession('talk'), isTrue);
    });

    test('an unpinned pin leaves no saved title behind', () async {
      final (prefs, open) = await _prefs({
        SharedPreferenceConstants.pinnedCourseIds: ['a', 'b'],
        SharedPreferenceConstants.pinnedTitles: '{"a": "Title a", "b": "B"}',
      });
      final pins = open().read(pinnedCoursesProvider.notifier);
      expect(pins.savedTitle('a'), 'Title a');

      await pins.unpin('a');
      expect(pins.savedTitle('a'), isNull);
      expect(pins.savedTitle('b'), 'B');
      expect(
        prefs.getString(SharedPreferenceConstants.pinnedTitles),
        '{"b":"B"}',
      );
      expect(
        open().read(pinnedCoursesProvider.notifier).savedTitle('a'),
        isNull,
      );
    });

    test('survive a restart', () async {
      final (_, open) = await _prefs({});
      await open().read(pinnedCoursesProvider.notifier).pin('x');
      expect(open().read(pinnedCoursesProvider), ['x']);
    });

    test('the course Home used to continue becomes the first pin', () async {
      final (_, open) = await _prefs({
        SharedPreferenceConstants.upNextPackId: 'lib-course-old',
      });
      expect(open().read(pinnedCoursesProvider), ['lib-course-old']);
    });

    test('a stored list longer than three is kept whole', () async {
      final (_, open) = await _prefs({
        SharedPreferenceConstants.pinnedCourseIds: ['a', 'b', 'c', 'd', 'a'],
      });
      expect(open().read(pinnedCoursesProvider), ['a', 'b', 'c', 'd']);
    });
  });

  group('Customize persists', () {
    test(
      'every section shows, in the default order, on a fresh install',
      () async {
        final (_, open) = await _prefs({});
        final c = open();
        expect(c.read(homeWidgetOrderProvider), [
          HomeWidgetType.upNext,
          HomeWidgetType.homeShortcuts,
          HomeWidgetType.pinned,
        ]);
        expect(c.read(homeHiddenWidgetsProvider), isEmpty);
      },
    );

    test('order and hidden sections are remembered', () async {
      final (_, open) = await _prefs({});
      final first = open();
      await first.read(homeWidgetOrderProvider.notifier).updateOrder([
        HomeWidgetType.pinned,
        HomeWidgetType.upNext,
        HomeWidgetType.homeShortcuts,
      ]);
      await first
          .read(homeHiddenWidgetsProvider.notifier)
          .setVisible(HomeWidgetType.homeShortcuts, false);

      final second = open();
      expect(second.read(homeWidgetOrderProvider), [
        HomeWidgetType.pinned,
        HomeWidgetType.upNext,
        HomeWidgetType.homeShortcuts,
      ]);
      expect(second.read(homeHiddenWidgetsProvider), {
        HomeWidgetType.homeShortcuts,
      });

      await second
          .read(homeHiddenWidgetsProvider.notifier)
          .setVisible(HomeWidgetType.homeShortcuts, true);
      expect(open().read(homeHiddenWidgetsProvider), isEmpty);
    });

    test('a hidden Shortcuts saved before the rename stays hidden', () async {
      final (_, open) = await _prefs({
        SharedPreferenceConstants.homeWidgetHidden: ['quickLinks', 'quote'],
      });
      expect(open().read(homeHiddenWidgetsProvider), {
        HomeWidgetType.homeShortcuts,
      });
    });

    test('a layout saved by the Medito home keeps what still exists', () async {
      final (_, open) = await _prefs({
        SharedPreferenceConstants.homeWidgetOrder: [
          'quote',
          'upNext',
          'carousel',
          'shortcuts',
        ],
      });
      expect(open().read(homeWidgetOrderProvider), [
        HomeWidgetType.upNext,
        HomeWidgetType.homeShortcuts,
        HomeWidgetType.pinned,
      ]);
    });
  });
}
