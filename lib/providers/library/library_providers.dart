import 'dart:io';

import 'package:medito/exceptions/app_error.dart';

import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/services/youtube/youtube_platform.dart';
import 'package:medito/src/youtube_api.g.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/library/feed_refresher.dart';
import 'package:medito/services/library/import_http.dart';
import 'package:medito/services/library/import_service.dart';
import 'package:medito/services/library/lib_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_migration.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/library/playback_position_tracker.dart';
import 'package:medito/services/my_courses/my_course_source.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/utils/logger.dart';
import 'package:path_provider/path_provider.dart';

/// The user's library file, on the device only.
final libraryDatabaseProvider = Provider<LibraryDatabase>((ref) {
  final db = LibraryDatabase.open();
  ref.onDispose(db.close);
  return db;
});

/// The library itself. The first use carries over saves made before it
/// existed, files Dharma Seed retreats under Practice, and, on a first run,
/// adds the starter set.
final libraryStoreProvider = Provider<LibraryStore>((ref) {
  final store = LibraryStore(
    ref.watch(libraryDatabaseProvider),
    prepare: (db) async {
      final dharmaSeed = ref.read(dharmaSeedDatabaseProvider);
      await migrateDharmaSeedSaves(db, dharmaSeed);
      await reclassifyLibraryDefaults(db);
      await seedStarterSet(
        db,
        dharmaSeed,
        includeYoutube: ref.read(youtubeAvailableProvider),
      );
    },
  );
  ref.onDispose(store.dispose);
  return store;
});

/// Imported courses and singles, served as a content source.
final libSourceProvider = Provider<LibSource>(
  (ref) => LibSource(
    db: ref.watch(libraryDatabaseProvider),
    library: ref.watch(libraryStoreProvider),
  ),
);

/// Courses the user made from sessions anywhere, served as a content source.
/// It reads their sessions through the other sources.
final Provider<MyCourseSource> myCourseSourceProvider = Provider((ref) {
  final source = MyCourseSource(
    db: ref.watch(libraryDatabaseProvider),
    library: ref.watch(libraryStoreProvider),
    sources: () => ref.read(contentSourcesProvider),
  );
  void changed() => ref.invalidate(packTrackIdsProvider);
  source.revision.addListener(changed);
  ref.onDispose(() {
    source.revision.removeListener(changed);
    source.dispose();
  });
  return source;
});

/// Changes when a personal course or its sessions do.
final myCoursesRevisionProvider =
    NotifierProvider<ValueListenableNotifier<int>, int>(
      () => ValueListenableNotifier(
        (ref) => ref.watch(myCourseSourceProvider).revision,
      ),
    );

final youtubeAvailableProvider = Provider<bool>(
  (ref) => youtubeBridgeAvailable,
);

final youtubeExtractorProvider = Provider<YoutubeExtractorApi>(
  (ref) => YoutubeExtractorApi(),
);

final youtubeSourceProvider = Provider<YoutubeSource>((ref) {
  final source = YoutubeSource(
    db: ref.watch(libraryDatabaseProvider),
    library: ref.watch(libraryStoreProvider),
    api: ref.watch(youtubeExtractorProvider),
  );
  void refreshCompleted() => ref.invalidate(packTrackIdsProvider);
  source.refreshRevision.addListener(refreshCompleted);
  ref.onDispose(() => source.refreshRevision.removeListener(refreshCompleted));
  return source;
});

final youtubeContentRevisionProvider =
    NotifierProvider<ValueListenableNotifier<int>, int>(
      () => ValueListenableNotifier(
        (ref) => ref.watch(youtubeSourceProvider).contentRevision,
      ),
    );

/// Refresh failures are separate from catalogue reads: cached sessions stay usable.
final youtubeRefreshRevisionProvider =
    NotifierProvider<ValueListenableNotifier<int>, int>(
      () => ValueListenableNotifier(
        (ref) => ref.watch(youtubeSourceProvider).refreshRevision,
      ),
    );

final youtubeRefreshErrorProvider = Provider.autoDispose
    .family<YoutubeUnavailableError?, String>((ref, id) {
      ref.watch(youtubeRefreshRevisionProvider);
      return ref.watch(youtubeSourceProvider).refreshError(id);
    });

final importHttpProvider = Provider<ImportHttp>((ref) {
  final http = ImportHttp();
  ref.onDispose(http.close);
  return http;
});

/// Reads an audio file's length with a throwaway player; null if it cannot.
Future<int?> probeAudioDuration(String pathOrUrl) async {
  final player = AudioPlayer();
  try {
    final duration = pathOrUrl.startsWith('http')
        ? await player.setUrl(pathOrUrl)
        : await player.setFilePath(pathOrUrl);
    return duration?.inMilliseconds;
  } catch (e) {
    AppLogger.d('LIBRARY', 'Could not read the length of $pathOrUrl: $e');
    return null;
  } finally {
    await player.dispose();
  }
}

final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(
    http: ref.watch(importHttpProvider),
    lib: ref.watch(libSourceProvider),
    library: ref.watch(libraryStoreProvider),
    dharmaSeed: ref.watch(dharmaSeedSourceProvider),
    youtube: ref.watch(youtubeAvailableProvider)
        ? ref.watch(youtubeSourceProvider)
        : null,
    storageDirectory: () async {
      final directory = await getApplicationSupportDirectory();
      return Directory(directory.path);
    },
    temporaryDirectories: () async => [(await getTemporaryDirectory()).path],
    durationProbe: probeAudioDuration,
  ),
);

final feedRefresherProvider = Provider<FeedRefresher>(
  (ref) => FeedRefresher(
    db: ref.watch(libraryDatabaseProvider),
    lib: ref.watch(libSourceProvider),
    library: ref.watch(libraryStoreProvider),
    http: ref.watch(importHttpProvider),
  ),
);

/// Changes when the library's entries do; watch it to re-read.
final libraryRevisionProvider =
    NotifierProvider<ValueListenableNotifier<int>, int>(
      () => ValueListenableNotifier(
        (ref) => ref.watch(libraryStoreProvider).revision,
      ),
    );

/// Changes when a saved position is added, moved or cleared.
final playbackPositionsRevisionProvider =
    NotifierProvider<ValueListenableNotifier<int>, int>(
      () => ValueListenableNotifier(
        (ref) => ref.watch(libraryStoreProvider).positionsRevision,
      ),
    );

/// Everything in the library, most recently added or played first.
final libraryEntriesProvider = FutureProvider.autoDispose<List<LibraryEntry>>((
  ref,
) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(libraryStoreProvider).entries();
});

/// The library as the screens group it: practice first, then talks, with
/// teachers apart.
class LibrarySections {
  const LibrarySections({
    this.practice = const [],
    this.talks = const [],
    this.teachers = const [],
  });

  factory LibrarySections.of(List<LibraryEntry> entries) => LibrarySections(
    practice: [
      for (final e in entries)
        if (e.kind != LibraryKind.teacher && e.group == LibraryGroup.practice)
          e,
    ],
    talks: [
      for (final e in entries)
        if (e.kind != LibraryKind.teacher && e.group == LibraryGroup.talks) e,
    ],
    teachers: [
      for (final e in entries)
        if (e.kind == LibraryKind.teacher) e,
    ],
  );

  final List<LibraryEntry> practice;
  final List<LibraryEntry> talks;
  final List<LibraryEntry> teachers;

  /// Practice first, then talks: the order Home shows them in.
  List<LibraryEntry> get contentFirstPractice => [...practice, ...talks];

  bool get isEmpty => practice.isEmpty && talks.isEmpty && teachers.isEmpty;
}

final librarySectionsProvider =
    Provider.autoDispose<AsyncValue<LibrarySections>>(
      (ref) => ref.watch(libraryEntriesProvider).whenData(LibrarySections.of),
    );

/// Whether one course, talk or teacher is in the library.
final inLibraryProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  id,
) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(libraryStoreProvider).contains(id);
});

/// Where the user stopped in a session, if they did.
final resumePointProvider = FutureProvider.autoDispose
    .family<ResumePoint?, String>((ref, trackId) {
      ref.watch(playbackPositionsRevisionProvider);
      return ref.watch(libraryStoreProvider).resumePoint(trackId);
    });

/// Resume points for several sessions at once (a course page's rows).
final resumePointsProvider = FutureProvider.autoDispose
    .family<Map<String, ResumePoint>, List<String>>((ref, trackIds) {
      ref.watch(playbackPositionsRevisionProvider);
      return ref.watch(libraryStoreProvider).resumePoints(trackIds);
    });

/// Looks for new episodes in the imported feeds shortly after launch, off the
/// startup path. A feed is asked about at most twice a day; offline, it fails
/// quietly and the episodes already on the device are what the app uses.
Future<void> startFeedRefresh(
  WidgetRef ref, {
  Duration delay = const Duration(seconds: 10),
}) async {
  try {
    await Future<void>.delayed(delay);
    final youtubeChanged =
        ref.read(youtubeAvailableProvider) &&
        await ref.read(youtubeSourceProvider).refreshAll();
    final report = await ref.read(feedRefresherProvider).refreshAll();
    if (youtubeChanged || report.checked > report.failed) {
      // A feed answered, so its name, artwork or episodes may have changed.
      // Course pages and completion ticks cached before would otherwise keep
      // showing the old ones.
      ref.invalidate(packDataProvider);
      ref.invalidate(packTrackIdsProvider);
    }
  } catch (e, st) {
    AppLogger.e('LIBRARY', 'Feed refresh did not run', e, st);
  }
}

/// Keeps the saved place in each session, and the library's order, in step
/// with what the player is doing. Listened to once, from the main screen.
final playbackPositionTrackerProvider = Provider<PlaybackPositionTracker>((
  ref,
) {
  final router = ref.watch(libraryContentRouterProvider);
  final store = ref.watch(libraryStoreProvider);
  return PlaybackPositionTracker(
    store,
    // The course the session was opened from, and the one its source names.
    parentsOf: (trackId) async => {
      ?await store.sessionContext(trackId),
      ?await router.parentOf(trackId),
    },
    ignore: (id) => id == kLegacyTimerTrackId || isTimerSessionId(id),
  );
});

/// A router over the sources, for questions about content IDs.
final libraryContentRouterProvider = Provider<ContentRouter>(
  (ref) => ContentRouter(sources: ref.watch(contentSourcesProvider)),
);
