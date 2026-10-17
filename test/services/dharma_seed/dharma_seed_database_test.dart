import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';

import '../../helpers/dharma_seed_fake_api.dart';

Map<int, Map<String, Object?>> _records(String fixture) => {
  for (final MapEntry(:key, :value)
      in (dsFixture(fixture)['items'] as Map).entries)
    int.parse('$key'): (value as Map).cast<String, Object?>(),
};

void main() {
  late DharmaSeedDatabase db;

  setUp(() async {
    db = memoryDharmaSeedDb();
    await db.upsertTeacherRecords(_records('teachers_detail.json'));
    await db.upsertRetreatRecords(_records('retreats_detail.json'));
    await db.upsertTalkRecords(_records('talks_detail.json'));
  });
  tearDown(() => db.close());

  group('records', () {
    test('talks keep duration, kind and every teacher', () async {
      final talk = (await db.talkById(97073))!;
      expect(talk.title, 'GM Standing');
      expect(talk.recordingType, 'Meditation');
      expect(talk.durationMs, greaterThan(0));
      expect(talk.audioUrl, startsWith('/talks/97073/'));

      final standalone = (await db.talkById(99944))!;
      expect(standalone.retreatId, 6689);
      expect(standalone.durationMs, (24.63825850340136 * 60000).round());
    });

    test('teachers store no contact details', () async {
      final teacher = (await db.teacherById(210))!;
      expect(teacher.name, 'Rob Burbea');
      expect(teacher.photo, 'photo.png');
      expect(teacher.bio, startsWith('ROB BURBEA'));
      expect(teacher.toJson().keys, isNot(contains('address1')));
    });

    test('contact fields in a teacher record are never written', () async {
      const secret = 'private-person@example.invalid';
      await db.upsertTeacherRecords({
        9001: {
          'id': 9001,
          'name': 'Contact Test',
          'bio': 'A bio',
          'address1': secret,
          'address2': '1 Private Lane',
          'city': 'Hidden City',
          'postal_code': '99999',
          'website': 'https://example.invalid/',
          'photo': '',
          'monastic': false,
          'non_public': false,
        },
      });

      for (final table in ['ds_teachers', 'ds_teachers_fts']) {
        final rows = await db.customSelect('SELECT * FROM $table').get();
        final dump = [for (final r in rows) r.data.values.join('|')].join('\n');
        expect(dump, isNot(contains(secret)), reason: table);
        expect(dump, isNot(contains('Private Lane')), reason: table);
        expect(dump, isNot(contains('Hidden City')), reason: table);
      }
      expect((await db.teacherById(9001))!.name, 'Contact Test');
    });

    test('a retreat lists talks by recording date, then ID', () async {
      final talks = await db.talksOfRetreat(6689);
      expect(talks.map((t) => t.id), [
        95073,
        95232,
        95421,
        95545,
        95800,
        95953,
        99944,
      ]);
      expect(
        DharmaSeedDatabase.talkIdsOf((await db.retreatById(6689))!),
        contains(90000001),
      );
    });

    test('deleting removes records and their search rows', () async {
      await db.deleteRecords(DsKind.talks, [95073]);
      expect(await db.talkById(95073), isNull);
      expect(await db.searchTalks('renewing'), isEmpty);
    });

    test('deletes thousands of IDs in one call', () async {
      await db.deleteRecords(
        DsKind.talks,
        List.generate(41542, (i) => i + 1),
      );
      expect(await db.countOf(DsKind.talks), 9);
    });
  });

  group('full-text search', () {
    test('matches word prefixes in titles', () async {
      final hits = await db.searchTalks('eightfold');
      expect(hits.map((h) => h.talk.id), [95232]);
      expect(hits.single.teacher?.name, 'Jill Shepherd');

      final prefix = await db.searchTalks('wise vie');
      expect(
        prefix.map((h) => h.talk.id),
        containsAll([95421, 95545, 95800]),
      );
    });

    test('finds talks by teacher name', () async {
      final hits = await db.searchTalks('shepherd');
      expect(hits, hasLength(7));
    });

    test('ignores accents', () async {
      final hits = await db.searchTalks('deplaisantes');
      expect(hits.map((h) => h.talk.id), [99974]);
    });

    test('ranks title matches first', () async {
      final hits = await db.searchTalks('intention');
      expect(hits.first.talk.id, 95953); // "Wise Intention part1"
    });

    test('filters by length and kind', () async {
      final short = await db.searchTalks(
        'shepherd',
        filter: const DsTalkFilter(maxDuration: Duration(minutes: 21)),
      );
      expect(short.map((h) => h.talk.id), unorderedEquals([95545, 95232]));

      final mid = await db.searchTalks(
        'shepherd',
        filter: const DsTalkFilter(
          minDuration: Duration(minutes: 25),
          maxDuration: Duration(minutes: 30),
        ),
      );
      expect(mid.map((h) => h.talk.id), unorderedEquals([95953, 95073]));

      final none = await db.searchTalks(
        'shepherd',
        filter: const DsTalkFilter(recordingTypes: {'Meditation'}),
      );
      expect(none, isEmpty);
    });

    test('user text never becomes FTS syntax', () async {
      expect(DharmaSeedDatabase.matchExpression('  '), isNull);
      expect(DharmaSeedDatabase.matchExpression('"*()-:^'), isNull);
      expect(
        DharmaSeedDatabase.matchExpression('wise OR NOT "view"'),
        '"wise"* "OR"* "NOT"* "view"*',
      );
      expect(await db.searchTalks('wise: view ('), isNotEmpty);
    });

    test('searches retreats and teachers', () async {
      final retreats = await db.searchRetreats('auckland');
      expect(retreats.map((r) => r.id), [6689]);

      final teachers = await db.searchTeachers('rob');
      expect(teachers.first.id, 210);
      final byBio = await db.searchTeachers('emptiness');
      expect(byBio.map((t) => t.id), [210]);
    });

    test('talk search follows a teacher rename', () async {
      final records = _records('teachers_detail.json');
      records[637] = {...records[637]!, 'name': 'Jill Renamed'};
      await db.upsertTeacherRecords(records);

      expect(await db.searchTalks('shepherd'), isEmpty);
      expect(await db.searchTalks('renamed'), hasLength(7));
    });
  });

  group('saves and sync bookkeeping', () {
    test('saved retreats and teachers, newest first', () async {
      await db.setSaved(DsSavedKind.retreat, 6689, saved: true);
      await db.setSaved(DsSavedKind.retreat, 7000, saved: true);
      await db.setSaved(DsSavedKind.teacher, 210, saved: true);

      expect(await db.savedIds(DsSavedKind.retreat), [7000, 6689]);
      expect(await db.savedIds(DsSavedKind.teacher), [210]);

      await db.setSaved(DsSavedKind.retreat, 7000, saved: false);
      expect(await db.savedIds(DsSavedKind.retreat), [6689]);
    });

    test('the queue hands out IDs newest first and survives dequeues', () async {
      await db.enqueue(DsKind.talks, [3, 1, 2, 2]);
      expect(await db.queuedCount(DsKind.talks), 3);
      expect(await db.nextQueued(DsKind.talks, 2), [3, 2]);
      await db.dequeue(DsKind.talks, [3, 2]);
      expect(await db.nextQueued(DsKind.talks, 2), [1]);
      expect(await db.queuedCount(DsKind.teachers), 0);
    });
  });
}
