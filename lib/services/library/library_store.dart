import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';

/// The user's library: what they keep, how it is classified, and where they
/// stopped in each session. Everything here is on the device and nothing is
/// sent anywhere.
///
/// [prepare] runs once before the first read or write; the app uses it to
/// carry over saves from before the library existed.
class LibraryStore {
  LibraryStore(this.db, {this.prepare, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final Future<void> Function(LibraryDatabase db)? prepare;
  final DateTime Function() _clock;

  /// Changes whenever entries do; providers watch it to re-read.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// Changes when a saved position is added, moved on pause, or cleared.
  final ValueNotifier<int> positionsRevision = ValueNotifier(0);

  Future<void>? _prepared;

  Future<void> _ready() => _prepared ??= () async {
    try {
      await prepare?.call(db);
    } catch (_) {
      _prepared = null; // try again on the next call
      rethrow;
    }
  }();

  void _changed() => revision.value++;

  // --------------------------------------------------------------- entries

  /// Everything in the library, most recently added or played first.
  Future<List<LibraryEntry>> entries() async {
    await _ready();
    final rows = [for (final row in await db.allEntries()) _entry(row)];
    rows.sort((a, b) {
      final byActivity = b.lastActivity.compareTo(a.lastActivity);
      return byActivity != 0 ? byActivity : a.sourceId.compareTo(b.sourceId);
    });
    return rows;
  }

  Future<LibraryEntry?> entry(String sourceId) async {
    await _ready();
    final row = await db.entryById(sourceId);
    return row == null ? null : _entry(row);
  }

  Future<bool> contains(String sourceId) async => await entry(sourceId) != null;

  /// Adds [draft]. Returns false, changing nothing, when it is already there.
  Future<bool> add(LibraryDraft draft) async {
    await _ready();
    if (await db.entryById(draft.sourceId) != null) return false;
    await db.insertEntry(
      LibraryEntriesCompanion.insert(
        sourceId: draft.sourceId,
        kind: draft.kind.name,
        detectedGroup: Value(draft.group.name),
        title: draft.title,
        subtitle: Value(draft.subtitle),
        coverUrl: Value(draft.coverUrl),
        itemCount: Value(draft.itemCount),
        durationMs: Value(draft.durationMs),
        addedAt: draft.addedAt ?? _clock(),
      ),
    );
    _changed();
    return true;
  }

  Future<void> remove(String sourceId) async {
    await _ready();
    if (await db.deleteEntry(sourceId) > 0) _changed();
  }

  /// Overrides the Practice/Talks classification; null returns to what the
  /// app detected.
  Future<void> setGroup(String sourceId, LibraryGroup? group) async {
    await _ready();
    await db.updateEntry(
      sourceId,
      LibraryEntriesCompanion(groupOverride: Value(group?.name)),
    );
    _changed();
  }

  /// Renames an entry in the library only; null or blank restores the title
  /// the source gave it.
  Future<void> setTitle(String sourceId, String? title) async {
    await _ready();
    final trimmed = title?.trim();
    await db.updateEntry(
      sourceId,
      LibraryEntriesCompanion(
        titleOverride: Value(
          trimmed == null || trimmed.isEmpty ? null : trimmed,
        ),
      ),
    );
    _changed();
  }

  /// Refreshes the stored snapshot, for example after a feed gained episodes.
  Future<void> updateSnapshot(
    String sourceId, {
    String? title,
    String? subtitle,
    String? coverUrl,
    int? itemCount,
    int? durationMs,
  }) async {
    await _ready();
    await db.updateEntry(
      sourceId,
      LibraryEntriesCompanion(
        title: Value.absentIfNull(title),
        subtitle: Value.absentIfNull(subtitle),
        coverUrl: Value.absentIfNull(coverUrl),
        itemCount: Value.absentIfNull(itemCount),
        durationMs: Value.absentIfNull(durationMs),
      ),
    );
    _changed();
  }

  /// Marks entries as just played, so they lead the library.
  Future<void> touchPlayed(Iterable<String> sourceIds) async {
    await _ready();
    final now = _clock();
    var touched = false;
    for (final id in sourceIds.toSet()) {
      if (await db.entryById(id) == null) continue;
      await db.updateEntry(
        id,
        LibraryEntriesCompanion(lastPlayedAt: Value(now)),
      );
      touched = true;
    }
    if (touched) _changed();
  }

  /// The effective group of [sourceId], or null when it is not in the
  /// library.
  Future<LibraryGroup?> groupOf(String sourceId) async =>
      (await entry(sourceId))?.group;

  LibraryEntry _entry(LibraryEntryRow row) => LibraryEntry(
    sourceId: row.sourceId,
    kind: LibraryKind.parse(row.kind),
    detectedGroup:
        LibraryGroup.tryParse(row.detectedGroup) ?? LibraryGroup.practice,
    groupOverride: LibraryGroup.tryParse(row.groupOverride),
    title: row.title,
    titleOverride: row.titleOverride,
    subtitle: row.subtitle,
    coverUrl: row.coverUrl,
    itemCount: row.itemCount,
    durationMs: row.durationMs,
    addedAt: row.addedAt,
    lastPlayedAt: row.lastPlayedAt,
  );

  // ------------------------------------------------------------- positions

  /// Within this much of the end a session counts as finished: there is
  /// nothing to resume.
  static const finishedWithin = Duration(seconds: 20);

  /// Shorter than this is just an opening, not a place to come back to.
  static const minimumResume = Duration(seconds: 10);

  Future<ResumePoint?> resumePoint(String trackId) async {
    await _ready();
    final row = await db.positionOf(trackId);
    return row == null ? null : _resume(row);
  }

  Future<Map<String, ResumePoint>> resumePoints(
    Iterable<String> trackIds,
  ) async {
    await _ready();
    if (trackIds.isEmpty) return const {};
    return {
      for (final row in await db.positionsOf(trackIds))
        row.trackId: _resume(row),
    };
  }

  ResumePoint _resume(PlaybackPositionRow row) => ResumePoint(
    positionMs: row.positionMs,
    durationMs: row.durationMs,
    fileId: row.fileId,
  );

  /// Remembers where the user is. A position at the very start, or within
  /// [finishedWithin] of the end, is not worth resuming and clears the mark.
  ///
  /// Writes while playing pass `notify: false`, so lists are not re-read every
  /// few seconds; the pause or stop that follows notifies once.
  Future<void> savePosition(
    String trackId,
    int positionMs,
    int durationMs, {
    String fileId = '',
    bool notify = true,
  }) async {
    await _ready();
    final nearEnd =
        durationMs > 0 &&
        positionMs >= durationMs - finishedWithin.inMilliseconds;
    if (positionMs < minimumResume.inMilliseconds || nearEnd) {
      await db.clearPosition(trackId);
    } else {
      await db.savePosition(trackId, positionMs, durationMs, fileId: fileId);
    }
    if (notify) positionsRevision.value++;
  }

  Future<void> clearPosition(String trackId) async {
    await _ready();
    await db.clearPosition(trackId);
    positionsRevision.value++;
  }

  void dispose() {
    revision.dispose();
    positionsRevision.dispose();
  }
}
