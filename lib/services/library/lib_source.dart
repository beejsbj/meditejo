import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/library/feed_parser.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/utils/logger.dart';
import 'package:path/path.dart' as p;

/// The user's own imports as a [ContentSource]: a feed or a set of files is a
/// course (a pack whose sessions are its episodes or files), and a URL or a
/// file on its own is a single (a track). PackView, the player, downloads,
/// favourites and completion work on these exactly as on any other source.
///
/// The library entry, not this source, says whether something is *kept*;
/// this holds the content behind the entries. Adding to the library is saving
/// ([SavableContentSource]), and removing deletes the content and any file
/// copied into app storage.
class LibSource
    implements ContentSource, SavableContentSource, ParentedContentSource {
  LibSource({required this.db, required this.library});

  final LibraryDatabase db;
  final LibraryStore library;

  final _removals = StreamController<List<String>>.broadcast();

  /// The sessions this source just stopped having (an import was deleted), so
  /// a personal course listing one can mark it unavailable without waiting
  /// for its page to be opened.
  Stream<List<String>> get removals => _removals.stream;

  void dispose() => _removals.close();

  @override
  String get prefix => libPrefix;

  // --------------------------------------------------------------- reading

  /// Imported courses, newest first.
  @override
  Future<List<PackModel>> browsePacks() async {
    final courses = await db.allCourses();
    return [for (final course in courses) _packSummary(course)];
  }

  @override
  Future<PackModel> pack(String id) async {
    final course = await db.courseById(id);
    if (course == null) throw CatalogueEntryUnavailable('pack', id);
    var tracks = await db.tracksOfCourse(id);
    if (course.episodeOrder == 'newest') tracks = tracks.reversed.toList();
    return _packSummary(
      course,
    ).copyWith(items: [for (final track in tracks) _item(track, course)]);
  }

  @override
  Future<Track> track(String id) async {
    final row = await db.trackById(id);
    if (row == null) throw CatalogueEntryUnavailable('track', id);
    final course = row.courseId == null
        ? null
        : await db.courseById(row.courseId!);
    final group =
        await library.groupOf(row.id) ??
        (row.courseId == null ? null : await library.groupOf(row.courseId!));
    return mapTrack(row, course, practice: group != LibraryGroup.talks);
  }

  /// Every imported course with its sessions: small, and entirely the user's.
  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async {
    final courses = await db.allCourses();
    return {
      for (final course in courses)
        course.id: [for (final t in await db.tracksOfCourse(course.id)) t.id],
    };
  }

  @override
  Future<List<PackItemsModel>> searchPacks(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final course in await db.allCourses())
        if (_matches(needle, [course.title, course.author, course.description]))
          PackItemsModel(
            type: TypeConstants.pack,
            id: course.id,
            title: course.title,
            subtitle: course.author,
            coverUrl: course.artworkUrl,
            path: '/packs/${course.id}',
          ),
    ];
  }

  @override
  Future<List<TrackSearchModel>> searchTracks(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final track in await db.allTracks())
        if (_matches(needle, [track.title, track.author, track.description]))
          TrackSearchModel(
            id: track.id,
            title: track.title,
            subtitle: track.author,
            description: track.description,
            coverUrl: track.artworkUrl,
            path: '/tracks/${track.id}',
          ),
    ];
  }

  bool _matches(String needle, List<String> fields) =>
      fields.any((f) => f.toLowerCase().contains(needle));

  @override
  Future<String?> parentOf(String trackId) async =>
      (await db.trackById(trackId))?.courseId;

  // ---------------------------------------------------------------- mapping

  PackModel _packSummary(LibCourseRow course) => PackModel(
    id: course.id,
    title: course.title,
    subtitle: _courseSubtitle(course),
    coverUrl: course.artworkUrl,
    path: '/packs/${course.id}',
    description: course.description,
    isPublished: true,
    attribution: courseAttribution(course),
  );

  String _courseSubtitle(LibCourseRow course) => course.author;

  PackItemsModel _item(LibTrackRow track, LibCourseRow course) =>
      PackItemsModel(
        type: TypeConstants.track,
        id: track.id,
        title: track.title,
        subtitle: track.author,
        coverUrl: track.artworkUrl.isNotEmpty
            ? track.artworkUrl
            : course.artworkUrl,
        path: '/tracks/${track.id}',
        durationMs: track.durationMs > 0 ? track.durationMs : null,
        date: track.publishedAt.length >= 10
            ? track.publishedAt.substring(0, 10)
            : null,
        teacher: track.author.isNotEmpty ? track.author : null,
      );

  /// The credit owed for a course: who made it, where it lives, and the
  /// licence when the feed states one. Always present, so the page reads as a
  /// course.
  static SourceAttribution courseAttribution(LibCourseRow course) =>
      SourceAttribution(
        source: course.origin == 'feed'
            ? _hostOf(course.siteUrl, course.feedUrl)
            : 'This device',
        creator: course.author.isEmpty ? null : course.author,
        url: course.siteUrl.isNotEmpty ? course.siteUrl : course.feedUrl,
        licenseName: course.licenseName,
        licenseUrl: course.licenseUrl,
      );

  static SourceAttribution trackAttribution(
    LibTrackRow track,
    LibCourseRow? course,
  ) {
    if (course != null) return courseAttribution(course);
    final uri = Uri.tryParse(track.audioUrl);
    return SourceAttribution(
      source: track.isLocalFile
          ? 'This device'
          : _hostOf(track.pageUrl, track.audioUrl),
      creator: track.author.isEmpty ? null : track.author,
      url: track.pageUrl.isNotEmpty
          ? track.pageUrl
          : (uri != null && uri.hasScheme && !track.isLocalFile
                ? track.audioUrl
                : ''),
      licenseName: '',
      licenseUrl: '',
    );
  }

  static String _hostOf(String primary, String fallback) {
    for (final candidate in [primary, fallback]) {
      final host = Uri.tryParse(candidate)?.host ?? '';
      if (host.isNotEmpty) return host.replaceFirst(RegExp(r'^www\.'), '');
    }
    return 'Imported';
  }

  /// One voice, one file: the original audio, untouched. [practice] decides
  /// whether a background sound may sit under it.
  static Track mapTrack(
    LibTrackRow row,
    LibCourseRow? course, {
    required bool practice,
  }) {
    final attribution = trackAttribution(row, course);
    final cover = row.artworkUrl.isNotEmpty
        ? row.artworkUrl
        : (course?.artworkUrl ?? '');
    return Track(
      id: row.id,
      title: row.title,
      subtitle: row.author.isEmpty ? null : row.author,
      description: row.description,
      coverUrl: cover,
      isPublished: true,
      hasBackgroundSound: practice,
      artist: TrackArtist(
        name: row.author.isNotEmpty ? row.author : attribution.source,
        path: attribution.url,
      ),
      attribution: attribution,
      voices: [
        TrackVoice(
          guideName: row.author.isEmpty ? null : row.author,
          audioFiles: [
            TrackAudioFile(
              id: row.id,
              path: row.audioUrl,
              duration: row.durationMs,
            ),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- saving

  @override
  bool canSave(String id) => isLibCourseId(id) || isLibTrackId(id);

  @override
  Future<bool> isSaved(String id) => library.contains(id);

  /// Saving an imported item that has content puts it (back) in the library;
  /// unsaving removes it and its content.
  @override
  Future<void> setSaved(String id, {required bool saved}) async {
    if (saved) {
      final draft = await draftFor(id);
      if (draft != null) await library.add(draft);
    } else {
      await remove(id);
    }
  }

  /// A library draft for stored content, or null when nothing is stored.
  Future<LibraryDraft?> draftFor(String id, {LibraryGroup? group}) async {
    if (isLibCourseId(id)) {
      final course = await db.courseById(id);
      if (course == null) return null;
      final tracks = await db.tracksOfCourse(id);
      return LibraryDraft(
        sourceId: id,
        kind: LibraryKind.course,
        title: course.title,
        group: group ?? LibraryGroup.practice,
        subtitle: _entrySubtitle(course.author, tracks.length),
        coverUrl: course.artworkUrl,
        itemCount: tracks.length,
        durationMs: tracks.fold(0, (sum, t) => sum + t.durationMs),
      );
    }
    if (isLibTrackId(id)) {
      final track = await db.trackById(id);
      if (track == null) return null;
      return LibraryDraft(
        sourceId: id,
        kind: LibraryKind.single,
        title: track.title,
        group: group ?? LibraryGroup.practice,
        subtitle: track.author,
        coverUrl: track.artworkUrl,
        durationMs: track.durationMs,
      );
    }
    return null;
  }

  static String _entrySubtitle(String author, int count) => [
    if (author.isNotEmpty) author,
    '$count ${count == 1 ? 'session' : 'sessions'}',
  ].join(' · ');

  /// Removes the entry and deletes what was imported for it, including files
  /// copied into app storage.
  Future<void> remove(String id) async {
    await library.remove(id);
    final paths = <String>[];
    final removed = <String>[];
    if (isLibCourseId(id)) {
      // Sessions of the course that were also added on their own go too.
      final children = await db.trackIdsOfCourse(id);
      for (final child in children) {
        await library.remove(child);
      }
      paths.addAll(await db.deleteCourse(id));
      removed.addAll(children);
    } else if (isLibTrackId(id)) {
      // A session inside a course belongs to the course: taking it out of the
      // library as its own entry leaves the course (and its audio) alone.
      if ((await db.trackById(id))?.courseId == null) {
        final path = await db.deleteTrack(id);
        if (path != null) paths.add(path);
        removed.add(id);
      }
    }
    if (removed.isNotEmpty && !_removals.isClosed) _removals.add(removed);
    for (final path in paths) {
      // Only ever our own copies, never a path from anywhere else.
      if (p.basename(p.dirname(path)) != 'library') continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        AppLogger.w('LIBRARY', 'Could not delete $path: $e');
      }
    }
  }

  // --------------------------------------------------------- storing imports

  /// Stores a feed as a course with all its episodes (new ones are added,
  /// known ones keep their rows). Returns how many episodes are new.
  Future<int> storeFeed({
    required String courseId,
    required String feedUrl,
    required ParsedFeed feed,
    String episodeOrder = 'oldest',
    String? etag,
    String? lastModified,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final existing = await db.courseById(courseId);
    await db.upsertCourse(
      LibCoursesCompanion.insert(
        id: courseId,
        origin: 'feed',
        title: feed.title,
        description: Value(feed.description),
        author: Value(feed.author),
        artworkUrl: Value(feed.imageUrl),
        feedUrl: Value(feedUrl),
        siteUrl: Value(feed.siteUrl),
        licenseName: Value(feed.licenseName),
        licenseUrl: Value(feed.licenseUrl),
        episodeOrder: Value(existing?.episodeOrder ?? episodeOrder),
        autoRefresh: Value(existing?.autoRefresh ?? true),
        etag: Value(etag),
        lastModified: Value(lastModified),
        lastCheckedAt: Value(stamp),
        lastError: const Value(null),
        createdAt: existing?.createdAt ?? stamp,
      ),
    );
    final known = await db.trackIdsOfCourse(courseId);
    var added = 0;
    for (final episode in feed.episodes) {
      final id = libEpisodeId(feedUrl, episode.guid);
      if (!known.contains(id)) added++;
      await storeEpisode(
        episode,
        feedUrl: feedUrl,
        courseId: courseId,
        now: stamp,
      );
    }
    await _renumber(courseId, {
      for (final e in feed.episodes) libEpisodeId(feedUrl, e.guid): e.ordinal,
    });
    return added;
  }

  /// Oldest-first ranks 0..N-1 over the whole course. Episodes the feed no
  /// longer lists (it trimmed its history) are older than the ones it does,
  /// so they go first, by date, instead of sharing ranks with current ones.
  Future<void> _renumber(String courseId, Map<String, int> current) async {
    final tracks = await db.tracksOfCourse(courseId);
    final dropped = [
      for (final t in tracks)
        if (!current.containsKey(t.id)) t,
    ]..sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
    var rank = 0;
    for (final t in dropped) {
      await db.updateTrack(t.id, LibTracksCompanion(ordinal: Value(rank++)));
    }
    final live = [
      for (final t in tracks)
        if (current.containsKey(t.id)) t,
    ]..sort((a, b) => current[a.id]!.compareTo(current[b.id]!));
    for (final t in live) {
      await db.updateTrack(t.id, LibTracksCompanion(ordinal: Value(rank++)));
    }
  }

  /// Stores one feed episode, attached to [courseId] or on its own.
  Future<String> storeEpisode(
    ParsedEpisode episode, {
    required String feedUrl,
    String? courseId,
    DateTime? now,
  }) async {
    final id = libEpisodeId(feedUrl, episode.guid);
    final existing = await db.trackById(id);
    await db.upsertTrack(
      LibTracksCompanion.insert(
        id: id,
        courseId: Value(courseId ?? existing?.courseId),
        title: episode.title,
        description: Value(episode.description),
        author: Value(episode.author),
        artworkUrl: Value(episode.imageUrl),
        audioUrl: episode.audioUrl,
        mimeType: Value(episode.mimeType),
        durationMs: Value(episode.durationMs ?? existing?.durationMs ?? 0),
        guid: Value(episode.guid),
        publishedAt: Value(
          episode.publishedAt?.toUtc().toIso8601String() ?? '',
        ),
        ordinal: Value(episode.ordinal),
        pageUrl: Value(episode.pageUrl),
        createdAt: existing?.createdAt ?? now ?? DateTime.now(),
      ),
    );
    return id;
  }

  /// Stores a single audio address or file as a stand-alone track.
  Future<void> storeSingle({
    required String id,
    required String title,
    required String audioUrl,
    bool isLocalFile = false,
    String mimeType = '',
    int durationMs = 0,
    String author = '',
    String artworkUrl = '',
    String description = '',
    String pageUrl = '',
    DateTime? now,
  }) async {
    final existing = await db.trackById(id);
    await db.upsertTrack(
      LibTracksCompanion.insert(
        id: id,
        title: title,
        description: Value(description),
        author: Value(author),
        artworkUrl: Value(artworkUrl),
        audioUrl: audioUrl,
        isLocalFile: Value(isLocalFile),
        mimeType: Value(mimeType),
        durationMs: Value(durationMs),
        pageUrl: Value(pageUrl),
        createdAt: existing?.createdAt ?? now ?? DateTime.now(),
      ),
    );
  }

  /// Stores local files as one course; each [files] entry is already copied
  /// into app storage.
  Future<void> storeFileCourse({
    required String courseId,
    required String title,
    required List<StoredFile> files,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    await db.upsertCourse(
      LibCoursesCompanion.insert(
        id: courseId,
        origin: 'files',
        title: title,
        autoRefresh: const Value(false),
        createdAt: stamp,
      ),
    );
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      await db.upsertTrack(
        LibTracksCompanion.insert(
          id: file.id,
          courseId: Value(courseId),
          title: file.title,
          audioUrl: file.path,
          isLocalFile: const Value(true),
          mimeType: Value(file.mimeType),
          durationMs: Value(file.durationMs),
          ordinal: Value(i),
          createdAt: stamp,
        ),
      );
    }
  }

  /// Sets how a feed course lists its episodes and whether it refreshes.
  Future<void> updateCourseSettings(
    String courseId, {
    String? episodeOrder,
    bool? autoRefresh,
  }) => db.updateCourse(
    courseId,
    LibCoursesCompanion(
      episodeOrder: Value.absentIfNull(episodeOrder),
      autoRefresh: Value.absentIfNull(autoRefresh),
    ),
  );
}

/// A file copied into app storage, ready to be stored as a session.
class StoredFile {
  const StoredFile({
    required this.id,
    required this.title,
    required this.path,
    this.mimeType = '',
    this.durationMs = 0,
  });

  final String id;
  final String title;
  final String path;
  final String mimeType;
  final int durationMs;
}
