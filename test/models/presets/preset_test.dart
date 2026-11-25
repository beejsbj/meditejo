import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';

const _rain = SoundMix([SoundLayer(soundId: 'rain-terrace', volume: 0.6)]);
const _bowl = 'assets/audio/bell_bowl_medium.wav';
const _gong = 'assets/audio/bell_gong.wav';
const _heart = 'assets/audio/pulse_heartbeat.wav';

Preset _roundTrip(Preset preset) =>
    Preset.tryFromJson(jsonDecode(jsonEncode(preset.toJson())))!;

void main() {
  group('slots', () {
    test('a preset holds only the slots that were set', () {
      final sit = Preset(
        id: 'user-1',
        name: 'Morning sit',
        slots: PresetSlots(
          bells: PresetCues.bells(const CueSettings(startSound: _bowl)),
          length: const PresetLength.minutes(20),
        ),
      );
      expect(sit.slots.filled, {PresetSlot.bells, PresetSlot.length});
      expect(sit.slots.has(PresetSlot.sound), isFalse);
      expect(sit.playsSound, isFalse);
      expect(sit.mix, SoundMix.empty);
      expect(sit.toJson().keys, ['id', 'name', 'bells', 'length']);
    });

    test('an empty slot falls through to what is underneath', () {
      final defaults = PresetSlots(
        sound: SoundMix.empty,
        bells: PresetCues.bells(const CueSettings()),
        rhythm: PresetCues.rhythm(const CueSettings()),
        length: const PresetLength.minutes(10),
      );
      const rain = PresetSlots(sound: _rain);
      final resolved = defaults.withSlots(rain);
      expect(resolved.sound, _rain);
      expect(resolved.bells, defaults.bells);
      expect(resolved.rhythm, defaults.rhythm);
      expect(resolved.length, const PresetLength.minutes(10));
      // Per kind: talks' defaults stay talks' under the same preset.
      final talks = PresetSlots(
        bells: PresetCues.bells(const CueSettings(endSound: '')),
      ).withSlots(rain);
      expect(talks.bells!.asSettings.endSound, '');
    });

    test('bells and rhythm are put into the settings they are applied to, '
        'and nothing else is touched', () {
      const before = CueSettings(
        durationMinutes: 45,
        extendMinutes: 5,
        endSilenceMinutes: 3,
        bellVolume: 0.9,
        autoplay: true,
        soundscape: 'none',
      );
      final bells = PresetCues.bells(
        const CueSettings(
          startSound: _bowl,
          endSound: _gong,
          countdownSeconds: 5,
          intervalMinutes: 10,
        ),
      );
      final rhythm = PresetCues.rhythm(
        const CueSettings(pulseSound: _heart, pulseBpm: 54),
      );
      final after = rhythm.applyTo(bells.applyTo(before));
      expect(after.startSound, _bowl);
      expect(after.endSound, _gong);
      expect(after.countdownSeconds, 5);
      expect(after.intervalMinutes, 10);
      expect(after.pulseSound, _heart);
      expect(after.pulseBpm, 54);
      // Not a preset's: the length, Extend, the ending bell's silence, the
      // volume all bells share, autoplay, the sound choice.
      expect(after.durationMinutes, 45);
      expect(after.extendMinutes, 5);
      expect(after.endSilenceMinutes, 3);
      expect(after.bellVolume, 0.9);
      expect(after.autoplay, isTrue);
      expect(after.soundscape, 'none');
    });

    test('an interval bell or a pulse that is off is off, whatever rate it '
        'remembers', () {
      expect(
        PresetCues.bells(const CueSettings(intervalSound: _gong)),
        PresetCues.bells(const CueSettings()),
      );
      expect(
        PresetCues.bells(
          const CueSettings(intervalHalfway: true, intervalMinutes: 7),
        ),
        PresetCues.bells(const CueSettings(intervalHalfway: true)),
      );
      expect(
        PresetCues.rhythm(const CueSettings(pulseBpm: 90, pulseEndBpm: 30)),
        PresetCues.rhythm(const CueSettings()),
      );
      expect(
        PresetCues.rhythm(const CueSettings(pulseSound: _heart, pulseBpm: 90)),
        isNot(PresetCues.rhythm(const CueSettings(pulseSound: _heart))),
      );
    });

    test('differing names the slots that are not the same', () {
      final a = PresetSlots(
        sound: _rain,
        bells: PresetCues.bells(const CueSettings()),
        length: const PresetLength.minutes(10),
      );
      final b = PresetSlots(
        sound: _rain,
        bells: PresetCues.bells(const CueSettings(startSound: _bowl)),
        length: const PresetLength.openEnded(),
      );
      expect(a.differing(b, PresetSlot.values), {
        PresetSlot.bells,
        PresetSlot.length,
      });
      expect(a.differing(b, {PresetSlot.sound, PresetSlot.rhythm}), isEmpty);
    });
  });

  group('JSON', () {
    test('all four slots round-trip, ∞ included', () {
      final sit = Preset(
        id: 'user-1',
        name: 'Morning sit',
        slots: PresetSlots(
          sound: _rain,
          bells: PresetCues.bells(
            const CueSettings(startSound: _bowl, intervalHalfway: true),
          ),
          rhythm: PresetCues.rhythm(
            const CueSettings(
              pulseSound: _heart,
              pulseBpm: 60,
              pulseEndBpm: 48,
              pulseRampMinutes: 10,
            ),
          ),
          length: const PresetLength.openEnded(),
        ),
      );
      expect(_roundTrip(sit), sit);
      final timed = sit.copyWith(
        slots: const PresetSlots(length: PresetLength.minutes(25)),
      );
      expect(_roundTrip(timed), timed);
      expect(_roundTrip(timed).slots.filled, {PresetSlot.length});
    });

    test('silence, chosen, is a Sound slot and not an empty one', () {
      const silent = Preset(
        id: 'user-2',
        name: 'Quiet',
        slots: PresetSlots(sound: SoundMix.empty),
      );
      expect(_roundTrip(silent).slots.has(PresetSlot.sound), isTrue);
      expect(_roundTrip(silent).playsSound, isFalse);
    });

    test('a mix saved before presets had slots reads as a preset with only '
        'its Sound slot', () {
      final old = Preset.tryFromJson({
        'id': 'user-9',
        'name': 'Evening',
        'layers': _rain.toJson(),
      })!;
      expect(old.slots.filled, {PresetSlot.sound});
      expect(old.mix, _rain);
    });

    test('what a newer version wrote is kept: unknown fields survive a save, '
        'and a slot it cannot read is empty', () {
      final json = {
        'id': 'user-3',
        'name': 'From the future',
        'layers': _rain.toJson(),
        'length': {'until': '07:30'},
        'posture': 'walking',
        'tags': ['dawn'],
      };
      final preset = Preset.tryFromJson(json)!;
      expect(preset.slots.filled, {PresetSlot.sound});
      final written = preset.copyWith(name: 'Renamed').toJson();
      expect(written['posture'], 'walking');
      expect(written['tags'], ['dawn']);
      expect(written['name'], 'Renamed');
    });

    test('damaged values never throw: a bad slot is empty, a bad bell is the '
        'default, a preset with no id is dropped', () {
      final preset = Preset.tryFromJson({
        'id': 'user-4',
        'name': 'Odd',
        'layers': 'rain',
        'bells': {'startSound': 'not-a-bell', 'countdownSeconds': 'five'},
        'rhythm': 7,
        'length': {'minutes': 100000},
      })!;
      expect(preset.slots.has(PresetSlot.sound), isFalse);
      expect(preset.slots.bells!.asSettings.startSound, cueDefaultBell);
      expect(preset.slots.bells!.asSettings.countdownSeconds, 0);
      expect(preset.slots.has(PresetSlot.rhythm), isFalse);
      expect(preset.slots.length, const PresetLength.minutes(299));
      expect(Preset.tryFromJson({'name': 'No id'}), isNull);
      expect(Preset.tryFromJson('nonsense'), isNull);
    });

    test('a bell the user made is kept by its id', () {
      const id = 'custom-bell:abc123';
      final preset = Preset(
        id: 'user-5',
        name: 'Mine',
        slots: PresetSlots(
          bells: PresetCues.bells(const CueSettings(startSound: id)),
        ),
      );
      expect(_roundTrip(preset).slots.bells!.asSettings.startSound, id);
    });
  });

  test('the presets that ship each hold only a sound', () {
    for (final preset in kStarterPresets) {
      expect(preset.builtIn, isTrue);
      expect(preset.slots.filled, {PresetSlot.sound}, reason: preset.id);
      expect(preset.playsSound, isTrue);
    }
  });
}
