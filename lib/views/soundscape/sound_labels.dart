import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/synth.dart';

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

/// A sound's Material Symbol, shared by its shelf. A null [category] is
/// the generated shelf (noise, drone, binaural beats). The art itself comes
/// from the art engine (`ArtSubject.sound`).
class SoundLook {
  const SoundLook(this.icon);

  final IconData icon;

  static SoundLook forCategory(SoundCategory? category) => switch (category) {
    SoundCategory.rain => const SoundLook(Symbols.rainy_rounded),
    SoundCategory.water => const SoundLook(Symbols.water_rounded),
    SoundCategory.wind => const SoundLook(Symbols.air_rounded),
    SoundCategory.forest => const SoundLook(Symbols.forest_rounded),
    SoundCategory.fire => const SoundLook(
      Symbols.local_fire_department_rounded,
    ),
    SoundCategory.room => const SoundLook(Symbols.chair_rounded),
    SoundCategory.night => const SoundLook(Symbols.bedtime_rounded),
    null => const SoundLook(Symbols.graphic_eq_rounded),
  };

  /// One sound: its shelf's icon, and for a generated layer its own.
  static SoundLook forSound(String soundId, SoundLibrary library) {
    if (isSynthId(soundId)) {
      return SoundLook(switch (soundId) {
        kSynthNoiseId => Symbols.grain_rounded,
        kSynthDroneId => Symbols.waves_rounded,
        _ => Symbols.headphones_rounded,
      });
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
