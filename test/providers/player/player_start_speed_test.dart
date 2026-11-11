import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/player/download/audio_downloader_provider.dart';
import 'package:medito/providers/player/ios_audio_handler.dart';
import 'package:medito/providers/player/playback_speed_provider.dart';
import 'package:medito/providers/player/player_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/src/audio_pigeon.g.dart' as pigeon;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends Mock implements AudioPlayer {}

/// The engine as the player provider drives it off Android: records the
/// speed it is set to and plays nothing.
class _Engine extends IosAudioHandler {
  _Engine() : super(player: _Player());

  final speeds = <double>[];
  final order = <String>[];

  /// Set to make the engine refuse a speed.
  bool speedFails = false;

  @override
  Future<void> setSpeed(double speed) async {
    if (speedFails) throw StateError('engine not ready');
    speeds.add(speed);
    order.add('speed');
  }

  @override
  Future<void> setCustomRepeatMode(pigeon.RepeatMode mode) async {}

  @override
  Future<void> setUrl(
    String? downloadPath,
    PlaybackRequest request,
    pigeon.Track trackData,
  ) async => order.add('url');

  @override
  Future<void> configureCues(
    CueSettings settings,
    PlaybackRequest request,
  ) async {}

  @override
  Future<void> play() async => order.add('play');
}

/// Nothing downloaded. The lookup waits for [_lookup] when one is set: the
/// session is still loading while it waits.
class _NoDownloads extends AudioDownloaderProvider {
  @override
  Future<String?> getTrackPath(String fileName) async {
    await _lookup?.future;
    return null;
  }
}

Completer<void>? _lookup;

const _talk = PlaybackRequest(
  trackId: 'ds-talk-2',
  fileId: 'ds-talk-2',
  title: 'Jhana basics',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://dharmaseed.org/talks/2/file.mp3',
  duration: 3600000,
  hasBackgroundSound: false,
);

const _sit = PlaybackRequest(
  trackId: 'ds-sit-3',
  fileId: 'ds-sit-3',
  title: 'Guided sit',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://dharmaseed.org/talks/3/file.mp3',
  duration: 1800000,
  hasBackgroundSound: true,
);

final _timer = timerPlaybackRequest(
  mode: TimerMode.countdown,
  duration: const Duration(minutes: 10),
  filePath: '/tmp/meditejo-timer.wav',
  title: 'Timer',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Engine engine;

  Future<ProviderContainer> container(Map<String, Object> prefs) async {
    _lookup = null;
    SharedPreferences.setMockInitialValues(prefs);
    engine = _Engine();
    iosAudioHandler = engine;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        audioDownloaderProvider.overrideWith(_NoDownloads.new),
        // The app keeps one audio state; each test gets its own.
        audioStateProvider.overrideWith(AudioStateNotifier.new),
        // The kind as the library would resolve it: talks for the talk, a
        // practice group for the sit.
        cueScopeForRequestProvider.overrideWith(
          (ref, request) async => CueScope(
            request.trackId == _talk.trackId ? CueKind.talks : CueKind.practice,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  const stored = {'speed.v1.talks': 1.5, 'speed.v1.practice': 0.9};

  test('a talk starts at the talks speed, before it plays', () async {
    final c = await container(stored);
    await c.read(playerProvider.notifier).play(_talk);
    expect(engine.speeds, [1.5]);
    expect(engine.order, ['speed', 'url', 'play']);
  });

  test('a sit starts at the practice speed', () async {
    final c = await container(stored);
    await c.read(playerProvider.notifier).play(_sit);
    expect(engine.speeds, [0.9]);
  });

  test('a timer always starts at 1×', () async {
    final c = await container(stored);
    await c.read(playerProvider.notifier).play(_timer);
    expect(engine.speeds, [1.0]);
  });

  test('with nothing stored every session starts at 1×', () async {
    final c = await container({});
    await c.read(playerProvider.notifier).play(_talk);
    await c.read(playerProvider.notifier).play(_sit);
    expect(engine.speeds, [1.0, 1.0]);
  });

  test(
    'a talk after a sped-up talk-then-sit does not inherit the sit',
    () async {
      final c = await container(stored);
      final player = c.read(playerProvider.notifier);
      await player.play(_talk);
      await player.play(_sit);
      await player.play(_talk);
      expect(engine.speeds, [1.5, 0.9, 1.5]);
    },
  );

  test(
    'a speed chosen while the session loads is the one it starts at',
    () async {
      final c = await container(stored);
      _lookup = Completer<void>();
      final playing = c.read(playerProvider.notifier).play(_talk);
      await Future<void>.delayed(Duration.zero);
      // The speed sheet, during loading: talks to 2×.
      await c.read(playbackSpeedProvider(CueKind.talks).notifier).set(2.0);
      _lookup!.complete();
      await playing;
      expect(engine.speeds, [2.0]);
    },
  );

  test('an engine that refuses the speed does not stop the session', () async {
    final c = await container(stored);
    engine.speedFails = true;
    await c.read(playerProvider.notifier).play(_talk);
    expect(engine.order, ['url', 'play']);
    expect(c.read(playerProvider), _talk);
  });
}
