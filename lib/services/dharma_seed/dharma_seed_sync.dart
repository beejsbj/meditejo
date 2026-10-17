import 'dart:async';
import 'dart:collection';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/utils/logger.dart';

enum DharmaSeedSyncPhase { idle, syncing, failed }

@immutable
class DharmaSeedSyncStatus {
  const DharmaSeedSyncStatus({
    this.phase = DharmaSeedSyncPhase.idle,
    this.kind,
    this.done = 0,
    this.total = 0,
    this.lastSyncedAt,
    this.error,
  });

  final DharmaSeedSyncPhase phase;

  /// The record kind being fetched while [phase] is syncing.
  final DsKind? kind;
  final int done;
  final int total;

  /// When every kind last finished syncing; null until the first full sync.
  final DateTime? lastSyncedAt;
  final String? error;

  bool get isSyncing => phase == DharmaSeedSyncPhase.syncing;

  DharmaSeedSyncStatus copyWith({
    DharmaSeedSyncPhase? phase,
    DsKind? kind,
    int? done,
    int? total,
    DateTime? lastSyncedAt,
    String? error,
  }) => DharmaSeedSyncStatus(
    phase: phase ?? this.phase,
    kind: kind ?? this.kind,
    done: done ?? this.done,
    total: total ?? this.total,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    error: error,
  );

  @override
  String toString() =>
      'DharmaSeedSyncStatus($phase ${kind?.name} $done/$total, '
      'last $lastSyncedAt${error == null ? '' : ', $error'})';
}

/// Keeps [DharmaSeedDatabase] in step with Dharma Seed, politely.
///
/// Order, so the app is useful early: teachers, then retreats (about a dozen
/// requests, enough to browse courses), then the ~49k talks in the
/// background. Opening a retreat or talk that has not synced yet fetches it
/// ahead of the background queue ([ensureRetreatTalks], [ensureTalk]).
///
/// Politeness: every request goes through one serial lane with a pause
/// between requests, so nothing runs in parallel; detail requests are
/// batched; later syncs ask only for changes since the stored edition; the
/// client backs off on errors. The fetch queue lives in the database, so a
/// killed app resumes where it stopped instead of starting over.
class DharmaSeedSync {
  DharmaSeedSync({
    required this.db,
    required this.client,
    this.pause = const Duration(milliseconds: 750),
    this.autoSyncInterval = const Duration(hours: 12),
    Map<DsKind, int>? batchSizes,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
  }) : batchSizes =
           batchSizes ??
           const {DsKind.teachers: 250, DsKind.retreats: 250, DsKind.talks: 500},
       _clock = clock ?? DateTime.now,
       _lane = _PoliteLane(pause, sleep ?? Future<void>.delayed);

  final DharmaSeedDatabase db;
  final DharmaSeedClient client;
  final Duration pause;

  /// Automatic syncs (app start) are skipped when the last full sync is
  /// newer than this. Manual refreshes always run.
  final Duration autoSyncInterval;
  final Map<DsKind, int> batchSizes;
  final DateTime Function() _clock;
  final _PoliteLane _lane;

  static const order = [DsKind.teachers, DsKind.retreats, DsKind.talks];

  final ValueNotifier<DharmaSeedSyncStatus> status = ValueNotifier(
    const DharmaSeedSyncStatus(),
  );

  /// Bumped when a sync pass over one record kind changed something, so
  /// browse lists can re-query. Not per batch: talks sync in ~100 batches.
  final ValueNotifier<int> revision = ValueNotifier(0);

  Future<void>? _running;
  bool _disposed = false;
  bool _changed = false;

  /// Loads the last-synced time without touching the network.
  Future<void> loadStatus() async {
    final last = await _lastFullSync();
    if (!status.value.isSyncing) {
      _emit(status.value.copyWith(lastSyncedAt: last));
    }
  }

  /// Runs the sync, or joins the one already running. With [force] false it
  /// is skipped when nothing is pending and the last full sync is recent.
  Future<void> sync({bool force = false}) {
    return _running ??= _run(force: force).whenComplete(() => _running = null);
  }

  Future<void> _run({required bool force}) async {
    if (!force && !await _isDue()) {
      await loadStatus();
      return;
    }
    try {
      for (final kind in order) {
        if (_disposed) return;
        await _syncKind(kind, force: force);
      }
      final last = await _lastFullSync();
      _emit(DharmaSeedSyncStatus(lastSyncedAt: last));
    } catch (e, st) {
      AppLogger.w('DHARMA_SEED', 'Sync stopped: $e\n$st');
      final kind = status.value.kind;
      if (kind != null) {
        await db.writeSyncState(
          kind,
          DsSyncStateCompanion(lastError: Value('$e')),
        );
      }
      _emit(
        status.value.copyWith(
          phase: DharmaSeedSyncPhase.failed,
          error: e is DharmaSeedApiException ? e.message : '$e',
        ),
      );
    }
  }

  Future<bool> _isDue() async {
    for (final kind in order) {
      final state = await db.syncState(kind);
      if (state == null || state.edition == null) return true;
      if (state.pendingEdition != null) return true;
      if (await db.queuedCount(kind) > 0) return true;
    }
    final last = await _lastFullSync();
    return last == null || _clock().difference(last) >= autoSyncInterval;
  }

  Future<DateTime?> _lastFullSync() async {
    DateTime? oldest;
    for (final kind in order) {
      final at = (await db.syncState(kind))?.lastSyncedAt;
      if (at == null) return null;
      if (oldest == null || at.isBefore(oldest)) oldest = at;
    }
    return oldest;
  }

  Future<void> _syncKind(DsKind kind, {required bool force}) async {
    var state = await db.syncState(kind);
    var queued = await db.queuedCount(kind);
    final last = state?.lastSyncedAt;
    // Resuming an interrupted sync: kinds that finished recently are done.
    if (!force &&
        queued == 0 &&
        state?.pendingEdition == null &&
        state?.edition != null &&
        last != null &&
        _clock().difference(last) < autoSyncInterval) {
      return;
    }

    // List IDs unless a killed run left work behind: a nonempty queue, or a
    // pending edition whose queue already drained (then just record it).
    if (queued == 0 && state?.pendingEdition == null) {
      _emit(status.value.copyWith(
        phase: DharmaSeedSyncPhase.syncing,
        kind: kind,
        done: 0,
        total: 0,
      ));
      final list = await _lane.run(
        () => client.fetchIds(kind, edition: state?.edition),
      );
      await db.transaction(() async {
        await db.deleteRecords(kind, list.removed);
        await db.dequeue(kind, list.removed);
        await db.enqueue(kind, list.items);
        await db.writeSyncState(
          kind,
          DsSyncStateCompanion(
            pendingEdition: Value(list.edition),
            lastError: const Value(null),
          ),
        );
      });
      if (list.removed.isNotEmpty) _changed = true;
      queued = await db.queuedCount(kind);
    }

    final total = queued;
    var done = 0;
    _emit(status.value.copyWith(
      phase: DharmaSeedSyncPhase.syncing,
      kind: kind,
      done: done,
      total: total,
    ));
    final size = batchSizes[kind]!;
    while (!_disposed) {
      final ids = await db.nextQueued(kind, size);
      if (ids.isEmpty) break;
      final details = await _lane.run(() => client.fetchDetails(kind, ids));
      await _apply(kind, ids, details);
      done += ids.length;
      _emit(status.value.copyWith(done: done, total: total));
    }
    if (_disposed) return;

    state = await db.syncState(kind);
    await db.writeSyncState(
      kind,
      DsSyncStateCompanion(
        edition: Value(state?.pendingEdition ?? state?.edition),
        pendingEdition: const Value(null),
        lastSyncedAt: Value(_clock()),
        lastError: const Value(null),
      ),
    );
    if (_changed) {
      _changed = false;
      _bump();
    }
  }

  /// Stores fetched records and dequeues [requested]. A requested ID missing
  /// from the response is gone upstream; drop it rather than retry forever.
  Future<void> _apply(DsKind kind, List<int> requested, DsDetails details) async {
    final missing = requested.where((id) => !details.records.containsKey(id));
    await db.transaction(() async {
      switch (kind) {
        case DsKind.teachers:
          await db.upsertTeacherRecords(details.records);
        case DsKind.retreats:
          await db.upsertRetreatRecords(details.records);
        case DsKind.talks:
          await db.upsertTalkRecords(details.records);
      }
      await db.deleteRecords(kind, missing);
      await db.dequeue(kind, requested);
    });
    _changed = true;
  }

  /// Makes sure [retreatId] and all its talks are on the device, fetching
  /// what is missing ahead of the background queue. Throws on network
  /// failure; callers fall back to what is stored.
  Future<void> ensureRetreatTalks(int retreatId) async {
    var retreat = await db.retreatById(retreatId);
    if (retreat == null) {
      await _fetchNow(DsKind.retreats, [retreatId]);
      retreat = await db.retreatById(retreatId);
      if (retreat == null) return;
    }
    final talkIds = await db.liveTalkIdsOf(retreat);
    final have = await db.existingTalkIds(talkIds);
    final missing = [
      for (final id in talkIds)
        if (!have.contains(id)) id,
    ];
    if (missing.isEmpty) return;
    final gone = <int>{};
    final size = batchSizes[DsKind.talks]!;
    for (var i = 0; i < missing.length; i += size) {
      final chunk = missing.sublist(i, (i + size).clamp(0, missing.length));
      gone.addAll(await _fetchNow(DsKind.talks, chunk));
    }
    await db.pruneRetreatTalks(retreatId, gone);
    await _ensureTeachersOf(missing);
  }

  /// Makes sure one teacher is on the device. Returns false when Dharma Seed
  /// no longer has them.
  Future<bool> ensureTeacher(int teacherId) async {
    if (await db.teacherById(teacherId) != null) return true;
    final gone = await _fetchNow(DsKind.teachers, [teacherId]);
    return !gone.contains(teacherId);
  }

  /// Makes sure one talk is on the device. Returns false when Dharma Seed no
  /// longer has it.
  Future<bool> ensureTalk(int talkId) async {
    if (await db.talkById(talkId) != null) return true;
    final gone = await _fetchNow(DsKind.talks, [talkId]);
    if (gone.contains(talkId)) return false;
    await _ensureTeachersOf([talkId]);
    return true;
  }

  /// Fetches the teachers of [talkIds] not yet on the device, so a course
  /// opened before the teacher list synced still shows names and artwork.
  Future<void> _ensureTeachersOf(List<int> talkIds) async {
    final teacherIds = <int>{};
    for (final id in talkIds) {
      final teacher = (await db.talkById(id))?.teacherId;
      if (teacher != null) teacherIds.add(teacher);
    }
    final known = await db.teachersById(teacherIds);
    final missing = teacherIds.where((id) => !known.containsKey(id)).toList();
    if (missing.isNotEmpty) await _fetchNow(DsKind.teachers, missing);
  }

  /// Priority detail fetch through the same polite lane. Returns IDs that
  /// came back missing.
  Future<Set<int>> _fetchNow(DsKind kind, List<int> ids) async {
    final details = await _lane.run(
      () => client.fetchDetails(kind, ids),
      priority: true,
    );
    await _apply(kind, ids, details);
    return {
      for (final id in ids)
        if (!details.records.containsKey(id)) id,
    };
  }

  void _emit(DharmaSeedSyncStatus next) {
    if (!_disposed) status.value = next;
  }

  void _bump() {
    if (!_disposed) revision.value++;
  }

  /// Stops the background loop after its current request. The notifiers
  /// stay usable so late listeners can still detach.
  void dispose() {
    _disposed = true;
  }
}

/// Runs one request at a time, at least [pause] apart. Priority work (a
/// retreat the user just opened) goes ahead of queued background batches but
/// never alongside them.
class _PoliteLane {
  _PoliteLane(this.pause, this._sleep);

  final Duration pause;
  final Future<void> Function(Duration) _sleep;
  final _waiting = Queue<Completer<void>>();
  bool _busy = false;
  DateTime? _lastFinished;

  Future<T> run<T>(Future<T> Function() task, {bool priority = false}) async {
    if (_busy) {
      final turn = Completer<void>();
      priority ? _waiting.addFirst(turn) : _waiting.addLast(turn);
      await turn.future;
    }
    _busy = true;
    try {
      final last = _lastFinished;
      if (last != null) {
        final wait = pause - DateTime.now().difference(last);
        if (wait > Duration.zero) await _sleep(wait);
      }
      return await task();
    } finally {
      _lastFinished = DateTime.now();
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _busy = false;
      }
    }
  }
}
