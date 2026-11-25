import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/presets/preset.dart';
import '../../models/soundscape/sound_mix.dart';
import '../../models/soundscape/starter_presets.dart';

/// Remembers the mixer: the current mix, the user's presets, the Sounds
/// volume and what plays under each kind of session. Plain JSON in shared
/// preferences; a value that won't parse reads as unset.
class SoundscapeStore {
  SoundscapeStore(this._prefs);

  static const mixKey = 'soundscape_mix';

  /// The user's presets (#64): a list of [Preset.toJson].
  static const presetsKey = 'presets.v1';

  /// Where saved mixes were kept before #64. Read once, to become
  /// [presetsKey], and then left as it is: an older build still finds its
  /// mixes there.
  static const legacyPresetsKey = 'soundscape_presets';

  /// The presets pinned to Home, oldest pin first.
  static const pinnedPresetsKey = 'presets.pinned';

  /// Which preset was last loaded in each place (see `PresetContext`).
  static const loadedPresetsKey = 'presets.loaded';

  /// How many preset tiles Home showed by itself before presets were pinned.
  static const _legacyHomeTiles = 2;
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

  /// The user's presets. The first read after #64 turns every saved mix
  /// into a preset holding only its Sound slot, under the same id (so
  /// `preset:<id>` choices still resolve), and writes [presetsKey]; from
  /// then on the old list is not read again.
  List<Preset> readPresets() {
    if (!_prefs.containsKey(presetsKey)) {
      final legacy = _decode(legacyPresetsKey);
      final migrated = [
        if (legacy is List)
          for (final item in legacy) ?_fromSavedMix(item),
      ];
      writePresets(migrated);
      // With them, the tiles Home showed: pinned now, before anything new
      // is saved and would look like one of them.
      if (!_prefs.containsKey(pinnedPresetsKey)) {
        writePinnedPresets(_legacyHomePins(migrated));
      }
      return migrated;
    }
    final raw = _decode(presetsKey);
    if (raw is! List) return const [];
    return [for (final item in raw) ?Preset.tryFromJson(item)];
  }

  static Preset? _fromSavedMix(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String || id.isEmpty) return null;
    return Preset.sound(
      id: id,
      name: name,
      mix: SoundMix.fromJson(json['layers']),
    );
  }

  void writePresets(List<Preset> presets) => unawaited(
    _prefs.setString(
      presetsKey,
      jsonEncode([
        for (final p in presets)
          if (!p.builtIn) p.toJson(),
      ]),
    ),
  );

  /// The ids of the presets pinned to Home. Before pinning, Home showed two
  /// preset tiles by itself (the newest saved mixes, then the built-in
  /// ones): the first read pins exactly those, so Home keeps them, and
  /// writes [pinnedPresetsKey] so it happens once.
  List<String> readPinnedPresets() {
    final saved = _prefs.getStringList(pinnedPresetsKey);
    if (saved != null) return saved.toSet().toList();
    final presets = readPresets();
    final migrated = _prefs.getStringList(pinnedPresetsKey);
    if (migrated != null) return migrated;
    final seen = _legacyHomePins(presets);
    writePinnedPresets(seen);
    return seen;
  }

  static List<String> _legacyHomePins(List<Preset> saved) => [
    ...saved.reversed,
    ...kStarterPresets,
  ].take(_legacyHomeTiles).map((p) => p.id).toList();

  void writePinnedPresets(List<String> ids) =>
      unawaited(_prefs.setStringList(pinnedPresetsKey, ids));

  Map<String, String> readLoadedPresets() {
    final raw = _decode(loadedPresetsKey);
    return {
      if (raw is Map)
        for (final MapEntry(:key, :value) in raw.entries)
          if (key is String && value is String) key: value,
    };
  }

  void writeLoadedPresets(Map<String, String> loaded) =>
      unawaited(_prefs.setString(loadedPresetsKey, jsonEncode(loaded)));

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
  /// in Customize puts the sound back. A user with a built mix but no Practice
  /// setting stored (nothing ever rewrote it) is pinned to the old default
  /// explicitly, so the mix keeps playing.
  ///
  /// Runs once: the version key stops it from undoing a later explicit choice.
  ///
  /// The version key is written only after the Practice setting has been saved
  /// (and only if that save succeeded), so a failed save leaves the next launch
  /// to try again. The setting is written first and synchronously as far as the
  /// preferences cache goes, so a read right after this call already sees it.
  Future<void> migrateSessionDefaults() async {
    if ((_prefs.getInt(sessionDefaultsVersionKey) ?? 1) >=
        _sessionDefaultsVersion) {
      return;
    }
    final migrated = _migratedSessionDefaults();
    if (migrated != null &&
        !await _prefs.setString(sessionDefaultsKey, migrated)) {
      // The plugin keeps the value in its cache even when the save failed: a
      // later call in this process would find nothing left to migrate and
      // write the version without the setting. Drop the cache's copy.
      await _prefs.reload();
      return;
    }
    await _prefs.setInt(sessionDefaultsVersionKey, _sessionDefaultsVersion);
  }

  /// The session-defaults JSON the migration wants stored, or `null` when the
  /// stored value already stands.
  String? _migratedSessionDefaults() {
    final decoded = _decode(sessionDefaultsKey);
    final raw = decoded is Map ? decoded : const <Object?, Object?>{};
    final stored = raw[SoundscapeSessionKind.practice.name];
    final mix = readMix();
    if (stored is! Map) {
      // Nothing stored for Practice, so it followed the old factory default
      // (on, the current mix). Someone who built a mix has been hearing it
      // under every session: keep that explicit before the new default (off)
      // would silently drop it.
      if (mix != null && !mix.isEmpty) {
        return jsonEncode({
          ...raw,
          SoundscapeSessionKind.practice.name: const SoundscapeSessionDefault(
            enabled: true,
          ).toJson(),
        });
      }
      return null;
    }
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
    if (!untouched) return null;
    return jsonEncode({
      ...raw,
      SoundscapeSessionKind.practice.name: {...stored, 'enabled': false},
    });
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
