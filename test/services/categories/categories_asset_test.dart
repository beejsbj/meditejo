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

  test('every category has a rule or a curated item, or says it has none yet', () {
    // Sankalpa and TMI have nothing on Dharma Seed (checked 2026-10-27); they
    // are filled by the user's labels and imports. Anything else must have
    // something, or the page would be empty for no reason.
    const knownEmpty = {'tmi', 'sankalpa'};
    for (final c in catalogue.categories) {
      if (knownEmpty.contains(c.id)) continue;
      final reachable =
          catalogue.curatedIn(c.id).isNotEmpty ||
          catalogue.rulesFor(c.id).isNotEmpty;
      expect(reachable, isTrue, reason: '${c.id} is unreachable');
    }
  });

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
      final rows = snapshot.select(
        'SELECT 1 FROM $table WHERE id = ?',
        [number],
      );
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
      expect(ofTitle('Dzogchen Retreat'), ['open-awareness']);
      expect(ofTitle('Mindfulness of the Body'), ['body']);
      expect(ofTitle('Maximize your Meditation with Culadasa'), ['tmi']);
      expect(ofTitle('Sankalpa and the Heart'), ['sankalpa']);
    });

    test('do not fire on look-alikes', () {
      expect(ofTitle('Nobody home'), isEmpty);
      expect(ofTitle('A walk with John'), isEmpty);
      expect(ofTitle('Dependent Origination'), isEmpty);
    });

    test('read the catalogue\'s descriptions where a rule allows', () {
      // Retreat 1308 is curated; the rule path is checked on its text.
      expect(ofRetreat(1308), contains('samatha'));
    });

    test('stay a fallback: no category swallows the catalogue', () {
      final total =
          snapshot.select('SELECT COUNT(*) AS n FROM ds_retreats').first['n']
              as int;
      for (final c in catalogue.categories) {
        var hits = 0;
        for (final row in snapshot.select(
          'SELECT id, name, description FROM ds_retreats',
        )) {
          final result = catalogue.classify(
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
