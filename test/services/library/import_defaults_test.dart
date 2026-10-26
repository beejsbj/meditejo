import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:medito/services/library/import_defaults.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/youtube/youtube_source.dart';

import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/library_fixtures.dart';
import '../../helpers/youtube_fake.dart';

const _feedUrl = 'https://example.org/evening.rss';
const _audioUrl = 'https://example.org/files/body-scan.mp3';

/// One test per kind of link or pick: what it arrives as, and what else Add
/// allows. The table (`importDefaults`) is the single source; these tests
/// check that every resolver follows it, so a list is never silently a Single.
void main() {
  late LibraryHarness h;

  tearDown(() => h.dispose());

  void expectFollowsTable(ImportPreview preview, ImportShape shape) {
    expect(
      preview.kind,
      importDefaults[shape]!.kind,
      reason: '$shape arrives as ${importDefaults[shape]!.kind}',
    );
    expect(preview.allowedKinds, importDefaults[shape]!.allowed);
    expect(
      preview.allowedKinds,
      contains(preview.kind),
      reason: 'the default must be one of the choices',
    );
  }

  group('the table', () {
    setUp(() => h = LibraryHarness.create());

    test('has a row for every kind of link and pick', () {
      expect(importDefaults.keys.toSet(), ImportShape.values.toSet());
    });

    test('every list is a Course by default; one recording is a Single', () {
      const lists = {
        ImportShape.feed,
        ImportShape.youtubePlaylist,
        ImportShape.youtubeWatchWithPlaylist,
        ImportShape.dharmaSeedRetreat,
        ImportShape.localFolder,
        ImportShape.localFiles,
      };
      const recordings = {
        ImportShape.youtubeVideo,
        ImportShape.dharmaSeedTalk,
        ImportShape.audioUrl,
        ImportShape.localFile,
      };
      expect(lists.union(recordings), ImportShape.values.toSet());
      for (final shape in lists) {
        expect(shape.defaultKind, LibraryKind.course, reason: '$shape');
      }
      for (final shape in recordings) {
        expect(shape.defaultKind, LibraryKind.single, reason: '$shape');
      }
    });

    test('a default is always one of its choices', () {
      for (final shape in ImportShape.values) {
        expect(shape.allowedKinds, contains(shape.defaultKind));
      }
    });
  });

  group('feeds', () {
    setUp(() {
      h = LibraryHarness.create(
        routes: {_feedUrl: xmlResponse(libraryFixture('rss_podcast.xml'))},
      );
    });

    test('an RSS feed arrives as the whole list, a Course', () async {
      expectFollowsTable(await h.service.resolve(_feedUrl), ImportShape.feed);
    });

    test('so does a page that points at a feed', () async {
      h = LibraryHarness.create(
        routes: {
          'https://example.org/': htmlResponse(
            libraryFixture('page_with_feed.html'),
          ),
          'https://example.org/feeds/evening.rss': xmlResponse(
            libraryFixture('rss_podcast.xml'),
          ),
        },
      );
      expectFollowsTable(
        await h.service.resolve('https://example.org/'),
        ImportShape.feed,
      );
    });
  });

  group('one recording', () {
    test('an audio URL stays a Single', () async {
      h = LibraryHarness.create(routes: {_audioUrl: audioResponse()});
      expectFollowsTable(
        await h.service.resolve(_audioUrl),
        ImportShape.audioUrl,
      );
    });

    test('one local file stays a Single', () async {
      h = LibraryHarness.create();
      final file = h.writeAudio('Metta.mp3');
      expectFollowsTable(
        await h.service.resolveFiles([PickedFile(path: file.path)]),
        ImportShape.localFile,
      );
    });
  });

  group('Dharma Seed', () {
    setUp(() {
      final api = FakeDharmaSeedApi();
      final ds = memoryDharmaSeedDb();
      addTearDown(ds.close);
      h = LibraryHarness.create(
        dharmaSeed: (store) => DharmaSeedSource(
          db: ds,
          library: store,
          sync: DharmaSeedSync(
            db: ds,
            client: api.client(),
            sleep: (_) async {},
          ),
        ),
      );
    });

    test('a retreat arrives as a Course', () async {
      expectFollowsTable(
        await h.service.resolve('https://dharmaseed.org/retreats/6689/'),
        ImportShape.dharmaSeedRetreat,
      );
    });

    test('a talk stays a Single', () async {
      expectFollowsTable(
        await h.service.resolve('https://www.dharmaseed.org/talks/99944/'),
        ImportShape.dharmaSeedTalk,
      );
    });

    test('a teacher is a person to follow, not a list to play', () async {
      final preview = await h.service.resolve(
        'https://dharmaseed.org/teacher/637/',
      );
      expect(preview.kind, LibraryKind.teacher);
      expect(preview.allowedKinds, {LibraryKind.teacher});
    });
  });

  group('local folders and files', () {
    setUp(() => h = LibraryHarness.create());

    test('several picked files arrive as a Course', () async {
      final a = h.writeAudio('01 arrive.mp3');
      final b = h.writeAudio('02 settle.mp3');
      expectFollowsTable(
        await h.service.resolveFiles([
          PickedFile(path: a.path),
          PickedFile(path: b.path),
        ]),
        ImportShape.localFiles,
      );
    });

    test('a folder read by path arrives as a Course', () async {
      h.writeAudio('Session 1.mp3');
      h.writeAudio('Session 2.mp3');
      expectFollowsTable(
        await h.service.resolve('${h.storage.path}/inbox'),
        ImportShape.localFolder,
      );
    });

    test('a folder copied in by the Android picker is a Course', () async {
      final a = h.writeAudio('Session 1.mp3');
      final b = h.writeAudio('Session 2.mp3');
      final preview = await h.service.resolveFiles(
        [PickedFile(path: a.path), PickedFile(path: b.path)],
        suggestedTitle: 'Retreat',
        folder: true,
        unreadable: 2,
      );
      expectFollowsTable(preview, ImportShape.localFolder);
      expect(preview.title, 'Retreat');
      expect(preview.unreadableItems, 2);
    });

    test('a folder holding one file is that file, a Single', () async {
      final only = h.writeAudio('Only.mp3');
      expectFollowsTable(
        await h.service.resolveFiles(
          [PickedFile(path: only.path)],
          suggestedTitle: 'Folder',
          folder: true,
        ),
        ImportShape.localFile,
      );
    });
  });

  group('YouTube', () {
    late LibraryDatabase db;
    late FakeYoutubeApi api;
    late YoutubeSource source;

    setUp(() {
      h = LibraryHarness.create();
      db = memoryLibraryDb();
      api = FakeYoutubeApi()
        ..videos[videoA] = video(videoA)
        ..playlists[playlistOne] = playlist([item(videoA), item(videoB)]);
      source = YoutubeSource(db: db, library: LibraryStore(db), api: api);
    });

    tearDown(() => db.close());

    Future<ImportPreview> preview(String url) => source.preview(Uri.parse(url));

    test('a playlist link arrives as the whole list, a Course', () async {
      expectFollowsTable(
        await preview('https://www.youtube.com/playlist?list=$playlistOne'),
        ImportShape.youtubePlaylist,
      );
    });

    test('a watch link that carries a playlist arrives as the list', () async {
      expectFollowsTable(
        await preview(
          'https://www.youtube.com/watch?v=$videoA&list=$playlistOne',
        ),
        ImportShape.youtubeWatchWithPlaylist,
      );
    });

    test('a plain watch link stays a Single', () async {
      expectFollowsTable(
        await preview('https://www.youtube.com/watch?v=$videoA'),
        ImportShape.youtubeVideo,
      );
    });
  });
}
