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
    test('hold at most three; a fourth is refused, not swapped in', () async {
      final (prefs, open) = await _prefs({});
      final c = open();
      final pins = c.read(pinnedCoursesProvider.notifier);

      expect(await pins.pin('a'), isTrue);
      expect(await pins.pin('b'), isTrue);
      expect(await pins.pin('c'), isTrue);
      expect(await pins.pin('d'), isFalse);
      expect(c.read(pinnedCoursesProvider), ['a', 'b', 'c']);
      expect(prefs.getStringList(SharedPreferenceConstants.pinnedCourseIds), [
        'a',
        'b',
        'c',
      ]);

      // Pinning one already pinned is fine, and unpinning frees a place.
      expect(await pins.pin('b'), isTrue);
      await pins.unpin('a');
      expect(await pins.pin('d'), isTrue);
      expect(c.read(pinnedCoursesProvider), ['b', 'c', 'd']);
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

    test('a stored list longer than three is cut to three', () async {
      final (_, open) = await _prefs({
        SharedPreferenceConstants.pinnedCourseIds: ['a', 'b', 'c', 'd'],
      });
      expect(open().read(pinnedCoursesProvider), ['a', 'b', 'c']);
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
