import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/player/playback_source.dart';

PlaybackRequest _request(String trackId) => PlaybackRequest(
  trackId: trackId,
  fileId: trackId,
  title: 'A sit',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
  duration: 600000,
  hasBackgroundSound: true,
);

Track _resolved(String id) => Track(
  id: id,
  title: 'A sit',
  description: '',
  coverUrl: '',
  isPublished: true,
  hasBackgroundSound: true,
  voices: [
    TrackVoice(
      guideName: 'Quiet Channel',
      audioFiles: [
        TrackAudioFile(
          id: id,
          path: 'https://rr1.googlevideo.com/audio?sig=SECRET',
          duration: 600000,
        ),
      ],
    ),
  ],
);

void main() {
  const video = 'yt-video-aaaaaaaaaaa';

  test(
    'a downloaded YouTube session plays its file and resolves nothing',
    () async {
      final asked = <String>[];
      final source = await playbackSource(
        _request(video),
        downloadPath: '/data/$video-$video.audio',
        resolve: (id) async {
          asked.add(id);
          return _resolved(id);
        },
      );

      expect(source, '/data/$video-$video.audio');
      expect(asked, isEmpty);
    },
  );

  test(
    'a downloaded session opens even when the extractor would fail',
    () async {
      // Offline, rate-limited or stuck: the local file does not depend on it.
      final source = await playbackSource(
        _request(video),
        downloadPath: '/data/$video.audio',
        resolve: (_) => throw const YoutubeUnavailableError(
          reason: YoutubeFailureReason.rateLimited,
        ),
      );
      expect(source, '/data/$video.audio');
    },
  );

  test(
    'a YouTube session that is not downloaded streams a fresh address',
    () async {
      final asked = <String>[];
      final source = await playbackSource(
        _request(video),
        downloadPath: null,
        resolve: (id) async {
          asked.add(id);
          return _resolved(id);
        },
      );

      expect(source, 'https://rr1.googlevideo.com/audio?sig=SECRET');
      expect(asked, [video]);
    },
  );

  test(
    'a failed resolve keeps its type for the message the user sees',
    () async {
      await expectLater(
        playbackSource(
          _request(video),
          downloadPath: null,
          resolve: (_) => throw const YoutubeUnavailableError(
            reason: YoutubeFailureReason.rateLimited,
          ),
        ),
        throwsA(
          isA<YoutubeUnavailableError>().having(
            (e) => e.reason,
            'reason',
            YoutubeFailureReason.rateLimited,
          ),
        ),
      );
    },
  );

  test('other sources play the address their request carries', () async {
    final source = await playbackSource(
      _request('ds-talk-1'),
      downloadPath: null,
      resolve: (_) => throw PlatformException(code: 'unexpected'),
    );
    expect(source, 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
  });
}
