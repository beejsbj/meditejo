import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/youtube_fake.dart';

void main() {
  test(
    'schema 1 library gains YouTube tables without losing saves or positions',
    () async {
      useSystemSqlite();
      final scratch = Directory.systemTemp.createTempSync('youtube_migration');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final file = File('${scratch.path}/library.sqlite');
      var db = LibraryDatabase(NativeDatabase(file));
      var store = LibraryStore(db);
      await store.add(
        const LibraryDraft(
          sourceId: 'ds-talk-1',
          kind: LibraryKind.single,
          title: 'My saved practice',
          group: LibraryGroup.practice,
        ),
      );
      await store.savePosition('ds-talk-1', 60000, 600000);
      store.dispose();
      await db.close();

      // Recreate the previous schema exactly: only the additive tables and
      // columns of schemas 2 to 4 differ. The old library's data is left in place.
      final old = sqlite3.open(file.path);
      old.execute('DROP TABLE youtube_videos');
      old.execute('DROP TABLE youtube_playlists');
      old.execute('DROP TABLE youtube_channels');
      old.execute('DROP TABLE my_courses');
      old.execute('DROP TABLE my_course_items');
      old.execute('DROP TABLE session_contexts');
      old.execute('ALTER TABLE lib_tracks DROP COLUMN license_name');
      old.execute('ALTER TABLE lib_tracks DROP COLUMN license_url');
      old.execute('PRAGMA user_version = 1');
      old.dispose();

      db = LibraryDatabase(NativeDatabase(file));
      store = LibraryStore(db);
      addTearDown(() async {
        store.dispose();
        await db.close();
      });
      expect((await store.entries()).single.title, 'My saved practice');
      expect((await store.resumePoint('ds-talk-1'))!.positionMs, 60000);
      expect(await db.youtubeCourses(), isEmpty);
      expect(await db.youtubeSessions(), isEmpty);
      expect(await db.youtubeChannel('UCanyone0000000000000000'), isNull);
    },
  );

  test('schema 5 library gains YouTube channels and descriptions, keeping '
      'its courses, videos, saves and positions (#85)', () async {
    useSystemSqlite();
    final scratch = Directory.systemTemp.createTempSync('youtube_channels');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final file = File('${scratch.path}/library.sqlite');
    var db = LibraryDatabase(NativeDatabase(file));
    var store = LibraryStore(db);
    await store.add(
      const LibraryDraft(
        sourceId: 'yt-playlist-$playlistOne',
        kind: LibraryKind.course,
        title: 'Awakening from the Meaning Crisis',
        group: LibraryGroup.talks,
      ),
    );
    await store.savePosition('yt-video-$videoA', 90000, 1800000);
    store.dispose();
    await db.close();

    // The file as schema 5 left it: the YouTube tables without the new
    // columns, no channels table, and the old rows in place.
    final old = sqlite3.open(file.path);
    old.execute('DROP TABLE youtube_channels');
    old.execute('ALTER TABLE youtube_videos DROP COLUMN channel_id');
    old.execute('ALTER TABLE youtube_videos DROP COLUMN resolved_at');
    old.execute('ALTER TABLE youtube_playlists DROP COLUMN description');
    old.execute('ALTER TABLE youtube_playlists DROP COLUMN channel_id');
    old.execute(
      'INSERT INTO youtube_videos '
      '(video_id, title, uploader, thumbnail, description, duration_seconds) '
      "VALUES ('$videoA', 'Episode 1', 'John Vervaeke', "
      "'https://i.example/a.jpg', 'Resolved before the upgrade.', 1800), "
      "('$videoB', 'Episode 2', 'John Vervaeke', '', '', 0)",
    );
    old.execute(
      'INSERT INTO youtube_playlists '
      '(playlist_id, title, uploader, thumbnail, video_ids, last_checked_at) '
      "VALUES ('$playlistOne', 'Awakening from the Meaning Crisis', "
      "'John Vervaeke', 'https://i.example/p.jpg', "
      '\'["$videoA","$videoB"]\', 1760000000)',
    );
    old.execute('PRAGMA user_version = 5');
    old.dispose();

    db = LibraryDatabase(NativeDatabase(file));
    store = LibraryStore(db);
    addTearDown(() async {
      store.dispose();
      await db.close();
    });
    final entry = (await store.entries()).single;
    expect(entry.sourceId, 'yt-playlist-$playlistOne');
    expect(entry.group, LibraryGroup.talks);
    expect((await store.resumePoint('yt-video-$videoA'))!.positionMs, 90000);
    final a = (await db.youtubeVideo(videoA))!;
    expect(a.title, 'Episode 1');
    expect(a.description, 'Resolved before the upgrade.');
    expect(a.durationSeconds, 1800);
    expect(a.channelId, '');
    // Already described: counted as looked up, so the first launch does not
    // read the whole library again.
    expect(a.resolvedAt, isNotNull);
    expect(a.retryAt, isNull);
    expect((await db.youtubeVideo(videoB))!.resolvedAt, isNull);
    final list = (await db.youtubePlaylist(playlistOne))!;
    expect(list.title, 'Awakening from the Meaning Crisis');
    expect(list.videoIds, '["$videoA","$videoB"]');
    expect(list.description, '');
    expect(list.channelId, '');

    // The upgraded file works end to end: the course opens as it did, then
    // the details fill in from the (fake) extractor.
    const channel = 'UCpqDUjTsof-kTNpnyWper_Q';
    final api = FakeYoutubeApi()
      ..videos[videoA] = video(videoA, description: 'Episode one.')
      ..videos[videoB] = video(
        videoB,
        description: 'Episode two.',
        channel: channel,
      );
    final source = YoutubeSource(
      db: db,
      library: store,
      api: api,
      detailsPause: () => Duration.zero,
    );
    final pack = await source.pack('yt-playlist-$playlistOne');
    expect(pack.items, hasLength(2));
    expect(pack.teacher, isNull, reason: 'no channel known yet');
    await source.fillDetails('yt-playlist-$playlistOne');
    expect(api.videoCalls, [videoB], reason: 'only the undescribed one');
    expect(
      (await db.youtubeVideo(videoA))!.description,
      'Resolved before the upgrade.',
    );
    final b = (await db.youtubeVideo(videoB))!;
    expect(b.description, 'Episode two.');
    expect(b.channelId, channel);
    expect(await db.youtubeChannel(channel), isNotNull);
  });
}
