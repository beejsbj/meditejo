import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/views/categories/category_view.dart';
import 'package:medito/views/categories/practice_tile.dart';
import 'package:medito/views/categories/practices_view.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/section_title.dart';

/// Explore's ways to practise (Burooj, 2026-11-02): the heading with "See
/// all", then one carousel of practice cards per group. Only practices with
/// something in them are shown; a group with none is left out. Renders
/// nothing until the mapping has loaded.
class ExplorePractices extends ConsumerWidget {
  const ExplorePractices({super.key});

  /// A card's slot: its figure (148 × 132) and the words under it, which
  /// grow with the text size.
  static const cardWidth = 148.0;
  static double cardHeight(BuildContext context) =>
      132 + 130 * MediaQuery.textScalerOf(context).scale(14) / 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(categoryCatalogueProvider).value;
    // Only categories with something in them; the empty ones stay in the
    // asset for the labels sheet.
    final browsable = ref.watch(browsableCategoriesProvider).value;
    if (catalogue == null || browsable == null) return const SizedBox.shrink();
    final groups = groupPractices([
      for (final c in catalogue.categories)
        if (browsable.contains(c.id)) c,
    ]);
    if (groups.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            l10n.exploreCategories,
            trailing: TextButton(
              key: const ValueKey('practices_see_all'),
              onPressed: () => openPractices(context),
              child: Text(l10n.practicesSeeAll),
            ),
          ),
          Semantics(
            container: true,
            label: l10n.exploreCategoriesLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (group, items) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kCardGutter + 4,
                      4,
                      kCardGutter,
                      8,
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(
                        practiceGroupName(l10n, group).toUpperCase(),
                        style: context.typography.baseline.labelMedium
                            ?.copyWith(
                              letterSpacing: 1.2,
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: cardHeight(context),
                    child: ListView.separated(
                      key: ValueKey('practices_row_$group'),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: kCardGutter,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) => SizedBox(
                        width: cardWidth,
                        child: PracticeTile(
                          key: ValueKey('category_${items[i].id}'),
                          category: items[i],
                          size: PracticeTileSize.card,
                          onTap: () => openCategory(context, items[i].id),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The categories of one course or session, as chips that open the category's
/// page, then the user's own labels as plain chips. Renders nothing when it
/// has none, so the page keeps its layout.
class CategoryChips extends ConsumerWidget {
  const CategoryChips({
    super.key,
    required this.subject,
    this.padding = EdgeInsets.zero,
  });

  final LabelSubject subject;

  /// Applied only when there are chips, so an unlabelled item leaves no gap.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(labelsOfProvider(subject)).value;
    final catalogue = ref.watch(categoryCatalogueProvider).value;
    if (labels == null || catalogue == null || labels.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final assignment in labels.categories)
            if (catalogue.category(assignment.id) case final category?)
              ActionChip(
                key: ValueKey('category_chip_${category.id}'),
                label: Text(category.name),
                onPressed: () => openCategory(context, category.id),
              ),
          for (final text in labels.custom)
            Chip(key: ValueKey('label_chip_$text'), label: Text(text)),
        ],
      ),
    );
  }
}
