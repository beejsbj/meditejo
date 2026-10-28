import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/custom_bell_provider.dart';
import 'package:medito/services/bells/custom_bell.dart';
import 'package:medito/views/cues/bell_maker_view.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';

/// The bells a cue can ring, each with its icon (the bell's figure,
/// drawn from its sound), then the ones the user made and a row to make
/// another. Tapping one selects it and rings it once, so what is heard is
/// what a session will play, and its icon is struck with it.
class BellList extends ConsumerStatefulWidget {
  const BellList({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.volume,
  });

  /// The sound the cue rings now: a bundled bell's asset, a made bell's id, or
  /// empty for none. A made bell that no longer exists reads as the default
  /// bell, which is what rings.
  final String selected;
  final ValueChanged<String> onSelected;

  /// The cue's bell volume, which a bell being made is heard at.
  final double volume;

  @override
  ConsumerState<BellList> createState() => _BellListState();
}

class _BellListState extends ConsumerState<BellList> {
  // One per bell, made when a bell first needs it.
  final _strikes = <String, ValueNotifier<int>>{};

  ValueNotifier<int> _strike(String id) =>
      _strikes.putIfAbsent(id, () => ValueNotifier(0));

  @override
  void dispose() {
    for (final n in _strikes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _pick(String sound) {
    widget.onSelected(sound);
    if (sound.isNotEmpty) _strike(sound).value++;
  }

  /// [BellList.selected] as the list shows it: a made bell that is gone is
  /// the default bell.
  String _shown(List<CustomBell> made) =>
      isCustomBellId(widget.selected) &&
          !made.any((b) => b.id == widget.selected)
      ? cueDefaultBell
      : widget.selected;

  Future<void> _make() async {
    final bell = await showBellMaker(
      context,
      from: _shown(ref.read(customBellsProvider)),
      volume: widget.volume,
    );
    if (bell != null && mounted) _pick(bell.id);
  }

  Future<void> _rename(CustomBell bell) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _BellNameDialog(initial: bell.name),
    );
    if (name == null || cleanBellName(name) == null || !mounted) return;
    await ref.read(customBellsProvider.notifier).rename(bell.id, name);
  }

  Future<void> _delete(CustomBell bell) async {
    final l10n = AppLocalizations.of(context);
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          l10n?.bellDeleteTitle(bell.name) ?? 'Delete “${bell.name}”?',
        ),
        content: Text(
          l10n?.bellDeleteBody ??
              'Cues that ring it go back to the Swell bell.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n?.soundsCancel ?? 'Cancel'),
          ),
          TextButton(
            key: const ValueKey('bell_delete_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n?.soundsDelete ?? 'Delete'),
          ),
        ],
      ),
    );
    if (delete != true || !mounted) return;
    // Every stored cue that rang it moves to the default bell, and the sheet
    // follows through the settings provider.
    await ref.read(customBellsProvider.notifier).delete(bell.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final made = ref.watch(customBellsProvider);
    final selected = _shown(made);
    return Material(
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: MeditejoShapes.rounded(MeditejoShapes.largeIncreased),
      child: Column(
        children: [
          for (final e in cueBellSounds.entries)
            _row(
              key: e.value,
              name: e.key,
              selected: e.value == selected,
              icon: e.value.isEmpty
                  ? ColoredBox(
                      color: scheme.surfaceContainerLow,
                      child: Icon(
                        Icons.notifications_off_outlined,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : ArtCover(
                      key: ValueKey('bell_icon_${e.value}'),
                      subject: ArtSubject.bell(e.value, icon: true),
                      strike: _strike(e.value),
                    ),
              onTap: () => _pick(e.value),
            ),
          if (made.isNotEmpty) _heading(l10n?.bellYours ?? 'Your bells'),
          for (final b in made)
            _row(
              key: b.id,
              name: b.name,
              selected: b.id == selected,
              icon: ArtCover(
                key: ValueKey('bell_icon_${b.id}'),
                subject: ArtSubject.customBell(
                  b.id,
                  b.preset,
                  b.knobs,
                  icon: true,
                ),
                strike: _strike(b.id),
              ),
              onTap: () => _pick(b.id),
              menu: PopupMenuButton<String>(
                key: ValueKey('bell_menu_${b.id}'),
                tooltip: l10n?.bellMenu(b.name) ?? 'More about ${b.name}',
                onSelected: (v) => v == 'rename'
                    ? unawaited(_rename(b))
                    : unawaited(_delete(b)),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(l10n?.bellRename ?? 'Rename'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n?.soundsDelete ?? 'Delete'),
                  ),
                ],
              ),
            ),
          _row(
            key: 'make',
            name: l10n?.bellMakerTitle ?? 'Make a bell',
            selected: false,
            icon: ColoredBox(
              color: scheme.secondaryContainer,
              child: Icon(
                Icons.add_rounded,
                size: 22,
                color: scheme.onSecondaryContainer,
              ),
            ),
            onTap: _make,
            action: true,
          ),
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: context.typography.baseline.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );

  Widget _row({
    required String key,
    required String name,
    required bool selected,
    required Widget icon,
    required VoidCallback onTap,
    Widget? menu,
    bool action = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    return Semantics(
      button: true,
      selected: selected,
      label: action || key.isEmpty ? name : '$name, plays a preview',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: ValueKey('bell_row_$key'),
        onTap: onTap,
        child: Ink(
          color: selected ? scheme.secondaryContainer : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 40,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: icon,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (selected
                                  ? type.emphasized.bodyLarge
                                  : type.baseline.bodyLarge)
                              ?.copyWith(
                                color: selected
                                    ? scheme.onSecondaryContainer
                                    : scheme.onSurface,
                              ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_rounded, color: scheme.primary)
                  else if (!action && key.isNotEmpty && menu == null)
                    Icon(
                      Icons.volume_up_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ?menu,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a bell's new name.
class _BellNameDialog extends StatefulWidget {
  const _BellNameDialog({required this.initial});

  final String initial;

  @override
  State<_BellNameDialog> createState() => _BellNameDialogState();
}

class _BellNameDialogState extends State<_BellNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n?.bellRenameTitle ?? 'Rename bell'),
      content: TextField(
        key: const ValueKey('bell_rename_field'),
        controller: _controller,
        autofocus: true,
        maxLength: maxCustomBellNameLength,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n?.soundsCancel ?? 'Cancel'),
        ),
        TextButton(
          key: const ValueKey('bell_rename_confirm'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n?.bellMakerSave ?? 'Save'),
        ),
      ],
    );
  }
}
