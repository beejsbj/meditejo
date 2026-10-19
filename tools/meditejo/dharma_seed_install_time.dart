// Times a first launch from the bundled catalogue, offline. Not part of CI.
// ignore_for_file: avoid_print
//
//   timeout 600 nice -n 10 flutter test tools/meditejo/dharma_seed_install_time.dart
//
// Installs assets/dharma_seed into an empty folder the way the app does on a
// first launch, then opens the database and searches it. No network is used.
// bjslab is not a phone: expect a phone to be a few times slower.
import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_snapshot.dart';
import 'package:sqlite3/open.dart';

void main() {
  test('first launch from the bundled catalogue', () async {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so');
      } on ArgumentError {
        return DynamicLibrary.open('libsqlite3.so.0');
      }
    });
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory.systemTemp.createTempSync('meditejo-ds-install');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/dharma_seed.sqlite');
    final snapshot = DharmaSeedSnapshot(
      readManifest: () =>
          File('assets/dharma_seed/catalogue.json').readAsString(),
      readDatabase: () =>
          File('assets/dharma_seed/catalogue.sqlite.gz').readAsBytes(),
    );

    final clock = Stopwatch()..start();
    final result = await snapshot.installIfNeeded(target);
    final installed = clock.elapsedMilliseconds;
    final db = DharmaSeedDatabase(NativeDatabase(target));
    final talks = await db.countOf(DsKind.talks);
    final opened = clock.elapsedMilliseconds;
    final hits = await db.searchTalks('jhana');
    final searched = clock.elapsedMilliseconds;
    await db.close();

    print('result: $result');
    print('install (unpack, 0 requests): $installed ms');
    print('open and count $talks talks: ${opened - installed} ms');
    print(
      'first search "jhana" (${hits.length} hits): ${searched - opened} ms',
    );
    print('file: ${(target.lengthSync() / 1048576).toStringAsFixed(1)} MiB');
    expect(result, DsSnapshotResult.installed);
  });
}
