import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

/// Opens [HomeMarkSheet]: from a long-press on Home's mark, and from
/// Settings › Appearance.
Future<void> showHomeMarkSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const HomeMarkSheet(),
    );

/// Home's mark, large, with whether it is today's or pinned, and the one
/// action that changes that: pin it, or go back to the daily mark.
class HomeMarkSheet extends ConsumerWidget {
  const HomeMarkSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final type = context.typography;
    final scheme = Theme.of(context).colorScheme;
    final mark = ref.watch(homeMarkProvider);
    final pinned = ref.watch(pinnedMarkProvider) != null;
    final notifier = ref.read(pinnedMarkProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MeditejoMark(mark: mark, size: 168),
            const SizedBox(height: 16),
            Text(
              pinned ? l10n.homeMarkPinned : l10n.homeMarkToday,
              key: const ValueKey('home_mark_state'),
              style: type.emphasized.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              pinned ? l10n.homeMarkPinnedBody : l10n.homeMarkTodayBody,
              textAlign: TextAlign.center,
              style: type.baseline.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (pinned)
              OutlinedButton.icon(
                key: const ValueKey('home_mark_unpin'),
                icon: const Icon(Icons.today_rounded),
                label: Text(l10n.homeMarkUnpin),
                onPressed: notifier.unpin,
              )
            else
              FilledButton.tonalIcon(
                key: const ValueKey('home_mark_pin'),
                icon: const Icon(Icons.push_pin_outlined),
                label: Text(l10n.homeMarkPin),
                onPressed: () => notifier.pin(mark),
              ),
          ],
        ),
      ),
    );
  }
}
