import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/updates/update_providers.dart';
import 'package:medito/providers/main_tab_provider.dart';

/// One quiet line on Home when a newer build exists. Dismissing it hides it for
/// that version; Settings, under About, still offers the update.
class UpdateNotice extends ConsumerWidget {
  const UpdateNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(updatesSupportedProvider)) return const SizedBox.shrink();
    final state = ref.watch(updateControllerProvider);
    final release = state.release;
    if (!state.showHomeNotice || release == null) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(padding16, padding8, padding8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.homeUpdateNotice(release.versionName),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(
            // Settings moves About to the top while an update is waiting.
            onPressed: () =>
                ref.read(mainTabProvider.notifier).select(MainTab.settings),
            child: Text(l10n.homeUpdateView),
          ),
          IconButton(
            tooltip: l10n.homeUpdateDismiss,
            icon: const Icon(Icons.close, size: 20),
            onPressed: () =>
                ref.read(updateControllerProvider.notifier).dismissHomeNotice(),
          ),
        ],
      ),
    );
  }
}
