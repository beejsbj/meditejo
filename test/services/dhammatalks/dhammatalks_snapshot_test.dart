import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/dhammatalks/dhammatalks_catalogue.dart';
import 'package:medito/services/dhammatalks/dhammatalks_ids.dart';

/// The bundled dhammatalks.org snapshot and its manifest, as committed. The
/// hard rule is the last test: a snapshot older than the RSS feeds can bridge
/// fails the build until it is refreshed.
void main() {
  final asset = File('assets/dhammatalks/catalogue.json.gz');
  final manifestFile = File('assets/dhammatalks/manifest.json');
  late Map<String, Object?> manifest;
  late Uint8List gz;

  setUpAll(() {
    manifest = (jsonDecode(manifestFile.readAsStringSync()) as Map)
        .cast<String, Object?>();
    gz = asset.readAsBytesSync();
  });

  test('the asset is the one the manifest describes', () {
    final pinned = (manifest['asset']! as Map).cast<String, Object?>();
    expect(gz.length, pinned['bytes']);
    expect(sha256.convert(gz).toString(), pinned['sha256']);
  });

  test('it stays under the size that justifies keeping it in git', () {
    expect(gz.length, lessThan(1024 * 1024));
  });

  test('it reads, and agrees with the manifest', () {
    final catalogue = DtCatalogue.fromJson(DtCatalogue.decode(gz));
    final counts = (manifest['counts']! as Map).cast<String, Object?>();
    expect(catalogue.talkCount, counts['talks']);
    expect(
      catalogue.talks.where((t) => t.code == 'e').length,
      counts['evening'],
    );
    expect(
      catalogue.talks.where((t) => t.code == 'm').length,
      counts['morning'],
    );
    expect(catalogue.courses.length, counts['courses']);
    expect(catalogue.asOf, DateTime.parse(manifest['asOf']! as String));
    expect(catalogue.talks.first.date, manifest['newest']);
  });

  test('every talk has an ID that parses back, a file and a title', () {
    final catalogue = DtCatalogue.fromJson(DtCatalogue.decode(gz));
    final ids = <String>{};
    for (final talk in catalogue.talks) {
      expect(ids.add(talk.id), isTrue, reason: 'duplicate ${talk.id}');
      final ref = parseDtTalkId(talk.id);
      expect(ref, isNotNull, reason: talk.id);
      expect(ref!.key, talk.key);
      expect(talk.title, isNotEmpty);
      expect(talk.audioPath, startsWith('/Archive/'));
      expect(talk.date, isNotEmpty, reason: talk.id);
    }
  });

  test('the guided meditations are Practice and carry their lengths', () {
    final catalogue = DtCatalogue.fromJson(DtCatalogue.decode(gz));
    final guided = catalogue.course('guided')!;
    expect(guided.items, isNotEmpty);
    expect(guided.items.every((t) => t.practice && t.durationMs > 0), isTrue);
    expect(catalogue.course('basics')!.items, hasLength(50));
  });

  group('staleness', () {
    test('the rule counts whole days past the window', () {
      final asOf = DateTime.utc(2026, 10, 27, 12);
      expect(
        dtSnapshotIsStale(asOf, asOf.add(const Duration(days: 45))),
        isFalse,
      );
      expect(
        dtSnapshotIsStale(asOf, asOf.add(const Duration(days: 46))),
        isTrue,
      );
      expect(
        dtSnapshotIsStale(
          asOf,
          asOf.add(const Duration(days: 60)),
          maxAgeDays: 90,
        ),
        isFalse,
      );
    });

    test('the bundled snapshot is fresh enough for the RSS feeds to bridge', () {
      final asOf = DateTime.parse(manifest['asOf']! as String);
      expect(
        dtSnapshotIsStale(asOf, DateTime.now().toUtc()),
        isFalse,
        reason:
            'The dhammatalks.org snapshot was made $asOf, more than '
            '$dtSnapshotMaxAgeDays days ago, so talks given since fall in a gap '
            'the feeds (50 items each) no longer cover. Refresh it with: '
            'python3 -I tools/meditejo/dhammatalks.py build',
      );
    });
  });
}
