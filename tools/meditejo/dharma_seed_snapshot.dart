// Builds the Dharma Seed catalogue snapshot that ships inside the app.
// Not part of CI; `release.sh` runs it when the pinned snapshot is stale.
// The snapshot is a GitHub release asset, not a file in git: this tool starts
// from the one `python3 -I tools/meditejo/catalogue.py fetch` put in
// assets/dharma_seed, and `catalogue.py publish` uploads the result and pins
// it in catalogue.json (docs/fork/ARCHITECTURE.md, "The bundled catalogue").
// ignore_for_file: avoid_print
//
//   timeout 2400 nice -n 10 flutter test tools/meditejo/dharma_seed_snapshot.dart
//
// It runs the app's own polite sync (one request at a time, 750 ms apart) and
// writes assets/dharma_seed/catalogue.sqlite.gz plus catalogue.json. Starting
// from the snapshot already in the repository, a refresh is a delta of a few
// requests; from nothing it is a full sync (125 requests, about six minutes on
// 2026-10-19). Catalogue text only: no audio is fetched.
//
// Options, as --dart-define=NAME=value:
//   DS_OUT      output folder (default assets/dharma_seed)
//   DS_WORK_DB  keep the working database at this path, so an interrupted run
//               resumes and a finished one can be inspected (default: a
//               temporary file, deleted afterwards)
//   DS_FRESH    true: ignore the snapshot in the repository and sync from
//               scratch
//   DS_FORCE    true: rewrite the files even when nothing changed upstream
import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_snapshot_writer.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:sqlite3/open.dart';

const _out = String.fromEnvironment(
  'DS_OUT',
  defaultValue: 'assets/dharma_seed',
);
const _workDb = String.fromEnvironment('DS_WORK_DB', defaultValue: '');
const _fresh = bool.fromEnvironment('DS_FRESH');
const _force = bool.fromEnvironment('DS_FORCE');

void main() {
  test('build the Dharma Seed snapshot', () async {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so');
      } on ArgumentError {
        return DynamicLibrary.open('libsqlite3.so.0');
      }
    });
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    final outDir = Directory(_out);
    final scratch = Directory.systemTemp.createTempSync('meditejo-ds-snapshot');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final work = File(
      _workDb.isEmpty ? '${scratch.path}/catalogue-work.sqlite' : _workDb,
    );

    final previous = DharmaSeedSnapshotWriter.existing(outDir);
    if (!work.existsSync() && !_fresh && previous != null) {
      // Start from the last snapshot: the sync then fetches only the changes.
      final packed = File(
        '${outDir.path}/${DharmaSeedSnapshotWriter.databaseFileName}',
      );
      if (!packed.existsSync()) {
        fail(
          '${packed.path} is missing: run `python3 -I '
          'tools/meditejo/catalogue.py fetch` first (or DS_FRESH=true for a '
          'full sync).',
        );
      }
      await packed.openRead().transform(gzip.decoder).pipe(work.openWrite());
      print('starting from the snapshot of ${previous.asOf.toIso8601String()}');
    }

    final db = DharmaSeedDatabase(NativeDatabase(work));
    final counter = _CountingClient(http.Client());
    final sync = DharmaSeedSync(
      db: db,
      client: DharmaSeedClient(httpClient: counter),
    );
    final clock = Stopwatch()..start();
    await sync.sync(force: true);
    final status = sync.status.value;
    await db.close();
    if (status.phase == DharmaSeedSyncPhase.failed || status.error != null) {
      fail('The sync did not finish: $status. Run again to resume.');
    }
    print(
      'sync: ${clock.elapsed.inSeconds}s, ${counter.requests} requests, '
      '${counter.bytes ~/ 1024} KiB',
    );

    final built = Directory('${scratch.path}/out');
    final manifest = await DharmaSeedSnapshotWriter.write(
      source: work,
      directory: built,
    );
    print('counts: ${manifest.counts}, editions: ${manifest.editions}');

    // Editions are the server's clock at the time of asking, so they differ on
    // every run; "nothing changed" means the sync fetched no record and
    // removed none.
    final unchanged =
        previous != null &&
        previous.databaseSchema == manifest.databaseSchema &&
        sync.revision.value == 0;
    if (unchanged && !_force) {
      print(
        'Nothing changed upstream since ${previous.asOf.toIso8601String()}: '
        'the snapshot in $_out stays as it is.',
      );
      return;
    }
    await outDir.create(recursive: true);
    for (final name in [
      DharmaSeedSnapshotWriter.databaseFileName,
      DharmaSeedSnapshotWriter.manifestFileName,
    ]) {
      File('${built.path}/$name').copySync('${outDir.path}/$name');
    }
    final packedSize = File(
      '${outDir.path}/${DharmaSeedSnapshotWriter.databaseFileName}',
    ).lengthSync();
    print(
      'wrote $_out: ${(packedSize / 1048576).toStringAsFixed(1)} MiB packed, '
      '${(manifest.bytes / 1048576).toStringAsFixed(1)} MiB unpacked, '
      'as of ${manifest.asOf.toIso8601String()}',
    );
  }, timeout: const Timeout(Duration(minutes: 40)));
}

class _CountingClient extends http.BaseClient {
  _CountingClient(this._inner);

  final http.Client _inner;
  int requests = 0;
  int bytes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    final response = await _inner.send(request);
    return http.StreamedResponse(
      response.stream.map((chunk) {
        bytes += chunk.length;
        return chunk;
      }),
      response.statusCode,
      headers: response.headers,
      request: response.request,
    );
  }
}
