import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/widgets/snackbar_widget.dart';

/// A small "add to library" action for a course or talk in a list. It shows
/// a tick once the item is in the library and never removes it from there:
/// taking something out is deliberate, from the library or the item's own
/// page. Renders nothing for an item that cannot be saved.
class AddToLibraryIcon extends ConsumerStatefulWidget {
  const AddToLibraryIcon({super.key, required this.id, this.color});

  final String id;
  final Color? color;

  @override
  ConsumerState<AddToLibraryIcon> createState() => _AddToLibraryIconState();
}

class _AddToLibraryIconState extends ConsumerState<AddToLibraryIcon> {
  bool _adding = false;

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _adding = true);
    try {
      await ref.read(contentRouterProvider).setSaved(widget.id, saved: true);
      if (mounted) {
        showSnackBar(
          context,
          l10n.libraryAddedSnack,
          actionLabel: l10n.undo,
          onActionPressed: () =>
              ref.read(contentRouterProvider).setSaved(widget.id, saved: false),
        );
      }
    } catch (e, st) {
      AppLogger.e('LIBRARY', 'Could not add ${widget.id}', e, st);
      if (mounted) showSnackBar(context, l10n.importFailAdd);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(contentRouterProvider).canSave(widget.id)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final inLibrary = ref.watch(inLibraryProvider(widget.id)).value ?? false;
    final color =
        widget.color ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8);

    if (_adding) {
      return const SizedBox.square(
        dimension: 44,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return IconButton(
      key: ValueKey('add_to_library_${widget.id}'),
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      tooltip: inLibrary ? l10n.libraryInLibrary : l10n.libraryAddToLibrary,
      color: color,
      onPressed: inLibrary
          ? () => showSnackBar(context, l10n.libraryAlreadyIn)
          : _add,
      icon: Icon(
        inLibrary
            ? Icons.check_circle_rounded
            : Icons.add_circle_outline_rounded,
      ),
    );
  }
}
