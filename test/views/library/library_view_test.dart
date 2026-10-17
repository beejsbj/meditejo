import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/views/home/widgets/library/home_library_section.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/track/track_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/library_fixtures.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

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
    testWidgets('lists Practice before Talks, then teachers', (tester) async {
      final app = await LibraryTestApp.create(tester);
      final store = app.harness.store;
      // Added first, so it would lead by time alone.
      await add(tester, store, 'ds-retreat-1', 'A winter talk series', group: LibraryGroup.talks);
      await add(tester, store, 'ds-retreat-2', 'Body scan course');
      await add(tester, store, 'ds-teacher-1', 'Rob Burbea', kind: LibraryKind.teacher);
      await add(tester, store, 'ds-talk-9', 'One long talk', kind: LibraryKind.single, group: LibraryGroup.talks);
      await app.pump(tester, const LibraryView());

      final practice = tester.getTopLeft(find.text('Practice')).dy;
      final talks = tester.getTopLeft(find.text('Talks')).dy;
      final teachers = tester.getTopLeft(find.text('Teachers')).dy;
      expect(practice, lessThan(talks));
      expect(talks, lessThan(teachers));
      expect(
        tester.getTopLeft(find.text('Body scan course')).dy,
        lessThan(tester.getTopLeft(find.text('A winter talk series')).dy),
      );
      expect(find.text('One long talk'), findsOneWidget);
    });

    testWidgets('empty, it invites the first addition', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(tester, const LibraryView(), asRoute: true);

      expect(find.text('Your library is empty'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('library_empty_add')));
      await settle(tester);
      expect(find.byType(ImportView), findsOneWidget);
    });

    testWidgets('an entry can be moved between Practice and Talks', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await add(tester, app.harness.store, 'ds-retreat-1', 'Evening sits');
      await app.pump(tester, const LibraryView());
      expect(find.text('Talks'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Move to Talks'));
      await settle(tester);

      expect(find.text('Talks'), findsOneWidget);
      expect(find.text('Practice'), findsNothing);
      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.group, LibraryGroup.talks);
      expect(entry.detectedGroup, LibraryGroup.practice);

      // And back: the override is cleared, not stacked.
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Move to Practice'));
      await settle(tester);
      final back = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(back.groupOverride, isNull);
    });

    testWidgets('rename shows the new name and keeps the source title', (tester) async {
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
      expect((await tester.runAsync(app.harness.store.entries))!.single.title, 'Evening sits');
    });

    testWidgets('removing a catalogue entry has an Undo', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await add(tester, app.harness.store, 'ds-retreat-1', 'Evening sits', subtitle: 'Somebody · 2020');
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

    testWidgets('removing an import asks first, and deletes its audio', (tester) async {
      final app = await LibraryTestApp.create(tester, probe: (_) async => 60000);
      late String copiedPath;
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(app.harness.writeAudio('Sit.mp3').path);
        final result = await app.harness.service.add(
          preview,
          const ImportChoice(kind: LibraryKind.single, group: LibraryGroup.practice),
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
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Remove from library')));
      await settle(tester);
      expect(find.text('Your library is empty'), findsOneWidget);
      expect(File(copiedPath).existsSync(), isFalse);
    });

    testWidgets('an imported course opens on its course page, oldest first', (tester) async {
      final app = await LibraryTestApp.create(
        tester,
        routes: {'https://example.org/evening.rss': xmlResponse(libraryFixture('rss_podcast.xml'))},
      );
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve('https://example.org/evening.rss');
        await app.harness.service.add(
          preview,
          const ImportChoice(kind: LibraryKind.course, group: LibraryGroup.practice),
        );
      });
      await app.pump(tester, const LibraryView());
      expect(find.text('Evening Sits'), findsOneWidget);

      await tester.tap(find.text('Evening Sits'));
      await settle(tester);
      expect(find.byType(PackView), findsOneWidget);
      expect(find.text('First sit: arriving'), findsOneWidget);
      expect(find.text('3 of 3 left'), findsOneWidget);
    });

    testWidgets('an imported single opens its track page', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(app.harness.writeAudio('Metta.mp3').path);
        await app.harness.service.add(
          preview,
          const ImportChoice(kind: LibraryKind.single, group: LibraryGroup.practice),
        );
      });
      await app.pump(tester, const LibraryView());
      await tester.tap(find.text('Metta'));
      await settle(tester);
      expect(find.byType(TrackView), findsOneWidget);
    });
  });

  group('Home', () {
    testWidgets('leads with the library, practice before talks', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await add(tester, app.harness.store, 'ds-retreat-1', 'Winter talks', group: LibraryGroup.talks);
      await add(tester, app.harness.store, 'ds-retreat-2', 'Body scan');
      await app.pump(tester, const Scaffold(body: SingleChildScrollView(child: HomeLibrarySection())));

      expect(find.text('Your library'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Body scan')).dx,
        lessThan(tester.getTopLeft(find.text('Winter talks')).dx),
        reason: 'the rail runs practice first',
      );
    });

    testWidgets('empty, it says how to start and offers Add', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const Scaffold(body: HomeLibrarySection()),
        asRoute: true,
      );
      expect(find.text('Paste a link, share one from another app, or pick a file.'), findsOneWidget);
      expect(find.text('See all'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('home_library_add')));
      await settle(tester);
      expect(find.byType(ImportView), findsOneWidget);
    });

    testWidgets('See all opens the library', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await add(tester, app.harness.store, 'ds-retreat-1', 'Body scan');
      await app.pump(tester, const Scaffold(body: HomeLibrarySection()));
      await tester.tap(find.byKey(const ValueKey('library_see_all')));
      await settle(tester);
      expect(find.byType(LibraryView), findsOneWidget);
    });
  });
}
