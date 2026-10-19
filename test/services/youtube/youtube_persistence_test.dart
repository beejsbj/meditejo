import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/repositories/track/track_repository.dart';
import 'package:medito/src/youtube_api.g.dart';
import 'package:medito/utils/pending_end_screen.dart';
import 'package:medito/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const signed =
      'https://rr1.googlevideo.com/videoplayback?expire=1800000000&sig=secret';
  const track = Track(
    id: 'yt-video-aaaaaaaaaaa',
    title: 'Sit',
    description: '',
    coverUrl: '',
    isPublished: true,
    hasBackgroundSound: true,
    voices: [
      TrackVoice(
        audioFiles: [
          TrackAudioFile(
            id: 'yt-video-aaaaaaaaaaa',
            path: signed,
            duration: 600000,
          ),
        ],
      ),
    ],
  );

  test(
    'persisted download and current track metadata retain IDs without signed URLs',
    () {
      final saved = withoutYoutubeStream(track);
      final json = jsonEncode(saved);
      expect(json, isNot(contains('googlevideo')));
      expect(saved.voices.single.audioFiles.single.id, track.id);
      expect(
        track.voices.single.audioFiles.single.path,
        signed,
        reason: 'live request is unchanged',
      );
      expect(
        audioFileName(track.id, track.id, signed),
        audioFileName(saved.id, saved.voices.single.audioFiles.single.id, ''),
      );
    },
  );

  test('end-screen recovery never writes a signed stream URL', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final request = PlaybackRequest.fromTrack(
      track,
      track.voices.single,
      track.voices.single.audioFiles.single,
    );
    await PendingEndScreen.start(prefs, request, null);
    final record =
        jsonDecode(prefs.getString(PendingEndScreen.prefsKey)!) as Map;
    expect(record['request']['remoteUrl'], '');
    expect(record['request']['trackId'], track.id);
    expect(
      prefs.getString(PendingEndScreen.prefsKey),
      isNot(contains('googlevideo')),
    );
  });

  for (final code in [
    'private',
    'age-restricted',
    'network',
    'unavailable',
    'rate-limited',
  ]) {
    test('generated Pigeon codec preserves typed $code failures', () async {
      const channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.medito.YoutubeExtractorApi.resolveAudioStream',
        YoutubeExtractorApi.pigeonChannelCodec,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockDecodedMessageHandler<Object?>(channel, (
        Object? message,
      ) async {
        expect(message, ['aaaaaaaaaaa']);
        return <Object?>[code, 'Safe sentence', null];
      });
      addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
      await expectLater(
        YoutubeExtractorApi().resolveAudioStream('aaaaaaaaaaa'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    });
  }
}
