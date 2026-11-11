import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/views/presets/preset_labels.dart';

/// What the save sheet did.
typedef SavedPreset = ({Preset preset, bool updated});

/// Opens the one save sheet (#64, #68) on what is set in [place]. The place
/// decides which slots it offers; the others are shown, not saved. Returns
/// what was saved, or null.
Future<SavedPreset?> showSavePresetSheet(
  BuildContext context,
  PresetContext place,
) => showModalBottomSheet<SavedPreset>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => SavePresetSheet(place: place),
);

class SavePresetSheet extends ConsumerStatefulWidget {
  const SavePresetSheet({super.key, required this.place});

  final PresetContext place;

  @override
  ConsumerState<SavePresetSheet> createState() => _SavePresetSheetState();
}

class _SavePresetSheetState extends ConsumerState<SavePresetSheet> {
  final _name = TextEditingController();

  /// The user's own preset loaded here: it can be updated. Null with
  /// nothing loaded (or a built-in one), and once "Save as new" is chosen.
  Preset? _loaded;
  late Set<PresetSlot> _ticked;
  bool _pin = false;

  PresetContext get _place => widget.place;

  @override
  void initState() {
    super.initState();
    final loaded = ref.read(loadedPresetProvider(_place))?.preset;
    _loaded = loaded == null || loaded.builtIn ? null : loaded;
    _ticked = _changed();
    if (_loaded case final preset?) {
      // What it already holds is written again, unless unticked.
      _ticked.addAll(preset.slots.filled.intersection(_place.offered));
      _pin = ref.read(pinnedPresetIdsProvider).contains(preset.id);
    }
    _name.addListener(() => setState(() {}));
  }

  /// The offered slots that differ from the defaults: what was set.
  Set<PresetSlot> _changed() => ref
      .read(currentPresetSlotsProvider(_place))
      .differing(ref.read(defaultPresetSlotsProvider(_place)), _place.offered);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _saveAsNew() => setState(() {
    _loaded = null;
    _ticked = _changed();
    _pin = false;
  });

  void _save() {
    final container = ProviderScope.containerOf(context, listen: false);
    final loaded = _loaded;
    final preset = loaded == null
        ? saveNewPreset(
            container,
            _place,
            name: _name.text,
            ticked: _ticked,
            pin: _pin,
          )
        : updatePreset(container, _place, loaded, ticked: _ticked, pin: _pin);
    if (preset == null) return;
    Navigator.of(context).pop((preset: preset, updated: loaded != null));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final words = PresetWords.of(context, ref);
    final current = ref.watch(currentPresetSlotsProvider(_place));
    final loaded = _loaded;
    final canSave =
        _ticked.isNotEmpty && (loaded != null || _name.text.trim().isNotEmpty);

    Widget slotRow(PresetSlot slot) {
      final offered = _place.offered.contains(slot);
      final ticked = _ticked.contains(slot);
      final kept = switch (loaded) {
        null => null,
        final preset => words.value(preset.slots, slot),
      };
      // What ticking it saves; otherwise what the preset keeps, if anything.
      final value = offered && ticked
          ? words.value(current, slot)
          : kept != null
          ? l10n.presetKept(kept)
          : offered
          ? words.value(current, slot)
          : l10n.presetNotSet;
      final quiet = scheme.onSurfaceVariant.withValues(alpha: 0.72);
      final on = offered && ticked;
      void toggle() =>
          setState(() => ticked ? _ticked.remove(slot) : _ticked.add(slot));
      return ListTile(
        key: ValueKey('preset_slot_${slot.name}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: Icon(presetSlotIcon(slot), color: on ? scheme.primary : quiet),
        title: Text(
          presetSlotName(l10n, slot),
          style: type.emphasized.titleSmall?.copyWith(
            color: offered ? scheme.onSurface : quiet,
          ),
        ),
        subtitle: Text(
          value ?? l10n.presetNotSet,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: type.baseline.bodyMedium?.copyWith(
            color: on ? scheme.onSurfaceVariant : quiet,
          ),
        ),
        trailing: offered
            ? Checkbox(value: ticked, onChanged: (_) => toggle())
            : null,
        onTap: offered ? toggle : null,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.soundsSavePreset,
                  style: type.emphasized.headlineSmall,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (loaded == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                        child: TextField(
                          key: const ValueKey('preset_name'),
                          controller: _name,
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: l10n.soundsPresetName,
                          ),
                          onSubmitted: (_) => canSave ? _save() : null,
                        ),
                      ),
                    for (final slot in PresetSlot.values) slotRow(slot),
                    const Divider(indent: 24, endIndent: 24),
                    ListTile(
                      key: const ValueKey('preset_pin'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      leading: Icon(
                        Icons.push_pin_outlined,
                        color: _pin ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        l10n.pinCourse,
                        style: type.emphasized.titleSmall,
                      ),
                      trailing: Checkbox(
                        value: _pin,
                        onChanged: (v) => setState(() => _pin = v ?? false),
                      ),
                      onTap: () => setState(() => _pin = !_pin),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (loaded != null)
                    TextButton(
                      key: const ValueKey('preset_save_as_new'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _saveAsNew,
                      child: Text(l10n.presetSaveAsNew),
                    ),
                  FilledButton(
                    key: ValueKey(
                      loaded == null ? 'preset_name_save' : 'preset_update',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: MeditejoShapes.stadium,
                    ),
                    onPressed: canSave ? _save : null,
                    child: Text(
                      loaded == null
                          ? l10n.soundsSave
                          : l10n.presetUpdate(loaded.name),
                    ),
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
