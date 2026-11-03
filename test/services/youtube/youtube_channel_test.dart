import 'dart:async';

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
      detailsPause: Duration.zero,
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

  test(
    'a video YouTube will not show is marked done, not asked again',
    () async {
      final id = await addPlaylist();
      api.videos.remove(videoB); // unavailable
      api.videoCalls.clear();

      await source.fillDetails(id);
      expect(api.videoCalls, [videoA, videoB, videoC]);
      final gone = (await db.youtubeVideo(videoB))!;
      expect(gone.resolvedAt, isNotNull);
      expect(gone.description, '');

      api.videoCalls.clear();
      await source.fillDetails(id);
      expect(api.videoCalls, isEmpty);
    },
  );

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
}
