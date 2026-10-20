import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/review_service_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/services/review_service.dart';
import 'package:medito/src/audio_pigeon.g.dart';
import 'package:medito/views/home/previews/stats_fixtures.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlaybackState _state({
  required bool completed,
  required int positionMs,
  required int durationMs,
  bool playing = false,
}) {
  return PlaybackState(
    isPlaying: playing,
    isBuffering: false,
    isSeeking: false,
    isCompleted: completed,
    position: positionMs,
    duration: durationMs,
    speed: Speed(speed: 1),
    volume: 100,
    track: Track(
      id: '',
      title: '',
      fileId: '',
      description: '',
      imageUrl: '',
      artist: '',
    ),
  );
}

class _FakePlayer extends PlayerProvider {
  _FakePlayer(this.initial);

  final PlaybackRequest initial;
  final played = <PlaybackRequest>[];
  int stops = 0;

  @override
  PlaybackRequest? build() => initial;

  @override
  Future<void> play(PlaybackRequest request) async {
    played.add(request);
    state = request;
  }

  @override
  void stop() => stops++;

  @override
  void setSpeed(double speed) {}

  @override
  Future<void> updateCueSettings(CueSettings settings) async {}
}

class _Bell extends SessionBellPreview {
  final rung = <(double, String)>[];

  @override
  Future<void> play(double volume, {String asset = kSessionBellAsset}) async {
    rung.add((volume, asset));
  }
}

class _SilentBackgroundSounds extends BackgroundSoundsNotifier {
  @override
  void applyCueSettings(CueSettings settings) {}

  @override
  void stopBackgroundSound() {}

  @override
  void playBackgroundSoundFromPref() {}
}

class _Stats extends StatsNotifier {
  @override
  Future<LocalAllStats> build() async => previewStats;
}

class _Review implements ReviewService {
  @override
  Future<bool> onHappyFeedback({bool suppress = false}) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object> _prefsWith(CueSettings practice) => {
  ...prefsDark,
  'cues.v1.practice': jsonEncode(practice.toJson()),
};

Widget _player({
  required PlayerProvider player,
  required Map<String, Object> prefs,
  SessionBellPreview? bell,
  List overrides = const [],
}) => PreviewShell(
  prefs: prefs,
  overrides: [
    playerProvider.overrideWith(() => player),
    audioStateProvider.overrideWith(AudioStateNotifier.new),
    backgroundSoundsNotifierProvider.overrideWith(_SilentBackgroundSounds.new),
    statsProvider.overrideWith(_Stats.new),
    reviewServiceProvider.overrideWithValue(_Review()),
    if (bell != null) sessionBellPreviewProvider.overrideWithValue(bell),
    ...overrides,
  ],
  child: const PlayerView(skipCustomize: true),
);

final _timer = timerPlaybackRequest(
  mode: TimerMode.countdown,
  duration: const Duration(minutes: 10),
  filePath: '/tmp/timer.wav',
  title: 'Timer',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => 0,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_health'),
      (call) async => false,
    );
  });

  Future<void> endTimerEarly(
    WidgetTester tester, {
    required CueSettings practice,
    required _Bell bell,
  }) async {
    final player = _FakePlayer(_timer);
    await tester.pumpWidget(
      _player(player: player, prefs: _prefsWith(practice), bell: bell),
    );
    await tester.pump();
    await tester.pump();
    final audio = ProviderScope.containerOf(
      tester.element(find.byType(PlayerView)),
    ).read(audioStateProvider.notifier);
    audio.updatePlaybackState(
      _state(
        completed: false,
        positionMs: 120000,
        durationMs: 600000,
        playing: true,
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(player.stops, 1);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    'ending a timer early rings the Customize end cue at the bell volume',
    (tester) async {
      final bell = _Bell();
      await endTimerEarly(
        tester,
        practice: const CueSettings(bellVolume: 0.8),
        bell: bell,
      );
      expect(bell.rung, [(0.8, kSessionBellAsset)]);
    },
  );

  testWidgets('ending a timer early with the end cue Off rings nothing', (
    tester,
  ) async {
    final bell = _Bell();
    await endTimerEarly(
      tester,
      practice: const CueSettings(endSound: ''),
      bell: bell,
    );
    expect(bell.rung, isEmpty);
  });
}
