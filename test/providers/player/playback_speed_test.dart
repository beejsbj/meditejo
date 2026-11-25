import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/player/playback_speed_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/speed_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([
  Map<String, Object> prefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the offered speeds run from 0.6× to 2× and include 1×', () {
    expect(playbackSpeedOptions.first, 0.6);
    expect(playbackSpeedOptions.last, 2.0);
    expect(playbackSpeedOptions, containsAll([1.0, 1.25, 1.5, 1.75]));
    expect(
      playbackSpeedOptions,
      orderedEquals([...playbackSpeedOptions]..sort()),
    );
  });

  test('labels drop trailing zeros', () {
    expect(formatSpeed(1.0), '1×');
    expect(formatSpeed(0.75), '0.75×');
    expect(formatSpeed(1.5), '1.5×');
    expect(formatSpeed(2.0), '2×');
    expect(formatSpeed(0.6), '0.6×');
  });

  group('migration from the transient speed', () {
    test('nothing stored: both kinds start at 1×', () async {
      final container = await _container();
      expect(container.read(playbackSpeedProvider(CueKind.practice)), 1.0);
      expect(container.read(playbackSpeedProvider(CueKind.talks)), 1.0);
    });

    test('existing cue settings carry no speed and change nothing', () async {
      final container = await _container({
        'cues.v1.talks': '{"version":1,"autoplay":true}',
        'cues.v1.practice': '{"version":1,"countdownSeconds":10}',
      });
      expect(container.read(playbackSpeedProvider(CueKind.talks)), 1.0);
      expect(container.read(playbackSpeedProvider(CueKind.practice)), 1.0);
    });

    test(
      'a bad stored value reads as 1×, a near one snaps to a stop',
      () async {
        expect(normalisePlaybackSpeed('fast'), 1.0);
        expect(normalisePlaybackSpeed(double.nan), 1.0);
        expect(normalisePlaybackSpeed(double.infinity), 1.0);
        expect(normalisePlaybackSpeed(4.0), 1.0);
        expect(normalisePlaybackSpeed(0.1), 1.0);
        expect(normalisePlaybackSpeed(1.49), 1.5);
        expect(normalisePlaybackSpeed(0.7), 0.75);
        expect(normalisePlaybackSpeed(2), 2.0);
        final container = await _container({'speed.v1.talks': 'oops'});
        expect(container.read(playbackSpeedProvider(CueKind.talks)), 1.0);
      },
    );
  });

  test('each kind keeps its own speed, and it persists', () async {
    final container = await _container();
    await container
        .read(playbackSpeedProvider(CueKind.talks).notifier)
        .set(1.5);
    expect(container.read(playbackSpeedProvider(CueKind.talks)), 1.5);
    expect(container.read(playbackSpeedProvider(CueKind.practice)), 1.0);

    await container
        .read(playbackSpeedProvider(CueKind.practice).notifier)
        .set(0.75);
    expect(container.read(playbackSpeedProvider(CueKind.talks)), 1.5);

    // A fresh read (the next launch) sees both.
    final prefs = container.read(sharedPreferencesProvider);
    final store = PlaybackSpeedStore(prefs);
    expect(store.read(CueKind.talks), 1.5);
    expect(store.read(CueKind.practice), 0.75);
    expect(prefs.getDouble('speed.v1.talks'), 1.5);
    // The cue settings are untouched: speed is not part of them.
    expect(prefs.containsKey('cues.v1.talks'), isFalse);
  });

  test('a session starts at its kind\'s speed; a timer at 1×', () {
    double speedOf(CueKind kind) => kind == CueKind.talks ? 1.75 : 0.9;
    expect(
      sessionPlaybackSpeed(speedOf, kind: CueKind.talks, isTimer: false),
      1.75,
    );
    expect(
      sessionPlaybackSpeed(speedOf, kind: CueKind.practice, isTimer: false),
      0.9,
    );
    expect(
      sessionPlaybackSpeed(speedOf, kind: CueKind.practice, isTimer: true),
      1.0,
    );
  });

  test('the course scope does not change a kind\'s speed', () async {
    // Speed is kept per kind only: a course override of the cue settings
    // carries none of its own.
    final container = await _container();
    await container
        .read(playbackSpeedProvider(CueKind.talks).notifier)
        .set(1.25);
    await container
        .read(
          cueSettingsProvider(
            const CueScope(CueKind.talks, courseId: 'ds-retreat-4496'),
          ).notifier,
        )
        .update(const CueSettings(autoplay: true), courseOverride: true);
    expect(container.read(playbackSpeedProvider(CueKind.talks)), 1.25);
  });

  group('time at 2×', () {
    final now = DateTime(2026, 11, 5, 9);

    test('"Finishes at" halves the recording\'s remaining time', () {
      final end = customizeFinishesAt(
        now,
        const CueSettings(),
        isTimer: false,
        audioDurationMs: 60 * 60 * 1000,
        positionMs: 20 * 60 * 1000,
        isActive: true,
        speed: 2,
      );
      expect(end, now.add(const Duration(minutes: 20)));
    });

    test('before the start it adds the countdown and the silence', () {
      final end = customizeFinishesAt(
        now,
        const CueSettings(countdownSeconds: 10, extendMinutes: 5),
        isTimer: false,
        audioDurationMs: 60 * 60 * 1000,
        positionMs: 0,
        speed: 2,
      );
      // 10 s countdown, 30 min of a 60 min talk, 5 min of silence: the
      // silence is wall time and does not speed up.
      expect(end, now.add(const Duration(minutes: 35, seconds: 10)));
    });

    test('the model\'s finishesAt agrees', () {
      expect(
        const CueSettings(extendMinutes: 5).finishesAt(
          now,
          const Duration(minutes: 40),
          isTimer: false,
          speed: 2,
        ),
        now.add(const Duration(minutes: 25)),
      );
    });

    test('a timer ignores speed', () {
      expect(
        const CueSettings(
          durationMinutes: 20,
        ).finishesAt(now, Duration.zero, isTimer: true, speed: 2),
        now.add(const Duration(minutes: 20)),
      );
    });
  });
}
