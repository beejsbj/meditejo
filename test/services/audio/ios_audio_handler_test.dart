import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/providers/player/ios_audio_handler.dart';
import 'package:medito/services/audio/ios_session_bells.dart';
import 'package:medito/src/audio_pigeon.g.dart' as pigeon;
import 'package:mocktail/mocktail.dart';

class _Player extends Mock implements AudioPlayer {}

class _Bells extends Mock implements IosSessionBells {}

// Keep native session setup out of the source-selection regression test.
class _Handler extends IosAudioHandler {
  _Handler(AudioPlayer player) : super(player: player);

  @override
  final IosSessionBells sessionBells = _Bells();

  @override
  Future<void> ensureInitialized() async {}
}

void main() {
  test(
    'downloaded audio loads from its filesystem path, not the asset bundle',
    () async {
      final player = _Player();
      const path = '/documents/my downloads/lib-track-file.mp3';
      when(
        () => player.setFilePath(path),
      ).thenAnswer((_) async => const Duration(minutes: 5));
      when(() => player.setLoopMode(LoopMode.off)).thenAnswer((_) async {});
      final handler = _Handler(player);
      const request = PlaybackRequest(
        trackId: 'lib-track',
        fileId: 'file',
        title: 'Downloaded session',
        description: '',
        coverUrl: '',
        remoteUrl: 'https://source.example/session.mp3',
        duration: 300000,
        hasBackgroundSound: false,
      );
      final track = pigeon.Track(
        id: request.trackId,
        fileId: request.fileId,
        title: request.title,
        description: '',
        imageUrl: '',
        artist: '',
      );

      await handler.setUrl(path, request, track);

      verify(() => player.setFilePath(path)).called(1);
      verifyNever(() => player.setAsset(any()));
      expect(handler.trackState, same(track));
    },
  );
}
