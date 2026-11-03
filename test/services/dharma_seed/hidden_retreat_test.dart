import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/categories/category_service.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/library/library_store.dart';

import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/library_fixtures.dart';

/// Retreat 5371 ("ORIGINAL RECORDINGS, TO BE EDITED", Ajahn Sucitto) says
/// "Not for public distribution". Meditejo respects the note: neither it nor
/// its talks appear in browsing, search, teacher pages or categories, but it
/// still opens by id for a library that already holds it (DECISIONS.md,
/// 2026-11-03). Checked against the bundled snapshot.
void main() {
  late Directory dir;
  late DharmaSeedDatabase ds;
  const hidden = 5371, sucitto = 9;

  setUpAll(() {
    useSystemSqlite();
    final gz = File('assets/dharma_seed/catalogue.sqlite.gz');
    if (!gz.existsSync()) {
      fail(
        'The Dharma Seed snapshot is missing. Run: '
        'python3 -I tools/meditejo/catalogue.py fetch',
      );
    }
    dir = Directory.systemTemp.createTempSync('hidden_retreat_test');
    final file = File('${dir.path}/catalogue.sqlite')
      ..writeAsBytesSync(gzip.decode(gz.readAsBytesSync()));
    ds = DharmaSeedDatabase(NativeDatabase(file));
  });
  tearDownAll(() async {
    await ds.close();
    dir.deleteSync(recursive: true);
  });

  test('is in the snapshot, with talks, and opens by id', () async {
    expect(DharmaSeedDatabase.hiddenRetreatIds, contains(hidden));
    final retreat = await ds.retreatById(hidden);
    expect(retreat, isNotNull);
    expect(retreat!.description, contains('Not for public distribution'));
    // Reachable for a library that already holds it.
    expect(await ds.talksOfRetreat(hidden), isNotEmpty);
  });

  test('is left out of browsing and search', () async {
    final talks = await ds.talksOfRetreat(hidden);
    final talkIds = {for (final t in talks) t.id};

    expect(
      (await ds.searchRetreats('original recordings edited')).map((r) => r.id),
      isNot(contains(hidden)),
    );
    expect(
      (await ds.recentRetreats(limit: 100000)).map((r) => r.id),
      isNot(contains(hidden)),
    );
    for (final group in [null, ...DsContentGroup.values]) {
      expect(
        (await ds.recentRetreatsOf(group, limit: 100000)).map((r) => r.id),
        isNot(contains(hidden)),
        reason: '$group',
      );
    }
    expect(
      (await ds.retreatsOfTeacher(sucitto)).map((r) => r.id),
      isNot(contains(hidden)),
    );
    final teacherTalks = await ds.talksOfTeacher(sucitto, limit: 100000);
    expect(
      teacherTalks.map((t) => t.talk.id).toSet().intersection(talkIds),
      isEmpty,
    );
    // Each of its talks, searched by its own title, is not found.
    for (final t in talks) {
      final found = await ds.searchTalks(t.title, limit: 200);
      expect(
        found.map((x) => x.talk.retreatId),
        isNot(contains(hidden)),
        reason: t.title,
      );
    }
    final recent = await ds.recentTalks(limit: 100000);
    expect(recent.map((x) => x.talk.retreatId), isNot(contains(hidden)));
  });

  test('is left out of category pages', () async {
    final catalogue = CategoryCatalogue.parse(
      File(categoriesAsset).readAsStringSync(),
      modelPass: File(categoriesPassAsset).readAsStringSync(),
    );
    final db = memoryLibraryDb();
    final store = LibraryStore(db);
    addTearDown(() async {
      store.dispose();
      await db.close();
    });
    final service = CategoryService(
      catalogue: catalogue,
      library: store,
      dharmaSeed: ds,
    );
    // Its talks include guided metta and talks on citta and the aggregates.
    for (final id in ['metta', 'vipassana', 'samatha']) {
      final listing = await service.listing(id, entries: const []);
      expect(
        listing.courses.map((c) => c.id),
        isNot(contains('ds-retreat-$hidden')),
        reason: id,
      );
      final sessions = [...listing.practiceSessions, ...listing.talkSessions];
      for (final s in sessions) {
        final talk = await ds.talkById(int.parse(s.id.split('-').last));
        expect(talk?.retreatId, isNot(hidden), reason: '$id ${s.title}');
      }
    }
  });
}
