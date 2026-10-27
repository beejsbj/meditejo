import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/services/categories/category_service.dart';
import 'package:medito/views/dharma_seed/widgets/course_rows_sliver.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/views/library/library_widgets.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/section_title.dart';
import 'package:medito/widgets/widgets.dart';

void openCategory(BuildContext context, String categoryId) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => CategoryView(categoryId: categoryId)),
);

/// One category's page: what the user keeps under it, then Dharma Seed's
/// courses and sessions, Practice before Talks (decision 11).
///
/// Thin on purpose: the model is in `CategoryService`, and the UX pass may
/// reshape how browsing reads.
class CategoryView extends ConsumerWidget {
  const CategoryView({super.key, required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(categoryListingProvider(categoryId));
    final category = ref
        .watch(categoryCatalogueProvider)
        .value
        ?.category(categoryId);

    return Scaffold(
      appBar: AppBar(
        title: Text(category?.name ?? ''),
        titleTextStyle: context.typography.emphasized.titleLarge,
      ),
      body: AdaptivePageBody(
        maxWidth: 760,
        child: listing.when(
          data: (data) => _Body(listing: data),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => MeditoErrorWidget(
            error: error is AppError ? error : const UnknownError(),
            isScaffold: false,
            onTap: () => ref.invalidate(categoryListingProvider(categoryId)),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.listing});

  final CategoryListing listing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final blurb = listing.category.blurb;
    return CustomScrollView(
      key: ValueKey('category_page_${listing.category.id}'),
      slivers: [
        if (blurb.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                kCardGutter + 4,
                4,
                kCardGutter,
                8,
              ),
              child: Text(
                blurb,
                style: context.typography.baseline.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (listing.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.categoryEmptyTitle,
                      style: context.typography.emphasized.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.categoryEmptyBody,
                      style: context.typography.baseline.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          if (listing.hasPractice) ...[
            _heading(l10n.libraryPractice),
            SliverList.list(
              children: [
                for (final entry in listing.libraryPractice)
                  LibraryEntryTile(entry: entry),
              ],
            ),
            if (listing.courses.isNotEmpty)
              CourseRowsSliver(courses: listing.courses),
            if (listing.practiceSessions.isNotEmpty)
              SessionRowsSliver(items: listing.practiceSessions),
          ],
          if (listing.hasTalks) ...[
            _heading(l10n.libraryTalks),
            SliverList.list(
              children: [
                for (final entry in listing.libraryTalks)
                  LibraryEntryTile(entry: entry),
              ],
            ),
            if (listing.talkSessions.isNotEmpty)
              SessionRowsSliver(items: listing.talkSessions),
          ],
        ],
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 24,
          ),
        ),
      ],
    );
  }

  Widget _heading(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SectionTitle(text),
    ),
  );
}
