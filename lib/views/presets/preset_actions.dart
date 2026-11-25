import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/views/soundscape/sound_labels.dart';
import 'package:medito/widgets/cards/card_actions.dart';

/// What can be done with a preset wherever it is listed: pin it to Home or
/// unpin it (the same words and pin as a course's), and delete one of the
/// user's own.
List<CardAction> presetActions(
  BuildContext context,
  ProviderContainer container,
  Preset preset,
) {
  final l10n = AppLocalizations.of(context)!;
  final pins = container.read(pinnedPresetIdsProvider.notifier);
  final pinned = pins.isPinned(preset.id);
  return [
    CardAction(
      key: ValueKey('preset_pin_${preset.id}'),
      icon: Icons.push_pin_outlined,
      label: pinned ? l10n.unpinCourse : l10n.pinCourse,
      onSelected: () => pins.setPinned(preset.id, !pinned),
    ),
    if (!preset.builtIn)
      CardAction(
        key: ValueKey('preset_delete_${preset.id}'),
        icon: Icons.delete_outline_rounded,
        label: l10n.soundsDelete,
        onSelected: () => confirmDeletePreset(context, container, preset),
      ),
  ];
}

/// A preset's actions in a sheet: what holding it, or its ⋮, opens.
Future<void> showPresetActions(BuildContext context, Preset preset) =>
    showCardActions(
      context,
      title: soundPresetLabel(AppLocalizations.of(context)!, preset),
      actions: presetActions(
        context,
        ProviderScope.containerOf(context, listen: false),
        preset,
      ),
    );

/// Confirms, then deletes one of the user's presets.
Future<void> confirmDeletePreset(
  BuildContext context,
  ProviderContainer container,
  Preset preset,
) async {
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final delete = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.soundsDeletePreset(preset.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.soundsCancel),
        ),
        TextButton(
          key: const ValueKey('preset_delete_confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.soundsDelete),
        ),
      ],
    ),
  );
  if (delete == true) deletePreset(container, preset.id);
}
