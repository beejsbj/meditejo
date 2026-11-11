import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/pauses/pause_hold.dart';
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

  // #72 moved Autoplay to the player and dropped Customize's Flow section.
  // What the old sheet stored still loads, keeps its meaning, and survives
  // the next save; keys the app does not know are ignored.
  test('settings stored by the Flow-era sheet load unchanged', () async {
    const flowEra = {
      'version': 1,
      'durationMinutes': 25,
      'extendMinutes': 5,
      'countdownSeconds': 10,
      'startSound': 'assets/audio/bell_gong.wav',
      'endSound': 'assets/audio/bell_chime.wav',
      'pulseSound': 'assets/audio/pulse_heartbeat.wav',
      'autoplay': true,
      'interludeSeconds': 30,
      'hideBeforePractice': true,
      // Not keys this app writes: a section that no longer exists, and
      // whatever another build might have added.
      'flow': {'autoplay': true},
      'somethingNewer': 'x',
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cues.v1.practice', jsonEncode(flowEra));
    await prefs.setString(
      'cues.v1.talks.course.c1',
      jsonEncode({...flowEra, 'hideBeforePractice': false}),
    );
    final store = CueSettingsStore(prefs);
    final practice = store.read(const CueScope(CueKind.practice));
    expect(practice.autoplay, isTrue, reason: 'the player reads it now');
    expect(practice.interludeSeconds, 30);
    expect(practice.showBeforeSession, isFalse);
    expect(practice.countdownSeconds, 10, reason: 'now the starting bell');
    expect(practice.extendMinutes, 5, reason: 'Extend, under Length');
    expect(practice.durationMinutes, 25);
    final course = store.read(const CueScope(CueKind.talks, courseId: 'c1'));
    expect(course.showBeforeSession, isTrue);
    expect(course.autoplay, isTrue);

    // Saved again, it keeps the same keys, so an older build reads it too.
    await store.save(const CueScope(CueKind.practice), practice);
    final saved =
        jsonDecode(prefs.getString('cues.v1.practice')!)
            as Map<String, dynamic>;
    expect(saved['hideBeforePractice'], isTrue);
    expect(saved['autoplay'], isTrue);
    expect(saved['interludeSeconds'], 30);
    expect(saved.containsKey('flow'), isFalse);
  });

  test('"Show before each session" is on until switched off', () {
    expect(CueSettings.defaults(CueKind.practice).showBeforeSession, isTrue);
    expect(CueSettings.defaults(CueKind.talks).showBeforeSession, isTrue);
    expect(
      const CueSettings(hideBeforePractice: true).showBeforeSession,
      isFalse,
    );
    expect(
      CueSettings.decode(
        '{"hideBeforePractice":"yes"}',
        CueKind.practice,
      ).showBeforeSession,
      isTrue,
      reason: 'a damaged value shows the sheet',
    );
  });

  group('Extend', () {
    const holds = [PauseHold(105000, 60000), PauseHold(215000, 120000)];

    test(
      'Extend and the Ending bell silence are apart and survive a round trip',
      () {
        expect(const CueSettings().endSilenceMinutes, 0);
        const s = CueSettings(extendMinutes: 10, endSilenceMinutes: 5);
        final back = CueSettings.fromJson(s.toJson());
        expect(back.extendMinutes, 10);
        expect(back.endSilenceMinutes, 5);
        expect(CueSettings.fromJson(const {}).endSilenceMinutes, 0);
        expect(
          CueSettings.fromJson({'endSilenceMinutes': 'ten'}).endSilenceMinutes,
          0,
        );
        expect(
          CueSettings.fromJson({'endSilenceMinutes': 500}).endSilenceMinutes,
          60,
        );
        expect(s.copyWith(extendMinutes: 0).endSilenceMinutes, 5);
        expect(s.copyWith(endSilenceMinutes: 0).extendMinutes, 10);
        // 0.1.4's "Extend with silence" is still Extend.
        expect(CueSettings.fromJson({'extendMinutes': 6}).extendMinutes, 6);
      },
    );

    test('a test build rest in the pauses becomes Extend', () {
      // The 2026-10-28 builds of #49 stored the silence after the recording
      // as extendMinutes and the rest in the pauses as pauseMinutes.
      final s = CueSettings.fromJson({'extendMinutes': 3, 'pauseMinutes': 8});
      expect(s.extendMinutes, 8);
      expect(s.endSilenceMinutes, 3);
      // Once saved in the new shape it is read as it is.
      expect(CueSettings.fromJson(s.toJson()).extendMinutes, 8);
      expect(CueSettings.fromJson(s.toJson()).endSilenceMinutes, 3);
      expect(s.toJson().containsKey('pauseMinutes'), isFalse);
    });

    test(
      'the engines get all the silence as one extension, holds from Extend',
      () {
        const s = CueSettings(extendMinutes: 10, endSilenceMinutes: 5);
        final sent = s.nativeConfiguration(
          durationMs: 600000,
          isTimer: false,
          holds: holds,
        );
        expect(sent['extendMinutes'], 15);
        expect(sent['holds'], [
          {'atMs': 105000, 'holdMs': 60000},
          {'atMs': 215000, 'holdMs': 120000},
        ]);
        // No Extend: whatever was computed, nothing is held in the recording.
        final atEnd = const CueSettings(
          endSilenceMinutes: 10,
        ).nativeConfiguration(durationMs: 600000, isTimer: false, holds: holds);
        expect(atEnd['holds'], isEmpty);
        expect(atEnd['extendMinutes'], 10);
        // A timer has no recording to extend.
        final timer = s.nativeConfiguration(
          durationMs: 600000,
          isTimer: true,
          holds: holds,
        );
        expect(timer['holds'], isEmpty);
        expect(timer['extendMinutes'], 0);
      },
    );

    test('the session lasts the recording plus all of its silence', () {
      const s = CueSettings(extendMinutes: 10, endSilenceMinutes: 5);
      expect(s.extraMinutes, 15);
      expect(
        s.sessionDuration(const Duration(minutes: 30), isTimer: false),
        const Duration(minutes: 45),
      );
      final now = DateTime(2026, 10, 28, 9);
      expect(
        s.finishesAt(now, const Duration(minutes: 30), isTimer: false),
        now.add(const Duration(minutes: 45)),
      );
    });
  });
}
