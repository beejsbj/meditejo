import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/review_service_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/review_service.dart';
import 'package:medito/src/audio_pigeon.g.dart' hide Track;
import 'package:medito/src/audio_pigeon.g.dart' as pigeon show Track;
import 'package:medito/views/end_screen/end_screen_view.dart';
import 'package:medito/views/home/previews/stats_fixtures.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/bg_sound_widget.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

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
  _SilentBackgroundSounds({this.legacyBells = false});

  /// The legacy Home-sheet bells switch, which the cues must ignore.
  final bool legacyBells;

  @override
  BackgroundSoundsState build() =>
      BackgroundSoundsState(bellsEnabled: legacyBells);

  @override
  void applyCueSettings(CueSettings settings) {}

  @override
  void stopBackgroundSound() {}

  SoundscapeSessionKind? _kind;
  SoundscapeSelection? _selection;

  /// Each soundscape start: its kind and the scope's Customize choice.
  final starts = <(SoundscapeSessionKind?, SoundscapeSelection?)>[];

  @override
  void setSessionKind(
    SoundscapeSessionKind kind, {
    SoundscapeSelection? selection,
  }) {
    _kind = kind;
    _selection = selection;
  }

  @override
  void playBackgroundSoundFromPref() => starts.add((_kind, _selection));
}

/// The real soundscape wiring (setSessionKind, playBackgroundSoundFromPref)
/// with the legacy native layers left out.
class _MixerBackgroundSounds extends BackgroundSoundsNotifier {
  @override
  BackgroundSoundsState build() => const BackgroundSoundsState();

  @override
  void applyCueSettings(CueSettings settings) {}

  @override
  void stopBackgroundSound() =>
      ref.read(soundscapeProvider.notifier).endSession();
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
  bool legacyBells = false,
  BackgroundSoundsNotifier? sounds,
  List<dynamic> overrides = const [],
  Widget child = const PlayerView(skipCustomize: true),
}) => PreviewShell(
  prefs: prefs,
  overrides: [
    playerProvider.overrideWith(() => player),
    audioStateProvider.overrideWith(AudioStateNotifier.new),
    backgroundSoundsNotifierProvider.overrideWith(
      () => sounds ?? _SilentBackgroundSounds(legacyBells: legacyBells),
    ),
    statsProvider.overrideWith(_Stats.new),
    reviewServiceProvider.overrideWithValue(_Review()),
    if (bell != null) sessionBellPreviewProvider.overrideWithValue(bell),
    ...overrides,
  ],
  child: child,
);

const _first = PlaybackRequest(
  trackId: 'fake-a',
  fileId: 'a-file',
  title: 'Session A',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://example.test/a.mp3',
  duration: 60000,
  hasBackgroundSound: false,
);

const _nextTrack = Track(
  id: 'fake-b',
  title: 'Session B',
  description: '',
  coverUrl: '',
  isPublished: true,
  hasBackgroundSound: false,
  voices: [
    TrackVoice(
      audioFiles: [
        TrackAudioFile(
          id: 'b-file',
          path: 'https://example.test/b.mp3',
          duration: 60000,
        ),
      ],
    ),
  ],
);

/// A two-session course.
class _Course implements ContentSource {
  @override
  String get prefix => 'fake-';

  @override
  Future<PackModel> pack(String id) async => const PackModel(
    id: 'fake-course',
    title: 'Course',
    items: [
      PackItemsModel(
        type: TypeConstants.track,
        id: 'fake-a',
        title: 'Session A',
        path: '',
      ),
      PackItemsModel(
        type: TypeConstants.track,
        id: 'fake-b',
        title: 'Session B',
        path: '',
      ),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NextTrack extends Tracks {
  @override
  Future<Track> build({required String trackId}) async => _nextTrack;
}

final _courseOverrides = [
  cueScopeForRequestProvider.overrideWith(
    (ref, request) async =>
        const CueScope(CueKind.practice, courseId: 'fake-course'),
  ),
  contentSourcesProvider.overrideWithValue([_Course()]),
  tracksProvider(trackId: 'fake-b').overrideWith(_NextTrack.new),
];

const _autoplay = CueSettings(autoplay: true, interludeSeconds: 5);

void _setLifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

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
    bool legacyBells = false,
  }) async {
    final player = _FakePlayer(_timer);
    await tester.pumpWidget(
      _player(
        player: player,
        prefs: _prefsWith(practice),
        bell: bell,
        legacyBells: legacyBells,
      ),
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

  testWidgets("the session's soundscape follows its scope's Customize choice", (
    tester,
  ) async {
    final sounds = _SilentBackgroundSounds();
    await tester.pumpWidget(
      _player(
        player: _FakePlayer(_timer),
        prefs: _prefsWith(
          const CueSettings(soundscape: 'preset:starter-night'),
        ),
        sounds: sounds,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(sounds.starts, [
      (
        SoundscapeSessionKind.practice,
        const SoundscapeSelection.preset('starter-night'),
      ),
    ]);

    // A new choice mid-session plays at once; other edits do not restart.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerView)),
    );
    const scope = CueScope(CueKind.practice);
    final notifier = container.read(cueSettingsProvider(scope).notifier);
    await notifier.update(
      container.read(cueSettingsProvider(scope)).copyWith(soundscape: 'none'),
    );
    await tester.pump();
    await notifier.update(
      container.read(cueSettingsProvider(scope)).copyWith(bellVolume: 0.1),
    );
    await tester.pump();
    expect(sounds.starts.length, 2);
    expect(sounds.starts.last.$2, SoundscapeSelection.none);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'ending a timer early rings the Customize end cue at the bell volume',
    (tester) async {
      final bell = _Bell();
      // The legacy bells switch is off: the old path would ring nothing.
      await endTimerEarly(
        tester,
        practice: const CueSettings(bellVolume: 0.8),
        bell: bell,
      );
      // Bowl is the only end sound besides Off; the volume is Customize's.
      expect(bell.rung, [(0.8, kSessionBellAsset)]);
    },
  );

  testWidgets(
    'the legacy bells switch cannot ring an end cue Customize turned off',
    (tester) async {
      final bell = _Bell();
      await endTimerEarly(
        tester,
        practice: const CueSettings(endSound: ''),
        bell: bell,
        legacyBells: true,
      );
      expect(bell.rung, isEmpty);
    },
  );

  testWidgets('autoplay starts the next session while the screen is locked', (
    tester,
  ) async {
    addTearDown(
      () => _setLifecycle(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]),
    );
    final player = _FakePlayer(_first);
    await tester.pumpWidget(
      _player(
        player: player,
        prefs: _prefsWith(_autoplay),
        overrides: _courseOverrides,
      ),
    );
    await tester.pump();
    await tester.pump();
    final audio = ProviderScope.containerOf(
      tester.element(find.byType(PlayerView)),
    ).read(audioStateProvider.notifier);
    audio.updatePlaybackState(
      _state(
        completed: false,
        positionMs: 1000,
        durationMs: 60000,
        playing: true,
      ),
    );
    await tester.pump();
    expect(player.played, [_first]);

    // The screen locks: Flutter builds no more frames.
    _setLifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(tester.binding.framesEnabled, isFalse);

    audio.updatePlaybackState(
      _state(completed: true, positionMs: 60000, durationMs: 60000),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(player.played, hasLength(1), reason: 'the interlude is 5 s');
    await tester.pump(const Duration(seconds: 2));
    expect(player.played.map((r) => r.trackId), ['fake-a', 'fake-b']);

    // Unlocking shows the next session on the same screen.
    _setLifecycle(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Session B'), findsWidgets);
    expect(find.byType(EndScreenView), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the real mixer carries across autoplay and ends with the '
      'course, and the sound button follows it', (tester) async {
    final engine = FakeSoundscapeEngine();
    final player = _FakePlayer(_first);
    await tester.pumpWidget(
      _player(
        player: player,
        prefs: _prefsWith(_autoplay),
        sounds: _MixerBackgroundSounds(),
        overrides: [..._courseOverrides, ...soundscapeTestOverrides(engine)],
      ),
    );
    await tester.pump();
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerView)),
    );
    final audio = container.read(audioStateProvider.notifier);
    SoundscapeState mixer() => container.read(soundscapeProvider);
    bool button() => tester
        .widget<BgSoundWidget>(find.byType(BgSoundWidget))
        .isBackgroundSoundSelected;

    Future<void> playing(int positionMs) async {
      audio.updatePlaybackState(
        _state(
          completed: false,
          positionMs: positionMs,
          durationMs: 60000,
          playing: true,
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // Practice plays the current mix under the session.
    await playing(1000);
    expect(mixer().underSession, isTrue);
    expect(mixer().playing, isTrue);
    expect(engine.playing, isNotEmpty);
    expect(button(), isTrue, reason: 'the button shows the mixer playing');

    // The voice ends: the mixer pauses (fading) through the interlude, but
    // the session goes on.
    audio.updatePlaybackState(
      _state(completed: true, positionMs: 60000, durationMs: 60000),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(mixer().inSession, isTrue);
    expect(mixer().playing, isFalse);
    expect(engine.paused, isTrue);
    expect(button(), isFalse);

    // The next session starts on the same screen; the mix resumes.
    await tester.pump(const Duration(seconds: 5));
    expect(player.played.map((r) => r.trackId), ['fake-a', 'fake-b']);
    await playing(1000);
    expect(mixer().underSession, isTrue);
    expect(mixer().playing, isTrue);
    expect(engine.paused, isFalse);
    expect(engine.playing, isNotEmpty);

    // The last session ends naturally: the end screen opens and the mixer's
    // session ends with it.
    audio.updatePlaybackState(
      _state(completed: true, positionMs: 60000, durationMs: 60000),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(EndScreenView), findsOneWidget);
    expect(mixer().inSession, isFalse);
    expect(mixer().active, isFalse);
    expect(engine.playing, isEmpty);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('going back during the interlude does not start the next '
      'session', (tester) async {
    final player = _FakePlayer(_first);
    await tester.pumpWidget(
      _player(
        player: player,
        prefs: _prefsWith(_autoplay),
        overrides: _courseOverrides,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PlayerView(skipCustomize: true),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final audio = ProviderScope.containerOf(
      tester.element(find.byType(PlayerView)),
    ).read(audioStateProvider.notifier);
    audio.updatePlaybackState(
      _state(
        completed: false,
        positionMs: 1000,
        durationMs: 60000,
        playing: true,
      ),
    );
    await tester.pump();
    audio.updatePlaybackState(
      _state(completed: true, positionMs: 60000, durationMs: 60000),
    );
    await tester.pump(const Duration(seconds: 1));

    // Back, with the interlude still running.
    Navigator.of(tester.element(find.byType(PlayerView))).pop();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(
      player.played,
      hasLength(1),
      reason: 'the next session must not start',
    );
  });

  testWidgets('autoplay after the last session of a course opens the end '
      'screen', (tester) async {
    final last = _first.copyWith(trackId: 'fake-b', title: 'Session B');
    final player = _FakePlayer(last);
    await tester.pumpWidget(
      _player(
        player: player,
        prefs: _prefsWith(_autoplay),
        overrides: _courseOverrides,
      ),
    );
    await tester.pump();
    await tester.pump();
    final audio = ProviderScope.containerOf(
      tester.element(find.byType(PlayerView)),
    ).read(audioStateProvider.notifier);
    audio.updatePlaybackState(
      _state(completed: false, positionMs: 1000, durationMs: 60000),
    );
    await tester.pump();
    audio.updatePlaybackState(
      _state(completed: true, positionMs: 60000, durationMs: 60000),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(EndScreenView), findsOneWidget);
    expect(player.played, [last]);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

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
