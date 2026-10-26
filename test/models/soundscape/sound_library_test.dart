import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/soundscape/synth.dart';

/// Checks the bundled library as shipped: what the processing script wrote
/// into assets/sounds/ is what the app can read, credit and play.
void main() {
  final json =
      jsonDecode(File('assets/sounds/sounds.json').readAsStringSync())
          as Map<String, Object?>;
  final library = SoundLibrary.fromJson(json);
  final raw = (json['sounds'] as List).cast<Map<String, Object?>>();

  test('every entry parses, with an allowed licence and a category', () {
    expect(library.sounds, hasLength(raw.length));
    expect(library.sounds.length, inInclusiveRange(15, 25));
    for (final sound in library.sounds) {
      expect(sound.author, isNotEmpty, reason: sound.id);
      expect(sound.sourceUrl, startsWith('https://'), reason: sound.id);
      expect(sound.modifications, isNotEmpty, reason: sound.id);
    }
  });

  test('every asset exists and the library fits the 15 MB budget', () {
    var total = 0;
    for (final sound in library.sounds) {
      final file = File(sound.asset);
      expect(file.existsSync(), isTrue, reason: sound.asset);
      total += file.lengthSync();
    }
    expect(total, lessThanOrEqualTo(15 * 1000 * 1000));
    expect(total, json['totalBytes']);
  });

  test('no orphan files ship beside the library', () {
    final listed = {for (final s in library.sounds) s.asset};
    final shipped = Directory('assets/sounds')
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.opus'))
        .toSet();
    expect(shipped, listed);
  });

  test('loudness was measured near the -27 LUFS target', () {
    for (final entry in raw) {
      final after =
          (entry['processing'] as Map)['measuredAfter'] as Map<String, Object?>;
      // Peaky sounds may sit below the target (true-peak ceiling), never
      // well above it.
      expect(after['lufs'] as num, lessThan(-25), reason: '${entry['id']}');
      expect(after['lufs'] as num, greaterThan(-42), reason: '${entry['id']}');
    }
  });

  test('NOTICE credits every file', () {
    final notice = File('assets/sounds/NOTICE').readAsStringSync();
    expect(notice, contains('not'));
    expect(notice, contains('AGPL'));
    for (final sound in library.sounds) {
      expect(notice, contains(sound.asset.split('/').last));
      expect(notice, contains(sound.sourceUrl));
    }
  });

  test('every starter preset plays only sounds in the library', () {
    expect(kStarterPresets.length, inInclusiveRange(3, 5));
    for (final preset in kStarterPresets) {
      expect(preset.builtIn, isTrue);
      for (final layer in preset.mix.layers) {
        expect(
          library.contains(layer.soundId) || isSynthId(layer.soundId),
          isTrue,
          reason: '${preset.id}: ${layer.soundId}',
        );
      }
    }
  });

  test('an entry with an unvetted licence or category is dropped', () {
    final lib = SoundLibrary.fromJson({
      'sounds': [
        {
          'id': 'ok',
          'category': 'rain',
          'asset': 'a.opus',
          'license': {'spdx': 'CC0-1.0'},
        },
        {
          'id': 'sa',
          'category': 'rain',
          'asset': 'b.opus',
          'license': {'spdx': 'CC-BY-SA-3.0'},
        },
        {
          'id': 'nc',
          'category': 'rain',
          'asset': 'c.opus',
          'license': {'spdx': 'CC-BY-NC-4.0'},
        },
        {
          'id': 'odd',
          'category': 'space',
          'asset': 'd.opus',
          'license': {'spdx': 'CC0-1.0'},
        },
      ],
    });
    expect(lib.sounds.map((s) => s.id), ['ok']);
  });

  group('selection grammar', () {
    test('round-trips and defaults to the current mix', () {
      for (final value in [
        'mix',
        'none',
        'preset:starter-night',
        'sound:stream',
      ]) {
        expect(SoundscapeSelection.parse(value).encode(), value);
      }
      expect(SoundscapeSelection.parse(''), SoundscapeSelection.currentMix);
      expect(SoundscapeSelection.parse(null), SoundscapeSelection.currentMix);
      expect(
        SoundscapeSelection.parse('preset:'),
        SoundscapeSelection.currentMix,
      );
    });
  });

  group('session defaults (decisions 8 and 17)', () {
    test('nothing is chosen for practice or talks', () {
      expect(
        SoundscapeSessionDefault.initial(
          SoundscapeSessionKind.practice,
        ).enabled,
        isFalse,
      );
      expect(
        SoundscapeSessionDefault.initial(SoundscapeSessionKind.talks).enabled,
        isFalse,
      );
    });

    test('a damaged value falls back to the kind default', () {
      final value = SoundscapeSessionDefault.fromJson({
        'enabled': 'yes',
        'volume': 7,
      }, SoundscapeSessionKind.talks);
      expect(value.enabled, isFalse);
      expect(value.volume, 1.0);
    });
  });

  test('a mix keeps one layer per sound and at most kMaxLayers', () {
    final mix = SoundMix.fromJson([
      for (var i = 0; i < 9; i++) {'soundId': 's${i % 8}', 'volume': 0.5},
    ]);
    expect(mix.layers.length, SoundMix.kMaxLayers);
    expect(mix.layers.map((l) => l.soundId).toSet().length, mix.layers.length);
  });
}
