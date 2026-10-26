import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/import_service.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:medito/services/youtube/youtube_source.dart';

import '../../helpers/library_fixtures.dart';
import '../../helpers/youtube_fake.dart';

const feedUrl = 'https://example.org/evening.rss';

const single = ImportChoice(
  kind: LibraryKind.single,
  group: LibraryGroup.practice,
);

/// "Single" is picking one episode from the list, with the latest ready.
void main() {
  group('a feed', () {
    late LibraryHarness h;

    setUp(() {
      h = LibraryHarness.create(
        routes: {feedUrl: xmlResponse(libraryFixture('rss_podcast.xml'))},
      );
    });

    tearDown(() => h.dispose());

    test('offers its episodes newest first, with the latest chosen', () async {
      final preview = await h.service.resolve(feedUrl);

      expect(preview.episodes.map((e) => e.id), ['ep-3', 'ep-2', 'ep-1']);
      expect(preview.episodes.first.title, 'Third sit: open awareness');
      expect(preview.episodes.first.durationMs, 3723000);
      expect(preview.episodes.first.publishedAt, DateTime.utc(2025, 6, 10, 4));
      expect(preview.episodes.last.durationMs, isNull);
      expect(preview.defaultEpisodeId, 'ep-3');
      expect(preview.hasEpisodeChoice, isTrue);
      expect(preview.episode(null)!.id, 'ep-3');
      expect(preview.episode('ep-1')!.title, 'First sit: arriving');
    });

    test('Single with no pick adds the latest, as before', () async {
      final preview = await h.service.resolve(feedUrl);
      final result = await h.service.add(preview, single);

      expect(result.kind, LibraryKind.single);
      expect(result.entryId, libEpisodeId(feedUrl, 'ep-3'));
      expect((await h.store.entry(result.entryId))!.title, contains('Third'));
    });

    test('Single adds the episode that was picked', () async {
      final preview = await h.service.resolve(feedUrl);
      final result = await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
          episodeId: 'ep-2',
        ),
      );

      expect(result.entryId, libEpisodeId(feedUrl, 'ep-2'));
      final entry = (await h.store.entry(result.entryId))!;
      expect(entry.kind, LibraryKind.single);
      expect(entry.title, 'Second sit: the breath');
      expect(await h.db.allCourses(), isEmpty);
      expect(await h.db.allTracks(), hasLength(1));
    });

    test('a single keeps the feed\'s credit', () async {
      final preview = await h.service.resolve(feedUrl);
      final result = await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
          episodeId: 'ep-2',
        ),
      );
      final track = await h.lib.track(result.entryId);
      expect(track.attribution!.creator, 'Example Sangha');
      expect(track.attribution!.url, 'https://example.org/evening');
      expect(track.attribution!.source, 'example.org');
    });

    test('adding the same episode again finds the first', () async {
      final preview = await h.service.resolve(feedUrl);
      const pick = ImportChoice(
        kind: LibraryKind.single,
        group: LibraryGroup.practice,
        episodeId: 'ep-1',
      );
      final first = await h.service.add(preview, pick);
      final again = await h.service.add(preview, pick);

      expect(again.alreadyPresent, isTrue);
      expect(again.entryId, first.entryId);
      expect(await h.store.entries(), hasLength(1));
    });

    test('an episode has one ID alone or inside the course', () async {
      final preview = await h.service.resolve(feedUrl);
      final alone = await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
          episodeId: 'ep-1',
        ),
      );
      await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.course,
          group: LibraryGroup.practice,
        ),
      );

      expect(await h.db.allTracks(), hasLength(3));
      expect(
        (await h.db.trackById(alone.entryId))!.courseId,
        preview.entryId,
        reason: 'the same track joined the course',
      );
    });

    test('a pick the feed no longer has falls back to the latest', () async {
      final preview = await h.service.resolve(feedUrl);
      final result = await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
          episodeId: 'ep-gone',
        ),
      );
      expect(result.entryId, libEpisodeId(feedUrl, 'ep-3'));
    });

    test('selectedId says what the choices would add', () async {
      final preview = await h.service.resolve(feedUrl);

      expect(
        ImportService.selectedId(preview, LibraryKind.course),
        preview.entryId,
      );
      expect(
        ImportService.selectedId(preview, LibraryKind.single),
        libEpisodeId(feedUrl, 'ep-3'),
      );
      expect(
        ImportService.selectedId(
          preview,
          LibraryKind.single,
          episodeId: 'ep-1',
        ),
        libEpisodeId(feedUrl, 'ep-1'),
      );
      await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
          episodeId: 'ep-1',
        ),
      );
      expect(
        await h.store.contains(
          ImportService.selectedId(
            preview,
            LibraryKind.single,
            episodeId: 'ep-1',
          ),
        ),
        isTrue,
      );
      expect(
        await h.store.contains(
          ImportService.selectedId(preview, LibraryKind.single),
        ),
        isFalse,
      );
    });
  });

  group('YouTube', () {
    late LibraryDatabase db;
    late LibraryStore store;
    late FakeYoutubeApi api;
    late YoutubeSource source;

    const listUrl = 'https://www.youtube.com/playlist?list=$playlistOne';
    const watchA = 'https://www.youtube.com/watch?v=$videoA';

    setUp(() {
      db = memoryLibraryDb();
      store = LibraryStore(db);
      api = FakeYoutubeApi()
        ..videos[videoA] = video(videoA, title: 'First sit')
        ..videos[videoB] = video(videoB, title: 'Second sit')
        ..playlists[playlistOne] = playlist([
          item(videoA, title: 'First sit', seconds: 600),
          item(videoB, title: 'Second sit', seconds: 1200),
          item(videoC, title: 'Third sit', seconds: 900),
          item(videoA, title: 'First sit', seconds: 600),
        ]);
      source = YoutubeSource(db: db, library: store, api: api);
    });

    tearDown(() => db.close());

    Future<ImportPreview> previewOf(String url) =>
        source.preview(Uri.parse(url));

    test('a playlist now offers Single, from its own list', () async {
      final preview = await previewOf(listUrl);

      expect(preview.allowedKinds, {LibraryKind.course, LibraryKind.single});
      expect(preview.episodes.map((e) => e.id), [videoA, videoB, videoC]);
      expect(preview.episodes[1].durationMs, 1200000);
      expect(preview.defaultEpisodeId, videoA, reason: 'the top of the list');
      expect(preview.itemCount, 4, reason: 'the course keeps every row');
    });

    test('a watch link in a list starts on the video in the link', () async {
      final preview = await previewOf(
        '${watchA.replaceFirst(videoA, videoB)}'
        '&list=$playlistOne',
      );

      expect(preview.kind, LibraryKind.course);
      expect(preview.defaultEpisodeId, videoB);
    });

    test('a plain video has just itself to pick', () async {
      final preview = await previewOf(watchA);

      expect(preview.kind, LibraryKind.single);
      expect(preview.episodes.single.id, videoA);
      expect(preview.hasEpisodeChoice, isFalse);
    });

    test('Single from a playlist adds the video picked', () async {
      final preview = await previewOf(listUrl);
      final result = await source.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
          episodeId: videoC,
        ),
      );

      expect(result.kind, LibraryKind.single);
      expect(result.entryId, ytVideoId(videoC));
      final entry = (await store.entry(result.entryId))!;
      expect(entry.title, 'Third sit');
      expect(entry.durationMs, 900000);
      expect(await store.contains(ytPlaylistId(playlistOne)), isFalse);
      expect(await db.youtubeVideo(videoC), isNotNull);
    });

    test('with no pick, Single from a playlist adds its first video', () async {
      final preview = await previewOf(listUrl);
      final result = await source.add(preview, single);
      expect(result.entryId, ytVideoId(videoA));
    });

    test('a watch link in a list adds the linked video, or another', () async {
      final preview = await previewOf('$watchA&list=$playlistOne');
      final linked = await source.add(preview, single);
      expect(linked.entryId, ytVideoId(videoA));

      final other = await source.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
          episodeId: videoB,
        ),
      );
      expect(other.entryId, ytVideoId(videoB));
      expect(other.alreadyPresent, isFalse);
    });

    test('adding the same video again finds the first', () async {
      final preview = await previewOf(listUrl);
      const pick = ImportChoice(
        kind: LibraryKind.single,
        group: LibraryGroup.practice,
        episodeId: videoB,
      );
      await source.add(preview, pick);
      final again = await source.add(preview, pick);

      expect(again.alreadyPresent, isTrue);
      expect(await store.entries(), hasLength(1));
    });

    test('selectedId follows the pick', () async {
      final preview = await previewOf(listUrl);

      expect(
        ImportService.selectedId(preview, LibraryKind.course),
        ytPlaylistId(playlistOne),
      );
      expect(
        ImportService.selectedId(preview, LibraryKind.single),
        ytVideoId(videoA),
      );
      expect(
        ImportService.selectedId(
          preview,
          LibraryKind.single,
          episodeId: videoC,
        ),
        ytVideoId(videoC),
      );
    });
  });
}
