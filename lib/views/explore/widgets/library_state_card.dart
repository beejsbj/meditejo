import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';

/// What Explore says before any course has arrived: the first sync is under
/// way (with how far it has got), or it has not run or has failed.
class LibraryStateCard extends ConsumerWidget {
  const LibraryStateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final status = ref.watch(dharmaSeedSyncStatusProvider);
    final syncing = status.isSyncing;

    final progress = syncing && status.total > 0
        ? l10n.dharmaSeedSyncProgress(
            switch (status.kind) {
              DsKind.teachers => l10n.dharmaSeedTeachers,
              DsKind.retreats => l10n.dharmaSeedRetreats,
              DsKind.talks || null => l10n.dharmaSeedTalks,
            },
            status.done,
            status.total,
          )
        : null;

    return Padding(
      padding: const EdgeInsets.all(padding24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (syncing)
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(
              Icons.library_music_outlined,
              size: 32,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          const SizedBox(height: padding16),
          Text(
            syncing ? l10n.exploreSyncingTitle : l10n.exploreNoLibraryTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: padding8),
          Text(
            syncing ? l10n.exploreSyncingBody : l10n.exploreNoLibraryBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.4,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: padding12),
            Text(progress, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
