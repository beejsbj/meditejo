import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/categories/category_service.dart';
import 'package:medito/services/categories/entry_labels.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/library_fixtures.dart';

LibraryDraft _draft(
  String id, {
  String title = 'A course',
  LibraryKind kind = LibraryKind.course,
  LibraryGroup group = LibraryGroup.practice,
}) => LibraryDraft(sourceId: id, kind: kind, title: title, group: group);

void main() {
  late CategoryCatalogue catalogue;
  late LibraryDatabase db;
  late LibraryStore store;

  setUpAll(() {
    useSystemSqlite();
    catalogue = CategoryCatalogue.parse(
      File(categoriesAsset).readAsStringSync(),
      modelPass: File(categoriesPassAsset).readAsStringSync(),
    );
  });
  setUp(() {
    db = memoryLibraryDb();
    store = LibraryStore(db);
  });
  tearDown(() async {
    store.dispose();
    await db.close();
  });

  CategoryService service([CategoryCatalogue? with_]) =>
      CategoryService(catalogue: with_ ?? catalogue, library: store);

  group('stored labels', () {
    test('add, exclude and clear, per entry', () async {
      await store.addLabel('a', 'metta');
      await store.addLabel(
        'a',
        customLabelKey('Retreat prep'),
        display: 'Retreat prep',
      );
      await store.excludeCategory('a', 'body');
      await store.addLabel('b', 'jhana');

      final all = await store.userLabels();
      expect(all['a']!.added, {'metta': '', 'retreat-prep': 'Retreat prep'});
      expect(all['a']!.excluded, {'body'});
      expect(all['b']!.added.keys, ['jhana']);

      await store.clearLabel('a', 'body');
      expect((await store.userLabels())['a']!.excluded, isEmpty);
    });

    test('adding after excluding replaces the exclusion', () async {
      await store.excludeCategory('a', 'metta');
      await store.addLabel('a', 'metta');
      final labels = (await store.userLabels())['a']!;
      expect(labels.added.keys, ['metta']);
      expect(labels.excluded, isEmpty);
    });

    test(
      'survive removing the entry, so Undo and re-adding find them',
      () async {
        await store.add(_draft('ds-retreat-1'));
        await store.addLabel('ds-retreat-1', 'metta');
        await store.remove('ds-retreat-1');
        await store.add(_draft('ds-retreat-1'));
        expect((await store.userLabels())['ds-retreat-1']!.added.keys, [
          'metta',
        ]);
      },
    );

    test('a label change tells the library to re-read', () async {
      final before = store.revision.value;
      await store.addLabel('a', 'metta');
      expect(store.revision.value, greaterThan(before));
    });

    test(
      'a library from before labels upgrades without losing anything',
      () async {
        final dir = Directory.systemTemp.createTempSync('labels_upgrade');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/library.sqlite');
        var fileDb = LibraryDatabase(NativeDatabase(file));
        var fileStore = LibraryStore(fileDb);
        await fileStore.add(_draft('ds-talk-1', title: 'Kept'));
        fileStore.dispose();
        await fileDb.close();

        final old = raw.sqlite3.open(file.path);
        old.execute('DROP TABLE library_labels');
        old.execute('PRAGMA user_version = 4');
        old.dispose();

        fileDb = LibraryDatabase(NativeDatabase(file));
        fileStore = LibraryStore(fileDb);
        addTearDown(() async {
          fileStore.dispose();
          await fileDb.close();
        });
        expect((await fileStore.entries()).single.title, 'Kept');
        await fileStore.addLabel('ds-talk-1', 'breath');
        expect((await fileStore.userLabels())['ds-talk-1']!.added.keys, [
          'breath',
        ]);
      },
    );
  });

  group('labels of an entry', () {
    test('a curated item has its curated categories', () async {
      await store.add(
        _draft('ds-retreat-4496', title: 'Practising the Jhānas'),
      );
      final labels = await service().labelsOfEntries(await store.entries());
      expect(labels['ds-retreat-4496']!.categories, [
        const CategoryAssignment('jhana', CategorySource.curated),
      ]);
    });

    test('something else is read from its title', () async {
      await store.add(_draft('yt-playlist-x', title: 'Metta for beginners'));
      final labels = await service().labelsOfEntries(await store.entries());
      expect(labels['yt-playlist-x']!.categories.map((c) => c.id), ['metta']);
    });

    test('teachers carry no labels', () async {
      await store.add(
        _draft(
          'ds-teacher-1',
          title: 'Metta Teacher',
          kind: LibraryKind.teacher,
        ),
      );
      expect(await service().labelsOfEntries(await store.entries()), isEmpty);
    });

    test('the user can take a guess off and put their own on', () async {
      await store.add(_draft('yt-playlist-x', title: 'Metta and breath'));
      final s = service();
      var labels = (await s.labelsOfEntries(
        await store.entries(),
      ))['yt-playlist-x']!;
      expect(labels.categories.map((c) => c.id), ['metta', 'breath']);

      await s.setCategory(
        'yt-playlist-x',
        'breath',
        on: false,
        current: labels,
      );
      await s.setCategory('yt-playlist-x', 'jhana', on: true, current: labels);
      labels = (await s.labelsOfEntries(
        await store.entries(),
      ))['yt-playlist-x']!;
      expect(labels.categories, [
        const CategoryAssignment('metta', CategorySource.rule),
        const CategoryAssignment('jhana', CategorySource.user),
      ]);

      // Taking the user's own off forgets it; putting the guess back clears
      // the exclusion.
      await s.setCategory('yt-playlist-x', 'jhana', on: false, current: labels);
      await s.setCategory('yt-playlist-x', 'breath', on: true, current: labels);
      labels = (await s.labelsOfEntries(
        await store.entries(),
      ))['yt-playlist-x']!;
      expect(labels.categories.map((c) => c.id), ['metta', 'breath']);
      expect((await store.userLabels())['yt-playlist-x']!.excluded, isEmpty);
    });

    test(
      'unticking a guess the user had ticked removes it, first time',
      () async {
        await store.add(_draft('yt-playlist-x', title: 'Metta and breath'));
        final s = service();
        var labels = await s.labelsOf(
          'yt-playlist-x',
          title: 'Metta and breath',
        );
        await s.setCategory(
          'yt-playlist-x',
          'breath',
          on: true,
          current: labels,
          title: 'Metta and breath',
        );
        labels = await s.labelsOf('yt-playlist-x', title: 'Metta and breath');
        expect(labels.userChose('breath'), isTrue);

        await s.setCategory(
          'yt-playlist-x',
          'breath',
          on: false,
          current: labels,
          title: 'Metta and breath',
        );
        labels = await s.labelsOf('yt-playlist-x', title: 'Metta and breath');
        expect(labels.hasCategory('breath'), isFalse);
        expect((await store.userLabels())['yt-playlist-x']!.excluded, {
          'breath',
        });
      },
    );

    test('labels in other scripts are kept', () async {
      await store.add(_draft('a'));
      final s = service();
      expect(await s.addLabel('a', 'ध्यान'), isNull);
      expect(await s.addLabel('a', '🪷'), isNull);
      expect((await s.labelsOf('a')).custom, containsAll(['ध्यान', '🪷']));
      await s.removeCustomLabel('a', 'ध्यान');
      expect((await s.labelsOf('a')).custom, ['🪷']);
    });

    test(
      'typed text becomes a category when it names one, else a label',
      () async {
        await store.add(_draft('a'));
        final s = service();
        expect((await s.addLabel('a', ' Jhāna '))?.id, 'jhana');
        expect(await s.addLabel('a', 'Retreat prep'), isNull);
        expect(await s.addLabel('a', '  '), isNull);
        final labels = await s.labelsOf('a');
        expect(labels.categories, [
          const CategoryAssignment('jhana', CategorySource.user),
        ]);
        expect(labels.custom, ['Retreat prep']);

        await s.removeCustomLabel('a', 'retreat  PREP');
        expect((await s.labelsOf('a')).custom, isEmpty);
      },
    );

    test('survive a new edition of the catalogue and outrank it', () async {
      await store.add(
        _draft('ds-retreat-4496', title: 'Practising the Jhānas'),
      );
      final first = service();
      await first.addLabel('ds-retreat-4496', 'emptiness');
      await first.addLabel('ds-retreat-4496', 'Evening');
      await first.setCategory(
        'ds-retreat-4496',
        'jhana',
        on: false,
        current: await first.labelsOf('ds-retreat-4496'),
      );

      // A later release re-curates the retreat as Samatha only.
      final next = CategoryCatalogue.parse('''
{"format": 1, "version": 99, "updated": "2027-01-01",
 "categories": [{"id": "samatha", "name": "Samatha"},
                {"id": "jhana", "name": "Jhāna"},
                {"id": "emptiness", "name": "Emptiness"}],
 "curated": [{"id": "ds-retreat-4496", "categories": ["samatha", "jhana"]}],
 "rules": []}''');
      final labels = await service(next).labelsOf('ds-retreat-4496');
      expect(labels.categories, [
        const CategoryAssignment('samatha', CategorySource.curated),
        const CategoryAssignment('emptiness', CategorySource.user),
      ]);
      expect(labels.custom, ['Evening']);
    });
  });

  group('over the bundled catalogue', () {
    late Directory dir;
    late DharmaSeedDatabase ds;

    setUpAll(() {
      final gz = File('assets/dharma_seed/catalogue.sqlite.gz');
      if (!gz.existsSync()) {
        fail(
          'The Dharma Seed snapshot is missing. Run: '
          'python3 -I tools/meditejo/catalogue.py fetch',
        );
      }
      dir = Directory.systemTemp.createTempSync('categories_service_test');
      final file = File('${dir.path}/catalogue.sqlite')
        ..writeAsBytesSync(gzip.decode(gz.readAsBytesSync()));
      ds = DharmaSeedDatabase(NativeDatabase(file));
    });
    tearDownAll(() async {
      await ds.close();
      dir.deleteSync(recursive: true);
    });

    CategoryService withCatalogue() =>
        CategoryService(catalogue: catalogue, library: store, dharmaSeed: ds);

    test('a talk takes its retreat\'s category', () async {
      // Talk 60864 is curated; another talk of retreat 4496 is not.
      final talks = await ds.talksOfRetreat(4496);
      final other = talks.firstWhere((t) => t.id != 60864);
      final result = await withCatalogue().automatic('ds-talk-${other.id}');
      expect(result.map((a) => a.id), contains('jhana'));
    });

    test(
      'a category page lists the library first and never repeats it',
      () async {
        await store.add(
          _draft('ds-retreat-4496', title: 'Practising the Jhānas'),
        );
        await store.add(
          _draft(
            'lib-track-mine',
            title: 'My jhana notes',
            kind: LibraryKind.single,
            group: LibraryGroup.talks,
          ),
        );
        final listing = await withCatalogue().listing(
          'jhana',
          entries: await store.entries(),
        );
        expect(listing.libraryPractice.map((e) => e.sourceId), [
          'ds-retreat-4496',
        ]);
        expect(listing.libraryTalks.map((e) => e.sourceId), ['lib-track-mine']);
        expect(listing.courses, isNotEmpty);
        expect(
          listing.courses.map((c) => c.id),
          isNot(contains('ds-retreat-4496')),
        );
        // Curated retreats come before keyword matches.
        expect(listing.courses.first.id, 'ds-retreat-603');
        for (final course in listing.courses) {
          expect(course.id, startsWith('ds-retreat-'));
        }
        for (final item in [
          ...listing.practiceSessions,
          ...listing.talkSessions,
        ]) {
          expect(item.id, startsWith('ds-talk-'));
        }
        final ids = [
          ...listing.courses,
          ...listing.practiceSessions,
          ...listing.talkSessions,
        ].map((i) => i.id).toList();
        expect(ids.toSet(), hasLength(ids.length));
      },
    );

    test('a session of a course in the library is not listed again', () async {
      // Retreat 4496 is in the starter set; talk 60864 is curated Jhāna and
      // belongs to it.
      await store.add(
        _draft('ds-retreat-4496', title: 'Practising the Jhānas'),
      );
      final listing = await withCatalogue().listing(
        'jhana',
        entries: await store.entries(),
      );
      expect(listing.libraryPractice.map((e) => e.sourceId), [
        'ds-retreat-4496',
      ]);
      for (final session in [
        ...listing.practiceSessions,
        ...listing.talkSessions,
      ]) {
        final talk = await ds.talkById(int.parse(session.id.split('-').last));
        expect(talk!.retreatId, isNot(4496), reason: session.id);
      }
    });

    test('a session whose course is on the page is not listed again', () async {
      final listing = await withCatalogue().listing('jhana', entries: const []);
      final listed = {
        for (final c in listing.courses) int.parse(c.id.split('-').last),
      };
      for (final session in [
        ...listing.practiceSessions,
        ...listing.talkSessions,
      ]) {
        final talk = await ds.talkById(int.parse(session.id.split('-').last));
        expect(listed, isNot(contains(talk!.retreatId)));
      }
    });

    test('Practice sessions are practice recordings, Talks are not', () async {
      final listing = await withCatalogue().listing(
        'breath',
        entries: const [],
      );
      for (final session in listing.practiceSessions) {
        final talk = await ds.talkById(int.parse(session.id.split('-').last));
        expect([
          'meditation',
          'guided meditation',
          'chanting',
        ], contains(talk!.recordingType.toLowerCase().trim()));
      }
      for (final session in listing.talkSessions) {
        final talk = await ds.talkById(int.parse(session.id.split('-').last));
        expect([
          'meditation',
          'guided meditation',
          'chanting',
        ], isNot(contains(talk!.recordingType.toLowerCase().trim())));
      }
      expect(listing.practiceSessions.length, lessThanOrEqualTo(30));
      expect(listing.talkSessions.length, lessThanOrEqualTo(30));
    });

    test(
      'a category with nothing on Dharma Seed is empty, not an error',
      () async {
        final listing = await withCatalogue().listing('tmi', entries: const []);
        expect(listing.courses, isEmpty);
        expect(listing.isEmpty, isTrue);
      },
    );

    test('a retreat the model pass read carries its reading', () async {
      final id = catalogue.modelIn('metta').first;
      final result = await withCatalogue().automatic(id);
      expect(
        result,
        contains(const CategoryAssignment('metta', CategorySource.model)),
      );
    });

    test('a page lists every hand-picked retreat and a bounded tail', () async {
      final listing = await withCatalogue().listing(
        'vipassana',
        entries: const [],
      );
      final curated = catalogue.curatedIn('vipassana').length;
      expect(listing.courses.length, greaterThan(curated));
      expect(
        listing.courses.length,
        lessThanOrEqualTo(curated + CategoryService.guessCourseLimit),
      );
    });

    test('browsing offers only categories with something in them', () async {
      // The shipped list plus one that nothing on Dharma Seed can match.
      final json =
          jsonDecode(File(categoriesAsset).readAsStringSync())
              as Map<String, dynamic>;
      (json['categories'] as List).add({'id': 'unseen', 'name': 'Unseen'});
      final withUnseen = CategoryCatalogue.parse(
        jsonEncode(json),
        modelPass: File(categoriesPassAsset).readAsStringSync(),
      );
      CategoryService service() => CategoryService(
        catalogue: withUnseen,
        library: store,
        dharmaSeed: ds,
      );

      final shown = await service().nonEmpty(entries: const []);
      expect(shown, containsAll(['metta', 'jhana', 'vipassana', 'walking']));
      // A talk: "On Having No Head: A Simple, Effective Anatta Practice".
      expect(shown, contains('headless'));
      // Culadasa's retreat page is hand-picked as TMI but has no talks.
      expect(shown, isNot(contains('tmi')));
      expect(shown, isNot(contains('unseen')));

      await store.add(_draft('yt-video-x', title: 'Something new'));
      await store.addLabel('yt-video-x', 'unseen');
      final entries = await store.entries();
      expect(await service().nonEmpty(entries: entries), contains('unseen'));
    });

    test('an unknown category is refused', () {
      expect(
        withCatalogue().listing('nope', entries: const []),
        throwsArgumentError,
      );
    });
  });
}
