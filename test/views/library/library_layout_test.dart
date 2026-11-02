import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
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

final _overrides = [
  ..._progress,
  inProgressItemsProvider.overrideWith((ref) async => const []),
];

const _played = ['j-1', 'j-2', 'j-3', 'm-1'];

Finder _visibleText(String text) => find.text(text, skipOffstage: false);

void main() {
  group('the library tab', () {
    testWidgets('filters by kind: courses, playlists, singles, teachers', (
      tester,
    ) async {
      final app = await _mixed(tester);
      await app.pump(
        tester,
        const LibraryView(),
        played: _played,
        overrides: _overrides,
      );

      Future<void> filter(String name) => tapFilter(tester, name);

      // All: everything, teacher included.
      for (final title in [
        'Practising the Jhānas',
        'Morning sits',
        'Developing Piti',
        'On emptiness',
        'Rob Burbea',
      ]) {
        expect(_visibleText(title), findsOneWidget, reason: title);
      }

      await filter('courses');
      expect(_visibleText('Practising the Jhānas'), findsOneWidget);
      expect(_visibleText('Qualia Mastery'), findsOneWidget);
      expect(_visibleText('Morning sits'), findsNothing);
      expect(_visibleText('Developing Piti'), findsNothing);

      await filter('playlists');
      expect(_visibleText('Morning sits'), findsOneWidget);
      expect(_visibleText('Evening wind-down'), findsOneWidget);
      expect(_visibleText('Practising the Jhānas'), findsNothing);

      await filter('singles');
      expect(_visibleText('Developing Piti'), findsOneWidget);
      expect(_visibleText('Body scan'), findsOneWidget);
      expect(_visibleText('On emptiness'), findsOneWidget);
      expect(_visibleText('Morning sits'), findsNothing);

      // Decision 18: saved teachers live in the Library as a filter.
      await filter('teachers');
      expect(find.byType(LibraryEntryTile), findsOneWidget);
      expect(_visibleText('Rob Burbea'), findsOneWidget);
      // Teachers have no Practice or Talks.
      expect(find.byKey(const ValueKey('library_group')), findsNothing);

      await filter('all');
      expect(_visibleText('Morning sits'), findsOneWidget);
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

    testWidgets('Practice or Talks narrows the list', (tester) async {
      final app = await _mixed(tester);
      await app.pump(tester, const LibraryView(), overrides: _overrides);

      await tester.tap(find.byKey(const ValueKey('library_group_talks')));
      await settle(tester);
      expect(_visibleText('On emptiness'), findsOneWidget);
      expect(_visibleText('Developing Piti'), findsNothing);
      expect(_visibleText('Rob Burbea'), findsNothing);

      // Tapping it again shows both.
      await tester.tap(find.byKey(const ValueKey('library_group_talks')));
      await settle(tester);
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
      await tapFilter(tester, 'courses');

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
      // Singles stay rows in the grid.
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

    testWidgets('In progress shows the whole set, not three', (tester) async {
      final app = await _mixed(tester);
      final items = [
        for (var i = 0; i < 5; i++)
          ContinueItem(
            trackId: 't$i',
            path: '/tracks/t$i',
            title: 'Session $i',
            group: LibraryGroup.practice,
            lastPlayed: DateTime(2026, 10, 20 + i),
            courseId: 'c$i',
            courseTitle: 'Course $i',
            sessionNumber: 2,
            sessionTotal: 8,
            completedSessions: 1,
          ),
      ];
      await app.pump(
        tester,
        const LibraryView(),
        overrides: [
          ..._progress,
          inProgressItemsProvider.overrideWith((ref) async => items),
        ],
      );

      expect(find.text('In progress'), findsOneWidget);
      final strip = find.byKey(const ValueKey('library_in_progress'));
      expect(find.text('Session 0'), findsOneWidget);
      // All five, the last at the far end of the strip.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('in_progress_t4')),
        strip,
        const Offset(-300, 0),
      );
      expect(find.byKey(const ValueKey('in_progress_t4')), findsOneWidget);
      // Above the filters.
      expect(
        tester.getTopLeft(find.text('In progress')).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('library_filter_all')))
              .dy,
        ),
      );
    });

    testWidgets('a filter with nothing points to Explore and Add', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await _add(tester, app.harness.store, 'ds-retreat-1', 'A course');
      await app.pump(tester, const LibraryView(), overrides: _overrides);
      await tapFilter(tester, 'playlists');

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('library_filter_new_playlist')),
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
        for (final item in tester.widgetList<PopupMenuItem<Object?>>(
          find.byWidgetPredicate((w) => w is PopupMenuItem),
        ))
          ((item.child as Text?)?.data ?? ''),
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
        // The new-playlist button stays in the app bar.
        expect(find.byTooltip('New playlist'), findsOneWidget);

        expect(await menuOf(tester, 'ds-retreat-1'), {
          'Add to playlist…',
          'Copy as playlist',
          'Move to Talks',
          'Rename',
          'Labels',
          'Pin to Home',
          'Remove from library',
        });
        expect(await menuOf(tester, 'my-course-0123456789abcdef'), {
          'Edit playlist',
          'Add to playlist…',
          'Copy as playlist',
          'Move to Talks',
          'Rename',
          'Labels',
          'Pin to Home',
          'Delete playlist',
        });
        expect(await menuOf(tester, 'ds-talk-2'), {
          'Add to playlist…',
          'Move to Practice',
          'Rename',
          'Labels',
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
          final items = [
            ContinueItem(
              trackId: 't1',
              path: '/tracks/t1',
              title: 'Developing Piti, Developing Focus, Developing Wellbeing',
              group: LibraryGroup.practice,
              lastPlayed: DateTime(2026, 10, 25),
              courseId: 'ds-retreat-1',
              courseTitle: 'Practising the Jhānas',
              resume: const ResumePoint(
                positionMs: 1800000,
                durationMs: 5340000,
              ),
              sessionNumber: 4,
              sessionTotal: 32,
              completedSessions: 3,
            ),
          ];
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
            overrides: [
              ..._progress,
              inProgressItemsProvider.overrideWith((ref) async => items),
            ],
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
