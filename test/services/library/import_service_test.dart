import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/local_catalogue.dart';

import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/library_fixtures.dart';

const feedUrl = 'https://example.org/evening.rss';

Future<ImportFailureReason> failureOf(Future<Object?> Function() run) async {
  try {
    await run();
  } on ImportFailure catch (e) {
    return e.reason;
  }
  fail('expected an ImportFailure');
}

void main() {
  late LibraryHarness h;

  tearDown(() => h.dispose());

  group('feeds', () {
    setUp(() {
      h = LibraryHarness.create(
        routes: {
          feedUrl: xmlResponse(
            libraryFixture('rss_podcast.xml'),
            headers: {
              'etag': '"v1"',
              'last-modified': 'Tue, 10 Jun 2025 04:00:00 GMT',
            },
          ),
        },
      );
    });

    test('a feed link previews as a course, one request', () async {
      final preview = await h.service.resolve(feedUrl);

      expect(h.web.urls, [feedUrl]);
      expect(h.web.requests.single.headers['User-Agent'], contains('Meditejo'));
      expect(preview.origin, ImportOrigin.feed);
      expect(preview.kind, LibraryKind.course);
      expect(preview.allowedKinds, {LibraryKind.course, LibraryKind.single});
      expect(
        preview.group,
        LibraryGroup.practice,
        reason: 'unknown defaults to Practice',
      );
      expect(preview.title, 'Evening Sits');
      expect(preview.itemCount, 3);
      expect(preview.durationMs, (3723 + 1830) * 1000);
      expect(
        preview.durationComplete,
        isFalse,
        reason: 'one episode has no length',
      );
      expect(preview.firstItems.map((i) => i.title), [
        'First sit: arriving',
        'Second sit: the breath',
        'Third sit: open awareness',
      ]);
      expect(preview.artworkUrl, 'https://example.org/art/evening.jpg');
      expect(preview.attribution!.licenseName, 'CC BY-NC 4.0');
      expect(preview.attribution!.creator, 'Example Sangha');
      expect(preview.skippedItems, 2);
      expect(preview.alreadyInLibrary, isFalse);
      // Nothing was stored by looking.
      expect(await h.db.allCourses(), isEmpty);
      expect(await h.store.entries(), isEmpty);
    });

    test('shared text with a link inside works the same', () async {
      final preview = await h.service.resolve(
        'Evening Sits podcast $feedUrl — enjoy!',
      );
      expect(preview.title, 'Evening Sits');
    });

    test(
      'adding stores the course oldest first and puts it in the library',
      () async {
        final preview = await h.service.resolve(feedUrl);
        final result = await h.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.course,
            group: LibraryGroup.practice,
          ),
        );

        expect(result.entryId, preview.entryId);
        expect(result.kind, LibraryKind.course);
        expect(result.alreadyPresent, isFalse);

        final entry = (await h.store.entry(result.entryId))!;
        expect(entry.kind, LibraryKind.course);
        expect(entry.itemCount, 3);
        expect(entry.group, LibraryGroup.practice);

        // The library's content source serves it through the shared models.
        final pack = await h.lib.pack(result.entryId);
        expect(pack.items.map((i) => i.title), [
          'First sit: arriving',
          'Second sit: the breath',
          'Third sit: open awareness',
        ]);
        expect(pack.items.every((i) => i.path == '/tracks/${i.id}'), isTrue);
        expect(pack.attribution!.licenseName, 'CC BY-NC 4.0');

        final track = await h.lib.track(pack.items.last.id);
        expect(
          track.voices.single.audioFiles.single.path,
          'https://cdn.example.org/ep3.mp3',
        );
        expect(track.voices.single.audioFiles.single.duration, 3723000);
        expect(
          track.hasBackgroundSound,
          isTrue,
          reason: 'practice allows a background sound',
        );
        expect(track.attribution!.source, 'example.org');

        // The caching validators are kept for the next refresh.
        final course = (await h.db.courseById(result.entryId))!;
        expect(course.etag, '"v1"');
        expect(course.lastModified, 'Tue, 10 Jun 2025 04:00:00 GMT');
        expect(course.episodeOrder, 'oldest');
      },
    );

    test(
      'newest-first is a setting, and talks drop the background sound',
      () async {
        final preview = await h.service.resolve(feedUrl);
        final result = await h.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.course,
            group: LibraryGroup.talks,
            episodeOrder: 'newest',
          ),
        );
        final pack = await h.lib.pack(result.entryId);
        expect(pack.items.first.title, 'Third sit: open awareness');
        final track = await h.lib.track(pack.items.first.id);
        expect(track.hasBackgroundSound, isFalse);
      },
    );

    test('adding twice changes nothing and says so', () async {
      final preview = await h.service.resolve(feedUrl);
      const choice = ImportChoice(
        kind: LibraryKind.course,
        group: LibraryGroup.practice,
      );
      await h.service.add(preview, choice);
      final again = await h.service.add(preview, choice);
      expect(again.alreadyPresent, isTrue);
      expect(await h.store.entries(), hasLength(1));
      expect(await h.db.allTracks(), hasLength(3));
      expect((await h.service.resolve(feedUrl)).alreadyInLibrary, isTrue);
    });

    test('the latest episode can be added as a single', () async {
      final preview = await h.service.resolve(feedUrl);
      final result = await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
        ),
      );
      expect(result.kind, LibraryKind.single);
      final entry = (await h.store.entry(result.entryId))!;
      expect(entry.kind, LibraryKind.single);
      expect(entry.title, 'Third sit: open awareness');
      expect(await h.db.allCourses(), isEmpty);
      expect((await h.db.trackById(result.entryId))!.courseId, isNull);
      // The same episode keeps one ID whether it came alone or in the course.
      await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.course,
          group: LibraryGroup.practice,
        ),
      );
      expect(await h.db.allTracks(), hasLength(3));
      expect((await h.db.trackById(result.entryId))!.courseId, preview.entryId);
    });

    test('a typed title is kept in the library only', () async {
      final preview = await h.service.resolve(feedUrl);
      final result = await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.course,
          group: LibraryGroup.practice,
          title: 'My evenings',
        ),
      );
      final entry = (await h.store.entry(result.entryId))!;
      expect(entry.displayTitle, 'My evenings');
      expect(entry.title, 'Evening Sits');
    });

    test('removing deletes the course, its sessions and positions', () async {
      final preview = await h.service.resolve(feedUrl);
      final result = await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.course,
          group: LibraryGroup.practice,
        ),
      );
      final first = (await h.lib.pack(result.entryId)).items.first.id;
      await h.store.savePosition(first, 60000, 600000);

      await h.lib.setSaved(result.entryId, saved: false);

      expect(await h.store.entries(), isEmpty);
      expect(await h.db.allCourses(), isEmpty);
      expect(await h.db.allTracks(), isEmpty);
      expect(await h.store.resumePoint(first), isNull);
      await expectLater(
        h.lib.pack(result.entryId),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
    });
  });

  group('finding a feed', () {
    test('a web page that advertises one leads to it (two requests)', () async {
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
      final preview = await h.service.resolve('https://example.org/');
      expect(h.web.urls, [
        'https://example.org/',
        'https://example.org/feeds/evening.rss',
      ]);
      expect(preview.title, 'Evening Sits');
      expect(preview.feedUrl, 'https://example.org/feeds/evening.rss');
    });

    test('an Apple Podcasts link is looked up, then read', () async {
      h = LibraryHarness.create(
        routes: {
          'https://itunes.apple.com/lookup?id=1234567&entity=podcast':
              http.Response(
                libraryFixture('apple_lookup.json'),
                200,
                headers: {'content-type': 'application/json'},
              ),
          feedUrl: xmlResponse(libraryFixture('rss_podcast.xml')),
        },
      );
      final preview = await h.service.resolve(
        'https://podcasts.apple.com/us/podcast/evening-sits/id1234567',
      );
      expect(preview.title, 'Evening Sits');
      expect(h.web.requests, hasLength(2));
    });

    test('an Atom feed previews like any other', () async {
      h = LibraryHarness.create(
        routes: {
          'https://example.net/feed.atom': xmlResponse(
            libraryFixture('atom_feed.xml'),
          ),
        },
      );
      final preview = await h.service.resolve('https://example.net/feed.atom');
      expect(preview.title, 'Dhamma Notes');
      expect(preview.itemCount, 2);
      expect(preview.attribution!.licenseName, 'CC BY-NC-ND 3.0');
    });

    test('a known talks site defaults to Talks', () async {
      h = LibraryHarness.create(
        routes: {
          'https://www.dhammatalks.org/feed.xml': xmlResponse(
            libraryFixture('rss_podcast.xml'),
          ),
        },
      );
      final preview = await h.service.resolve(
        'https://www.dhammatalks.org/feed.xml',
      );
      expect(preview.group, LibraryGroup.talks);
    });
  });

  group('audio URLs', () {
    test(
      'a direct link becomes a single, with one request that reads no body',
      () async {
        h = LibraryHarness.create(
          routes: {
            'https://example.org/files/body-scan_20min.mp3': audioResponse(),
          },
          probe: (url) async => url.endsWith('.mp3') ? 1200000 : null,
        );
        final preview = await h.service.resolve(
          'https://example.org/files/body-scan_20min.mp3',
        );
        expect(h.web.requests, hasLength(1));
        expect(preview.origin, ImportOrigin.audioUrl);
        expect(preview.kind, LibraryKind.single);
        expect(preview.hasKindChoice, isFalse);
        expect(preview.title, 'body scan 20min');
        expect(preview.durationMs, 1200000);
        expect(preview.durationComplete, isTrue);
        expect(preview.group, LibraryGroup.practice);

        final result = await h.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.single,
            group: LibraryGroup.practice,
          ),
        );
        final track = await h.lib.track(result.entryId);
        expect(
          track.voices.single.audioFiles.single.path,
          'https://example.org/files/body-scan_20min.mp3',
        );
        expect(track.attribution!.source, 'example.org');
        expect((await h.store.entry(result.entryId))!.kind, LibraryKind.single);
      },
    );

    test(
      'a page URL that is really audio is found by its content type',
      () async {
        h = LibraryHarness.create(
          routes: {'https://example.org/listen/42': audioResponse()},
        );
        final preview = await h.service.resolve(
          'https://example.org/listen/42',
        );
        expect(preview.origin, ImportOrigin.audioUrl);
      },
    );
  });

  group('calm failures', () {
    setUp(
      () => h = LibraryHarness.create(
        routes: {
          'https://example.org/gone': http.Response('', 404),
          'https://example.org/boom': http.Response('', 500),
          'https://example.org/plain': htmlResponse(
            libraryFixture('page_plain.html'),
          ),
          'https://example.org/broken.xml': xmlResponse(
            '<rss><channel><title>x</title>',
          ),
          'https://example.org/empty.xml': xmlResponse(
            '<rss><channel><title>T</title></channel></rss>',
          ),
        },
      ),
    );

    test('YouTube says it is coming, without any request', () async {
      expect(
        await failureOf(() => h.service.resolve('https://youtu.be/abc')),
        ImportFailureReason.youtube,
      );
      expect(h.web.requests, isEmpty);
    });

    test('Spotify and rubbish are named, not crashed on', () async {
      expect(
        await failureOf(
          () => h.service.resolve('https://open.spotify.com/show/x'),
        ),
        ImportFailureReason.unsupportedHost,
      );
      expect(
        await failureOf(() => h.service.resolve('hello there')),
        ImportFailureReason.unrecognised,
      );
      expect(
        await failureOf(() => h.service.resolve('   ')),
        ImportFailureReason.empty,
      );
      expect(h.web.requests, isEmpty);
    });

    test('a missing page, a server error and a page with no feed', () async {
      expect(
        await failureOf(() => h.service.resolve('https://example.org/gone')),
        ImportFailureReason.notFound,
      );
      expect(
        await failureOf(() => h.service.resolve('https://example.org/boom')),
        ImportFailureReason.unreachable,
      );
      expect(
        await failureOf(() => h.service.resolve('https://example.org/plain')),
        ImportFailureReason.noFeedOrAudio,
      );
    });

    test('a feed that will not parse or has no audio', () async {
      expect(
        await failureOf(
          () => h.service.resolve('https://example.org/broken.xml'),
        ),
        ImportFailureReason.brokenFeed,
      );
      expect(
        await failureOf(
          () => h.service.resolve('https://example.org/empty.xml'),
        ),
        ImportFailureReason.noEpisodes,
      );
    });

    test('no connection is offline', () async {
      final offline = LibraryHarness.create(offline: true);
      addTearDown(offline.dispose);
      expect(
        await failureOf(
          () => offline.service.resolve('https://example.org/feed.xml'),
        ),
        ImportFailureReason.offline,
      );
    });
  });

  group('local files', () {
    setUp(
      () => h = LibraryHarness.create(
        probe: (path) async => path.endsWith('b.mp3') ? 90000 : 60000,
      ),
    );

    test('one file is copied into app storage as a single', () async {
      final source = h.writeAudio('Metta Practice.mp3');
      final preview = await h.service.resolve(source.path);

      expect(preview.origin, ImportOrigin.localFiles);
      expect(preview.kind, LibraryKind.single);
      expect(preview.title, 'Metta Practice');
      expect(preview.sourceLabel, 'This device');
      expect(preview.durationMs, 60000);
      expect(h.web.requests, isEmpty);

      final result = await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
        ),
      );
      final row = (await h.db.trackById(result.entryId))!;
      expect(row.isLocalFile, isTrue);
      expect(row.audioUrl, startsWith('${h.storage.path}/library/lib-track-'));
      expect(
        File(row.audioUrl).readAsStringSync(),
        'ID3 fake audio',
        reason: 'audio is copied untouched',
      );
      expect(
        source.existsSync(),
        isTrue,
        reason: 'a file the user pointed at is left alone',
      );

      // Removing deletes the copy.
      await h.lib.setSaved(result.entryId, saved: false);
      expect(File(row.audioUrl).existsSync(), isFalse);
    });

    test('a picker cache file is moved, not duplicated', () async {
      final cached = File('${h.storage.path}/cache/file_picker/a.mp3')
        ..createSync(recursive: true);
      cached.writeAsStringSync('audio');
      final preview = await h.service.resolveFiles([
        PickedFile(path: cached.path, name: 'a.mp3'),
      ]);
      await h.service.add(
        preview,
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
        ),
      );
      expect(cached.existsSync(), isFalse);
      expect(Directory('${h.storage.path}/library').listSync(), hasLength(1));
    });

    test(
      'a failure part-way leaves the cache copies and stores nothing',
      () async {
        final cacheDir = Directory('${h.storage.path}/cache/file_picker')
          ..createSync(recursive: true);
        final first = File('${cacheDir.path}/01.mp3')..writeAsStringSync('one');
        final second = File('${cacheDir.path}/02.mp3')
          ..writeAsStringSync('two');
        final preview = await h.service.resolveFiles([
          PickedFile(path: first.path),
          PickedFile(path: second.path),
        ]);
        second.deleteSync(); // vanishes between the preview and Add
        const choice = ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
        );

        await expectLater(h.service.add(preview, choice), throwsA(anything));
        expect(first.existsSync(), isTrue, reason: 'the original is kept');
        expect(await h.store.entries(), isEmpty);
        final library = Directory('${h.storage.path}/library');
        expect(
          library.existsSync()
              ? library.listSync()
              : const <FileSystemEntity>[],
          isEmpty,
          reason: 'no stranded copy',
        );

        // Once the cause is gone the same preview adds cleanly.
        second.writeAsStringSync('two');
        await h.service.add(preview, choice);
        expect(await h.store.entries(), hasLength(2));
        expect(first.existsSync(), isFalse);
        expect(second.existsSync(), isFalse);
      },
    );

    test(
      'several files become a course in the order given, or separate singles',
      () async {
        final a = h.writeAudio('01 arrive.mp3');
        final b = h.writeAudio(
          '02 settle b.mp3',
        ); // probe sees "b.mp3"? no: ends with " b.mp3"
        final preview = await h.service.resolveFiles([
          PickedFile(path: a.path),
          PickedFile(path: b.path),
        ], suggestedTitle: 'Retreat audio');
        expect(preview.kind, LibraryKind.course);
        expect(preview.allowedKinds, {LibraryKind.course, LibraryKind.single});
        expect(preview.title, 'Retreat audio');
        expect(preview.itemCount, 2);
        expect(preview.durationMs, 150000);

        final course = await h.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.course,
            group: LibraryGroup.practice,
          ),
        );
        final pack = await h.lib.pack(course.entryId);
        expect(pack.items.map((i) => i.title), ['01 arrive', '02 settle b']);
        expect(pack.attribution!.source, 'This device');
        expect((await h.store.entry(course.entryId))!.title, 'Retreat audio');

        final singles = await h.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.single,
            group: LibraryGroup.talks,
          ),
        );
        expect(singles.addedCount, 2);
        final entries = await h.store.entries();
        expect(
          entries.where((e) => e.kind == LibraryKind.single),
          hasLength(2),
        );
        expect(
          entries
              .where((e) => e.kind == LibraryKind.single)
              .every((e) => e.group == LibraryGroup.talks),
          isTrue,
        );
      },
    );

    test(
      'a folder becomes a course, files in natural order, other files ignored',
      () async {
        h.writeAudio('Session 10.mp3');
        h.writeAudio('Session 2.mp3');
        h.writeAudio('notes.txt');
        final preview = await h.service.resolve('${h.storage.path}/inbox');
        expect(preview.kind, LibraryKind.course);
        expect(preview.firstItems.map((i) => i.title), [
          'Session 2',
          'Session 10',
        ]);
        expect(preview.title, 'inbox');
      },
    );

    test('files that are missing or not audio fail plainly', () async {
      expect(
        await failureOf(() => h.service.resolve('/no/such/file.mp3')),
        ImportFailureReason.fileMissing,
      );
      final text = h.writeAudio('notes.txt');
      expect(
        await failureOf(
          () => h.service.resolveFiles([PickedFile(path: text.path)]),
        ),
        ImportFailureReason.noAudioFiles,
      );
      expect(
        await failureOf(() => h.service.resolveFiles(const [])),
        ImportFailureReason.noAudioFiles,
      );
    });
  });

  group('Dharma Seed links', () {
    late FakeDharmaSeedApi api;

    setUp(() {
      api = FakeDharmaSeedApi();
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

    test(
      'a retreat URL resolves to the ds- course, fetched on demand',
      () async {
        final preview = await h.service.resolve(
          'https://dharmaseed.org/retreats/6689/',
        );
        expect(preview.origin, ImportOrigin.dharmaSeed);
        expect(preview.entryId, 'ds-retreat-6689');
        expect(preview.kind, LibraryKind.course);
        expect(preview.title, 'Auckland Insight Meditation meetings 2026');
        expect(preview.sourceLabel, 'Dharma Seed');
        expect(preview.itemCount, 7);
        expect(preview.attribution!.licenseName, 'CC BY-NC-ND 4.0');
        expect(preview.firstItems, isNotEmpty);
        expect(
          preview.group,
          LibraryGroup.practice,
          reason: 'a retreat is practice even when its recordings are "Talk"',
        );
        expect(api.requests, isNotEmpty);
        expect(
          h.web.requests,
          isEmpty,
          reason: 'only the Dharma Seed API was used',
        );

        final result = await h.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.course,
            group: LibraryGroup.talks,
          ),
        );
        expect(result.entryId, 'ds-retreat-6689');
        final entry = (await h.store.entry('ds-retreat-6689'))!;
        expect(
          entry.group,
          LibraryGroup.talks,
          reason: 'the user overrode the detected group',
        );
        expect(entry.detectedGroup, LibraryGroup.practice);
        expect(entry.itemCount, 7);
      },
    );

    test(
      'a talk URL becomes a single; the teacher URL a teacher entry',
      () async {
        final talk = await h.service.resolve(
          'https://www.dharmaseed.org/talks/99944/',
        );
        expect(talk.entryId, 'ds-talk-99944');
        expect(talk.kind, LibraryKind.single);
        await h.service.add(
          talk,
          ImportChoice(kind: talk.kind, group: talk.group),
        );
        expect(
          (await h.store.entry('ds-talk-99944'))!.kind,
          LibraryKind.single,
        );

        final teacher = await h.service.resolve(
          'https://dharmaseed.org/teacher/637/',
        );
        expect(teacher.entryId, 'ds-teacher-637');
        expect(teacher.kind, LibraryKind.teacher);
        await h.service.add(
          teacher,
          ImportChoice(kind: teacher.kind, group: teacher.group),
        );
        expect(
          (await h.store.entry('ds-teacher-637'))!.kind,
          LibraryKind.teacher,
        );
      },
    );

    test('an ID Dharma Seed does not have is a plain failure', () async {
      expect(
        await failureOf(
          () => h.service.resolve('https://dharmaseed.org/talks/1/'),
        ),
        ImportFailureReason.dharmaSeedMissing,
      );
      expect(
        await failureOf(
          () => h.service.resolve('https://dharmaseed.org/retreats/1/'),
        ),
        ImportFailureReason.dharmaSeedMissing,
      );
    });
  });

  group('IDs', () {
    test('the same address always has the same ID; files get fresh ones', () {
      expect(libCourseIdFor(feedUrl), libCourseIdFor(feedUrl));
      expect(libCourseIdFor(feedUrl), startsWith('lib-course-'));
      expect(libTrackIdFor('a'), isNot(libTrackIdFor('b')));
      expect(
        libEpisodeId(feedUrl, 'ep-1'),
        isNot(libEpisodeId(feedUrl, 'ep-2')),
      );
      expect(newLibTrackId(), isNot(newLibTrackId()));
      expect(isLibTrackId(newLibTrackId()), isTrue);
      expect(isLibCourseId(newLibTrackId()), isFalse);
    });
  });
}
