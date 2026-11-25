import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_migration.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/library/starter_set.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/src/youtube_api.g.dart';

import '../../helpers/dharma_seed_catalogue.dart';
import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/library_fixtures.dart';
import '../../helpers/youtube_fake.dart';

/// The four starter retreats and the starter talk, shaped like Dharma Seed's
/// own records: Rob Burbea's retreat sittings are filed as "Talk".
Future<void> seedStarterCatalogue(DharmaSeedDatabase ds) async {
  await ds.upsertTeacherRecords({
    1: {'name': 'Rob Burbea', 'bio': '', 'photo': ''},
  });
  await ds.upsertRetreatRecords({
    4496: {
      'name': 'Practising the Jhānas',
      'start_date': '2019-03-01',
      'talks': [60863, 60864],
    },
    1084: {
      'name': 'The Loving Kindness (Metta) Retreat',
      'start_date': '2010-03-01',
      'talks': [10841],
    },
    1183: {
      'name': 'The Art Of Concentration (Samatha Meditation)',
      'start_date': '2008-03-01',
      'talks': [11831],
    },
    1308: {
      'name': 'Samatha Meditation',
      'start_date': '2007-03-01',
      'talks': [13081],
    },
  });
  await ds.upsertTalkRecords({
    60863: dsTalkRecord('Settling', teacher: 1, retreat: 4496, type: 'Talk'),
    60864: dsTalkRecord(
      'Developing Piti, Developing Focus, Developing Wellbeing',
      teacher: 1,
      retreat: 4496,
      type: 'Talk',
      minutes: 89,
    ),
    10841: dsTalkRecord('Metta', teacher: 1, retreat: 1084, type: 'Talk'),
    11831: dsTalkRecord('Concentration', teacher: 1, retreat: 1183),
    13081: dsTalkRecord('Samatha', teacher: 1, retreat: 1308, type: 'Talk'),
  });
}

/// A library whose insert fails on the nth call, as a dying disk would.
class _FlakyLibrary extends LibraryDatabase {
  _FlakyLibrary({this.failOnInsert}) : super(NativeDatabase.memory());

  int? failOnInsert;
  var _inserts = 0;

  @override
  Future<void> insertEntry(LibraryEntriesCompanion entry) {
    if (++_inserts == failOnInsert) throw StateError('disk I/O error');
    return super.insertEntry(entry);
  }
}

/// What pass 4 added to the starter set, in the set's order.
const _since2 = [
  'yt-video-9c736DThL_M',
  'yt-playlist-PLND1JCRq8VuhiAkaZ4UfmMwDq0c3a_cDn',
  'yt-playlist-PLbmYHvGI-YStGL1bzkuxj_xqFvHzvjxEY',
];

void main() {
  late LibraryDatabase db;
  late DharmaSeedDatabase ds;

  setUp(() async {
    db = memoryLibraryDb();
    ds = memoryDharmaSeedDb();
    await seedStarterCatalogue(ds);
  });
  tearDown(() async {
    await db.close();
    await ds.close();
  });

  Future<LibraryStore> openStore() async {
    final store = LibraryStore(
      db,
      prepare: (d) async {
        await migrateDharmaSeedSaves(d, ds);
        await reclassifyLibraryDefaults(d);
        await seedStarterSet(d, ds);
        await addNewStarterItems(d, ds);
      },
    );
    addTearDown(store.dispose);
    return store;
  }

  group('Dharma Seed classification defaults', () {
    test(
      'a retreat is Practice even when every recording is a "Talk"',
      () async {
        final source = DharmaSeedSource(db: ds);
        final draft = (await source.libraryDraft('ds-retreat-4496'))!;
        expect(draft.group, LibraryGroup.practice);
        expect(draft.kind, LibraryKind.course);
      },
    );

    test('a single talk follows its own recording type', () async {
      await ds.upsertTalkRecords({
        1: dsTalkRecord('Sit', teacher: 1, type: 'Meditation'),
        2: dsTalkRecord('Chant', teacher: 1, type: 'Chanting'),
        3: dsTalkRecord('Talk', teacher: 1, type: 'Talk'),
        4: dsTalkRecord('Questions', teacher: 1, type: 'Q & A'),
        5: dsTalkRecord('Other', teacher: 1, type: 'Other'),
        6: dsTalkRecord('Untyped', teacher: 1, type: ''),
      });
      final source = DharmaSeedSource(db: ds);
      Future<LibraryGroup> groupOf(int id) async =>
          (await source.libraryDraft('ds-talk-$id'))!.group;

      expect(await groupOf(1), LibraryGroup.practice);
      expect(await groupOf(2), LibraryGroup.practice);
      expect(await groupOf(3), LibraryGroup.talks);
      expect(await groupOf(4), LibraryGroup.talks);
      expect(await groupOf(5), LibraryGroup.talks);
      expect(await groupOf(6), LibraryGroup.talks);
    });
  });

  group('one-time reclassification', () {
    Future<void> insert(
      String id, {
      required String detected,
      String? override,
      String kind = 'course',
    }) => db.insertEntry(
      LibraryEntriesCompanion.insert(
        sourceId: id,
        kind: kind,
        detectedGroup: Value(detected),
        groupOverride: Value(override),
        title: id,
        addedAt: DateTime.utc(2026, 10, 18),
      ),
    );

    test('moves retreats the user has not overridden to Practice', () async {
      await insert('ds-retreat-4496', detected: 'talks');
      await insert('ds-retreat-1084', detected: 'talks');
      await insert('ds-retreat-1183', detected: 'talks', override: 'talks');
      await insert('ds-talk-60864', detected: 'talks', kind: 'single');
      await insert('lib-course-abc', detected: 'talks');
      await insert('ds-retreat-1308', detected: 'practice', override: 'talks');

      await reclassifyLibraryDefaults(db);

      Future<String> detected(String id) async =>
          (await db.entryById(id))!.detectedGroup;
      expect(await detected('ds-retreat-4496'), 'practice');
      expect(await detected('ds-retreat-1084'), 'practice');
      for (final id in ['ds-retreat-1183', 'ds-retreat-1308']) {
        expect(
          (await db.entryById(id))!.groupOverride,
          'talks',
          reason: '$id: the user\'s own choice stands',
        );
      }
      expect(await detected('ds-retreat-1183'), 'talks', reason: 'untouched');
      expect(await detected('ds-talk-60864'), 'talks');
      expect(await detected('lib-course-abc'), 'talks');
    });

    test('runs once: a later move back to Talks is not undone', () async {
      await insert('ds-retreat-4496', detected: 'talks');
      await reclassifyLibraryDefaults(db);
      await db.updateEntry(
        'ds-retreat-4496',
        const LibraryEntriesCompanion(detectedGroup: Value('talks')),
      );
      await reclassifyLibraryDefaults(db);
      expect((await db.entryById('ds-retreat-4496'))!.detectedGroup, 'talks');
    });

    test(
      'through the store, so the library lists them under Practice',
      () async {
        await insert('ds-retreat-4496', detected: 'talks');
        final store = await openStore();
        final entry = (await store.entry('ds-retreat-4496'))!;
        expect(entry.group, LibraryGroup.practice);
      },
    );
  });

  group('starter set', () {
    test('seeds an empty library once, in order, from the catalogue', () async {
      final store = await openStore();
      final entries = await store.entries();

      expect(entries.map((e) => e.sourceId).toSet(), {
        for (final item in starterSet) item.id,
      });
      expect(entries.take(5).map((e) => e.sourceId), [
        'ds-retreat-4496',
        'ds-retreat-1084',
        'ds-retreat-1183',
        'ds-retreat-1308',
        'ds-talk-60864',
      ], reason: 'the first starter item leads the library');
      for (final id in [
        'ds-retreat-4496',
        'ds-retreat-1084',
        'ds-retreat-1183',
        'ds-retreat-1308',
      ]) {
        final e = entries.firstWhere((e) => e.sourceId == id);
        expect(e.kind, LibraryKind.course);
        expect(e.group, LibraryGroup.practice, reason: id);
      }
      final jhana = entries.firstWhere((e) => e.sourceId == 'ds-retreat-4496');
      expect(jhana.title, 'Practising the Jhānas');
      expect(jhana.itemCount, 2, reason: 'described from the catalogue');
      final talk = entries.firstWhere((e) => e.sourceId == 'ds-talk-60864');
      expect(talk.kind, LibraryKind.single);
      expect(talk.durationMs, 89 * 60 * 1000);
      expect(
        talk.group,
        LibraryGroup.talks,
        reason: 'the talk follows its own label ("Talk")',
      );
    });

    test('includes the two YouTube playlists as Practice courses', () async {
      const vervaeke = 'yt-playlist-PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3';
      const qualia = 'yt-playlist-PLbmYHvGI-YSvnpbh3ppQqcG72lpw4aQdE';
      final entries = await (await openStore()).entries();

      for (final id in [vervaeke, qualia]) {
        final e = entries.firstWhere((e) => e.sourceId == id);
        expect(e.kind, LibraryKind.course, reason: id);
        expect(e.group, LibraryGroup.practice, reason: id);
      }
      expect(starterSet.map((i) => i.id), containsAll([vervaeke, qualia]));
    });

    test('a seeded YouTube course opens before its background fetch', () async {
      const vervaeke = 'PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3';
      final store = await openStore();
      await store.entries();
      final api = FakeYoutubeApi()
        ..playlists[vervaeke] = playlist(
          [item(videoA), item(videoB)],
          title: 'Meditating with John Vervaeke',
          uploader: "John Vervaeke's Lectern",
        );
      final source = YoutubeSource(db: db, library: store, api: api);

      final initial = await source.pack('yt-playlist-$vervaeke');
      expect(initial.items, isEmpty);
      await source.refresh('yt-playlist-$vervaeke');
      final pack = await source.pack('yt-playlist-$vervaeke');

      expect(api.playlistCalls, hasLength(1));
      expect(pack.items.map((i) => i.id), [
        'yt-video-$videoA',
        'yt-video-$videoB',
      ]);
    });

    test(
      'a single marked Meditation follows that label into Practice',
      () async {
        await ds.upsertTalkRecords({
          60864: dsTalkRecord(
            'Developing Piti',
            teacher: 1,
            retreat: 4496,
            type: 'Meditation',
          ),
        });
        final entries = await (await openStore()).entries();
        expect(
          entries.firstWhere((e) => e.sourceId == 'ds-talk-60864').group,
          LibraryGroup.practice,
        );
      },
    );

    test('never re-adds what the user removed', () async {
      final store = await openStore();
      await store.remove('ds-retreat-4496');
      await store.remove('ds-talk-60864');

      // The next launch: a fresh store over the same file.
      final again = await openStore();
      final ids = (await again.entries()).map((e) => e.sourceId);
      expect(ids, isNot(contains('ds-retreat-4496')));
      expect(ids, isNot(contains('ds-talk-60864')));
      expect(ids, contains('ds-retreat-1084'));
    });

    test('an emptied library stays empty', () async {
      final store = await openStore();
      for (final e in await store.entries()) {
        await store.remove(e.sourceId);
      }
      expect(await (await openStore()).entries(), isEmpty);
    });

    test('a library that already has things is left alone', () async {
      await db.insertEntry(
        LibraryEntriesCompanion.insert(
          sourceId: 'ds-retreat-4496',
          kind: 'course',
          title: 'Mine',
          addedAt: DateTime.utc(2026, 10, 18),
        ),
      );
      final store = await openStore();
      final entries = await store.entries();
      // Pass 4: an install from before the starter set still gets the items
      // added since (their `since` is 2), as an update brings them to every
      // install; the first set stays out.
      expect(entries.map((e) => e.sourceId).toSet(), {
        'ds-retreat-4496',
        ..._since2,
      });

      for (final e in await store.entries()) {
        await store.remove(e.sourceId);
      }
      expect(
        await (await openStore()).entries(),
        isEmpty,
        reason: 'the flag was set on that first run, so no later seeding',
      );
    });

    test(
      'an interruption mid-seed leaves nothing, then seeds in full',
      () async {
        final flaky = _FlakyLibrary(failOnInsert: 3);
        addTearDown(flaky.close);

        await seedStarterSet(flaky, ds);
        expect(await flaky.allEntries(), isEmpty, reason: 'rolled back');
        expect(await flaky.metaValue('starter_seeded'), isNull);

        flaky.failOnInsert = null;
        await seedStarterSet(flaky, ds);
        expect(await flaky.allEntries(), hasLength(starterSet.length));
        expect(await flaky.metaValue('starter_seeded'), isNotNull);
      },
    );

    test('works without the catalogue, under the listed titles', () async {
      final empty = memoryDharmaSeedDb();
      addTearDown(empty.close);
      await seedStarterSet(db, empty);
      final rows = await db.allEntries();
      expect(rows, hasLength(starterSet.length));
      final jhana = rows.firstWhere((r) => r.sourceId == 'ds-retreat-4496');
      expect(jhana.title, 'Practising the Jhānas');
      expect(jhana.itemCount, 32);
      expect(jhana.detectedGroup, 'practice');
    });

    test('takes no network: the catalogue alone describes the items', () async {
      // A source with no sync cannot reach out; seeding must not need one.
      await seedStarterSet(db, ds);
      expect(await db.allEntries(), hasLength(starterSet.length));
    });

    group('items added later (pass 4)', () {
      final firstSet = [
        for (final item in starterSet)
          if (item.since == 1) item,
      ];

      test('the set holds the new courses and the single', () {
        expect(starterSetVersion, 2);
        expect([
          for (final i in starterSet)
            if (i.since == 2) i.id,
        ], _since2);
        final single = starterSet.firstWhere((i) => i.id == _since2.first);
        expect(single.kind, LibraryKind.single);
        expect(single.group, LibraryGroup.practice);
      });

      test(
        'a fresh install seeds them, opens the single, records v2',
        () async {
          final store = await openStore();
          final entries = await store.entries();
          final ids = entries.map((e) => e.sourceId).toList();
          expect(ids, containsAll(_since2));
          expect(ids.toSet(), hasLength(ids.length), reason: 'no doubles');
          expect(await db.metaValue('starter_version'), '2');

          // The single has a placeholder row, so it opens before any lookup.
          final source = YoutubeSource(
            db: db,
            library: store,
            api: FakeYoutubeApi(),
          );
          final track = await source.track('yt-video-9c736DThL_M');
          expect(track.title, 'Mindfulness Meditation - Find Your Center');
          expect(track.subtitle, "John Vervaeke's Lectern");
          // Each new course has its due playlist row.
          for (final id in _since2.skip(1)) {
            expect(
              await db.youtubePlaylist(id.substring('yt-playlist-'.length)),
              isNotNull,
              reason: id,
            );
          }
        },
      );

      test('an install seeded with the first set gets them once', () async {
        // Seeded weeks before the update.
        await seedStarterSet(
          db,
          ds,
          items: firstSet,
          version: 1,
          clock: () => DateTime.now().subtract(const Duration(days: 30)),
        );
        await db.setMeta('starter_version', '1');
        final before = (await db.allEntries()).length;
        expect(before, firstSet.length);

        final store = await openStore();
        final entries = await store.entries();
        expect(entries, hasLength(before + _since2.length));
        expect(
          entries.take(3).map((e) => e.sourceId),
          _since2,
          reason: 'new items lead the library, in the set\'s order',
        );
        expect(await db.metaValue('starter_version'), '2');

        // Removed, it stays removed.
        await store.remove(_since2.last);
        final again = await openStore();
        expect(
          (await again.entries()).map((e) => e.sourceId),
          isNot(contains(_since2.last)),
        );
      });

      test('an item the user already imported is not added again', () async {
        await seedStarterSet(db, ds, items: firstSet, version: 1);
        const qualia2 = 'PLbmYHvGI-YStGL1bzkuxj_xqFvHzvjxEY';
        await db.insertEntry(
          LibraryEntriesCompanion.insert(
            sourceId: 'yt-playlist-$qualia2',
            kind: 'course',
            title: 'Mine',
            addedAt: DateTime.utc(2026, 11, 1),
          ),
        );
        await db
            .into(db.youtubePlaylists)
            .insert(
              YoutubePlaylistsCompanion.insert(
                playlistId: qualia2,
                title: 'Qualia Mastery II',
                uploader: 'Qualia Research Institute',
                thumbnail: 'https://i.ytimg.com/vi/x/hq.jpg',
                videoIds: '["aaaaaaaaaaa"]',
                lastCheckedAt: DateTime.utc(2026, 11, 1),
              ),
            );

        await addNewStarterItems(db, ds);
        final rows = await db.allEntries();
        expect(
          rows.where((r) => r.sourceId == 'yt-playlist-$qualia2'),
          hasLength(1),
        );
        expect(
          rows.firstWhere((r) => r.sourceId == 'yt-playlist-$qualia2').title,
          'Mine',
        );
        final kept = await db.youtubePlaylist(qualia2);
        expect(kept!.videoIds, '["aaaaaaaaaaa"]', reason: 'its row is kept');
        expect(rows.map((r) => r.sourceId), containsAll(_since2));
      });

      test(
        'without YouTube nothing is added, and it does not ask again',
        () async {
          await seedStarterSet(db, ds, items: firstSet, version: 1);
          await addNewStarterItems(db, ds, includeYoutube: false);
          expect(await db.allEntries(), hasLength(firstSet.length));
          expect(await db.metaValue('starter_version'), '2');
        },
      );

      test('waits for the first seed', () async {
        await addNewStarterItems(db, ds);
        expect(await db.allEntries(), isEmpty);
        expect(await db.metaValue('starter_version'), isNull);
      });

      test(
        'the single fills in its picture and length when looked up',
        () async {
          final store = await openStore();
          await store.entries();
          const id = '9c736DThL_M';
          final api = FakeYoutubeApi()
            ..videos[id] = YoutubeVideo(
              videoId: id,
              title: 'Mindfulness Meditation - Find Your Center',
              uploader: "John Vervaeke's Lectern",
              durationSeconds: 1920,
              thumbnail: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
              description: 'Practice #1.',
            );
          final source = YoutubeSource(db: db, library: store, api: api);

          expect(await source.describe('yt-video-$id'), isTrue);
          final row = await db.youtubeVideo(id);
          expect(row!.durationSeconds, 1920);
          expect(row.thumbnail, 'https://i.ytimg.com/vi/$id/hqdefault.jpg');
          expect(row.description, 'Practice #1.');
          final entry = (await store.entries()).firstWhere(
            (e) => e.sourceId == 'yt-video-$id',
          );
          expect(entry.durationMs, 1920 * 1000);
          expect(entry.coverUrl, 'https://i.ytimg.com/vi/$id/hqdefault.jpg');
        },
      );
    });
  });
}
