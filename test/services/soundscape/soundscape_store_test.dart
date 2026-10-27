import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences that log writes in order and can refuse the session-defaults
/// save, as a full disk or a platform error would.
class _Prefs extends Fake implements SharedPreferences {
  _Prefs(this._inner);

  final SharedPreferences _inner;
  final writes = <String>[];
  bool failDefaults = false;

  /// Like the plugin, a save that fails still lands in the cache, until the
  /// cache is reloaded from disk.
  final _cacheOnly = <String, String>{};

  @override
  int? getInt(String key) => _inner.getInt(key);

  @override
  String? getString(String key) => _cacheOnly[key] ?? _inner.getString(key);

  @override
  Future<void> reload() async => _cacheOnly.clear();

  @override
  Future<bool> setInt(String key, int value) async {
    writes.add(key);
    return _inner.setInt(key, value);
  }

  @override
  Future<bool> setString(String key, String value) async {
    if (key == SoundscapeStore.sessionDefaultsKey && failDefaults) {
      _cacheOnly[key] = value;
      return false;
    }
    writes.add(key);
    return _inner.setString(key, value);
  }
}

// Practice as every install had it before decision 17: on, the current mix.
final _oldFactory = jsonEncode({
  'practice': {'enabled': true, 'selection': 'mix', 'volume': 0.5},
});

Future<_Prefs> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return _Prefs(await SharedPreferences.getInstance());
}

bool _practiceEnabled(SharedPreferences prefs) {
  final raw = jsonDecode(prefs.getString(SoundscapeStore.sessionDefaultsKey)!);
  return (raw as Map)['practice']['enabled'] as bool;
}

void main() {
  group('migrateSessionDefaults', () {
    test('saves the Practice setting before it writes the version', () async {
      final prefs = await _prefs({
        SoundscapeStore.sessionDefaultsKey: _oldFactory,
      });
      await SoundscapeStore(prefs).migrateSessionDefaults();
      expect(prefs.writes, [
        SoundscapeStore.sessionDefaultsKey,
        SoundscapeStore.sessionDefaultsVersionKey,
      ]);
      expect(_practiceEnabled(prefs), isFalse);
      expect(prefs.getInt(SoundscapeStore.sessionDefaultsVersionKey), 2);
    });

    test('a read right after the call already sees the new setting', () async {
      final prefs = await _prefs({
        SoundscapeStore.sessionDefaultsKey: _oldFactory,
      });
      final store = SoundscapeStore(prefs);
      final done = store.migrateSessionDefaults();
      expect(
        store.readSessionDefaults()[SoundscapeSessionKind.practice]?.enabled,
        isFalse,
      );
      await done;
    });

    test('a failed save leaves the version unwritten, so a later launch '
        'tries again', () async {
      final prefs =
          await _prefs({SoundscapeStore.sessionDefaultsKey: _oldFactory})
            ..failDefaults = true;
      await SoundscapeStore(prefs).migrateSessionDefaults();
      expect(prefs.getInt(SoundscapeStore.sessionDefaultsVersionKey), isNull);
      expect(prefs.writes, isEmpty);

      prefs.failDefaults = false;
      await SoundscapeStore(prefs).migrateSessionDefaults();
      expect(_practiceEnabled(prefs), isFalse);
      expect(prefs.getInt(SoundscapeStore.sessionDefaultsVersionKey), 2);
    });

    test('a failed save is not forgotten by a second call in the same '
        'process', () async {
      final prefs =
          await _prefs({SoundscapeStore.sessionDefaultsKey: _oldFactory})
            ..failDefaults = true;
      final store = SoundscapeStore(prefs);
      await store.migrateSessionDefaults();
      // The controller can be rebuilt in the same process: it must try again,
      // not find the cache already migrated and write the version.
      prefs.failDefaults = false;
      await store.migrateSessionDefaults();
      expect(_practiceEnabled(prefs), isFalse);
      expect(prefs.getInt(SoundscapeStore.sessionDefaultsVersionKey), 2);
      expect(prefs.writes, [
        SoundscapeStore.sessionDefaultsKey,
        SoundscapeStore.sessionDefaultsVersionKey,
      ]);
    });

    test('a setting that needs no move still gets its version', () async {
      final prefs = await _prefs({
        SoundscapeStore.mixKey: jsonEncode(
          SoundMix([SoundLayer(soundId: 'a')]).toJson(),
        ),
        SoundscapeStore.sessionDefaultsKey: jsonEncode({
          'practice': {'enabled': true, 'selection': 'mix', 'volume': 0.8},
        }),
      });
      final done = SoundscapeStore(prefs).migrateSessionDefaults();
      // No setting to save first: the version is written without a wait.
      expect(prefs.getInt(SoundscapeStore.sessionDefaultsVersionKey), 2);
      await done;
      expect(prefs.writes, [SoundscapeStore.sessionDefaultsVersionKey]);
      expect(_practiceEnabled(prefs), isTrue);
    });

    test('runs once', () async {
      final prefs = await _prefs({
        SoundscapeStore.sessionDefaultsKey: _oldFactory,
      });
      final store = SoundscapeStore(prefs);
      await store.migrateSessionDefaults();
      prefs.writes.clear();
      await store.migrateSessionDefaults();
      expect(prefs.writes, isEmpty);
    });
  });
}
