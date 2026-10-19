import 'package:medito/src/youtube_api.g.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:medito/services/youtube/youtube_source.dart';

import '../../helpers/library_fixtures.dart';
import '../../helpers/youtube_fake.dart';

const watchA = 'https://www.youtube.com/watch?v=$videoA';
const listOne = 'https://www.youtube.com/playlist?list=$playlistOne';
const unavailable = "This video isn't available right now";

Matcher failsWith(ImportFailureReason reason) =>
    throwsA(isA<ImportFailure>().having((e) => e.reason, 'reason', reason));

const practice = ImportChoice(
  kind: LibraryKind.course,
  group: LibraryGroup.practice,
);
const single = ImportChoice(
  kind: LibraryKind.single,
  group: LibraryGroup.practice,
);

void main() {
  late LibraryDatabase db;
  late LibraryStore store;
  late FakeYoutubeApi api;
  late TestClock clock;
  late YoutubeSource source;

  YoutubeSource newSource() =>
      YoutubeSource(db: db, library: store, api: api, clock: clock.call);

  setUp(() {
    db = memoryLibraryDb();
    store = LibraryStore(db);
    api = FakeYoutubeApi()
      ..videos[videoA] = video(videoA, description: 'Described.')
      ..videos[videoB] = video(videoB, title: 'Second sit')
      ..playlists[playlistOne] = playlist([
        item(videoA, title: 'First sit', seconds: 600),
        item(videoB, title: 'Second sit', seconds: 1200),
        item(videoA, title: 'First sit', seconds: 600),
      ])
      ..playlists[playlistTwo] = playlist([
        item(videoA),
        item(videoC),
      ], title: 'Other course');
    clock = TestClock();
    source = newSource();
  });

  tearDown(() => db.close());

  Future<ImportPreview> previewOf(String url) => source.preview(Uri.parse(url));

  Future<ImportResult> addCourse(
    String url, {
    ImportChoice choice = practice,
  }) async => source.add(await previewOf(url), choice);

  group('previewing', () {
    for (final url in [
      watchA,
      'https://youtu.be/$videoA',
      'https://m.youtube.com/watch?v=$videoA&t=30s',
      'https://www.youtube.com/shorts/$videoA',
    ]) {
      test('$url previews one video and asks for nothing else', () async {
        final preview = await previewOf(url);

        expect(api.videoCalls, [watchA], reason: 'normalised to a watch URL');
        expect(api.playlistCalls, isEmpty);
        expect(preview.origin, ImportOrigin.youtube);
        expect(preview.entryId, ytVideoId(videoA));
        expect(preview.kind, LibraryKind.single);
        expect(preview.allowedKinds, {LibraryKind.course, LibraryKind.single});
        expect(preview.title, 'A quiet sit');
        expect(preview.subtitle, 'Quiet Channel');
        expect(preview.itemCount, 1);
        expect(preview.durationMs, 600000);
        expect(preview.durationComplete, isTrue);
        expect(preview.description, 'Described.');
        expect(preview.attribution?.source, 'YouTube');
        expect(preview.attribution?.creator, 'Quiet Channel');
        expect(preview.attribution?.url, watchA);
      });
    }

    test('a playlist page previews the course and offers no Single', () async {
      final preview = await previewOf(listOne);

      expect(api.playlistCalls, [listOne]);
      expect(api.videoCalls, isEmpty);
      expect(preview.entryId, ytPlaylistId(playlistOne));
      expect(preview.kind, LibraryKind.course);
      expect(preview.allowedKinds, {LibraryKind.course});
      expect(preview.title, 'Evening Sits');
      expect(preview.subtitle, 'Quiet Channel');
      expect(preview.itemCount, 3, reason: 'repeats count');
      expect(preview.durationMs, 2400000);
      expect(preview.durationComplete, isTrue);
      expect(
        [for (final i in preview.firstItems) i.title],
        ['First sit', 'Second sit', 'First sit'],
      );
      expect(preview.attribution?.url, listOne);
    });

    test(
      'a watch link inside a list previews the course, offers both',
      () async {
        final preview = await previewOf('$watchA&list=$playlistOne');

        expect(api.videoCalls, [watchA]);
        expect(api.playlistCalls, [listOne]);
        expect(preview.entryId, ytPlaylistId(playlistOne));
        expect(preview.kind, LibraryKind.course);
        expect(preview.allowedKinds, {LibraryKind.course, LibraryKind.single});
        expect(preview.itemCount, 3);
      },
    );

    test('only the first five items are previewed', () async {
      api.playlists[playlistOne] = playlist([
        for (var i = 0; i < 8; i++) item('v${i}vvvvvvvvv', title: 'Sit $i'),
      ]);
      final preview = await previewOf(listOne);
      expect(preview.itemCount, 8);
      expect(preview.firstItems.map((i) => i.title), [
        for (var i = 0; i < 5; i++) 'Sit $i',
      ]);
    });

    test('unknown durations are left out, and the total says so', () async {
      api.playlists[playlistOne] = playlist([
        item(videoA, seconds: 600),
        item(videoB, seconds: 0),
      ]);
      final preview = await previewOf(listOne);
      expect(preview.durationMs, 600000);
      expect(preview.durationComplete, isFalse);
      expect(preview.firstItems.last.durationMs, isNull);
    });

    test('nothing is stored by looking', () async {
      await previewOf(listOne);
      await previewOf(watchA);
      expect(await store.entries(), isEmpty);
      expect(await db.youtubeSessions(), isEmpty);
      expect(await db.youtubeCourses(), isEmpty);
    });

    test('something already kept says so', () async {
      await addCourse(listOne);
      expect((await previewOf(listOne)).alreadyInLibrary, isTrue);
      expect((await previewOf(watchA)).alreadyInLibrary, isFalse);
    });

    test(
      'links that are not YouTube pages are unrecognised, unasked',
      () async {
        for (final url in [
          'https://example.org/watch?v=$videoA',
          'https://www.youtube.com/@quietchannel',
          'https://www.youtube.com/watch?v=short',
        ]) {
          await expectLater(
            previewOf(url),
            failsWith(ImportFailureReason.unrecognised),
          );
        }
        expect(api.videoCalls, isEmpty);
        expect(api.playlistCalls, isEmpty);
      },
    );

    test('an empty playlist has no episodes', () async {
      api.playlists[playlistOne] = playlist([]);
      await expectLater(
        previewOf(listOne),
        failsWith(ImportFailureReason.noEpisodes),
      );
    });

    group('a watch link that also carries a list', () {
      test('an unusable list falls back to the video alone', () async {
        // A radio mix, a private list, anything the extractor will not read.
        final preview = await previewOf('$watchA&list=RDaaaaaaaaaaa');

        expect(preview.entryId, ytVideoId(videoA));
        expect(preview.kind, LibraryKind.single);
        expect(preview.allowedKinds, {LibraryKind.course, LibraryKind.single});
        expect(preview.youtubePlaylist, isNull);
        expect(preview.youtubePlaylistId, isNull);
        final result = await source.add(preview, single);
        expect(result.entryId, ytVideoId(videoA));
      });

      test('an empty list falls back to the video alone', () async {
        api.playlists[playlistOne] = playlist([]);
        final preview = await previewOf('$watchA&list=$playlistOne');
        expect(preview.entryId, ytVideoId(videoA));
        expect(preview.youtubePlaylistId, isNull);
      });

      test('an unusable video leaves the list as a course', () async {
        const gone = 'https://www.youtube.com/watch?v=ggggggggggg';
        final preview = await previewOf('$gone&list=$playlistOne');
        expect(preview.entryId, ytPlaylistId(playlistOne));
        expect(preview.allowedKinds, {LibraryKind.course});
      });

      test('both unusable is the calm unavailable failure', () async {
        await expectLater(
          previewOf('https://www.youtube.com/watch?v=ggggggggggg&list=RDx'),
          failsWith(ImportFailureReason.youtubeUnavailable),
        );
      });

      test('no network is still offline, not a silent fallback', () async {
        api.failure = PlatformException(code: 'network');
        await expectLater(
          previewOf('$watchA&list=$playlistOne'),
          failsWith(ImportFailureReason.offline),
        );
      });
    });

    for (final (code, reason) in [
      ('age-restricted', ImportFailureReason.youtubeAgeRestricted),
      ('private', ImportFailureReason.youtubePrivate),
      ('rate-limited', ImportFailureReason.youtubeRateLimited),
    ]) {
      test('both halves failing preserve $code', () async {
        api.failure = PlatformException(code: code);
        await expectLater(
          previewOf('$watchA&list=$playlistOne'),
          failsWith(reason),
        );
      });
    }

    group('failures are calm', () {
      test('no network is offline', () async {
        api.failure = PlatformException(code: 'network', message: 'dns fail');
        await expectLater(
          previewOf(watchA),
          failsWith(ImportFailureReason.offline),
        );
        await expectLater(
          previewOf(listOne),
          failsWith(ImportFailureReason.offline),
        );
      });

      for (final (code, reason) in [
        ('unavailable', ImportFailureReason.youtubeUnavailable),
        ('age-restricted', ImportFailureReason.youtubeAgeRestricted),
        ('private', ImportFailureReason.youtubePrivate),
        ('rate-limited', ImportFailureReason.youtubeRateLimited),
      ]) {
        test('$code preserves its import reason', () async {
          api.failure = PlatformException(code: code, message: 'internal');
          await expectLater(previewOf(watchA), failsWith(reason));
          await expectLater(previewOf(listOne), failsWith(reason));
        });
      }

      test('anything unexpected is unavailable too', () async {
        api.failure = StateError('boom');
        await expectLater(
          previewOf(listOne),
          failsWith(ImportFailureReason.youtubeUnavailable),
        );
      });

      test('the failure carries no raw detail', () async {
        api.failure = PlatformException(code: 'unavailable', message: 'SECRET');
        try {
          await previewOf(watchA);
          fail('should have thrown');
        } on ImportFailure catch (e) {
          expect(e.toString(), isNot(contains('SECRET')));
        }
      });
    });
  });

  group('practice or talk', () {
    test('only whole-word talk-like titles start as Talks', () {
      for (final title in [
        'Dharma Talk: Impermanence',
        'Weekly talks',
        'A lecture on the jhanas',
        'Interview with a teacher',
        'Podcast 12',
        'Open discussion',
        'Questions & Answers',
        'Q&A with the group',
        'q & a',
        'EVENING TALK',
      ]) {
        expect(youtubeGroup(title), LibraryGroup.talks, reason: title);
      }
    });

    test('everything else starts as Practice', () {
      for (final title in [
        'Body scan',
        'Talking meditation',
        'Walking meditation',
        'Metta for beginners',
        'Soundtalk',
        'Lecturer training',
        '',
      ]) {
        expect(youtubeGroup(title), LibraryGroup.practice, reason: title);
      }
    });

    test(
      'the preview starts from the title, the description is ignored',
      () async {
        api.videos[videoA] = video(
          videoA,
          title: 'Dharma talk on patience',
          description: 'A guided meditation',
        );
        expect((await previewOf(watchA)).group, LibraryGroup.talks);
        api.videos[videoA] = video(
          videoA,
          title: 'Patience',
          description: 'A dharma talk and lecture',
        );
        expect((await previewOf(watchA)).group, LibraryGroup.practice);
      },
    );

    test('a choice that differs from detection is an override', () async {
      api.videos[videoA] = video(videoA, title: 'Dharma talk');
      await addCourse(
        watchA,
        choice: const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
        ),
      );
      final entry = (await store.entry(ytVideoId(videoA)))!;
      expect(entry.detectedGroup, LibraryGroup.talks);
      expect(entry.groupOverride, LibraryGroup.practice);
      expect(entry.group, LibraryGroup.practice);
    });

    test('a choice that matches detection stores no override', () async {
      await addCourse(watchA, choice: single);
      final entry = (await store.entry(ytVideoId(videoA)))!;
      expect(entry.detectedGroup, LibraryGroup.practice);
      expect(entry.groupOverride, isNull);
    });
  });

  group('adding', () {
    test('a playlist becomes a course with the stable playlist ID', () async {
      final result = await addCourse(listOne);

      expect(result.entryId, 'yt-playlist-PLone');
      expect(result.kind, LibraryKind.course);
      expect(result.alreadyPresent, isFalse);
      final entry = (await store.entry(result.entryId))!;
      expect(entry.kind, LibraryKind.course);
      expect(entry.title, 'Evening Sits');
      expect(entry.subtitle, 'Quiet Channel');
      expect(entry.itemCount, 3);
      expect(entry.durationMs, 2400000);
    });

    test('a video added as Single is the stable video ID, no course', () async {
      final result = await addCourse(watchA, choice: single);

      expect(result.entryId, 'yt-video-$videoA');
      expect(result.kind, LibraryKind.single);
      final entry = (await store.entry(result.entryId))!;
      expect(entry.kind, LibraryKind.single);
      expect(entry.itemCount, 1);
      expect(entry.durationMs, 600000);
      expect(await db.youtubeVideo(videoA), isNotNull);
      expect(await db.youtubeCourses(), isEmpty);
    });

    test('a video added as Course is a one-session course', () async {
      final result = await addCourse(watchA);

      expect(result.entryId, 'yt-playlist-single-$videoA');
      expect(result.kind, LibraryKind.course);
      expect((await store.entry(result.entryId))!.itemCount, 1);
      final row = (await db.youtubePlaylist('single-$videoA'))!;
      expect(jsonDecode(row.videoIds), [videoA]);
      expect(await db.youtubeVideo(videoA), isNotNull);
    });

    test(
      'a watch link inside a list: Course keeps the list, Single the video',
      () async {
        final asCourse = await addCourse('$watchA&list=$playlistOne');
        expect(asCourse.entryId, 'yt-playlist-PLone');
        expect(await store.contains(ytVideoId(videoA)), isFalse);

        final asSingle = await addCourse(
          '$watchA&list=$playlistOne',
          choice: single,
        );
        expect(asSingle.entryId, 'yt-video-$videoA');
        expect(asSingle.alreadyPresent, isFalse);
        expect(await store.entries(), hasLength(2));
      },
    );

    test('adding twice changes nothing and says so', () async {
      await addCourse(listOne);
      final again = await addCourse(listOne);
      expect(again.alreadyPresent, isTrue);
      expect(again.entryId, 'yt-playlist-PLone');
      expect(await store.entries(), hasLength(1));
    });

    test('a name typed in the preview is kept apart from the title', () async {
      await addCourse(
        listOne,
        choice: const ImportChoice(
          kind: LibraryKind.course,
          group: LibraryGroup.practice,
          title: 'My evenings',
        ),
      );
      final entry = (await store.entry(ytPlaylistId(playlistOne)))!;
      expect(entry.displayTitle, 'My evenings');
      expect(entry.title, 'Evening Sits');
    });

    test('an unedited title is not a rename', () async {
      await addCourse(
        listOne,
        choice: const ImportChoice(
          kind: LibraryKind.course,
          group: LibraryGroup.practice,
          title: 'Evening Sits',
        ),
      );
      expect(
        (await store.entry(ytPlaylistId(playlistOne)))!.titleOverride,
        isNull,
      );
    });

    test('playlist order and repeats are kept exactly', () async {
      await addCourse(listOne);
      final row = (await db.youtubePlaylist(playlistOne))!;
      expect(jsonDecode(row.videoIds), [videoA, videoB, videoA]);
      expect(row.lastCheckedAt.isAtSameMomentAs(clock.now), isTrue);
    });

    test('a playlist summary does not erase a described video', () async {
      await addCourse(watchA, choice: single); // stores the description
      await addCourse(listOne);
      expect((await db.youtubeVideo(videoA))!.description, 'Described.');
    });

    test('the same video can belong to two courses', () async {
      await addCourse(listOne);
      await addCourse('https://www.youtube.com/playlist?list=$playlistTwo');

      final ids = await source.packTrackIds();
      expect(ids[ytPlaylistId(playlistOne)], [
        ytVideoId(videoA),
        ytVideoId(videoB),
        ytVideoId(videoA),
      ]);
      expect(ids[ytPlaylistId(playlistTwo)], [
        ytVideoId(videoA),
        ytVideoId(videoC),
      ]);
      expect(await db.youtubeSessions(), hasLength(3), reason: 'stored once');
    });
  });

  group('reading what was kept', () {
    test(
      'a pack lists its items in playlist order, repeats included',
      () async {
        await addCourse(listOne);
        final pack = await source
            .pack(ytPlaylistId(playlistOne))
            .timeout(const Duration(seconds: 3));

        expect(pack.title, 'Evening Sits');
        expect(
          [for (final i in pack.items) i.id],
          [ytVideoId(videoA), ytVideoId(videoB), ytVideoId(videoA)],
        );
        expect(
          [for (final i in pack.items) i.title],
          ['First sit', 'Second sit', 'First sit'],
        );
        expect(pack.items.first.durationMs, 600000);
        expect(pack.attribution?.url, listOne);
      },
    );

    test('a one-session course points back at its video', () async {
      await addCourse(watchA);
      final pack = await source.pack(ytSingleCourseId(videoA));
      expect(pack.items.single.id, ytVideoId(videoA));
      expect(pack.attribution?.url, watchA);
    });

    test('browse shows only courses still in the library', () async {
      await addCourse(listOne);
      await addCourse('https://www.youtube.com/playlist?list=$playlistTwo');
      await store.remove(ytPlaylistId(playlistTwo));

      final packs = await source.browsePacks();
      expect([for (final p in packs) p.id], [ytPlaylistId(playlistOne)]);
    });

    test('search finds courses and sessions by title or channel', () async {
      await addCourse(listOne);
      expect(
        (await source.searchPacks('evening')).single.id,
        ytPlaylistId(playlistOne),
      );
      expect(await source.searchPacks('quiet channel'), hasLength(1));
      expect(await source.searchPacks('  '), isEmpty);
      expect(await source.searchPacks('nothing'), isEmpty);
      expect(
        (await source.searchTracks('second')).single.id,
        ytVideoId(videoB),
      );
      expect(await source.searchTracks(''), isEmpty);
    });

    test(
      'removing a single hides it from search but retains metadata',
      () async {
        await addCourse(watchA, choice: single);
        await store.remove(ytVideoId(videoA));
        expect(await source.searchTracks('quiet'), isEmpty);
        expect((await source.track(ytVideoId(videoA))).id, ytVideoId(videoA));
        expect(await db.youtubeVideo(videoA), isNotNull);
        expect(api.audioCalls, isEmpty);
      },
    );

    test(
      'removed courses hide unique videos while shared active videos remain',
      () async {
        await addCourse(listOne);
        await addCourse('https://www.youtube.com/playlist?list=$playlistTwo');
        await store.remove(ytPlaylistId(playlistOne));
        expect((await source.searchTracks('quiet')).map((t) => t.id).toSet(), {
          ytVideoId(videoA),
          ytVideoId(videoC),
        });
        expect(await source.searchPacks('evening'), isEmpty);
        expect((await source.browsePacks()).map((p) => p.id), [
          ytPlaylistId(playlistTwo),
        ]);
        expect(await db.youtubeSessions(), hasLength(3));
        expect(
          (await source.pack(ytPlaylistId(playlistOne))).items,
          hasLength(3),
          reason: 'history can still read retained source metadata',
        );
      },
    );

    test(
      'a saved single stays searchable after its course is removed',
      () async {
        await addCourse(listOne);
        await addCourse(
          'https://www.youtube.com/watch?v=$videoB',
          choice: single,
        );
        await store.remove(ytPlaylistId(playlistOne));
        expect((await source.searchTracks('quiet')).map((t) => t.id), [
          ytVideoId(videoB),
        ]);
      },
    );

    test(
      'refresh hides orphaned videos without erasing their metadata',
      () async {
        await addCourse(listOne);
        api.playlists[playlistOne] = playlist([item(videoB)]);
        await source.refresh(ytPlaylistId(playlistOne), force: true);
        expect((await source.searchTracks('quiet')).map((t) => t.id), [
          ytVideoId(videoB),
        ]);
        expect(await db.youtubeVideo(videoA), isNotNull);
      },
    );

    test('a course is the parent of its sessions', () async {
      await addCourse(listOne);
      expect(
        await source.parentOf(ytVideoId(videoB)),
        ytPlaylistId(playlistOne),
      );
      expect(await source.parentOf(ytVideoId(videoC)), isNull);
    });

    test('saving and removing go through the library', () async {
      await addCourse(listOne);
      final id = ytPlaylistId(playlistOne);
      expect(source.canSave(id), isTrue);
      expect(source.canSave('lib-something'), isFalse);
      expect(await source.isSaved(id), isTrue);
      await source.setSaved(id, saved: false);
      expect(await source.isSaved(id), isFalse);
      await source.setSaved(id, saved: true);
      expect((await store.entry(id))!.itemCount, 3);
    });

    test('unknown or foreign IDs are unavailable, not crashes', () async {
      await expectLater(
        source.pack('yt-playlist-nope'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      await expectLater(
        source.pack('lib-x'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      await expectLater(
        source.track('yt-video-$videoC'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      await expectLater(
        source.track('lib-x'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      expect(api.audioCalls, isEmpty);
    });
  });

  group('playing', () {
    late int hour; // epoch ms, one hour from the clock

    setUp(() async {
      hour = clock.now.add(const Duration(hours: 1)).millisecondsSinceEpoch;
      api.streams[videoA] = stream(videoA, expiresAt: hour);
      await addCourse(watchA, choice: single);
    });

    test('metadata opens offline without stream or video lookup', () async {
      api.failure = PlatformException(code: 'network');
      api.audioGate = Completer<void>();
      final track = await source.track(ytVideoId(videoA));
      expect(track.voices.single.audioFiles.single.path, watchA);
      expect(track.voices.single.audioFiles.single.id, ytVideoId(videoA));
      expect(api.audioCalls, isEmpty);
      expect(api.videoCalls, hasLength(1), reason: 'only the earlier import');
    });

    test('retained metadata remains available after library removal', () async {
      await store.remove(ytVideoId(videoA));
      api.failure = PlatformException(code: 'network');
      final track = await source.track(ytVideoId(videoA));
      expect(track.title, 'A quiet sit');
      expect(api.audioCalls, isEmpty);
    });

    test('a track plays the resolved audio address', () async {
      final track = await source.resolveTrack(ytVideoId(videoA));

      expect(track.id, ytVideoId(videoA));
      expect(track.title, 'A quiet sit');
      expect(
        track.voices.single.audioFiles.single.path,
        api.streams[videoA]!.url,
      );
      expect(track.voices.single.audioFiles.single.duration, 600000);
      expect(track.attribution?.url, watchA);
      expect(track.hasBackgroundSound, isTrue, reason: 'Practice');
    });

    test('a Talk plays without background sound', () async {
      await store.setGroup(ytVideoId(videoA), LibraryGroup.talks);
      expect(
        (await source.track(ytVideoId(videoA))).hasBackgroundSound,
        isFalse,
      );
    });

    test('a session takes the group of its course', () async {
      await addCourse(listOne);
      await store.setGroup(ytPlaylistId(playlistOne), LibraryGroup.talks);
      await store.remove(ytVideoId(videoA)); // leave only the course
      expect(
        (await source.track(ytVideoId(videoA))).hasBackgroundSound,
        isFalse,
      );
    });

    test(
      'the address is reused until five minutes before it expires',
      () async {
        await source.resolveTrack(ytVideoId(videoA));
        clock.advance(const Duration(minutes: 54));
        await source.resolveTrack(ytVideoId(videoA));
        expect(api.audioCalls, hasLength(1));

        clock.advance(const Duration(minutes: 2)); // 56 min: inside the margin
        await source.resolveTrack(ytVideoId(videoA));
        expect(api.audioCalls, hasLength(2));
      },
    );

    test('the cache boundary is exactly the margin', () async {
      await source.resolveTrack(ytVideoId(videoA));
      clock.advance(const Duration(minutes: 54, seconds: 59));
      await source.resolveTrack(ytVideoId(videoA));
      expect(api.audioCalls, hasLength(1));

      clock.advance(const Duration(seconds: 1)); // 55:00 — no longer fresh
      await source.resolveTrack(ytVideoId(videoA));
      expect(api.audioCalls, hasLength(2));
    });

    test('an unknown expiry is cached briefly, not for hours', () async {
      api.streams[videoA] = stream(videoA); // expiresAt null
      await source.resolveTrack(ytVideoId(videoA));
      clock.advance(const Duration(minutes: 4));
      await source.resolveTrack(ytVideoId(videoA));
      expect(api.audioCalls, hasLength(1));

      clock.advance(const Duration(minutes: 2));
      await source.resolveTrack(ytVideoId(videoA));
      expect(api.audioCalls, hasLength(2));

      clock.advance(const Duration(minutes: 30));
      await source.resolveTrack(ytVideoId(videoA));
      expect(api.audioCalls, hasLength(3));
    });

    test('a new source starts with nothing cached', () async {
      await source.resolveTrack(ytVideoId(videoA));
      await newSource().resolveTrack(ytVideoId(videoA));
      expect(api.audioCalls, hasLength(2));
    });

    test('simultaneous requests share one extraction', () async {
      api.audioGate = Completer<void>();
      final first = source.resolveTrack(ytVideoId(videoA));
      final second = source.resolveTrack(ytVideoId(videoA));
      final third = source.resolveTrack(ytVideoId(videoA));
      await pumpEventQueue();
      expect(api.audioCalls, hasLength(1));

      api.audioGate!.complete();
      final tracks = await Future.wait([first, second, third]);
      expect(api.audioCalls, hasLength(1));
      expect({
        for (final t in tracks) t.voices.single.audioFiles.single.path,
      }, hasLength(1));
    });

    test('a failed extraction is calm and the next try asks again', () async {
      api.failure = PlatformException(
        code: 'network',
        message: 'dns lookup for rr1.googlevideo.com failed',
      );
      await expectLater(
        source.resolveTrack(ytVideoId(videoA)),
        throwsA(
          isA<YoutubeUnavailableError>().having(
            (e) => e.message,
            'message',
            unavailable,
          ),
        ),
      );

      api.failure = null;
      expect(
        (await source.resolveTrack(ytVideoId(videoA))).title,
        'A quiet sit',
      );
      expect(api.audioCalls, hasLength(2));
    });

    for (final (code, reason) in [
      ('network', YoutubeFailureReason.offline),
      ('unavailable', YoutubeFailureReason.unavailable),
      ('age-restricted', YoutubeFailureReason.ageRestricted),
      ('private', YoutubeFailureReason.private),
      ('rate-limited', YoutubeFailureReason.rateLimited),
      ('unrecognised-code', YoutubeFailureReason.unavailable),
    ]) {
      test(
        'audio preserves $code as $reason without extractor detail',
        () async {
          api.failure = PlatformException(code: code, message: 'SECRET');
          await expectLater(
            source.resolveTrack(ytVideoId(videoA)),
            throwsA(
              isA<YoutubeUnavailableError>()
                  .having((e) => e.reason, 'reason', reason)
                  .having(
                    (e) => e.toString(),
                    'safe message',
                    isNot(contains('SECRET')),
                  ),
            ),
          );
        },
      );
    }

    test('unexpected audio failures remain safely unavailable', () async {
      api.failure = StateError('SECRET');
      await expectLater(
        source.resolveTrack(ytVideoId(videoA)),
        throwsA(
          isA<YoutubeUnavailableError>().having(
            (e) => e.reason,
            'reason',
            YoutubeFailureReason.unavailable,
          ),
        ),
      );
    });

    for (final (name, bad) in <(String, YoutubeAudioStream)>[
      ('a plain-http address', stream(videoA, url: 'http://x.example/a')),
      ('an address with no host', stream(videoA, url: 'https:///a')),
      ('a non-audio stream', stream(videoA, mime: 'video/mp4')),
      ('an address already expired', stream(videoA, expiresAt: 1000)),
    ]) {
      test('$name is refused and not cached', () async {
        api.streams[videoA] = bad;
        await expectLater(
          source.resolveTrack(ytVideoId(videoA)),
          throwsA(isA<YoutubeUnavailableError>()),
        );
        await expectLater(
          source.resolveTrack(ytVideoId(videoA)),
          throwsA(isA<YoutubeUnavailableError>()),
        );
        expect(api.audioCalls, hasLength(2));
      });
    }

    test('the database holds metadata only, never an address', () async {
      await addCourse(listOne);
      await source.resolveTrack(ytVideoId(videoA));
      final url = api.streams[videoA]!.url;

      final everything = [
        for (final row in await db.youtubeSessions()) row.toString(),
        for (final row in await db.youtubeCourses()) row.toString(),
        for (final row in await db.allEntries()) row.toString(),
      ].join('\n');
      expect(everything, isNot(contains('googlevideo')));
      expect(everything, isNot(contains('SECRET')));
      expect(everything, isNot(contains(url)));
    });
  });

  group('refreshing', () {
    const id = 'yt-playlist-PLone';

    setUp(() async => addCourse(listOne));

    int calls() => api.playlistCalls.length;

    test(
      'pack returns stored sessions while a slow refresh notifies later',
      () async {
        clock.advance(const Duration(hours: 13));
        api.playlistGate = Completer<void>();
        api.playlists[playlistOne] = playlist([
          item(videoC),
        ], title: 'New course');
        final before = store.revision.value;
        final outcomes = source.refreshRevision.value;
        final stored = await source
            .pack(id)
            .timeout(const Duration(seconds: 1));
        expect(stored.items.map((i) => i.id), [
          ytVideoId(videoA),
          ytVideoId(videoB),
          ytVideoId(videoA),
        ]);
        await pumpEventQueue();
        expect(calls(), 2);
        expect(store.revision.value, before);

        final refresh = source.refresh(
          id,
        ); // shares the pack's background attempt
        api.playlistGate!.complete();
        expect(await refresh, isTrue);
        expect(store.revision.value, before + 1);
        expect(source.refreshRevision.value, outcomes + 1);
        expect(source.refreshError(id), isNull);
        expect((await source.pack(id)).items.single.id, ytVideoId(videoC));
      },
    );

    test(
      'empty starter failure keeps timestamp and retries within twelve hours',
      () async {
        await source.storePlaylist(playlistOne, playlist([]));
        final checked = (await db.youtubePlaylist(playlistOne))!.lastCheckedAt;
        clock.advance(const Duration(minutes: 1));
        api.failure = PlatformException(code: 'network');
        final notifications = source.refreshRevision.value;

        final empty = await source.pack(id).timeout(const Duration(seconds: 1));
        expect(empty.items, isEmpty);
        expect(await source.refresh(id), isFalse);
        expect(source.refreshError(id)?.reason, YoutubeFailureReason.offline);
        expect(source.refreshRevision.value, notifications + 1);
        expect((await db.youtubePlaylist(playlistOne))!.lastCheckedAt, checked);

        // Reopening while offline retries but does not repeatedly invalidate UI.
        await source.pack(id);
        expect(await source.refresh(id), isFalse);
        expect(source.refreshRevision.value, notifications + 1);
        final attempted = calls();
        api.failure = null;
        expect(
          await newSource().refresh(id),
          isTrue,
          reason: 'empty state bypasses the persisted twelve-hour gate',
        );
        expect(calls(), attempted + 1);
        expect((await source.pack(id)).items, hasLength(3));
        // An explicit successful refresh clears this source's recorded failure.
        expect(await source.refresh(id, force: true), isTrue);
        expect(source.refreshError(id), isNull);
      },
    );

    test(
      'an empty extraction also leaves an empty starter immediately retryable',
      () async {
        await source.storePlaylist(playlistOne, playlist([]));
        final checked = (await db.youtubePlaylist(playlistOne))!.lastCheckedAt;
        clock.advance(const Duration(minutes: 1));
        api.playlists[playlistOne] = playlist([]);
        expect(await source.refresh(id), isFalse);
        expect((await db.youtubePlaylist(playlistOne))!.lastCheckedAt, checked);
        expect(
          source.refreshError(id)?.reason,
          YoutubeFailureReason.unavailable,
        );
        api.playlists[playlistOne] = playlist([item(videoA)]);
        expect(await source.refresh(id), isTrue);
        expect(source.refreshError(id), isNull);
      },
    );

    for (final (code, reason) in [
      ('network', YoutubeFailureReason.offline),
      ('unavailable', YoutubeFailureReason.unavailable),
      ('age-restricted', YoutubeFailureReason.ageRestricted),
      ('private', YoutubeFailureReason.private),
      ('rate-limited', YoutubeFailureReason.rateLimited),
    ]) {
      test(
        'forced refresh preserves $code and automatic refresh records it',
        () async {
          api.failure = PlatformException(code: code, message: 'SECRET');
          clock.advance(const Duration(hours: 13));
          expect(await source.refresh(id), isFalse);
          expect(source.refreshError(id)?.reason, reason);
          await expectLater(
            source.refresh(id, force: true),
            throwsA(
              isA<YoutubeUnavailableError>()
                  .having((e) => e.reason, 'reason', reason)
                  .having(
                    (e) => e.toString(),
                    'safe message',
                    isNot(contains('SECRET')),
                  ),
            ),
          );
          expect((await source.pack(id)).items, hasLength(3));
        },
      );
    }

    test(
      'forced refresh joining a background failure still throws its reason',
      () async {
        clock.advance(const Duration(hours: 13));
        api.playlistGate = Completer<void>();
        api.failure = PlatformException(code: 'private');
        await source.pack(id);
        await pumpEventQueue();
        final forced = source.refresh(id, force: true);
        final assertion = expectLater(
          forced,
          throwsA(
            isA<YoutubeUnavailableError>().having(
              (e) => e.reason,
              'reason',
              YoutubeFailureReason.private,
            ),
          ),
        );
        api.playlistGate!.complete();
        await assertion;
        expect(calls(), 2, reason: 'one import and one shared refresh');
      },
    );

    test(
      'forced refresh bypasses a simultaneous automatic throttle check',
      () async {
        final automatic = source.refresh(id);
        final forced = source.refresh(id, force: true);
        expect(await automatic, isFalse);
        expect(await forced, isTrue);
        expect(calls(), 2);
      },
    );

    test('a fresh course is not asked again within twelve hours', () async {
      final before = calls();
      clock.advance(const Duration(hours: 11, minutes: 59));
      expect(await source.refresh(id), isFalse);
      await source.pack(id);
      expect(calls(), before);
    });

    test(
      'after twelve hours the list is re-read and the library follows',
      () async {
        api.playlists[playlistOne] = playlist([
          item(videoB, seconds: 300),
          item(videoC, seconds: 300),
        ], title: 'Evening Sits, renewed');
        final before = calls();
        clock.advance(const Duration(hours: 12));

        expect(await source.refresh(id), isTrue);
        expect(calls(), before + 1);
        expect(api.playlistCalls.last, listOne);
        final entry = (await store.entry(id))!;
        expect(entry.title, 'Evening Sits, renewed');
        expect(entry.itemCount, 2);
        expect(entry.durationMs, 600000);
        expect(
          (await db.youtubePlaylist(
            playlistOne,
          ))!.lastCheckedAt.isAtSameMomentAs(clock.now),
          isTrue,
        );
        final pack = await source.pack(id);
        expect(
          [for (final i in pack.items) i.id],
          [ytVideoId(videoB), ytVideoId(videoC)],
        );
      },
    );

    test('a changed list leaves other courses intact', () async {
      await addCourse('https://www.youtube.com/playlist?list=$playlistTwo');
      api.playlists[playlistOne] = playlist([item(videoB)]);
      clock.advance(const Duration(hours: 13));
      await source.refresh(id);

      final other = await source.pack(ytPlaylistId(playlistTwo));
      expect(
        [for (final i in other.items) i.id],
        [ytVideoId(videoA), ytVideoId(videoC)],
      );
    });

    test('a forced refresh ignores the interval', () async {
      final before = calls();
      expect(await source.refresh(id, force: true), isTrue);
      expect(calls(), before + 1);
    });

    test('a failed refresh keeps everything and returns quietly', () async {
      clock.advance(const Duration(hours: 13));
      api.failure = PlatformException(code: 'network');

      expect(await source.refresh(id), isFalse);
      final pack = await source.pack(id);
      expect(pack.items, hasLength(3));
      expect((await store.entry(id))!.itemCount, 3);
    });

    test('an empty answer keeps the stored sessions', () async {
      clock.advance(const Duration(hours: 13));
      api.playlists[playlistOne] = playlist([]);

      expect(await source.refresh(id), isFalse);
      expect((await source.pack(id)).items, hasLength(3));
      expect((await store.entry(id))!.itemCount, 3);
    });

    test('opening a course while offline still works', () async {
      clock.advance(const Duration(days: 3));
      api.failure = PlatformException(code: 'network');
      expect((await source.pack(id)).items, hasLength(3));
      expect(await source.refresh(id), isFalse);
    });

    test('a failed attempt is remembered, across new sources', () async {
      clock.advance(const Duration(hours: 13));
      api.failure = PlatformException(code: 'network');
      await source.refresh(id);
      final attempted = calls();

      clock.advance(const Duration(hours: 1));
      expect(await newSource().refresh(id), isFalse);
      await newSource().refreshAll();
      expect(calls(), attempted, reason: 'throttled by the stored attempt');

      clock.advance(const Duration(hours: 11)); // 12 h since the attempt
      api.failure = null;
      expect(await newSource().refresh(id), isTrue);
      expect(calls(), attempted + 1);
    });

    test(
      'a forced refresh that fails says so plainly, keeping content',
      () async {
        api.failure = PlatformException(code: 'unavailable');
        await expectLater(
          source.refresh(id, force: true),
          throwsA(
            isA<YoutubeUnavailableError>().having(
              (e) => e.message,
              'message',
              unavailable,
            ),
          ),
        );
        expect((await source.pack(id)).items, hasLength(3));
      },
    );

    test('a forced refresh after a failure is not throttled', () async {
      clock.advance(const Duration(hours: 13));
      api.failure = PlatformException(code: 'network');
      await source.refresh(id);
      final attempted = calls();

      api.failure = null;
      expect(await source.refresh(id, force: true), isTrue);
      expect(calls(), attempted + 1);
    });

    test('simultaneous refreshes share one request', () async {
      api.playlistGate = Completer<void>();
      final before = calls();
      final first = source.refresh(id, force: true);
      final second = source.refresh(id, force: true);
      await pumpEventQueue();
      expect(calls(), before + 1);

      api.playlistGate!.complete();
      expect(await Future.wait([first, second]), [true, true]);
      expect(calls(), before + 1);
    });

    test('one-video courses and foreign IDs are never refreshed', () async {
      await addCourse(watchA);
      clock.advance(const Duration(days: 2));
      final before = calls();
      expect(
        await source.refresh(ytSingleCourseId(videoA), force: true),
        isFalse,
      );
      expect(await source.refresh(ytVideoId(videoA), force: true), isFalse);
      expect(await source.refresh('lib-x', force: true), isFalse);
      expect(await source.refresh('yt-playlist-unknown', force: true), isFalse);
      expect(calls(), before);
    });

    test('refreshAll visits only due YouTube courses', () async {
      await addCourse('https://www.youtube.com/playlist?list=$playlistTwo');
      await addCourse(watchA, choice: single);
      clock.advance(const Duration(hours: 13));
      api.playlists[playlistTwo] = playlist([item(videoC)], title: 'Shrunk');
      final before = calls();
      final videosBefore = api.videoCalls.length;

      await source.refreshAll();

      expect(calls(), before + 2, reason: 'both playlists, nothing else');
      expect(api.videoCalls, hasLength(videosBefore));
      expect((await store.entry(ytPlaylistId(playlistTwo)))!.itemCount, 1);
    });

    test('refreshAll shrugs off a failing playlist and carries on', () async {
      await addCourse('https://www.youtube.com/playlist?list=$playlistTwo');
      clock.advance(const Duration(hours: 13));
      api.playlists.remove(playlistOne); // one now unavailable
      api.playlists[playlistTwo] = playlist([item(videoC)], title: 'Shrunk');

      await source.refreshAll();

      expect((await store.entry(id))!.itemCount, 3);
      expect((await store.entry(ytPlaylistId(playlistTwo)))!.itemCount, 1);
    });
  });
}
