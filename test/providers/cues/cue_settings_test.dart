import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Practice and Talks have separate background defaults', () async {
    final store = CueSettingsStore(await SharedPreferences.getInstance());
    expect(
      store.read(const CueScope(CueKind.practice)).backgroundEnabled,
      isTrue,
    );
    expect(
      store.read(const CueScope(CueKind.talks)).backgroundEnabled,
      isFalse,
    );
  });
  test('all cue preferences persist independently by kind', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = CueSettingsStore(prefs);
    const practice = CueScope(CueKind.practice);
    const s = CueSettings(
      countdownSeconds: 10,
      extendMinutes: 25,
      intervalMinutes: 5,
      randomWindowMinutes: 2,
      pulseSound: 'assets/audio/pulse_click.wav',
      pulseBpm: 70,
      pulseEndBpm: 35,
      pulseRampMinutes: 15,
      pulseVolume: .3,
      backgroundVolume: 25,
      autoplay: true,
      interludeSeconds: 30,
      hideBeforePractice: true,
    );
    await store.save(practice, s);
    expect(CueSettingsStore(prefs).read(practice).toJson(), s.toJson());
    expect(store.read(const CueScope(CueKind.talks)).countdownSeconds, 0);
  });
  test(
    'course inherits defaults until override and can return to them',
    () async {
      final store = CueSettingsStore(await SharedPreferences.getInstance());
      const base = CueScope(CueKind.practice);
      const course = CueScope(CueKind.practice, courseId: 'ds-retreat-4496');
      await store.save(base, const CueSettings(extendMinutes: 5));
      expect(store.read(course).extendMinutes, 5);
      expect(store.hasOverride(course), isFalse);
      await store.save(course, const CueSettings(extendMinutes: 20));
      await store.save(base, const CueSettings(extendMinutes: 10));
      expect(store.read(course).extendMinutes, 20);
      expect(store.hasOverride(course), isTrue);
      await store.removeOverride(course);
      expect(store.read(course).extendMinutes, 10);
    },
  );
  test('invalid stored values safely clamp and unknown sounds are refused', () {
    final s = CueSettings.fromJson({
      'extendMinutes': 900,
      'countdownSeconds': 7,
      'pulseBpm': -1,
      'pulseVolume': 3,
      'startSound': 'https://unlicensed.test/bell.mp3',
      'backgroundVolume': double.nan,
    });
    expect(s.extendMinutes, 60);
    expect(s.countdownSeconds, 0);
    expect(s.pulseBpm, 20);
    expect(s.pulseVolume, 1);
    expect(s.startSound, 'assets/audio/session_bell_v2.wav');
    expect(s.backgroundVolume, 50);
    expect(
      CueSettings.decode('broken json', CueKind.talks).backgroundEnabled,
      isFalse,
    );
  });
  test('non-finite numbers and newer formats fall back to defaults', () {
    // Valid JSON that is not a finite int must not throw.
    expect(
      CueSettings.decode(
        '{"durationMinutes": 1e999}',
        CueKind.practice,
      ).durationMinutes,
      10,
    );
    expect(
      CueSettings.decode(
        '{"intervalMinutes": 1e999, "extendMinutes": 5}',
        CueKind.practice,
      ).extendMinutes,
      5,
    );
    expect(CueSettings.decode('1e999', CueKind.talks).backgroundEnabled, false);
    // A value from a newer app is not guessed at; an unversioned one is v1.
    final newer = jsonEncode({
      ...const CueSettings(extendMinutes: 7).toJson(),
      'version': CueSettings.formatVersion + 1,
    });
    expect(CueSettings.decode(newer, CueKind.practice).extendMinutes, 0);
    final current = jsonEncode(const CueSettings(extendMinutes: 7).toJson());
    expect(CueSettings.decode(current, CueKind.practice).extendMinutes, 7);
    expect(
      CueSettings.decode(
        '{"extendMinutes": 7}',
        CueKind.practice,
      ).extendMinutes,
      7,
    );
  });

  test('the soundscape selection is a compatible, inherited field', () async {
    // Default: follow the mixer's own default for the kind.
    expect(const CueSettings().soundscape, '');
    expect(const CueSettings().soundscapeSelection, isNull);
    for (final kind in CueKind.values) {
      expect(CueSettings.defaults(kind).soundscape, '');
    }
    // Round trip, normalised to the selection grammar.
    const chosen = CueSettings(soundscape: 'preset:starter-night');
    expect(
      CueSettings.decode(jsonEncode(chosen.toJson()), CueKind.talks).soundscape,
      'preset:starter-night',
    );
    expect(
      chosen.soundscapeSelection,
      const SoundscapeSelection.preset('starter-night'),
    );
    expect(CueSettings.fromJson({'soundscape': ' '}).soundscape, '');
    // An unknown value follows the default rather than turning sound on.
    expect(CueSettings.fromJson({'soundscape': 'nonsense'}).soundscape, '');
    expect(CueSettings.fromJson({'soundscape': 'drone:low'}).soundscape, '');
    expect(CueSettings.fromJson({'soundscape': 7}).soundscape, '');
    expect(
      const CueSettings().copyWith(soundscape: 'none').soundscapeSelection,
      SoundscapeSelection.none,
    );

    // Slice 6's background switch never played anything and never shipped:
    // values saved before this field follow the mixer, whatever it said.
    String old(CueKind kind, bool enabled) => CueSettings.decode(
      jsonEncode({'version': 1, 'backgroundEnabled': enabled}),
      kind,
    ).soundscape;
    for (final kind in CueKind.values) {
      expect(old(kind, true), '');
      expect(old(kind, false), '');
    }

    // A course inherits its kind's choice until it overrides it.
    final store = CueSettingsStore(await SharedPreferences.getInstance());
    const base = CueScope(CueKind.talks);
    const course = CueScope(CueKind.talks, courseId: 'ds-retreat-1');
    await store.save(base, const CueSettings(soundscape: 'sound:river'));
    expect(store.read(course).soundscape, 'sound:river');
    await store.save(course, const CueSettings(soundscape: 'none'));
    expect(store.read(course).soundscape, 'none');
    expect(store.read(base).soundscape, 'sound:river');
  });

  test('native timer configuration omits extension and off assets', () {
    final map = const CueSettings(
      extendMinutes: 20,
      startSound: '',
      pulseSound: '',
    ).nativeConfiguration(durationMs: 600000, isTimer: true);
    expect(map['extendMinutes'], 0);
    expect(map['startSound'], isNull);
    expect(map['pulseSound'], isNull);
    expect(map['durationMs'], 600000);
  });
  test(
    'legacy timer duration is retained until Customize has its own default',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('timer_minutes', 25);
      final store = CueSettingsStore(prefs);
      expect(store.read(const CueScope(CueKind.practice)).durationMinutes, 25);
      await store.save(
        const CueScope(CueKind.practice),
        const CueSettings(durationMinutes: 15),
      );
      expect(store.read(const CueScope(CueKind.practice)).durationMinutes, 15);
    },
  );
  test(
    'editing a kind refreshes previously read inheriting course scopes',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      const base = CueScope(CueKind.practice);
      const course = CueScope(CueKind.practice, courseId: 'course');
      expect(container.read(cueSettingsProvider(course)).extendMinutes, 0);
      await container
          .read(cueSettingsProvider(base).notifier)
          .update(const CueSettings(extendMinutes: 10));
      expect(container.read(cueSettingsProvider(course)).extendMinutes, 10);
    },
  );
}
