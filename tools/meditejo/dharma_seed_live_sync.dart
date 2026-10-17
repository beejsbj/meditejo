// Manual check of the Dharma Seed sync against the live API. Not part of CI.
// ignore_for_file: avoid_print
//
//   timeout 1800 nice -n 10 flutter test tools/meditejo/dharma_seed_live_sync.dart \
//     --dart-define=DS_DB=/tmp/ds-live.sqlite
//
// It makes the same polite, sequential requests as one fresh install (124 on
// 2026-10-17), then a second, incremental sync. Rerunning against the same DS_DB
// file resumes or syncs incrementally. Prints timings and request counts.
import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:sqlite3/open.dart';

void main() {
  test('live Dharma Seed sync', () async {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so');
      } on ArgumentError {
        return DynamicLibrary.open('libsqlite3.so.0');
      }
    });
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    const path = String.fromEnvironment('DS_DB', defaultValue: '');
    final db = DharmaSeedDatabase(
      path.isEmpty ? NativeDatabase.memory() : NativeDatabase(File(path)),
    );
    final counter = _CountingClient(http.Client());
    final sync = DharmaSeedSync(
      db: db,
      client: DharmaSeedClient(httpClient: counter),
    );
    final clock = Stopwatch()..start();
    final firstUseful = <String>[];
    sync.status.addListener(() {
      final s = sync.status.value;
      if (s.kind == DsKind.talks && firstUseful.isEmpty) {
        firstUseful.add(
          'teachers+retreats ready: ${clock.elapsed.inSeconds}s, '
          '${counter.requests} requests',
        );
      }
    });

    await sync.sync(force: true);
    final full = clock.elapsed;
    final fullRequests = counter.requests;
    print(firstUseful.join());
    print(
      'full sync: ${full.inSeconds}s, $fullRequests requests, '
      '${counter.bytes ~/ 1024} KiB; status ${sync.status.value}',
    );
    for (final kind in DsKind.values) {
      print('  ${kind.name}: ${await db.countOf(kind)}');
    }

    clock.reset();
    counter.requests = 0;
    await sync.sync(force: true);
    print(
      'incremental sync: ${clock.elapsed.inMilliseconds}ms, '
      '${counter.requests} requests',
    );

    final hits = await db.searchTalks('jhana');
    print('search "jhana": ${hits.length} hits, e.g. ${hits.first.talk.title}');
    final burbea = await db.searchTalks('burbea soulmaking');
    print('search "burbea soulmaking": ${burbea.length} hits');
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 30)));
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
