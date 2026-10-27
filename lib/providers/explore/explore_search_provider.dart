import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/content/catalogue_source.dart';
import 'package:medito/utils/logger.dart';

/// Explore's search: the user's library first, then the built-in catalogues.
///
/// Courses and talks from the library's own sources (imports, YouTube) lead,
/// then anything else already in the library (a saved retreat), then the rest
/// of the catalogues, merged across sources (or narrowed to the one chosen in
/// Explore). An item appears once. Teachers come from the catalogues, with
/// followed ones first.
///
/// The length filter narrows talks by duration, which only catalogue talks
/// carry, so while it is on the library's imports are left out.
final exploreSearchProvider = FutureProvider.autoDispose
    .family<CatalogueSearchResults, CatalogueSearchKey>((ref, key) async {
      final catalogue = await ref.watch(catalogueSearchProvider(key).future);
      ref.watch(libraryRevisionProvider);
      final library = {
        for (final e in await ref.watch(libraryStoreProvider).entries())
          e.sourceId: e,
      };
      final cataloguePrefixes = [
        for (final s in ref.watch(catalogueSourcesProvider)) s.prefix,
      ];
      final needle = key.query.trim().toLowerCase();
      // Source search indexes retain the source title. Search renamed entries
      // as well, without changing that metadata or duplicating a source hit.
      final renamedMatches = library.values.where(
        (e) =>
            e.titleOverride != null &&
            needle.isNotEmpty &&
            e.displayTitle.toLowerCase().contains(needle),
      );
      PackItemsModel asItem(LibraryEntry e) => PackItemsModel(
        type: e.isCourse ? TypeConstants.pack : TypeConstants.track,
        id: e.sourceId,
        title: e.displayTitle,
        subtitle: e.subtitle,
        coverUrl: e.coverUrl,
        path: '/${e.isCourse ? 'packs' : 'tracks'}/${e.sourceId}',
      );
      final ownCourses = [
        for (final e in renamedMatches)
          if (e.isCourse) asItem(e),
      ];
      final ownTalks = [
        for (final e in renamedMatches)
          if (e.kind == LibraryKind.single &&
              (key.length == null ||
                  (cataloguePrefixes.any(e.sourceId.startsWith) &&
                      e.durationMs > 0 &&
                      key.length!.matches(
                        Duration(milliseconds: e.durationMs),
                      ))))
            asItem(e),
      ];
      for (final source in ref.watch(contentSourcesProvider)) {
        if (source is CatalogueSource) continue;
        try {
          ownCourses.addAll(await source.searchPacks(key.query));
          if (key.length == null) {
            ownTalks.addAll(
              (await source.searchTracks(key.query)).map(_asItem),
            );
          }
        } catch (e) {
          AppLogger.d('EXPLORE', 'Library search skipped ${source.prefix}: $e');
        }
      }

      List<PackItemsModel> merge(
        List<PackItemsModel> own,
        List<PackItemsModel> catalogue,
      ) {
        final seen = <String>{};
        final all = [
          ...own,
          ...catalogue.where((i) => library.containsKey(i.id)),
          ...catalogue.where((i) => !library.containsKey(i.id)),
        ];
        return [
          for (final item in all)
            if (seen.add(item.id))
              item.copyWith(
                title: library[item.id]?.displayTitle ?? item.title,
              ),
        ];
      }

      return CatalogueSearchResults(
        teachers: [
          ...catalogue.teachers.where((t) => library.containsKey(t.id)),
          ...catalogue.teachers.where((t) => !library.containsKey(t.id)),
        ],
        courses: merge(ownCourses, catalogue.courses),
        talks: merge(ownTalks, catalogue.talks),
      );
    });

PackItemsModel _asItem(TrackSearchModel t) => PackItemsModel(
  type: TypeConstants.track,
  id: t.id,
  title: t.title,
  subtitle: t.subtitle,
  coverUrl: t.coverUrl,
  path: t.path,
);
