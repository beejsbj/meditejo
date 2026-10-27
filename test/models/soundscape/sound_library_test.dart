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
    expect(library.sounds.length, inInclusiveRange(15, 40));
    for (final sound in library.sounds) {
      expect(sound.author, isNotEmpty, reason: sound.id);
      expect(sound.sourceUrl, startsWith('https://'), reason: sound.id);
      expect(sound.modifications, isNotEmpty, reason: sound.id);
    }
  });

  test('every bundled asset exists, and the APK carries only those', () {
    var bundled = 0;
    for (final sound in library.sounds.where((s) => s.bundled)) {
      final file = File(sound.asset);
      expect(file.existsSync(), isTrue, reason: sound.asset);
      expect(file.lengthSync(), sound.bytes, reason: sound.id);
      bundled += file.lengthSync();
    }
    // The point of the sound pack: the APK holds the core set, not the library.
    expect(bundled, lessThanOrEqualTo(6 * 1024 * 1024));
    expect(bundled, json['bundledBytes']);
    final total = library.sounds.fold<int>(0, (n, s) => n + s.bytes);
    expect(total, json['totalBytes']);
    expect(total - bundled, json['packBytes']);
  });

  test('no orphan files ship beside the library, and none of the pack', () {
    final listed = {
      for (final s in library.sounds)
        if (s.bundled) s.asset,
    };
    final shipped = Directory('assets/sounds')
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.opus'))
        .toSet();
    expect(shipped, listed);
  });

  group('the sound pack', () {
    test('has sounds, pinned to a release the updater never reads', () {
      expect(library.packSounds, isNotEmpty);
      expect(library.pack, isNotNull);
      // `sounds-YYYYMMDD[-n]` is not a `vX.Y.Z` app release, and the repository
      // marks it a prerelease.
      expect(library.pack!.release, matches(RegExp(r'^sounds-\d{8}(-\d+)?$')));
    });

    test('every pack sound pins its bytes, and downloads from the release', () {
      for (final sound in library.packSounds) {
        expect(sound.bytes, greaterThan(10000), reason: sound.id);
        expect(
          sound.sha256,
          matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: sound.id,
        );
        expect(sound.file, '${sound.id}.opus');
        expect(
          library.pack!.urlFor(sound).toString(),
          'https://github.com/beejsbj/meditejo/releases/download/'
          '${library.pack!.release}/${sound.file}',
        );
      }
    });

    test('a pack sound without a pinned hash and size is not offered', () {
      SoundLibrary parse(Map<String, Object?> extra) => SoundLibrary.fromJson({
        'sounds': [
          {
            'id': 'far',
            'category': 'rain',
            'license': {'spdx': 'CC0-1.0'},
            'bundled': false,
            ...extra,
          },
        ],
      });
      expect(parse({}).sounds, isEmpty);
      expect(parse({'sha256': 'abc', 'bytes': 5}).sounds, isEmpty);
      expect(parse({'sha256': 'a' * 64, 'bytes': 0}).sounds, isEmpty);
      expect(parse({'sha256': 'a' * 64, 'bytes': 5}).sounds, hasLength(1));
    });

    test('a pin that is not a sounds release is ignored', () {
      for (final release in ['v0.1.4', 'catalogue-20261019', 'sounds-1', '']) {
        expect(SoundPackPin.tryFromJson({'release': release}), isNull);
      }
      expect(SoundPackPin.tryFromJson(null), isNull);
    });

    test('the presets work offline: every layer is bundled', () {
      for (final preset in kStarterPresets) {
        for (final layer in preset.mix.layers) {
          if (isSynthId(layer.soundId)) continue;
          expect(
            library[layer.soundId]!.bundled,
            isTrue,
            reason: '${preset.id}: ${layer.soundId}',
          );
        }
      }
    });

    test('every shelf has a sound that is bundled', () {
      for (final category in library.categories) {
        expect(
          library.inCategory(category).any((s) => s.bundled),
          isTrue,
          reason: category.name,
        );
      }
    });
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

  test('NOTICE credits every sound, downloaded or not', () {
    final notice = File('assets/sounds/NOTICE').readAsStringSync();
    expect(notice, contains('not'));
    expect(notice, contains('AGPL'));
    for (final sound in library.sounds) {
      expect(notice, contains(sound.file));
      expect(notice, contains(sound.sourceUrl));
    }
  });

  test('a CC BY sound is credited in full, and only CC0 or CC BY ships', () {
    final notice = File('assets/sounds/NOTICE').readAsStringSync();
    for (final sound in library.sounds) {
      expect(
        {SoundLicense.cc0, SoundLicense.ccBy3, SoundLicense.ccBy4},
        contains(sound.license),
        reason: '${sound.id}: ${sound.license.spdx}',
      );
      if (!sound.license.requiresAttribution) continue;
      // CC BY: who, what, where, under which licence, and what was changed.
      for (final credit in [
        sound.originalTitle,
        sound.author,
        sound.authorUrl,
        sound.sourceUrl,
        sound.license.label,
        sound.license.url,
        sound.modifications,
      ]) {
        expect(credit, isNotEmpty, reason: sound.id);
        expect(notice, contains(credit), reason: '${sound.id}: $credit');
      }
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
