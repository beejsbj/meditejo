import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/widgets/cards/card_tokens.dart';

/// Explore's filter row. First the content kinds: Practice (guided
/// meditations, chanting) and Talks (talks, Q & A, other); neither selected
/// shows everything, and tapping the chosen chip again clears it. Then, once
/// more than one catalogue is built in, the source: All, Dharma Seed,
/// Dhammatalks.
class ExploreKindChips extends ConsumerWidget {
  const ExploreKindChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final group = ref.watch(exploreGroupProvider);
    final groupNotifier = ref.read(exploreGroupProvider.notifier);
    final sources = ref.watch(catalogueSourcesProvider);
    final source = ref.watch(exploreSourceProvider);
    final sourceNotifier = ref.read(exploreSourceProvider.notifier);

    Widget kind(ContentGroup value, String label, String key) => ChoiceChip(
      key: ValueKey(key),
      label: Text(label),
      selected: group == value,
      onSelected: (_) => groupNotifier.toggle(value),
    );

    return Semantics(
      container: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kCardGutter),
        child: Row(
          children: [
            kind(
              ContentGroup.practice,
              l10n.exploreKindPractice,
              'explore_chip_practice',
            ),
            const SizedBox(width: 8),
            kind(
              ContentGroup.talks,
              l10n.exploreKindTalks,
              'explore_chip_talks',
            ),
            if (sources.length > 1) ...[
              const SizedBox(width: 12),
              SizedBox(
                height: 24,
                child: VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                key: const ValueKey('explore_source_all'),
                label: Text(l10n.exploreSourceAll),
                selected: source == null,
                onSelected: (_) => sourceNotifier.select(null),
              ),
              for (final s in sources) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  key: ValueKey('explore_source_${s.prefix}'),
                  label: Text(s.name),
                  selected: source == s.prefix,
                  onSelected: (_) => sourceNotifier.select(s.prefix),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
