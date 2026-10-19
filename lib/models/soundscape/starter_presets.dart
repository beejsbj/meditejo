import 'sound_mix.dart';

/// Presets that ship with the app. The first is the mix a fresh install
/// plays under practice (decision 8) until the user makes their own.
///
/// Sound ids are those in `assets/sounds/sounds.json`; a layer whose sound is
/// missing is skipped when the preset plays.
const kStarterPresets = <SoundPreset>[
  SoundPreset(
    id: 'starter-rain-forest',
    name: 'Rain on the forest',
    builtIn: true,
    mix: SoundMix([
      SoundLayer(soundId: 'rain-terrace', volume: 0.7),
      SoundLayer(soundId: 'forest-birds', volume: 0.45, animate: true),
      SoundLayer(soundId: 'wind-trees', volume: 0.3, animate: true),
    ]),
  ),
  SoundPreset(
    id: 'starter-night',
    name: 'Night',
    builtIn: true,
    mix: SoundMix([
      SoundLayer(soundId: 'night-meadow', volume: 0.6),
      SoundLayer(soundId: 'stream', volume: 0.35, animate: true),
    ]),
  ),
  SoundPreset(
    id: 'starter-hearth',
    name: 'Hearth',
    builtIn: true,
    mix: SoundMix([
      SoundLayer(soundId: 'fire-stove', volume: 0.6),
      SoundLayer(soundId: 'fire-crackle', volume: 0.55, animate: true),
      SoundLayer(soundId: 'rain-window', volume: 0.4, animate: true),
    ]),
  ),
  SoundPreset(
    id: 'starter-shore',
    name: 'Shore',
    builtIn: true,
    mix: SoundMix([
      SoundLayer(soundId: 'waves', volume: 0.7, animate: true),
      SoundLayer(soundId: 'wind-grass', volume: 0.3),
    ]),
  ),
];
