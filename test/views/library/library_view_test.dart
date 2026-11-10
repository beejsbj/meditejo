import 'dart:io';

import 'package:medito/views/pack/widgets/pack_item_widget.dart';
import 'package:flutter/material.dart';
import 'package:medito/constants/colors/color_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/widgets/save_button.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/library/library_widgets.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/track/track_view.dart';
import 'package:medito/widgets/cards/section_title.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/library_fixtures.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

/// A section heading, not a chip's label.
Finder heading(String text) =>
    find.descendant(of: find.byType(SectionTitle), matching: find.text(text));

Future<void> add(
  WidgetTester tester,
  LibraryStore store,
  String id,
  String title, {
  LibraryKind kind = LibraryKind.course,
  LibraryGroup group = LibraryGroup.practice,
  String subtitle = '',
}) async {
  await tester.runAsync(
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
}

void main() {
  group('the library screen', () {
    testWidgets('lists sessions, then courses, then teachers (#80)', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      final store = app.harness.store;
      await add(
        tester,
        store,
        'ds-retreat-1',
        'A winter talk series',
        group: LibraryGroup.talks,
      );
      await add(tester, store, 'ds-retreat-2', 'Body scan course');
      await add(
        tester,
        store,
        'ds-teacher-1',
        'Rob Burbea',
        kind: LibraryKind.teacher,
      );
      await add(
        tester,
        store,
        'ds-talk-9',
        'One long talk',
        kind: LibraryKind.single,
        group: LibraryGroup.talks,
      );
      await app.pump(tester, const LibraryView());

      final sessions = tester.getTopLeft(heading('Sessions')).dy;
      final courses = tester.getTopLeft(heading('Courses')).dy;
      final teachers = tester.getTopLeft(heading('Teachers')).dy;
      expect(sessions, lessThan(courses));
      expect(courses, lessThan(teachers));
      // No Practice or Talks sections: a talk course and a practice course
      // sit together, under Courses.
      expect(heading('Practice'), findsNothing);
      expect(heading('Talks'), findsNothing);
      for (final title in ['Body scan course', 'A winter talk series']) {
        final y = tester.getTopLeft(find.text(title)).dy;
        expect(y, greaterThan(courses), reason: title);
        expect(y, lessThan(teachers), reason: title);
      }
      final talk = tester.getTopLeft(find.text('One long talk')).dy;
      expect(talk, greaterThan(sessions));
      expect(talk, lessThan(courses));
      expect(find.text('One long talk'), findsOneWidget);
    });

    testWidgets('says which rows are playlists and which are courses', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      final store = app.harness.store;
      await add(
        tester,
        store,
        'ds-retreat-2',
        'Body scan course',
        subtitle: 'Tara Brach',
      );
      await add(
        tester,
        store,
        'my-course-0123456789abcdef',
        'Morning sits',
        subtitle: '3 sessions',
      );
      await app.pump(tester, const LibraryView());

      // A playlist says what it is above its name; a course says its source.
      expect(find.text('Playlist'), findsOneWidget);
      expect(find.text('3 sessions'), findsOneWidget);
      expect(find.text('Dharma Seed'), findsOneWidget);
      expect(find.text('Tara Brach'), findsOneWidget);
      // New playlist lives behind the header's "+" (#62).
      expect(find.text('New playlist'), findsNothing);
      expect(find.byTooltip('Add to your library'), findsOneWidget);
    });

    testWidgets('empty, it invites the first addition', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(tester, const LibraryView(), asRoute: true);

      expect(find.text('Your library is empty'), findsOneWidget);
      // "Import", so it is not a second "Add to your library" beside the
      // header's "+" (#62).
      final emptyAdd = find.byKey(const ValueKey('library_empty_add'));
      expect(
        find.descendant(of: emptyAdd, matching: find.text('Import')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: emptyAdd,
          matching: find.text('Add to your library'),
        ),
        findsNothing,
      );
      await tester.tap(emptyAdd);
      await settle(tester);
      expect(find.byType(ImportView), findsOneWidget);
    });

    testWidgets('an entry can be moved between Practice and Talks', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await add(tester, app.harness.store, 'ds-retreat-1', 'Evening sits');
      await app.pump(tester, const LibraryView());
      expect(find.text('Practice 1'), findsOneWidget);
      expect(find.text('Talks 0'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Move to Talks'));
      await settle(tester);

      // The chips follow the move.
      expect(find.text('Practice 0'), findsOneWidget);
      expect(find.text('Talks 1'), findsOneWidget);
      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.group, LibraryGroup.talks);
      expect(entry.detectedGroup, LibraryGroup.practice);

      // And back: the choice is kept, even as what was detected (#80).
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Move to Practice'));
      await settle(tester);
      final back = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(back.groupOverride, LibraryGroup.practice);
      expect(find.text('Practice 1'), findsOneWidget);

      // Show by sessions forgets it.
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Show by sessions'));
      await settle(tester);
      final cleared = (await tester.runAsync(
        app.harness.store.entries,
      ))!.single;
      expect(cleared.groupOverride, isNull);
      expect(cleared.group, LibraryGroup.practice);
    });

    testWidgets('rename shows the new name and keeps the source title', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await add(tester, app.harness.store, 'ds-retreat-1', 'Evening sits');
      await app.pump(tester, const LibraryView());

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Rename'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'My evenings');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('My evenings'), findsOneWidget);
      expect(
        (await tester.runAsync(app.harness.store.entries))!.single.title,
        'Evening sits',
      );
    });

    testWidgets('removing a catalogue entry has an Undo', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await add(
        tester,
        app.harness.store,
        'ds-retreat-1',
        'Evening sits',
        subtitle: 'Somebody · 2020',
      );
      await app.pump(tester, const LibraryView());

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Remove from library'));
      await settle(tester);
      expect(find.text('Your library is empty'), findsOneWidget);
      expect(find.text('Removed from your library'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.text('Evening sits'), findsOneWidget);
    });

    testWidgets('removing an import asks first, and deletes its audio', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(
        tester,
        probe: (_) async => 60000,
      );
      late String copiedPath;
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(
          app.harness.writeAudio('Sit.mp3').path,
        );
        final result = await app.harness.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.single,
            group: LibraryGroup.practice,
          ),
        );
        copiedPath = (await app.harness.db.trackById(result.entryId))!.audioUrl;
      });
      await app.pump(tester, const LibraryView());
      expect(File(copiedPath).existsSync(), isTrue);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Remove from library'));
      await settle(tester);
      expect(find.text('Remove from your library?'), findsOneWidget);
      expect(find.textContaining('will be deleted'), findsOneWidget);

      // Backing out changes nothing.
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('Sit'), findsOneWidget);
      expect(File(copiedPath).existsSync(), isTrue);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Remove from library'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove from library'),
        ),
      );
      await settle(tester);
      expect(find.text('Your library is empty'), findsOneWidget);
      expect(File(copiedPath).existsSync(), isFalse);
    });

    testWidgets('an imported course opens on its course page, oldest first', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(
        tester,
        routes: {
          'https://example.org/evening.rss': xmlResponse(
            libraryFixture('rss_podcast.xml'),
          ),
        },
      );
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(
          'https://example.org/evening.rss',
        );
        await app.harness.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.course,
            group: LibraryGroup.practice,
          ),
        );
      });
      await app.pump(tester, const LibraryView());
      expect(find.text('Evening Sits'), findsOneWidget);

      await tester.tap(find.text('Evening Sits'));
      await settle(tester);
      expect(find.byType(PackView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PackItemWidget),
          matching: find.text('First sit: arriving'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('3 sessions'), findsOneWidget);
    });

    testWidgets('removing an imported course unpins it and its sessions', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(
        tester,
        routes: {
          'https://example.org/evening.rss': xmlResponse(
            libraryFixture('rss_podcast.xml'),
          ),
        },
      );
      late String courseId;
      late List<String> sessionIds;
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(
          'https://example.org/evening.rss',
        );
        final result = await app.harness.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.course,
            group: LibraryGroup.practice,
          ),
        );
        courseId = result.entryId;
        sessionIds = [...await app.harness.db.trackIdsOfCourse(courseId)];
      });
      await app.prefs.setStringList(SharedPreferenceConstants.pinnedCourseIds, [
        'ds-retreat-1',
        courseId,
        sessionIds.first,
      ]);
      await app.prefs.setStringList(
        SharedPreferenceConstants.pinnedSessionIds,
        [sessionIds.first],
      );
      await app.pump(tester, const LibraryView());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryView)),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Remove from library'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove from library'),
        ),
      );
      await settle(tester);

      // What is left is not an ID on Home.
      expect(container.read(pinnedCoursesProvider), ['ds-retreat-1']);
    });

    testWidgets('removing a course episode kept on its own keeps its pin', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(
        tester,
        routes: {
          'https://example.org/evening.rss': xmlResponse(
            libraryFixture('rss_podcast.xml'),
          ),
        },
      );
      late String episode;
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(
          'https://example.org/evening.rss',
        );
        final result = await app.harness.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.course,
            group: LibraryGroup.practice,
          ),
        );
        episode = (await app.harness.db.trackIdsOfCourse(result.entryId)).first;
        // The episode also saved as a single of its own.
        await app.harness.store.add(
          LibraryDraft(
            sourceId: episode,
            kind: LibraryKind.single,
            title: 'An episode on its own',
            group: LibraryGroup.practice,
          ),
        );
      });
      await app.prefs.setStringList(SharedPreferenceConstants.pinnedCourseIds, [
        episode,
      ]);
      await app.prefs.setStringList(
        SharedPreferenceConstants.pinnedSessionIds,
        [episode],
      );
      await app.pump(tester, const LibraryView());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryView)),
      );

      await tester.tap(find.byKey(ValueKey('library_menu_$episode')));
      await settle(tester);
      await tester.tap(find.text('Remove from library'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove from library'),
        ),
      );
      await settle(tester);

      // Only its own library entry went; the episode is still in its course.
      expect(find.text('An episode on its own'), findsNothing);
      expect(container.read(pinnedCoursesProvider), [episode]);
      expect(
        container.read(pinnedCoursesProvider.notifier).isSession(episode),
        isTrue,
      );
    });

    testWidgets('removing an import from its own page closes the page', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(
        tester,
        routes: {
          'https://example.org/evening.rss': xmlResponse(
            libraryFixture('rss_podcast.xml'),
          ),
        },
      );
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(
          'https://example.org/evening.rss',
        );
        await app.harness.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.course,
            group: LibraryGroup.practice,
          ),
        );
      });
      await app.pump(tester, const LibraryView());
      await tester.tap(find.text('Evening Sits'));
      await settle(tester);
      expect(find.byType(PackView), findsOneWidget);

      await tester.ensureVisible(find.byType(SaveIconButton));
      await tester.tap(find.byType(SaveIconButton));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove from library'),
        ),
      );
      await settle(tester);
      expect(find.byType(PackView), findsNothing);
      expect(find.text('Your library is empty'), findsOneWidget);
      // Said, though the page that asked is gone, in readable text: styled
      // from the app's messenger, not left white on the white snackbar.
      final said = find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Removed from your library'),
      );
      expect(said, findsOneWidget);
      expect(
        tester.widget<Text>(said).style?.color,
        ColorConstants.greyIsTheNewBlack,
      );
    });

    testWidgets(
      'a feed course can flip its order and stop checking for episodes',
      (tester) async {
        final app = await LibraryTestApp.create(
          tester,
          routes: {
            'https://example.org/evening.rss': xmlResponse(
              libraryFixture('rss_podcast.xml'),
            ),
          },
        );
        late String id;
        await tester.runAsync(() async {
          final preview = await app.harness.service.resolve(
            'https://example.org/evening.rss',
          );
          id = (await app.harness.service.add(
            preview,
            const ImportChoice(
              kind: LibraryKind.course,
              group: LibraryGroup.practice,
            ),
          )).entryId;
        });
        await app.pump(tester, PackView(id: id));

        // A row's title (the Play button names the next one too).
        double top(String title) => tester
            .getTopLeft(
              find.descendant(
                of: find.byType(PackItemWidget),
                matching: find.text(title),
              ),
            )
            .dy;
        expect(
          top('First sit: arriving'),
          lessThan(top('Third sit: open awareness')),
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('course_order_newest')),
        );
        await tester.tap(find.byKey(const ValueKey('course_order_newest')));
        await settle(tester);
        expect(
          top('Third sit: open awareness'),
          lessThan(top('First sit: arriving')),
        );
        expect(
          (await tester.runAsync(
            () => app.harness.db.courseById(id),
          ))!.episodeOrder,
          'newest',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('course_auto_refresh')),
        );
        await tester.tap(find.byKey(const ValueKey('course_auto_refresh')));
        await settle(tester);
        expect(
          (await tester.runAsync(
            () => app.harness.db.courseById(id),
          ))!.autoRefresh,
          isFalse,
        );
      },
    );

    testWidgets('an imported single opens its track page', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(
          app.harness.writeAudio('Metta.mp3').path,
        );
        await app.harness.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.single,
            group: LibraryGroup.practice,
          ),
        );
      });
      await app.pump(tester, const LibraryView());
      await tester.tap(find.text('Metta'));
      await settle(tester);
      expect(find.byType(TrackView), findsOneWidget);
    });

    testWidgets('courses can be pinned; past three, See all has them', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      for (final n in ['a', 'b', 'c', 'd']) {
        await add(tester, app.harness.store, 'ds-retreat-$n', 'Course $n');
      }
      await app.pump(tester, const LibraryView());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryView)),
      );

      Future<void> pin(String title) async {
        final menu = find.descendant(
          of: find.ancestor(
            of: find.text(title),
            matching: find.byType(LibraryEntryTile),
          ),
          matching: find.byIcon(Icons.more_vert_rounded),
        );
        await tester.tap(menu);
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('item_action_pin')));
        await settle(tester);
      }

      await pin('Course a');
      await pin('Course b');
      await pin('Course c');
      expect(container.read(pinnedCoursesProvider), hasLength(3));
      expect(find.text('Pinned to Home'), findsOneWidget);
      await pin('Course d');
      expect(container.read(pinnedCoursesProvider), [
        'ds-retreat-a',
        'ds-retreat-b',
        'ds-retreat-c',
        'ds-retreat-d',
      ]);
      expect(find.text('Pinned to Home, under See all'), findsOneWidget);
    });

    testWidgets('a single session is pinned as a session', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await add(
        tester,
        app.harness.store,
        'ds-talk-9',
        'Metta',
        kind: LibraryKind.single,
      );
      await app.pump(tester, const LibraryView());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryView)),
      );
      await tester.tap(find.byTooltip('Show menu').first);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('item_action_pin')));
      await settle(tester);
      expect(container.read(pinnedCoursesProvider), ['ds-talk-9']);
      expect(
        container.read(pinnedCoursesProvider.notifier).isSession('ds-talk-9'),
        isTrue,
      );
      // The row shows it is pinned.
      expect(find.bySemanticsLabel('Pinned to Home'), findsOneWidget);
    });
  });
}
