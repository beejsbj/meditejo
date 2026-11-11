import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/home/widgets/shortcuts/shortcuts_section.dart';
import 'package:medito/views/soundscape/sounds_sheet.dart';
import 'package:medito/views/soundscape/sound_mix_panel.dart';

/// Home's Sounds tile: opens the Sounds sheet. While sounds play on their
/// own it names them (the preset, or the sounds of the mix) and takes the
/// accent, so Home shows what is in the air; a tap still opens the sheet.
class SoundsShortcutTile extends ConsumerWidget {
  const SoundsShortcutTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Only what the tile shows: the mixer changes with every slider.
    final playing = ref.watch(
      soundscapeProvider.select(
        (s) => s.owner == SoundscapeOwner.standalone && s.playing
            ? mixSummary(
                l10n,
                s,
                ref.read(soundLibraryProvider).value ?? SoundLibrary.empty,
              )
            : null,
      ),
    );
    return ShortcutTile(
      color: playing == null
          ? scheme.surfaceContainerHigh
          : scheme.primaryContainer,
      onColor: playing == null ? scheme.onSurface : scheme.onPrimaryContainer,
      icon: (color) => Icon(
        Symbols.graphic_eq_rounded,
        color: color,
        size: 24,
        fill: playing == null ? 0 : 1,
      ),
      label: l10n.backgroundSoundsSection,
      caption: playing,
      semanticsLabel: playing == null ? null : l10n.homeSoundsPlaying(playing),
      onTap: () => showSoundsSheet(context),
    );
  }
}
