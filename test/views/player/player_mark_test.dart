import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';
import 'package:medito/views/player/widgets/player_mark.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/track/track.dart' as model;
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/review_service_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/review_service.dart';
import 'package:medito/src/audio_pigeon.g.dart' as pigeon;
import 'package:medito/views/home/previews/stats_fixtures.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/art_finders.dart';

const _credit = SourceAttribution(
  source: 'Dharma Seed',
  creator: 'Rob Burbea',
  url: 'https://dharmaseed.org/talks/2/',
  licenseName: 'CC BY-NC-ND 4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
);

PlaybackRequest _request({
  SourceAttribution? attribution,
  String coverUrl = '',
}) => PlaybackRequest(
  trackId: 'ds-talk-2',
  fileId: 'ds-talk-2',
  title: 'Jhana basics',
  description: '',
  coverUrl: coverUrl,
  remoteUrl: 'https://dharmaseed.org/talks/2/file.mp3',
  duration: 3600000,
  hasBackgroundSound: false,
  guideName: 'Rob Burbea',
  artist: const model.TrackArtist(
    name: 'Rob Burbea',
    path: 'https://dharmaseed.org/talks/2/',
  ),
  attribution: attribution,
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
    duration: 3600000,
    speed: pigeon.Speed(speed: 1),
    volume: 100,
    track: pigeon.Track(
      id: 'ds-talk-2',
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

PlaybackRequest _timer() => timerPlaybackRequest(
  mode: TimerMode.countdown,
  duration: const Duration(minutes: 20),
  filePath: '/tmp/silence.mp3',
  title: 'Timer',
);

/// A session that is playing.
class _PlayingAudio extends _IdleAudio {
  @override
  pigeon.PlaybackState build() {
    final s = super.build();
    s.isPlaying = true;
    return s;
  }
}

MeditejoMarkState _mark(WidgetTester tester) =>
    tester.state<MeditejoMarkState>(find.byType(MeditejoMark));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    holdCuratedArt();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => 0,
        );
  });

  Future<void> pumpPlayer(
    WidgetTester tester,
    PlaybackRequest request, {
    bool playing = false,
    Map<String, Object> prefs = const {},
    bool reducedMotion = false,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PreviewShell(
        prefs: {...prefsDark, ...prefs},
        overrides: [
          playerProvider.overrideWith(() => _FakePlayer(request)),
          audioStateProvider.overrideWith(
            playing ? _PlayingAudio.new : _IdleAudio.new,
          ),
          backgroundSoundsNotifierProvider.overrideWith(
            _SilentBackgroundSounds.new,
          ),
          statsProvider.overrideWith(_Stats.new),
          reviewServiceProvider.overrideWithValue(_Review()),
        ],
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reducedMotion),
            child: const PlayerView(skipCustomize: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets("a timer shows the day's mark, above its controls", (
    tester,
  ) async {
    await pumpPlayer(tester, _timer());
    expect(find.byType(PlayerMark), findsOneWidget);
    expect(find.byType(MeditejoMark), findsOneWidget);
    final mark = tester.getRect(find.byType(PlayerMark));
    expect(mark.shortestSide, greaterThan(150));
    expect(mark.bottom, lessThan(tester.getRect(find.byType(Slider)).top));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('a recording keeps its cover and shows no mark', (tester) async {
    final request = _request();
    await pumpPlayer(tester, request);
    expect(find.byType(PlayerMark), findsNothing);
    expect(find.byType(MeditejoMark), findsNothing);
    expect(findArt(singleArt(request.trackId)), findsOneWidget);
    await close(tester);
  });

  testWidgets('it breathes at six a minute while playing', (tester) async {
    await pumpPlayer(tester, _timer(), playing: true);
    expect(_mark(tester).isRunning, isTrue);
    final widget = tester.widget<MeditejoMark>(find.byType(MeditejoMark));
    expect(widget.breathSeconds, 10);
    expect(widget.paused, isFalse);
    await close(tester);
  });

  testWidgets('it breathes at the pulse rate when one is set', (tester) async {
    await pumpPlayer(
      tester,
      _timer(),
      playing: true,
      prefs: {
        'cues.v1.practice': jsonEncode(
          CueSettings.defaults(CueKind.practice)
              .copyWith(pulseSound: cuePulseSounds['Soft click'], pulseBpm: 40)
              .toJson(),
        ),
      },
    );
    final widget = tester.widget<MeditejoMark>(find.byType(MeditejoMark));
    expect(widget.breathSeconds, 1.5);
    await close(tester);
  });

  testWidgets('paused, it holds', (tester) async {
    await pumpPlayer(tester, _timer());
    final widget = tester.widget<MeditejoMark>(find.byType(MeditejoMark));
    expect(widget.paused, isTrue);
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_mark(tester).isRunning, isFalse);
    await close(tester);
  });

  testWidgets('with reduced motion it is a still mark', (tester) async {
    await pumpPlayer(tester, _timer(), playing: true, reducedMotion: true);
    final widget = tester.widget<MeditejoMark>(find.byType(MeditejoMark));
    expect(widget.breathSeconds, isNull);
    expect(_mark(tester).isRunning, isFalse);
    await close(tester);
  });
}
