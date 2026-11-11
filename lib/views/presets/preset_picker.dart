import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/presets/preset_actions.dart';
import 'package:medito/views/presets/preset_labels.dart';
import 'package:medito/views/presets/save_preset_sheet.dart';
import 'package:medito/views/soundscape/sound_labels.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/medito_icon.dart';

/// "From Morning sit", or "From Morning sit · edited".
String presetFromLine(AppLocalizations l10n, LoadedPreset loaded) {
  final name = soundPresetLabel(l10n, loaded.preset);
  return loaded.edited ? l10n.presetFromEdited(name) : l10n.presetFrom(name);
}

/// Presets, in Customize, as one line under the tiles: it names the
/// preset loaded ("From Morning sit · edited") and opens the list of them;
/// Save beside it opens the save sheet. Under the tiles so the dial stays
/// on top and the four tiles stay on the first screen.
class PresetRow extends ConsumerWidget {
  const PresetRow({super.key, required this.place, this.onOpened});

  final PresetContext place;

  /// Called as the list or the save sheet opens.
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final loaded = ref.watch(loadedPresetProvider(place));
    final line = loaded == null
        ? l10n.soundsPresets
        : presetFromLine(l10n, loaded);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            child: InkWell(
              key: const ValueKey('customize_presets'),
              borderRadius: BorderRadius.circular(MeditejoShapes.full),
              onTap: () {
                onOpened?.call();
                showPresetPicker(context, place);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.bookmarks_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          line,
                          key: const ValueKey('preset_loaded'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.emphasized.labelLarge?.copyWith(
                            color: loaded == null
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        TextButton(
          key: const ValueKey('customize_preset_save'),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () {
            onOpened?.call();
            showSavePresetSheet(context, place);
          },
          child: Text(l10n.soundsSave),
        ),
      ],
    );
  }
}

/// Opens the list of presets for [place]. A tap on one sets the slots it
/// holds there and closes the list.
Future<void> showPresetPicker(BuildContext context, PresetContext place) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PresetPickerSheet(place: place),
    );

/// Every preset, the user's own first (newest first), then the ones that
/// ship. Each says what it sets; the slots that do nothing in this place
/// are muted. Its ⋮, or holding it, opens its actions (pin, delete).
class PresetPickerSheet extends ConsumerWidget {
  const PresetPickerSheet({super.key, required this.place});

  final PresetContext place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final type = context.typography;
    final mine = ref.watch(soundscapeProvider.select((s) => s.userPresets));
    final loaded = ref.watch(loadedPresetProvider(place));
    final presets = [...mine.reversed, ...kStarterPresets];
    final container = ProviderScope.containerOf(context, listen: false);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.soundsPresets,
                  style: type.emphasized.headlineSmall,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                key: const ValueKey('preset_picker'),
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  for (final preset in presets)
                    _PresetEntry(
                      key: ValueKey('preset_entry_${preset.id}'),
                      preset: preset,
                      label: soundPresetLabel(l10n, preset),
                      applies: place.offered,
                      selected: loaded?.preset.id == preset.id,
                      onTap: () {
                        // Set before the list closes; the sheet under it
                        // follows its providers.
                        applyPreset(container, place, preset);
                        Navigator.of(context).pop();
                      },
                      onMenu: () => showPresetActions(context, preset),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One preset in the list: its sound's art (or the timer's mark), its name
/// over what it sets, and its ⋮. Filled while it is the one loaded.
class _PresetEntry extends StatelessWidget {
  const _PresetEntry({
    super.key,
    required this.preset,
    required this.label,
    required this.applies,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });

  final Preset preset;
  final String label;
  final Set<PresetSlot> applies;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    // Nothing it holds is in play here: it is shown, and does nothing.
    final inert = preset.slots.filled.intersection(applies).isEmpty;
    final onColor = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    final art = ClipRRect(
      borderRadius: BorderRadius.circular(MeditejoShapes.small),
      child: SizedBox.square(
        dimension: 40,
        child: preset.playsSound
            ? ArtCover(subject: ArtSubject.layers(preset.id, preset.mix.layers))
            : ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Center(
                  child: MeditoIcon(
                    assetName: MeditoIcons.timer,
                    color: scheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: MeditejoShapes.rounded(MeditejoShapes.large),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                enabled: !inert,
                label: l10n.presetApply(label),
                child: InkWell(
                  onTap: inert ? null : onTap,
                  onLongPress: onMenu,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
                    child: Row(
                      children: [
                        art,
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: type.emphasized.titleSmall?.copyWith(
                                    color: inert
                                        ? onColor.withValues(alpha: 0.5)
                                        : onColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              PresetSummary(
                                preset.slots,
                                applies: applies,
                                color: selected
                                    ? scheme.onSecondaryContainer
                                    : scheme.onSurfaceVariant,
                                style: type.baseline.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              key: ValueKey('preset_menu_${preset.id}'),
              tooltip: l10n.homeCardMenu(label),
              color: onColor,
              onPressed: onMenu,
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
