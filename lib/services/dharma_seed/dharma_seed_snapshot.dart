import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/utils/logger.dart';
import 'package:sqlite3/sqlite3.dart';

/// The Dharma Seed catalogue shipped inside the app: a compressed copy of the
/// catalogue database (text only, never audio) made by
/// `tools/meditejo/dharma_seed_snapshot.dart` at release time.
///
/// A fresh install would otherwise sync all ~49k talks (124 requests, a few
/// minutes) before search worked. Instead the snapshot is unpacked from the
/// app, with no network, and only what changed since its editions is fetched
/// afterwards (see `DharmaSeedSync`), when the user opens Search or Explore.
class DsSnapshotManifest {
  const DsSnapshotManifest({
    required this.schema,
    required this.databaseSchema,
    required this.asOf,
    required this.editions,
    required this.counts,
    required this.bytes,
    required this.sha256,
  });

  factory DsSnapshotManifest.fromJson(Map<String, Object?> json) =>
      DsSnapshotManifest(
        schema: json['schema']! as int,
        databaseSchema: json['databaseSchema']! as int,
        asOf: DateTime.parse(json['asOf']! as String).toUtc(),
        editions: (json['editions']! as Map).cast<String, String>(),
        counts: (json['counts']! as Map).cast<String, int>(),
        bytes: json['bytes']! as int,
        sha256: json['sha256']! as String,
      );

  /// The manifest format this code reads.
  static const supportedSchema = 1;

  final int schema;

  /// `PRAGMA user_version` of the database inside: the layout it was made with.
  final int databaseSchema;

  /// When the catalogue was last fully in step with Dharma Seed: the oldest
  /// per-kind `last_synced_at`, the same measure the app uses for its own data.
  final DateTime asOf;

  /// The `edition` cursor of each kind (`teachers`, `retreats`, `talks`) that
  /// the delta continues from.
  final Map<String, String> editions;

  /// Rows per kind.
  final Map<String, int> counts;

  /// Size of the database once unpacked.
  final int bytes;

  /// SHA-256 of the unpacked database, for the build tool and tests.
  final String sha256;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'databaseSchema': databaseSchema,
    'asOf': asOf.toIso8601String(),
    'editions': editions,
    'counts': counts,
    'bytes': bytes,
    'sha256': sha256,
  };
}

enum DsSnapshotResult {
  /// The snapshot was unpacked into place.
  installed,

  /// The data on the device is as new as the snapshot, or newer.
  upToDate,

  /// This build has no usable snapshot (a dev build, or a layout mismatch).
  unavailable,

  /// Unpacking failed; the app carries on with whatever is on the device and
  /// the ordinary first sync.
  failed,
}

/// Unpacks the bundled snapshot into the catalogue database file when the
/// device has no catalogue yet, or the snapshot is newer than the one it has.
///
/// This runs before the database is first opened, offline. It never throws.
///
/// Safety, in order: the unpacked copy is built and checked beside the
/// database (size and layout against the manifest), the saved rows are carried
/// into it (a failure there abandons the install), and only then is the old
/// file moved aside and the new one renamed into place. The old file is kept
/// until the new one is in place, and a crash between the two renames is
/// undone on the next launch ([_recover]). The unpacking itself runs in a
/// separate isolate so the 35 MiB inflate never blocks the UI thread.
class DharmaSeedSnapshot {
  DharmaSeedSnapshot({required this.readManifest, required this.readDatabase});

  /// The snapshot inside the app's assets.
  factory DharmaSeedSnapshot.bundled() => DharmaSeedSnapshot(
    readManifest: () async {
      try {
        return await rootBundle.loadString(manifestAsset);
      } catch (_) {
        return null; // no asset in this build
      }
    },
    readDatabase: () async =>
        (await rootBundle.load(databaseAsset)).buffer.asUint8List(),
  );

  static const manifestAsset = 'assets/dharma_seed/catalogue.json';
  static const databaseAsset = 'assets/dharma_seed/catalogue.sqlite.gz';

  /// The manifest's JSON text, or null when there is none.
  final Future<String?> Function() readManifest;

  /// The gzip-compressed database.
  final Future<Uint8List> Function() readDatabase;

  /// Runs first inside the unpacking isolate. Tests use it to point that
  /// isolate at the system SQLite, as they do for the main one.
  @visibleForTesting
  static void Function()? isolateSetup;

  /// Installs into [target] when it is needed: it has no complete catalogue,
  /// or the snapshot is newer than the catalogue it has.
  Future<DsSnapshotResult> installIfNeeded(File target) async {
    try {
      _recover(target);
      final manifest = await _manifest();
      if (manifest == null) return DsSnapshotResult.unavailable;

      final local = _localAsOf(target);
      if (local != null && !manifest.asOf.isAfter(local)) {
        return DsSnapshotResult.upToDate;
      }

      final clock = Stopwatch()..start();
      await _install(target, manifest, replacing: target.existsSync());
      AppLogger.d(
        'DHARMA_SEED',
        'Installed the bundled catalogue (${manifest.counts}) in '
            '${clock.elapsedMilliseconds} ms',
      );
      return DsSnapshotResult.installed;
    } catch (e, st) {
      AppLogger.e(
        'DHARMA_SEED',
        'Could not install the bundled catalogue',
        e,
        st,
      );
      return DsSnapshotResult.failed;
    }
  }

  Future<DsSnapshotManifest?> _manifest() async {
    final text = await readManifest();
    if (text == null) return null;
    final manifest = DsSnapshotManifest.fromJson(
      (jsonDecode(text) as Map).cast<String, Object?>(),
    );
    if (manifest.schema != DsSnapshotManifest.supportedSchema ||
        manifest.databaseSchema != DharmaSeedDatabase.currentSchemaVersion) {
      AppLogger.w('DHARMA_SEED', 'The bundled catalogue has another layout');
      return null;
    }
    return manifest;
  }

  /// How current the catalogue in [file] is: its newest per-kind sync time,
  /// so a device that has synced anything since the snapshot was made is never
  /// rolled back (its own incremental sync continues from its own cursors).
  /// Null when there is no file, or it never completed a sync of every kind
  /// (a first sync killed part-way): the snapshot is then the better start,
  /// since it brings the missing kind whole, and the delta refetches whatever
  /// the other kinds gained since, a few requests.
  static DateTime? _localAsOf(File file) {
    if (!file.existsSync() || file.lengthSync() == 0) return null;
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      final rows = db.select(
        'SELECT kind, edition, last_synced_at FROM ds_sync_state',
      );
      DateTime? newest;
      for (final kind in DsKind.values) {
        final row = rows.where((r) => r['kind'] == kind.name).firstOrNull;
        final at = row?['last_synced_at'];
        if (row == null || row['edition'] == null || at is! int) return null;
        final time = DateTime.fromMillisecondsSinceEpoch(
          at * 1000,
          isUtc: true,
        );
        if (newest == null || time.isAfter(newest)) newest = time;
      }
      return newest;
    } on SqliteException {
      return null; // not a catalogue database (yet)
    } finally {
      db.dispose();
    }
  }

  /// Undoes an install that was interrupted: leftovers of the staged copy go,
  /// and an old database moved aside but not replaced comes back.
  static void _recover(File target) {
    final staged = File('${target.path}.installing');
    final previous = File('${target.path}.previous');
    if (staged.existsSync()) staged.deleteSync();
    if (!previous.existsSync()) return;
    if (target.existsSync()) {
      previous.deleteSync();
    } else {
      previous.renameSync(target.path);
    }
  }

  Future<void> _install(
    File target,
    DsSnapshotManifest manifest, {
    required bool replacing,
  }) async {
    final staged = File('${target.path}.installing');
    final previous = File('${target.path}.previous');
    await target.parent.create(recursive: true);
    var movedAside = false;
    try {
      final request = _StageRequest(
        compressed: TransferableTypedData.fromList([await readDatabase()]),
        stagedPath: staged.path,
        oldPath: replacing ? target.path : null,
        expectedBytes: manifest.bytes,
        expectedSchema: manifest.databaseSchema,
        setup: isolateSetup,
      );
      await Isolate.run(() => _stage(request));

      if (replacing) {
        await target.rename(previous.path);
        movedAside = true;
        for (final suffix in const ['-wal', '-shm', '-journal']) {
          final old = File('${target.path}$suffix');
          if (old.existsSync()) await old.delete();
        }
      }
      await staged.rename(target.path);
      if (previous.existsSync()) {
        try {
          await previous.delete();
        } on FileSystemException {
          // Harmless: the next launch removes it ([_recover]).
        }
      }
    } catch (_) {
      if (movedAside && !target.existsSync() && previous.existsSync()) {
        await previous.rename(target.path);
      }
      if (staged.existsSync()) await staged.delete();
      rethrow;
    }
  }
}

class _StageRequest {
  const _StageRequest({
    required this.compressed,
    required this.stagedPath,
    required this.oldPath,
    required this.expectedBytes,
    required this.expectedSchema,
    required this.setup,
  });

  final TransferableTypedData compressed;
  final String stagedPath;
  final String? oldPath;
  final int expectedBytes;
  final int expectedSchema;
  final void Function()? setup;
}

/// Builds the staged database in a worker isolate: inflates the snapshot,
/// checks it is the database the manifest describes, and carries the old saved
/// rows into it. Throws on any problem, which abandons the install with the
/// old database untouched.
void _stage(_StageRequest request) {
  request.setup?.call();
  final staged = File(request.stagedPath);
  if (staged.existsSync()) staged.deleteSync();
  try {
    final bytes = gzip.decode(request.compressed.materialize().asUint8List());
    if (bytes.length != request.expectedBytes) {
      throw StateError(
        'The bundled catalogue unpacks to ${bytes.length} bytes, '
        'not ${request.expectedBytes}',
      );
    }
    // gzip's own CRC has already vouched for the asset's bytes. The manifest's
    // SHA-256 is not recomputed here (about a second on bjslab, several on a
    // phone, at first launch); a test checks the committed asset against it.
    staged.writeAsBytesSync(bytes, flush: true);

    final db = sqlite3.open(staged.path);
    try {
      final version =
          db.select('PRAGMA user_version').first.values.first as int;
      if (version != request.expectedSchema) {
        throw StateError('The bundled catalogue has layout $version');
      }
      db.select('SELECT 1 FROM ds_sync_state LIMIT 1');
      final old = request.oldPath;
      if (old != null) _carryOverSaves(db, oldPath: old);
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      db.dispose();
    }
  } catch (_) {
    if (staged.existsSync()) staged.deleteSync();
    rethrow;
  }
}

/// The old "Save course / teacher" rows live in the catalogue database, so
/// they are copied into the new file; the library migration reads them.
///
/// An old file that is not a readable catalogue holds nothing to keep. Any
/// other failure (disk full, locked, I/O) propagates: better to keep the old
/// database and its saves than to replace it without them.
void _carryOverSaves(Database staged, {required String oldPath}) {
  final List<Row> rows;
  final old = sqlite3.open(oldPath);
  try {
    // Fold the write-ahead log in, so the file moved aside is complete. A
    // checkpoint another connection blocks reports it in the result row
    // (busy, log frames, frames checkpointed) instead of throwing.
    final checkpoint = old.select('PRAGMA wal_checkpoint(TRUNCATE)').first;
    final busy = checkpoint.columnAt(0) as int;
    final log = checkpoint.columnAt(1) as int;
    final done = checkpoint.columnAt(2) as int;
    if (busy != 0 || (log >= 0 && log != done)) {
      throw StateError('The catalogue database is busy; not replacing it');
    }
    rows = old.select('SELECT kind, item_id, saved_at FROM ds_saved');
  } on SqliteException catch (e) {
    const unreadable = {1, 11, 26}; // error (no table), corrupt, not a database
    if (unreadable.contains(e.resultCode)) return;
    rethrow;
  } finally {
    old.dispose();
  }
  staged.execute('BEGIN');
  try {
    final insert = staged.prepare(
      'INSERT OR IGNORE INTO ds_saved (kind, item_id, saved_at) '
      'VALUES (?, ?, ?)',
    );
    try {
      for (final row in rows) {
        insert.execute([row['kind'], row['item_id'], row['saved_at']]);
      }
    } finally {
      insert.dispose();
    }
    staged.execute('COMMIT');
  } catch (_) {
    staged.execute('ROLLBACK');
    rethrow;
  }
}
