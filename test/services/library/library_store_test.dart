import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_migration.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';

import '../../helpers/dharma_seed_catalogue.dart';
import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/library_fixtures.dart';

void main() {
  late LibraryDatabase db;
  late LibraryStore store;
  var now = DateTime.utc(2026, 10, 1);

  setUp(() {
    db = memoryLibraryDb();
    now = DateTime.utc(2026, 10, 1);
    store = LibraryStore(db, clock: () => now);
  });
  tearDown(() => db.close());

  LibraryDraft draft(
    String id, {
    LibraryKind kind = LibraryKind.course,
    LibraryGroup group = LibraryGroup.practice,
    String title = 'A course',
  }) => LibraryDraft(sourceId: id, kind: kind, title: title, group: group);

  group('entries', () {
    test('add keeps what was given and refuses a duplicate', () async {
      expect(await store.add(draft('ds-retreat-1', title: 'Jhana')), isTrue);
      expect(await store.add(draft('ds-retreat-1', title: 'Changed')), isFalse);

      final entry = (await store.entry('ds-retreat-1'))!;
      expect(entry.title, 'Jhana');
      expect(entry.kind, LibraryKind.course);
      expect(entry.group, LibraryGroup.practice);
      expect(entry.addedAt.toUtc(), DateTime.utc(2026, 10, 1));
      expect(await store.contains('ds-retreat-1'), isTrue);
      expect(await store.contains('ds-retreat-2'), isFalse);
    });

    test('lists the most recently added or played first', () async {
      await store.add(draft('a'));
      now = DateTime.utc(2026, 10, 2);
      await store.add(draft('b'));
      now = DateTime.utc(2026, 10, 3);
      await store.add(draft('c'));
      expect((await store.entries()).map((e) => e.sourceId), ['c', 'b', 'a']);

      // Playing the oldest brings it to the front.
      now = DateTime.utc(2026, 10, 4);
      await store.touchPlayed(['a', 'not-in-library']);
      expect((await store.entries()).map((e) => e.sourceId), ['a', 'c', 'b']);
    });

    test('the user can override Practice/Talks and go back to the detected one', () async {
      await store.add(draft('x', group: LibraryGroup.talks));
      expect((await store.entry('x'))!.group, LibraryGroup.talks);

      await store.setGroup('x', LibraryGroup.practice);
      var entry = (await store.entry('x'))!;
      expect(entry.group, LibraryGroup.practice);
      expect(entry.detectedGroup, LibraryGroup.talks);
      expect(await store.groupOf('x'), LibraryGroup.practice);

      await store.setGroup('x', null);
      entry = (await store.entry('x'))!;
      expect(entry.group, LibraryGroup.talks);
    });

    test('a title override changes what is shown, not what the source said', () async {
      await store.add(draft('x', title: 'Source title'));
      await store.setTitle('x', '  My name  ');
      var entry = (await store.entry('x'))!;
      expect(entry.displayTitle, 'My name');
      expect(entry.title, 'Source title');

      await store.setTitle('x', '   ');
      entry = (await store.entry('x'))!;
      expect(entry.displayTitle, 'Source title');
    });

    test('remove and snapshot updates', () async {
      await store.add(draft('x'));
      await store.updateSnapshot('x', itemCount: 12, durationMs: 5000, subtitle: 'new');
      final entry = (await store.entry('x'))!;
      expect(entry.itemCount, 12);
      expect(entry.durationMs, 5000);
      expect(entry.subtitle, 'new');
      expect(entry.title, 'A course');

      await store.remove('x');
      expect(await store.entry('x'), isNull);
    });

    test('changes bump the revision providers watch', () async {
      final seen = store.revision.value;
      await store.add(draft('x'));
      expect(store.revision.value, greaterThan(seen));
      final afterAdd = store.revision.value;
      await store.add(draft('x'));
      expect(store.revision.value, afterAdd, reason: 'a refused duplicate changes nothing');
    });
  });

  group('resume positions', () {
    test('a position past the opening is remembered', () async {
      await store.savePosition('t', 90000, 600000);
      final point = (await store.resumePoint('t'))!;
      expect(point.positionMs, 90000);
      expect(point.durationMs, 600000);
    });

    test('the very start and the very end are not worth resuming', () async {
      await store.savePosition('t', 90000, 600000);
      await store.savePosition('t', 4000, 600000);
      expect(await store.resumePoint('t'), isNull);

      await store.savePosition('t', 90000, 600000);
      await store.savePosition('t', 595000, 600000);
      expect(await store.resumePoint('t'), isNull);
    });

    test('an unknown length still saves a position', () async {
      await store.savePosition('t', 30000, 0);
      expect((await store.resumePoint('t'))!.positionMs, 30000);
    });

    test('resumePoints answers for many and clearing removes one', () async {
      await store.savePosition('a', 20000, 100000);
      await store.savePosition('b', 40000, 100000);
      final points = await store.resumePoints(['a', 'b', 'c']);
      expect(points.keys, unorderedEquals(['a', 'b']));
      await store.clearPosition('a');
      expect(await store.resumePoint('a'), isNull);
      expect(await store.resumePoints(const []), isEmpty);
    });

    test('while-playing writes do not notify; the pause does', () async {
      final before = store.positionsRevision.value;
      await store.savePosition('t', 30000, 100000, notify: false);
      expect(store.positionsRevision.value, before);
      await store.savePosition('t', 35000, 100000);
      expect(store.positionsRevision.value, greaterThan(before));
    });
  });

  group('migrating Dharma Seed saves', () {
    late DharmaSeedDatabase ds;
    setUp(() async {
      ds = memoryDharmaSeedDb();
      await seedDharmaSeedCatalogue(ds);
    });
    tearDown(() => ds.close());

    test('saved courses and teachers come across once, keeping their time', () async {
      await ds.setSaved(DsSavedKind.retreat, 100, saved: true);
      await ds.setSaved(DsSavedKind.retreat, 200, saved: true);
      await ds.setSaved(DsSavedKind.teacher, 2, saved: true);

      final migrating = LibraryStore(db, prepare: (d) => migrateDharmaSeedSaves(d, ds));
      final entries = await migrating.entries();

      expect(entries.map((e) => e.sourceId), unorderedEquals(['ds-retreat-100', 'ds-retreat-200', 'ds-teacher-2']));
      final jhana = entries.firstWhere((e) => e.sourceId == 'ds-retreat-100');
      expect(jhana.kind, LibraryKind.course);
      expect(jhana.title, 'Jhana Retreat');
      expect(jhana.group, LibraryGroup.practice, reason: '3 of 4 talks are guided meditation');
      final talks = entries.firstWhere((e) => e.sourceId == 'ds-retreat-200');
      expect(talks.group, LibraryGroup.talks);
      expect(entries.firstWhere((e) => e.sourceId == 'ds-teacher-2').kind, LibraryKind.teacher);

      // The old table is untouched, and a second run adds nothing.
      expect(await ds.savedIds(DsSavedKind.retreat), hasLength(2));
      await migrateDharmaSeedSaves(db, ds);
      expect(await db.allEntries(), hasLength(3));
    });

    test('a save the catalogue no longer holds is still carried over', () async {
      await ds.setSaved(DsSavedKind.retreat, 9999, saved: true);
      final migrating = LibraryStore(db, prepare: (d) => migrateDharmaSeedSaves(d, ds));
      final entry = (await migrating.entries()).single;
      expect(entry.sourceId, 'ds-retreat-9999');
      expect(entry.title, isNotEmpty);
    });

    test('a library with entries already keeps them', () async {
      await store.add(draft('ds-retreat-100', title: 'Already here'));
      await ds.setSaved(DsSavedKind.retreat, 100, saved: true);
      await migrateDharmaSeedSaves(db, ds);
      expect((await store.entry('ds-retreat-100'))!.title, 'Already here');
    });
  });
}
