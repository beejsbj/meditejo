import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/library/library_models.dart';

import '../../helpers/library_fixtures.dart';

/// The library's labels and a category's page follow the library's revision
/// rather than watching its entries (see `_libraryEntriesNow`); they must
/// still pick up every add and remove.
void main() {
  test(
    'labels and a category listing refresh when the library changes',
    () async {
      final h = LibraryHarness.create();
      addTearDown(h.dispose);
      final catalogue = CategoryCatalogue.parse(
        File(categoriesAsset).readAsStringSync(),
      );
      final container = ProviderContainer(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(h.db),
          libraryStoreProvider.overrideWithValue(h.store),
          dharmaSeedDatabaseProvider.overrideWithValue(h.dsDb),
          categoryCatalogueProvider.overrideWith((ref) async => catalogue),
        ],
      );
      addTearDown(container.dispose);
      // Kept listened, as the Library and a category page would.
      container.listen(libraryLabelsProvider, (_, _) {});
      container.listen(categoryListingProvider('body'), (_, _) {});

      Future<Set<String>> labelled() async =>
          (await container.read(libraryLabelsProvider.future)).keys.toSet();
      Future<List<String>> inBody() async => [
        for (final e in (await container.read(
          categoryListingProvider('body').future,
        )).libraryPractice)
          e.sourceId,
      ];

      expect(await labelled(), isEmpty);
      expect(await inBody(), isEmpty);

      await h.store.add(
        const LibraryDraft(
          sourceId: 'lib-track-a',
          kind: LibraryKind.single,
          title: 'Body scan',
          group: LibraryGroup.practice,
        ),
      );
      expect(await labelled(), {'lib-track-a'});
      expect(await inBody(), ['lib-track-a']);

      await h.store.remove('lib-track-a');
      expect(await labelled(), isEmpty);
      expect(await inBody(), isEmpty);
    },
  );
}
