import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';

part 'dharma_seed_database.g.dart';

/// On-device copy of Dharma Seed's catalogue metadata (never its audio), plus
/// sync bookkeeping and the user's saved retreats and teachers.
///
/// Full-text search uses SQLite FTS5 tables kept beside the records:
/// `ds_talks_fts` (title, description, teacher), `ds_retreats_fts` (name,
/// description) and `ds_teachers_fts` (name, bio). Each row's `rowid` is the
/// Dharma Seed ID. Writers in this class keep them in step.
@DataClassName('DsTeacher')
class DsTeachers extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get bio => text().withDefault(const Constant(''))();
  TextColumn get photo => text().withDefault(const Constant(''))();
  TextColumn get website => text().withDefault(const Constant(''))();
  BoolColumn get monastic => boolean().withDefault(const Constant(false))();
  BoolColumn get isPublic => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DsRetreat')
class DsRetreats extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get startDate => text().withDefault(const Constant(''))();
  TextColumn get endDate => text().withDefault(const Constant(''))();

  /// JSON list of the retreat's talk IDs, as Dharma Seed lists them. Known
  /// before the talks themselves sync, so progress and fetches can use it.
  TextColumn get talkIds => text().withDefault(const Constant('[]'))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DsTalk')
@TableIndex(name: 'ds_talks_retreat', columns: {#retreatId, #recDate})
@TableIndex(name: 'ds_talks_teacher', columns: {#teacherId})
class DsTalks extends Table {
  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get teacherId => integer().nullable()();
  IntColumn get retreatId => integer().nullable()();

  /// Site-relative path; see `dsAudioUrl`.
  TextColumn get audioUrl => text()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get recDate => text().withDefault(const Constant(''))();
  TextColumn get recordingType => text().withDefault(const Constant(''))();
  IntColumn get languageId => integer().nullable()();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Every teacher of a talk, including co-teachers beyond `teacher_id`.
@TableIndex(name: 'ds_talk_teachers_teacher', columns: {#teacherId})
class DsTalkTeachers extends Table {
  IntColumn get talkId => integer()();
  IntColumn get teacherId => integer()();

  @override
  Set<Column> get primaryKey => {talkId, teacherId};
}

/// Per record kind: the edition last fully applied, and the one being
/// applied while [DsSyncQueue] still holds its IDs.
@DataClassName('DsSyncStateRow')
class DsSyncState extends Table {
  TextColumn get kind => text()();
  TextColumn get edition => text().nullable()();
  TextColumn get pendingEdition => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {kind};
}

/// IDs listed by the server but not yet fetched in detail. Surviving here is
/// what makes a killed sync resume where it stopped.
@DataClassName('DsQueuedItem')
class DsSyncQueue extends Table {
  TextColumn get kind => text()();
  IntColumn get itemId => integer()();

  @override
  Set<Column> get primaryKey => {kind, itemId};
}

/// Retreats and teachers the user saved. Talk favourites use the app's
/// existing favourites.
@DataClassName('DsSavedItem')
class DsSaved extends Table {
  TextColumn get kind => text()(); // 'retreat' | 'teacher'
  IntColumn get itemId => integer()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {kind, itemId};
}

enum DsSavedKind { retreat, teacher }

/// A talk with its primary teacher, as search and mapping need it.
class DsTalkWithTeacher {
  const DsTalkWithTeacher(this.talk, this.teacher);

  final DsTalk talk;
  final DsTeacher? teacher;
}

class DsTalkFilter {
  const DsTalkFilter({
    this.minDuration,
    this.maxDuration,
    this.recordingTypes,
    this.group,
  });

  /// Inclusive lower bound on length.
  final Duration? minDuration;

  /// Exclusive upper bound on length.
  final Duration? maxDuration;

  /// Raw `recording_type` values to include; null for all.
  final Set<String>? recordingTypes;

  /// Practice or Talks, as the Explore chips choose; null for both.
  final DsContentGroup? group;

  /// SQL conditions on a `ds_talks` row aliased [alias], with their values.
  /// Null when the filter can match nothing.
  ({List<String> where, List<Variable> variables})? toSql(String alias) {
    final where = <String>[];
    final variables = <Variable>[];
    // A talk with no recorded length (stored as 0) belongs to no bucket.
    if (minDuration != null || maxDuration != null) {
      where.add('$alias.duration_ms > 0');
    }
    if (minDuration case final min?) {
      where.add('$alias.duration_ms >= ?');
      variables.add(Variable.withInt(min.inMilliseconds));
    }
    if (maxDuration case final max?) {
      where.add('$alias.duration_ms < ?');
      variables.add(Variable.withInt(max.inMilliseconds));
    }
    if (recordingTypes case final types?) {
      if (types.isEmpty) return null;
      where.add(
        '$alias.recording_type IN (${List.filled(types.length, '?').join(',')})',
      );
      variables.addAll(types.map(Variable.withString));
    }
    if (group case final group?) {
      where.add(DharmaSeedDatabase.groupCondition(group, alias));
    }
    return (where: where, variables: variables);
  }
}

/// A teacher with how much of their material is stored, for browsing.
class DsTeacherSummary {
  const DsTeacherSummary(this.teacher, this.talkCount);

  final DsTeacher teacher;
  final int talkCount;
}

@DriftDatabase(
  tables: [
    DsTeachers,
    DsRetreats,
    DsTalks,
    DsTalkTeachers,
    DsSyncState,
    DsSyncQueue,
    DsSaved,
  ],
)
class DharmaSeedDatabase extends _$DharmaSeedDatabase {
  DharmaSeedDatabase(super.executor);

  /// The app's database file, opened on first query: constructing it touches
  /// no platform channel, so startup and unrelated tests never wait on it.
  factory DharmaSeedDatabase.open() => DharmaSeedDatabase(
    LazyDatabase(() => driftDatabase(name: 'dharma_seed')),
  );

  @override
  int get schemaVersion => 1;

  static const _ftsTokenizer = "tokenize = 'unicode61 remove_diacritics 2'";

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE VIRTUAL TABLE ds_talks_fts USING fts5('
        'title, description, teacher, $_ftsTokenizer)',
      );
      await customStatement(
        'CREATE VIRTUAL TABLE ds_retreats_fts USING fts5('
        'name, description, $_ftsTokenizer)',
      );
      await customStatement(
        'CREATE VIRTUAL TABLE ds_teachers_fts USING fts5('
        'name, bio, $_ftsTokenizer)',
      );
    },
  );

  // ---------------------------------------------------------------- writes

  /// Inserts or replaces teachers from API records. Contact fields
  /// (addresses, emails) are deliberately not stored.
  Future<void> upsertTeacherRecords(Map<int, Map<String, Object?>> records) {
    if (records.isEmpty) return Future.value();
    return transaction(() async {
      final previous = {
        for (final t in await (select(
          dsTeachers,
        )..where((t) => t.id.isIn(records.keys))).get())
          t.id: t.name,
      };
      await batch((b) {
        for (final MapEntry(key: id, value: r) in records.entries) {
          final name = r.str('name');
          final bio = r.str('bio');
          b.insert(
            dsTeachers,
            DsTeachersCompanion.insert(
              id: Value(id),
              name: name,
              bio: Value(bio),
              photo: Value(r.str('photo')),
              website: Value(r.str('website')),
              monastic: Value(r.flag('monastic')),
              isPublic: Value(!r.flag('non_public')),
              updatedAt: Value(r.str('update_date')),
            ),
            mode: InsertMode.insertOrReplace,
          );
          _replaceFts(b, 'ds_teachers_fts', id, [name, bio]);
          if (previous[id] != name) {
            // Talk search indexes the teacher's name: follow renames, and
            // fill it in for talks that arrived before their teacher.
            b.customStatement(
              'UPDATE ds_talks_fts SET teacher = ? WHERE rowid IN '
              '(SELECT id FROM ds_talks WHERE teacher_id = ?)',
              [name, id],
            );
          }
        }
      });
    });
  }

  Future<void> upsertRetreatRecords(Map<int, Map<String, Object?>> records) {
    if (records.isEmpty) return Future.value();
    return batch((b) {
      for (final MapEntry(key: id, value: r) in records.entries) {
        final name = r.str('name');
        final description = r.str('description');
        b.insert(
          dsRetreats,
          DsRetreatsCompanion.insert(
            id: Value(id),
            name: name,
            description: Value(description),
            startDate: Value(r.str('start_date')),
            endDate: Value(r.str('end_date')),
            talkIds: Value(jsonEncode(r.ints('talks'))),
            updatedAt: Value(r.str('update_date')),
          ),
          mode: InsertMode.insertOrReplace,
        );
        _replaceFts(b, 'ds_retreats_fts', id, [name, description]);
      }
    });
  }

  Future<void> upsertTalkRecords(Map<int, Map<String, Object?>> records) {
    if (records.isEmpty) return Future.value();
    return transaction(() async {
      final names = {
        for (final t in await teachersById(
          records.values.map((r) => r.integer('teacher_id')).nonNulls,
        ).then((m) => m.values))
          t.id: t.name,
      };
      await batch((b) {
        b.deleteWhere(dsTalkTeachers, (t) => t.talkId.isIn(records.keys));
        for (final MapEntry(key: id, value: r) in records.entries) {
          final title = r.str('title');
          final description = r.str('description');
          final teacherId = r.integer('teacher_id');
          final retreatId = r.integer('retreat_id');
          final minutes = r['duration_in_minutes'];
          b.insert(
            dsTalks,
            DsTalksCompanion.insert(
              id: Value(id),
              title: title,
              description: Value(description),
              teacherId: Value(teacherId),
              // Dharma Seed uses 0 for "no retreat".
              retreatId: Value(retreatId == 0 ? null : retreatId),
              audioUrl: r.str('audio_url'),
              durationMs: Value(
                minutes is num
                    ? (minutes * Duration.millisecondsPerMinute).round()
                    : 0,
              ),
              recDate: Value(r.str('rec_date')),
              recordingType: Value(r.str('recording_type')),
              languageId: Value(r.integer('language_id')),
              updatedAt: Value(r.str('update_date')),
            ),
            mode: InsertMode.insertOrReplace,
          );
          b.insertAll(dsTalkTeachers, [
            for (final teacher in {?teacherId, ...r.ints('teachers')})
              DsTalkTeachersCompanion.insert(talkId: id, teacherId: teacher),
          ], mode: InsertMode.insertOrIgnore);
          _replaceFts(b, 'ds_talks_fts', id, [
            title,
            description,
            names[teacherId] ?? '',
          ]);
        }
      });
    });
  }

  /// SQLite caps bound variables per statement; stay well under it.
  static const _chunk = 500;

  static Iterable<List<int>> _chunks(Iterable<int> ids) sync* {
    final list = ids.toList();
    for (var i = 0; i < list.length; i += _chunk) {
      yield list.sublist(i, (i + _chunk).clamp(0, list.length));
    }
  }

  Future<void> deleteRecords(DsKind kind, Iterable<int> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value();
    return transaction(() async {
      for (final chunk in _chunks(list)) {
        await batch((b) {
          switch (kind) {
            case DsKind.teachers:
              b.deleteWhere(dsTeachers, (t) => t.id.isIn(chunk));
            case DsKind.retreats:
              b.deleteWhere(dsRetreats, (t) => t.id.isIn(chunk));
            case DsKind.talks:
              b.deleteWhere(dsTalks, (t) => t.id.isIn(chunk));
              b.deleteWhere(dsTalkTeachers, (t) => t.talkId.isIn(chunk));
          }
          final placeholders = List.filled(chunk.length, '?').join(',');
          b.customStatement(
            'DELETE FROM ${_ftsTable(kind)} WHERE rowid IN ($placeholders)',
            chunk,
          );
        });
      }
    });
  }

  /// Drops [missing] talk IDs from a retreat's list, so a talk Dharma Seed
  /// withdrew is neither refetched nor counted towards progress.
  Future<void> pruneRetreatTalks(int retreatId, Set<int> missing) async {
    if (missing.isEmpty) return;
    final retreat = await retreatById(retreatId);
    if (retreat == null) return;
    final kept = talkIdsOf(retreat).where((id) => !missing.contains(id));
    await (update(dsRetreats)..where((r) => r.id.equals(retreatId))).write(
      DsRetreatsCompanion(talkIds: Value(jsonEncode(kept.toList()))),
    );
  }

  void _replaceFts(Batch b, String table, int id, List<String> columns) {
    b.customStatement('DELETE FROM $table WHERE rowid = ?', [id]);
    final placeholders = List.filled(columns.length, '?').join(',');
    b.customStatement(
      'INSERT INTO $table(rowid, ${_ftsColumns[table]}) '
      'VALUES (?, $placeholders)',
      [id, ...columns],
    );
  }

  static const _ftsColumns = {
    'ds_talks_fts': 'title, description, teacher',
    'ds_retreats_fts': 'name, description',
    'ds_teachers_fts': 'name, bio',
  };

  static String _ftsTable(DsKind kind) => switch (kind) {
    DsKind.teachers => 'ds_teachers_fts',
    DsKind.retreats => 'ds_retreats_fts',
    DsKind.talks => 'ds_talks_fts',
  };

  // ------------------------------------------------------------ sync state

  Future<DsSyncStateRow?> syncState(DsKind kind) => (select(
    dsSyncState,
  )..where((s) => s.kind.equals(kind.name))).getSingleOrNull();

  Future<List<DsSyncStateRow>> allSyncStates() => select(dsSyncState).get();

  Future<void> writeSyncState(DsKind kind, DsSyncStateCompanion values) =>
      into(dsSyncState).insert(
        values.copyWith(kind: Value(kind.name)),
        onConflict: DoUpdate((_) => values.copyWith(kind: Value(kind.name))),
      );

  Future<void> enqueue(DsKind kind, Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await batch((b) {
      b.insertAll(dsSyncQueue, [
        for (final id in list)
          DsSyncQueueCompanion.insert(kind: kind.name, itemId: id),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  Future<List<int>> nextQueued(DsKind kind, int limit) async {
    final rows =
        await (select(dsSyncQueue)
              ..where((q) => q.kind.equals(kind.name))
              ..orderBy([(q) => OrderingTerm.desc(q.itemId)])
              ..limit(limit))
            .get();
    return [for (final row in rows) row.itemId];
  }

  Future<int> queuedCount(DsKind kind) async {
    final count = dsSyncQueue.itemId.count();
    final row =
        await (selectOnly(dsSyncQueue)
              ..addColumns([count])
              ..where(dsSyncQueue.kind.equals(kind.name)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> dequeue(DsKind kind, Iterable<int> ids) => batch((b) {
    for (final chunk in _chunks(ids)) {
      b.deleteWhere(
        dsSyncQueue,
        (q) => q.kind.equals(kind.name) & q.itemId.isIn(chunk),
      );
    }
  });

  // ------------------------------------------------------------- user saves

  Future<void> setSaved(DsSavedKind kind, int id, {required bool saved}) =>
      saved
      ? into(dsSaved).insert(
          DsSavedCompanion.insert(
            kind: kind.name,
            itemId: id,
            savedAt: DateTime.now(),
          ),
          mode: InsertMode.insertOrIgnore,
        )
      : (delete(
          dsSaved,
        )..where((s) => s.kind.equals(kind.name) & s.itemId.equals(id))).go();

  /// Saved IDs of [kind], most recently saved first.
  Future<List<int>> savedIds(DsSavedKind kind) async {
    final rows =
        await (select(dsSaved)
              ..where((s) => s.kind.equals(kind.name))
              // Saves within one second tie on savedAt; insertion order breaks it.
              ..orderBy([
                (s) => OrderingTerm.desc(s.savedAt),
                (s) => OrderingTerm.desc(s.rowId),
              ]))
            .get();
    return [for (final row in rows) row.itemId];
  }

  // ---------------------------------------------------------------- reads

  Future<int> countOf(DsKind kind) async {
    final table = switch (kind) {
      DsKind.teachers => 'ds_teachers',
      DsKind.retreats => 'ds_retreats',
      DsKind.talks => 'ds_talks',
    };
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM $table',
    ).getSingle();
    return row.read<int>('c');
  }

  Future<DsTeacher?> teacherById(int id) =>
      (select(dsTeachers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Map<int, DsTeacher>> teachersById(Iterable<int> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const {};
    return {
      for (final t in await (select(
        dsTeachers,
      )..where((t) => t.id.isIn(list))).get())
        t.id: t,
    };
  }

  Future<DsRetreat?> retreatById(int id) =>
      (select(dsRetreats)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<List<DsRetreat>> retreatsById(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return const [];
    final rows = await (select(
      dsRetreats,
    )..where((r) => r.id.isIn(list))).get();
    final byId = {for (final r in rows) r.id: r};
    return [for (final id in list) ?byId[id]];
  }

  static List<int> talkIdsOf(DsRetreat retreat) {
    final decoded = jsonDecode(retreat.talkIds);
    return decoded is List ? decoded.whereType<int>().toList() : const [];
  }

  /// Whether the talks listing has been fully applied: an edition recorded
  /// and nothing pending or queued.
  Future<bool> talksSynced() async {
    final state = await syncState(DsKind.talks);
    return state?.edition != null &&
        state?.pendingEdition == null &&
        await queuedCount(DsKind.talks) == 0;
  }

  /// A retreat's talk IDs that can still be played. Once every talk has
  /// synced, a listed ID with no stored talk is one Dharma Seed no longer
  /// serves (the background sync never requests it), so it is left out.
  /// Until then the retreat's own list is returned as it stands.
  Future<List<int>> liveTalkIdsOf(DsRetreat retreat) async {
    final ids = talkIdsOf(retreat);
    if (ids.isEmpty || !await talksSynced()) return ids;
    final have = await existingTalkIds(ids);
    return [
      for (final id in ids)
        if (have.contains(id)) id,
    ];
  }

  /// Retreats with talks, newest first.
  Future<List<DsRetreat>> recentRetreats({int limit = 40}) =>
      (select(dsRetreats)
            ..where((r) => r.talkIds.equals('[]').not())
            ..orderBy([
              (r) => OrderingTerm.desc(r.startDate),
              (r) => OrderingTerm.desc(r.id),
            ])
            ..limit(limit))
          .get();

  Future<DsTalk?> talkById(int id) =>
      (select(dsTalks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Set<int>> existingTalkIds(Iterable<int> ids) async {
    final found = <int>{};
    for (final chunk in _chunks(ids)) {
      final query = selectOnly(dsTalks)
        ..addColumns([dsTalks.id])
        ..where(dsTalks.id.isIn(chunk));
      found.addAll([
        for (final row in await query.get()) row.read(dsTalks.id)!,
      ]);
    }
    return found;
  }

  /// A retreat's talks in recording order: `rec_date`, then ID.
  Future<List<DsTalk>> talksOfRetreat(int retreatId) =>
      (select(dsTalks)
            ..where((t) => t.retreatId.equals(retreatId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.recDate),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  /// The teacher who gave most of each retreat's synced talks.
  Future<Map<int, int>> leadTeacherOfRetreats(Iterable<int> retreatIds) async {
    final list = retreatIds.toList();
    if (list.isEmpty) return const {};
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await customSelect(
      'SELECT retreat_id, teacher_id, COUNT(*) AS n FROM ds_talks '
      'WHERE retreat_id IN ($placeholders) AND teacher_id IS NOT NULL '
      'GROUP BY retreat_id, teacher_id ORDER BY n ASC',
      variables: [for (final id in list) Variable.withInt(id)],
      readsFrom: {dsTalks},
    ).get();
    // Ascending order, so the most frequent teacher is written last.
    return {
      for (final row in rows)
        row.read<int>('retreat_id'): row.read<int>('teacher_id'),
    };
  }

  /// Retreats containing any of [talkIds].
  Future<Set<int>> retreatIdsOfTalks(Iterable<int> talkIds) async {
    final found = <int>{};
    for (final chunk in _chunks(talkIds)) {
      final query = selectOnly(dsTalks, distinct: true)
        ..addColumns([dsTalks.retreatId])
        ..where(dsTalks.id.isIn(chunk) & dsTalks.retreatId.isNotNull());
      found.addAll([
        for (final row in await query.get()) row.read(dsTalks.retreatId)!,
      ]);
    }
    return found;
  }

  /// SQL for "this talk is in [group]" on a `ds_talks` row aliased [alias].
  /// Untyped and unknown recordings are Talks.
  static String groupCondition(DsContentGroup group, String alias) {
    final types = dsPracticeRecordingTypes.map((t) => "'$t'").join(',');
    final practice = "lower(trim($alias.recording_type)) IN ($types)";
    return group == DsContentGroup.practice ? practice : 'NOT ($practice)';
  }

  /// Retreats with talks, newest first, optionally only those that are mostly
  /// [group] (at least half of their stored talks). Retreats whose talks have
  /// not synced yet cannot be classified and only appear without a group.
  Future<List<DsRetreat>> recentRetreatsOf(
    DsContentGroup? group, {
    int limit = 40,
  }) async {
    if (group == null) return recentRetreats(limit: limit);
    final practiceShare = dsPracticeRecordingTypes.map((t) => "'$t'").join(',');
    final comparison = group == DsContentGroup.practice ? '>=' : '<';
    final rows = await customSelect(
      'SELECT r.* FROM ds_retreats r JOIN ('
      'SELECT retreat_id, COUNT(*) AS n, SUM('
      "CASE WHEN lower(trim(recording_type)) IN ($practiceShare) "
      'THEN 1 ELSE 0 END) AS p FROM ds_talks '
      'WHERE retreat_id IS NOT NULL GROUP BY retreat_id) k '
      'ON k.retreat_id = r.id '
      'WHERE r.talk_ids != \'[]\' AND k.p * 2 $comparison k.n '
      'ORDER BY r.start_date DESC, r.id DESC LIMIT ?',
      variables: [Variable.withInt(limit)],
      readsFrom: {dsRetreats, dsTalks},
    ).get();
    return [for (final row in rows) dsRetreats.map(row.data)];
  }

  /// Newest talks first, for the Explore "latest" list.
  Future<List<DsTalkWithTeacher>> recentTalks({
    DsTalkFilter filter = const DsTalkFilter(),
    int limit = 20,
  }) async {
    final sql = filter.toSql('t');
    if (sql == null) return const [];
    final rows = await customSelect(
      'SELECT t.* FROM ds_talks t '
      '${sql.where.isEmpty ? '' : 'WHERE ${sql.where.join(' AND ')} '}'
      'ORDER BY t.rec_date DESC, t.id DESC LIMIT ?',
      variables: [...sql.variables, Variable.withInt(limit)],
      readsFrom: {dsTalks},
    ).get();
    return _withTeachers([for (final row in rows) dsTalks.map(row.data)]);
  }

  Future<List<DsTalkWithTeacher>> _withTeachers(List<DsTalk> talks) async {
    final teachers = await teachersById(talks.map((t) => t.teacherId).nonNulls);
    return [
      for (final talk in talks)
        DsTalkWithTeacher(talk, teachers[talk.teacherId]),
    ];
  }

  /// Teachers with the most stored talks (of [group], when given), most first.
  /// Co-teaching counts for every teacher of a talk, as on a teacher's page;
  /// teachers marked non-public are left out.
  Future<List<DsTeacherSummary>> topTeachers({
    DsContentGroup? group,
    int limit = 20,
  }) async {
    final rows = await customSelect(
      'SELECT tt.teacher_id AS id, COUNT(*) AS n FROM ds_talk_teachers tt '
      'JOIN ds_talks t ON t.id = tt.talk_id '
      'JOIN ds_teachers k ON k.id = tt.teacher_id AND k.is_public = 1 '
      '${group == null ? '' : 'WHERE ${groupCondition(group, 't')} '}'
      'GROUP BY tt.teacher_id ORDER BY n DESC, tt.teacher_id LIMIT ?',
      variables: [Variable.withInt(limit)],
      readsFrom: {dsTalks, dsTalkTeachers, dsTeachers},
    ).get();
    final teachers = await teachersById([
      for (final row in rows) row.read<int>('id'),
    ]);
    return [
      for (final row in rows)
        if (teachers[row.read<int>('id')] case final teacher?)
          DsTeacherSummary(teacher, row.read<int>('n')),
    ];
  }

  /// How many stored talks each of [teacherIds] gave (co-teaching counts).
  Future<Map<int, int>> talkCounts(Iterable<int> teacherIds) async {
    final list = teacherIds.toList();
    if (list.isEmpty) return const {};
    final rows = await customSelect(
      'SELECT teacher_id AS id, COUNT(*) AS n FROM ds_talk_teachers '
      'WHERE teacher_id IN (${List.filled(list.length, '?').join(',')}) '
      'GROUP BY teacher_id',
      variables: [for (final id in list) Variable.withInt(id)],
      readsFrom: {dsTalkTeachers},
    ).get();
    return {for (final row in rows) row.read<int>('id'): row.read<int>('n')};
  }

  /// Retreats in which [teacherId] gave at least one stored talk, newest first.
  Future<List<DsRetreat>> retreatsOfTeacher(
    int teacherId, {
    int limit = 500,
  }) async {
    final rows = await customSelect(
      'SELECT r.* FROM ds_retreats r WHERE r.id IN ('
      'SELECT t.retreat_id FROM ds_talks t '
      'JOIN ds_talk_teachers tt ON tt.talk_id = t.id AND tt.teacher_id = ? '
      'WHERE t.retreat_id IS NOT NULL) '
      'ORDER BY r.start_date DESC, r.id DESC LIMIT ?',
      variables: [Variable.withInt(teacherId), Variable.withInt(limit)],
      readsFrom: {dsRetreats, dsTalks, dsTalkTeachers},
    ).get();
    return [for (final row in rows) dsRetreats.map(row.data)];
  }

  /// A teacher's talks, newest first, a page at a time.
  Future<List<DsTalkWithTeacher>> talksOfTeacher(
    int teacherId, {
    DsTalkFilter filter = const DsTalkFilter(),
    int limit = 30,
    int offset = 0,
  }) async {
    final sql = filter.toSql('t');
    if (sql == null) return const [];
    final rows = await customSelect(
      'SELECT t.* FROM ds_talks t '
      'JOIN ds_talk_teachers tt ON tt.talk_id = t.id AND tt.teacher_id = ? '
      '${sql.where.isEmpty ? '' : 'WHERE ${sql.where.join(' AND ')} '}'
      'ORDER BY t.rec_date DESC, t.id DESC LIMIT ? OFFSET ?',
      variables: [
        Variable.withInt(teacherId),
        ...sql.variables,
        Variable.withInt(limit),
        Variable.withInt(offset),
      ],
      readsFrom: {dsTalks, dsTalkTeachers},
    ).get();
    return _withTeachers([for (final row in rows) dsTalks.map(row.data)]);
  }

  /// Saves from before the library existed, oldest first, with their time.
  Future<List<DsSavedItem>> savedItems() =>
      (select(dsSaved)..orderBy([
            (s) => OrderingTerm.asc(s.savedAt),
            (s) => OrderingTerm.asc(s.rowId),
          ]))
          .get();

  Future<bool> isSaved(DsSavedKind kind, int id) async =>
      (await (select(dsSaved)
            ..where((s) => s.kind.equals(kind.name) & s.itemId.equals(id)))
          .getSingleOrNull()) !=
      null;

  // ---------------------------------------------------------------- search

  /// An FTS5 query matching every word of [input] as a prefix, or null when
  /// [input] has no searchable words. User text never reaches FTS syntax.
  static String? matchExpression(String input) {
    final words = RegExp(
      r'[\p{L}\p{N}]+',
      unicode: true,
    ).allMatches(input).map((m) => m[0]!).toList();
    if (words.isEmpty) return null;
    return words.map((w) => '"$w"*').join(' ');
  }

  Future<List<DsTalkWithTeacher>> searchTalks(
    String query, {
    DsTalkFilter filter = const DsTalkFilter(),
    int limit = 50,
  }) async {
    final match = matchExpression(query);
    if (match == null) return const [];
    final sql = filter.toSql('t');
    if (sql == null) return const [];
    final where = ['ds_talks_fts MATCH ?', ...sql.where];
    final variables = <Variable>[Variable.withString(match), ...sql.variables];
    variables.add(Variable.withInt(limit));
    final rows = await customSelect(
      'SELECT t.* FROM ds_talks_fts f JOIN ds_talks t ON t.id = f.rowid '
      'WHERE ${where.join(' AND ')} '
      // Title matters most, then teacher, then description.
      'ORDER BY bm25(ds_talks_fts, 10.0, 1.0, 5.0), t.rec_date DESC LIMIT ?',
      variables: variables,
      readsFrom: {dsTalks},
    ).get();
    return _withTeachers([for (final row in rows) dsTalks.map(row.data)]);
  }

  Future<List<DsRetreat>> searchRetreats(String query, {int limit = 30}) async {
    final match = matchExpression(query);
    if (match == null) return const [];
    final rows = await customSelect(
      'SELECT r.* FROM ds_retreats_fts f JOIN ds_retreats r ON r.id = f.rowid '
      'WHERE ds_retreats_fts MATCH ? '
      'ORDER BY bm25(ds_retreats_fts, 10.0, 1.0), r.start_date DESC LIMIT ?',
      variables: [Variable.withString(match), Variable.withInt(limit)],
      readsFrom: {dsRetreats},
    ).get();
    return [for (final row in rows) dsRetreats.map(row.data)];
  }

  /// Teachers whose *name* matches every word of [query]. Bios are not
  /// searched: a teacher mentioned in another's bio is not a teacher result.
  Future<List<DsTeacher>> searchTeachers(String query, {int limit = 20}) async {
    final words = matchExpression(query);
    if (words == null) return const [];
    final match = 'name : ($words)';
    final rows = await customSelect(
      'SELECT t.* FROM ds_teachers_fts f JOIN ds_teachers t ON t.id = f.rowid '
      'WHERE ds_teachers_fts MATCH ? AND t.is_public = 1 '
      'ORDER BY bm25(ds_teachers_fts, 10.0, 1.0) LIMIT ?',
      variables: [Variable.withString(match), Variable.withInt(limit)],
      readsFrom: {dsTeachers},
    ).get();
    return [for (final row in rows) dsTeachers.map(row.data)];
  }
}
