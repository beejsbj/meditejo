import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';
import 'package:medito/views/player/widgets/bottom_actions/player_action_bar.dart';
import 'package:medito/views/player/widgets/player_mark.dart';
import 'package:medito/views/player/widgets/sleep_timer_control.dart';
import 'package:medito/providers/player/sleep_timer_provider.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/track/track.dart' as model;
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/review_service_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/review_service.dart';
import 'package:medito/src/audio_pigeon.g.dart' as pigeon;
import 'package:medito/views/home/previews/stats_fixtures.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/art_finders.dart';

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

PlaybackRequest _timer({TimerMode mode = TimerMode.countdown}) =>
    timerPlaybackRequest(
      mode: mode,
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

class _SleepEngine implements SleepTimerEngine {
  final armed = <Duration>[];
  var cancels = 0;

  @override
  Future<void> arm(Duration after) async => armed.add(after);

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> expired() async {}
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
    double textScale = 1.0,
    Size size = const Size(411, 891),
    bool insets = false,
    List<Override> extra = const [],
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = size;
    if (insets) {
      // A status bar and a gesture/nav bar.
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 32);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 32);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
    }
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
          ...extra,
        ],
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.linear(textScale),
            ),
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

  // The transport must always be on screen with the mark, for the countdown
  // and the stopwatch (whose readout grows fastest with text), with insets.
  // Where there is too little room the mark is left out and the layout is the
  // one it was without a mark.
  for (final mode in TimerMode.values) {
    for (final size in const [
      Size(360, 640),
      Size(360, 740),
      Size(411, 891),
      Size(1024, 600),
    ]) {
      for (final scale in const [1.0, 1.3, 1.5, 2.0]) {
        testWidgets('the transport stays on screen: ${mode.name}, $size, '
            '${scale}x text', (tester) async {
          await pumpPlayer(
            tester,
            _timer(mode: mode),
            textScale: scale,
            size: size,
            insets: true,
          );
          final bar = tester.getRect(find.byType(PlayerActionBar));
          final stop = tester.getRect(find.byIcon(Icons.stop_rounded));
          final marks = find.byType(PlayerMark);
          if (marks.evaluate().isNotEmpty) {
            final mark = tester.getRect(marks);
            expect(mark.shortestSide, greaterThanOrEqualTo(96));
            expect(stop.top, greaterThanOrEqualTo(0));
            expect(stop.bottom, lessThanOrEqualTo(bar.top));
            expect(stop.bottom, lessThanOrEqualTo(size.height));
            if (size.width < 700) expect(mark.bottom, lessThan(stop.top));
          }
          // Roomy screens do show the mark.
          if (size.height >= 891 && scale <= 1.3) {
            expect(marks, findsOneWidget);
          }
          if (size.width >= 700) expect(marks, findsOneWidget);
          // Only the elapsed/total row overflowing a narrow width at 2x text
          // (as it does without a mark) may be reported.
          for (
            Object? error = tester.takeException();
            error != null;
            error = tester.takeException()
          ) {
            final text = '$error';
            expect(
              scale == 2.0 &&
                  text.contains('overflowed') &&
                  text.contains('right'),
              isTrue,
              reason: text,
            );
          }
          await close(tester);
        });
      }
    }
  }

  testWidgets('side by side, the mark is sized from its own column', (
    tester,
  ) async {
    await pumpPlayer(tester, _timer(), size: const Size(1024, 600));
    final mark = tester.getRect(find.byType(PlayerMark));
    // Room above the title, not that less the controls: well over its floor.
    expect(mark.shortestSide, greaterThan(150));
    await close(tester);
  });

  testWidgets('the mark gives way when there is no room for it', (
    tester,
  ) async {
    await pumpPlayer(
      tester,
      _timer(),
      textScale: 2.0,
      size: const Size(360, 560),
    );
    tester.takeException();
    expect(find.byType(PlayerMark), findsNothing);
    await close(tester);
  });

  testWidgets('a recording shows its art as its figure, and no mark', (
    tester,
  ) async {
    final request = _request();
    await pumpPlayer(tester, request);
    expect(find.byType(PlayerMark), findsNothing);
    expect(find.byType(MeditejoMark), findsNothing);
    expect(findArt(singleArt(request.trackId)), findsOneWidget);
    await close(tester);
  });

  // One look for every player (owner, 14 Nov): the figure at the top, the
  // title under it, the controls at the bottom, over the same dark backdrop.
  for (final (name, request) in [
    ('timer', _timer()),
    ('recording', _request()),
  ]) {
    testWidgets('the $name player: figure, then title, then controls at the '
        'bottom', (tester) async {
      await pumpPlayer(tester, request, insets: true);
      final figure = request.isTimer
          ? tester.getRect(find.byType(PlayerMark))
          : tester.getRect(findArt(singleArt(request.trackId)));
      final title = tester.getRect(find.text(request.title));
      final slider = tester.getRect(find.byType(Slider));
      final bar = tester.getRect(find.byType(PlayerActionBar));
      expect(figure.shortestSide, greaterThan(150));
      // The title sits just under the figure: no large gap between them.
      expect(title.top - figure.bottom, inInclusiveRange(0, 24));
      expect(slider.top, greaterThan(title.bottom));
      // The controls end near the bar, not in the middle of the screen.
      final lowest = request.isTimer
          ? tester.getRect(find.byIcon(Icons.stop_rounded)).bottom
          : tester.getRect(find.byKey(const ValueKey('player_sleep'))).bottom;
      expect(bar.top - lowest, inInclusiveRange(0, 48));
      // No wallpaper: neither the cover nor the art fills the screen.
      expect(figure.width, lessThan(411));
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }

  testWidgets('a recording has a sleep timer; a timer has none', (
    tester,
  ) async {
    await pumpPlayer(tester, _timer());
    expect(find.byType(SleepTimerButton), findsNothing);
    await close(tester);
    await pumpPlayer(tester, _request());
    expect(find.byType(SleepTimerButton), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    await close(tester);
  });

  testWidgets('the sleep timer: choose, see it count down, turn it off', (
    tester,
  ) async {
    final engine = _SleepEngine();
    await pumpPlayer(
      tester,
      _request(),
      extra: [sleepTimerEngineProvider.overrideWithValue(engine)],
    );
    await tester.tap(find.byKey(const ValueKey('player_sleep')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    for (final label in [
      '5 min',
      '10 min',
      '15 min',
      '30 min',
      'End of track',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // Nothing set yet: no way to turn it off.
    expect(find.byKey(const ValueKey('sleep_off')), findsNothing);
    await tester.tap(find.text('10 min'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(engine.armed, [const Duration(minutes: 10)]);
    expect(find.text('10:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('9:58'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player_sleep')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('sleep_off')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(engine.cancels, 1);
    expect(find.text('Sleep'), findsOneWidget);
    await close(tester);
  });

  testWidgets('end of track shows on the button', (tester) async {
    await pumpPlayer(
      tester,
      _request(),
      extra: [sleepTimerEngineProvider.overrideWithValue(_SleepEngine())],
    );
    await tester.tap(find.byKey(const ValueKey('player_sleep')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('End of track'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('player_sleep')),
        matching: find.text('End of track'),
      ),
      findsOneWidget,
    );
    await close(tester);
  });

  test('the countdown covers the player from the start', () {
    // Expected, not yet begun natively: covered, showing the whole of it.
    expect(showCountdownCover(countdownMs: 0, countdownExpected: true), isTrue);
    expect(countdownCoverSeconds(countdownMs: 0, configuredSeconds: 10), 10);
    // Counting: the native seconds.
    expect(
      showCountdownCover(countdownMs: 4200, countdownExpected: false),
      isTrue,
    );
    expect(countdownCoverSeconds(countdownMs: 4200, configuredSeconds: 10), 5);
    // Done.
    expect(
      showCountdownCover(countdownMs: 0, countdownExpected: false),
      isFalse,
    );
  });

  test('sleep time left reads m:ss', () {
    expect(formatSleepRemaining(const Duration(minutes: 30)), '30:00');
    expect(formatSleepRemaining(const Duration(seconds: 61)), '1:01');
    expect(formatSleepRemaining(const Duration(milliseconds: 400)), '0:01');
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
    // 40 BPM: seven 1.5 s beats to a breath.
    expect(widget.breathSeconds, closeTo(10.5, 1e-9));
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
