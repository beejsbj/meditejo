import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/widgets/cards/filter_chip_bar.dart';

/// Explore's content-kind chips: Practice (guided meditations, chanting) and
/// Talks (talks, Q & A, other). Neither selected shows everything; tapping
/// the chosen chip again clears it.
class ExploreKindChips extends ConsumerWidget {
  const ExploreKindChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selected = ref.watch(exploreGroupProvider);
    final notifier = ref.read(exploreGroupProvider.notifier);

    return FilterChipBar<DsContentGroup>(
      selected: selected,
      allowDeselect: true,
      onSelected: (group) =>
          group == null ? notifier.toggle(selected!) : notifier.toggle(group),
      options: [
        FilterOption(
          DsContentGroup.practice,
          l10n.exploreKindPractice,
          key: const ValueKey('explore_chip_practice'),
        ),
        FilterOption(
          DsContentGroup.talks,
          l10n.exploreKindTalks,
          key: const ValueKey('explore_chip_talks'),
        ),
      ],
    );
  }
}
