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
typedef LabelSubject = ({String id, String title});

/// The labels of one course or session, in the library or not.
final labelsOfProvider = FutureProvider.autoDispose
    .family<EntryLabels, LabelSubject>((ref, subject) async {
      ref.watch(libraryRevisionProvider);
      final service = await ref.watch(categoryServiceProvider.future);
      return service.labelsOf(subject.id, title: subject.title);
    });

/// A category's page: library items, then Dharma Seed, Practice first.
final categoryListingProvider = FutureProvider.autoDispose
    .family<CategoryListing, String>((ref, categoryId) async {
      final service = await ref.watch(categoryServiceProvider.future);
      final entries = await ref.watch(libraryEntriesProvider.future);
      return service.listing(categoryId, entries: entries);
    });

/// One chip in the Library's label row: a category or a label of the user's
/// own, with how many entries carry it.
typedef LibraryLabelOption = ({String key, String name, int count});

/// The categories and labels at least one library entry carries, curated
/// categories first in the catalogue's order, then the user's own A to Z.
final libraryLabelOptionsProvider =
    Provider.autoDispose<List<LibraryLabelOption>>((ref) {
      final catalogue = ref.watch(categoryCatalogueProvider).value;
      final labels = ref.watch(libraryLabelsProvider).value;
      if (catalogue == null || labels == null) return const [];
      final categoryCounts = <String, int>{};
      final customCounts = <String, ({String name, int count})>{};
      for (final entry in labels.values) {
        for (final c in entry.categories) {
          categoryCounts[c.id] = (categoryCounts[c.id] ?? 0) + 1;
        }
        for (final text in entry.custom) {
          final key = customLabelKey(text);
          final seen = customCounts[key];
          customCounts[key] = (name: seen?.name ?? text, count: (seen?.count ?? 0) + 1);
        }
      }
      return [
        for (final category in catalogue.categories)
          if ((categoryCounts[category.id] ?? 0) > 0)
            (
              key: category.id,
              name: category.name,
              count: categoryCounts[category.id]!,
            ),
        for (final MapEntry(:key, :value) in customCounts.entries.toList()
          ..sort(
            (a, b) => a.value.name.toLowerCase().compareTo(
              b.value.name.toLowerCase(),
            ),
          ))
          (key: key, name: value.name, count: value.count),
      ];
    });
