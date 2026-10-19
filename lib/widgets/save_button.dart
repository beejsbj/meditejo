import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/services/library/lib_ids.dart';

/// Saves or unsaves the course or teacher with [id], when its source supports
/// saving; renders nothing otherwise. Saved items lead Explore.
class SaveButton extends ConsumerWidget {
  const SaveButton({
    super.key,
    required this.id,
    required this.label,
    required this.savedLabel,
  });

  final String id;

  /// "Save course", "Save teacher".
  final String label;

  /// "Saved".
  final String savedLabel;

  /// Taking an imported item out deletes its audio from the device, so that
  /// asks first; a catalogue item toggles at once.
  Future<void> _toggle(BuildContext context, WidgetRef ref, bool saved) async {
    if (saved && id.startsWith(libPrefix)) {
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.libraryRemoveTitle),
          content: Text(l10n.libraryRemoveImported),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.libraryRemove),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref.read(savedProvider(id).notifier).toggle();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(contentRouterProvider).canSave(id)) {
      return const SizedBox.shrink();
    }
    final saved = ref.watch(savedProvider(id)).value ?? false;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      toggled: saved,
      label: saved ? savedLabel : label,
      excludeSemantics: true,
      onTap: () => _toggle(context, ref, saved),
      child: OutlinedButton.icon(
        onPressed: () => _toggle(context, ref, saved),
        icon: Icon(
          saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          size: 20,
        ),
        label: Text(saved ? savedLabel : label),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          minimumSize: const Size(0, 44),
          shape: const StadiumBorder(),
          side: BorderSide(
            color: theme.colorScheme.onSurface.withValues(
              alpha: saved ? 0.7 : 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
