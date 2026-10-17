import 'dart:io';

import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/import_http.dart';
import 'package:medito/services/library/import_service.dart';
import 'package:medito/services/library/lib_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_store.dart';

import 'dharma_seed_fake_api.dart';

String libraryFixture(String name) =>
    File('test/fixtures/library/$name').readAsStringSync();

LibraryDatabase memoryLibraryDb() {
  // Registers the system SQLite for host tests, as the Dharma Seed helper does.
  memoryDharmaSeedDb().close();
  return LibraryDatabase(NativeDatabase.memory());
}

/// A scripted web: addresses map to responses, and every request is recorded.
class FakeWeb {
  FakeWeb(this.routes, {this.offline = false});

  /// Every request fails to connect, as with no network.
  final bool offline;

  /// Address → response. A [http.Response] is returned as it stands.
  final Map<String, http.Response> routes;
  final List<http.BaseRequest> requests = [];

  /// A client that answers from [handler], still recording requests.
  MockClient clientWith(http.Response Function(http.BaseRequest) handler) =>
      MockClient((request) async {
        requests.add(request);
        return handler(request);
      });

  MockClient get client => MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('Failed host lookup');
    return routes[request.url.toString()] ??
        http.Response(
          'not found',
          404,
          headers: {'content-type': 'text/plain'},
        );
  });

  List<String> get urls => [for (final r in requests) r.url.toString()];
}

http.Response xmlResponse(
  String body, {
  Map<String, String> headers = const {},
}) => http.Response(
  body,
  200,
  headers: {'content-type': 'application/rss+xml; charset=utf-8', ...headers},
);

http.Response htmlResponse(String body) => http.Response(
  body,
  200,
  headers: {'content-type': 'text/html; charset=utf-8'},
);

http.Response audioResponse() =>
    http.Response('', 200, headers: {'content-type': 'audio/mpeg'});

/// The whole import stack over in-memory databases and a [FakeWeb], with
/// files going to a scratch folder.
class LibraryHarness {
  LibraryHarness._(
    this.db,
    this.store,
    this.lib,
    this.web,
    this.service,
    this.storage,
    this.dharmaSeed,
    this.dsDb,
  );

  final LibraryDatabase db;
  final LibraryStore store;
  final LibSource lib;
  final FakeWeb web;
  final ImportService service;
  final Directory storage;
  final DharmaSeedSource? dharmaSeed;
  final DharmaSeedDatabase? dsDb;

  static LibraryHarness create({
    Map<String, http.Response> routes = const {},
    bool offline = false,
    Future<int?> Function(String)? probe,
    DharmaSeedDatabase? dsDb,
    DharmaSeedSource? Function(LibraryStore)? dharmaSeed,
  }) {
    final db = memoryLibraryDb();
    final store = LibraryStore(db);
    final lib = LibSource(db: db, library: store);
    final web = FakeWeb(routes, offline: offline);
    final storage = Directory.systemTemp.createTempSync('library_test');
    final ds = dharmaSeed?.call(store);
    final service = ImportService(
      http: ImportHttp(client: web.client),
      lib: lib,
      library: store,
      dharmaSeed: ds,
      storageDirectory: () async => storage,
      durationProbe: probe,
      clock: () => DateTime.utc(2026, 10, 17, 12),
    );
    return LibraryHarness._(db, store, lib, web, service, storage, ds, dsDb);
  }

  Future<void> dispose() async {
    await db.close();
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  }

  File writeAudio(String name, {String content = 'ID3 fake audio'}) {
    final file = File('${storage.path}/inbox/$name')
      ..createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }
}
