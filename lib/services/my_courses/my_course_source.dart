import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/utils/logger.dart';

/// Courses the user made, as a [ContentSource]. A course (`my-course-…`) is a
/// pack whose items keep their own IDs (`ds-talk-…`, `yt-video-…`,
/// `lib-track-…`), so the player, downloads, Resume and completion treat a
/// session the same wherever it is listed. Completion belongs to the
/// session: finishing it anywhere ticks it in every course that holds it.
///
/// Sessions are read from their own sources each time the course opens. One
/// that its source no longer has stays in the course, marked unavailable and
/// shown from the snapshot taken when it was added. Deleting a course
/// removes only the course: the sessions, their library entries and their
/// downloads are left alone.
class MyCourseSource implements ContentSource {
  MyCourseSource({
    required this.db,
    required this.library,
    required List<ContentSource> Function() sources,
    DateTime Function()? clock,
    Random? random,
    this.resolveTimeout = const Duration(seconds: 8),
  }) : _sources = sources,
       _clock = clock ?? DateTime.now,
       _random = random;

  final LibraryDatabase db;
  final LibraryStore library;
  final List<ContentSource> Function() _sources;
  final DateTime Function() _clock;
  final Random? _random;

  /// How long one session's source may take before its snapshot is shown.
  final Duration resolveTimeout;

  /// Changes whenever a course or its sessions do; course pages and
  /// completion ticks re-read on it.
  final ValueNotifier<int> revision = ValueNotifier(0);

  void _changed() => revision.value++;

  /// The other sources, for reading what a course holds.
  ContentRouter get _router => ContentRouter(
    sources: [
      for (final source in _sources())
        if (source.prefix != myPrefix) source,
    ],
  );

  @override
  String get prefix => myPrefix;

  // --------------------------------------------------------------- reading

  @override
  Future<List<PackModel>> browsePacks() async => [
    for (final course in await _allCourses())
      _summary(course, await _rows(course.id)),
  ];

  @override
  Future<PackModel> pack(String id) async {
    final course = await _course(id);
    if (course == null) throw CatalogueEntryUnavailable('pack', id);
    final rows = await _rows(id);
    final items = <PackItemsModel>[];
    var section = '';
    var availabilityChanged = false;
    for (final row in rows) {
      if (row.itemId.isEmpty) {
        section = row.heading;
        continue;
      }
      final fresh = await _refresh(row);
      if (fresh.unavailable != row.unavailable) availabilityChanged = true;
      items.add(_item(fresh, section.isEmpty ? null : section));
    }
    // Availability feeds completion ticks (an unavailable session cannot be
    // finished), so they re-read; this pack is read again and finds nothing
    // new.
    if (availabilityChanged) _changed();
    return _summary(course, rows).copyWith(items: items);
  }

  /// Sessions belong to their own sources; a course holds no tracks itself.
  @override
  Future<Track> track(String id) async =>
      throw CatalogueEntryUnavailable('track', id);

  /// Every personal course with its available sessions: few, and all the
  /// user's own.
  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async => {
    for (final course in await _allCourses())
      course.id: [
        for (final row in await _rows(course.id))
          if (row.itemId.isNotEmpty && !row.unavailable) row.itemId,
      ],
  };

  @override
  Future<List<PackItemsModel>> searchPacks(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final course in await _allCourses())
        if ('${course.title}\n${course.description}'.toLowerCase().contains(
          needle,
        ))
          PackItemsModel(
            type: TypeConstants.pack,
            id: course.id,
            title: course.title,
            subtitle: course.description,
            coverUrl: course.coverUrl,
            path: '/packs/${course.id}',
          ),
    ];
  }

  /// A course's sessions are found through their own sources.
  @override
  Future<List<TrackSearchModel>> searchTracks(String query) async => const [];

  /// Re-reads one session from its source and keeps the snapshot current.
  /// Only the source saying the session is gone marks it unavailable; being
  /// offline or slow shows the snapshot as it was.
  Future<MyCourseItemRow> _refresh(MyCourseItemRow row) async {
    MyCourseItemRow next;
    try {
      final draft = MyItemDraft.fromTrack(
        await _router.track(row.itemId).timeout(resolveTimeout),
      );
      next = row.copyWith(
        title: draft.title.isEmpty ? row.title : draft.title,
        subtitle: draft.subtitle.isEmpty ? row.subtitle : draft.subtitle,
        coverUrl: draft.coverUrl.isEmpty ? row.coverUrl : draft.coverUrl,
        durationMs: draft.durationMs > 0 ? draft.durationMs : row.durationMs,
        unavailable: false,
      );
    } on CatalogueEntryUnavailable {
      next = row.copyWith(unavailable: true);
    } catch (e) {
      AppLogger.d('MY_COURSES', 'Showing ${row.itemId} as stored: $e');
      return row;
    }
    if (next != row) {
      await (db.update(db.myCourseItems)
            ..where((r) => r.rowId.equals(row.rowId)))
          .write(
            MyCourseItemsCompanion(
              title: Value(next.title),
              subtitle: Value(next.subtitle),
              coverUrl: Value(next.coverUrl),
              durationMs: Value(next.durationMs),
              unavailable: Value(next.unavailable),
            ),
          );
    }
    return next;
  }

  PackModel _summary(MyCourseRow course, List<MyCourseItemRow> rows) {
    final sessions = rows.where((r) => r.itemId.isNotEmpty).length;
    return PackModel(
      id: course.id,
      title: course.title,
      subtitle: sessionCountText(sessions),
      coverUrl: course.coverUrl,
      path: '/packs/${course.id}',
      description: course.description,
      isPublished: true,
    );
  }

  PackItemsModel _item(MyCourseItemRow row, String? section) => PackItemsModel(
    type: TypeConstants.track,
    id: row.itemId,
    title: row.title,
    subtitle: row.subtitle.isEmpty ? null : row.subtitle,
    teacher: row.subtitle.isEmpty ? null : row.subtitle,
    coverUrl: row.coverUrl,
    path: '/tracks/${row.itemId}',
    durationMs: row.durationMs > 0 ? row.durationMs : null,
    kind: row.kind.isNotEmpty ? row.kind : sourceLabel(row.itemId),
    section: section,
    unavailable: row.unavailable ? true : null,
  );

  /// What to call a session's source on its row when it has no kind of its
  /// own. Source names are not translated.
  static String sourceLabel(String id) {
    if (id.startsWith('ds-')) return 'Dharma Seed';
    if (id.startsWith('yt-')) return 'YouTube';
    return 'Imported';
  }

  /// "3 sessions", as the library's other courses say it.
  static String sessionCountText(int count) =>
      '$count ${count == 1 ? 'session' : 'sessions'}';

  // ------------------------------------------------------------------ lists

  Future<List<MyCourseRow>> _allCourses() => (db.select(
    db.myCourses,
  )..orderBy([(c) => OrderingTerm.desc(c.updatedAt)])).get();

  Future<MyCourseRow?> _course(String id) => (db.select(
    db.myCourses,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<MyCourseItemRow>> _rows(String courseId) =>
      (db.select(db.myCourseItems)
            ..where((r) => r.courseId.equals(courseId))
            ..orderBy([
              (r) => OrderingTerm.asc(r.position),
              (r) => OrderingTerm.asc(r.rowId),
            ]))
          .get();

  /// The user's courses for the "Add to course" sheet, most recently changed
  /// first; [containing] marks those that already hold every one of these
  /// sessions.
  Future<List<MyCourseSummary>> courses({
    Iterable<String> containing = const [],
  }) async {
    final wanted = containing.toSet();
    return [
      for (final course in await _allCourses())
        await () async {
          final ids = {
            for (final row in await _rows(course.id))
              if (row.itemId.isNotEmpty) row.itemId,
          };
          return MyCourseSummary(
            id: course.id,
            title: course.title,
            sessionCount: ids.length,
            coverUrl: course.coverUrl,
            contains: wanted.isNotEmpty && ids.containsAll(wanted),
          );
        }(),
    ];
  }

  /// IDs of the personal courses that list the session [itemId].
  Future<List<String>> coursesHolding(String itemId) async {
    final rows = await (db.select(
      db.myCourseItems,
    )..where((r) => r.itemId.equals(itemId))).get();
    return {for (final row in rows) row.courseId}.toList();
  }

  // ----------------------------------------------------------------- making

  /// Makes a course, adds it to the library and returns its ID.
  Future<String> create({
    required String title,
    LibraryGroup group = LibraryGroup.practice,
    String description = '',
    String coverUrl = '',
    List<MyCourseLine> lines = const [],
  }) async {
    final id = newMyCourseId(_random);
    final now = _clock();
    await db.transaction(() async {
      await db
          .into(db.myCourses)
          .insert(
            MyCoursesCompanion.insert(
              id: id,
              title: _titleOr(title),
              description: Value(description.trim()),
              coverUrl: Value(coverUrl),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _writeLines(id, _deduplicated(lines));
    });
    final stored = await _rows(id);
    await library.add(
      LibraryDraft(
        sourceId: id,
        kind: LibraryKind.course,
        title: _titleOr(title),
        group: group,
        subtitle: sessionCountText(stored.where((r) => r.itemId.isNotEmpty).length),
        coverUrl: coverUrl,
        itemCount: stored.where((r) => r.itemId.isNotEmpty).length,
        durationMs: stored.fold(0, (sum, r) => sum + r.durationMs),
      ),
    );
    _changed();
    return id;
  }

  /// Adds [items] to the end of [courseId], skipping sessions it already
  /// holds. Returns how many were added.
  Future<int> addItems(String courseId, List<MyItemDraft> items) async {
    final course = await _course(courseId);
    if (course == null) throw CatalogueEntryUnavailable('pack', courseId);
    final existing = await _rows(courseId);
    final held = {for (final r in existing) r.itemId};
    final fresh = [
      for (final item in items)
        if (held.add(item.id)) item,
    ];
    if (fresh.isEmpty) return 0;
    var position = existing.isEmpty ? 0 : existing.last.position + 1;
    await db.transaction(() async {
      for (final item in fresh) {
        await db.into(db.myCourseItems).insert(_session(courseId, position++, item));
      }
      await _touch(courseId);
    });
    await _syncEntry(courseId);
    _changed();
    return fresh.length;
  }

  /// The sessions to add for [id]: a course's available sessions in order,
  /// or one session. [fallback] stands in when the session cannot be read
  /// (for example a talk whose source is offline).
  Future<List<MyItemDraft>> itemsFor(String id, {MyItemDraft? fallback}) async {
    if (isCourseId(id)) {
      final pack = isMyCourseId(id) ? await this.pack(id) : await _router.pack(id);
      return [
        for (final item in pack.items)
          if (item.type == TypeConstants.track && item.unavailable != true)
            MyItemDraft.fromPackItem(item),
      ];
    }
    try {
      final track = await _router.track(id).timeout(resolveTimeout);
      final draft = MyItemDraft.fromTrack(track);
      return [
        MyItemDraft(
          id: draft.id,
          title: draft.title,
          subtitle: draft.subtitle,
          coverUrl: draft.coverUrl,
          durationMs: draft.durationMs,
          kind: fallback?.kind ?? '',
        ),
      ];
    } catch (e) {
      if (fallback != null) return [fallback];
      rethrow;
    }
  }

  /// Copies a course from any source into a new personal one, in its order,
  /// leaving the original untouched. Returns the new course's ID.
  Future<String> duplicate(String packId, {required String title}) async {
    final pack = isMyCourseId(packId)
        ? await this.pack(packId)
        : await _router.pack(packId);
    final lines = <MyCourseLine>[];
    String? section;
    for (final item in pack.items) {
      if (item.type != TypeConstants.track) continue;
      if (item.section != null && item.section != section) {
        lines.add(MyCourseLine.heading(item.section!));
      }
      section = item.section;
      lines.add(
        MyCourseLine.session(
          MyItemDraft.fromPackItem(item),
          unavailable: item.unavailable == true,
        ),
      );
    }
    return create(
      title: title,
      group: await library.groupOf(packId) ?? LibraryGroup.practice,
      description: pack.description ?? '',
      coverUrl: pack.coverUrl ?? '',
      lines: lines,
    );
  }

  // ---------------------------------------------------------------- editing

  /// The course as the edit screen starts from it, or null when it is gone.
  Future<MyCourseEdit?> edit(String id) async {
    final course = await _course(id);
    if (course == null) return null;
    return MyCourseEdit(
      title: course.title,
      description: course.description,
      coverUrl: course.coverUrl,
      group: await library.groupOf(id) ?? LibraryGroup.practice,
      lines: [
        for (final row in await _rows(id))
          if (row.itemId.isEmpty)
            MyCourseLine.heading(row.heading)
          else
            MyCourseLine.session(
              MyItemDraft(
                id: row.itemId,
                title: row.title,
                subtitle: row.subtitle,
                coverUrl: row.coverUrl,
                durationMs: row.durationMs,
                kind: row.kind,
              ),
              unavailable: row.unavailable,
            ),
      ],
    );
  }

  /// Writes the whole edit at once: title, description, cover, kind, and the
  /// rows in their new order. Removed sessions leave only this course.
  Future<void> save(String id, MyCourseEdit edit) async {
    if (await _course(id) == null) {
      throw CatalogueEntryUnavailable('pack', id);
    }
    await db.transaction(() async {
      await (db.update(db.myCourses)..where((c) => c.id.equals(id))).write(
        MyCoursesCompanion(
          title: Value(_titleOr(edit.title)),
          description: Value(edit.description.trim()),
          coverUrl: Value(edit.coverUrl),
          updatedAt: Value(_clock()),
        ),
      );
      await (db.delete(db.myCourseItems)..where((r) => r.courseId.equals(id))).go();
      await _writeLines(id, _deduplicated(edit.lines));
    });
    final entry = await library.entry(id);
    if (entry != null) {
      await library.setGroup(
        id,
        edit.group == entry.detectedGroup ? null : edit.group,
      );
      // The course's own title is the name; a library rename made before the
      // edit screen existed would hide it.
      if (entry.titleOverride != null) await library.setTitle(id, null);
    }
    await _syncEntry(id);
    _changed();
  }

  /// Renames a course (from the library's menu).
  Future<void> rename(String id, String title) async {
    await (db.update(db.myCourses)..where((c) => c.id.equals(id))).write(
      MyCoursesCompanion(
        title: Value(_titleOr(title)),
        updatedAt: Value(_clock()),
      ),
    );
    await _syncEntry(id);
    _changed();
  }

  /// Deletes the course and its library entry. The sessions it listed, their
  /// own library entries, saved places and downloads are not touched.
  Future<void> delete(String id) async {
    await db.transaction(() async {
      await (db.delete(db.myCourseItems)..where((r) => r.courseId.equals(id))).go();
      await (db.delete(db.myCourses)..where((c) => c.id.equals(id))).go();
      await db.clearSessionContextsOf(id);
    });
    await library.remove(id);
    _changed();
  }

  // ---------------------------------------------------------------- helpers

  String _titleOr(String title) {
    final trimmed = title.trim();
    return trimmed.isEmpty ? 'My course' : trimmed;
  }

  /// A session appears once per course; headings with nothing to say go.
  List<MyCourseLine> _deduplicated(List<MyCourseLine> lines) {
    final seen = <String>{};
    return [
      for (final line in lines)
        if (line.isHeading
            ? line.heading.trim().isNotEmpty
            : seen.add(line.item!.id))
          line,
    ];
  }

  Future<void> _writeLines(String courseId, List<MyCourseLine> lines) async {
    for (var i = 0; i < lines.length; i++) {
      final row = lines[i];
      await db
          .into(db.myCourseItems)
          .insert(
            row.isHeading
                ? MyCourseItemsCompanion.insert(
                    courseId: courseId,
                    position: i,
                    heading: Value(row.heading.trim()),
                  )
                : _session(courseId, i, row.item!, unavailable: row.unavailable),
          );
    }
  }

  MyCourseItemsCompanion _session(
    String courseId,
    int position,
    MyItemDraft item, {
    bool unavailable = false,
  }) => MyCourseItemsCompanion.insert(
    courseId: courseId,
    position: position,
    itemId: Value(item.id),
    title: Value(item.title),
    subtitle: Value(item.subtitle),
    coverUrl: Value(item.coverUrl),
    durationMs: Value(item.durationMs),
    kind: Value(item.kind),
    unavailable: Value(unavailable),
  );

  Future<void> _touch(String courseId) =>
      (db.update(db.myCourses)..where((c) => c.id.equals(courseId))).write(
        MyCoursesCompanion(updatedAt: Value(_clock())),
      );

  /// Keeps the library row's title, count, length and cover in step.
  Future<void> _syncEntry(String id) async {
    final course = await _course(id);
    if (course == null) return;
    final sessions = [
      for (final row in await _rows(id))
        if (row.itemId.isNotEmpty) row,
    ];
    await library.updateSnapshot(
      id,
      title: course.title,
      subtitle: sessionCountText(sessions.length),
      coverUrl: course.coverUrl,
      itemCount: sessions.length,
      durationMs: sessions.fold<int>(0, (sum, r) => sum + r.durationMs),
    );
  }

  void dispose() => revision.dispose();
}
