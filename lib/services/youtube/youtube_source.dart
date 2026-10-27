import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/library/import_defaults.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:medito/src/youtube_api.g.dart';

/// Conservative title-only detection. Whole words avoid "talking meditation";
/// no description guessing. Every other title starts in Practice.
LibraryGroup youtubeGroup(String title) =>
    RegExp(
      r'\b(talk|talks|lecture|lectures|interview|interviews|podcast|discussion)\b|\bq\s*&\s*a\b|\bquestions?\s*(?:&|and)\s*answers?\b',
      caseSensitive: false,
    ).hasMatch(title)
    ? LibraryGroup.talks
    : LibraryGroup.practice;

SourceAttribution youtubeAttribution(String url, String uploader) =>
    SourceAttribution(
      source: 'YouTube',
      creator: uploader.isEmpty ? null : uploader,
      url: url,
      licenseName: '',
      licenseUrl: '',
    );

/// Metadata stays in the user's database. Only this source's memory holds
/// expiring audio URLs; one extraction serves overlapping play requests.
class YoutubeSource
    implements
        ContentSource,
        SavableContentSource,
        ParentedContentSource,
        CourseMembershipSource {
  YoutubeSource({
    required this.db,
    required this.library,
    required this.api,
    DateTime Function()? clock,
    this.sessionCourse,
  }) : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final LibraryStore library;
  final YoutubeExtractorApi api;

  /// The course a session counts towards across every source (a personal
  /// course can hold a YouTube video too), wired to
  /// `ContentRouter.courseOfSession`. Without it only saved YouTube courses
  /// are considered.
  final Future<String?> Function(String trackId)? sessionCourse;
  final DateTime Function() _clock;
  final _streams = <String, ({YoutubeAudioStream stream, DateTime until})>{};
  final _resolving = <String, Future<YoutubeAudioStream>>{};
  final _refreshing = <String, Future<bool>>{};
  final _refreshErrors = <String, YoutubeUnavailableError>{};

  /// Refresh outcomes, including failures that leave the library unchanged.
  /// Listen for UI state; do not reopen an empty pack on a failure notification.
  final ValueNotifier<int> refreshRevision = ValueNotifier(0);

  /// Only successful refreshes change course contents. Failures update the
  /// empty-state notifier without triggering another pack read.
  final ValueNotifier<int> contentRevision = ValueNotifier(0);

  YoutubeUnavailableError? refreshError(String packId) =>
      _refreshErrors[packId];

  static const refreshInterval = Duration(hours: 12);
  static const expiryMargin = Duration(minutes: 5);

  @override
  String get prefix => 'yt-';

  Future<ImportPreview> preview(Uri uri) async {
    final link = parseYoutubeLink(uri);
    if (link == null) {
      throw const ImportFailure(ImportFailureReason.unrecognised);
    }
    try {
      // A watch link may carry both a video and a playlist. Each half is
      // independently useful, so one that cannot be used (a radio mix, a
      // private list, a removed video) leaves the other as the preview.
      final both = link.videoId != null && link.playlistId != null;
      final failures = <YoutubeUnavailableError>[];
      var video = link.videoId == null
          ? null
          : await _resolveOrNull(
              () => api.resolveVideo(link.videoUrl),
              tolerate: both,
              onFailure: failures.add,
            );
      var playlist = link.playlistId == null
          ? null
          : await _resolveOrNull(
              () => api.resolvePlaylist(link.playlistUrl),
              tolerate: both,
              onFailure: failures.add,
            );
      if (playlist != null && playlist.items.isEmpty) {
        if (video == null) {
          throw const ImportFailure(ImportFailureReason.noEpisodes);
        }
        playlist = null;
      }
      if (video == null && playlist == null) {
        throw failures.isEmpty
            ? const YoutubeUnavailableError()
            : failures.first;
      }
      final title = playlist?.title ?? video!.title;
      final uploader = playlist?.uploader ?? video!.uploader;
      final id = playlist == null
          ? ytVideoId(video!.videoId)
          : ytPlaylistId(link.playlistId!);
      final durations = playlist == null
          ? [video!.durationSeconds]
          : playlist.items.map((i) => i.durationSeconds).toList();
      final shape = playlist == null
          ? ImportShape.youtubeVideo
          : video == null
          ? ImportShape.youtubePlaylist
          : ImportShape.youtubeWatchWithPlaylist;
      // What Single picks from: the playlist in its own order, with the video
      // in the link (if any) selected; otherwise the top of the list.
      final listed = <String>{};
      final episodes = playlist == null
          ? [_episodeOfVideo(video!)]
          : [
              for (final item in playlist.items)
                // A video listed twice is one choice.
                if (listed.add(item.videoId))
                  // The video in the link was resolved in full; it speaks
                  // for itself where the list only summarises it.
                  if (item.videoId == video?.videoId)
                    _episodeOfVideo(video!)
                  else
                    ImportEpisode(
                      id: item.videoId,
                      title: item.title,
                      durationMs: item.durationSeconds > 0
                          ? item.durationSeconds * 1000
                          : null,
                      subtitle: item.uploader == playlist.uploader
                          ? ''
                          : item.uploader,
                      artworkUrl: item.thumbnail,
                    ),
            ];
      // A watch link whose video the list does not hold still has to be
      // something Single can pick.
      if (video != null && episodes.every((e) => e.id != video.videoId)) {
        episodes.insert(0, _episodeOfVideo(video));
      }
      return ImportPreview(
        origin: ImportOrigin.youtube,
        entryId: id,
        kind: shape.defaultKind,
        allowedKinds: shape.allowedKinds,
        group: youtubeGroup(title),
        title: title,
        subtitle: uploader,
        sourceLabel: 'YouTube',
        description: playlist == null ? video!.description : '',
        artworkUrl: playlist?.thumbnail ?? video!.thumbnail,
        itemCount: durations.length,
        durationMs: durations.fold<int>(
          0,
          (a, b) => a + (b > 0 ? b * 1000 : 0),
        ),
        durationComplete: durations.every((d) => d > 0),
        firstItems: [
          if (playlist != null)
            for (final item in playlist.items.take(5))
              PreviewItem(
                title: item.title,
                durationMs: item.durationSeconds > 0
                    ? item.durationSeconds * 1000
                    : null,
              ),
        ],
        attribution: youtubeAttribution(
          playlist == null ? link.videoUrl : link.playlistUrl,
          uploader,
        ),
        alreadyInLibrary: await library.contains(id),
        youtubeVideo: video,
        youtubePlaylist: playlist,
        youtubePlaylistId: playlist == null ? null : link.playlistId,
        episodes: episodes,
        defaultEpisodeId: video?.videoId ?? episodes.first.id,
      );
    } on ImportFailure {
      rethrow;
    } catch (e) {
      throw ImportFailure(switch (_failure(e).reason) {
        YoutubeFailureReason.offline => ImportFailureReason.offline,
        YoutubeFailureReason.ageRestricted =>
          ImportFailureReason.youtubeAgeRestricted,
        YoutubeFailureReason.private => ImportFailureReason.youtubePrivate,
        YoutubeFailureReason.rateLimited =>
          ImportFailureReason.youtubeRateLimited,
        YoutubeFailureReason.unavailable =>
          ImportFailureReason.youtubeUnavailable,
      });
    }
  }

  static ImportEpisode _episodeOfVideo(YoutubeVideo video) => ImportEpisode(
    id: video.videoId,
    title: video.title,
    durationMs: video.durationSeconds > 0 ? video.durationSeconds * 1000 : null,
    subtitle: video.uploader,
    artworkUrl: video.thumbnail,
  );

  static YoutubeUnavailableError _failure(Object error) {
    if (error is YoutubeUnavailableError) return error;
    return YoutubeUnavailableError(
      reason: switch (error) {
        PlatformException(code: 'network' || 'offline') =>
          YoutubeFailureReason.offline,
        PlatformException(code: 'age-restricted') =>
          YoutubeFailureReason.ageRestricted,
        PlatformException(code: 'private') => YoutubeFailureReason.private,
        PlatformException(code: 'rate-limited' || 'bot-check' || 'busy') =>
          YoutubeFailureReason.rateLimited,
        _ => YoutubeFailureReason.unavailable,
      },
    );
  }

  /// A content failure may leave the other half of a watch/list link usable.
  /// Connection failures and blocks apply to the entire request.
  Future<T?> _resolveOrNull<T>(
    Future<T> Function() resolve, {
    required bool tolerate,
    required void Function(YoutubeUnavailableError) onFailure,
  }) async {
    if (!tolerate) return resolve();
    try {
      return await resolve();
    } catch (e) {
      final failure = _failure(e);
      if (failure.reason == YoutubeFailureReason.offline ||
          failure.reason == YoutubeFailureReason.rateLimited) {
        throw failure;
      }
      onFailure(failure);
      return null;
    }
  }

  Future<ImportResult> add(ImportPreview preview, ImportChoice choice) async {
    final video = preview.youtubeVideo;
    final playlist = preview.youtubePlaylist;
    // A Single is the video the user picked from the list; the link's own
    // video when they did not pick another.
    final single = choice.kind == LibraryKind.course
        ? null
        : await _singleVideo(preview, choice.episodeId);
    final asCourse = single == null;
    final id = asCourse
        ? (playlist == null
              ? ytSingleCourseId(video!.videoId)
              : ytPlaylistId(preview.youtubePlaylistId!))
        : ytVideoId(single.videoId);
    if (await library.contains(id)) {
      return ImportResult(
        entryId: id,
        kind: asCourse ? LibraryKind.course : LibraryKind.single,
        alreadyPresent: true,
      );
    }
    final title = asCourse ? preview.title : single.title;
    final uploader = asCourse ? preview.subtitle : single.uploader;
    final artwork = asCourse ? preview.artworkUrl : single.thumbnail;
    final duration = asCourse
        ? preview.durationMs
        : single.durationSeconds * 1000;
    final detected = youtubeGroup(title);
    await db.transaction(() async {
      if (single != null) await storeVideo(single);
      if (asCourse && video != null) await storeVideo(video);
      if (asCourse) {
        await storePlaylist(
          id.substring('yt-playlist-'.length),
          playlist ??
              YoutubePlaylist(
                title: video!.title,
                uploader: video.uploader,
                thumbnail: video.thumbnail,
                items: [
                  YoutubePlaylistItem(
                    videoId: video.videoId,
                    title: video.title,
                    uploader: video.uploader,
                    durationSeconds: video.durationSeconds,
                    thumbnail: video.thumbnail,
                  ),
                ],
              ),
        );
      }
      // LibraryStore notifications occur once these rows are committed below.
    });
    final added = await library.add(
      LibraryDraft(
        sourceId: id,
        kind: asCourse ? LibraryKind.course : LibraryKind.single,
        title: title,
        subtitle: uploader,
        coverUrl: artwork,
        group: detected,
        itemCount: asCourse ? preview.itemCount : 1,
        durationMs: duration > 0 ? duration : 0,
      ),
    );
    if (added) {
      if (choice.group != detected) await library.setGroup(id, choice.group);
      final wanted = choice.title?.trim();
      // The unedited playlist title is not a rename of a selected single.
      if (wanted != null &&
          wanted.isNotEmpty &&
          wanted != preview.title &&
          wanted != title) {
        await library.setTitle(id, wanted);
      }
    }
    return ImportResult(
      entryId: id,
      kind: asCourse ? LibraryKind.course : LibraryKind.single,
      alreadyPresent: !added,
    );
  }

  /// The video a Single adds: the one picked from the playlist, else the one
  /// in the link. Null when there is neither, which makes it a course.
  Future<YoutubeVideo?> _singleVideo(
    ImportPreview preview,
    String? episodeId,
  ) async {
    final video = preview.youtubeVideo;
    final playlist = preview.youtubePlaylist;
    final wanted = episodeId ?? preview.defaultEpisodeId ?? video?.videoId;
    if (video != null && (wanted == null || wanted == video.videoId)) {
      return video;
    }
    for (final item in playlist?.items ?? const <YoutubePlaylistItem>[]) {
      if (item.videoId != wanted) continue;
      // A playlist row carries less than a resolved video; keep what is known.
      final previous = await db.youtubeVideo(item.videoId);
      return YoutubeVideo(
        videoId: item.videoId,
        title: item.title,
        uploader: _uploaderOf(item, previous, playlist!),
        // What a full resolve found outranks the list's summary.
        durationSeconds: previous?.durationSeconds ?? item.durationSeconds,
        thumbnail: previous?.thumbnail ?? item.thumbnail,
        description: previous?.description ?? '',
      );
    }
    return video;
  }

  /// A row's own channel, which the playlist's owner does not stand in for.
  /// Only when the extractor names none do we keep a channel already stored,
  /// then fall back to the playlist's.
  static String _uploaderOf(
    YoutubePlaylistItem item,
    YoutubeVideoRow? previous,
    YoutubePlaylist playlist,
  ) => item.uploader.isNotEmpty
      ? item.uploader
      : previous?.uploader ?? playlist.uploader;

  Future<void> storeVideo(YoutubeVideo video) => db
      .into(db.youtubeVideos)
      .insertOnConflictUpdate(
        YoutubeVideosCompanion.insert(
          videoId: video.videoId,
          title: video.title,
          uploader: video.uploader,
          thumbnail: video.thumbnail,
          description: Value(video.description),
          durationSeconds: video.durationSeconds,
        ),
      );

  Future<void> storePlaylist(String id, YoutubePlaylist playlist) =>
      db.transaction(() async {
        for (final item in playlist.items) {
          // Playlist summaries must not erase a description already resolved.
          final previous = await db.youtubeVideo(item.videoId);
          await storeVideo(
            YoutubeVideo(
              videoId: item.videoId,
              title: item.title,
              uploader: _uploaderOf(item, previous, playlist),
              durationSeconds: item.durationSeconds,
              thumbnail: item.thumbnail,
              description: previous?.description ?? '',
            ),
          );
        }
        await db
            .into(db.youtubePlaylists)
            .insertOnConflictUpdate(
              YoutubePlaylistsCompanion.insert(
                playlistId: id,
                title: playlist.title,
                uploader: playlist.uploader,
                thumbnail: playlist.thumbnail,
                videoIds: jsonEncode(
                  playlist.items.map((i) => i.videoId).toList(),
                ),
                lastCheckedAt: _clock(),
              ),
            );
      });

  List<String> _ids(YoutubePlaylistRow row) =>
      (jsonDecode(row.videoIds) as List).cast<String>();

  Future<List<YoutubeVideoRow>> _items(YoutubePlaylistRow row) async => [
    for (final id in _ids(row)) ?await db.youtubeVideo(id),
  ];

  Future<bool> refresh(String id, {bool force = false}) {
    final active = _refreshing[id];
    if (active != null) {
      // Manual refresh shares in-flight extraction, but still surfaces its
      // failure. If the automatic check was skipped, honor the forced retry.
      return force
          ? active.then<bool>(
              (changed) => changed ? true : refresh(id, force: true),
            )
          : active.catchError((Object _) => false);
    }
    final pending = _refreshing[id] = _refresh(id, force: force).whenComplete(
      () {
        // Do not return remove(): that would wait on this same Future.
        _refreshing.remove(id);
      },
    );
    return force ? pending : pending.catchError((Object _) => false);
  }

  Future<bool> _refresh(String id, {required bool force}) async {
    if (!id.startsWith('yt-playlist-')) return false;
    final key = id.substring('yt-playlist-'.length);
    final row = await db.youtubePlaylist(key);
    if (row == null || key.startsWith('single-')) return false;
    final hasStoredItems = (await _items(row)).isNotEmpty;
    if (!force &&
        hasStoredItems &&
        _clock().difference(row.lastCheckedAt) < refreshInterval) {
      return false;
    }
    // Throttle failed attempts only when stored sessions remain usable.
    // An empty starter must retry as soon as connectivity returns.
    if (hasStoredItems) {
      await (db.update(db.youtubePlaylists)
            ..where((p) => p.playlistId.equals(key)))
          .write(YoutubePlaylistsCompanion(lastCheckedAt: Value(_clock())));
    }
    try {
      final fresh = await api.resolvePlaylist(
        'https://www.youtube.com/playlist?list=$key',
      );
      // An empty answer is a failed extraction, not an emptied course:
      // keep the sessions already stored.
      if (fresh.items.isEmpty) throw const YoutubeUnavailableError();
      await storePlaylist(key, fresh);
      final updated = (await db.youtubePlaylist(key))!;
      final items = await _items(updated);
      await library.updateSnapshot(
        id,
        title: updated.title,
        subtitle: updated.uploader,
        coverUrl: updated.thumbnail,
        itemCount: items.length,
        durationMs: items.fold<int>(
          0,
          (a, b) => a + (b.durationSeconds > 0 ? b.durationSeconds * 1000 : 0),
        ),
      );
      _refreshErrors.remove(id);
      contentRevision.value++;
      refreshRevision.value++;
      return true;
    } catch (e) {
      final failure = _failure(e);
      final previous = _refreshErrors[id];
      _refreshErrors[id] = failure;
      // Repeated offline opens need no new UI invalidation.
      if (previous?.reason != failure.reason) refreshRevision.value++;
      throw failure; // Automatic callers retain their stored sessions quietly.
    }
  }

  Future<bool> refreshAll() async {
    var changed = false;
    for (final entry in await library.entries()) {
      if (entry.sourceId.startsWith('yt-playlist-')) {
        changed = await refresh(entry.sourceId) || changed;
      }
    }
    return changed;
  }

  @override
  Future<List<PackModel>> browsePacks() async => [
    for (final row in await db.youtubeCourses())
      if (await library.contains(ytPlaylistId(row.playlistId))) _summary(row),
  ];

  PackModel _summary(YoutubePlaylistRow row) => PackModel(
    id: ytPlaylistId(row.playlistId),
    title: row.title,
    subtitle: row.uploader,
    coverUrl: row.thumbnail,
    path: '/packs/${ytPlaylistId(row.playlistId)}',
    isPublished: true,
    attribution: youtubeAttribution(
      row.playlistId.startsWith('single-')
          ? 'https://www.youtube.com/watch?v=${row.playlistId.substring(7)}'
          : 'https://www.youtube.com/playlist?list=${row.playlistId}',
      row.uploader,
    ),
  );

  @override
  Future<PackModel> pack(String id) async {
    if (!id.startsWith('yt-playlist-')) {
      throw CatalogueEntryUnavailable('pack', id);
    }
    final row = await db.youtubePlaylist(id.substring('yt-playlist-'.length));
    if (row == null) throw CatalogueEntryUnavailable('pack', id);
    final stored = _summary(row).copyWith(
      items: [
        for (final item in await _items(row))
          PackItemsModel(
            type: TypeConstants.track,
            id: ytVideoId(item.videoId),
            title: item.title,
            subtitle: item.uploader,
            teacher: item.uploader,
            coverUrl: item.thumbnail,
            path: '/tracks/${ytVideoId(item.videoId)}',
            durationMs: item.durationSeconds > 0
                ? item.durationSeconds * 1000
                : null,
          ),
      ],
    );
    // A slow extractor must not delay opening stored courses or Home.
    // Automatic refresh records failures and returns false quietly.
    unawaited(refresh(id));
    return stored;
  }

  /// Resolves an expiring URL immediately before streaming or downloading.
  /// Callers must check for local audio before using this method.
  Future<Track> resolveTrack(String id) async {
    final metadata = await track(id);
    final stream = await _audio(id.substring('yt-video-'.length));
    return metadata.copyWith(
      voices: [
        for (final voice in metadata.voices)
          voice.copyWith(
            audioFiles: [
              for (final file in voice.audioFiles)
                file.copyWith(path: stream.url),
            ],
          ),
      ],
    );
  }

  Future<YoutubeAudioStream> _audio(String id) async {
    final hit = _streams[id];
    if (hit != null && _clock().isBefore(hit.until)) return hit.stream;
    _streams.remove(id);
    return _resolving[id] ??= () async {
      try {
        final stream = await api.resolveAudioStream(id);
        final uri = Uri.tryParse(stream.url);
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            !stream.mimeType.startsWith('audio/')) {
          throw const YoutubeUnavailableError();
        }
        final expiry = stream.expiresAt == null
            // Unknown expiry gets a short cache, never an assumed six hours.
            ? _clock().add(const Duration(minutes: 10))
            : DateTime.fromMillisecondsSinceEpoch(stream.expiresAt!);
        if (!expiry.isAfter(_clock())) throw const YoutubeUnavailableError();
        _streams[id] = (stream: stream, until: expiry.subtract(expiryMargin));
        return stream;
      } catch (e) {
        throw _failure(e);
      } finally {
        _resolving.remove(id);
      }
    }();
  }

  @override
  Future<Track> track(String id) async {
    if (!id.startsWith('yt-video-')) {
      throw CatalogueEntryUnavailable('track', id);
    }
    final videoId = id.substring('yt-video-'.length);
    final video = await db.youtubeVideo(videoId);
    if (video == null) throw CatalogueEntryUnavailable('track', id);
    // The course decides, as it does for the cues: the one the session was
    // opened from, else the most recently active. The video's own label
    // applies only when no course has one.
    final parent = await _courseOf(id);
    final group =
        (parent == null ? null : await library.groupOf(parent)) ??
        await library.groupOf(id) ??
        youtubeGroup(video.title);
    final url = 'https://www.youtube.com/watch?v=$videoId';
    return Track(
      id: id,
      title: video.title,
      subtitle: video.uploader,
      description: video.description,
      coverUrl: video.thumbnail,
      isPublished: true,
      hasBackgroundSound: group == LibraryGroup.practice,
      artist: TrackArtist(name: video.uploader, path: url),
      attribution: youtubeAttribution(url, video.uploader),
      voices: [
        TrackVoice(
          guideName: video.uploader,
          audioFiles: [
            TrackAudioFile(
              id: id,
              path: url,
              duration: video.durationSeconds > 0
                  ? video.durationSeconds * 1000
                  : 0,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async => {
    for (final row in await db.youtubeCourses())
      ytPlaylistId(row.playlistId): _ids(row).map(ytVideoId).toList(),
  };

  @override
  Future<List<PackItemsModel>> searchPacks(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return [];
    return [
      for (final pack in await browsePacks())
        if ('${pack.title} ${pack.subtitle}'.toLowerCase().contains(needle))
          PackItemsModel(
            type: TypeConstants.pack,
            id: pack.id,
            title: pack.title,
            subtitle: pack.subtitle,
            coverUrl: pack.coverUrl,
            path: pack.path ?? '/packs/${pack.id}',
          ),
    ];
  }

  @override
  Future<List<TrackSearchModel>> searchTracks(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return [];
    final activeVideoIds = <String>{};
    for (final entry in await library.entries()) {
      final id = entry.sourceId;
      if (id.startsWith('yt-video-')) {
        activeVideoIds.add(id.substring('yt-video-'.length));
      } else if (id.startsWith('yt-playlist-')) {
        final row = await db.youtubePlaylist(
          id.substring('yt-playlist-'.length),
        );
        if (row != null) activeVideoIds.addAll(_ids(row));
      }
    }
    return [
      for (final row in await db.youtubeSessions())
        if (activeVideoIds.contains(row.videoId) &&
            ('${row.title} ${row.uploader}'.toLowerCase().contains(needle)))
          TrackSearchModel(
            id: ytVideoId(row.videoId),
            title: row.title,
            subtitle: row.uploader,
            description: row.description,
            coverUrl: row.thumbnail,
            path: '/tracks/${ytVideoId(row.videoId)}',
          ),
    ];
  }

  /// The saved course a session counts towards: the one it was last opened
  /// from while that course still lists it, else [parentOf].
  Future<String?> _courseOf(String trackId) async {
    final lookup = sessionCourse;
    if (lookup != null) return lookup(trackId);
    final opened = await library.sessionContext(trackId);
    if (opened != null && await courseLists(opened, trackId)) return opened;
    return parentOf(trackId);
  }

  @override
  Future<bool> courseLists(String courseId, String trackId) async {
    if (!courseId.startsWith('yt-playlist-') ||
        !trackId.startsWith('yt-video-') ||
        !await library.contains(courseId)) {
      return false;
    }
    final row = await db.youtubePlaylist(
      courseId.substring('yt-playlist-'.length),
    );
    return row != null && _ids(row).map(ytVideoId).contains(trackId);
  }

  /// The most recently active saved course that lists [trackId] (the library
  /// is ordered by activity), for a session with no known context.
  @override
  Future<String?> parentOf(String trackId) async {
    for (final entry in await library.entries()) {
      if (!entry.sourceId.startsWith('yt-playlist-')) continue;
      final row = await db.youtubePlaylist(
        entry.sourceId.substring('yt-playlist-'.length),
      );
      if (row != null && _ids(row).map(ytVideoId).contains(trackId)) {
        return entry.sourceId;
      }
    }
    return null;
  }

  @override
  bool canSave(String id) =>
      id.startsWith('yt-video-') || id.startsWith('yt-playlist-');
  @override
  Future<bool> isSaved(String id) => library.contains(id);
  @override
  Future<void> setSaved(String id, {required bool saved}) async {
    if (!saved) {
      await library.remove(id);
      return;
    }
    if (id.startsWith('yt-playlist-')) {
      final row = await db.youtubePlaylist(id.substring('yt-playlist-'.length));
      if (row == null) return;
      final items = await _items(row);
      await library.add(
        LibraryDraft(
          sourceId: id,
          kind: LibraryKind.course,
          title: row.title,
          subtitle: row.uploader,
          coverUrl: row.thumbnail,
          group: youtubeGroup(row.title),
          itemCount: items.length,
          durationMs: items.fold<int>(
            0,
            (a, b) =>
                a + (b.durationSeconds > 0 ? b.durationSeconds * 1000 : 0),
          ),
        ),
      );
    } else {
      final row = await db.youtubeVideo(id.substring('yt-video-'.length));
      if (row == null) return;
      await library.add(
        LibraryDraft(
          sourceId: id,
          kind: LibraryKind.single,
          title: row.title,
          subtitle: row.uploader,
          coverUrl: row.thumbnail,
          group: youtubeGroup(row.title),
          durationMs: row.durationSeconds > 0 ? row.durationSeconds * 1000 : 0,
        ),
      );
    }
  }
}
