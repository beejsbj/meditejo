import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:medito/models/cues/cue_settings.dart';
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

  final IosSessionBells _bells = _Bells();

  @override
  IosSessionBells get sessionBells => _bells;

  @override
  Future<void> ensureInitialized() async {}
}

/// The same handler with Swift cues, as on an iPhone.
class _NativeHandler extends _Handler {
  _NativeHandler(super.player);

  @override
  bool get usesNativeCues => true;
}

const _cueChannel = MethodChannel('meditejo/cues');

const _guided = PlaybackRequest(
  trackId: 'lib-talk',
  fileId: 'file',
  title: 'A talk',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://source.example/talk.mp3',
  duration: 3600000,
  hasBackgroundSound: false,
);

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// A call from Swift to Dart on the cue channel.
Future<void> _fromSwift(String method, [Object? arguments]) =>
    _messenger.handlePlatformMessage(
      _cueChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );

/// Records what Dart asks of Swift; [answers] stands in for its replies.
List<MethodCall> _mockSwift([Map<String, Object?> answers = const {}]) {
  final calls = <MethodCall>[];
  _messenger.setMockMethodCallHandler(_cueChannel, (call) async {
    calls.add(call);
    return answers[call.method];
  });
  for (final name in [
    'com.ryanheise.audio_session',
    'com.ryanheise.av_audio_session',
  ]) {
    _messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
  addTearDown(() => _messenger.setMockMethodCallHandler(_cueChannel, null));
  return calls;
}

_Player _endedPlayer() {
  final player = _Player();
  when(() => player.duration).thenReturn(const Duration(hours: 1));
  when(() => player.playing).thenReturn(false);
  when(() => player.processingState).thenReturn(ProcessingState.completed);
  return player;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the true end is terminal even when the session did not earn its stats',
    () async {
      _mockSwift();
      final handler = _NativeHandler(_endedPlayer());
      await handler.configureCues(const CueSettings(), _guided);

      // A resumed or scrubbed talk: well under 90% heard, no extension.
      await _fromSwift('sessionEnded', {
        'extensionFinished': false,
        'tailMs': 0,
      });

      expect(handler.sessionCompleted, isTrue);
    },
  );

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
