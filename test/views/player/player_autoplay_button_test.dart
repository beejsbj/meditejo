import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/review_service_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/review_service.dart';
import 'package:medito/src/audio_pigeon.g.dart' as pigeon;
import 'package:medito/views/home/previews/stats_fixtures.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/art_finders.dart';

final _talk = PlaybackRequest(
  trackId: 'ds-talk-2',
  fileId: 'ds-talk-2',
  title: 'Jhana basics',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://dharmaseed.org/talks/2/file.mp3',
  duration: 3600000,
  hasBackgroundSound: false,
  guideName: 'Rob Burbea',
);

final _timer = timerPlaybackRequest(
  mode: TimerMode.countdown,
  duration: const Duration(minutes: 10),
  filePath: '/tmp/meditejo-timer.wav',
  title: 'Timer',
);

/// A player with nothing playing yet: not completed, at the start.
class _IdleAudio extends AudioStateNotifier {
  @override
  pigeon.PlaybackState build() => pigeon.PlaybackState(
    isPlaying: false,
    isBuffering: false,
    isSeeking: false,
    isCompleted: false,
    position: 0,
    duration: 600000,
    speed: pigeon.Speed(speed: 1),
    volume: 100,
    track: pigeon.Track(
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
  _FakePlayer(this.request);

  final PlaybackRequest request;

  @override
  PlaybackRequest? build() => request;

  @override
  Future<void> play(PlaybackRequest request) => Completer<void>().future;

  @override
  void stop() {}

  @override
  void setSpeed(double speed) {}
}

class _SilentBackgroundSounds extends BackgroundSoundsNotifier {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    holdCuratedArt();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => 0,
        );
  });

  /// The player for [request], whose cue scope names a course (as a session
  /// opened from one would).
  Future<void> pumpInCourse(
    WidgetTester tester,
    PlaybackRequest request,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PreviewShell(
        prefs: prefsDark,
        overrides: [
          playerProvider.overrideWith(() => _FakePlayer(request)),
          audioStateProvider.overrideWith(_IdleAudio.new),
          backgroundSoundsNotifierProvider.overrideWith(
            _SilentBackgroundSounds.new,
          ),
          statsProvider.overrideWith(_Stats.new),
          reviewServiceProvider.overrideWithValue(_Review()),
          cueScopeForRequestProvider.overrideWith(
            (ref, request) async =>
                const CueScope(CueKind.practice, courseId: 'ds-retreat-4496'),
          ),
        ],
        child: const PlayerView(skipCustomize: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  final autoplay = find.byKey(const ValueKey('player_autoplay'));

  testWidgets('a session in a course offers Autoplay', (tester) async {
    await pumpInCourse(tester, _talk);
    expect(autoplay, findsOneWidget);
    await close(tester);
  });

  testWidgets('a timer session never offers Autoplay', (tester) async {
    // Even with a course scope: a timer is not part of a course's queue.
    await pumpInCourse(tester, _timer);
    expect(find.byType(PlayerView), findsOneWidget);
    expect(autoplay, findsNothing);
    await close(tester);
  });
}
