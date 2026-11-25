import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/colors/color_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/scaffold_messenger_key.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/library/library_actions.dart';
import 'package:medito/widgets/snackbar_widget.dart';

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
      onTap: () => toggleSaved(context, ref, id, saved),
      child: OutlinedButton.icon(
        onPressed: () => toggleSaved(context, ref, id, saved),
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

/// The course header's Library toggle (#81): a round bookmark, filled in the
/// accent colour while [id] is in the library, beside Pin. Unlike the
/// labelled [SaveButton] it says what it did, as the icon alone does not.
/// Renders nothing when [id]'s source cannot save it.
class SaveIconButton extends ConsumerWidget {
  const SaveIconButton({
    super.key,
    required this.id,
    required this.label,
    required this.savedLabel,
  });

  final String id;

  /// "Add to library".
  final String label;

  /// "In library".
  final String savedLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(contentRouterProvider).canSave(id)) {
      return const SizedBox.shrink();
    }
    final saved = ref.watch(savedProvider(id)).value ?? false;
    final scheme = Theme.of(context).colorScheme;
    return IconButton.outlined(
      key: const ValueKey('course_library'),
      tooltip: saved ? savedLabel : label,
      isSelected: saved,
      onPressed: () => toggleSaved(context, ref, id, saved, announce: true),
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        side: BorderSide(
          color: scheme.onSurface.withValues(alpha: saved ? 0.7 : 0.3),
        ),
      ),
      icon: Icon(Icons.bookmark_border_rounded, color: scheme.onSurface),
      selectedIcon: Icon(Icons.bookmark_rounded, color: context.brandAccent),
    );
  }
}

/// Adds [id] to the library, or ([saved]) takes it out.
///
/// Taking an imported item out deletes its audio from the device, so that
/// asks first and the page showing it closes; a catalogue item toggles at
/// once. With [announce], a snackbar says which happened.
Future<void> toggleSaved(
  BuildContext context,
  WidgetRef ref,
  String id,
  bool saved, {
  bool announce = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  // The snackbar's text takes its style from a context: the page's while it
  // is there, else the app's messenger (with none it is white on white).
  BuildContext? styled() =>
      context.mounted ? context : scaffoldMessengerKey.currentContext;
  if (saved && id.startsWith(libPrefix)) {
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
    // Unsaving an import deletes it, and its pins with it; the saved state
    // follows the library's revision.
    try {
      await deleteImport(ref, id);
    } catch (e, st) {
      AppLogger.e('LIBRARY', 'Could not remove $id', e, st);
      // The app's messenger shows it, so it survives the page.
      showSnackBar(styled(), l10n.someThingWentWrong);
      return;
    }
    if (announce) showSnackBar(styled(), l10n.libraryRemovedSnack);
    // The page shows what was just deleted (a Play for a file that is gone),
    // so an imported item's page closes with it.
    if (context.mounted) await Navigator.of(context).maybePop();
    return;
  }
  // Replace rather than queue, so a quick re-tap reads the end state.
  if (announce) scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
  if (saved && announce) {
    // Taken out as the Library takes it out: with Undo, which puts it back
    // as it was (its section and title overrides too).
    final entry = await ref.read(libraryStoreProvider).entry(id);
    if (entry != null && context.mounted) {
      return removeFromLibrary(context, ref, entry);
    }
  }
  await ref.read(savedProvider(id).notifier).toggle();
  if (announce) {
    showSnackBar(
      styled(),
      saved ? l10n.libraryRemovedSnack : l10n.libraryAddedSnack,
    );
  }
}
