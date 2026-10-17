import 'package:drift/drift.dart';
import 'package:medito/services/library/feed_parser.dart';
import 'package:medito/services/library/import_http.dart';
import 'package:medito/services/library/lib_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/utils/logger.dart';

/// What a refresh pass found.
class FeedRefreshReport {
  const FeedRefreshReport({this.checked = 0, this.newEpisodes = 0, this.failed = 0});

  /// Feeds actually asked about.
  final int checked;
  final int newEpisodes;
  final int failed;
}

/// Looks for new episodes in the feeds the user imported.
///
/// A polite client: a feed is asked about at most once per [minInterval]
/// (unless forced), one at a time, and the request carries the `ETag` and
/// `Last-Modified` the server gave last time, so an unchanged feed costs a
/// bodyless 304. A failure is remembered with the time, so a dead feed is not
/// retried on every launch.
class FeedRefresher {
  FeedRefresher({
    required this.db,
    required this.lib,
    required this.library,
    required this.http,
    this.minInterval = const Duration(hours: 12),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final LibSource lib;
  final LibraryStore library;
  final ImportHttp http;
  final Duration minInterval;
  final DateTime Function() _clock;

  Future<FeedRefreshReport>? _running;

  /// Refreshes every due feed that is in the library and set to refresh.
  /// Overlapping calls share one pass.
  Future<FeedRefreshReport> refreshAll({bool force = false}) =>
      _running ??= _refreshAll(force).whenComplete(() => _running = null);

  Future<FeedRefreshReport> _refreshAll(bool force) async {
    var checked = 0;
    var added = 0;
    var failed = 0;
    for (final course in await db.feedsToRefresh()) {
      if (!await library.contains(course.id)) continue;
      final last = course.lastCheckedAt;
      if (!force && last != null && _clock().difference(last) < minInterval) {
        continue;
      }
      checked++;
      try {
        added += await refresh(course);
      } catch (e, st) {
        failed++;
        AppLogger.e('LIBRARY', 'Feed refresh failed for ${course.feedUrl}', e, st);
        await db.updateCourse(
          course.id,
          LibCoursesCompanion(
            lastCheckedAt: Value(_clock()),
            lastError: Value(e.toString()),
          ),
        );
      }
    }
    return FeedRefreshReport(checked: checked, newEpisodes: added, failed: failed);
  }

  /// Fetches one feed and stores what is new. Returns how many episodes were
  /// added. Throws when the feed cannot be read.
  Future<int> refresh(LibCourseRow course) async {
    final uri = Uri.parse(course.feedUrl);
    final result = await http.get(
      uri,
      etag: course.etag,
      lastModified: course.lastModified,
    );
    if (result.notModified) {
      await db.updateCourse(
        course.id,
        LibCoursesCompanion(lastCheckedAt: Value(_clock()), lastError: const Value(null)),
      );
      return 0;
    }
    if (!result.ok) throw StateError('HTTP ${result.status}');
    final feed = parseFeed(result.text, base: result.finalUri);
    if (feed.episodes.isEmpty) throw StateError('The feed has no audio episodes');
    final added = await lib.storeFeed(
      courseId: course.id,
      feedUrl: course.feedUrl,
      feed: feed,
      etag: result.etag,
      lastModified: result.lastModified,
      now: _clock(),
    );
    if (added > 0) {
      final tracks = await db.tracksOfCourse(course.id);
      await library.updateSnapshot(
        course.id,
        itemCount: tracks.length,
        durationMs: tracks.fold<int>(0, (sum, t) => sum + t.durationMs),
      );
    }
    return added;
  }
}
