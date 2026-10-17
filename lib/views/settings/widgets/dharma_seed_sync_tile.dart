import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';

/// Dharma Seed catalogue sync: progress, last sync or failure, and a manual
/// refresh on tap.
class DharmaSeedSyncTile extends ConsumerWidget {
  const DharmaSeedSyncTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final status = ref.watch(dharmaSeedSyncStatusProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return RowItemWidget(
      icon: Icon(Icons.library_music_outlined, color: onSurface),
      title: l10n.dharmaSeedLibrary,
      subTitle: _subtitle(context, l10n, status),
      hasUnderline: hasUnderline,
      trailingIcon: Icons.refresh_rounded,
      isTrailingIcon: !status.isSyncing,
      trailing: status.isSyncing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: status.isSyncing
          ? null
          : () => ref.read(dharmaSeedSyncProvider).sync(force: true),
    );
  }

  String _subtitle(
    BuildContext context,
    AppLocalizations l10n,
    DharmaSeedSyncStatus status,
  ) {
    switch (status.phase) {
      case DharmaSeedSyncPhase.syncing:
        final what = switch (status.kind) {
          DsKind.teachers => l10n.dharmaSeedTeachers,
          DsKind.retreats => l10n.dharmaSeedRetreats,
          DsKind.talks || null => l10n.dharmaSeedTalks,
        };
        return l10n.dharmaSeedSyncProgress(what, status.done, status.total);
      case DharmaSeedSyncPhase.failed:
        return l10n.dharmaSeedSyncFailed(status.error ?? '');
      case DharmaSeedSyncPhase.idle:
        final last = status.lastSyncedAt;
        if (last == null) return l10n.dharmaSeedNeverSynced;
        final locale = Localizations.localeOf(context).toLanguageTag();
        return l10n.dharmaSeedUpToDate(
          DateFormat.yMMMd(locale).add_jm().format(last.toLocal()),
        );
    }
  }
}
