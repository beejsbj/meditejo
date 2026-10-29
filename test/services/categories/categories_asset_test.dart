import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/library/starter_set.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

/// The shipped mapping, checked against the Dharma Seed catalogue the app
/// ships with. Needs the snapshot: `python3 -I tools/meditejo/catalogue.py
/// fetch` (docs/fork/BUILD.md).
void main() {
  late CategoryCatalogue catalogue;
  late Database snapshot;
  late Directory dir;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so');
      } on ArgumentError {
        return DynamicLibrary.open('libsqlite3.so.0');
      }
    });
    catalogue = CategoryCatalogue.parse(
      File(categoriesAsset).readAsStringSync(),
      modelPass: File(categoriesPassAsset).readAsStringSync(),
    );
    final gz = File('assets/dharma_seed/catalogue.sqlite.gz');
    if (!gz.existsSync()) {
      fail(
        'The Dharma Seed snapshot is missing. Run: '
        'python3 -I tools/meditejo/catalogue.py fetch',
      );
    }
    dir = Directory.systemTemp.createTempSync('categories_asset_test');
    final file = File('${dir.path}/catalogue.sqlite')
      ..writeAsBytesSync(gzip.decode(gz.readAsBytesSync()));
    snapshot = sqlite3.open(file.path, mode: OpenMode.readOnly);
  });

  tearDownAll(() {
    snapshot.dispose();
    dir.deleteSync(recursive: true);
  });

  test('offers the categories Burooj asked for, in a sensible order', () {
    final ids = catalogue.categories.map((c) => c.id).toList();
    expect(
      ids,
      containsAll([
        'metta',
        'vipassana',
        'sankalpa',
        'jhana',
        'tmi',
        'breath',
        'body',
        'samatha',
        'open-awareness',
      ]),
    );
    for (final c in catalogue.categories) {
      expect(c.blurb, isNotEmpty, reason: '${c.id} needs a one-line blurb');
    }
  });

  test(
    'every category has a rule or a curated item, or says it has none yet',
    () {
      // Several have nothing on Dharma Seed (TMI, Sankalpa, Kundalini, the
      // Headless Way, …); browsing hides them until the user's labels or
      // another source fill them. Each still needs a way in for when they do.
      for (final c in catalogue.categories) {
        final reachable =
            catalogue.curatedIn(c.id).isNotEmpty ||
            catalogue.modelIn(c.id).isNotEmpty ||
            catalogue.rulesFor(c.id).isNotEmpty;
        expect(reachable, isTrue, reason: '${c.id} is unreachable');
      }
    },
  );

  test('every curated item is a real Dharma Seed retreat or talk', () {
    for (final id in catalogue.curatedIds) {
      final retreat = RegExp(r'^ds-retreat-(\d+)$').firstMatch(id);
      final talk = RegExp(r'^ds-talk-(\d+)$').firstMatch(id);
      if (retreat == null && talk == null) {
        // A starter-set item from another source (a YouTube playlist).
        expect(id, matches(RegExp(r'^(yt|lib)-')), reason: id);
        continue;
      }
      final table = retreat != null ? 'ds_retreats' : 'ds_talks';
      final number = int.parse((retreat ?? talk)![1]!);
      final rows = snapshot.select('SELECT 1 FROM $table WHERE id = ?', [
        number,
      ]);
      expect(rows, isNotEmpty, reason: '$id is not in the catalogue');
    }
  });

  test('the curated names match the catalogue, so a typo cannot hide', () {
    for (final MapEntry(:key, :value) in catalogue.curatedNames.entries) {
      final retreat = RegExp(r'^ds-retreat-(\d+)$').firstMatch(key);
      final talk = RegExp(r'^ds-talk-(\d+)$').firstMatch(key);
      if (retreat == null && talk == null) continue;
      final rows = snapshot.select(
        retreat != null
            ? 'SELECT name AS t FROM ds_retreats WHERE id = ?'
            : 'SELECT title AS t FROM ds_talks WHERE id = ?',
        [int.parse((retreat ?? talk)![1]!)],
      );
      expect(
        (rows.first['t'] as String).replaceAll(RegExp(r'\s+'), ' ').trim(),
        value,
        reason: key,
      );
    }
  });

  test('the Dharma Seed starter set is curated (BRIEF decision 13)', () {
    for (final item in starterSet) {
      if (!item.id.startsWith('ds-')) continue;
      final categories = catalogue.curatedFor(item.id);
      expect(categories, isNotNull, reason: '${item.id} is not curated');
      expect(categories, isNotEmpty, reason: '${item.id} has no category');
    }
    expect(catalogue.curatedFor('ds-retreat-4496'), ['jhana']);
    expect(catalogue.curatedFor('ds-retreat-1084'), ['metta']);
    expect(catalogue.curatedFor('ds-retreat-1183'), ['samatha']);
    expect(catalogue.curatedFor('ds-retreat-1308'), ['samatha']);
    expect(catalogue.curatedFor('ds-talk-60864'), ['jhana']);
  });

  group('the model pass', () {
    test('no category but Vipassanā holds more than a quarter of it', () {
      // Dharma Seed is largely the Insight Meditation movement's archive, so
      // most of its retreats really are insight retreats: the pass reads
      // Vipassanā on well over a quarter (DECISIONS.md, 2026-10-28). That is
      // the one category allowed past the bound, and only up to 45%.
      final total =
          snapshot
                  .select(
                    "SELECT COUNT(*) AS n FROM ds_retreats WHERE talk_ids != '[]'",
                  )
                  .first['n']
              as int;
      for (final c in catalogue.categories) {
        final share = catalogue.modelIn(c.id).length / total;
        final bound = c.id == 'vipassana' ? 0.45 : 0.25;
        expect(share, lessThan(bound), reason: '${c.id}: $share');
      }
    });

    test('read every retreat with talks in the bundled snapshot', () {
      final withTalks = {
        for (final row in snapshot.select(
          "SELECT id FROM ds_retreats WHERE talk_ids != '[]'",
        ))
          row['id'] as int,
      };
      final read = {
        for (final id in withTalks)
          if (catalogue.modelFor('ds-retreat-$id') != null) id,
      };
      expect(read, withTalks);
    });

    test('names only retreats that exist', () {
      final ids = {
        for (final row in snapshot.select('SELECT id FROM ds_retreats'))
          'ds-retreat-${row['id']}',
      };
      for (final c in catalogue.categories) {
        for (final id in catalogue.modelIn(c.id)) {
          expect(ids, contains(id));
        }
      }
    });

    test('is outranked by the hand-picked entries', () {
      // Retreat 4496 is hand-picked as Jhāna, whatever the pass read.
      expect(catalogue.classify('ds-retreat-4496'), [
        const CategoryAssignment('jhana', CategorySource.curated),
      ]);
    });
  });

  group('the rules, over real titles', () {
    List<String> ofRetreat(int id) {
      final row = snapshot.select(
        'SELECT name, description FROM ds_retreats WHERE id = ?',
        [id],
      ).first;
      return [
        for (final a in catalogue.classify(
          'ds-retreat-$id-uncurated',
          title: row['name'] as String,
          description: row['description'] as String,
        ))
          a.id,
      ];
    }

    List<String> ofTitle(String title) => [
      for (final a in catalogue.classify('x', title: title)) a.id,
    ];

    test('recognise the plain cases', () {
      expect(ofTitle('Practising the Jhānas'), ['jhana']);
      expect(ofTitle('Summer Lovingkindness Retreat'), ['metta']);
      expect(ofTitle('Vipassana und Metta'), ['metta', 'vipassana']);
      expect(ofTitle('Mindfulness of Breathing'), ['breath']);
      expect(ofTitle('The Art Of Concentration (Samatha Meditation)'), [
        'samatha',
      ]);
      expect(ofTitle('Dzogchen Retreat'), ['dzogchen']);
      expect(ofTitle('Open Awareness Practice'), ['open-awareness']);
      expect(ofTitle('Walking Meditation Instructions'), ['walking']);
      expect(ofTitle('Tonglen Practice'), ['compassion']);
      expect(ofTitle('Maranasati: Contemplating Death'), ['death']);
      expect(ofTitle('Insight Dialogue Retreat'), ['relational']);
      expect(ofTitle('Morning Chanting'), ['chanting']);
      expect(ofTitle('Guided Qigong'), ['movement']);
      expect(ofTitle('Breathing with the Energy Body'), [
        'breath',
        'body',
        'energy',
      ]);
      expect(ofTitle('Mindfulness of the Body'), ['body']);
      expect(ofTitle('Maximize your Meditation with Culadasa'), ['tmi']);
      expect(ofTitle('Sankalpa and the Heart'), ['sankalpa']);
    });

    test('do not fire on look-alikes', () {
      expect(ofTitle('Nobody home'), isEmpty);
      expect(ofTitle('A walk with John'), isEmpty);
      expect(ofTitle('Walking Each Other Home'), isEmpty);
      expect(ofTitle('A Glimpse of Connection'), isEmpty);
      expect(ofTitle('Mindfulness Based on Right View'), isEmpty);
      expect(ofTitle('The Five Spiritual Faculties: Energy'), isEmpty);
      expect(ofTitle('Dependent Origination'), isEmpty);
    });

    test('read the catalogue\'s descriptions where a rule allows', () {
      // Retreat 1308 is curated; the rule path is checked on its text.
      expect(ofRetreat(1308), contains('samatha'));
    });

    test('stay a fallback: no category swallows the catalogue', () {
      // The rules alone, as for a retreat newer than the model pass.
      final rulesOnly = CategoryCatalogue.parse(
        File(categoriesAsset).readAsStringSync(),
      );
      final total =
          snapshot.select('SELECT COUNT(*) AS n FROM ds_retreats').first['n']
              as int;
      for (final c in rulesOnly.categories) {
        var hits = 0;
        for (final row in snapshot.select(
          'SELECT id, name, description FROM ds_retreats',
        )) {
          final result = rulesOnly.classify(
            'ds-retreat-${row['id']}',
            title: row['name'] as String,
            description: row['description'] as String,
          );
          if (result.any((a) => a.id == c.id)) hits++;
        }
        expect(hits, lessThan(total ~/ 4), reason: '${c.id} matches $hits');
      }
    });
  });
}
