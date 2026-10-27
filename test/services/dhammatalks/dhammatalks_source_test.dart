import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/services/dhammatalks/dhammatalks_feed.dart';
import 'package:medito/services/dhammatalks/dhammatalks_ids.dart';
import 'package:medito/services/dhammatalks/dhammatalks_source.dart';
import 'package:medito/services/library/import_http.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';

import '../../helpers/dhammatalks_fixtures.dart';
import '../../helpers/library_fixtures.dart';

void main() {
  late LibraryStore library;
  var now = DateTime.utc(2026, 10, 27, 12);

  DhammatalksSource source({
    ImportHttp? client,
    DtFeedCache? cache,
    LibraryStore? store,
  }) => DhammatalksSource(
    loadSnapshot: () async => dhammatalksCatalogue(),
    http: client,
    cache: cache,
    library: store ?? library,
    clock: () => now,
  );

  setUp(() {
    library = LibraryStore(memoryLibraryDb());
    now = DateTime.utc(2026, 10, 27, 12);
  });

  group('reads', () {
    test('a collection is a course; the talks it lists are in order', () async {
      final pack = await source().pack('dt-course-guided');
      expect(pack.title, 'Guided meditations');
      expect(pack.items.map((i) => i.title), [
        'Metta',
        'Breath (short version)',
      ]);
      expect(pack.items.first.durationMs, 240000);
      expect(
        pack.items.first.path,
        '/tracks/dt-talk-c-guided-01guidedmetta-4min',
      );
      expect(pack.teacher!.name, dtTeacherName);
    });

    test(
      'a file the archive also holds has one ID wherever it is listed',
      () async {
        final basics = await source().pack('dt-course-basics');
        expect(basics.items.map((i) => i.id), [
          'dt-talk-c-basics-01-strength',
          'dt-talk-e-0308n3-anger',
        ]);
      },
    );

    test('a talk is one voice and one unmodified file, with its credit', () async {
      final track = await source().track(
        'dt-talk-e-251231-an-auspicious-night',
      );
      expect(
        track.voices.single.audioFiles.single.path,
        'https://www.dhammatalks.org/Archive/y2025/251231_An_Auspicious_Night.mp3',
      );
      expect(track.hasBackgroundSound, isFalse);
      final credit = track.attribution!;
      expect(credit.licenseName, 'CC BY-NC 4.0');
      expect(
        credit.licenseUrl,
        'https://creativecommons.org/licenses/by-nc/4.0/',
      );
      expect(credit.creator, 'Thanissaro Bhikkhu');
      expect(
        credit.url,
        'https://www.dhammatalks.org/audio/evening/2025/251231-an-auspicious-night.html',
      );
    });

    test('a guided meditation allows background sound; its credit is the '
        'collection page', () async {
      final track = await source().track('dt-talk-c-guided-01guidedmetta-4min');
      expect(track.hasBackgroundSound, isTrue);
      expect(
        track.attribution!.url,
        'https://www.dhammatalks.org/mp3_guidedMed_index.html',
      );
    });

    test('unknown IDs are unavailable', () async {
      expect(
        source().track('dt-talk-e-nope'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      expect(
        source().pack('dt-course-nope'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      expect(
        source().teacherPage('dt-teacher-other'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
    });

    test(
      'a year of the archive is a list, newest first, and cannot be kept',
      () async {
        final s = source();
        final pack = await s.pack('dt-year-e-2025');
        expect(pack.title, 'Evening talks 2025');
        expect(pack.items.map((i) => i.title), [
          'An Auspicious Night',
          'Samādhi & Mindfulness',
        ]);
        expect(s.canSave('dt-year-e-2025'), isFalse);
        expect(s.canSave('dt-talk-e-251231-an-auspicious-night'), isTrue);
        expect(s.canSave('dt-course-basics'), isTrue);
        expect(s.canSave(dtTeacherId), isTrue);
      },
    );
  });

  group('Explore', () {
    test('Practice: the guided course and its talks, no archives', () async {
      final explore = await source().explore(group: ContentGroup.practice);
      expect(explore.courses.map((c) => c.id), ['dt-course-guided']);
      expect(explore.talks.map((t) => t.title), [
        'Metta',
        'Breath (short version)',
      ]);
      expect(explore.archives, isEmpty);
      expect(explore.teachers.single.name, dtTeacherName);
    });

    test('Talks: the Basics course, the latest talks and the years', () async {
      final explore = await source().explore(group: ContentGroup.talks);
      expect(explore.courses.map((c) => c.id), ['dt-course-basics']);
      expect(explore.talks.first.title, 'The Perfection of Equanimity');
      expect(explore.archives.map((a) => a.title), [
        'Evening 2025',
        'Evening 2003',
        'Morning 2026',
      ]);
    });

    test('with no chip, guided practice leads (decision 11)', () async {
      final explore = await source().explore();
      expect(explore.courses.map((c) => c.id), [
        'dt-course-guided',
        'dt-course-basics',
      ]);
      expect(explore.talks.map((t) => t.title), [
        'Metta',
        'Breath (short version)',
      ]);
    });

    test(
      'a course in the library is left out; a followed teacher moves',
      () async {
        final s = source();
        await s.setSaved('dt-course-basics', saved: true);
        await s.setSaved(dtTeacherId, saved: true);
        final explore = await s.explore();
        expect(explore.courses.map((c) => c.id), ['dt-course-guided']);
        expect(explore.teachers, isEmpty);
        expect(explore.savedTeachers.single.id, dtTeacherId);
      },
    );

    test(
      'an empty catalogue offers nothing, not a teacher with no talks',
      () async {
        final s = DhammatalksSource(
          loadSnapshot: () async => emptyDhammatalks(),
        );
        expect((await s.explore()).isEmpty, isTrue);
      },
    );
  });

  group('search', () {
    test('folds diacritics and matches word prefixes', () async {
      final results = await source().search('samadhi mind');
      expect(results.talks.map((t) => t.title), ['Samādhi & Mindfulness']);
    });

    test('finds courses and the teacher', () async {
      final results = await source().search('thanissaro');
      expect(results.teachers.single.id, dtTeacherId);
      expect(
        (await source().search('basics')).courses.single.id,
        'dt-course-basics',
      );
    });

    test(
      'talks without a length drop out while a length filter is on',
      () async {
        final all = await source().search('anger');
        expect(all.talks, isNotEmpty);
        final filtered = await source().search(
          'metta',
          length: SessionLength.under10,
        );
        expect(filtered.talks.map((t) => t.title), ['Metta']);
        expect(
          (await source().search('anger', length: SessionLength.under10)).talks,
          isEmpty,
        );
      },
    );

    test('a search of nothing is empty', () async {
      expect((await source().search('  ')).isEmpty, isTrue);
    });
  });

  group('library', () {
    test(
      'talks, courses and the teacher keep as the right kind and group',
      () async {
        final s = source();
        await s.setSaved('dt-course-guided', saved: true);
        await s.setSaved('dt-talk-e-251231-an-auspicious-night', saved: true);
        await s.setSaved('dt-talk-c-guided-01guidedmetta-4min', saved: true);
        final entries = {
          for (final e in await library.entries()) e.sourceId: e,
        };
        expect(entries['dt-course-guided']!.kind, LibraryKind.course);
        expect(entries['dt-course-guided']!.group, LibraryGroup.practice);
        expect(
          entries['dt-talk-e-251231-an-auspicious-night']!.group,
          LibraryGroup.talks,
        );
        expect(
          entries['dt-talk-c-guided-01guidedmetta-4min']!.group,
          LibraryGroup.practice,
        );
        expect(await s.isSaved('dt-course-guided'), isTrue);
        await s.setSaved('dt-course-guided', saved: false);
        expect(await s.isSaved('dt-course-guided'), isFalse);
      },
    );

    test('a collection-only talk knows its course', () async {
      expect(
        await source().parentOf('dt-talk-c-basics-01-strength'),
        'dt-course-basics',
      );
      expect(
        await source().parentOf('dt-talk-e-251231-an-auspicious-night'),
        isNull,
      );
    });

    test('pack track IDs cover saved and started collections only', () async {
      final s = source();
      expect(await s.packTrackIds(), isEmpty);
      await s.setSaved('dt-course-basics', saved: true);
      final ids = await s.packTrackIds(
        startedTrackIds: {'dt-talk-c-guided-01guidedmetta-4min'},
      );
      expect(ids.keys, containsAll(['dt-course-basics', 'dt-course-guided']));
    });
  });

  group('links', () {
    Future<String?> id(String url) => source().idForLink(Uri.parse(url));

    test('a talk page, a year, the landing page and the indexes', () async {
      expect(
        await id(
          'https://www.dhammatalks.org/audio/evening/2025/251231-an-auspicious-night.html',
        ),
        'dt-talk-e-251231-an-auspicious-night',
      );
      expect(
        await id('https://dhammatalks.org/audio/evening/2025/'),
        'dt-year-e-2025',
      );
      expect(
        await id('https://www.dhammatalks.org/audio/evening/'),
        'dt-year-e-2025',
      );
      expect(
        await id('https://www.dhammatalks.org/mp3_guidedMed_index.html'),
        'dt-course-guided',
      );
      expect(
        await id(
          'https://www.dhammatalks.org/mp3_collections_index.html#basics',
        ),
        'dt-course-basics',
      );
    });

    test('the audio file of a known talk, encoded or not', () async {
      expect(
        await id(
          'https://www.dhammatalks.org/Archive/y2025/251231_An_Auspicious_Night.mp3',
        ),
        'dt-talk-e-251231-an-auspicious-night',
      );
      expect(
        await id(
          'https://www.dhammatalks.org/Archive/y2003/0308n3a1%20Anger.mp3',
        ),
        'dt-talk-e-0308n3-anger',
      );
    });

    test('anything else is not the catalogue\'s', () async {
      expect(
        await id('https://www.dhammatalks.org/audio/evening/2025/zzz.html'),
        isNull,
      );
      expect(await id('https://www.dhammatalks.org/books/'), isNull);
      expect(await id('https://example.org/audio/evening/2025/'), isNull);
      expect(await id('https://www.dhammatalks.org/rss/evening.xml'), isNull);
    });
  });

  group('the feeds', () {
    final feed = File(
      'test/fixtures/dhammatalks/evening_feed.xml',
    ).readAsStringSync();

    test('items become talks with the date from their key', () {
      final talks = dtTalksFromFeed(feed, DtChannel.evening);
      // The parser reads a feed oldest first.
      expect(talks.map((t) => t.id), [
        'dt-talk-e-261025-appropriate-attention-to-the-breath',
        'dt-talk-e-261026-intelligent-silence',
      ], reason: 'an item with no page cannot be given an ID');
      final latest = talks.last;
      expect(latest.date, '2026-10-26');
      expect(latest.durationMs, 668000);
      expect(latest.audioPath, '/Archive/y2026/261026_Intelligent_Silence.mp3');
    });

    test('Explore opens: both feeds read, merged, and kept', () async {
      final requests = <Uri>[];
      final cache = MemoryDtFeedCache();
      final s = source(
        client: ImportHttp(
          client: MockClient((request) async {
            requests.add(request.url);
            return http.Response(
              feed,
              200,
              headers: {'content-type': 'application/rss+xml'},
            );
          }),
        ),
        cache: cache,
      );
      final before = s.revision.value;
      await s.catchUp();
      expect(requests.map((u) => u.path), [
        '/rss/evening.xml',
        '/rss/morning.xml',
      ]);
      expect(
        (await s.catalogue()).talk('dt-talk-e-261026-intelligent-silence'),
        isNotNull,
      );
      expect(s.revision.value, greaterThan(before));
      expect(cache.state!.talks, isNotEmpty);
      // The next launch has them without the network.
      final next = source(cache: cache);
      expect(
        (await next.catalogue())
            .talk('dt-talk-e-261026-intelligent-silence')!
            .durationMs,
        668000,
      );
    });

    test('read at most every six hours, unless forced', () async {
      var calls = 0;
      final s = source(
        client: ImportHttp(
          client: MockClient((_) async {
            calls++;
            return http.Response(feed, 200);
          }),
        ),
      );
      await s.catchUp();
      expect(calls, 2);
      now = now.add(const Duration(hours: 1));
      await s.catchUp();
      expect(calls, 2);
      await s.catchUp(force: true);
      expect(calls, 4);
      now = now.add(const Duration(hours: 7));
      await s.catchUp();
      expect(calls, 6);
    });

    test(
      'nothing is fetched until asked, and a failure keeps what there is',
      () async {
        var calls = 0;
        final s = source(
          client: ImportHttp(
            client: MockClient((_) async {
              calls++;
              throw const SocketException('offline');
            }),
          ),
        );
        await s.catalogue();
        await s.pack('dt-course-basics');
        expect(calls, 0, reason: 'reads never use the network');
        await s.catchUp();
        expect(calls, greaterThan(0));
        expect((await s.pack('dt-course-basics')).items, isNotEmpty);
      },
    );

    test('a feed talk the snapshot holds lends it its length', () async {
      final s = source(
        client: ImportHttp(
          client: MockClient(
            (_) async => http.Response(
              feed.replaceAll(
                '261026-intelligent-silence',
                '251231-an-auspicious-night',
              ),
              200,
            ),
          ),
        ),
      );
      await s.catchUp();
      final talk = (await s.catalogue()).talk(
        'dt-talk-e-251231-an-auspicious-night',
      )!;
      expect(talk.durationMs, 668000);
      expect(talk.title, 'An Auspicious Night');
    });
  });

  group('ids', () {
    test('round trips', () {
      expect(parseDtTalkId(dtTalkId('e', '260131-a-slug')), (
        code: 'e',
        key: '260131-a-slug',
      ));
      expect(parseDtCourseId(dtCourseId('basics')), 'basics');
      expect(parseDtYearId(dtYearId(DtChannel.morning, 2024)), (
        channel: DtChannel.morning,
        year: 2024,
      ));
      expect(parseDtTalkId('dt-talk-'), isNull);
      expect(parseDtTalkId('ds-talk-1'), isNull);
      expect(parseDtYearId('dt-year-x-2024'), isNull);
    });

    test('dates from keys', () {
      expect(dtDateOfKey('260131-a-slug'), '2026-01-31');
      expect(dtDateOfKey('0308n3-anger'), '2003-08');
      expect(dtDateOfKey('261301-bad'), '');
      expect(dtDateOfKey('plain'), '');
    });
  });
}
