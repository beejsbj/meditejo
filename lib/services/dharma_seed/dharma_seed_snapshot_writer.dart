import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_snapshot.dart';
import 'package:sqlite3/sqlite3.dart';

/// Turns a fully synced catalogue database into the bundled snapshot: a
/// compacted copy, gzip-compressed, with a manifest beside it. Build time only
/// (`tools/meditejo/dharma_seed_snapshot.dart`, `release.sh`) and tests.
class DharmaSeedSnapshotWriter {
  const DharmaSeedSnapshotWriter._();

  static const databaseFileName = 'catalogue.sqlite.gz';
  static const manifestFileName = 'catalogue.json';

  /// Reads the manifest already in [directory], or null.
  static DsSnapshotManifest? existing(Directory directory) {
    final file = File('${directory.path}/$manifestFileName');
    if (!file.existsSync()) return null;
    try {
      return DsSnapshotManifest.fromJson(
        (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Compacts [source] (closed, fully synced) into [directory]. Throws when
  /// any kind of record still has work pending, since a half-synced snapshot
  /// would make the app's first delta enormous. [source] is modified: the
  /// fetch queue and the user's saved rows are emptied, and the full-text
  /// indexes merged.
  static Future<DsSnapshotManifest> write({
    required File source,
    required Directory directory,
  }) async {
    await directory.create(recursive: true);
    final compact = File('${directory.path}/.catalogue.sqlite.tmp');
    if (compact.existsSync()) compact.deleteSync();
    final db = sqlite3.open(source.path);
    try {
      _requireComplete(db);
      db.execute('DELETE FROM ds_sync_queue');
      db.execute('DELETE FROM ds_saved');
      db.execute('UPDATE ds_sync_state SET last_error = NULL');
      for (final fts in const [
        'ds_talks_fts',
        'ds_retreats_fts',
        'ds_teachers_fts',
      ]) {
        db.execute("INSERT INTO $fts($fts) VALUES('optimize')");
      }
      db.execute('VACUUM INTO ?', [compact.path]);
    } finally {
      db.dispose();
    }

    final manifest = await _describe(compact);
    final packed = File('${directory.path}/.$databaseFileName.tmp');
    await compact
        .openRead()
        .transform(GZipCodec(level: ZLibOption.maxLevel).encoder)
        .pipe(packed.openWrite());
    await compact.delete();
    await packed.rename('${directory.path}/$databaseFileName');
    File('${directory.path}/$manifestFileName').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
    );
    return manifest;
  }

  static void _requireComplete(Database db) {
    final rows = db.select('SELECT * FROM ds_sync_state');
    for (final kind in DsKind.values) {
      final row = rows.where((r) => r['kind'] == kind.name).firstOrNull;
      if (row == null ||
          row['edition'] == null ||
          row['last_synced_at'] == null ||
          row['pending_edition'] != null) {
        throw StateError('The ${kind.name} sync has not finished.');
      }
      final queued =
          db.select('SELECT COUNT(*) AS n FROM ds_sync_queue WHERE kind = ?', [
                kind.name,
              ]).single['n']
              as int;
      if (queued > 0) {
        throw StateError('The ${kind.name} sync still has $queued queued.');
      }
    }
  }

  static Future<DsSnapshotManifest> _describe(File compact) async {
    final db = sqlite3.open(compact.path, mode: OpenMode.readOnly);
    try {
      final editions = <String, String>{};
      DateTime? oldest;
      for (final row in db.select(
        'SELECT kind, edition, last_synced_at FROM ds_sync_state',
      )) {
        editions[row['kind'] as String] = row['edition'] as String;
        final at = DateTime.fromMillisecondsSinceEpoch(
          (row['last_synced_at'] as int) * 1000,
          isUtc: true,
        );
        if (oldest == null || at.isBefore(oldest)) oldest = at;
      }
      int count(String table) =>
          db.select('SELECT COUNT(*) AS n FROM $table').single['n'] as int;
      return DsSnapshotManifest(
        schema: DsSnapshotManifest.supportedSchema,
        databaseSchema:
            db.select('PRAGMA user_version').single['user_version'] as int,
        asOf: oldest!,
        editions: editions,
        counts: {
          'teachers': count('ds_teachers'),
          'retreats': count('ds_retreats'),
          'talks': count('ds_talks'),
        },
        bytes: compact.lengthSync(),
        sha256: (await sha256.bind(compact.openRead()).first).toString(),
      );
    } finally {
      db.dispose();
    }
  }
}
