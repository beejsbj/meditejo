import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /// Installs into [target] when it is needed: it has no complete catalogue,
  /// or the snapshot is newer than the catalogue it has.
  Future<DsSnapshotResult> installIfNeeded(File target) async {
    try {
      final manifest = await _manifest();
      if (manifest == null) return DsSnapshotResult.unavailable;

      final local = _localAsOf(target);
      if (local != null && !manifest.asOf.isAfter(local)) {
        return DsSnapshotResult.upToDate;
      }

      final clock = Stopwatch()..start();
      await _install(target, replacing: target.existsSync());
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

  /// How current the catalogue in [file] is: its oldest per-kind sync time.
  /// Null when there is no file, or it never completed a sync of every kind,
  /// in which case the snapshot is the better start.
  static DateTime? _localAsOf(File file) {
    if (!file.existsSync() || file.lengthSync() == 0) return null;
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      final rows = db.select(
        'SELECT kind, edition, last_synced_at FROM ds_sync_state',
      );
      DateTime? oldest;
      for (final kind in DsKind.values) {
        final row = rows.where((r) => r['kind'] == kind.name).firstOrNull;
        final at = row?['last_synced_at'];
        if (row == null || row['edition'] == null || at is! int) return null;
        final time = DateTime.fromMillisecondsSinceEpoch(
          at * 1000,
          isUtc: true,
        );
        if (oldest == null || time.isBefore(oldest)) oldest = time;
      }
      return oldest;
    } on SqliteException {
      return null; // not a catalogue database (yet)
    } finally {
      db.dispose();
    }
  }

  Future<void> _install(File target, {required bool replacing}) async {
    final staged = File('${target.path}.installing');
    await target.parent.create(recursive: true);
    if (staged.existsSync()) await staged.delete();
    try {
      final compressed = await readDatabase();
      final sink = staged.openWrite();
      await sink.addStream(
        Stream<List<int>>.value(compressed).transform(gzip.decoder),
      );
      await sink.close();
      if (replacing) _carryOverSaves(from: target, to: staged);
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        final old = File('${target.path}$suffix');
        if (old.existsSync()) await old.delete();
      }
      await staged.rename(target.path);
    } catch (_) {
      if (staged.existsSync()) await staged.delete();
      rethrow;
    }
  }

  /// The old "Save course / teacher" rows live in the catalogue database, so
  /// they are copied into the new file; the library migration reads them.
  static void _carryOverSaves({required File from, required File to}) {
    try {
      final db = sqlite3.open(to.path);
      try {
        db.execute('ATTACH DATABASE ? AS old', [from.path]);
        db.execute(
          'INSERT OR IGNORE INTO ds_saved (kind, item_id, saved_at) '
          'SELECT kind, item_id, saved_at FROM old.ds_saved',
        );
        db.execute('DETACH DATABASE old');
      } finally {
        db.dispose();
      }
    } on SqliteException catch (e) {
      AppLogger.w('DHARMA_SEED', 'Could not carry over saved items: $e');
    }
  }
}
