import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/src/youtube_api.g.dart';

import '../../helpers/library_fixtures.dart';
import '../../helpers/youtube_fake.dart';

/// #85: the channel is the teacher, and descriptions come in for every item.
const vervaeke = 'UCpqDUjTsof-kTNpnyWper_Q';
const guest = 'UCguestguestguestguest01';
const listOne = 'https://www.youtube.com/playlist?list=$playlistOne';
const course = ImportChoice(
  kind: LibraryKind.course,
  group: LibraryGroup.practice,
);
const single = ImportChoice(
  kind: LibraryKind.single,
  group: LibraryGroup.practice,
);

void main() {
  late LibraryDatabase db;
  late LibraryStore store;
  late FakeYoutubeApi api;
  late TestClock clock;
  late YoutubeSource source;

  setUp(() {
    db = memoryLibraryDb();
    store = LibraryStore(db);
    api = FakeYoutubeApi()
      ..playlists[playlistOne] = playlist(
        [
          item(videoA, title: 'Episode 1', uploader: 'John Vervaeke'),
          item(videoB, title: 'Episode 2', uploader: 'John Vervaeke'),
          item(videoC, title: 'A guest', uploader: 'Guest', channel: guest),
        ],
        title: 'Awakening from the Meaning Crisis',
        uploader: 'John Vervaeke',
        description: 'A fifty-part series.',
        channel: vervaeke,
        avatar: 'https://yt3.example/vervaeke-small.jpg',
      )
      ..videos[videoA] = video(
        videoA,
        uploader: 'John Vervaeke',
        description: 'Episode one, in full.',
        channel: vervaeke,
      )
      ..videos[videoB] = video(
        videoB,
        uploader: 'John Vervaeke',
        description: 'Episode two, in full.',
        channel: vervaeke,
      )
      ..videos[videoC] = video(
        videoC,
        uploader: 'Guest',
        description: 'A guest talk.',
        channel: guest,
      )
      ..channels[vervaeke] = YoutubeChannel(
        url: channelUrl(vervaeke),
        name: 'John Vervaeke',
        avatar: 'https://yt3.example/vervaeke.jpg',
        description: 'Cognitive science and wisdom.',
      )
      ..channels[guest] = YoutubeChannel(
        url: channelUrl(guest),
        name: 'Guest',
        avatar: 'https://yt3.example/guest.jpg',
        description: '',
      );
    clock = TestClock();
    source = YoutubeSource(
      db: db,
      library: store,
      api: api,
      clock: clock.call,
      detailsPause: () => Duration.zero,
    );
  });

  tearDown(() => db.close());

  Future<String> addPlaylist() async {
    final preview = await source.preview(Uri.parse(listOne));
    return (await source.add(preview, course)).entryId;
  }

  test('a channel link gives its stable key, and nothing else does', () {
    expect(youtubeChannelKey(channelUrl(vervaeke)), vervaeke);
    expect(
      youtubeChannelKey('https://m.youtube.com/channel/$vervaeke/videos'),
      vervaeke,
    );
    expect(youtubeChannelKey('https://www.youtube.com/@vervaeke'), '@vervaeke');
    expect(
      youtubeChannelKey('https://www.youtube.com/watch?v=$videoA'),
      isNull,
    );
    expect(youtubeChannelKey('https://example.org/channel/$vervaeke'), isNull);
    expect(youtubeChannelKey(''), isNull);
    expect(youtubeChannelKey(null), isNull);
    expect(ytChannelId(vervaeke), 'yt-channel-$vervaeke');
    expect(ytChannelKeyOf(ytChannelId(vervaeke)), vervaeke);
  });

  test('an imported playlist keeps its description and its channel', () async {
    final preview = await source.preview(Uri.parse(listOne));
    expect(preview.description, 'A fifty-part series.');
    final id = (await source.add(preview, course)).entryId;

    final pack = await source.pack(id);
    expect(pack.description, 'A fifty-part series.');
    expect(pack.teacher?.id, 'yt-channel-$vervaeke');
    expect(pack.teacher?.name, 'John Vervaeke');
    expect(
      pack.teacher?.photoUrl,
      'https://yt3.example/vervaeke-small.jpg',
      reason: 'the playlist page already shows the owner\'s picture',
    );
    expect(pack.teacher?.pageUrl, channelUrl(vervaeke));
    expect(
      await source.avatarFor(id),
      'https://yt3.example/vervaeke-small.jpg',
    );

    final rows = {
      for (final v in await db.youtubeSessions()) v.videoId: v.channelId,
    };
    expect(rows, {videoA: vervaeke, videoB: vervaeke, videoC: guest});
  });

  test(
    'details fill each video once, then each channel once, and stop',
    () async {
      final id = await addPlaylist();
      api.videoCalls.clear();

      expect(await source.fillDetails(id), isTrue);

      expect(api.videoCalls, [videoA, videoB, videoC]);
      expect(
        api.channelCalls,
        unorderedEquals([channelUrl(vervaeke), channelUrl(guest)]),
      );
      final described = {
        for (final v in await db.youtubeSessions()) v.videoId: v.description,
      };
      expect(described, {
        videoA: 'Episode one, in full.',
        videoB: 'Episode two, in full.',
        videoC: 'A guest talk.',
      });
      final pack = await source.pack(id);
      expect(pack.teacher?.bio, 'Cognitive science and wisdom.');
      expect(pack.teacher?.photoUrl, 'https://yt3.example/vervaeke.jpg');
      final track = await source.track(ytVideoId(videoB));
      expect(track.description, 'Episode two, in full.');

      // Nothing is asked twice.
      api.videoCalls.clear();
      api.channelCalls.clear();
      expect(await source.fillDetails(id), isFalse);
      expect(api.videoCalls, isEmpty);
      expect(api.channelCalls, isEmpty);
    },
  );

  test('a later refresh of the list keeps what the details found', () async {
    final id = await addPlaylist();
    await source.fillDetails(id);
    clock.advance(const Duration(days: 1));

    expect(await source.refresh(id, force: true), isTrue);

    final row = (await db.youtubeVideo(videoA))!;
    expect(row.description, 'Episode one, in full.');
    expect(row.resolvedAt, isNotNull);
    expect(row.channelId, vervaeke);
    final channel = (await db.youtubeChannel(vervaeke))!;
    expect(
      channel.avatar,
      'https://yt3.example/vervaeke-small.jpg',
      reason: 'the playlist page\'s picture is still the channel\'s',
    );
    expect(channel.description, 'Cognitive science and wisdom.');
    expect((await source.pack(id)).description, 'A fifty-part series.');
  });

  test('offline stops the lookups; the next try picks up the rest', () async {
    final id = await addPlaylist();
    api.videoCalls.clear();
    api.failure = PlatformException(code: 'network');

    expect(await source.fillDetails(id), isFalse);
    expect(api.videoCalls, [videoA], reason: 'stopped at the first failure');
    expect(api.channelCalls, isEmpty);
    expect((await db.youtubeVideo(videoA))!.resolvedAt, isNull);

    api.failure = null;
    api.videoCalls.clear();
    expect(await source.fillDetails(id), isTrue);
    expect(api.videoCalls, [videoA, videoB, videoC]);
  });

  test('a private or age-restricted video is marked done, never asked '
      'again', () async {
    final id = await addPlaylist();
    api.videoFailures[videoA] = PlatformException(code: 'private');
    api.videoFailures[videoB] = PlatformException(code: 'age-restricted');
    api.videoCalls.clear();

    await source.fillDetails(id);
    expect(api.videoCalls, [videoA, videoB, videoC]);
    for (final videoId in [videoA, videoB]) {
      final row = (await db.youtubeVideo(videoId))!;
      expect(row.resolvedAt, isNotNull);
      expect(row.retryAt, isNull);
      expect(row.description, '');
    }

    clock.advance(const Duration(days: 30));
    api.videoCalls.clear();
    await source.fillDetails(id);
    expect(api.videoCalls, isEmpty);
  });

  test('any other failure waits a week, then is tried again', () async {
    final id = await addPlaylist();
    api.videoFailures[videoB] = PlatformException(code: 'unavailable');
    api.videoCalls.clear();

    await source.fillDetails(id);
    final waiting = (await db.youtubeVideo(videoB))!;
    expect(waiting.resolvedAt, isNull, reason: 'not done for good');
    expect(
      waiting.retryAt!.isAtSameMomentAs(
        clock.now.add(YoutubeSource.retryAfter),
      ),
      isTrue,
    );

    clock.advance(const Duration(days: 6));
    api.videoCalls.clear();
    await source.fillDetails(id);
    expect(api.videoCalls, isEmpty, reason: 'still waiting');

    clock.advance(const Duration(days: 2));
    api.videoFailures.clear();
    await source.fillDetails(id);
    expect(api.videoCalls, [videoB]);
    final read = (await db.youtubeVideo(videoB))!;
    expect(read.description, 'Episode two, in full.');
    expect(read.resolvedAt, isNotNull);
    expect(read.retryAt, isNull);
  });

  test('a channel that fails to read waits a week too', () async {
    final id = await addPlaylist();
    api.channels.remove(vervaeke);
    await source.fillDetails(id);
    final channel = (await db.youtubeChannel(vervaeke))!;
    expect(channel.checkedAt, isNull);
    expect(channel.retryAt, isNotNull);
    api.channelCalls.clear();
    await source.fillDetails(id);
    expect(api.channelCalls, isEmpty);
  });

  test('an empty answer never replaces a description', () async {
    final id = await addPlaylist();
    // A summary stored earlier, then a lookup that reads no description.
    await (db.update(db.youtubeVideos)..where((v) => v.videoId.equals(videoA)))
        .write(const YoutubeVideosCompanion(description: Value('Kept.')));
    api.videos[videoA] = video(
      videoA,
      uploader: 'John Vervaeke',
      description: '',
      channel: vervaeke,
    );
    api.channels[vervaeke] = YoutubeChannel(
      url: channelUrl(vervaeke),
      name: '',
      avatar: '',
      description: '',
    );
    await (db.update(db.youtubeChannels)
          ..where((c) => c.channelId.equals(vervaeke)))
        .write(const YoutubeChannelsCompanion(description: Value('About.')));

    await source.fillDetails(id);

    final row = (await db.youtubeVideo(videoA))!;
    expect(row.description, 'Kept.');
    expect(row.resolvedAt, isNotNull);
    final channel = (await db.youtubeChannel(vervaeke))!;
    expect(channel.description, 'About.');
    expect(channel.name, 'John Vervaeke');
    expect(channel.avatar, 'https://yt3.example/vervaeke-small.jpg');
  });

  test('background lookups stop at the budget for this run; the next run '
      'carries on', () async {
    final id = await addPlaylist();
    api.videoCalls.clear();
    source = YoutubeSource(
      db: db,
      library: store,
      api: api,
      clock: clock.call,
      detailsPause: () => Duration.zero,
      backgroundLookups: 2,
    );

    await source.fillDetails(id);
    expect(api.videoCalls, [videoA, videoB]);
    expect(api.channelCalls, isEmpty);
    expect((await db.youtubeVideo(videoC))!.resolvedAt, isNull);

    api.videoCalls.clear();
    await source.fillDetails(id);
    expect(api.videoCalls, isEmpty, reason: 'spent for this run');

    // Opening an episode is not a background lookup.
    expect(await source.describe(ytVideoId(videoC)), isTrue);
    expect(api.videoCalls, [videoC]);

    // A new run of the app has a new budget.
    source = YoutubeSource(
      db: db,
      library: store,
      api: api,
      clock: clock.call,
      detailsPause: () => Duration.zero,
      backgroundLookups: 2,
    );
    api.videoCalls.clear();
    await source.fillDetails(id);
    expect(api.videoCalls, isEmpty, reason: 'every video is done');
    expect(
      api.channelCalls,
      unorderedEquals([channelUrl(vervaeke), channelUrl(guest)]),
    );
  });

  test('the default pause is two to five seconds, and varies', () {
    final source = YoutubeSource(db: db, library: store, api: api);
    final pauses = {for (var i = 0; i < 50; i++) source.detailsPause()};
    expect(pauses.length, greaterThan(1));
    for (final pause in pauses) {
      expect(pause.inMilliseconds, inInclusiveRange(2000, 5000));
    }
    expect(source.backgroundLookups, 25);
  });

  test('opening an episode reads its description once, at once', () async {
    final id = await addPlaylist();
    api.videoCalls.clear();
    final revision = source.contentRevision.value;

    expect(await source.describe(ytVideoId(videoB)), isTrue);
    expect(api.videoCalls, [videoB]);
    expect(source.contentRevision.value, revision + 1);
    expect(
      (await source.track(ytVideoId(videoB))).description,
      'Episode two, in full.',
    );

    // Already read: no second lookup.
    expect(await source.describe(ytVideoId(videoB)), isFalse);
    expect(api.videoCalls, [videoB]);
    // A playlist's own description comes with the playlist.
    expect(await source.describe(id), isFalse);
    expect(api.videoCalls, [videoB]);
  });

  test('opening an episode while offline changes nothing and throws '
      'nothing', () async {
    await addPlaylist();
    api.failure = PlatformException(code: 'network');
    expect(await source.describe(ytVideoId(videoB)), isFalse);
    final row = (await db.youtubeVideo(videoB))!;
    expect(row.resolvedAt, isNull);
    expect(row.retryAt, isNull);
  });

  test('a one-video course\'s Summary reads its video on demand', () async {
    // Saved before descriptions were kept: nothing resolved yet.
    await source.storePlaylist(
      'single-$videoA',
      playlist([item(videoA, uploader: 'John Vervaeke')]),
    );
    final id = ytSingleCourseId(videoA);
    expect((await db.youtubeVideo(videoA))!.resolvedAt, isNull);
    api.videoCalls.clear();

    expect(await source.describe(id), isTrue);
    expect(api.videoCalls, [videoA]);
    expect((await source.pack(id)).description, 'Episode one, in full.');
  });

  test('a channel page and a fill share one channel read', () async {
    final id = await addPlaylist();
    // Every video already looked up, so the fill goes straight to channels.
    await (db.update(
      db.youtubeVideos,
    )).write(YoutubeVideosCompanion(resolvedAt: Value(clock.now)));
    api.channelGate = Completer<void>();
    final fill = source.fillDetails(id);
    await pumpEventQueue();
    await source.channelPage('yt-channel-$vervaeke');
    await pumpEventQueue();
    api.channelGate!.complete();
    await fill;
    expect(
      api.channelCalls.where((u) => u == channelUrl(vervaeke)),
      hasLength(1),
    );
  });

  test('two fills of the same course share one pass', () async {
    final id = await addPlaylist();
    api.videoCalls.clear();
    api.videoGate = Completer<void>();
    final first = source.fillDetails(id);
    final second = source.fillDetails(id);
    await pumpEventQueue();
    api.videoGate!.complete();
    expect(await Future.wait([first, second]), [true, true]);
    expect(api.videoCalls, [videoA, videoB, videoC]);
  });

  test(
    'a single video is its channel\'s, and needs only the channel',
    () async {
      api.videos[videoA] = video(
        videoA,
        uploader: 'John Vervaeke',
        channel: vervaeke,
        avatar: 'https://yt3.example/from-video.jpg',
      );
      final preview = await source.preview(
        Uri.parse('https://www.youtube.com/watch?v=$videoA'),
      );
      final id = (await source.add(preview, single)).entryId;
      expect(await source.avatarFor(id), 'https://yt3.example/from-video.jpg');
      api.videoCalls.clear();

      await source.fillDetails(id);
      expect(api.videoCalls, isEmpty, reason: 'it was resolved on import');
      expect(api.channelCalls, [channelUrl(vervaeke)]);
    },
  );

  test('refreshAll fills in details for everything saved', () async {
    final id = await addPlaylist();
    api.videoCalls.clear();
    await source.refreshAll();
    expect(api.videoCalls, [videoA, videoB, videoC]);
    expect((await source.pack(id)).teacher?.bio, isNotEmpty);
  });

  test(
    'a channel page lists its saved courses and videos, not others\'',
    () async {
      final courseId = await addPlaylist();
      final preview = await source.preview(
        Uri.parse('https://www.youtube.com/watch?v=$videoC'),
      );
      final guestVideo = (await source.add(preview, single)).entryId;

      final page = (await source.channelPage('yt-channel-$vervaeke'))!;
      expect(page.channel.name, 'John Vervaeke');
      expect(page.courses.map((c) => c.id), [courseId]);
      expect(page.sessions, isEmpty);

      final guestPage = (await source.channelPage('yt-channel-$guest'))!;
      expect(guestPage.courses, isEmpty);
      expect(guestPage.sessions.map((s) => s.id), [guestVideo]);

      expect(
        await source.channelPage('yt-channel-UCnobodynobodynobody00'),
        isNull,
      );
      expect(await source.channelPage('ds-teacher-1'), isNull);
    },
  );

  test('opening a channel page reads the channel once', () async {
    await addPlaylist();
    await source.channelPage('yt-channel-$vervaeke');
    await pumpEventQueue();
    expect(api.channelCalls, [channelUrl(vervaeke)]);
    final page = (await source.channelPage('yt-channel-$vervaeke'))!;
    expect(page.channel.bio, 'Cognitive science and wisdom.');
    expect(api.channelCalls, hasLength(1));
  });

  test(
    'an extractor that names no channel (an older build) leaves no teacher',
    () async {
      api.playlists[playlistOne] = playlist([item(videoA)]);
      final id = await addPlaylist();
      final pack = await source.pack(id);
      expect(pack.teacher, isNull);
      expect(pack.description, isNull);
      expect(await source.avatarFor(id), '');
    },
  );

  test('a channel saves as a teacher, lists, and comes out again', () async {
    await addPlaylist();
    final id = ytChannelId(vervaeke);
    expect(source.canSave(id), isTrue);
    expect(await source.isSaved(id), isFalse);

    await source.setSaved(id, saved: true);
    expect(await source.isSaved(id), isTrue);
    final entry = (await store.entry(id))!;
    expect(entry.kind, LibraryKind.teacher);
    expect(entry.title, 'John Vervaeke');
    expect(entry.subtitle, 'YouTube');
    expect(entry.coverUrl, 'https://yt3.example/vervaeke-small.jpg');
    expect(
      (await store.entries()).where((e) => e.kind == LibraryKind.teacher),
      [isA<LibraryEntry>().having((e) => e.sourceId, 'id', id)],
    );
    // Saving it subscribes to nothing: no lookups, now or on refresh.
    api.videoCalls.clear();
    api.playlistCalls.clear();
    expect(await source.fillDetails(id), isFalse);
    expect(api.videoCalls, isEmpty);
    expect(api.channelCalls, isEmpty);

    await source.setSaved(id, saved: false);
    expect(await source.isSaved(id), isFalse);
    expect(await store.entry(id), isNull);
    // The channel itself stays, for its courses' Teacher tab.
    expect(await db.youtubeChannel(vervaeke), isNotNull);
  });

  test('a saved channel takes the picture its page gives later', () async {
    api.playlists[playlistOne] = playlist(
      [item(videoA, uploader: 'John Vervaeke')],
      uploader: 'John Vervaeke',
      channel: vervaeke,
    );
    await addPlaylist();
    final id = ytChannelId(vervaeke);
    await source.setSaved(id, saved: true);
    expect((await store.entry(id))!.coverUrl, '', reason: 'art stands in');

    await source.channelPage(id);
    await pumpEventQueue();
    expect(
      (await store.entry(id))!.coverUrl,
      'https://yt3.example/vervaeke.jpg',
    );
  });

  test('a channel that is not stored cannot be saved', () async {
    await source.setSaved(ytChannelId(guest), saved: true);
    expect(await store.entry(ytChannelId(guest)), isNull);
  });
}
