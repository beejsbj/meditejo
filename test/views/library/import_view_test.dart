import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/library/import_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/library_fixtures.dart';

const feedUrl = 'https://example.org/evening.rss';

Map<String, http.Response> get feedRoutes => {
  feedUrl: xmlResponse(libraryFixture('rss_podcast.xml')),
  'https://example.org/sit.mp3': audioResponse(),
};

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

Future<void> enterLink(WidgetTester tester, String link) async {
  await tester.enterText(find.byKey(const ValueKey('import_field')), link);
  await tester.tap(find.byKey(const ValueKey('import_go')));
  await settle(tester);
}

void main() {
  group('previewing', () {
    testWidgets('a feed link shows a calm preview with one primary action', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);

      await enterLink(tester, feedUrl);

      expect(find.byKey(const ValueKey('import_preview')), findsOneWidget);
      expect(find.text('Evening Sits'), findsOneWidget);
      expect(find.textContaining('example.org'), findsWidgets);
      expect(find.text('3 sessions · at least 1 h 33 min'), findsOneWidget);
      expect(find.text('First sit: arriving'), findsOneWidget);
      expect(find.text('Third sit: open awareness'), findsOneWidget);
      // Licence where the feed states one.
      expect(find.text('CC BY-NC 4.0'), findsOneWidget);
      // One primary action; nothing stored by looking.
      expect(find.text('Add to library'), findsOneWidget);
      expect(await tester.runAsync(app.harness.store.entries), isEmpty);
    });

    testWidgets('Practice is the default, Talk is one tap away', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, feedUrl);

      final group = tester.widget<SegmentedButton<LibraryGroup>>(
        find.byKey(const ValueKey('import_group')),
      );
      expect(group.selected, {LibraryGroup.practice});

      await tester.tap(find.text('Talk'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('import_add')));
      await tester.tap(find.byKey(const ValueKey('import_add')));
      await settle(tester);

      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.group, LibraryGroup.talks);
      expect(
        entry.detectedGroup,
        LibraryGroup.practice,
        reason: 'the override is kept apart',
      );
    });

    testWidgets('a feed offers Course or Single, and adding makes a course', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, feedUrl);

      expect(find.byKey(const ValueKey('import_kind')), findsOneWidget);
      expect(find.text('All 3 episodes, in order'), findsOneWidget);
      expect(find.text('Oldest first'), findsOneWidget);

      await tester.tap(find.text('Single'));
      await settle(tester);
      expect(find.text('Just the latest episode'), findsOneWidget);
      await tester.tap(find.text('Course'));
      await settle(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('import_add')));
      await tester.tap(find.byKey(const ValueKey('import_add')));
      await settle(tester);

      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.kind, LibraryKind.course);
      expect(entry.title, 'Evening Sits');
      expect(entry.itemCount, 3);
      expect(
        find.byType(ImportView),
        findsNothing,
        reason: 'the screen closes when done',
      );
    });

    testWidgets('a direct audio link is a single, with no kind choice', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, 'https://example.org/sit.mp3');

      expect(find.text('sit'), findsOneWidget);
      expect(find.byKey(const ValueKey('import_kind')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('import_add')));
      await settle(tester);
      expect(
        (await tester.runAsync(app.harness.store.entries))!.single.kind,
        LibraryKind.single,
      );
    });

    testWidgets('the name can be changed before adding, in the library only', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, 'https://example.org/sit.mp3');

      await tester.tap(find.byKey(const ValueKey('import_edit_title')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('import_title_field')),
        'Morning sit',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('Morning sit'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import_add')));
      await settle(tester);
      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.displayTitle, 'Morning sit');
      expect(entry.title, 'sit');
    });

    testWidgets('something already in the library says so and offers Open', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, feedUrl);
      await tester.ensureVisible(find.byKey(const ValueKey('import_add')));
      await tester.tap(find.byKey(const ValueKey('import_add')));
      await settle(tester);

      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, feedUrl);
      expect(find.byKey(const ValueKey('import_already')), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.byKey(const ValueKey('import_kind')), findsNothing);
    });
  });

  group('the clipboard and pasting', () {
    testWidgets('a link on the clipboard is offered, not taken', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(
        tester,
        const ImportView(),
        asRoute: true,
        clipboard: feedUrl,
      );

      expect(find.text('Link on your clipboard: example.org'), findsOneWidget);
      expect(find.byKey(const ValueKey('import_preview')), findsNothing);
      expect(
        app.harness.web.requests,
        isEmpty,
        reason: 'nothing is fetched until the user says so',
      );

      await tester.tap(find.byKey(const ValueKey('import_use_clipboard')));
      await settle(tester);
      expect(find.text('Evening Sits'), findsOneWidget);
    });

    testWidgets('no link on the clipboard, no suggestion', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(tester, const ImportView(), asRoute: true);
      expect(find.byKey(const ValueKey('import_use_clipboard')), findsNothing);
      expect(find.text('Paste a link'), findsOneWidget);
    });
  });

  group('calm failures', () {
    testWidgets('YouTube says it is coming, in plain words', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, 'https://www.youtube.com/watch?v=abc');

      expect(find.textContaining('YouTube support is coming'), findsOneWidget);
      expect(find.byKey(const ValueKey('import_preview')), findsNothing);
      expect(find.byKey(const ValueKey('import_add')), findsNothing);
      expect(app.harness.web.requests, isEmpty);
    });

    testWidgets('a broken link explains itself without a stack trace', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, 'https://example.org/nowhere');

      expect(find.byKey(const ValueKey('import_failure')), findsOneWidget);
      expect(find.textContaining("That page wasn't found"), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('404'), findsNothing);
    });

    testWidgets('empty input and nonsense are gentle too', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(tester, const ImportView(), asRoute: true);
      await tester.tap(find.byKey(const ValueKey('import_go')));
      await settle(tester);
      expect(
        find.text('Paste a link or choose a file to begin.'),
        findsOneWidget,
      );

      await enterLink(tester, 'hello there');
      expect(find.textContaining("doesn't look like a link"), findsOneWidget);
    });

    testWidgets('a failure goes away when a good link follows', (tester) async {
      final app = await LibraryTestApp.create(tester, routes: feedRoutes);
      await app.pump(tester, const ImportView(), asRoute: true);
      await enterLink(tester, 'https://youtu.be/abc');
      expect(find.byKey(const ValueKey('import_failure')), findsOneWidget);
      await enterLink(tester, feedUrl);
      expect(find.byKey(const ValueKey('import_failure')), findsNothing);
      expect(find.text('Evening Sits'), findsOneWidget);
    });
  });

  group('files', () {
    testWidgets('chosen files become a course, or singles', (tester) async {
      final app = await LibraryTestApp.create(
        tester,
        probe: (_) async => 60000,
      );
      late PickedFile a, b;
      await tester.runAsync(() async {
        a = PickedFile(path: app.harness.writeAudio('01 arrive.mp3').path);
        b = PickedFile(path: app.harness.writeAudio('02 settle.mp3').path);
      });
      app.pickers.files = [a, b];
      await app.pump(tester, const ImportView(), asRoute: true);

      await tester.tap(find.byKey(const ValueKey('import_files')));
      await settle(tester);

      expect(find.text('2 sessions · 2 min'), findsOneWidget);
      expect(find.text('01 arrive'), findsOneWidget);
      expect(find.text('This device'), findsWidgets);
      expect(find.text('One course, in the order shown'), findsOneWidget);
      await tester.tap(find.text('Single'));
      await settle(tester);
      expect(find.text('Each file on its own'), findsOneWidget);
      await tester.tap(find.text('Course'));
      await settle(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('import_add')));
      await tester.tap(find.byKey(const ValueKey('import_add')));
      await settle(tester);
      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.kind, LibraryKind.course);
      expect(
        entry.title,
        'Imported audio',
        reason: 'a default name for several files',
      );
    });

    testWidgets('editing the link while it resolves drops that result', (
      tester,
    ) async {
      final gate = Completer<int?>();
      final app = await LibraryTestApp.create(
        tester,
        probe: (_) => gate.future,
      );
      late PickedFile file;
      await tester.runAsync(() async {
        file = PickedFile(path: app.harness.writeAudio('Metta.mp3').path);
      });
      app.pickers.files = [file];
      await app.pump(tester, const ImportView(), asRoute: true);

      await tester.tap(find.byKey(const ValueKey('import_files')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('import_field')),
        'https://example.org/other',
      );
      gate.complete(60000);
      await settle(tester);

      expect(find.byKey(const ValueKey('import_preview')), findsNothing);
    });

    testWidgets('files that arrive from outside are previewed at once', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      late PickedFile file;
      await tester.runAsync(() async {
        file = PickedFile(path: app.harness.writeAudio('Metta.mp3').path);
      });
      await app.pump(tester, ImportView(initialFiles: [file]), asRoute: true);
      expect(find.byKey(const ValueKey('import_preview')), findsOneWidget);
      expect(find.text('Metta'), findsOneWidget);
    });
  });

  testWidgets('a link that arrives from outside is previewed at once', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester, routes: feedRoutes);
    await app.pump(
      tester,
      const ImportView(
        initialText: 'Listen to this: https://example.org/evening.rss thanks!',
      ),
    );
    expect(find.text('Evening Sits'), findsOneWidget);
    expect(app.harness.web.urls, [feedUrl]);
  });
}
