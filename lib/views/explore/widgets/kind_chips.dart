import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/widgets/filter_pill.dart';

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(padding16, padding16, padding16, 0),
      child: Wrap(
        spacing: padding8,
        children: [
          FilterPill(
            key: const ValueKey('explore_chip_practice'),
            label: l10n.exploreKindPractice,
            selected: selected == DsContentGroup.practice,
            onTap: () => notifier.toggle(DsContentGroup.practice),
          ),
          FilterPill(
            key: const ValueKey('explore_chip_talks'),
            label: l10n.exploreKindTalks,
            selected: selected == DsContentGroup.talks,
            onTap: () => notifier.toggle(DsContentGroup.talks),
          ),
        ],
      ),
    );
  }
}
