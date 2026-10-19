import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/import_http.dart';
import 'package:medito/services/library/import_service.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/views/library/import_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/youtube_fake.dart';

const watchA = 'https://www.youtube.com/watch?v=$videoA';
const listOne = 'https://www.youtube.com/playlist?list=$playlistOne';

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
}

FakeYoutubeApi scriptedApi() => FakeYoutubeApi()
  ..videos[videoA] = video(videoA, title: 'A quiet sit', seconds: 600)
  ..playlists[playlistOne] = playlist([
    item(videoA, title: 'First sit', seconds: 600),
    item(videoB, title: 'Second sit', seconds: 1200),
    item(videoA, title: 'First sit', seconds: 600),
  ]);

/// The library screens, with the import service given a YouTube source that
/// talks to [api] instead of the platform.
Future<LibraryTestApp> openImport(
  WidgetTester tester,
  FakeYoutubeApi api,
) async {
  final app = await LibraryTestApp.create(tester);
  await pumpImport(tester, app, api);
  return app;
}

Future<void> pumpImport(
  WidgetTester tester,
  LibraryTestApp app,
  FakeYoutubeApi api,
) async {
  final h = app.harness;
  final source = YoutubeSource(db: h.db, library: h.store, api: api);
  final service = ImportService(
    http: ImportHttp(client: h.web.client),
    lib: h.lib,
    library: h.store,
    dharmaSeed: h.dharmaSeed,
    youtube: source,
    storageDirectory: () async => h.storage,
  );
  await app.pump(
    tester,
    const ImportView(),
    asRoute: true,
    overrides: [
      youtubeSourceProvider.overrideWithValue(source),
      importServiceProvider.overrideWithValue(service),
    ],
  );
}

SegmentedButton<LibraryGroup> groupButton(WidgetTester tester) =>
    tester.widget(find.byKey(const ValueKey('import_group')));

void main() {
  group('previewing a YouTube link', () {
    testWidgets('a video shows its title, channel, count and length', (
      tester,
    ) async {
      final api = scriptedApi();
      final app = await openImport(tester, api);

      await enterLink(tester, watchA);

      expect(find.byKey(const ValueKey('import_preview')), findsOneWidget);
      expect(find.text('A quiet sit'), findsOneWidget);
      expect(find.text('YouTube · Quiet Channel'), findsOneWidget);
      expect(find.text('1 session · 10 min'), findsOneWidget);
      expect(find.text('Add to library'), findsOneWidget);
      expect(
        await tester.runAsync(app.harness.store.entries),
        isEmpty,
        reason: 'nothing stored by looking',
      );
      expect(app.harness.web.requests, isEmpty, reason: 'no web fetch');
      expect(api.audioCalls, isEmpty, reason: 'no audio asked for');
    });

    testWidgets('a playlist shows its count and total length', (tester) async {
      final api = scriptedApi();
      await openImport(tester, api);

      await enterLink(tester, listOne);

      expect(find.text('Evening Sits'), findsOneWidget);
      expect(find.text('YouTube · Quiet Channel'), findsOneWidget);
      expect(find.text('3 sessions · 40 min'), findsOneWidget);
      expect(find.text('First sit'), findsNWidgets(2), reason: 'repeat kept');
      expect(find.text('Second sit'), findsOneWidget);
      expect(find.text('20 min'), findsOneWidget);
    });

    testWidgets('a video offers Course or Single; a playlist alone does not', (
      tester,
    ) async {
      final api = scriptedApi();
      await openImport(tester, api);

      await enterLink(tester, watchA);
      expect(find.byKey(const ValueKey('import_kind')), findsOneWidget);
      expect(find.text('Course'), findsOneWidget);
      expect(find.text('Single'), findsOneWidget);

      await enterLink(tester, listOne);
      expect(find.byKey(const ValueKey('import_kind')), findsNothing);
    });

    testWidgets('a video inside a list offers both and starts as the course', (
      tester,
    ) async {
      final api = scriptedApi();
      await openImport(tester, api);

      await enterLink(tester, '$watchA&list=$playlistOne');

      expect(find.byKey(const ValueKey('import_kind')), findsOneWidget);
      expect(find.text('Evening Sits'), findsOneWidget);
      expect(find.text('3 sessions · 40 min'), findsOneWidget);
      final kind = tester.widget<SegmentedButton<LibraryKind>>(
        find.byKey(const ValueKey('import_kind')),
      );
      expect(kind.selected, {LibraryKind.course});
    });

    testWidgets('the Single choice counts one session and that video', (
      tester,
    ) async {
      final api = scriptedApi();
      await openImport(tester, api);
      await enterLink(tester, '$watchA&list=$playlistOne');

      await tester.tap(find.text('Single'));
      await settle(tester);

      expect(find.text('1 session · 10 min'), findsOneWidget);
      expect(find.text('A quiet sit'), findsOneWidget);
    });
  });

  group('Practice or Talk', () {
    testWidgets('a plain title starts as Practice', (tester) async {
      await openImport(tester, scriptedApi());
      await enterLink(tester, watchA);
      expect(groupButton(tester).selected, {LibraryGroup.practice});
    });

    testWidgets('a talk-like title starts as Talk', (tester) async {
      final api = scriptedApi()
        ..videos[videoA] = video(videoA, title: 'Dharma talk: patience');
      await openImport(tester, api);
      await enterLink(tester, watchA);
      expect(groupButton(tester).selected, {LibraryGroup.talks});
    });

    testWidgets('a tap overrides the guess and the guess is kept apart', (
      tester,
    ) async {
      final api = scriptedApi()
        ..videos[videoA] = video(videoA, title: 'Dharma talk: patience');
      final app = await openImport(tester, api);
      await enterLink(tester, watchA);

      await tester.tap(find.text('Practice'));
      await settle(tester);
      expect(groupButton(tester).selected, {LibraryGroup.practice});
      await tapAdd(tester);

      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.groupOverride, LibraryGroup.practice);
      expect(entry.detectedGroup, LibraryGroup.talks);
    });

    testWidgets('Talk chosen on a plain title is an override too', (
      tester,
    ) async {
      final app = await openImport(tester, scriptedApi());
      await enterLink(tester, listOne);

      await tester.tap(find.text('Talk'));
      await settle(tester);
      await tapAdd(tester);

      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.group, LibraryGroup.talks);
      expect(entry.detectedGroup, LibraryGroup.practice);
    });
  });

  group('adding', () {
    testWidgets('a playlist becomes a course with the stable ID', (
      tester,
    ) async {
      final app = await openImport(tester, scriptedApi());
      await enterLink(tester, listOne);
      await tapAdd(tester);

      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.sourceId, ytPlaylistId(playlistOne));
      expect(entry.kind, LibraryKind.course);
      expect(entry.title, 'Evening Sits');
      expect(entry.itemCount, 3);
      expect(find.byType(ImportView), findsNothing, reason: 'closes when done');
    });

    testWidgets('a video added as Single is the stable video ID', (
      tester,
    ) async {
      final app = await openImport(tester, scriptedApi());
      await enterLink(tester, watchA);
      await tester.tap(find.text('Single'));
      await settle(tester);
      await tapAdd(tester);

      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.sourceId, ytVideoId(videoA));
      expect(entry.kind, LibraryKind.single);
      expect(entry.title, 'A quiet sit');
    });

    testWidgets('a video added as Course is a one-session course', (
      tester,
    ) async {
      final app = await openImport(tester, scriptedApi());
      await enterLink(tester, watchA);
      await tester.tap(find.text('Course'));
      await settle(tester);
      await tapAdd(tester);

      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.sourceId, ytSingleCourseId(videoA));
      expect(entry.kind, LibraryKind.course);
      expect(entry.itemCount, 1);
    });

    testWidgets('the name can be changed before adding', (tester) async {
      final app = await openImport(tester, scriptedApi());
      await enterLink(tester, listOne);

      await tester.tap(find.byKey(const ValueKey('import_edit_title')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('import_title_field')),
        'My evenings',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      await tapAdd(tester);

      final entry = (await tester.runAsync(app.harness.store.entries))!.single;
      expect(entry.displayTitle, 'My evenings');
      expect(entry.title, 'Evening Sits');
    });

    testWidgets(
      'a kept playlist can also add its addressed video as a Single',
      (tester) async {
        final api = scriptedApi();
        final app = await openImport(tester, api);
        await enterLink(tester, '$watchA&list=$playlistOne');
        await tapAdd(tester);
        await pumpImport(tester, app, api);
        await enterLink(tester, '$watchA&list=$playlistOne');
        expect(find.text('Open'), findsOneWidget);
        await tester.tap(find.text('Single'));
        await settle(tester);
        expect(find.text('A quiet sit'), findsOneWidget);
        expect(find.text('Add to library'), findsOneWidget);
        await tapAdd(tester);
        final entries = (await tester.runAsync(app.harness.store.entries))!;
        expect(
          entries.map((e) => e.sourceId),
          containsAll([ytPlaylistId(playlistOne), ytVideoId(videoA)]),
        );
      },
    );

    testWidgets('something already kept says so and offers Open', (
      tester,
    ) async {
      final api = scriptedApi();
      final app = await openImport(tester, api);
      await enterLink(tester, listOne);
      await tapAdd(tester);

      await pumpImport(tester, app, api);
      await enterLink(tester, listOne);

      expect(find.byKey(const ValueKey('import_already')), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });
  });

  group('calm failures', () {
    testWidgets('an unavailable video is one plain sentence', (tester) async {
      final api = scriptedApi()
        ..failure = PlatformException(
          code: 'private',
          message: 'SECRET extractor detail',
        );
      await openImport(tester, api);
      await enterLink(tester, watchA);

      expect(find.byKey(const ValueKey('import_failure')), findsOneWidget);
      expect(find.textContaining("isn't available right now"), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.byKey(const ValueKey('import_preview')), findsNothing);
      expect(find.byKey(const ValueKey('import_add')), findsNothing);
    });

    testWidgets('no network says to check the connection', (tester) async {
      final api = scriptedApi()
        ..failure = PlatformException(code: 'network', message: 'dns');
      await openImport(tester, api);
      await enterLink(tester, listOne);

      expect(find.textContaining('Check your connection'), findsOneWidget);
      expect(find.textContaining('dns'), findsNothing);
    });

    testWidgets('an empty playlist is gentle, and a good link follows', (
      tester,
    ) async {
      final api = scriptedApi();
      api.playlists[playlistTwo] = playlist([]);
      await openImport(tester, api);

      await enterLink(
        tester,
        'https://www.youtube.com/playlist?list=$playlistTwo',
      );
      expect(find.byKey(const ValueKey('import_failure')), findsOneWidget);
      expect(find.byKey(const ValueKey('import_preview')), findsNothing);

      await enterLink(tester, watchA);
      expect(find.byKey(const ValueKey('import_failure')), findsNothing);
      expect(find.text('A quiet sit'), findsOneWidget);
    });
  });
}
