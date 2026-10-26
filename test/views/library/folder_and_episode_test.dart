import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/services/library/folder_import.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/library/import_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/library_fixtures.dart';

const feedUrl = 'https://example.org/evening.rss';

Map<String, http.Response> get feedRoutes => {
  feedUrl: xmlResponse(libraryFixture('rss_podcast.xml')),
};

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

Future<void> enterLink(WidgetTester tester, String link) async {
  await tester.enterText(find.byKey(const ValueKey('import_field')), link);
  await tester.tap(find.byKey(const ValueKey('import_go')));
  await settle(tester);
}

Future<void> tapAdd(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('import_add')));
  await tester.tap(find.byKey(const ValueKey('import_add')));
  await settle(tester);
  // Storing takes several real file-system hops; the screen closes when done.
  for (
    var i = 0;
    i < 12 && find.byType(ImportView).evaluate().isNotEmpty;
    i++
  ) {
    await settle(tester);
  }
}

Future<void> chooseSingle(WidgetTester tester) async {
  await tester.tap(find.text('Single'));
  await settle(tester);
}

Future<void> openPicker(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('import_episode_change')),
  );
  await tester.tap(find.byKey(const ValueKey('import_episode_change')));
  await settle(tester);
}

/// A feed of [count] numbered episodes, newest last in the file as feeds go.
String longFeed(int count) {
  final items = StringBuffer();
  for (var i = 1; i <= count; i++) {
    items.writeln('''
<item>
  <title>Sit $i</title>
  <guid isPermaLink="false">long-$i</guid>
  <pubDate>${DateTime.utc(2025, 1, 1).add(Duration(days: i)).toIso8601String()}</pubDate>
  <enclosure url="https://cdn.example.org/long-$i.mp3" length="100" type="audio/mpeg"/>
  <itunes:duration>${i * 60}</itunes:duration>
</item>''');
  }
  return '''<?xml version="1.0"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel><title>Long Course</title><link>https://example.org/long</link>
$items</channel></rss>''';
}

void main() {
  group('importing a folder', () {
    /// A copied folder as the Android channel hands it over.
    Future<PickedFolder> copiedFolder(
      LibraryTestApp app,
      WidgetTester tester, {
      int unreadable = 0,
    }) async {
      late List<PickedFile> files;
      await tester.runAsync(() async {
        final staged = Directory(
          '${app.harness.storage.path}/cache/folder_import',
        )..createSync(recursive: true);
        files = [
          for (final (index, name) in [
            'Session 2.mp3',
            'Session 10.mp3',
          ].indexed)
            PickedFile(
              path: (File(
                '${staged.path}/00${index + 1}-$name',
              )..writeAsStringSync('audio')).path,
              name: name,
              mimeType: 'audio/mpeg',
            ),
        ];
      });
      return PickedFolder.copied(
        name: 'Retreat',
        files: files,
        unreadable: unreadable,
      );
    }

    testWidgets('a copied folder previews as a course and adds', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      app.pickers.copiedFolder = await copiedFolder(app, tester, unreadable: 1);
      await app.pump(tester, const ImportView(), asRoute: true);

      await tester.tap(find.byKey(const ValueKey('import_folder')));
      await settle(tester);

      expect(find.byKey(const ValueKey('import_preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('import_title')), findsOneWidget);
      expect(find.text('Retreat'), findsOneWidget);
      expect(find.text('One course, in the order shown'), findsOneWidget);
      expect(find.text('Session 2'), findsOneWidget);
      expect(
        find.text("1 item couldn't be read and was left out"),
        findsOneWidget,
        reason: 'what was skipped is reported, not hidden',
      );

      await tapAdd(tester);

      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.kind, LibraryKind.course);
      expect(entry.title, 'Retreat');
      expect(entry.itemCount, 2);
      final library = Directory('${app.harness.storage.path}/library');
      expect(library.listSync(), hasLength(2));
      expect(
        Directory('${app.harness.storage.path}/cache/folder_import').listSync(),
        isEmpty,
        reason: 'the staged files were moved, not copied twice',
      );
    });

    testWidgets('the folder\'s files can be added as separate singles', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      app.pickers.copiedFolder = await copiedFolder(app, tester);
      await app.pump(tester, const ImportView(), asRoute: true);
      await tester.tap(find.byKey(const ValueKey('import_folder')));
      await settle(tester);

      await chooseSingle(tester);
      expect(find.text('Each file on its own'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('import_episode')),
        findsNothing,
        reason: 'files are all added; there is no one episode to pick',
      );
      await tapAdd(tester);

      final entries = (await tester.runAsync(app.harness.store.entries))!;
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.kind == LibraryKind.single), isTrue);
    });

    testWidgets('progress shows while it copies, and Cancel stops it', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      final gate = Completer<PickedFolder?>();
      void Function(FolderProgress)? report;
      app.pickers.onPickFolder = (onProgress) {
        report = onProgress;
        return gate.future;
      };
      await app.pump(tester, const ImportView(), asRoute: true);

      await tester.tap(find.byKey(const ValueKey('import_folder')));
      await tester.pump();
      expect(find.text('Looking in the folder…'), findsOneWidget);

      report!(
        const FolderProgress(
          filesDone: 1,
          filesTotal: 5,
          bytesDone: 100,
          bytesTotal: 500,
          name: 'Session 2.mp3',
        ),
      );
      await tester.pump();
      expect(find.text('Copying 2 of 5…'), findsOneWidget);
      expect(find.text('Session 2.mp3'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.2);

      await tester.tap(find.byKey(const ValueKey('import_folder_cancel')));
      expect(app.pickers.cancelCalls, 1);
      gate.complete(null); // the native side answers a cancel with nothing
      await settle(tester);

      expect(
        find.byKey(const ValueKey('import_folder_progress')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('import_failure')), findsNothing);
      expect(find.byKey(const ValueKey('import_preview')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('Choose a folder'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNotNull,
        reason: 'the buttons are back',
      );
    });

    testWidgets('backing out of the system picker changes nothing', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(tester, const ImportView(), asRoute: true);

      await tester.tap(find.byKey(const ValueKey('import_folder')));
      await settle(tester);

      expect(find.byKey(const ValueKey('import_failure')), findsNothing);
      expect(find.byKey(const ValueKey('import_preview')), findsNothing);
      expect(
        find.byKey(const ValueKey('import_folder_progress')),
        findsNothing,
      );
    });

    const failures = {
      ImportFailureReason.folderEmpty: 'That folder is empty.',
      ImportFailureReason.noAudioFiles: 'No audio files found there.',
      ImportFailureReason.folderTooLarge:
          'That folder holds more than 1,000 audio files. Choose a smaller one.',
      ImportFailureReason.folderNoSpace:
          "There isn't enough free space on this phone to copy that folder.",
      ImportFailureReason.folderUnreadable:
          "That folder couldn't be read. Try choosing it again, or choose files instead.",
      ImportFailureReason.folderUnavailable:
          'This device has no folder picker. Choose files instead.',
    };
    for (final entry in failures.entries) {
      testWidgets('${entry.key.name} is a sentence, not a code', (
        tester,
      ) async {
        final app = await LibraryTestApp.create(tester);
        app.pickers.onPickFolder = (_) async => throw ImportFailure(entry.key);
        await app.pump(tester, const ImportView(), asRoute: true);

        await tester.tap(find.byKey(const ValueKey('import_folder')));
        await settle(tester);

        expect(find.text(entry.value), findsOneWidget);
        expect(
          find.byKey(const ValueKey('import_folder_progress')),
          findsNothing,
        );
      });
    }

    testWidgets('where a folder is read by path (iOS) it still previews', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await tester.runAsync(() async {
        app.harness.writeAudio('Session 2.mp3');
        app.harness.writeAudio('Session 10.mp3');
      });
      app.pickers.folder = '${app.harness.storage.path}/inbox';
      await app.pump(tester, const ImportView(), asRoute: true);

      await tester.tap(find.byKey(const ValueKey('import_folder')));
      // Listing a folder by path takes several real file-system hops.
      for (var i = 0; i < 6; i++) {
        await settle(tester);
      }

      expect(find.byKey(const ValueKey('import_preview')), findsOneWidget);
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('leaving the screen discards what it staged, and only that', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(tester, const ImportView(), asRoute: true);
      await tester.pageBack();
      await settle(tester);
      expect(
        app.pickers.discardCalls,
        0,
        reason: 'a screen that staged nothing must not wipe another\'s files',
      );

      app.pickers.copiedFolder = await copiedFolder(app, tester);
      await app.pump(tester, const ImportView(), asRoute: true);
      await tester.tap(find.byKey(const ValueKey('import_folder')));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      expect(app.pickers.discardCalls, 1);
    });

    testWidgets('Cancel also drops a preview still being worked out', (
      tester,
    ) async {
      final gate = Completer<int?>();
      final app = await LibraryTestApp.create(
        tester,
        probe: (_) => gate.future,
      );
      app.pickers.copiedFolder = await copiedFolder(app, tester);
      await app.pump(tester, const ImportView(), asRoute: true);

      await tester.tap(find.byKey(const ValueKey('import_folder')));
      // The copy is done; the files' lengths are still being read.
      // (No `settle`: its long pumps would trip the 8 s length-probe timeout.)
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.byKey(const ValueKey('import_folder_progress')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('import_folder_cancel')));
      await tester.pump();
      expect(app.pickers.cancelCalls, 1);
      expect(
        find.byKey(const ValueKey('import_folder_progress')),
        findsNothing,
      );

      gate.complete(60000);
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.byKey(const ValueKey('import_preview')),
        findsNothing,
        reason: 'the cancelled pick must not turn up afterwards',
      );
    });
  });

  group('picking an episode', () {
    testWidgets('Single shows the latest episode, ready to add', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, feedUrl);
      expect(
        find.byKey(const ValueKey('import_episode')),
        findsNothing,
        reason: 'a Course has no episode to pick',
      );

      await chooseSingle(tester);

      expect(find.byKey(const ValueKey('import_episode')), findsOneWidget);
      expect(find.text('Third sit: open awareness'), findsNWidgets(2));
      expect(find.textContaining('Latest · Jun 10, 2025'), findsOneWidget);
      expect(find.text('1 session · 1 h 2 min'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        contains('evening.rss'),
      );

      await tapAdd(tester);
      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.kind, LibraryKind.single);
      expect(entry.title, 'Third sit: open awareness');
    });

    testWidgets('Change lists the episodes, newest first, and a pick sticks', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, feedUrl);
      await chooseSingle(tester);

      await openPicker(tester);

      expect(find.text('Choose an episode'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('episode_search')),
        findsNothing,
        reason: 'three episodes need no search',
      );
      final order = [
        for (final id in ['ep-3', 'ep-2', 'ep-1'])
          tester.getTopLeft(find.byKey(ValueKey('episode_$id'))).dy,
      ];
      expect(order, [...order]..sort(), reason: 'newest first');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('episode_ep-3')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
        reason: 'the current choice is marked',
      );

      await tester.tap(find.byKey(const ValueKey('episode_ep-2')));
      await settle(tester);

      expect(find.text('Choose an episode'), findsNothing);
      expect(find.text('Second sit: the breath'), findsNWidgets(2));
      expect(find.textContaining('Latest'), findsNothing);
      expect(find.text('1 session · 31 min'), findsOneWidget);

      await tapAdd(tester);
      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.kind, LibraryKind.single);
      expect(entry.title, 'Second sit: the breath');
    });

    testWidgets('a name the user typed survives picking another episode', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, feedUrl);
      await chooseSingle(tester);

      await tester.tap(find.byKey(const ValueKey('import_edit_title')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('import_title_field')),
        'Evening favourite',
      );
      await openPicker(tester);
      await tester.tap(find.byKey(const ValueKey('episode_ep-1')));
      await settle(tester);

      await tapAdd(tester);
      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.displayTitle, 'Evening favourite');
    });

    testWidgets('an episode already kept says so, and another does not', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(feedUrl);
        await app.harness.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.single,
            group: LibraryGroup.practice,
            episodeId: 'ep-2',
          ),
        );
      });
      await enterLink(tester, feedUrl);
      await chooseSingle(tester);
      expect(find.byKey(const ValueKey('import_already')), findsNothing);

      await openPicker(tester);
      await tester.tap(find.byKey(const ValueKey('episode_ep-2')));
      await settle(tester);

      expect(find.byKey(const ValueKey('import_already')), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);

      await openPicker(tester);
      await tester.tap(find.byKey(const ValueKey('episode_ep-1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('import_already')), findsNothing);
      expect(find.text('Add to library'), findsOneWidget);
    });

    testWidgets('a long list can be searched', (tester) async {
      final app = await LibraryTestApp.create(
        tester,
        routes: {feedUrl: xmlResponse(longFeed(20))},
      );
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, feedUrl);
      await chooseSingle(tester);
      expect(find.text('Sit 20'), findsNWidgets(2), reason: 'the latest');

      await openPicker(tester);
      expect(find.byKey(const ValueKey('episode_search')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('episode_search')),
        'sit 7',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('episode_long-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('episode_long-8')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('episode_search')),
        'nothing like this',
      );
      await tester.pump();
      expect(find.text('No episode matches that.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('episode_search')),
        'sit 7',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('episode_long-7')));
      await settle(tester);
      await tapAdd(tester);
      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.title, 'Sit 7');
    });

    testWidgets('a feed with one episode has nothing to choose', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(
        tester,
        routes: {feedUrl: xmlResponse(longFeed(1))},
      );
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, feedUrl);
      await chooseSingle(tester);

      expect(find.byKey(const ValueKey('import_episode')), findsNothing);
      await tapAdd(tester);
      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.title, 'Sit 1');
    });
  });
}
