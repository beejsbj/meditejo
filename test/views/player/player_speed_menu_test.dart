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
import 'package:medito/providers/player/playback_speed_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/review_service_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/review_service.dart';
import 'package:medito/src/audio_pigeon.g.dart' as pigeon;
import 'package:medito/views/home/previews/stats_fixtures.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/audio_speed_widget.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/speed_sheet.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Nothing playing yet, at [speed] as the engine reports it.
class _IdleAudio extends AudioStateNotifier {
  _IdleAudio([this.speed = 1]);

  final double speed;

  @override
  pigeon.PlaybackState build() => pigeon.PlaybackState(
    isPlaying: false,
    isBuffering: false,
    isSeeking: false,
    isCompleted: false,
    position: 0,
    duration: 3600000,
    speed: pigeon.Speed(speed: speed),
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

/// Records what reaches the engine.
class _FakePlayer extends PlayerProvider {
  _FakePlayer(this.request, this.speeds);

  final PlaybackRequest request;
  final List<double> speeds;

  @override
  PlaybackRequest? build() => request;

  @override
  Future<void> play(PlaybackRequest request) => Completer<void>().future;

  @override
  void stop() {}

  @override
  void setSpeed(double speed) => speeds.add(speed);
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

  late List<double> speeds;

  /// Set to make the session's kind lookup fail from then on.
  var scopeFails = false;

  Future<void> pumpPlayer(
    WidgetTester tester,
    PlaybackRequest request,
    CueKind kind, {
    Map<String, Object> prefs = const {},
    double liveSpeed = 1,
  }) async {
    speeds = [];
    scopeFails = false;
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PreviewShell(
        prefs: {...prefsDark, ...prefs},
        overrides: [
          playerProvider.overrideWith(() => _FakePlayer(request, speeds)),
          audioStateProvider.overrideWith(() => _IdleAudio(liveSpeed)),
          backgroundSoundsNotifierProvider.overrideWith(
            _SilentBackgroundSounds.new,
          ),
          statsProvider.overrideWith(_Stats.new),
          reviewServiceProvider.overrideWithValue(_Review()),
          cueScopeForRequestProvider.overrideWith(
            (ref, request) async =>
                scopeFails ? throw StateError('no library') : CueScope(kind),
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

  /// The player keeps animating, so it never settles: pump past the sheet's
  /// own animation instead.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(AudioSpeedWidget));
    await settle(tester);
    expect(find.byType(SpeedSheet), findsOneWidget);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PlayerView)));

  Finder tab(CueKind kind) => find.byKey(ValueKey('speed_kind_${kind.name}'));
  Finder option(String label) => find.byKey(ValueKey('speed_option_$label'));

  bool isSelected(WidgetTester tester, Finder finder) =>
      isSemantics(isSelected: true).matches(tester.getSemantics(finder), {});

  testWidgets('during a talk the menu opens on Talks, listed first', (
    tester,
  ) async {
    await pumpPlayer(tester, _talk, CueKind.talks);
    await openMenu(tester);
    final talks = tester.getTopLeft(tab(CueKind.talks));
    final practice = tester.getTopLeft(tab(CueKind.practice));
    expect(talks.dx, lessThan(practice.dx));
    expect(isSelected(tester, tab(CueKind.talks)), isTrue);
    expect(isSelected(tester, tab(CueKind.practice)), isFalse);
    await close(tester);
  });

  testWidgets('during a sit the menu opens on Practice, listed first', (
    tester,
  ) async {
    await pumpPlayer(tester, _talk, CueKind.practice);
    await openMenu(tester);
    final talks = tester.getTopLeft(tab(CueKind.talks));
    final practice = tester.getTopLeft(tab(CueKind.practice));
    expect(practice.dx, lessThan(talks.dx));
    expect(isSelected(tester, tab(CueKind.practice)), isTrue);
    await close(tester);
  });

  testWidgets('changing speed during a talk changes talks only', (
    tester,
  ) async {
    await pumpPlayer(tester, _talk, CueKind.talks);
    await openMenu(tester);
    await tester.tap(option('1.5×'));
    await settle(tester);
    expect(speeds, [1.5], reason: 'the talk speeds up now');
    final container = containerOf(tester);
    expect(container.read(playbackSpeedProvider(CueKind.talks)), 1.5);
    expect(container.read(playbackSpeedProvider(CueKind.practice)), 1.0);
    expect(
      container.read(sharedPreferencesProvider).getDouble('speed.v1.talks'),
      1.5,
    );
    expect(find.text('1.5×'), findsWidgets);
    await close(tester);
  });

  testWidgets('the other kind can be set without touching this session', (
    tester,
  ) async {
    await pumpPlayer(tester, _talk, CueKind.talks);
    await openMenu(tester);
    await tester.tap(tab(CueKind.practice));
    await settle(tester);
    expect(isSelected(tester, tab(CueKind.practice)), isTrue);
    await tester.tap(option('0.75×'));
    await settle(tester);
    expect(speeds, isEmpty, reason: 'the talk keeps playing as it was');
    final container = containerOf(tester);
    expect(container.read(playbackSpeedProvider(CueKind.practice)), 0.75);
    expect(container.read(playbackSpeedProvider(CueKind.talks)), 1.0);
    // The Practice tab shows its new speed.
    expect(
      find.descendant(of: tab(CueKind.practice), matching: find.text('0.75×')),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('the menu shows the other kind\'s stored speed', (tester) async {
    await pumpPlayer(
      tester,
      _talk,
      CueKind.talks,
      prefs: {'speed.v1.talks': 1.75, 'speed.v1.practice': 0.9},
      liveSpeed: 1.75,
    );
    await openMenu(tester);
    expect(
      find.descendant(of: tab(CueKind.talks), matching: find.text('1.75×')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tab(CueKind.practice), matching: find.text('0.9×')),
      findsOneWidget,
    );
    expect(isSelected(tester, option('1.75×')), isTrue);
    await tester.tap(option('1×'));
    await settle(tester);
    expect(speeds, [1.0]);
    final container = containerOf(tester);
    expect(container.read(playbackSpeedProvider(CueKind.talks)), 1.0);
    expect(container.read(playbackSpeedProvider(CueKind.practice)), 0.9);
    await close(tester);
  });

  testWidgets('the session tab shows the live speed, and its stored speed '
      'still applies', (tester) async {
    // A lock screen set 1.5×; talks are stored at 1×.
    await pumpPlayer(tester, _talk, CueKind.talks, liveSpeed: 1.5);
    await openMenu(tester);
    expect(
      find.descendant(of: tab(CueKind.talks), matching: find.text('1.5×')),
      findsOneWidget,
    );
    expect(isSelected(tester, option('1.5×')), isTrue);
    expect(isSelected(tester, option('1×')), isFalse);
    await tester.tap(option('1×'));
    await settle(tester);
    expect(speeds, [1.0], reason: 'back to the stored speed');
    expect(isSelected(tester, option('1×')), isTrue);
    expect(containerOf(tester).read(playbackSpeedProvider(CueKind.talks)), 1.0);
    await close(tester);
  });

  testWidgets('the menu closes when autoplay moves to the next session', (
    tester,
  ) async {
    await pumpPlayer(tester, _talk, CueKind.talks);
    await openMenu(tester);
    containerOf(tester)
        .read(playerProvider.notifier)
        .prepare(_talk.copyWith(trackId: 'ds-sit-3', fileId: 'ds-sit-3'));
    await settle(tester);
    expect(find.byType(SpeedSheet), findsNothing);
    await close(tester);
  });

  testWidgets('a double tap opens one menu', (tester) async {
    await pumpPlayer(tester, _talk, CueKind.talks);
    await tester.tap(find.byType(AudioSpeedWidget));
    await tester.tap(find.byType(AudioSpeedWidget));
    await settle(tester);
    expect(find.byType(SpeedSheet), findsOneWidget);
    await close(tester);
  });

  testWidgets('if the kind cannot be told the menu still opens', (
    tester,
  ) async {
    await pumpPlayer(tester, _talk, CueKind.talks);
    scopeFails = true;
    containerOf(tester).invalidate(cueScopeForRequestProvider);
    await openMenu(tester);
    // Both kinds, Practice first, and the playing session is left alone.
    expect(
      tester.getTopLeft(tab(CueKind.practice)).dx,
      lessThan(tester.getTopLeft(tab(CueKind.talks)).dx),
    );
    await tester.tap(option('1.25×'));
    await settle(tester);
    expect(speeds, isEmpty);
    expect(
      containerOf(tester).read(playbackSpeedProvider(CueKind.practice)),
      1.25,
    );
    await close(tester);
  });

  testWidgets('every speed button is at least 48 dp', (tester) async {
    await pumpPlayer(tester, _talk, CueKind.talks);
    await openMenu(tester);
    for (final speed in playbackSpeedOptions) {
      final size = tester.getSize(option(formatSpeed(speed)));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }
    for (final kind in CueKind.values) {
      expect(tester.getSize(tab(kind)).height, greaterThanOrEqualTo(48));
    }
    await close(tester);
  });

  testWidgets('a timer has no speed control', (tester) async {
    await pumpPlayer(tester, _timer, CueKind.practice);
    expect(find.byType(PlayerView), findsOneWidget);
    expect(find.byType(AudioSpeedWidget), findsNothing);
    await close(tester);
  });
}
