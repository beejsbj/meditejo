import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:sqlite3/open.dart';

/// Recorded API fixtures, trimmed from live responses on 2026-10-17
/// (contact fields blanked). See test/fixtures/dharma_seed/.
Map<String, Object?> dsFixture(String name) =>
    jsonDecode(File('test/fixtures/dharma_seed/$name').readAsStringSync())
        as Map<String, Object?>;

const dsFirstEdition = '2026-10-17 07:49:28';
const dsSecondEdition = '2026-10-18 09:00:00';

DharmaSeedDatabase memoryDharmaSeedDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // Host tests use the system SQLite (the app bundles its own). Linux
  // runtimes often ship only the versioned library, not the dev symlink.
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } on ArgumentError {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
  return DharmaSeedDatabase(NativeDatabase.memory());
}

class DsRequest {
  DsRequest(this.kind, this.fields, this.headers);

  final String kind;
  final Map<String, String> fields;
  final Map<String, String> headers;

  bool get isDetail => fields['detail'] == '1';
  List<int> get items => (fields['items'] ?? '')
      .split(',')
      .where((s) => s.isNotEmpty)
      .map(int.parse)
      .toList();

  @override
  String toString() =>
      '$kind ${isDetail ? 'detail $items' : 'ids since ${fields['edition']}'}';
}

/// Serves the fixtures like Dharma Seed would: full ID lists without an
/// edition, the "since" fixtures for an edition, and detail records filtered
/// to the requested IDs. [fail] can inject a response per request.
class FakeDharmaSeedApi {
  FakeDharmaSeedApi({this.fail});

  final requests = <DsRequest>[];

  /// Talk ID listings served so far; the second sees the newer edition.
  var _talkListings = 0;

  /// Returns a response to send instead of the fixture, or null.
  http.Response? Function(DsRequest request, int index)? fail;

  late final http.Client httpClient = MockClient((request) async {
    final kind = request.url.pathSegments.where((s) => s.isNotEmpty).last;
    final parsed = DsRequest(
      kind,
      _multipartFields(request),
      request.headers,
    );
    requests.add(parsed);
    final injected = fail?.call(parsed, requests.length - 1);
    if (injected != null) return injected;
    if (!parsed.isDetail && kind == 'talks') _talkListings++;
    return http.Response.bytes(
      utf8.encode(jsonEncode(_respond(parsed))),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  DharmaSeedClient client() => DharmaSeedClient(
    httpClient: httpClient,
    sleep: (_) async {},
  );

  Map<String, Object?> _respond(DsRequest request) {
    final since = request.fields['edition'];
    if (!request.isDetail) {
      if (since == null) return dsFixture('${request.kind}_ids.json');
      if (request.kind == 'talks') return dsFixture('talks_ids_since.json');
      return {'edition': dsSecondEdition, 'items': [], 'x_items': []};
    }
    final base = dsFixture('${request.kind}_detail.json');
    final records = Map<String, Object?>.from(base['items'] as Map);
    if (request.kind == 'talks') {
      records.addAll(
        (dsFixture('talks_detail_since.json')['items'] as Map).cast(),
      );
      // The newer title only exists after the first edition.
      if (_talkListings < 2) {
        records['99974'] = (base['items'] as Map)['99974'];
      }
    }
    final wanted = request.items.map((id) => '$id').toSet();
    return {
      'edition': base['edition'],
      'items': {
        for (final entry in records.entries)
          if (wanted.contains(entry.key)) entry.key: entry.value,
      },
      'x_items': base['x_items'],
    };
  }

  static Map<String, String> _multipartFields(http.Request request) {
    final body = utf8.decode(request.bodyBytes);
    return {
      for (final match in RegExp(
        r'name="([^"]+)"\r\n\r\n(.*?)\r\n--',
        dotAll: true,
      ).allMatches(body))
        match[1]!: match[2]!,
    };
  }
}
