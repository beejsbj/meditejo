import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'library_database.g.dart';

/// What the user keeps. One row per thing in the library, whatever its
/// source: a Dharma Seed course or talk (`ds-…`), a teacher, or their own
/// imports (`lib-…`). The row holds a snapshot of the title and artwork so
/// the library draws instantly and offline; the content itself is read from
/// the source that owns the ID.
///
/// Kept apart from the Dharma Seed catalogue database on purpose: that file
/// is a replaceable copy of someone else's catalogue (and will be swapped for
/// a bundled snapshot), while this one is the user's own data.
@DataClassName('LibraryEntryRow')
@TableIndex(name: 'library_entries_added', columns: {#addedAt})
class LibraryEntries extends Table {
  /// The content ID: `ds-retreat-6689`, `ds-talk-99944`, `ds-teacher-210`,
  /// `lib-course-…`, `lib-track-…`.
  TextColumn get sourceId => text()();

  /// `course`, `single` or `teacher`.
  TextColumn get kind => text()();

  /// What the app detected: `practice` or `talks`.
  TextColumn get detectedGroup =>
      text().withDefault(const Constant('practice'))();

  /// The user's own classification, when they changed it.
  TextColumn get groupOverride => text().nullable()();

  TextColumn get title => text()();
  TextColumn get titleOverride => text().nullable()();
  TextColumn get subtitle => text().withDefault(const Constant(''))();
  TextColumn get coverUrl => text().withDefault(const Constant(''))();
  IntColumn get itemCount => integer().withDefault(const Constant(1))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {sourceId};
}

/// How far the user got in a session, for Resume. Written while playing,
/// cleared when the session is finished.
@DataClassName('PlaybackPositionRow')
class PlaybackPositions extends Table {
  TextColumn get trackId => text()();
  IntColumn get positionMs => integer()();

  /// The audio file the position belongs to (a track can have several
  /// lengths); empty when unknown.
  TextColumn get fileId => text().withDefault(const Constant(''))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// An imported course: a podcast feed or a set of local files.
@DataClassName('LibCourseRow')
class LibCourses extends Table {
  /// `lib-course-<hash>`; for a feed the hash is of the feed URL, so adding
  /// the same feed twice finds the first.
  TextColumn get id => text()();

  /// `feed` or `files`.
  TextColumn get origin => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get artworkUrl => text().withDefault(const Constant(''))();

  /// The feed URL for a feed; empty for files.
  TextColumn get feedUrl => text().withDefault(const Constant(''))();

  /// The feed's own web page, shown as the credit link.
  TextColumn get siteUrl => text().withDefault(const Constant(''))();
  TextColumn get licenseName => text().withDefault(const Constant(''))();
  TextColumn get licenseUrl => text().withDefault(const Constant(''))();

  /// `oldest` or `newest`: how episodes are listed. Oldest first is the
  /// default, so a course plays in the order it was made.
  TextColumn get episodeOrder => text().withDefault(const Constant('oldest'))();

  /// Whether the feed is re-read for new episodes now and then.
  BoolColumn get autoRefresh => boolean().withDefault(const Constant(true))();

  /// Caching validators from the last feed response.
  TextColumn get etag => text().nullable()();
  TextColumn get lastModified => text().nullable()();
  DateTimeColumn get lastCheckedAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One imported session: a feed episode, a URL, or a file in app storage.
@DataClassName('LibTrackRow')
@TableIndex(name: 'lib_tracks_course', columns: {#courseId, #ordinal})
class LibTracks extends Table {
  /// `lib-track-<hash>`.
  TextColumn get id => text()();

  /// The course this belongs to; null for a stand-alone single.
  TextColumn get courseId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get artworkUrl => text().withDefault(const Constant(''))();

  /// A web address, or an absolute path inside app storage for a file.
  TextColumn get audioUrl => text()();
  BoolColumn get isLocalFile => boolean().withDefault(const Constant(false))();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// The feed's own episode ID, to recognise it again on refresh.
  TextColumn get guid => text().withDefault(const Constant(''))();

  /// ISO date of publication; empty when unknown.
  TextColumn get publishedAt => text().withDefault(const Constant(''))();

  /// Rank in oldest-first order within the course.
  IntColumn get ordinal => integer().withDefault(const Constant(0))();

  /// Where the page for this session lives, for the credit link.
  TextColumn get pageUrl => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small flags that belong to the library itself, such as "saves migrated".
class LibraryMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// YouTube metadata only. Signed stream addresses never enter this database.
@DataClassName('YoutubeVideoRow')
class YoutubeVideos extends Table {
  TextColumn get videoId => text()();
  TextColumn get title => text()();
  TextColumn get uploader => text()();
  TextColumn get thumbnail => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get durationSeconds => integer()();

  @override
  Set<Column> get primaryKey => {videoId};
}

/// The ordered ID list preserves duplicates and permits a video in several
/// courses. A single-video course uses `single-<videoId>` as its playlist ID.
@DataClassName('YoutubePlaylistRow')
class YoutubePlaylists extends Table {
  TextColumn get playlistId => text()();
  TextColumn get title => text()();
  TextColumn get uploader => text()();
  TextColumn get thumbnail => text()();
  TextColumn get videoIds => text()();
  DateTimeColumn get lastCheckedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {playlistId};
}

/// A course the user made: an ordered list of sessions from any source
/// (`my-course-<random>`). Its Practice/Talks kind is the library entry's
/// group, since the course lives in the library and nowhere else.
@DataClassName('MyCourseRow')
class MyCourses extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();

  /// The chosen cover: one of the items' artwork, or empty for generated art.
  TextColumn get coverUrl => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row of a personal course: a session reference (any source ID) or a
/// section heading ("Day 1"), in [position] order. A session row keeps a
/// snapshot of what it looked like, so the course still reads when the
/// session is gone upstream.
@DataClassName('MyCourseItemRow')
@TableIndex(name: 'my_course_items_order', columns: {#courseId, #position})
@TableIndex(name: 'my_course_items_item', columns: {#itemId})
class MyCourseItems extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  TextColumn get courseId => text()();
  IntColumn get position => integer()();

  /// The session's own ID (`ds-talk-…`, `yt-video-…`, `lib-track-…`); empty
  /// for a heading.
  TextColumn get itemId => text().withDefault(const Constant(''))();

  /// The heading's text; empty for a session.
  TextColumn get heading => text().withDefault(const Constant(''))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get subtitle => text().withDefault(const Constant(''))();
  TextColumn get coverUrl => text().withDefault(const Constant(''))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// What the session is ("Guided Meditation", "YouTube"), for its row.
  TextColumn get kind => text().withDefault(const Constant(''))();

  /// Set when the owning source last said the session no longer exists.
  BoolColumn get unavailable => boolean().withDefault(const Constant(false))();
}

/// The course a session was last opened from, so Home's Continue and the
/// library's order follow the course the user is working through, not
/// whichever course the source says the session belongs to.
@DataClassName('SessionContextRow')
class SessionContexts extends Table {
  TextColumn get trackId => text()();
  TextColumn get courseId => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// What the user says an item is about. A row either adds a label to an
/// entry or, with [excluded], says an automatic category does not belong
/// there; the entry's effective labels are the automatic ones plus the adds,
/// minus the exclusions, so the user's word always outranks the guess.
///
/// [label] is a curated category's ID (`metta`) or, for a label of the
/// user's own, its folded text. Rows are keyed by the content ID, not by
/// anything in the Dharma Seed catalogue, so a refreshed catalogue never
/// touches them; removing an entry leaves its labels, so adding it back (or
/// Undo) finds them again.
@DataClassName('LibraryLabelRow')
@TableIndex(name: 'library_labels_label', columns: {#label})
class LibraryLabels extends Table {
  TextColumn get sourceId => text()();
  TextColumn get label => text()();

  /// The text as the user typed it, for a label of their own; empty for a
  /// curated category, which the catalogue names.
  TextColumn get display => text().withDefault(const Constant(''))();
  BoolColumn get excluded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sourceId, label};
}

@DriftDatabase(
  tables: [
    LibraryEntries,
    PlaybackPositions,
    LibCourses,
    LibTracks,
    LibraryMeta,
    YoutubeVideos,
    YoutubePlaylists,
    MyCourses,
    MyCourseItems,
    SessionContexts,
    LibraryLabels,
  ],
)
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase(super.executor);

  /// The app's library file, opened on first query so constructing it touches
  /// no platform channel.
  factory LibraryDatabase.open() => LibraryDatabase(
    LazyDatabase(() => driftDatabase(name: 'meditejo_library')),
  );

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(youtubeVideos);
        await m.createTable(youtubePlaylists);
      }
      if (from < 3) {
        await m.createTable(myCourses);
        await m.createTable(myCourseItems);
        await m.createIndex(myCourseItemsOrder);
        await m.createIndex(myCourseItemsItem);
        await m.createTable(sessionContexts);
      }
      if (from < 4) {
        await m.createTable(libraryLabels);
        await m.createIndex(libraryLabelsLabel);
      }
    },
  );

  Future<YoutubeVideoRow?> youtubeVideo(String id) => (select(
    youtubeVideos,
  )..where((v) => v.videoId.equals(id))).getSingleOrNull();

  Future<YoutubePlaylistRow?> youtubePlaylist(String id) => (select(
    youtubePlaylists,
  )..where((p) => p.playlistId.equals(id))).getSingleOrNull();

  Future<List<YoutubePlaylistRow>> youtubeCourses() =>
      select(youtubePlaylists).get();

  Future<List<YoutubeVideoRow>> youtubeSessions() =>
      select(youtubeVideos).get();

  // ---------------------------------------------------------------- meta

  Future<String?> metaValue(String key) async => (await (select(
    libraryMeta,
  )..where((m) => m.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setMeta(String key, String value) => into(
    libraryMeta,
  ).insertOnConflictUpdate(LibraryMetaCompanion.insert(key: key, value: value));

  // ------------------------------------------------------------- entries

  Future<List<LibraryEntryRow>> allEntries() => select(libraryEntries).get();

  Future<LibraryEntryRow?> entryById(String sourceId) => (select(
    libraryEntries,
  )..where((e) => e.sourceId.equals(sourceId))).getSingleOrNull();

  Future<void> insertEntry(LibraryEntriesCompanion entry) =>
      into(libraryEntries).insert(entry, mode: InsertMode.insertOrIgnore);

  Future<int> deleteEntry(String sourceId) =>
      (delete(libraryEntries)..where((e) => e.sourceId.equals(sourceId))).go();

  Future<void> updateEntry(String sourceId, LibraryEntriesCompanion changes) =>
      (update(
        libraryEntries,
      )..where((e) => e.sourceId.equals(sourceId))).write(changes);

  // -------------------------------------------------------------- labels

  Future<List<LibraryLabelRow>> allLabels() => select(libraryLabels).get();

  Future<void> putLabel(LibraryLabelsCompanion label) =>
      into(libraryLabels).insertOnConflictUpdate(label);

  Future<int> deleteLabel(String sourceId, String label) =>
      (delete(libraryLabels)
            ..where((l) => l.sourceId.equals(sourceId) & l.label.equals(label)))
          .go();

  // ----------------------------------------------------------- positions

  Future<PlaybackPositionRow?> positionOf(String trackId) => (select(
    playbackPositions,
  )..where((p) => p.trackId.equals(trackId))).getSingleOrNull();

  /// Every saved place, most recently moved first.
  Future<List<PlaybackPositionRow>> recentPositions({int? limit}) {
    final query = select(playbackPositions)
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  Future<List<PlaybackPositionRow>> positionsOf(Iterable<String> trackIds) =>
      (select(playbackPositions)..where((p) => p.trackId.isIn(trackIds))).get();

  Future<void> savePosition(
    String trackId,
    int positionMs,
    int durationMs, {
    String fileId = '',
  }) => into(playbackPositions).insertOnConflictUpdate(
    PlaybackPositionsCompanion.insert(
      trackId: trackId,
      fileId: Value(fileId),
      positionMs: positionMs,
      durationMs: Value(durationMs),
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> clearPosition(String trackId) =>
      (delete(playbackPositions)..where((p) => p.trackId.equals(trackId))).go();

  // ------------------------------------------------------ session context

  Future<SessionContextRow?> sessionContextOf(String trackId) => (select(
    sessionContexts,
  )..where((c) => c.trackId.equals(trackId))).getSingleOrNull();

  Future<void> saveSessionContext(String trackId, String courseId) =>
      into(sessionContexts).insertOnConflictUpdate(
        SessionContextsCompanion.insert(
          trackId: trackId,
          courseId: courseId,
          updatedAt: DateTime.now(),
        ),
      );

  Future<void> clearSessionContextsOf(String courseId) =>
      (delete(sessionContexts)..where((c) => c.courseId.equals(courseId))).go();

  // ------------------------------------------------------ imported content

  Future<LibCourseRow?> courseById(String id) =>
      (select(libCourses)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<LibCourseRow>> allCourses() => (select(
    libCourses,
  )..orderBy([(c) => OrderingTerm.desc(c.createdAt)])).get();

  Future<List<LibCourseRow>> feedsToRefresh() => (select(
    libCourses,
  )..where((c) => c.origin.equals('feed') & c.autoRefresh.equals(true))).get();

  Future<LibTrackRow?> trackById(String id) =>
      (select(libTracks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<LibTrackRow>> tracksOfCourse(String courseId) =>
      (select(libTracks)
            ..where((t) => t.courseId.equals(courseId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.ordinal),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  Future<List<LibTrackRow>> allTracks() => select(libTracks).get();

  Future<Set<String>> trackIdsOfCourse(String courseId) async => {
    for (final row in await tracksOfCourse(courseId)) row.id,
  };

  Future<void> upsertCourse(LibCoursesCompanion course) =>
      into(libCourses).insertOnConflictUpdate(course);

  Future<void> updateCourse(String id, LibCoursesCompanion changes) =>
      (update(libCourses)..where((c) => c.id.equals(id))).write(changes);

  Future<void> upsertTrack(LibTracksCompanion track) =>
      into(libTracks).insertOnConflictUpdate(track);

  Future<void> updateTrack(String id, LibTracksCompanion changes) =>
      (update(libTracks)..where((t) => t.id.equals(id))).write(changes);

  /// Removes an imported course with its sessions and their positions.
  /// Returns the audio paths of local files, for the caller to delete.
  Future<List<String>> deleteCourse(String id) => transaction(() async {
    final tracks = await tracksOfCourse(id);
    await (delete(
      playbackPositions,
    )..where((p) => p.trackId.isIn(tracks.map((t) => t.id)))).go();
    await (delete(libTracks)..where((t) => t.courseId.equals(id))).go();
    await (delete(libCourses)..where((c) => c.id.equals(id))).go();
    return [
      for (final t in tracks)
        if (t.isLocalFile) t.audioUrl,
    ];
  });

  /// Removes an imported single. Returns its local path, if it is a file.
  Future<String?> deleteTrack(String id) => transaction(() async {
    final track = await trackById(id);
    await clearPosition(id);
    await (delete(libTracks)..where((t) => t.id.equals(id))).go();
    return track != null && track.isLocalFile ? track.audioUrl : null;
  });
}
