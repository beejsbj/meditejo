import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/categories/category_service.dart';
import 'package:medito/services/categories/entry_labels.dart';

/// The curated mapping, read once from the bundled asset.
final categoryCatalogueProvider = FutureProvider<CategoryCatalogue>(
  (ref) => CategoryCatalogue.load(),
);

final categoryServiceProvider = FutureProvider<CategoryService>((ref) async {
  return CategoryService(
    catalogue: await ref.watch(categoryCatalogueProvider.future),
    library: ref.watch(libraryStoreProvider),
    dharmaSeed: ref.watch(dharmaSeedDatabaseProvider),
  );
});

/// The labels of everything in the library, by content ID: the app's guesses
/// with the user's own on top. Re-read when the library changes, which
/// includes every label edit.
final libraryLabelsProvider =
    FutureProvider.autoDispose<Map<String, EntryLabels>>((ref) async {
      final service = await ref.watch(categoryServiceProvider.future);
      final entries = await ref.watch(libraryEntriesProvider.future);
      return service.labelsOfEntries(entries);
    });

/// What a page needs to know to ask about one thing's labels.
typedef LabelSubject = ({String id, String title, String subtitle});

/// The labels of one course or session, in the library or not.
final labelsOfProvider = FutureProvider.autoDispose
    .family<EntryLabels, LabelSubject>((ref, subject) async {
      ref.watch(libraryRevisionProvider);
      final service = await ref.watch(categoryServiceProvider.future);
      return service.labelsOf(
        subject.id,
        title: subject.title,
        subtitle: subject.subtitle,
      );
    });

/// A category's page: library items, then Dharma Seed, Practice first.
final categoryListingProvider = FutureProvider.autoDispose
    .family<CategoryListing, String>((ref, categoryId) async {
      final service = await ref.watch(categoryServiceProvider.future);
      final entries = await ref.watch(libraryEntriesProvider.future);
      return service.listing(categoryId, entries: entries);
    });
