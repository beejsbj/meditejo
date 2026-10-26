import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';

/// How many sound presets Home offers as Timer starts.
const kHomePresetLimit = 2;

/// The presets Home shows as quick links, each starting the Timer with it
/// as the background: the user's own, newest first, then the built-in ones,
/// at most [kHomePresetLimit]. A placeholder rule (no choosing or pinning
/// yet); see DECISIONS 2026-10-26.
final homeSoundPresetsProvider = Provider<List<SoundPreset>>((ref) {
  final mine = ref.watch(soundscapeProvider.select((s) => s.userPresets));
  return [
    ...mine.reversed,
    ...kStarterPresets,
  ].take(kHomePresetLimit).toList(growable: false);
});
