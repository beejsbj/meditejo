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
