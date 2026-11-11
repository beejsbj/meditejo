import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/player/player_provider.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

const _bowl = 'assets/audio/bell_bowl_medium.wav';
const _gong = 'assets/audio/bell_gong.wav';
const _heart = 'assets/audio/pulse_heartbeat.wav';
const _river = SoundMix([SoundLayer(soundId: 'river', volume: 0.6)]);
const _practice = CueScope(CueKind.practice);
const _talks = CueScope(CueKind.talks);
const _timer = PresetContext.timer();
const _underTalk = PresetContext.session(_talks);
const _sounds = PresetContext.sounds();

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> make([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...soundscapeTestOverrides(FakeSoundscapeEngine()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(soundLibraryProvider.future);
    // Kept alive, as the screens that read it keep it.
    container.listen(timerSettingsProvider, (_, _) {});
  }

  SoundscapeController mixer() => container.read(soundscapeProvider.notifier);
  SoundscapeState sound() => container.read(soundscapeProvider);
  CueSettings cues(CueScope scope) =>
      container.read(cueSettingsProvider(scope));
  PresetSlots current(PresetContext place) =>
      container.read(currentPresetSlotsProvider(place));
  LoadedPreset? loaded(PresetContext place) =>
      container.read(loadedPresetProvider(place));
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// A sit holding all four slots.
  Preset sit({PresetLength length = const PresetLength.minutes(20)}) => Preset(
    id: 'user-sit',
    name: 'Morning sit',
    slots: PresetSlots(
      sound: _river,
      bells: PresetCues.bells(
        const CueSettings(startSound: _bowl, endSound: _gong),
      ),
      rhythm: PresetCues.rhythm(
        const CueSettings(pulseSound: _heart, pulseBpm: 54),
      ),
      length: length,
    ),
  );

  test('where you are decides which slots are in play', () {
    expect(_timer.offered, PresetSlot.values.toSet());
    expect(_underTalk.offered, {
      PresetSlot.sound,
      PresetSlot.bells,
      PresetSlot.rhythm,
    });
    expect(_sounds.offered, {PresetSlot.sound});
    expect(
      const PresetContext.sounds(
        chooserKind: SoundscapeSessionKind.practice,
      ).offered,
      {PresetSlot.sound},
    );
  });

  group('applying a preset', () {
    test('on the Timer sets all four slots, and names the preset', () async {
      await make();
      mixer().putPreset(sit());
      await applyPreset(container, _timer, sit());
      final s = cues(_practice);
      expect(s.startSound, _bowl);
      expect(s.endSound, _gong);
      expect(s.pulseSound, _heart);
      expect(s.pulseBpm, 54);
      expect(s.durationMinutes, 20);
      expect(container.read(timerSettingsProvider).mode, TimerMode.countdown);
      final under = mixer().sessionDefault(SoundscapeSessionKind.practice);
      expect(under.enabled, isTrue);
      expect(under.selection, const SoundscapeSelection.preset('user-sit'));
      expect(current(_timer), sit().slots);
      expect(loaded(_timer)!.preset.id, 'user-sit');
      expect(loaded(_timer)!.edited, isFalse);
    });

    test('∞ turns the Timer open-ended and leaves its minutes; a timed '
        'preset turns it back', () async {
      await make();
      await container
          .read(cueSettingsProvider(_practice).notifier)
          .update(const CueSettings(durationMinutes: 35));
      await applyPreset(
        container,
        _timer,
        sit(length: const PresetLength.openEnded()),
      );
      expect(container.read(timerSettingsProvider).mode, TimerMode.stopwatch);
      expect(cues(_practice).durationMinutes, 35);
      expect(current(_timer).length, const PresetLength.openEnded());
      await applyPreset(container, _timer, sit());
      expect(container.read(timerSettingsProvider).mode, TimerMode.countdown);
      expect(cues(_practice).durationMinutes, 20);
    });

    test('an empty slot leaves what is set as it is', () async {
      await make();
      await container
          .read(cueSettingsProvider(_practice).notifier)
          .update(
            const CueSettings(
              durationMinutes: 35,
              startSound: _gong,
              pulseSound: _heart,
            ),
          );
      // Sound only, as every preset that ships is.
      await applyPreset(container, _timer, kStarterPresets[1]);
      final s = cues(_practice);
      expect(s.durationMinutes, 35);
      expect(s.startSound, _gong);
      expect(s.pulseSound, _heart);
      expect(
        mixer().sessionDefault(SoundscapeSessionKind.practice).selection,
        SoundscapeSelection.preset(kStarterPresets[1].id),
      );
    });

    test('under a recording the length is the recording\'s: the rest is set '
        'for that kind, and the Timer is not touched', () async {
      await make();
      mixer().putPreset(sit());
      await applyPreset(container, _underTalk, sit());
      expect(cues(_talks).startSound, _bowl);
      expect(cues(_talks).pulseSound, _heart);
      expect(cues(_talks).durationMinutes, 10);
      expect(
        mixer().sessionDefault(SoundscapeSessionKind.talks).selection,
        const SoundscapeSelection.preset('user-sit'),
      );
      expect(cues(_practice).startSound, cueDefaultBell);
      expect(loaded(_underTalk)!.preset.id, 'user-sit');
      expect(loaded(_underTalk)!.edited, isFalse);
      expect(loaded(_timer), isNull);
    });

    test(
      'a course with its own settings keeps the choice for itself',
      () async {
        await make();
        const course = CueScope(CueKind.talks, courseId: 'course-1');
        const place = PresetContext.session(course, courseOverride: true);
        mixer().putPreset(sit());
        await applyPreset(container, place, sit());
        expect(cues(course).startSound, _bowl);
        expect(cues(course).soundscape, 'preset:user-sit');
        expect(cues(_talks).startSound, cueDefaultBell);
        expect(
          mixer().sessionDefault(SoundscapeSessionKind.talks).enabled,
          isFalse,
        );
      },
    );

    test('in the Sounds sheet only its sound plays, on its own, and that is '
        'not a sit', () async {
      await make();
      mixer().putPreset(sit());
      await applyPreset(container, _sounds, sit());
      await settle();
      expect(sound().mix, _river);
      expect(sound().playing, isTrue);
      expect(sound().owner, SoundscapeOwner.standalone);
      // No session: nothing for the stats to count.
      expect(sound().inSession, isFalse);
      expect(container.read(playerProvider), isNull);
      // Its bells, rhythm and length are not set by the Sounds sheet.
      expect(cues(_practice).startSound, cueDefaultBell);
      expect(cues(_practice).pulseSound, '');
      expect(cues(_practice).durationMinutes, 10);
      expect(loaded(_sounds)!.preset.id, 'user-sit');
    });
  });

  group('the preset loaded', () {
    test('reads as edited once a slot it sets has moved on, and not for '
        'slots it does not set', () async {
      await make();
      final bellsOnly = Preset(
        id: 'user-bells',
        name: 'Bowl',
        slots: PresetSlots(
          bells: PresetCues.bells(const CueSettings(startSound: _bowl)),
        ),
      );
      mixer().putPreset(bellsOnly);
      await applyPreset(container, _timer, bellsOnly);
      expect(loaded(_timer)!.edited, isFalse);
      final notifier = container.read(cueSettingsProvider(_practice).notifier);
      await notifier.update(cues(_practice).copyWith(durationMinutes: 42));
      expect(loaded(_timer)!.edited, isFalse);
      await notifier.update(cues(_practice).copyWith(startSound: _gong));
      expect(loaded(_timer)!.edited, isTrue);
    });

    test('the Timer and practice share their settings, so also the preset '
        'they came from; its length is not held against a recording', () async {
      await make();
      mixer().putPreset(sit());
      await applyPreset(container, _timer, sit());
      await container
          .read(cueSettingsProvider(_practice).notifier)
          .update(cues(_practice).copyWith(durationMinutes: 5));
      expect(loaded(_timer)!.edited, isTrue);
      const underPractice = PresetContext.session(_practice);
      expect(loaded(underPractice)!.preset.id, 'user-sit');
      expect(loaded(underPractice)!.edited, isFalse);
    });

    test('in the Sounds sheet a mix that is a preset\'s sound is that preset; '
        'changed, it is "edited"; emptied, it came from nowhere', () async {
      await make();
      await applyPreset(container, _sounds, kStarterPresets[1]);
      await settle();
      expect(loaded(_sounds)!.preset.id, kStarterPresets[1].id);
      expect(loaded(_sounds)!.edited, isFalse);
      mixer().toggleSound('river');
      expect(loaded(_sounds)!.preset.id, kStarterPresets[1].id);
      expect(loaded(_sounds)!.edited, isTrue);
      mixer().clearMix();
      expect(loaded(_sounds), isNull);
      mixer().toggleSound('river');
      expect(loaded(_sounds), isNull);
    });

    test(
      'is remembered across launches, and forgotten with the preset',
      () async {
        await make();
        mixer().putPreset(sit());
        await applyPreset(container, _timer, sit());
        final values = {
          for (final key in prefs.getKeys()) key: prefs.get(key)!,
        };
        await make(values);
        expect(loaded(_timer)!.preset.id, 'user-sit');
        deletePreset(container, 'user-sit');
        expect(loaded(_timer), isNull);
      },
    );
  });

  group('saving', () {
    test('from the Timer a new preset holds the ticked slots, as they are '
        'set, and is the one loaded', () async {
      await make();
      await container
          .read(cueSettingsProvider(_practice).notifier)
          .update(const CueSettings(durationMinutes: 25, startSound: _bowl));
      final saved = saveNewPreset(
        container,
        _timer,
        name: '  Short sit ',
        ticked: {PresetSlot.bells, PresetSlot.length},
      )!;
      expect(saved.name, 'Short sit');
      expect(saved.slots.filled, {PresetSlot.bells, PresetSlot.length});
      expect(saved.slots.bells!.asSettings.startSound, _bowl);
      expect(saved.slots.length, const PresetLength.minutes(25));
      expect(sound().userPresets.single, saved);
      expect(SoundscapeStore(prefs).readPresets().single, saved);
      expect(loaded(_timer)!.preset.id, saved.id);
      expect(
        container.read(pinnedPresetIdsProvider),
        isNot(contains(saved.id)),
      );
    });

    test('the Timer on ∞ saves ∞', () async {
      await make();
      container
          .read(timerSettingsProvider.notifier)
          .setMode(TimerMode.stopwatch);
      final saved = saveNewPreset(
        container,
        _timer,
        name: 'Open',
        ticked: {PresetSlot.length},
      )!;
      expect(saved.slots.length, const PresetLength.openEnded());
    });

    test('under a recording a ticked Length is not saved: the recording '
        'owns it', () async {
      await make();
      await container
          .read(cueSettingsProvider(_talks).notifier)
          .update(const CueSettings(startSound: _gong));
      final saved = saveNewPreset(
        container,
        _underTalk,
        name: 'For talks',
        ticked: PresetSlot.values.toSet(),
      )!;
      expect(saved.slots.filled, {
        PresetSlot.sound,
        PresetSlot.bells,
        PresetSlot.rhythm,
      });
      expect(saved.slots.bells!.asSettings.startSound, _gong);
      // Nothing plays under talks: that silence is what was saved.
      expect(saved.slots.sound, SoundMix.empty);
    });

    test('from the Sounds sheet it is the mix and nothing else, whatever is '
        'ticked', () async {
      await make();
      mixer().toggleSound('river');
      final saved = saveNewPreset(
        container,
        _sounds,
        name: 'River',
        ticked: PresetSlot.values.toSet(),
      )!;
      expect(saved.slots.filled, {PresetSlot.sound});
      expect(saved.mix.contains('river'), isTrue);
      expect(sound().matchingPreset, saved);
    });

    test(
      'no name, or nothing ticked, saves nothing; Pin to Home pins it',
      () async {
        await make();
        mixer().toggleSound('river');
        expect(
          saveNewPreset(
            container,
            _sounds,
            name: ' ',
            ticked: {PresetSlot.sound},
          ),
          isNull,
        );
        expect(
          saveNewPreset(container, _sounds, name: 'River', ticked: const {}),
          isNull,
        );
        expect(sound().userPresets, isEmpty);
        final saved = saveNewPreset(
          container,
          _sounds,
          name: 'River',
          ticked: {PresetSlot.sound},
          pin: true,
        )!;
        expect(container.read(pinnedPresetIdsProvider).last, saved.id);
        expect(container.read(pinnedPresetsProvider).last, saved);
      },
    );

    test('Update from the Sounds sheet writes the Sound slot alone: the sit '
        'keeps its bells, rhythm and length (#68)', () async {
      await make();
      mixer().putPreset(sit());
      await applyPreset(container, _sounds, sit());
      await settle();
      mixer().toggleSound('cafe');
      final updated = updatePreset(
        container,
        _sounds,
        sit(),
        ticked: PresetSlot.values.toSet(),
      );
      expect(updated.id, 'user-sit');
      expect(updated.mix.contains('cafe'), isTrue);
      expect(updated.slots.bells, sit().slots.bells);
      expect(updated.slots.rhythm, sit().slots.rhythm);
      expect(updated.slots.length, sit().slots.length);
      expect(sound().userPresets.single, updated);
      expect(loaded(_sounds)!.edited, isFalse);
    });

    test(
      'Update on the Timer writes only what is ticked: a sound-only '
      'preset gains bells when Bells is ticked, and not when it is not',
      () async {
        await make();
        final rain = Preset.sound(id: 'user-rain', name: 'Rain', mix: _river);
        mixer().putPreset(rain);
        await applyPreset(container, _timer, rain);
        final notifier = container.read(
          cueSettingsProvider(_practice).notifier,
        );
        await notifier.update(cues(_practice).copyWith(startSound: _bowl));
        final unticked = updatePreset(
          container,
          _timer,
          rain,
          ticked: {PresetSlot.sound},
        );
        expect(unticked.slots.filled, {PresetSlot.sound});
        final ticked = updatePreset(
          container,
          _timer,
          rain,
          ticked: {PresetSlot.sound, PresetSlot.bells},
        );
        expect(ticked.slots.filled, {PresetSlot.sound, PresetSlot.bells});
        expect(ticked.slots.bells!.asSettings.startSound, _bowl);
        expect(ticked.name, 'Rain');
        expect(sound().userPresets, [ticked]);
      },
    );

    test('a built-in preset is never written over', () async {
      await make();
      mixer().putPreset(kStarterPresets.first.copyWith(name: 'Mine now'));
      expect(sound().userPresets, isEmpty);
      expect(sound().presets.first.name, kStarterPresets.first.name);
    });
  });

  group('pins', () {
    test('pin, unpin and Undo keep the order; pinning twice is once', () async {
      await make({SoundscapeStore.pinnedPresetsKey: <String>[]});
      final pins = container.read(pinnedPresetIdsProvider.notifier);
      final ids = [for (final p in kStarterPresets.take(3)) p.id];
      for (final id in ids) {
        pins.pin(id);
      }
      pins.pin(ids.first);
      expect(container.read(pinnedPresetIdsProvider), ids);
      expect(prefs.getStringList(SoundscapeStore.pinnedPresetsKey), ids);
      final before = container.read(pinnedPresetIdsProvider);
      pins.unpin(ids[1]);
      expect(container.read(pinnedPresetIdsProvider), [ids[0], ids[2]]);
      expect(pins.isPinned(ids[1]), isFalse);
      pins.pinBack(ids[1], before);
      expect(container.read(pinnedPresetIdsProvider), ids);
    });

    test('a deleted preset is unpinned, and a pin whose preset is gone '
        'shows nothing', () async {
      await make({
        SoundscapeStore.pinnedPresetsKey: ['user-gone', 'starter-night'],
      });
      expect(container.read(pinnedPresetsProvider).map((p) => p.id), [
        'starter-night',
      ]);
      mixer().putPreset(sit());
      container.read(pinnedPresetIdsProvider.notifier).pin('user-sit');
      expect(container.read(pinnedPresetsProvider).last.id, 'user-sit');
      deletePreset(container, 'user-sit');
      expect(
        container.read(pinnedPresetIdsProvider),
        isNot(contains('user-sit')),
      );
      expect(sound().userPresets, isEmpty);
    });
  });
}
