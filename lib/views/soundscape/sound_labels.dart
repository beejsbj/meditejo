import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/widgets/generated_artwork.dart';

/// Localised names for the shelves of the library.
String soundCategoryLabel(AppLocalizations l10n, SoundCategory category) =>
    switch (category) {
      SoundCategory.rain => l10n.soundCategoryRain,
      SoundCategory.water => l10n.soundCategoryWater,
      SoundCategory.wind => l10n.soundCategoryWind,
      SoundCategory.forest => l10n.soundCategoryForest,
      SoundCategory.fire => l10n.soundCategoryFire,
      SoundCategory.room => l10n.soundCategoryRoom,
      SoundCategory.night => l10n.soundCategoryNight,
    };

/// Built-in presets carry English names in code; show them localised.
String soundPresetLabel(AppLocalizations l10n, SoundPreset preset) =>
    switch (preset.id) {
      'starter-rain-forest' => l10n.soundPresetRainForest,
      'starter-night' => l10n.soundPresetNight,
      'starter-hearth' => l10n.soundPresetHearth,
      'starter-shore' => l10n.soundPresetShore,
      'starter-stillness' => l10n.soundPresetStillness,
      _ => preset.name,
    };

/// How a sound looks on its card: a Material Symbol and the generated
/// art's colours, shared by its shelf. A null [category] is the generated
/// shelf (noise, drone, binaural beats).
class SoundLook {
  const SoundLook(this.icon, this.colors);

  final IconData icon;
  final (Color, Color) colors;

  static (Color, Color) _palette(int i) => GeneratedArtwork.palette[i];

  static SoundLook forCategory(SoundCategory? category) => switch (category) {
    SoundCategory.rain => SoundLook(Symbols.rainy_rounded, _palette(1)),
    SoundCategory.water => SoundLook(Symbols.water_rounded, _palette(6)),
    SoundCategory.wind => SoundLook(Symbols.air_rounded, _palette(0)),
    SoundCategory.forest => SoundLook(Symbols.forest_rounded, _palette(5)),
    SoundCategory.fire => SoundLook(
      Symbols.local_fire_department_rounded,
      _palette(2),
    ),
    SoundCategory.room => SoundLook(Symbols.chair_rounded, _palette(4)),
    SoundCategory.night => SoundLook(Symbols.bedtime_rounded, _palette(3)),
    null => SoundLook(Symbols.graphic_eq_rounded, _palette(7)),
  };

  /// One sound: its shelf's colours, and for a generated layer its own icon.
  static SoundLook forSound(String soundId, SoundLibrary library) {
    if (isSynthId(soundId)) {
      return SoundLook(switch (soundId) {
        kSynthNoiseId => Symbols.grain_rounded,
        kSynthDroneId => Symbols.waves_rounded,
        _ => Symbols.headphones_rounded,
      }, forCategory(null).colors);
    }
    return forCategory(library[soundId]?.category);
  }
}

/// A layer's display name: the synth's localised title or the recording's.
/// Null for a sound this build's library no longer has.
String? soundTitle(
  AppLocalizations l10n,
  String soundId,
  SoundLibrary library,
) => isSynthId(soundId) ? synthTitle(l10n, soundId) : library[soundId]?.title;

String synthTitle(AppLocalizations l10n, String id) => switch (id) {
  kSynthNoiseId => l10n.synthNoise,
  kSynthDroneId => l10n.synthDrone,
  kSynthBinauralId => l10n.synthBinaural,
  _ => id,
};
