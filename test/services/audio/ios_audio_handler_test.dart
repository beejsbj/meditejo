import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
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

/// A handler with its real listeners, on a player whose streams the test drives.
class _WiredHandler extends IosAudioHandler {
  _WiredHandler(AudioPlayer player) : super(player: player);

  final IosSessionBells _bells = _Bells();

  @override
  IosSessionBells get sessionBells => _bells;

  @override
  bool get usesNativeCues => true;
}

class _Streams {
  final position = StreamController<Duration>.broadcast();
  final playerState = StreamController<PlayerState>.broadcast();
  final processing = StreamController<ProcessingState>.broadcast();
  final discontinuity = StreamController<PositionDiscontinuity>.broadcast();

  _Player player() {
    final player = _endedPlayer();
    when(() => player.positionStream).thenAnswer((_) => position.stream);
    when(() => player.playerStateStream).thenAnswer((_) => playerState.stream);
    when(
      () => player.processingStateStream,
    ).thenAnswer((_) => processing.stream);
    when(
      () => player.positionDiscontinuityStream,
    ).thenAnswer((_) => discontinuity.stream);
    when(
      () => player.playbackEventStream,
    ).thenAnswer((_) => const Stream.empty());
    when(() => player.speedStream).thenAnswer((_) => const Stream.empty());
    when(
      () => player.bufferedPositionStream,
    ).thenAnswer((_) => const Stream.empty());
    when(() => player.durationStream).thenAnswer((_) => const Stream.empty());
    when(() => player.position).thenReturn(const Duration(hours: 1));
    when(() => player.speed).thenReturn(1);
    when(
      () => player.playerState,
    ).thenReturn(PlayerState(true, ProcessingState.completed));
    when(() => player.pause()).thenAnswer((_) async {});
    when(() => player.play()).thenAnswer((_) async {});
    return player;
  }

  void seek() => discontinuity.add(
    PositionDiscontinuity(
      PositionDiscontinuityReason.seek,
      PlaybackEvent(),
      PlaybackEvent(),
    ),
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an interruption during the extension', () {
    late List<MethodCall> calls;
    late _WiredHandler handler;

    setUp(() async {
      calls = _mockSwift();
      final streams = _Streams();
      handler = _WiredHandler(streams.player());
      await handler.ensureInitialized();
      await handler.configureCues(const CueSettings(extendMinutes: 5), _guided);
      streams.processing.add(ProcessingState.completed);
      await _settle();
      calls.clear();
    });

    // Ends the extension so its clock reader stops with the test.
    tearDown(
      () =>
          _fromSwift('sessionEnded', {'extensionFinished': false, 'tailMs': 0}),
    );

    List<Object?> held() => [
      for (final call in calls)
        if (call.method == 'setHeld') (call.arguments as Map)['held'],
    ];

    test('holds it and resumes only when the interruption ends', () async {
      handler.handleInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await _settle();
      expect(held(), [true]);

      handler.handleInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await _settle();
      expect(held(), [true, false]);
    });

    test('stays held when iOS does not ask to resume', () async {
      handler.handleInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.unknown),
      );
      handler.handleInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.unknown),
      );
      await _settle();
      expect(held(), [true]);
    });

    test('unplugging headphones holds it until the listener plays', () async {
      handler.handleBecomingNoisy();
      await _settle();
      expect(held(), [true]);
      handler.handleInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await _settle();
      expect(held(), [true]);
    });
  });

  test(
    'the extension clock carries the ambient fade to the true end',
    () async {
      final calls = _mockSwift({
        'state': {'phase': 'extension', 'extensionRemainingMs': 8000},
      });
      final streams = _Streams();
      final handler = _WiredHandler(streams.player());
      await handler.ensureInitialized();
      await handler.configureCues(const CueSettings(extendMinutes: 1), _guided);
      final remaining = handler.extensionRemainingStream.first;

      streams.processing.add(ProcessingState.completed);
      expect(await remaining, 8000);
      expect(handler.extending, isTrue);
      // Eight seconds from the end: the ambient is fading, not at full volume.
      expect(ambientFadeVolume(50, 8000), 40);

      await _fromSwift('sessionEnded', {
        'extensionFinished': true,
        'tailMs': 0,
      });
      expect(handler.extending, isFalse);
      final polls = calls.where((c) => c.method == 'state').length;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        calls.where((c) => c.method == 'state').length,
        polls,
        reason: 'the clock is read only while the extension runs',
      );
    },
  );

  test('the ambient fade is full until the last ten seconds', () {
    expect(ambientFadeVolume(50, 600000), 50);
    expect(ambientFadeVolume(50, 10000), 50);
    expect(ambientFadeVolume(50, 5000), 25);
    expect(ambientFadeVolume(50, 0), 0);
    expect(ambientFadeVolume(50, -300), 0);
  });

  test('seeking back during the extension ends the Swift hold', () async {
    final calls = _mockSwift();
    final streams = _Streams();
    final handler = _WiredHandler(streams.player());
    await handler.ensureInitialized();
    await handler.configureCues(const CueSettings(extendMinutes: 5), _guided);

    // The voice reaches its end: the silent extension begins in Swift.
    streams.processing.add(ProcessingState.completed);
    await _settle();
    expect(calls.map((c) => c.method), contains('voiceEnded'));
    expect(handler.nativeHold, isTrue);

    // Scrub back two minutes: the narration plays again.
    streams.seek();
    await _settle();
    expect(handler.nativeHold, isFalse);

    // Pause now pauses the voice, not a hold that no longer runs.
    calls.clear();
    await handler.pause();
    expect(calls.map((c) => c.method), isNot(contains('setHeld')));
  });

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

  test('with autoplay Swift holds the interlude until Dart ends it', () async {
    final calls = _mockSwift();
    final handler = _NativeHandler(_endedPlayer());
    await handler.configureCues(
      const CueSettings(autoplay: true, interludeSeconds: 10),
      _guided,
    );
    await _fromSwift('sessionEnded', {
      'extensionFinished': false,
      'tailMs': 0,
      'interlude': true,
    });
    expect(handler.sessionCompleted, isTrue);

    // The course has no next session: release the hold.
    await handler.endInterlude();
    expect(calls.map((c) => c.method), contains('endInterlude'));
  });

  test(
    'a finished extension after a seek to the end does not earn the stats',
    () async {
      _mockSwift({'sampleListening': false});
      final handler = _NativeHandler(_endedPlayer());
      await handler.configureCues(const CueSettings(extendMinutes: 1), _guided);

      await _fromSwift('sessionEnded', {
        'extensionFinished': true,
        'tailMs': 0,
      });

      expect(handler.completionEarned, isFalse);
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
