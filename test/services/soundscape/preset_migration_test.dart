import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rain = [
  {'soundId': 'rain-terrace', 'volume': 0.6},
];
const _stream = [
  {'soundId': 'stream', 'volume': 0.4, 'animate': true},
  {'soundId': 'wind-trees', 'volume': 0.2},
];

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  group('saved mixes become presets', () {
    test('every saved mix is a preset with only its Sound slot, under the '
        'same id, name and order', () async {
      final saved = [
        {'id': 'user-1', 'name': 'Evening', 'layers': _rain},
        {'id': 'user-2', 'name': 'By the stream', 'layers': _stream},
      ];
      final prefs = await _prefs({
        SoundscapeStore.legacyPresetsKey: jsonEncode(saved),
      });
      final presets = SoundscapeStore(prefs).readPresets();
      expect(presets.map((p) => p.id), ['user-1', 'user-2']);
      expect(presets.map((p) => p.name), ['Evening', 'By the stream']);
      for (final (i, preset) in presets.indexed) {
        expect(preset.slots.filled, {PresetSlot.sound});
        expect(preset.mix, SoundMix.fromJson(saved[i]['layers']));
        expect(preset.builtIn, isFalse);
      }
      // Written where presets live now; the old list is left for an older
      // build to find.
      expect(
        jsonDecode(prefs.getString(SoundscapeStore.presetsKey)!),
        jsonDecode(jsonEncode(saved)),
      );
      expect(
        prefs.getString(SoundscapeStore.legacyPresetsKey),
        jsonEncode(saved),
      );
    });

    test('it runs once: what is saved afterwards is not overwritten by the '
        'old list, and reading again changes nothing', () async {
      final prefs = await _prefs({
        SoundscapeStore.legacyPresetsKey: jsonEncode([
          {'id': 'user-1', 'name': 'Evening', 'layers': _rain},
        ]),
      });
      final store = SoundscapeStore(prefs);
      final first = store.readPresets();
      final sit = Preset(
        id: 'user-3',
        name: 'Morning sit',
        slots: PresetSlots(
          bells: PresetCues.bells(const CueSettings(countdownSeconds: 5)),
          length: const PresetLength.minutes(20),
        ),
      );
      store.writePresets([sit]);
      expect(SoundscapeStore(prefs).readPresets(), [sit]);
      // Deleting everything stays deleted: the old list does not come back.
      store.writePresets(const []);
      expect(SoundscapeStore(prefs).readPresets(), isEmpty);
      expect(first.single.id, 'user-1');
      final written = prefs.getString(SoundscapeStore.presetsKey);
      SoundscapeStore(prefs).readPresets();
      expect(prefs.getString(SoundscapeStore.presetsKey), written);
    });

    test('nothing saved, or an old list that will not parse, is no presets; '
        'a damaged entry does not take the others with it', () async {
      var prefs = await _prefs({});
      expect(SoundscapeStore(prefs).readPresets(), isEmpty);
      prefs = await _prefs({SoundscapeStore.legacyPresetsKey: '{not json'});
      expect(SoundscapeStore(prefs).readPresets(), isEmpty);
      expect(prefs.getString(SoundscapeStore.legacyPresetsKey), '{not json');
      prefs = await _prefs({
        SoundscapeStore.legacyPresetsKey: jsonEncode([
          {'name': 'No id', 'layers': _rain},
          'nonsense',
          {'id': 'user-2', 'name': 'Kept', 'layers': _stream},
        ]),
      });
      expect(SoundscapeStore(prefs).readPresets().single.name, 'Kept');
    });

    test(
      'a saved mix with no layers left keeps its place as a preset',
      () async {
        final prefs = await _prefs({
          SoundscapeStore.legacyPresetsKey: jsonEncode([
            {'id': 'user-1', 'name': 'Emptied'},
          ]),
        });
        final preset = SoundscapeStore(prefs).readPresets().single;
        expect(preset.name, 'Emptied');
        expect(preset.slots.filled, {PresetSlot.sound});
      },
    );
  });

  group('the tiles Home showed become pins', () {
    test('the two newest saved mixes, newest first', () async {
      final prefs = await _prefs({
        SoundscapeStore.legacyPresetsKey: jsonEncode([
          {'id': 'user-1', 'name': 'Oldest', 'layers': _rain},
          {'id': 'user-2', 'name': 'Middle', 'layers': _rain},
          {'id': 'user-3', 'name': 'Newest', 'layers': _stream},
        ]),
      });
      expect(SoundscapeStore(prefs).readPinnedPresets(), ['user-3', 'user-2']);
      expect(prefs.getStringList(SoundscapeStore.pinnedPresetsKey), [
        'user-3',
        'user-2',
      ]);
    });

    test('with one saved mix, it and the first built-in; with none, the '
        'first two built-in', () async {
      var prefs = await _prefs({
        SoundscapeStore.legacyPresetsKey: jsonEncode([
          {'id': 'user-1', 'name': 'Mine', 'layers': _rain},
        ]),
      });
      expect(SoundscapeStore(prefs).readPinnedPresets(), [
        'user-1',
        kStarterPresets[0].id,
      ]);
      prefs = await _prefs({});
      expect(SoundscapeStore(prefs).readPinnedPresets(), [
        kStarterPresets[0].id,
        kStarterPresets[1].id,
      ]);
    });

    test('a preset saved before Home is first shown is not mistaken for a '
        'tile Home used to show', () async {
      final prefs = await _prefs({});
      final store = SoundscapeStore(prefs);
      // The mixer reads the presets as the app starts.
      expect(store.readPresets(), isEmpty);
      store.writePresets([
        Preset.sound(id: 'user-1', name: 'New', mix: SoundMix.fromJson(_rain)),
      ]);
      expect(SoundscapeStore(prefs).readPinnedPresets(), [
        kStarterPresets[0].id,
        kStarterPresets[1].id,
      ]);
    });

    test('it runs once: unpinning everything stays unpinned, and a preset '
        'saved later is not pinned by itself', () async {
      final prefs = await _prefs({});
      final store = SoundscapeStore(prefs);
      expect(store.readPinnedPresets(), hasLength(2));
      store.writePinnedPresets(const []);
      store.writePresets([
        Preset.sound(id: 'user-1', name: 'New', mix: SoundMix.fromJson(_rain)),
      ]);
      expect(SoundscapeStore(prefs).readPinnedPresets(), isEmpty);
      expect(SoundscapeStore(prefs).readPinnedPresets(), isEmpty);
    });
  });

  test('deleting a bell swaps it for the default bell in the presets that '
      'rang it', () async {
    const made = 'custom-bell:0123456789abcdef';
    final preset = Preset(
      id: 'user-1',
      name: 'My bell sit',
      slots: PresetSlots(
        bells: PresetCues.bells(
          const CueSettings(startSound: made, endSound: made),
        ),
      ),
    );
    expect(preset.slots.bells!.asSettings.startSound, made);
    final prefs = await _prefs({});
    SoundscapeStore(prefs).writePresets([preset]);
    await CueSettingsStore(prefs).replaceSound(made, cueDefaultBell);
    final after = SoundscapeStore(prefs).readPresets().single;
    expect(after.slots.bells!.asSettings.startSound, cueDefaultBell);
    expect(after.slots.bells!.asSettings.endSound, cueDefaultBell);
    expect(after.name, 'My bell sit');
  });
}
