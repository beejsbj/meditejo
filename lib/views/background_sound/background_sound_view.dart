import 'package:medito/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/background_sounds/background_sounds_notifier.dart';
import '../../providers/soundscape/soundscape_provider.dart';
import '../soundscape/sounds_panel.dart';
import 'widgets/volume_slider_widget.dart';

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
/// Session bells keep their switch here, with their own volume, until the
/// cue system takes them over.
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
    final bellsOn = ref.watch(
      backgroundSoundsNotifierProvider.select((s) => s.bellsEnabled),
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
              // Bells are a switch: they play alongside any sound.
              const _SessionBellsSwitch(),
              if (bellsOn) const VolumeSliderWidget(),
              const SoundsCreditsLink(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionBellsSwitch extends ConsumerWidget {
  const _SessionBellsSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final l10n = AppLocalizations.of(context)!;
    final enabled = ref.watch(
      backgroundSoundsNotifierProvider.select((s) => s.bellsEnabled),
    );

    void toggle(bool value) {
      ref
          .read(backgroundSoundsNotifierProvider.notifier)
          .setSessionBells(value);
    }

    // Same type and margins as the sound rows below.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: () => toggle(!enabled),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.sessionBells,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.sessionBellsDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: onSurface.withValues(alpha: 0.7),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(value: enabled, onChanged: toggle),
            ],
          ),
        ),
      ),
    );
  }
}
