import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/views/home/widgets/shortcuts/shortcuts_section.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';

/// Opens the full list of pins over whatever is showing.
void openPinnedList(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const PinnedListView()));

/// Everything pinned, in Home's order and as Home shows it: every pinned
/// preset as a tile, then every pinned course and session as a card. Opened
/// from Home's "See all" and the You page.
class PinnedListView extends ConsumerWidget {
  const PinnedListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ids = ref.watch(pinnedCoursesProvider);
    final presets = ref.watch(pinnedPresetsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homePinnedTitle)),
      body: AdaptivePageBody(
        maxWidth: 760,
        child: ids.isEmpty && presets.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    key: const ValueKey('pinned_list_empty'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.push_pin_outlined,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.pinnedEmpty,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.pinnedEmptyHint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                key: const ValueKey('pinned_list'),
                padding: const EdgeInsets.fromLTRB(
                  kHomeGutter,
                  8,
                  kHomeGutter,
                  32,
                ),
                children: [
                  if (presets.isNotEmpty)
                    ShortcutTileGrid(
                      tiles: [
                        for (final preset in presets)
                          PinnedPresetTile(preset: preset),
                      ],
                    ),
                  for (final (i, id) in ids.indexed)
                    Padding(
                      padding: EdgeInsets.only(
                        top: i > 0
                            ? kHomeRowGap
                            : presets.isEmpty
                            ? 0
                            : kHomeGap,
                      ),
                      child: PinnedTile(id: id),
                    ),
                ],
              ),
      ),
    );
  }
}
