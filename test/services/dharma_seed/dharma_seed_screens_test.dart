import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';

import '../../helpers/dharma_seed_catalogue.dart';
import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/library_fixtures.dart';

void main() {
  late DharmaSeedDatabase db;
  late DharmaSeedSource source;
  late LibraryDatabase libraryDb;
  late LibraryStore library;

  setUp(() async {
    db = memoryDharmaSeedDb();
    libraryDb = memoryLibraryDb();
    library = LibraryStore(libraryDb);
    source = DharmaSeedSource(db: db, library: library, browseLimit: 10);
    await seedDharmaSeedCatalogue(db);
  });
  tearDown(() async {
    await db.close();
    await libraryDb.close();
  });

  group('explore', () {
    test(
      'without a chip: newest courses, busiest teachers, latest practice',
      () async {
        final explore = await source.explore();
        expect(explore.hasCatalogue, isTrue);
        expect(explore.courses.map((c) => c.id), [
          'ds-retreat-300',
          'ds-retreat-200',
          'ds-retreat-100',
        ]);
        // Practice leads where nothing else decides (decision 11): the
        // latest guided practice, newest first, and no talks.
        expect(explore.talks.map((t) => t.title), [
          'Sit',
          'Metta',
          'Breath meditation',
          'Settling',
        ]);
        // Burbea gave 5 talks and co-taught one more; Brasington gave 4.
        expect(explore.teachers.map((t) => t.name), [
          'Rob Burbea',
          'Leigh Brasington',
        ]);
        expect(explore.teachers.first.talkCount, 6);
        expect(
          explore.teachers.first.photoUrl,
          'https://www.dharmaseed.org/api/1/teachers/1/p.png/?maxW=400',
        );
        expect(explore.teachers.last.photoUrl, isEmpty);
      },
    );

    test(
      'Practice shows courses that are at least half guided practice',
      () async {
        final explore = await source.explore(group: ContentGroup.practice);
        expect(explore.courses.map((c) => c.id), [
          'ds-retreat-300',
          'ds-retreat-100',
        ]);
        expect(explore.talks.map((t) => t.title), [
          'Sit',
          'Metta',
          'Breath meditation',
          'Settling',
        ]);
        expect(
          explore.talks.every((t) => t.kind == 'Guided meditation'),
          isTrue,
        );
        expect(explore.teachers.first.name, 'Rob Burbea');
        expect(explore.teachers.first.talkCount, 3);
      },
    );

    test('Talks includes Q & A and untyped recordings', () async {
      final explore = await source.explore(group: ContentGroup.talks);
      expect(explore.courses.map((c) => c.id), ['ds-retreat-200']);
      expect(explore.talks.map((t) => t.title), [
        'Untyped talk about jhana',
        'Talk about sitting',
        'Winter questions',
        'Winter talk',
        'Jhana basics',
      ]);
      expect(explore.talks.first.kind, 'Recording');
    });

    test(
      'what is in the library leaves the browse lists, under any chip',
      () async {
        await source.setSaved('ds-retreat-100', saved: true);
        await source.setSaved('ds-teacher-2', saved: true);

        final all = await source.explore();
        // The library lists its own courses; browse does not repeat them.
        expect(all.courses.map((c) => c.id), [
          'ds-retreat-300',
          'ds-retreat-200',
        ]);
        expect(all.savedTeachers.map((t) => t.name), ['Leigh Brasington']);
        expect(all.teachers.map((t) => t.name), ['Rob Burbea']);

        // A chip never hides what the user kept.
        final practice = await source.explore(group: ContentGroup.practice);
        expect(practice.courses.map((c) => c.id), ['ds-retreat-300']);
        expect(practice.savedTeachers.map((t) => t.name), ['Leigh Brasington']);
      },
    );

    test('retreats whose talks have not synced yet wait for a chip', () async {
      await db.upsertRetreatRecords({
        400: {
          'name': 'Not synced',
          'start_date': '2020-01-01',
          'talks': [90],
        },
      });
      expect(
        (await source.explore()).courses.map((c) => c.id).first,
        'ds-retreat-400',
      );
      expect(
        (await source.explore(
          group: ContentGroup.talks,
        )).courses.map((c) => c.id),
        isNot(contains('ds-retreat-400')),
      );
    });

    test(
      'a chip needs synced talks before it can say "nothing here"',
      () async {
        final fresh = memoryDharmaSeedDb();
        addTearDown(fresh.close);
        await fresh.upsertRetreatRecords({
          1: {
            'name': 'R',
            'start_date': '2020-01-01',
            'talks': [1],
          },
        });
        final early = DharmaSeedSource(db: fresh);
        expect((await early.explore()).hasCatalogue, isTrue);
        expect(
          (await early.explore(group: ContentGroup.practice)).hasCatalogue,
          isFalse,
        );
      },
    );

    test('an empty database says there is no catalogue yet', () async {
      final empty = DharmaSeedSource(db: memoryDharmaSeedDb());
      final explore = await empty.explore();
      expect(explore.hasCatalogue, isFalse);
      expect(explore.isEmpty, isTrue);
    });
  });

  group('search', () {
    test('groups teachers, courses and talks, teachers first', () async {
      final results = await source.search('burbea');
      expect(results.teachers.map((t) => t.name), ['Rob Burbea']);
      expect(results.teachers.single.talkCount, 6);
      expect(results.courses, isEmpty); // "Burbea" is in no course text
      expect(results.talks.map((t) => t.title), contains('Settling'));

      final jhana = await source.search('jhana');
      expect(jhana.courses.map((c) => c.id), ['ds-retreat-100']);
      expect(
        jhana.talks.map((t) => t.title),
        containsAll(['Jhana basics', 'Untyped talk about jhana']),
      );
    });

    test('the length filter buckets are [min, max) in minutes', () async {
      // Give every talk a shared word and one length per bucket edge.
      await db.upsertTalkRecords({
        for (final id in [1, 2, 3, 4, 5, 6, 7, 8, 9])
          id: dsTalkRecord(
            'zen $id',
            teacher: 1,
            minutes: const {
              1: 9.99,
              2: 10,
              3: 19.99,
              4: 20,
              5: 29.99,
              6: 30,
              7: 44.99,
              8: 45,
              9: 120,
            }[id]!.toDouble(),
          ),
      });
      Future<List<String>> bucket(SessionLength length) async => [
        for (final t in (await source.search('zen', length: length)).talks)
          t.title,
      ]..sort();
      expect(await bucket(SessionLength.under10), ['zen 1']);
      expect(await bucket(SessionLength.from10to20), ['zen 2', 'zen 3']);
      expect(await bucket(SessionLength.from20to30), ['zen 4', 'zen 5']);
      expect(await bucket(SessionLength.from30to45), ['zen 6', 'zen 7']);
      expect(await bucket(SessionLength.over45), ['zen 8', 'zen 9']);
    });

    test('the length filter leaves teachers and courses alone', () async {
      final results = await source.search(
        'jhana',
        length: SessionLength.under10,
      );
      expect(results.courses.map((c) => c.id), ['ds-retreat-100']);
      expect(results.talks, isEmpty);
    });

    test('a talk with no recorded length is in no length bucket', () async {
      await db.upsertTalkRecords({
        50: {
          ...dsTalkRecord('zen unknown', teacher: 1),
          'duration_in_minutes': null,
        },
        51: dsTalkRecord('zen short', teacher: 1, minutes: 5),
      });
      final under10 = await source.search('zen', length: SessionLength.under10);
      expect(under10.talks.map((t) => t.title), ['zen short']);
      // Without a length filter it is still found.
      expect((await source.search('zen')).talks, hasLength(2));
    });

    test('teachers marked non-public are not searchable', () async {
      await db.upsertTeacherRecords({
        9: {'name': 'Hidden Teacher', 'non_public': true},
      });
      expect((await source.search('hidden')).teachers, isEmpty);
      await db.upsertTeacherRecords({
        10: {'name': 'Visible Teacher'},
      });
      expect((await source.search('visible')).teachers, hasLength(1));
    });

    test('no words, no results', () async {
      expect((await source.search('  ')).isEmpty, isTrue);
    });
  });

  group('teacher page', () {
    test('counts, courses and a page of talks, newest first', () async {
      final page = await source.teacherPage('ds-teacher-1', talkPage: 3);
      expect(page.teacher.name, 'Rob Burbea');
      expect(page.teacher.bio, 'Taught at Gaia House.');
      expect(page.teacher.pageUrl, 'https://dharmaseed.org/teacher/1/');
      // Burbea's own talks 1-4 and 9, plus co-teaching on talk 5.
      expect(page.teacher.talkCount, 6);
      expect(page.teacher.retreatCount, 2);
      expect(page.courses.map((c) => c.id), [
        'ds-retreat-200',
        'ds-retreat-100',
      ]);
      expect(page.talks.map((t) => t.title), [
        'Untyped talk about jhana',
        'Winter talk',
        'Metta',
      ]);
      expect(page.hasMoreTalks, isTrue);

      final more = await source.teacherTalks('ds-teacher-1', offset: 3);
      expect(more.map((t) => t.title), [
        'Breath meditation',
        'Jhana basics',
        'Settling',
      ]);
    });

    test('an unknown teacher is unavailable', () async {
      await expectLater(
        source.teacherPage('ds-teacher-99'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      await expectLater(
        source.teacherPage('ds-talk-1'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
    });
  });

  group('saving', () {
    test(
      'courses, talks and teachers go to the library through the router',
      () async {
        final router = ContentRouter(
          catalogue: const LocalCatalogue(),
          sources: [source],
        );
        expect(router.canSave('ds-retreat-100'), isTrue);
        expect(router.canSave('ds-teacher-1'), isTrue);
        expect(router.canSave('ds-talk-1'), isTrue);
        expect(router.canSave('ds-nonsense'), isFalse);
        expect(router.canSave('lib-other'), isFalse);

        expect(await router.isSaved('ds-retreat-100'), isFalse);
        await router.setSaved('ds-retreat-100', saved: true);
        await router.setSaved('ds-teacher-1', saved: true);
        await router.setSaved('ds-talk-1', saved: true);
        expect(await router.isSaved('ds-retreat-100'), isTrue);
        expect(await router.isSaved('ds-teacher-1'), isTrue);

        final entries = {
          for (final e in await library.entries()) e.sourceId: e,
        };
        expect(
          entries.keys,
          unorderedEquals(['ds-retreat-100', 'ds-teacher-1', 'ds-talk-1']),
        );
        expect(entries['ds-retreat-100']!.kind, LibraryKind.course);
        expect(entries['ds-retreat-100']!.title, 'Jhana Retreat');
        expect(entries['ds-retreat-100']!.group, LibraryGroup.practice);
        expect(entries['ds-teacher-1']!.kind, LibraryKind.teacher);
        expect(entries['ds-talk-1']!.kind, LibraryKind.single);
        // The old saved table is no longer written.
        expect(await db.savedIds(DsSavedKind.retreat), isEmpty);

        await router.setSaved('ds-retreat-100', saved: false);
        expect(await router.isSaved('ds-retreat-100'), isFalse);
        // Adding something that does not exist is a quiet no-op.
        await router.setSaved('ds-talk-99999', saved: true);
        expect(await library.contains('ds-talk-99999'), isFalse);
      },
    );
  });

  group('mapping', () {
    test(
      'a course carries its teacher, attribution and session details',
      () async {
        final pack = await source.pack('ds-retreat-100');
        expect(pack.teacher?.id, 'ds-teacher-1');
        expect(pack.teacher?.name, 'Rob Burbea');
        expect(pack.teacher?.bio, 'Taught at Gaia House.');
        expect(pack.teacher?.pageUrl, 'https://dharmaseed.org/teacher/1/');
        expect(pack.attribution?.source, 'Dharma Seed');
        expect(pack.attribution?.url, 'https://dharmaseed.org/retreats/100/');
        expect(pack.attribution?.licenseName, 'CC BY-NC-ND 4.0');
        expect(
          pack.attribution?.licenseUrl,
          'https://creativecommons.org/licenses/by-nc-nd/4.0/',
        );

        final first = pack.items.first;
        expect(first.kind, 'Guided meditation');
        expect(first.teacher, 'Rob Burbea');
        expect(first.durationMs, 570000);
        expect(first.date, '2014-03-01');
        // Same day, so morning before evening, by recording time then ID.
        expect(pack.items.map((i) => i.title), [
          'Settling',
          'Jhana basics',
          'Breath meditation',
          'Metta',
        ]);
      },
    );

    test(
      'a talk carries attribution for the player and track details',
      () async {
        final track = await source.track('ds-talk-2');
        expect(track.attribution?.creator, 'Rob Burbea');
        expect(track.attribution?.url, 'https://dharmaseed.org/talks/2/');
        expect(track.attribution?.licenseName, 'CC BY-NC-ND 4.0');
      },
    );
  });

  test('session lengths match half-open minute ranges', () {
    expect(
      SessionLength.under10.matches(const Duration(minutes: 9, seconds: 59)),
      isTrue,
    );
    expect(SessionLength.under10.matches(const Duration(minutes: 10)), isFalse);
    expect(
      SessionLength.from10to20.matches(const Duration(minutes: 10)),
      isTrue,
    );
    expect(SessionLength.over45.matches(const Duration(minutes: 45)), isTrue);
    expect(
      SessionLength.from30to45.matches(const Duration(minutes: 45)),
      isFalse,
    );
  });
}
