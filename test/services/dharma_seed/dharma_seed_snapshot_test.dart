import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_snapshot.dart';
import 'package:medito/services/dharma_seed/dharma_seed_snapshot_writer.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../../helpers/dharma_seed_fake_api.dart';

/// A snapshot made the way the build tool makes one, from the recorded API
/// fixtures: a real sync into a file, compacted and gzipped.
class _Built {
  _Built(this.snapshot, this.manifest);

  final DharmaSeedSnapshot snapshot;
  final DsSnapshotManifest manifest;
}

void main() {
  late Directory dir;
  late File target;
  final builtAt = DateTime.utc(2026, 10, 19, 12);

  setUp(() {
    useSystemSqlite();
    // The unpacking isolate needs the same SQLite the tests use.
    DharmaSeedSnapshot.isolateSetup = useSystemSqlite;
    dir = Directory.systemTemp.createTempSync('ds_snapshot_test');
    target = File('${dir.path}/app/dharma_seed.sqlite');
  });
  tearDown(() {
    DharmaSeedSnapshot.isolateSetup = null;
    dir.deleteSync(recursive: true);
  });

  Future<_Built> build({DateTime? at, String name = 'snapshot'}) async {
    final work = File('${dir.path}/$name-work.sqlite');
    final db = DharmaSeedDatabase(NativeDatabase(work));
    await DharmaSeedSync(
      db: db,
      client: FakeDharmaSeedApi().client(),
      clock: () => at ?? builtAt,
      sleep: (_) async {},
    ).sync();
    await db.close();
    final out = Directory('${dir.path}/$name');
    final manifest = await DharmaSeedSnapshotWriter.write(
      source: work,
      directory: out,
    );
    return _Built(
      DharmaSeedSnapshot(
        readManifest: () async =>
            File('${out.path}/catalogue.json').readAsString(),
        readDatabase: () async =>
            File('${out.path}/catalogue.sqlite.gz').readAsBytes(),
      ),
      manifest,
    );
  }

  Future<DharmaSeedDatabase> openTarget() async =>
      DharmaSeedDatabase(NativeDatabase(target));

  group('writer', () {
    test('compacts a finished sync into a gzip and a manifest', () async {
      final built = await build();
      final m = built.manifest;
      expect(m.counts, {'teachers': 3, 'retreats': 1, 'talks': 9});
      expect(m.editions, {
        'teachers': dsFirstEdition,
        'retreats': dsFirstEdition,
        'talks': dsFirstEdition,
      });
      expect(m.databaseSchema, DharmaSeedDatabase.currentSchemaVersion);
      expect(m.asOf, builtAt);
      expect(m.bytes, greaterThan(0));
      final packed = File('${dir.path}/snapshot/catalogue.sqlite.gz');
      expect(packed.lengthSync(), lessThan(m.bytes));
    });

    test('refuses a half-finished sync', () async {
      final work = File('${dir.path}/half.sqlite');
      final db = DharmaSeedDatabase(NativeDatabase(work));
      await db.enqueue(DsKind.talks, [1, 2, 3]);
      await db.writeSyncState(DsKind.talks, const DsSyncStateCompanion());
      await db.close();
      expect(
        DharmaSeedSnapshotWriter.write(
          source: work,
          directory: Directory('${dir.path}/half'),
        ),
        throwsStateError,
      );
    });
  });

  group('installing, with no network', () {
    test('a fresh install unpacks the catalogue and search works', () async {
      final built = await build();
      expect(target.existsSync(), isFalse);

      final result = await built.snapshot.installIfNeeded(target);

      expect(result, DsSnapshotResult.installed);
      // The unpacked file is byte-for-byte the database that was compacted.
      expect(
        (await sha256.bind(target.openRead()).first).toString(),
        built.manifest.sha256,
      );
      final db = await openTarget();
      addTearDown(db.close);
      expect(await db.countOf(DsKind.talks), 9);
      expect(await db.countOf(DsKind.teachers), 3);
      expect(await db.countOf(DsKind.retreats), 1);
      expect((await db.searchTalks('teintes')).map((h) => h.talk.id), [99974]);
      // The cursors the delta continues from, and nothing left to fetch.
      final talks = await db.syncState(DsKind.talks);
      expect(talks!.edition, dsFirstEdition);
      expect(talks.pendingEdition, isNull);
      expect(await db.queuedCount(DsKind.talks), 0);
      expect(File('${target.path}.installing').existsSync(), isFalse);
    });

    test('installing again changes nothing', () async {
      final built = await build();
      await built.snapshot.installIfNeeded(target);
      final stamp = target.lastModifiedSync();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        await built.snapshot.installIfNeeded(target),
        DsSnapshotResult.upToDate,
      );
      expect(target.lastModifiedSync(), stamp);
    });

    test('a newer snapshot replaces older local data', () async {
      final old = await build(at: DateTime.utc(2026, 10, 1), name: 'old');
      await old.snapshot.installIfNeeded(target);
      final newer = await build(name: 'new');

      expect(
        await newer.snapshot.installIfNeeded(target),
        DsSnapshotResult.installed,
      );
      final db = await openTarget();
      addTearDown(db.close);
      expect(
        (await db.syncState(DsKind.talks))!.lastSyncedAt!.toUtc(),
        builtAt,
      );
    });

    test('local data newer than the snapshot is never replaced', () async {
      final newer = await build(at: DateTime.utc(2026, 10, 25), name: 'new');
      await newer.snapshot.installIfNeeded(target);
      final older = await build(name: 'old');
      final stamp = target.lastModifiedSync();

      expect(
        await older.snapshot.installIfNeeded(target),
        DsSnapshotResult.upToDate,
      );
      expect(target.lastModifiedSync(), stamp);
    });

    test('replacing keeps the old "Save course / teacher" rows', () async {
      final old = await build(at: DateTime.utc(2026, 10, 1), name: 'old');
      await old.snapshot.installIfNeeded(target);
      var db = await openTarget();
      await db.setSaved(DsSavedKind.retreat, 6689, saved: true);
      await db.setSaved(DsSavedKind.teacher, 637, saved: true);
      await db.close();

      await (await build(name: 'new')).snapshot.installIfNeeded(target);

      db = await openTarget();
      addTearDown(db.close);
      expect(await db.savedIds(DsSavedKind.retreat), [6689]);
      expect(await db.savedIds(DsSavedKind.teacher), [637]);
    });

    test(
      'a catalogue that never finished its first sync is replaced',
      () async {
        // The app killed during the first full sync: teachers and retreats in,
        // talks still queued.
        final db = await openTarget();
        await db.upsertTeacherRecords({
          1: {'name': 'Someone'},
        });
        await db.enqueue(DsKind.talks, [1, 2]);
        await db.close();

        final built = await build();
        expect(
          await built.snapshot.installIfNeeded(target),
          DsSnapshotResult.installed,
        );
        final after = await openTarget();
        addTearDown(after.close);
        expect(await after.countOf(DsKind.talks), 9);
        expect(await after.queuedCount(DsKind.talks), 0);
      },
    );

    test('a damaged snapshot fails safely and leaves the data alone', () async {
      final good = await build(at: DateTime.utc(2026, 10, 1), name: 'old');
      await good.snapshot.installIfNeeded(target);
      final before = target.readAsBytesSync();
      final newer = await build(name: 'new');
      final broken = DharmaSeedSnapshot(
        readManifest: newer.snapshot.readManifest,
        readDatabase: () async => Uint8List.fromList([1, 2, 3, 4, 5]),
      );

      expect(await broken.installIfNeeded(target), DsSnapshotResult.failed);
      expect(target.readAsBytesSync(), before);
      expect(File('${target.path}.installing').existsSync(), isFalse);
    });

    test('a gzip that is not the described database fails safely', () async {
      final good = await build(at: DateTime.utc(2026, 10, 1), name: 'old');
      await good.snapshot.installIfNeeded(target);
      final before = target.readAsBytesSync();
      final newer = await build(name: 'new');
      final wrong = DharmaSeedSnapshot(
        readManifest: newer.snapshot.readManifest,
        // Valid gzip, but not a database, and not the size the manifest says.
        readDatabase: () async =>
            Uint8List.fromList(gzip.encode(List.filled(4096, 7))),
      );

      expect(await wrong.installIfNeeded(target), DsSnapshotResult.failed);
      expect(target.readAsBytesSync(), before);
      expect(File('${target.path}.installing').existsSync(), isFalse);
      expect(File('${target.path}.previous').existsSync(), isFalse);
    });

    test('a payload of the right size but another layout is refused', () async {
      final good = await build(at: DateTime.utc(2026, 10, 1), name: 'old');
      await good.snapshot.installIfNeeded(target);
      final before = target.readAsBytesSync();
      final newer = await build(name: 'new');
      final json =
          jsonDecode(await newer.snapshot.readManifest() ?? '')
              as Map<String, Object?>;
      final junk = Uint8List(json['bytes']! as int);
      final wrong = DharmaSeedSnapshot(
        readManifest: newer.snapshot.readManifest,
        readDatabase: () async => Uint8List.fromList(gzip.encode(junk)),
      );

      expect(await wrong.installIfNeeded(target), DsSnapshotResult.failed);
      expect(target.readAsBytesSync(), before);
    });

    test('saved rows that cannot be read abandon the install', () async {
      final old = await build(at: DateTime.utc(2026, 10, 1), name: 'old');
      await old.snapshot.installIfNeeded(target);
      var db = await openTarget();
      await db.setSaved(DsSavedKind.retreat, 6689, saved: true);
      await db.close();
      final before = target.readAsBytesSync();

      // Another connection holds the file exclusively, as a busy disk would.
      final holder = raw.sqlite3.open(target.path)
        ..execute('BEGIN EXCLUSIVE');
      final result = await (await build(
        name: 'new',
      )).snapshot.installIfNeeded(target);
      holder.execute('ROLLBACK');
      holder.dispose();

      expect(result, DsSnapshotResult.failed);
      expect(target.readAsBytesSync(), before);
      db = await openTarget();
      addTearDown(db.close);
      expect(await db.savedIds(DsSavedKind.retreat), [6689]);
    });

    test('a checkpoint that a reader blocks abandons the install', () async {
      final old = await build(at: DateTime.utc(2026, 10, 1), name: 'old');
      await old.snapshot.installIfNeeded(target);
      // A WAL database with a save that only the log holds, and a reader
      // pinned to an older view so the log cannot be folded in.
      final reader = raw.sqlite3.open(target.path)
        ..execute('PRAGMA journal_mode=WAL')
        ..execute('BEGIN')
        ..select('SELECT count(*) FROM ds_saved');
      final writer = raw.sqlite3.open(target.path)
        ..execute(
          "INSERT INTO ds_saved (kind, item_id, saved_at) "
          "VALUES ('retreat', 6689, 1)",
        );
      writer.dispose();

      final result = await (await build(
        name: 'new',
      )).snapshot.installIfNeeded(target);
      reader.execute('ROLLBACK');
      reader.dispose();

      expect(result, DsSnapshotResult.failed);
      expect(File('${target.path}.previous').existsSync(), isFalse);
      final db = await openTarget();
      addTearDown(db.close);
      expect(await db.savedIds(DsSavedKind.retreat), [6689]);
    });

    test('a database that is not a catalogue is replaced', () async {
      target.parent.createSync(recursive: true);
      target.writeAsStringSync('this is not a database ' * 50);

      expect(
        await (await build()).snapshot.installIfNeeded(target),
        DsSnapshotResult.installed,
      );
      final db = await openTarget();
      addTearDown(db.close);
      expect(await db.countOf(DsKind.talks), 9);
    });

    test('a launch after a crash between the two renames restores the old '
        'database', () async {
      final old = await build(at: DateTime.utc(2026, 10, 1), name: 'old');
      await old.snapshot.installIfNeeded(target);
      final before = target.readAsBytesSync();
      // The state a crash leaves: old file moved aside, staged copy beside it.
      target.renameSync('${target.path}.previous');
      File('${target.path}.installing').writeAsStringSync('half');

      final none = DharmaSeedSnapshot(
        readManifest: () async => null,
        readDatabase: () async => throw StateError('not read'),
      );
      expect(await none.installIfNeeded(target), DsSnapshotResult.unavailable);

      expect(target.readAsBytesSync(), before);
      expect(File('${target.path}.previous').existsSync(), isFalse);
      expect(File('${target.path}.installing').existsSync(), isFalse);
    });

    test('a leftover old copy beside a complete install is cleared', () async {
      final built = await build();
      await built.snapshot.installIfNeeded(target);
      File('${target.path}.previous').writeAsStringSync('stale');

      expect(
        await built.snapshot.installIfNeeded(target),
        DsSnapshotResult.upToDate,
      );
      expect(File('${target.path}.previous').existsSync(), isFalse);
    });

    test('a device that synced one kind after the snapshot is kept', () async {
      // Teachers and retreats are newer than the snapshot, talks older (an
      // interrupted sync). Replacing would roll the newer kinds back.
      final old = await build(at: DateTime.utc(2026, 10, 18), name: 'old');
      await old.snapshot.installIfNeeded(target);
      var db = await openTarget();
      for (final kind in [DsKind.teachers, DsKind.retreats]) {
        await db.writeSyncState(
          kind,
          DsSyncStateCompanion(lastSyncedAt: Value(DateTime.utc(2026, 10, 20))),
        );
      }
      await db.close();
      final before = target.readAsBytesSync();

      expect(
        await (await build(name: 'new')).snapshot.installIfNeeded(target),
        DsSnapshotResult.upToDate,
      );
      expect(target.readAsBytesSync(), before);
    });

    test(
      'a build without a snapshot, or with another layout, is skipped',
      () async {
        final none = DharmaSeedSnapshot(
          readManifest: () async => null,
          readDatabase: () async => throw StateError('not read'),
        );
        expect(
          await none.installIfNeeded(target),
          DsSnapshotResult.unavailable,
        );
        expect(target.existsSync(), isFalse);

        final built = await build();
        final json =
            jsonDecode(await built.snapshot.readManifest() ?? '')
                as Map<String, Object?>;
        final other = DharmaSeedSnapshot(
          readManifest: () async => jsonEncode({...json, 'databaseSchema': 99}),
          readDatabase: built.snapshot.readDatabase,
        );
        expect(
          await other.installIfNeeded(target),
          DsSnapshotResult.unavailable,
        );
        expect(target.existsSync(), isFalse);
      },
    );
  });

  group('the delta', () {
    test(
      'only what changed since the snapshot is fetched, when asked',
      () async {
        final built = await build();
        await built.snapshot.installIfNeeded(target);
        final db = await openTarget();
        addTearDown(db.close);

        final api = FakeDharmaSeedApi();
        // The fixture's second edition comes after a first listing; the
        // snapshot's own sync was that first listing.
        await api.client().fetchIds(DsKind.talks);
        api.requests.clear();
        var now = builtAt.add(const Duration(hours: 1));
        final sync = DharmaSeedSync(
          db: db,
          client: api.client(),
          clock: () => now,
          sleep: (_) async {},
        );

        // Starting up reads the state and asks the server nothing.
        await sync.loadStatus();
        expect(api.requests, isEmpty);
        expect(sync.status.value.lastSyncedAt!.toUtc(), builtAt);

        // Opened soon after the snapshot was made: nothing is due yet.
        await sync.sync();
        expect(api.requests, isEmpty);

        // A day later, opening Search fetches the changes only.
        now = builtAt.add(const Duration(days: 1));
        await sync.sync();
        expect(api.requests.map((r) => r.toString()), [
          'teachers ids since $dsFirstEdition',
          'retreats ids since $dsFirstEdition',
          'talks ids since $dsFirstEdition',
          'talks detail [99974]',
        ]);
        expect(await db.talkById(95073), isNull, reason: 'removed upstream');
        expect(
          (await db.talkById(99974))!.title,
          'Ces teintes plaisantes (révisé)',
        );
        expect((await db.syncState(DsKind.talks))!.edition, dsSecondEdition);
        expect(await db.countOf(DsKind.talks), 8);
      },
    );

    testWidgets('opening Search or Explore catches up; launch does not', (
      tester,
    ) async {
      final api = FakeDharmaSeedApi();
      late DharmaSeedDatabase db;
      late DharmaSeedSync sync;
      // File and database work is real I/O: outside the test's fake clock.
      await tester.runAsync(() async {
        final built = await build();
        await built.snapshot.installIfNeeded(target);
        db = await openTarget();
        sync = DharmaSeedSync(
          db: db,
          client: api.client(),
          // Long after the snapshot, so the catch-up is due.
          clock: () => builtAt.add(const Duration(days: 3)),
          sleep: (_) async {},
        );
      });
      addTearDown(() => tester.runAsync(db.close));

      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dharmaSeedSyncProvider.overrideWithValue(sync)],
          child: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.runAsync(() => prepareDharmaSeed(ref));
      expect(api.requests, isEmpty, reason: 'startup stays off the network');

      await tester.runAsync(() async {
        catchUpDharmaSeed(ref);
        // The sync runs in the background; wait for it to finish.
        await sync.sync();
      });
      expect(
        api.requests.map((r) => r.toString()),
        contains('talks ids since $dsFirstEdition'),
      );
    });
  });

  test('the committed snapshot matches this build of the app', () {
    // Guards a schema change made without regenerating the snapshot: the app
    // would silently skip it and fall back to a full first sync.
    final manifest = DharmaSeedSnapshotWriter.existing(
      Directory('assets/dharma_seed'),
    );
    expect(manifest, isNotNull, reason: 'assets/dharma_seed/catalogue.json');
    expect(manifest!.schema, DsSnapshotManifest.supportedSchema);
    expect(
      manifest.databaseSchema,
      DharmaSeedDatabase.currentSchemaVersion,
      reason: 'rerun tools/meditejo/dharma_seed_snapshot.dart',
    );
    final packed = File('assets/dharma_seed/catalogue.sqlite.gz');
    expect(packed.existsSync(), isTrue);
    expect(manifest.counts['talks'], greaterThan(40000));
    // A Git LFS pointer or a truncated file would be tiny.
    expect(packed.lengthSync(), greaterThan(5 * 1024 * 1024));
    expect(
      manifest.editions.keys,
      containsAll(['teachers', 'retreats', 'talks']),
    );
    // The installer trusts gzip's CRC and does not hash at launch, so this is
    // where a wrong asset (unpacking to another database than the manifest
    // describes) is caught.
    final unpacked = gzip.decode(packed.readAsBytesSync());
    expect(unpacked.length, manifest.bytes);
    expect(sha256.convert(unpacked).toString(), manifest.sha256);
  });
}
