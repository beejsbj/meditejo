import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';

import '../../helpers/dharma_seed_fake_api.dart';

void main() {
  late DharmaSeedDatabase db;
  // Local time at whole seconds, as drift stores and returns it.
  var now = DateTime(2026, 10, 17, 8);

  setUp(() {
    db = memoryDharmaSeedDb();
    now = DateTime(2026, 10, 17, 8);
  });
  tearDown(() => db.close());

  DharmaSeedSync syncWith(
    FakeDharmaSeedApi api, {
    int talkBatch = 500,
    Future<void> Function(Duration)? sleep,
  }) => DharmaSeedSync(
    db: db,
    client: api.client(),
    batchSizes: {
      DsKind.teachers: 250,
      DsKind.retreats: 250,
      DsKind.talks: talkBatch,
    },
    clock: () => now,
    sleep: sleep ?? (_) async {},
  );

  test('first sync: teachers, then retreats, then talks', () async {
    final api = FakeDharmaSeedApi();
    final sync = syncWith(api);

    await sync.sync();

    expect(api.requests.map((r) => r.toString()), [
      'teachers ids since null',
      'teachers detail [637, 210, 198]',
      'retreats ids since null',
      'retreats detail [6689]',
      'talks ids since null',
      'talks detail [99974, 99944, 97073, 95953, 95800, 95545, 95421, 95232, 95073]',
    ]);
    expect(await db.countOf(DsKind.teachers), 3);
    expect(await db.countOf(DsKind.retreats), 1);
    expect(await db.countOf(DsKind.talks), 9);
    expect(await db.queuedCount(DsKind.talks), 0);
    for (final kind in DharmaSeedSync.order) {
      final state = await db.syncState(kind);
      expect(state!.edition, dsFirstEdition, reason: kind.name);
      expect(state.pendingEdition, isNull);
      expect(state.lastSyncedAt, now);
    }
    expect(sync.status.value.phase, DharmaSeedSyncPhase.idle);
    expect(sync.status.value.lastSyncedAt, now);
  });

  test('pauses between requests and never overlaps them', () async {
    var inFlight = 0;
    var overlapped = false;
    final api = FakeDharmaSeedApi(
      fail: (_, _) {
        // This request is in flight itself; another one would make two.
        if (inFlight > 1) overlapped = true;
        return null;
      },
    );
    final pauses = <Duration>[];
    final sync = DharmaSeedSync(
      db: db,
      client: DharmaSeedClient(
        httpClient: _Counting(api.httpClient, (d) => inFlight += d),
        sleep: (_) async {},
      ),
      batchSizes: const {
        DsKind.teachers: 1,
        DsKind.retreats: 1,
        DsKind.talks: 2,
      },
      pause: const Duration(hours: 1), // longer than any request
      sleep: (d) async => pauses.add(d),
    );

    await sync.sync();

    expect(overlapped, isFalse);
    // Every request after the first waits out the pause.
    expect(pauses, hasLength(api.requests.length - 1));
  });

  test('later syncs ask only for changes since the edition', () async {
    final api = FakeDharmaSeedApi();
    final sync = syncWith(api);
    await sync.sync();
    api.requests.clear();
    now = now.add(const Duration(days: 1));

    await sync.sync(force: true);

    expect(api.requests.map((r) => r.toString()), [
      'teachers ids since $dsFirstEdition',
      'retreats ids since $dsFirstEdition',
      'talks ids since $dsFirstEdition',
      'talks detail [99974]',
    ]);
    // x_items removed the talk; the changed talk was refetched.
    expect(await db.talkById(95073), isNull);
    expect((await db.talkById(99974))!.title, 'Ces teintes plaisantes (révisé)');
    expect((await db.syncState(DsKind.talks))!.edition, dsSecondEdition);
    final hits = await db.searchTalks('révisé');
    expect(hits.map((h) => h.talk.id), [99974]);
  });

  test('automatic syncs skip while the last full sync is recent', () async {
    final api = FakeDharmaSeedApi();
    final sync = syncWith(api);
    await sync.sync();
    final made = api.requests.length;

    now = now.add(const Duration(hours: 2));
    await sync.sync();
    expect(api.requests, hasLength(made));

    now = now.add(const Duration(hours: 11));
    await sync.sync();
    expect(api.requests.length, greaterThan(made));
  });

  test('a killed sync resumes from its queue without refetching', () async {
    // The app "dies" on the third talk batch.
    var dead = false;
    final api = FakeDharmaSeedApi(
      fail: (request, _) {
        if (dead) return http.Response('killed', 400);
        return null;
      },
    );
    var talkBatches = 0;
    api.fail = (request, _) {
      if (request.kind == 'talks' && request.isDetail && ++talkBatches == 3) {
        dead = true;
      }
      return dead ? http.Response('killed', 400) : null;
    };
    final first = syncWith(api, talkBatch: 2);
    await first.sync();

    expect(first.status.value.phase, DharmaSeedSyncPhase.failed);
    expect(await db.countOf(DsKind.talks), 4);
    expect(await db.queuedCount(DsKind.talks), 5);
    expect(
      (await db.syncState(DsKind.talks))!.pendingEdition,
      dsFirstEdition,
    );
    expect((await db.syncState(DsKind.talks))!.edition, isNull);

    // A fresh service on the same database, as after a restart.
    dead = false;
    api.fail = null;
    api.requests.clear();
    final second = syncWith(api, talkBatch: 2);
    await second.sync();

    expect(api.requests.map((r) => r.toString()), [
      'talks detail [95800, 95545]',
      'talks detail [95421, 95232]',
      'talks detail [95073]',
    ]);
    expect(await db.countOf(DsKind.talks), 9);
    expect((await db.syncState(DsKind.talks))!.edition, dsFirstEdition);
    expect(second.status.value.phase, DharmaSeedSyncPhase.idle);
  });

  test('after a failure, automatic syncs wait out a cooldown', () async {
    final down = FakeDharmaSeedApi(fail: (_, _) => http.Response('', 503));
    final sync = DharmaSeedSync(
      db: db,
      client: DharmaSeedClient(
        httpClient: down.httpClient,
        maxAttempts: 2,
        sleep: (_) async {},
      ),
      clock: () => now,
      sleep: (_) async {},
    );

    await sync.sync();
    expect(sync.status.value.phase, DharmaSeedSyncPhase.failed);
    final after = down.requests.length;
    expect(after, greaterThan(0));

    // The next tab change, a minute later: no new requests.
    now = now.add(const Duration(minutes: 1));
    await sync.sync();
    expect(down.requests.length, after);

    // A manual refresh ignores the cooldown.
    await sync.sync(force: true);
    expect(down.requests.length, greaterThan(after));

    // And once the cooldown has passed, automatic syncs try again.
    final tried = down.requests.length;
    now = now.add(const Duration(hours: 1));
    await sync.sync();
    expect(down.requests.length, greaterThan(tried));
  });

  test('offline: fails quietly and keeps what is stored', () async {
    final api = FakeDharmaSeedApi();
    await syncWith(api).sync();

    final offline = FakeDharmaSeedApi(fail: (_, _) => http.Response('', 503));
    final sync = DharmaSeedSync(
      db: db,
      client: DharmaSeedClient(
        httpClient: offline.httpClient,
        maxAttempts: 2,
        sleep: (_) async {},
      ),
      sleep: (_) async {},
    );
    await sync.sync(force: true);

    expect(sync.status.value.phase, DharmaSeedSyncPhase.failed);
    expect(sync.status.value.error, 'HTTP 503');
    expect(await db.countOf(DsKind.talks), 9);
  });

  group('on demand', () {
    test('ensureRetreatTalks fetches a retreat and its missing talks', () async {
      final api = FakeDharmaSeedApi();
      final sync = syncWith(api);

      await sync.ensureRetreatTalks(6689);

      expect(api.requests.map((r) => r.toString()), [
        'retreats detail [6689]',
        'talks detail [95073, 95232, 95421, 95545, 95800, 95953, 99944, 90000001]',
        'teachers detail [637]',
      ]);
      final talks = await db.talksOfRetreat(6689);
      expect(talks, hasLength(7));
      // The talk Dharma Seed no longer serves leaves the course.
      final retreat = (await db.retreatById(6689))!;
      expect(DharmaSeedDatabase.talkIdsOf(retreat), isNot(contains(90000001)));

      api.requests.clear();
      await sync.ensureRetreatTalks(6689);
      expect(api.requests, isEmpty);
    });

    test('ensureTalk reports talks that are gone', () async {
      final api = FakeDharmaSeedApi();
      final sync = syncWith(api);

      expect(await sync.ensureTalk(95073), isTrue);
      expect(await sync.ensureTalk(95073), isTrue);
      expect(await sync.ensureTalk(1), isFalse);
      expect(api.requests.map((r) => r.toString()), [
        'talks detail [95073]',
        'teachers detail [637]',
        'talks detail [1]',
      ]);
      // The teacher arrived after the talk; search still finds it by name.
      expect(await db.searchTalks('shepherd'), hasLength(1));
    });

    test('priority fetches go ahead of queued background batches', () async {
      final api = FakeDharmaSeedApi();
      // A real (short) pause keeps the lane busy between background batches,
      // as on a device.
      final sync = syncWith(
        api,
        talkBatch: 1,
        sleep: (_) => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      final background = sync.sync();
      // Let the background reach the talk queue, then ask for a retreat.
      while (!api.requests.any((r) => r.kind == 'talks' && r.isDetail)) {
        await Future<void>.delayed(Duration.zero);
      }
      final opened = sync.ensureTalk(95232);
      await Future.wait([background, opened]);

      final talkDetails = [
        for (final r in api.requests)
          if (r.kind == 'talks' && r.isDetail) r.items.single,
      ];
      // 95232 is near the end of the background order but fetched early.
      expect(talkDetails.indexOf(95232), lessThan(3));
      expect(talkDetails.where((id) => id == 95232), hasLength(1));
    });
  });
}

/// Tracks concurrent in-flight requests through [onDelta].
class _Counting extends http.BaseClient {
  _Counting(this._inner, this.onDelta);

  final http.Client _inner;
  final void Function(int delta) onDelta;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onDelta(1);
    try {
      final response = await _inner.send(request);
      final bytes = await response.stream.toBytes();
      await Future<void>.delayed(Duration.zero);
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        headers: response.headers,
      );
    } finally {
      onDelta(-1);
    }
  }
}
