import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/soundscape/sound_mix_panel.dart';
import 'package:medito/views/soundscape/sounds_sheet.dart';

/// Room a tab keeps clear at the foot of its scrolling content, so the last
/// row's action scrolls out from under the [SoundsButton] (a 56 dp button
/// 16 dp above the nav bar, and a little air).
const kSoundsButtonClearance = 80.0;

/// The one way to Sounds from the tabs (pass 4: "Sounds should be one
/// floating button reachable from anywhere"), bottom right over Home,
/// Explore, Library and Settings. It opens the Sounds sheet on the user's
/// own mix. While that mix plays on its own it is filled and its record
/// turns, and a screen reader hears what plays.
class SoundsButton extends ConsumerStatefulWidget {
  const SoundsButton({super.key});

  @override
  ConsumerState<SoundsButton> createState() => _SoundsButtonState();
}

class _SoundsButtonState extends ConsumerState<SoundsButton>
    with SingleTickerProviderStateMixin {
  // 33⅓ rpm, as the player's sound button turns.
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Only what the button says: the mixer changes with every slider.
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
    final turning = playing != null && !MediaQuery.disableAnimationsOf(context);
    if (turning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!turning && _spin.isAnimating) {
      _spin.stop();
    }
    return FloatingActionButton(
      key: const ValueKey('sounds_button'),
      heroTag: null,
      tooltip: playing == null
          ? l10n.backgroundSoundsSection
          : l10n.homeSoundsPlaying(playing),
      backgroundColor: playing == null
          ? scheme.surfaceContainerHigh
          : scheme.primary,
      foregroundColor: playing == null ? scheme.onSurface : scheme.onPrimary,
      elevation: 2,
      onPressed: () => showSoundsSheet(context),
      child: playing == null
          ? const Icon(Symbols.graphic_eq_rounded, key: ValueKey('idle'))
          : RotationTransition(
              key: const ValueKey('sounds_button_playing'),
              turns: _spin,
              child: const Icon(Symbols.album_rounded, fill: 1),
            ),
    );
  }
}
