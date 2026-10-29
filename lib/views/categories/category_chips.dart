import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/views/categories/category_view.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/section_title.dart';

/// Explore's category entry points: a heading and a sideways row of chips,
/// one per category that has something in it. Each opens that category's
/// page. Renders nothing until the mapping has loaded.
class ExploreCategoryChips extends ConsumerWidget {
  const ExploreCategoryChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(categoryCatalogueProvider).value;
    // Only categories with something in them; the empty ones stay in the
    // asset for the labels sheet.
    final browsable = ref.watch(browsableCategoriesProvider).value;
    if (catalogue == null || browsable == null) return const SizedBox.shrink();
    final shown = [
      for (final c in catalogue.categories)
        if (browsable.contains(c.id)) c,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(l10n.exploreCategories),
          Semantics(
            container: true,
            label: l10n.exploreCategoriesLabel,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: kCardGutter),
              child: Row(
                children: [
                  for (final (i, category) in shown.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    ActionChip(
                      key: ValueKey('category_${category.id}'),
                      label: Text(category.name),
                      onPressed: () => openCategory(context, category.id),
                    ),
                  ],
                ],
              ),
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
