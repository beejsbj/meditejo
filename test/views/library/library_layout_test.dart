import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/library/library_view_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/library/library_widgets.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

/// Taps a kind chip, scrolling the chip row to it first: on a phone the
/// later chips start off to the right.
Future<void> tapFilter(WidgetTester tester, String name) async {
  final chip = find.byKey(ValueKey('library_filter_$name'));
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await settle(tester);
}

Future<void> _add(
  WidgetTester tester,
  LibraryStore store,
  String id,
  String title, {
  LibraryKind kind = LibraryKind.course,
  LibraryGroup group = LibraryGroup.practice,
  String subtitle = '',
}) => tester.runAsync(
  () => store.add(
    LibraryDraft(
      sourceId: id,
      kind: kind,
      title: title,
      group: group,
      subtitle: subtitle,
    ),
  ),
);

/// A realistic mix: two courses (one in progress), two playlists, three
/// singles (one a talk) and a saved teacher.
Future<LibraryTestApp> _mixed(WidgetTester tester) async {
  final app = await LibraryTestApp.create(tester);
  final store = app.harness.store;
  await _add(
    tester,
    store,
    'ds-retreat-1',
    'Practising the Jhānas',
    subtitle: 'Rob Burbea · 2019 · 32 talks',
  );
  await _add(
    tester,
    store,
    'yt-playlist-q',
    'Qualia Mastery',
    subtitle: 'Qualia Research Institute',
  );
  await _add(
    tester,
    store,
    'my-course-0123456789abcdef',
    'Morning sits',
    subtitle: '5 sessions',
  );
  await _add(
    tester,
    store,
    'my-course-fedcba9876543210',
    'Evening wind-down',
    subtitle: '2 sessions',
  );
  await _add(
    tester,
    store,
    'ds-talk-60864',
    'Developing Piti',
    kind: LibraryKind.single,
    subtitle: 'Rob Burbea · 89 min',
  );
  await _add(
    tester,
    store,
    'lib-track-a',
    'Body scan',
    kind: LibraryKind.single,
    subtitle: 'My recording',
  );
  await _add(
    tester,
    store,
    'ds-talk-2',
    'On emptiness',
    kind: LibraryKind.single,
    group: LibraryGroup.talks,
    subtitle: 'Talk · 52 min',
  );
  await _add(
    tester,
    store,
    'ds-teacher-210',
    'Rob Burbea',
    kind: LibraryKind.teacher,
  );
  return app;
}

final _progress = [
  packTrackIdsProvider.overrideWith(
    (ref) async => {
      'ds-retreat-1': ['j-1', 'j-2', 'j-3', 'j-4'],
      'my-course-0123456789abcdef': ['m-1', 'm-2', 'm-3', 'm-4', 'm-5'],
      'yt-playlist-q': ['q-1', 'q-2'],
    },
  ),
];

final _overrides = [..._progress];

const _played = ['j-1', 'j-2', 'j-3', 'm-1'];

Finder _visibleText(String text) => find.text(text, skipOffstage: false);

void main() {
  group('the library tab', () {
    testWidgets('sections by form: Sessions, Playlists, Courses, Teachers', (
      tester,
    ) async {
      final app = await _mixed(tester);
      await app.pump(
        tester,
        const LibraryView(),
        played: _played,
        overrides: _overrides,
      );

      double top(Finder f) => tester.getTopLeft(f).dy;
      final sections = [
        for (final name in ['sessions', 'playlists', 'courses', 'teachers'])
          find.byKey(ValueKey('library_section_$name'), skipOffstage: false),
      ];
      for (final section in sections) {
        expect(section, findsOneWidget);
      }
      for (var i = 1; i < sections.length; i++) {
        expect(top(sections[i]), greaterThan(top(sections[i - 1])));
      }
      expect(find.text('Playlists', skipOffstage: false), findsOneWidget);
      expect(find.text('Courses', skipOffstage: false), findsOneWidget);
      expect(find.text('Sessions', skipOffstage: false), findsOneWidget);

      // Each entry under its form, practice and talks together.
      void under(String title, int section) {
        final y = top(_visibleText(title));
        expect(y, greaterThan(top(sections[section])), reason: title);
        if (section + 1 < sections.length) {
          expect(y, lessThan(top(sections[section + 1])), reason: title);
        }
      }

      under('Developing Piti', 0);
      under('On emptiness', 0);
      under('Body scan', 0);
      under('Morning sits', 1);
      under('Evening wind-down', 1);
      under('Practising the Jhānas', 2);
      under('Qualia Mastery', 2);
      under('Rob Burbea', 3);
      // No kind sections and no In progress.
      expect(find.text('Practice', skipOffstage: false), findsNothing);
      expect(find.text('In progress', skipOffstage: false), findsNothing);

      // Decision 18: saved teachers keep a filter of their own.
      await tapFilter(tester, 'teachers');
      expect(find.byType(LibraryEntryTile), findsOneWidget);
      expect(_visibleText('Rob Burbea'), findsOneWidget);
      expect(_visibleText('Morning sits'), findsNothing);
    });

    testWidgets('Downloads shows what has a downloaded session', (
      tester,
    ) async {
      final app = await _mixed(tester);
      await app.pump(
        tester,
        const LibraryView(),
        downloaded: const {'q-2', 'lib-track-a'},
        overrides: _overrides,
      );
      await tapFilter(tester, 'downloads');

      expect(_visibleText('Qualia Mastery'), findsOneWidget);
      expect(_visibleText('Body scan'), findsOneWidget);
      expect(_visibleText('Practising the Jhānas'), findsNothing);
      expect(_visibleText('Developing Piti'), findsNothing);
    });

    testWidgets('Practice or Talks chips narrow the list, with counts', (
      tester,
    ) async {
      final app = await _mixed(tester);
      await app.pump(tester, const LibraryView(), overrides: _overrides);

      // Nothing downloaded: no Downloads chip.
      expect(
        find.byKey(const ValueKey('library_filter_downloads')),
        findsNothing,
      );
      expect(find.text('Practice 6'), findsOneWidget);
      expect(find.text('Talks 1'), findsOneWidget);
      expect(find.text('Teachers 1'), findsOneWidget);

      await tapFilter(tester, 'talks');
      expect(_visibleText('On emptiness'), findsOneWidget);
      expect(_visibleText('Developing Piti'), findsNothing);
      expect(_visibleText('Rob Burbea'), findsNothing);
      // Only the sections with something in them.
      expect(
        find.byKey(const ValueKey('library_section_sessions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('library_section_courses')),
        findsNothing,
      );

      await tapFilter(tester, 'practice');
      expect(_visibleText('Developing Piti'), findsOneWidget);
      expect(_visibleText('On emptiness'), findsNothing);

      await tapFilter(tester, 'all');
      expect(_visibleText('On emptiness'), findsOneWidget);
      expect(_visibleText('Developing Piti'), findsOneWidget);
    });

    testWidgets('sorts by recent, A–Z and progress', (tester) async {
      final app = await _mixed(tester);
      // Renamed so A–Z and Progress disagree.
      await tester.runAsync(
        () => app.harness.store.setTitle('yt-playlist-q', 'Awakening, Qualia'),
      );
      await app.pump(
        tester,
        const LibraryView(),
        played: _played,
        overrides: _overrides,
      );

      List<String> order() {
        final titles = ['Practising the Jhānas', 'Awakening, Qualia'];
        return titles..sort(
          (a, b) => tester
              .getTopLeft(_visibleText(a))
              .dy
              .compareTo(tester.getTopLeft(_visibleText(b)).dy),
        );
      }

      Future<void> sortBy(String name) async {
        await tester.tap(find.byKey(const ValueKey('library_sort')));
        await settle(tester);
        await tester.tap(find.byKey(ValueKey('library_sort_$name')));
        await settle(tester);
      }

      final recent = order();
      await sortBy('title');
      expect(order(), ['Awakening, Qualia', 'Practising the Jhānas']);
      // Progress: 3 of 4 leads the unbegun.
      await sortBy('progress');
      expect(order(), ['Practising the Jhānas', 'Awakening, Qualia']);
      await sortBy('recent');
      expect(order(), recent);
      expect(app.prefs.getString('library_sort'), 'recent');
      expect(find.text('3 of 4'), findsOneWidget);
    });

    testWidgets('the grid and list switch, and the choice is kept', (
      tester,
    ) async {
      final app = await _mixed(tester);
      await app.pump(tester, const LibraryView(), overrides: _overrides);

      expect(find.byType(LibraryEntryCard), findsNothing);
      await tester.tap(find.byTooltip('Show as grid'));
      await settle(tester);
      expect(find.byType(LibraryEntryCard, skipOffstage: false), findsWidgets);
      // Sessions stay rows in the grid.
      expect(
        find.ancestor(
          of: _visibleText('Developing Piti'),
          matching: find.byType(LibraryEntryTile),
        ),
        findsOneWidget,
      );
      expect(app.prefs.getString('library_layout'), 'grid');

      await tester.tap(find.byTooltip('Show as list'));
      await settle(tester);
      expect(find.byType(LibraryEntryCard), findsNothing);
      expect(app.prefs.getString('library_layout'), 'list');
    });

    testWidgets('cards say where a course came from, and how far along', (
      tester,
    ) async {
      final app = await _mixed(tester);
      await app.pump(
        tester,
        const LibraryView(),
        played: _played,
        overrides: _overrides,
      );

      expect(find.text('Dharma Seed'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Playlist'), findsNWidgets(2));
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.text('1 of 5'), findsOneWidget);
    });

    testWidgets('has no In progress: Home\'s Continue has it', (tester) async {
      final app = await _mixed(tester);
      // Practising the Jhānas is 3 of 4 done: in progress.
      await app.pump(
        tester,
        const LibraryView(),
        played: _played,
        overrides: _overrides,
      );

      expect(find.text('In progress', skipOffstage: false), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('in_progress'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      // The chips come first.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('library_filter_all'))).dy,
        lessThan(200),
      );
    });

    testWidgets('a chip with nothing says what it would show', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await _add(tester, app.harness.store, 'ds-retreat-1', 'A course');
      await app.pump(tester, const LibraryView(), overrides: _overrides);
      expect(find.text('Talks 0'), findsOneWidget);
      await tapFilter(tester, 'talks');

      expect(find.byKey(const ValueKey('library_empty_talks')), findsOneWidget);
      expect(find.text('No talks here yet'), findsOneWidget);
      expect(
        find.text('Talks, and courses with talks, show up here.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('library_filter_empty_add')),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryView)),
      );
      await tester.tap(find.byKey(const ValueKey('library_empty_explore')));
      await settle(tester);
      expect(container.read(mainTabProvider), MainTab.explore);
    });

    testWidgets('Practice and Downloads have their own empty words', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await _add(
        tester,
        app.harness.store,
        'ds-talk-2',
        'On emptiness',
        kind: LibraryKind.single,
        group: LibraryGroup.talks,
      );
      await app.pump(tester, const LibraryView(), overrides: _overrides);
      await tapFilter(tester, 'practice');
      expect(find.text('No practice here yet'), findsOneWidget);

      // Downloads, chosen, stays while it has nothing (it is shown only once
      // something is downloaded, or while chosen).
      ProviderScope.containerOf(tester.element(find.byType(LibraryView)))
          .read(libraryViewOptionsProvider.notifier)
          .setFilter(LibraryFilter.downloads);
      await settle(tester);
      expect(find.text('Nothing downloaded'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('library_filter_downloads')),
        findsOneWidget,
      );
    });

    testWidgets('an empty library offers Explore as well as Add', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(tester, const LibraryView(), overrides: _overrides);
      expect(find.text('Your library is empty'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('library_empty_explore')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('library_empty_add')), findsOneWidget);
    });
  });

  group('every row action is still reachable', () {
    Future<Set<String>> menuOf(WidgetTester tester, String id) async {
      final menu = find.byKey(ValueKey('library_menu_$id'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await settle(tester);
      final items = {
        for (final tile in tester.widgetList<ListTile>(
          find.descendant(
            of: find.byKey(const ValueKey('item_actions_sheet')),
            matching: find.byType(ListTile),
          ),
        ))
          (tile.title! as Text).data!,
      };
      await tester.tapAt(Offset.zero);
      await settle(tester);
      return items;
    }

    for (final grid in [false, true]) {
      testWidgets('in the ${grid ? 'grid' : 'list'}', (tester) async {
        final app = await _mixed(tester);
        await app.pump(tester, const LibraryView(), overrides: _overrides);
        if (grid) {
          await tester.tap(find.byTooltip('Show as grid'));
          await settle(tester);
        }
        // New playlist stays one tap behind the app bar's "+" (#62).
        expect(find.byTooltip('Add to your library'), findsOneWidget);

        expect(await menuOf(tester, 'ds-retreat-1'), {
          'Play',
          'Add to playlist…',
          'Copy as playlist',
          'Pin to Home',
          'Share',
          'Move to Talks',
          'Rename',
          'Labels',
          'Remove from library',
        });
        expect(await menuOf(tester, 'my-course-0123456789abcdef'), {
          'Play',
          'Edit playlist',
          'Add to playlist…',
          'Copy as playlist',
          'Pin to Home',
          'Move to Talks',
          'Rename',
          'Labels',
          'Delete playlist',
        });
        expect(await menuOf(tester, 'ds-talk-2'), {
          'Play',
          'Add to playlist…',
          'Download audio',
          'Mark as played',
          'Share',
          'Move to Practice',
          'Rename',
          'Labels',
          'Pin to Home',
          'Remove from library',
        });
        expect(await menuOf(tester, 'ds-teacher-210'), {'Remove from library'});
      });
    }
  });

  group('fits a 360 dp phone at twice the text size', () {
    for (final grid in [false, true]) {
      {
        testWidgets(grid ? 'grid' : 'list', (tester) async {
          final app = await _mixed(tester);
          await app.pump(
            tester,
            MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 780),
                textScaler: TextScaler.linear(2),
              ),
              child: const LibraryView(),
            ),
            played: _played,
            overrides: _overrides,
          );
          tester.view.physicalSize = const Size(360, 780);
          await settle(tester);
          if (grid) {
            await tester.tap(find.byKey(const ValueKey('library_layout')));
            await settle(tester);
          }
          expect(tester.takeException(), isNull);
          // Scroll through all of it.
          final scroll = find.byKey(const ValueKey('library_scroll'));
          for (var i = 0; i < 12; i++) {
            await tester.drag(scroll, const Offset(0, -400));
            await settle(tester);
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  });
}
