import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/views/timer/start_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

/// BRIEF decision 19: the Timer starts silent. A Timer is a Practice session
/// (`timerCueScope`), so this pins what a fresh install's Timer does: no
/// background sound, the default bells, and whatever the user saves wins.
void main() {
  late FakeSoundscapeEngine engine;

  Future<ProviderContainer> launch([
    Map<String, Object> stored = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    engine = FakeSoundscapeEngine();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...soundscapeTestOverrides(engine),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Starts the Timer's soundscape as the player does: the kind, plus the
  /// scope's own choice when it has one.
  Future<void> startTimerSound(ProviderContainer c) async {
    final cues = c.read(cueSettingsProvider(timerCueScope));
    await c
        .read(soundscapeProvider.notifier)
        .startSession(
          SoundscapeSessionKind.practice,
          selection: cues.soundscapeSelection,
        );
    await settle();
  }

  test('a fresh install has the default bells and nothing else', () async {
    final c = await launch();
    final cues = c.read(cueSettingsProvider(timerCueScope));
    expect(cues.startSound, kSessionBellAsset);
    expect(cues.endSound, kSessionBellAsset);
    expect(cues.hasIntervalBell, isFalse);
    expect(cues.intervalHalfway, isFalse);
    expect(cues.pulseSound, '');
    expect(cues.countdownSeconds, 0);
    expect(cues.soundscape, '', reason: 'follows the kind, which is off');
    expect(
      c
          .read(soundscapeProvider)
          .sessionDefault(SoundscapeSessionKind.practice)
          .enabled,
      isFalse,
    );
  });

  test('a fresh install\'s Timer plays no background sound', () async {
    final c = await launch();
    await startTimerSound(c);
    expect(engine.playing, isEmpty);
    expect(c.read(soundscapeProvider).active, isFalse);
    expect(c.read(soundscapeProvider).owner, SoundscapeOwner.none);
  });

  test('user-saved defaults win, and survive a relaunch', () async {
    final c = await launch();
    c
        .read(soundscapeProvider.notifier)
        .setSessionDefault(
          SoundscapeSessionKind.practice,
          const SoundscapeSessionDefault(
            enabled: true,
            selection: SoundscapeSelection.preset('starter-night'),
          ),
        );
    await c
        .read(cueSettingsProvider(timerCueScope).notifier)
        .update(
          c
              .read(cueSettingsProvider(timerCueScope))
              .copyWith(intervalHalfway: true, countdownSeconds: 5),
        );
    await startTimerSound(c);
    expect(engine.playing, isNotEmpty, reason: 'the chosen sound plays');

    // A relaunch reads the same prefs: the choices are still there.
    final prefs = c.read(sharedPreferencesProvider);
    final stored = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
    final again = await launch(stored);
    final cues = again.read(cueSettingsProvider(timerCueScope));
    expect(cues.intervalHalfway, isTrue);
    expect(cues.countdownSeconds, 5);
    await startTimerSound(again);
    expect(engine.playing, isNotEmpty);
  });
}
