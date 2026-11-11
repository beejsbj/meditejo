import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Params as the editors before #71 saved them: bands dragged by hand
/// (ints where a slider sat at an end), a beat off the half-hertz steps,
/// a root among the chips.
const _legacyLayers = [
  {
    'soundId': kSynthNoiseId,
    'volume': 0.5,
    'animate': true,
    'params': {
      'colour': 'white',
      'bands': [0, 0.25, 1, 0.8, 0.31, 0.6, 1, 0.4, 0.1, 0],
    },
  },
  {
    'soundId': kSynthDroneId,
    'volume': 0.4,
    'params': {'rootHz': 98.0, 'timbre': 'bright', 'movement': 0.73},
  },
  {
    'soundId': kSynthBinauralId,
    'volume': 0.3,
    'params': {'carrierHz': 231.4, 'beatHz': 6.37},
  },
];

void main() {
  group('beat bands', () {
    test('name the usual ranges, edges going up', () {
      expect(BeatBand.of(0.5), BeatBand.delta);
      expect(BeatBand.of(3.99), BeatBand.delta);
      expect(BeatBand.of(4), BeatBand.theta);
      expect(BeatBand.of(7.5), BeatBand.theta);
      expect(BeatBand.of(8), BeatBand.alpha);
      expect(BeatBand.of(12.9), BeatBand.alpha);
      expect(BeatBand.of(13), BeatBand.beta);
      expect(BeatBand.of(30), BeatBand.beta);
    });

    test('step by half a hertz, covering the whole range once', () {
      expect(BeatBand.theta.steps, [4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5]);
      expect(BeatBand.delta.steps.first, BinauralParams.minBeat);
      expect(BeatBand.beta.steps.last, BinauralParams.maxBeat);
      final all = [for (final b in BeatBand.values) ...b.steps];
      expect(all.toSet().length, all.length);
      for (var i = 1; i < all.length; i++) {
        expect(all[i] - all[i - 1], 0.5);
      }
      for (final band in BeatBand.values) {
        expect(BeatBand.of(band.centre), band);
        expect(band.steps, contains(band.centre));
        for (final hz in band.steps) {
          expect(BeatBand.of(hz), band, reason: '$hz');
        }
      }
    });

    test('the default beat is theta', () {
      expect(const BinauralParams().band, BeatBand.theta);
    });
  });

  group('noise bands', () {
    test('a curve saved with a mix is kept as it was', () {
      // The Stillness preset's highs fall away: the curve the "Soft" shape
      // chip once named. The chips are gone; the bands still say it.
      final stillness = kStarterPresets
          .firstWhere((p) => p.id == 'starter-stillness')
          .mix
          .layer(kSynthNoiseId)!;
      final bands = NoiseParams.fromJson(stillness.params).bands;
      expect(bands, [1, 1, 1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3]);
      expect(NoiseParams.fromJson(stillness.params).toJson(), {
        'colour': NoiseParams.fromJson(stillness.params).colour.name,
        'bands': bands,
      });
    });

    test('a curve drawn by hand round-trips', () {
      final legacy = _legacyLayers.first['params']! as Map<String, Object?>;
      final params = NoiseParams.fromJson(legacy);
      expect(NoiseParams.fromJson(params.toJson()).bands, params.bands);
    });
  });

  group('saved params from before #71', () {
    // The params' JSON did not change shape, so nothing migrates: these
    // pin that what was saved reads, plays and saves back as it was.

    test('presets, the mix and a session\'s layers: read and write back '
        'unchanged', () async {
      final mix = {'layers': _legacyLayers};
      final presets = [
        {'id': 'p1', 'name': 'Mine', 'layers': mix['layers']},
      ];
      SharedPreferences.setMockInitialValues({
        SoundscapeStore.mixKey: jsonEncode(mix['layers']),
        SoundscapeStore.presetsKey: jsonEncode(presets),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SoundscapeStore(prefs);

      final readMix = store.readMix()!;
      final readPresets = store.readPresets();
      expect(readPresets.single.mix, readMix);
      store
        ..writeMix(readMix)
        ..writePresets(readPresets);
      expect(
        jsonDecode(prefs.getString(SoundscapeStore.mixKey)!),
        jsonDecode(jsonEncode(mix['layers'])),
      );
      expect(
        jsonDecode(prefs.getString(SoundscapeStore.presetsKey)!),
        jsonDecode(jsonEncode(presets)),
      );

      final selection = SoundscapeSelection.layers(readMix).encode();
      expect(SoundscapeSelection.parse(selection).mix, readMix);
      expect(SoundscapeSelection.parse(selection).encode(), selection);
    });

    test('they sound as they did: the same voices and noise spectrum', () {
      final layers = SoundMix.fromJson(_legacyLayers).layers;
      final noise = NoiseParams.fromJson(layers[0].params);
      expect(noise.colour, NoiseColour.white);
      expect(noise.bands, [0, 0.25, 1, 0.8, 0.31, 0.6, 1, 0.4, 0.1, 0]);
      final drone = DroneParams.fromJson(layers[1].params);
      expect(drone.rootHz, 98);
      expect(drone.rootsHz, [98]);
      // Saved again, it still names the old key and gains the chord's.
      expect(drone.toJson()['rootHz'], 98);
      expect(DroneParams.fromJson(drone.toJson()).rootsHz, [98]);
      expect(drone.timbre, DroneTimbre.bright);
      expect(drone.movement, 0.73);
      final binaural = BinauralParams.fromJson(layers[2].params);
      expect(binaural.carrierHz, 231.4);
      expect(binaural.beatHz, 6.37);
      expect(binaural.band, BeatBand.theta);
      // The voices come from the params alone: a round trip through JSON
      // makes the same ones.
      expect(
        DroneParams.fromJson(
          jsonDecode(jsonEncode(drone.toJson())) as Map<String, Object?>,
        ).partials(),
        drone.partials(),
      );
      expect(
        BinauralParams.fromJson(
          jsonDecode(jsonEncode(binaural.toJson())) as Map<String, Object?>,
        ).partials(),
        binaural.partials(),
      );
    });
  });
}
