import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/player/player_provider.dart'
    show iosAudioHandler;
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

  int sessions = 0;
  int repeats = 0;

  @override
  Future<void> recordSessionCompletion() async => sessions++;

  @override
  Future<void> recordRepeatPlaythrough() async => repeats++;
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

  /// Repeat forever wrapping back to the start of the same item.
  void loop() {
    final event = PlaybackEvent(
      processingState: ProcessingState.ready,
      duration: const Duration(hours: 1),
    );
    discontinuity.add(
      PositionDiscontinuity(
        PositionDiscontinuityReason.autoAdvance,
        event,
        event,
      ),
    );
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
      // The ambient notifier follows this handler's fade, as on an iPhone.
      iosAudioHandler = handler;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ambient = container.read(backgroundSoundsNotifierProvider.notifier);
      ambient.followIosFade();
      await iosBackgroundPlayer.setVolume(ambient.scaledVolume(50));

      streams.processing.add(ProcessingState.completed);
      expect(await remaining, 8000);
      await _settle();
      expect(handler.extending, isTrue);
      // Eight seconds from the true end, past the voice's end: fading, at 40%.
      expect(
        iosBackgroundPlayer.volume,
        closeTo(ambient.scaledVolume(40), 1e-9),
      );

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

  test('Swift hears of state changes, not every position tick', () async {
    final calls = _mockSwift({'sampleListening': false});
    final streams = _Streams();
    final player = streams.player();
    when(() => player.setSpeed(any())).thenAnswer((_) async {});
    final handler = _WiredHandler(player);
    await handler.ensureInitialized();
    await handler.configureCues(const CueSettings(), _guided);
    await handler.play();
    await _settle();
    calls.clear();
    int count(String method) => calls.where((c) => c.method == method).length;

    // Five position ticks within a second: one listening sample, no transport.
    for (var i = 1; i <= 5; i++) {
      streams.position.add(Duration(milliseconds: 200 * i));
      await _settle();
    }
    expect(count('transport'), 0);
    expect(count('sampleListening'), 1);

    // A state change, a seek and a speed change each go to Swift.
    streams.playerState.add(PlayerState(false, ProcessingState.ready));
    await _settle();
    streams.seek();
    await _settle();
    await handler.setSpeed(1.5);
    await _settle();
    expect(count('transport'), 3);
  });

  group('repeat play-throughs follow the 90% rule', () {
    late Map<String, Object?> swift;
    late _Streams streams;
    late _WiredHandler handler;

    setUp(() async {
      swift = {'sampleListening': false};
      _mockSwift(swift);
      streams = _Streams();
      final player = streams.player();
      for (final mode in LoopMode.values) {
        when(() => player.setLoopMode(mode)).thenAnswer((_) async {});
      }
      when(() => player.seek(Duration.zero)).thenAnswer((_) async {});
      handler = _WiredHandler(player);
      await handler.ensureInitialized();
      await handler.configureCues(const CueSettings(), _guided);
      await handler.play();
      await _settle();
    });

    Future<void> heardNinetyPercent() async {
      swift['sampleListening'] = true;
      streams.playerState.add(PlayerState(true, ProcessingState.ready));
      await _settle();
    }

    test(
      'repeat once: a session earned in pass two is not also a repeat',
      () async {
        await handler.setCustomRepeatMode(pigeon.RepeatMode.once);
        // Pass one: seeked to the middle, then heard to its end (50%).
        streams.processing.add(ProcessingState.completed);
        await _settle();
        expect((handler.sessions, handler.repeats), (0, 0));

        // Pass two: 90% is reached part-way and recorded as the session.
        await heardNinetyPercent();
        expect((handler.sessions, handler.repeats), (1, 0));

        // Its end is the session's own end, not another repeat.
        streams.processing.add(ProcessingState.completed);
        await _settle();
        await _fromSwift('sessionEnded', {
          'extensionFinished': false,
          'tailMs': 0,
        });
        expect((handler.sessions, handler.repeats), (1, 0));
      },
    );

    test(
      'repeat forever: wraps count only after the session was earned',
      () async {
        await handler.setCustomRepeatMode(pigeon.RepeatMode.infinite);
        // Seeked near the end twice: nothing heard, nothing counted.
        streams.loop();
        streams.loop();
        await _settle();
        expect((handler.sessions, handler.repeats), (0, 0));

        // The third pass is heard: the session, once.
        await heardNinetyPercent();
        streams.loop();
        await _settle();
        expect((handler.sessions, handler.repeats), (1, 0));

        // Only a further full pass is a repeat.
        swift['endPass'] = true;
        streams.loop();
        await _settle();
        expect((handler.sessions, handler.repeats), (1, 1));
      },
    );

    test(
      'repeat forever: a pass that was not 90% heard adds nothing',
      () async {
        await handler.setCustomRepeatMode(pigeon.RepeatMode.infinite);
        await heardNinetyPercent();
        streams.loop();
        await _settle();
        expect((handler.sessions, handler.repeats), (1, 0));

        // Seeked to the end of the loop: Swift says the pass was not heard.
        swift['endPass'] = false;
        streams.loop();
        streams.loop();
        await _settle();
        expect((handler.sessions, handler.repeats), (1, 0));

        // The next pass is heard in full.
        swift['endPass'] = true;
        streams.loop();
        await _settle();
        expect((handler.sessions, handler.repeats), (1, 1));
      },
    );

    test(
      'every finished pass starts a fresh listening record in Swift',
      () async {
        final calls = _mockSwift(swift);
        await handler.setCustomRepeatMode(pigeon.RepeatMode.infinite);
        await heardNinetyPercent();
        streams.loop();
        streams.loop();
        await _settle();
        expect(calls.where((c) => c.method == 'endPass'), hasLength(2));
      },
    );
  });

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
      when(() => player.pause()).thenAnswer((_) async {});
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

      // Paused first: a previous session left just_audio "playing", and the
      // new source must not start under a countdown.
      verifyInOrder([() => player.pause(), () => player.setFilePath(path)]);
      verifyNever(() => player.setAsset(any()));
      expect(handler.trackState, same(track));
    },
  );
}
