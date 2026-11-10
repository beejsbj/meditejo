import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/views/categories/category_view.dart';
import 'package:medito/views/categories/practice_tile.dart';
import 'package:medito/widgets/cards/card_tokens.dart';

void openPractices(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => const PracticesView()),
);

/// Every way to practise that has something in it, as a grid of tall tiles
/// by group: Explore's "See all".
class PracticesView extends ConsumerWidget {
  const PracticesView({super.key});

  /// A tall tile [width] wide: its figure (170 : 148) and the words under
  /// it, which grow with the text size.
  static double tileHeight(BuildContext context, double width) =>
      width * 148 / 170 + 168 * MediaQuery.textScalerOf(context).scale(14) / 14;

  /// The grid's columns and tile width at [width]: two on a phone, more on
  /// a tablet, each at most about 220 wide.
  static ({int columns, double tile}) gridFor(double width) {
    final inner = width - 2 * kCardGutter;
    final columns = ((inner + 12) / (220 + 12)).ceil().clamp(2, 6);
    return (columns: columns, tile: (inner - 12 * (columns - 1)) / columns);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final catalogue = ref.watch(categoryCatalogueProvider).value;
    final browsable = ref.watch(browsableCategoriesProvider).value;
    final groups = catalogue == null || browsable == null
        ? null
        : groupPractices([
            for (final c in catalogue.categories)
              if (browsable.contains(c.id)) c,
          ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.exploreCategories),
        titleTextStyle: context.typography.emphasized.titleLarge,
      ),
      body: groups == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, box) {
                final grid = gridFor(box.maxWidth);
                return CustomScrollView(
                  key: const ValueKey('practices_page'),
                  slivers: [
                    for (final (group, items) in groups) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            kCardGutter + 4,
                            16,
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
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kCardGutter,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: grid.columns,
                                mainAxisExtent: tileHeight(context, grid.tile),
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => PracticeTile(
                              key: ValueKey('practice_tile_${items[i].id}'),
                              category: items[i],
                              size: PracticeTileSize.tall,
                              onTap: () => openCategory(context, items[i].id),
                            ),
                            childCount: items.length,
                          ),
                        ),
                      ),
                    ],
                    const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                  ],
                );
              },
            ),
    );
  }
}
