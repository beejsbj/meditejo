import 'package:medito/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/background_sounds/background_sounds_notifier.dart';
import '../../providers/soundscape/soundscape_provider.dart';
import '../soundscape/sounds_panel.dart';

/// Opens the Sounds screen as a draggable bottom sheet: over the player, so
/// the session stays in view, and from Home's Sounds quick link.
Future<void> showBackgroundSoundSheet(BuildContext context) {
  // A failed fetch is kept (keepAlive); retry it each time the sheet opens so
  // coming back online shows every sound again.
  final container = ProviderScope.containerOf(context);
  if (container.read(backgroundSoundsProvider).hasError) {
    container.invalidate(backgroundSoundsProvider);
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 1,
      builder: (context, scrollController) =>
          BackgroundSoundView(scrollController: scrollController),
    ),
  );
}

/// The Sounds screen: the mixer (play/pause, master volume, the layers of
/// the current mix), presets, whether the mix plays under sessions, and the
/// library shelf by shelf. Shown inside [showBackgroundSoundSheet], from the
/// player and from Home; [scrollController] ties the list to the sheet's drag
/// so scrolling past the top expands or dismisses it.
///
/// Bells are not here: the cue scheduler owns them, set in Customize. (The
/// old Session bells switch would have rung a second set of bells over the
/// cues once this sheet opened from the player.)
class BackgroundSoundView extends ConsumerWidget {
  const BackgroundSoundView({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    ref
        .read(soundscapeProvider.notifier)
        .setNotificationText(
          SoundscapeNotificationText(
            title: l10n.backgroundSoundsSection,
            text: l10n.soundsNotificationText,
            stop: l10n.soundsStop,
          ),
        );
    // The transport stays pinned above the scrolling list. No
    // pull-to-refresh: in a sheet, pulling down at the top should collapse
    // the sheet.
    return Column(
      children: [
        const SoundsTransport(),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 16,
            ),
            children: [
              const SoundsMixLayers(),
              SoundsSectionLabel(l10n.soundsPresets),
              const SoundsPresets(),
              const SoundsLibraryShelves(),
              SoundsSectionLabel(l10n.soundsUnderSessions),
              const SoundsSessionDefaults(),
              const SizedBox(height: 8),
              const SoundsCreditsLink(),
            ],
          ),
        ),
      ],
    );
  }
}
