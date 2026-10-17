import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';

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
      onTap: () => ref.read(savedProvider(id).notifier).toggle(),
      child: OutlinedButton.icon(
        onPressed: () => ref.read(savedProvider(id).notifier).toggle(),
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
