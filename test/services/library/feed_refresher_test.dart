import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/services/library/feed_refresher.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/import_http.dart';
import 'package:medito/services/library/library_models.dart';

import '../../helpers/library_fixtures.dart';

const feedUrl = 'https://example.org/evening.rss';

String withExtraEpisode() => libraryFixture('rss_podcast.xml').replaceFirst(
  '<item>\n      <title>Third sit',
  '''<item>
      <title>Fourth sit: walking</title>
      <guid isPermaLink="false">ep-4</guid>
      <pubDate>Tue, 17 Jun 2025 04:00:00 +0000</pubDate>
      <enclosure url="https://cdn.example.org/ep4.mp3" length="1" type="audio/mpeg"/>
      <itunes:duration>600</itunes:duration>
    </item>
    <item>
      <title>Third sit''',
);

void main() {
  late LibraryHarness h;
  late FeedRefresher refresher;
  late FakeWeb web;
  var now = DateTime.utc(2026, 10, 17, 8);
  late http.Response Function(http.BaseRequest) respond;

  setUp(() async {
    now = DateTime.utc(2026, 10, 17, 8);
    h = LibraryHarness.create(
      routes: {
        feedUrl: xmlResponse(
          libraryFixture('rss_podcast.xml'),
          headers: {'etag': '"v1"'},
        ),
      },
    );
    final preview = await h.service.resolve(feedUrl);
    await h.service.add(
      preview,
      const ImportChoice(
        kind: LibraryKind.course,
        group: LibraryGroup.practice,
      ),
    );
    // From here the feed answers from [respond], recording requests.
    respond = (_) => xmlResponse(libraryFixture('rss_podcast.xml'));
    web = FakeWeb({});
    refresher = FeedRefresher(
      db: h.db,
      lib: h.lib,
      library: h.store,
      http: ImportHttp(client: web.clientWith((request) => respond(request))),
      clock: () => now,
    );
  });
  tearDown(() => h.dispose());

  test('a conditional request, and a 304 changes nothing', () async {
    respond = (_) => http.Response('', 304, headers: {'etag': '"v1"'});
    now = DateTime.utc(2026, 10, 18, 9); // a day later: due
    final report = await refresher.refreshAll();

    expect(report.checked, 1);
    expect(report.newEpisodes, 0);
    expect(web.requests.single.headers['If-None-Match'], '"v1"');
    expect(await h.db.allTracks(), hasLength(3));
    final course = (await h.db.courseById(
      (await h.store.entries()).single.sourceId,
    ))!;
    expect(course.lastCheckedAt!.toUtc(), DateTime.utc(2026, 10, 18, 9));
  });

  test('new episodes are added and the library entry follows', () async {
    respond = (_) => xmlResponse(withExtraEpisode(), headers: {'etag': '"v2"'});
    now = DateTime.utc(2026, 10, 18, 9);
    final report = await refresher.refreshAll();

    expect(report.newEpisodes, 1);
    final entry = (await h.store.entries()).single;
    expect(entry.itemCount, 4);
    final pack = await h.lib.pack(entry.sourceId);
    expect(
      pack.items.map((i) => i.title).last,
      'Fourth sit: walking',
      reason: 'oldest first, so newest last',
    );
    expect((await h.db.courseById(entry.sourceId))!.etag, '"v2"');
  });

  test(
    'a renamed feed updates the library entry, a user rename is kept',
    () async {
      final id = (await h.store.entries()).single.sourceId;
      await h.store.setTitle(id, 'My name');
      respond = (_) => xmlResponse(
        libraryFixture('rss_podcast.xml').replaceFirst(
          '<title>Evening Sits</title>',
          '<title>Night Sits</title>',
        ),
      );
      now = DateTime.utc(2026, 10, 18, 9);
      final report = await refresher.refreshAll();

      expect(report.newEpisodes, 0, reason: 'metadata only');
      final entry = (await h.store.entries()).single;
      expect(entry.title, 'Night Sits');
      expect(entry.displayTitle, 'My name');
    },
  );

  test('a feed checked recently is left alone, unless forced', () async {
    now = DateTime.utc(2026, 10, 17, 9);
    expect((await refresher.refreshAll()).checked, 0);
    expect(web.requests, isEmpty);
    expect((await refresher.refreshAll(force: true)).checked, 1);
  });

  test(
    'a failure is remembered so a dead feed is not asked every launch',
    () async {
      respond = (_) => http.Response('oops', 500);
      now = DateTime.utc(2026, 10, 18, 9);
      final report = await refresher.refreshAll();
      expect(report.failed, 1);
      final id = (await h.store.entries()).single.sourceId;
      final course = (await h.db.courseById(id))!;
      expect(course.lastError, isNotNull);
      expect(course.lastCheckedAt!.toUtc(), DateTime.utc(2026, 10, 18, 9));
      expect(
        await h.db.allTracks(),
        hasLength(3),
        reason: 'what was there stays',
      );
      expect((await refresher.refreshAll()).checked, 0);
    },
  );

  test('feeds turned off, or no longer in the library, are skipped', () async {
    final id = (await h.store.entries()).single.sourceId;
    now = DateTime.utc(2026, 10, 18, 9);
    await h.lib.updateCourseSettings(id, autoRefresh: false);
    expect((await refresher.refreshAll()).checked, 0);
    await h.lib.updateCourseSettings(id, autoRefresh: true);
    await h.store.remove(id);
    expect((await refresher.refreshAll()).checked, 0);
  });
}
