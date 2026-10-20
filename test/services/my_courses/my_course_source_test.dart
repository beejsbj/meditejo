import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/services/my_courses/my_course_source.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/fake_session_source.dart';
import '../../helpers/library_fixtures.dart';

MyItemDraft draft(String id) => MyItemDraft(
  id: id,
  title: 'Session $id',
  subtitle: 'Teacher of $id',
  coverUrl: 'https://img.test/$id.jpg',
  durationMs: 600000,
);

void main() {
  late LibraryDatabase db;
  late LibraryStore store;
  late FakeSessionSource upstream;
  late MyCourseSource source;

  setUp(() {
    db = memoryLibraryDb();
    store = LibraryStore(db);
    upstream = FakeSessionSource();
    source = MyCourseSource(db: db, library: store, sources: () => [upstream]);
  });
  tearDown(() async {
    source.dispose();
    store.dispose();
    await db.close();
  });

  List<String> ids(List<MyCourseLine> lines) => [
    for (final line in lines)
      line.isHeading ? '# ${line.heading}' : line.item!.id,
  ];

  group('the model', () {
    test('course IDs are my-course-<random> and only they are personal', () {
      final id = newMyCourseId();
      expect(id, startsWith('my-course-'));
      expect(isMyCourseId(id), isTrue);
      expect(newMyCourseId(), isNot(id));
      expect(isMyCourseId('ds-retreat-4496'), isFalse);
      expect(isCourseId('ds-retreat-4496'), isTrue);
      expect(isCourseId('yt-playlist-PL1'), isTrue);
      expect(isCourseId('ds-talk-60864'), isFalse);
    });

    test('cover choices are each session\'s artwork, once', () {
      final edit = MyCourseEdit(
        title: 't',
        lines: [
          MyCourseLine.session(draft('x-1')),
          const MyCourseLine.heading('Day 1'),
          MyCourseLine.session(draft('x-1')),
          MyCourseLine.session(draft('x-2')),
        ],
      );
      expect(edit.coverChoices, [
        'https://img.test/x-1.jpg',
        'https://img.test/x-2.jpg',
      ]);
    });
  });

  group('migration', () {
    test('a schema 2 library gains course tables and keeps its data', () async {
      useSystemSqlite();
      final scratch = Directory.systemTemp.createTempSync(
        'my_course_migration',
      );
      addTearDown(() => scratch.deleteSync(recursive: true));
      final file = File('${scratch.path}/library.sqlite');
      var fileDb = LibraryDatabase(NativeDatabase(file));
      var fileStore = LibraryStore(fileDb);
      await fileStore.add(
        const LibraryDraft(
          sourceId: 'ds-talk-1',
          kind: LibraryKind.single,
          title: 'My saved practice',
          group: LibraryGroup.practice,
        ),
      );
      await fileStore.savePosition('ds-talk-1', 60000, 600000);
      fileStore.dispose();
      await fileDb.close();

      final old = sqlite3.open(file.path);
      old.execute('DROP TABLE my_course_items');
      old.execute('DROP TABLE my_courses');
      old.execute('DROP TABLE session_contexts');
      old.execute('PRAGMA user_version = 2');
      old.dispose();

      fileDb = LibraryDatabase(NativeDatabase(file));
      fileStore = LibraryStore(fileDb);
      final fileSource = MyCourseSource(
        db: fileDb,
        library: fileStore,
        sources: () => const [],
      );
      addTearDown(() async {
        fileSource.dispose();
        fileStore.dispose();
        await fileDb.close();
      });
      expect((await fileStore.entries()).single.title, 'My saved practice');
      expect((await fileStore.resumePoint('ds-talk-1'))!.positionMs, 60000);
      expect(await fileSource.courses(), isEmpty);
      final id = await fileSource.create(title: 'After the upgrade');
      expect((await fileSource.courses()).single.id, id);
      await fileStore.noteSessionContext('ds-talk-1', id);
      expect(await fileStore.sessionContext('ds-talk-1'), id);
    });
  });

  group('as a content source', () {
    test('a new course is in the library as Practice, empty', () async {
      final id = await source.create(title: '  My jhāna curriculum ');
      final entry = (await store.entry(id))!;
      expect(entry.kind, LibraryKind.course);
      expect(entry.group, LibraryGroup.practice);
      expect(entry.title, 'My jhāna curriculum');
      expect(entry.itemCount, 0);
      final pack = await source.pack(id);
      expect(pack.title, 'My jhāna curriculum');
      expect(pack.items, isEmpty);
    });

    test('a blank title falls back to a name', () async {
      final id = await source.create(title: '   ');
      expect((await source.pack(id)).title, 'My course');
    });

    test('its sessions keep their own IDs, in order, under headings', () async {
      final id = await source.create(
        title: 'Curriculum',
        group: LibraryGroup.talks,
        lines: [
          MyCourseLine.session(draft('x-1')),
          const MyCourseLine.heading('Day 1'),
          MyCourseLine.session(draft('x-2')),
          MyCourseLine.session(draft('x-3')),
          const MyCourseLine.heading('Day 2'),
          MyCourseLine.session(draft('x-4')),
        ],
      );
      final pack = await source.pack(id);
      expect([for (final i in pack.items) i.id], ['x-1', 'x-2', 'x-3', 'x-4']);
      expect(
        [for (final i in pack.items) i.section],
        [null, 'Day 1', 'Day 1', 'Day 2'],
      );
      final first = pack.items.first;
      expect(first.type, TypeConstants.track);
      expect(first.path, '/tracks/x-1');
      expect(first.durationMs, 600000);
      expect(first.teacher, 'Teacher of x-1');
      expect(first.unavailable, isNull);
      expect(pack.subtitle, '4 sessions');
      expect((await store.entry(id))!.group, LibraryGroup.talks);
      expect((await store.entry(id))!.itemCount, 4);
    });

    test('the router sends my- IDs to it and lists it among packs', () async {
      final id = await source.create(
        title: 'Curriculum',
        lines: [MyCourseLine.session(draft('x-1'))],
      );
      final router = ContentRouter(sources: [upstream, source]);
      expect((await router.pack(id)).items.single.id, 'x-1');
      expect((await source.packTrackIds())[id], ['x-1']);
      expect((await source.searchPacks('curric')).single.id, id);
      expect(await source.searchPacks('nothing like it'), isEmpty);
    });

    test('a session re-read from its source refreshes the snapshot', () async {
      final id = await source.create(
        title: 'C',
        lines: [MyCourseLine.session(draft('x-1'))],
      );
      upstream.titles['x-1'] = 'Renamed upstream';
      expect((await source.pack(id)).items.single.title, 'Renamed upstream');
      // Stored, so the snapshot shown offline is the latest one.
      upstream.offline = true;
      expect((await source.pack(id)).items.single.title, 'Renamed upstream');
    });
  });

  group('adding, reordering and removing', () {
    test('adds to the end and skips sessions it already holds', () async {
      final id = await source.create(
        title: 'C',
        lines: [MyCourseLine.session(draft('x-1'))],
      );
      expect(await source.addItems(id, [draft('x-2'), draft('x-1')]), 1);
      expect(await source.addItems(id, [draft('x-2')]), 0);
      expect(
        [for (final i in (await source.pack(id)).items) i.id],
        ['x-1', 'x-2'],
      );
      expect((await store.entry(id))!.itemCount, 2);
      expect((await store.entry(id))!.durationMs, 1200000);
    });

    test('itemsFor reads a session, or a whole course\'s sessions', () async {
      upstream.addCourse('retreat', ['x-1', 'x-2', 'x-3']);
      final course = await source.itemsFor('x-course-retreat');
      expect([for (final d in course) d.id], ['x-1', 'x-2', 'x-3']);
      expect(course.first.kind, 'Guided Meditation');

      final single = await source.itemsFor('x-9');
      expect(single.single.title, 'Session x-9');
      expect(single.single.subtitle, 'Teacher of x-9');
      expect(single.single.durationMs, 600000);

      upstream.offline = true;
      final fallback = await source.itemsFor('x-9', fallback: draft('x-9'));
      expect(fallback.single.title, 'Session x-9');
    });

    test('lists which courses already hold what is being added', () async {
      final a = await source.create(
        title: 'A',
        lines: [MyCourseLine.session(draft('x-1'))],
      );
      final b = await source.create(title: 'B');
      final listed = await source.courses(containing: ['x-1']);
      expect({for (final c in listed) c.id: c.contains}, {a: true, b: false});
      expect(await source.coursesHolding('x-1'), [a]);
    });

    test('saving an edit reorders, removes, renames and regroups', () async {
      final id = await source.create(
        title: 'Before',
        lines: [
          MyCourseLine.session(draft('x-1')),
          MyCourseLine.session(draft('x-2')),
          MyCourseLine.session(draft('x-3')),
        ],
      );
      final edit = (await source.edit(id))!;
      expect(ids(edit.lines), ['x-1', 'x-2', 'x-3']);
      await source.save(
        id,
        edit.copyWith(
          title: 'After',
          description: '  Three sits a week ',
          coverUrl: 'https://img.test/x-3.jpg',
          group: LibraryGroup.talks,
          lines: [
            const MyCourseLine.heading('Week 1'),
            edit.lines[2],
            edit.lines[0],
            // A heading left blank is dropped.
            const MyCourseLine.heading('  '),
          ],
        ),
      );
      final saved = (await source.edit(id))!;
      expect(saved.title, 'After');
      expect(saved.description, 'Three sits a week');
      expect(saved.coverUrl, 'https://img.test/x-3.jpg');
      expect(saved.group, LibraryGroup.talks);
      expect(ids(saved.lines), ['# Week 1', 'x-3', 'x-1']);
      final entry = (await store.entry(id))!;
      expect(entry.displayTitle, 'After');
      expect(entry.group, LibraryGroup.talks);
      expect(entry.itemCount, 2);
      expect(entry.coverUrl, 'https://img.test/x-3.jpg');
    });

    test('removing a session takes it out of that course only', () async {
      final a = await source.create(
        title: 'A',
        lines: [
          MyCourseLine.session(draft('x-1')),
          MyCourseLine.session(draft('x-2')),
        ],
      );
      final b = await source.create(
        title: 'B',
        lines: [MyCourseLine.session(draft('x-1'))],
      );
      await source.removeItem(a, 'x-1');
      expect([for (final i in (await source.pack(a)).items) i.id], ['x-2']);
      expect([for (final i in (await source.pack(b)).items) i.id], ['x-1']);
    });

    test('a cover from elsewhere stays when a session is removed', () async {
      final id = await source.create(
        title: 'A',
        coverUrl: 'https://img.test/retreat.jpg',
        lines: [
          MyCourseLine.session(draft('x-1')),
          MyCourseLine.session(draft('x-2')),
        ],
      );
      await source.removeItem(id, 'x-1');
      expect((await source.edit(id))!.coverUrl, 'https://img.test/retreat.jpg');
    });

    test(
      'a copy keeps every heading, even one with no session after it',
      () async {
        final id = await source.create(
          title: 'A',
          lines: [
            const MyCourseLine.heading('One'),
            const MyCourseLine.heading('Two'),
            MyCourseLine.session(draft('x-1')),
            const MyCourseLine.heading('Last'),
          ],
        );
        final copy = await source.duplicate(id, title: 'A copy');
        expect(ids((await source.edit(copy))!.lines), [
          '# One',
          '# Two',
          'x-1',
          '# Last',
        ]);
      },
    );

    test('removing the session that supplied the cover resets it', () async {
      final id = await source.create(
        title: 'A',
        lines: [
          MyCourseLine.session(draft('x-1')),
          MyCourseLine.session(draft('x-2')),
        ],
      );
      final edit = (await source.edit(id))!;
      await source.save(
        id,
        edit.copyWith(coverUrl: 'https://img.test/x-2.jpg'),
      );

      await source.removeItem(id, 'x-1');
      expect((await source.edit(id))!.coverUrl, 'https://img.test/x-2.jpg');
      await source.removeItem(id, 'x-2');
      expect((await source.edit(id))!.coverUrl, isEmpty);
      expect((await store.entry(id))!.coverUrl, isNot(contains('x-2')));
    });

    test('renaming changes the course\'s own title', () async {
      final id = await source.create(title: 'Old');
      await source.rename(id, 'New');
      expect((await source.pack(id)).title, 'New');
      expect((await store.entry(id))!.displayTitle, 'New');
    });

    test('every change bumps the revision', () async {
      var bumps = 0;
      source.revision.addListener(() => bumps++);
      final id = await source.create(title: 'C');
      await source.addItems(id, [draft('x-1')]);
      await source.removeItem(id, 'x-1');
      await source.rename(id, 'D');
      expect(bumps, 4);
    });
  });

  group('duplicating a source course', () {
    test('copies it in order and leaves the original untouched', () async {
      final original = upstream.addCourse('retreat', ['x-1', 'x-2', 'x-3']);
      await store.add(
        const LibraryDraft(
          sourceId: 'x-course-retreat',
          kind: LibraryKind.course,
          title: 'Course retreat',
          group: LibraryGroup.talks,
        ),
      );
      final copy = await source.duplicate(
        'x-course-retreat',
        title: 'Course retreat (my copy)',
      );
      expect(isMyCourseId(copy), isTrue);
      final pack = await source.pack(copy);
      expect(pack.title, 'Course retreat (my copy)');
      expect(pack.description, 'About retreat');
      expect(pack.coverUrl, 'https://img.test/retreat.jpg');
      expect([for (final i in pack.items) i.id], ['x-1', 'x-2', 'x-3']);
      expect((await store.entry(copy))!.group, LibraryGroup.talks);

      // Trim the copy; the retreat is as it was.
      await source.removeItem(copy, 'x-2');
      expect(upstream.packs['x-course-retreat'], original);
      expect((await store.entry('x-course-retreat'))!.title, 'Course retreat');
    });

    test('a personal course copies with its headings', () async {
      final id = await source.create(
        title: 'Mine',
        lines: [
          const MyCourseLine.heading('Day 1'),
          MyCourseLine.session(draft('x-1')),
          const MyCourseLine.heading('Day 2'),
          MyCourseLine.session(draft('x-2')),
        ],
      );
      final copy = await source.duplicate(id, title: 'Mine again');
      expect(ids((await source.edit(copy))!.lines), [
        '# Day 1',
        'x-1',
        '# Day 2',
        'x-2',
      ]);
    });
  });

  group('sessions gone upstream', () {
    test(
      'show as unavailable from their snapshot; the course still opens',
      () async {
        final id = await source.create(
          title: 'C',
          lines: [
            MyCourseLine.session(draft('x-1')),
            MyCourseLine.session(draft('x-2')),
          ],
        );
        upstream.gone.add('x-1');
        final pack = await source.pack(id);
        expect(pack.items.first.unavailable, isTrue);
        expect(pack.items.first.title, 'Session x-1');
        expect(pack.items.last.unavailable, isNull);
        // Progress counts only what can be played.
        expect((await source.packTrackIds())[id], ['x-2']);
        expect([for (final i in pack.playableTracks) i.id], ['x-2']);
        expect((await source.edit(id))!.lines.first.unavailable, isTrue);
      },
    );

    test('being offline is not being gone', () async {
      final id = await source.create(
        title: 'C',
        lines: [MyCourseLine.session(draft('x-1'))],
      );
      upstream.offline = true;
      final item = (await source.pack(id)).items.single;
      expect(item.unavailable, isNull);
      expect(item.title, 'Session x-1');
    });

    test('a session the source could not be asked about is not gone', () async {
      final id = await source.create(
        title: 'C',
        lines: [MyCourseLine.session(draft('x-1'))],
      );
      upstream.unreachable = true;
      final item = (await source.pack(id)).items.single;
      expect(item.unavailable, isNull);
      expect((await source.edit(id))!.lines.single.unavailable, isNot(true));
    });

    test('a session that comes back is available again', () async {
      final id = await source.create(
        title: 'C',
        lines: [MyCourseLine.session(draft('x-1'))],
      );
      upstream.gone.add('x-1');
      expect((await source.pack(id)).items.single.unavailable, isTrue);
      upstream.gone.clear();
      expect((await source.pack(id)).items.single.unavailable, isNull);
    });

    test('a gone session is not offered when adding a course', () async {
      final id = await source.create(
        title: 'C',
        lines: [
          MyCourseLine.session(draft('x-1')),
          MyCourseLine.session(draft('x-2')),
        ],
      );
      upstream.gone.add('x-1');
      final items = await source.itemsFor(id);
      expect([for (final d in items) d.id], ['x-2']);
    });
  });

  group('deleting', () {
    test(
      'removes the course only: sessions, places and entries stay',
      () async {
        await store.add(
          const LibraryDraft(
            sourceId: 'x-1',
            kind: LibraryKind.single,
            title: 'Saved single',
            group: LibraryGroup.practice,
          ),
        );
        await store.savePosition('x-1', 60000, 600000);
        final id = await source.create(
          title: 'C',
          lines: [MyCourseLine.session(draft('x-1'))],
        );
        await store.noteSessionContext('x-1', id);
        await source.delete(id);

        expect(await store.entry(id), isNull);
        expect(await source.courses(), isEmpty);
        expect(
          () => source.pack(id),
          throwsA(isA<CatalogueEntryUnavailable>()),
        );
        expect((await store.entry('x-1'))!.title, 'Saved single');
        expect((await store.resumePoint('x-1'))!.positionMs, 60000);
        expect(await store.sessionContext('x-1'), isNull);
      },
    );
  });

  group('a session in several courses', () {
    test('counts in each: completion belongs to the session', () async {
      final a = await source.create(
        title: 'A',
        lines: [
          MyCourseLine.session(draft('x-1')),
          MyCourseLine.session(draft('x-2')),
        ],
      );
      final b = await source.create(
        title: 'B',
        lines: [MyCourseLine.session(draft('x-1'))],
      );
      final tracks = await source.packTrackIds();
      expect(tracks[a], contains('x-1'));
      expect(tracks[b], ['x-1']);
    });

    test('remembers the course it was last opened from', () async {
      final a = await source.create(title: 'A');
      final b = await source.create(title: 'B');
      await store.noteSessionContext('x-1', a);
      await store.noteSessionContext('x-1', b);
      expect(await store.sessionContext('x-1'), b);
    });
  });
}
