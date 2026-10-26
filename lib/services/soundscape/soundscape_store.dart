import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/soundscape/sound_mix.dart';

/// Remembers the mixer: the current mix, the user's presets, the Sounds
/// volume and what plays under each kind of session. Plain JSON in shared
/// preferences; a value that won't parse reads as unset.
class SoundscapeStore {
  SoundscapeStore(this._prefs);

  static const mixKey = 'soundscape_mix';
  static const presetsKey = 'soundscape_presets';
  static const volumeKey = 'soundscape_volume';
  static const sessionDefaultsKey = 'soundscape_session_defaults';
  static const sessionDefaultsVersionKey =
      'soundscape_session_defaults_version';
  static const _sessionDefaultsVersion = 2;

  final SharedPreferences _prefs;

  /// `null` before the user has ever touched the mixer.
  SoundMix? readMix() {
    final raw = _decode(mixKey);
    return raw == null ? null : SoundMix.fromJson(raw);
  }

  void writeMix(SoundMix mix) =>
      unawaited(_prefs.setString(mixKey, jsonEncode(mix.toJson())));

  List<SoundPreset> readPresets() {
    final raw = _decode(presetsKey);
    if (raw is! List) return const [];
    return [for (final item in raw) ?SoundPreset.tryFromJson(item)];
  }

  void writePresets(List<SoundPreset> presets) => unawaited(
    _prefs.setString(
      presetsKey,
      jsonEncode([
        for (final p in presets)
          if (!p.builtIn) p.toJson(),
      ]),
    ),
  );

  double readVolume() => (_prefs.getDouble(volumeKey) ?? 0.7).clamp(0.0, 1.0);

  void writeVolume(double volume) =>
      unawaited(_prefs.setDouble(volumeKey, volume));

  /// Practice used to start on with the current mix (decision 8) and now
  /// starts with nothing chosen (decision 17). A device that never touched the
  /// setting must follow, but the stored value cannot always say so: changing
  /// Talks' level, switching Talks, or deleting a preset rewrites both kinds,
  /// Practice's included, at its old factory value.
  ///
  /// So Practice moves to "nothing" only when it is *exactly* that old factory
  /// value (on, the current mix, level 0.5) and no sound was ever put in the
  /// mixer. Any other stored Practice (a different level, a preset or a single
  /// sound, an explicit off) or a mix the user built stays as it was: a sound
  /// someone may have chosen is never taken away. The one case the data cannot
  /// separate is a user who switched Practice on with the starter mix, left
  /// every level alone and never opened the mixer; they move too, and one tap
  /// in Customize puts the sound back.
  ///
  /// Runs once: the version key stops it from undoing a later explicit choice.
  void migrateSessionDefaults() {
    if ((_prefs.getInt(sessionDefaultsVersionKey) ?? 1) >=
        _sessionDefaultsVersion) {
      return;
    }
    unawaited(
      _prefs.setInt(sessionDefaultsVersionKey, _sessionDefaultsVersion),
    );
    final raw = _decode(sessionDefaultsKey);
    if (raw is! Map) return;
    final stored = raw[SoundscapeSessionKind.practice.name];
    if (stored is! Map) return;
    final mix = readMix();
    final untouched =
        stored['enabled'] == true &&
        SoundscapeSelection.parse(
              stored['selection'] is String
                  ? stored['selection'] as String
                  : null,
            ) ==
            SoundscapeSelection.currentMix &&
        (stored['volume'] ?? 0.5) == 0.5 &&
        (mix == null || mix.isEmpty);
    if (!untouched) return;
    unawaited(
      _prefs.setString(
        sessionDefaultsKey,
        jsonEncode({
          ...raw,
          SoundscapeSessionKind.practice.name: {...stored, 'enabled': false},
        }),
      ),
    );
  }

  Map<SoundscapeSessionKind, SoundscapeSessionDefault> readSessionDefaults() {
    final raw = _decode(sessionDefaultsKey);
    return {
      for (final kind in SoundscapeSessionKind.values)
        kind: SoundscapeSessionDefault.fromJson(
          raw is Map ? raw[kind.name] : null,
          kind,
        ),
    };
  }

  void writeSessionDefaults(
    Map<SoundscapeSessionKind, SoundscapeSessionDefault> defaults,
  ) => unawaited(
    _prefs.setString(
      sessionDefaultsKey,
      jsonEncode({
        for (final e in defaults.entries) e.key.name: e.value.toJson(),
      }),
    ),
  );

  Object? _decode(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}
