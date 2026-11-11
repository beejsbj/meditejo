import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/home/home_provider.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/player/ios_audio_handler.dart';
import 'package:medito/providers/player/player_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/player/widgets/stopwatch_elapsed_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/soundscape_fakes.dart';

const _ioTimeout = Duration(seconds: 5);
const _settleTimeout = Duration(seconds: 3);

/// Only the operating system audio boundary is replaced. Home, timer, local
/// repositories, PlayerProvider, IosAudioHandler and its bell scheduler are real.
/// Desktop widget runners take PlayerProvider's non-Android engine path.
class _NativeAudio {
  final players = <String, _NativePlayer>{};
  int healthPermissionRequests = 0;
  final _channels = <MethodChannel>[];
  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void _handle(String name, Future<Object?> Function(MethodCall) handler) {
    final channel = MethodChannel(name);
    _channels.add(channel);
    _messenger.setMockMethodCallHandler(channel, handler);
  }

  void install(Directory directory) {
    _handle('plugins.flutter.io/path_provider', (_) async => directory.path);
    _handle('com.ryanheise.audio_session', (_) async => null);
    _handle('flutter_health', (call) async {
      if (call.method == 'requestAuthorization') healthPermissionRequests++;
      return false;
    });
    _handle('home_widget', (_) async => true);
    _handle('flutter.baseflow.com/permissions/methods', (_) async => 0);
    _handle('com.ryanheise.just_audio.methods', (call) async {
      if (call.method == 'init') {
        final id = (call.arguments as Map)['id'] as String;
        final player = players[id] = _NativePlayer(id);
        _handle('com.ryanheise.just_audio.events.$id', (_) async => null);
        _handle('com.ryanheise.just_audio.data.$id', (_) async => null);
        _handle('com.ryanheise.just_audio.methods.$id', (call) async {
          player.calls.add(call);
          if (call.method == 'load') {
            final source = (call.arguments as Map)['audioSource'];
            player.uri = Uri.parse(_sourceUris(source).single);
            // Neither primary playback nor the bell may load a remote URL.
            expect(player.uri!.scheme, 'file');
            player.duration = player.uri!.path.endsWith('session_bell_v2.wav')
                ? const Duration(seconds: 6)
                : const Duration(minutes: 3);
            position(player, Duration.zero);
            return {'duration': player.duration.inMicroseconds};
          }
          if (call.method == 'seek') {
            position(
              player,
              Duration(
                microseconds: (call.arguments as Map)['position'] as int? ?? 0,
              ),
            );
          }
          return <String, Object?>{};
        });
      }
      return <String, Object?>{};
    });
  }

  Iterable<String> _sourceUris(Object? source) sync* {
    if (source is Map) {
      if (source['uri'] case final String uri) yield uri;
      for (final child in source.values) {
        if (child is Map || child is List) yield* _sourceUris(child);
      }
    } else if (source is List) {
      for (final child in source) {
        yield* _sourceUris(child);
      }
    }
  }

  void position(_NativePlayer player, Duration position) {
    ServicesBinding.instance.channelBuffers.push(
      'com.ryanheise.just_audio.events.${player.id}',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'processingState': 3, // just_audio's ready state
        'updateTime': DateTime.now().millisecondsSinceEpoch,
        'updatePosition': position.inMicroseconds,
        'bufferedPosition': player.duration.inMicroseconds,
        'duration': player.duration.inMicroseconds,
        'currentIndex': 0,
      }),
      (_) {},
    );
  }

  void uninstall() {
    for (final channel in _channels) {
      _messenger.setMockMethodCallHandler(channel, null);
    }
  }
}

class _NativePlayer {
  _NativePlayer(this.id);

  final String id;
  Uri? uri;
  Duration duration = Duration.zero;
  final calls = <MethodCall>[];

  int count(String method) =>
      calls.where((call) => call.method == method).length;
}

/// File creation and bundled-asset extraction use real I/O. Give those tasks
/// event-loop turns, then pump widget work, without settling a playing timer.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  required String reason,
}) async {
  debugPrint('LOCAL_TIMER: $reason');
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: reason);
}

Future<void> _fileIO(
  WidgetTester tester,
  Future<void> Function() operation, {
  required String reason,
}) async {
  debugPrint('LOCAL_TIMER: $reason');
  // The timeout is created in the real event loop, not FakeAsync.
  await tester.runAsync(() => operation().timeout(_ioTimeout));
}

Future<ProviderContainer> _home(
  WidgetTester tester,
  SharedPreferences prefs, {
  bool ownAudioState = false,
  FakeSoundscapeEngine? sounds,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      // No catalogue, content, stats or playback provider fixtures.
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // The library is a separate database; Home's timer link needs none.
        continueItemsProvider.overrideWith((ref) async => []),
        // The app's audio state notifier is one global instance, which only
        // one container may own: a test that plays nothing (but whose
        // Customize sheet reads the Sounds mixer, which follows the audio
        // state) uses its own, leaving the global one to the playing test.
        if (ownAudioState)
          audioStateProvider.overrideWith(AudioStateNotifier.new),
        // The Sounds mixer, silent, for a test that follows what it plays.
        if (sounds != null) ...soundscapeTestOverrides(sounds),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Home's mark moves for as long as it is shown, so nothing would
        // settle: still it, as reduced motion does.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const HomeView(),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HomeView)),
  );
  // The singleton's serialized preferences queue can finish outside FakeAsync.
  // Give it real event-loop turns before settling loading animations.
  await _pumpUntil(
    tester,
    () =>
        container.read(statsProvider).hasValue &&
        container.read(fetchHomeProvider).hasValue,
    reason: 'Local history and the empty catalogue must finish loading',
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    _settleTimeout,
  );
  final catalogue = await container.read(fetchHomeProvider.future);
  expect(catalogue.shortcuts, isEmpty);
  expect(catalogue.carousel, isEmpty);
  expect(catalogue.todayQuote, isNull);
  return container;
}

Future<void> _openTimer(WidgetTester tester) async {
  final open = find.byKey(const ValueKey('shortcut_timer'));
  expect(open, findsOneWidget);
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    _settleTimeout,
  );
  // The Timer is the Customize sheet, over Home: not a page of its own.
  expect(find.byType(CustomizeSheet), findsOneWidget);
  expect(find.byType(HomeView), findsOneWidget);
  expect(find.byType(BottomSheet), findsOneWidget);
  expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
  expect(tester.getBottomLeft(find.text('Start')).dy, lessThan(844));
  // The timer's length is the sheet's dial, there as it opens.
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('customize_dial')),
      matching: find.byKey(_wheel),
    ),
    findsOneWidget,
  );
  expect(find.textContaining('Stopwatch'), findsNothing);
}

const _wheel = ValueKey('wheel_Duration');

/// Start on the Timer sheet, through to the player.
Future<void> _start(WidgetTester tester) async {
  final start = find.widgetWithText(FilledButton, 'Start');
  await tester.ensureVisible(start);
  await tester.tap(start);
  await _pumpUntil(
    tester,
    () => find.byType(PlayerView).evaluate().isNotEmpty,
    reason: 'Start must navigate to the real player after creating audio',
  );
}

/// Runs [body] with the native audio boundary faked and a temporary
/// directory for the timer's silent file, then stops the audio handler
/// before removing the fakes.
Future<void> _withNativeAudio(
  WidgetTester tester,
  Future<void> Function(_NativeAudio native, Directory directory) body,
) async {
  final semantics = tester.ensureSemantics();
  final directory = (await tester.runAsync(
    () => Directory.systemTemp
        .createTemp('local_home_timer_')
        .timeout(_ioTimeout),
  ))!;
  final native = _NativeAudio()..install(directory);
  addTearDown(native.uninstall);
  addTearDown(() => directory.delete(recursive: true).timeout(_ioTimeout));
  iosAudioHandler = IosAudioHandler();

  try {
    await body(native, directory);
  } finally {
    // Stop before removing channel handlers so position timers and pending
    // bell work cannot leak into subsequent tests. Plugin shutdown also
    // cancels event streams: pump those callbacks instead of awaiting a
    // future whose continuations may still be queued in FakeAsync.
    var stopped = false;
    Object? stopError;
    StackTrace? stopTrace;
    // Pause changes just_audio's playing state synchronously, cancelling
    // its position timer even if native disposal then fails.
    await iosAudioHandler.pause();
    iosAudioHandler.stop().then<void>(
      (_) => stopped = true,
      onError: (Object error, StackTrace trace) {
        stopError = error;
        stopTrace = trace;
        stopped = true;
      },
    );
    try {
      await _pumpUntil(
        tester,
        () => stopped,
        reason: 'The audio handler must finish stopping native players',
      );
      if (stopError != null) {
        Error.throwWithStackTrace(stopError!, stopTrace!);
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      semantics.dispose();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    // The same preferences are supplied to Riverpod and plugin consumers.
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    StatsManager().resetForTesting();
  });

  tearDown(() => StatsManager().resetForTesting());

  testWidgets('an empty local catalogue still exposes the home timer', (
    tester,
  ) async {
    final container = await _home(tester, prefs, ownAudioState: true);
    expect(container.read(playerProvider), isNull);

    await _openTimer(tester);

    expect(container.read(timerSettingsProvider).minutes, 10);
    expect(container.read(playerProvider), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home timer Customize duration starts a local silent track', (
    tester,
  ) async {
    await _withNativeAudio(tester, (native, directory) async {
      final container = await _home(tester, prefs);
      await _openTimer(tester);

      // Turn the dial to 3 minutes (∞ is its first place, then 1 min).
      tester.state<WheelPickerState<int>>(find.byKey(_wheel)).moveTo(3);
      await tester.pumpAndSettle();
      expect(
        container
            .read(cueSettingsProvider(const CueScope(CueKind.practice)))
            .durationMinutes,
        3,
      );
      await _start(tester);

      final request = container.read(playerProvider)!;
      expect(
        native.healthPermissionRequests,
        0,
        reason: 'Starting a timer must never ask for Health permission',
      );
      expect(request.trackId, 'timer-180');
      expect(request.fileId, 'timer-countdown-180000');
      expect(request.duration, 180000);
      expect(request.title, 'Timer');
      expect(request.coverUrl, isEmpty);
      expect(request.hasBackgroundSound, isTrue);
      final uri = Uri.parse(request.remoteUrl);
      expect(uri.scheme, 'file');
      expect(uri.toFilePath(), startsWith(directory.path));

      await _fileIO(tester, () async {
        final file = File.fromUri(uri);
        expect(await file.exists(), isTrue);
        expect(await file.length(), 44 + 180 * 8000 * 2);
        final reader = await file.open();
        try {
          final header = await reader.read(44);
          expect(String.fromCharCodes(header.take(4)), 'RIFF');
          expect(String.fromCharCodes(header.sublist(8, 12)), 'WAVE');
          // Sample the sparse PCM body, not only its file extension/header.
          expect(await reader.read(64), everyElement(0));
          await reader.setPosition(44 + 90 * 8000 * 2);
          expect(await reader.read(64), everyElement(0));
        } finally {
          await reader.close();
        }
      }, reason: 'Verify the generated silent WAV');

      await _pumpUntil(
        tester,
        () => native.players.values.any(
          (player) => player.uri == uri && player.count('play') > 0,
        ),
        reason: 'The primary player must start the generated local silence',
      );
      final primary = native.players.values.singleWhere(
        (player) => player.uri == uri,
      );
      expect(primary.count('play'), 1);
      expect(iosAudioHandler.playing, isTrue);
      // Cue execution now lives in the native channel, covered by the
      // scheduling maths tests, rather than a second just_audio player.
      final cues = container.read(
        cueSettingsProvider(const CueScope(CueKind.practice)),
      );
      expect(cues.startSound, kSessionBellAsset);
      expect(cues.endSound, kSessionBellAsset);
      expect(iosAudioHandler.sessionBells.enabled, isFalse);
      expect(primary.count('seek'), 0);
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('∞ on the dial starts an open-ended timer, which counts up', (
    tester,
  ) async {
    await _withNativeAudio(tester, (native, directory) async {
      final container = await _home(
        tester,
        prefs,
        sounds: FakeSoundscapeEngine(),
        ownAudioState: true,
      );
      await _openTimer(tester);
      await tester.tap(find.byKey(const ValueKey('customize_infinity')));
      await tester.pumpAndSettle();
      expect(
        tester.state<WheelPickerState<int>>(find.byKey(_wheel)).selectedIndex,
        0,
      );
      await _start(tester);

      // The stopwatch engine underneath: its file id, and the longest file.
      final request = container.read(playerProvider)!;
      expect(request.isTimer, isTrue);
      expect(request.timerMode, TimerMode.stopwatch);
      expect(request.fileId, 'timer-stopwatch-0');
      expect(request.duration, kStopwatchMaxDuration.inMilliseconds);
      // It is a Timer by name, and the player counts up.
      expect(request.title, 'Timer');
      expect(find.byType(StopwatchElapsedWidget), findsOneWidget);
      // The sheet has gone: the player is over Home, not over the sheet.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.byType(CustomizeSheet), findsNothing);
      expect(find.textContaining('Stopwatch'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('a link to the stopwatch opens the Timer sheet on ∞ and starts '
      'open-ended', (tester) async {
    await _withNativeAudio(tester, (native, directory) async {
      final container = await _home(
        tester,
        prefs,
        sounds: FakeSoundscapeEngine(),
        ownAudioState: true,
      );
      // It completes when the sheet closes.
      unawaited(
        handleNavigation(TypeConstants.route, [
          RouteConstants.stopwatch,
        ], tester.element(find.byType(HomeView))),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        _settleTimeout,
      );
      expect(find.byType(CustomizeSheet), findsOneWidget);
      expect(
        tester.state<WheelPickerState<int>>(find.byKey(_wheel)).selectedIndex,
        0,
        reason: 'resting on ∞',
      );
      await _start(tester);
      final request = container.read(playerProvider)!;
      expect(request.timerMode, TimerMode.stopwatch);
      expect(request.fileId, 'timer-stopwatch-0');
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('the timer link opens the same sheet, on the length', (
    tester,
  ) async {
    await _home(tester, prefs, ownAudioState: true);
    unawaited(
      handleNavigation(TypeConstants.route, [
        RouteConstants.timer,
      ], tester.element(find.byType(HomeView))),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      _settleTimeout,
    );
    expect(find.byType(CustomizeSheet), findsOneWidget);
    expect(
      tester.state<WheelPickerState<int>>(find.byKey(_wheel)).selectedIndex,
      10,
    );
    expect(find.textContaining('Finishes at'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a timer left on the stopwatch still starts open-ended from a '
      'preset tile, and Home calls it open-ended', (tester) async {
    await _withNativeAudio(tester, (native, directory) async {
      final container = await _home(
        tester,
        prefs,
        sounds: FakeSoundscapeEngine(),
        ownAudioState: true,
      );
      // As the old Timer page's Stopwatch tab set it.
      container
          .read(timerSettingsProvider.notifier)
          .setMode(TimerMode.stopwatch);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        _settleTimeout,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shortcut_timer')),
          matching: find.text('Open-ended'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Stopwatch'), findsNothing);

      // A sound-only preset has no length of its own: the Timer's stands.
      final preset = kStarterPresets[1];
      final tile = find.byKey(ValueKey('pinned_preset_${preset.id}'));
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await _pumpUntil(
        tester,
        () => find.byType(PlayerView).evaluate().isNotEmpty,
        reason: 'The preset tile must open the player at once',
      );
      final request = container.read(playerProvider)!;
      expect(request.timerMode, TimerMode.stopwatch);
      expect(request.fileId, 'timer-stopwatch-0');
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('a pinned sound-only preset starts the Timer at its current '
      'length with that sound under it', (tester) async {
    await _withNativeAudio(tester, (native, directory) async {
      final sounds = FakeSoundscapeEngine();
      // Its own audio state: the global one belongs to the test above.
      final container = await _home(
        tester,
        prefs,
        sounds: sounds,
        ownAudioState: true,
      );
      // Not the first built-in: that is also Practice's default mix.
      final preset = kStarterPresets[1];
      final tile = find.byKey(ValueKey('pinned_preset_${preset.id}'));
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await _pumpUntil(
        tester,
        () => find.byType(PlayerView).evaluate().isNotEmpty,
        reason: 'The preset tile must open the player at once',
      );

      final request = container.read(playerProvider)!;
      expect(request.isTimer, isTrue);
      expect(request.trackId, 'timer-600');

      await _pumpUntil(
        tester,
        () => native.players.values.any((p) => p.count('play') > 0),
        reason: 'The timer must start playing',
      );
      await _pumpUntil(
        tester,
        () => container.read(soundscapeProvider).underSession,
        reason: 'The preset must play under the timer session',
      );
      final mixer = container.read(soundscapeProvider);
      expect(mixer.sessionKind, SoundscapeSessionKind.practice);
      expect(mixer.mix, preset.mix);
      expect(
        sounds.playing.keys,
        containsAll([for (final layer in preset.mix.layers) layer.soundId]),
      );

      // A tile is the preset picked on the Timer, then Start: the Timer
      // (and so practice, whose settings it shares) keeps the sound, and
      // names the preset it came from.
      const practice = CueScope(CueKind.practice);
      expect(container.read(cueSettingsProvider(practice)).soundscape, '');
      final kept = container
          .read(soundscapeProvider.notifier)
          .sessionDefault(SoundscapeSessionKind.practice);
      expect(kept.enabled, isTrue);
      expect(kept.selection, SoundscapeSelection.preset(preset.id));
      expect(
        container
            .read(loadedPresetProvider(const PresetContext.timer()))
            ?.preset
            .id,
        preset.id,
      );
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 45)));
}
