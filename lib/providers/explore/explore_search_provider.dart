import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_models.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/utils/logger.dart';

/// Explore's search: the user's library first, then Dharma Seed.
///
/// Courses and talks from the library's own sources (imports, YouTube) lead,
/// then anything else already in the library (a saved retreat), then the rest
/// of Dharma Seed. An item appears once. Teachers are Dharma Seed's, with
/// followed ones first.
///
/// The length filter narrows talks by duration, which only Dharma Seed talks
/// carry, so while it is on the library's imports are left out.
final exploreSearchProvider = FutureProvider.autoDispose
    .family<DsSearchResults, DsSearchKey>((ref, key) async {
      final dharmaSeed = await ref.watch(dharmaSeedSearchProvider(key).future);
      ref.watch(libraryRevisionProvider);
      final libraryIds = {
        for (final e in await ref.watch(libraryStoreProvider).entries())
          e.sourceId,
      };

      final ownCourses = <PackItemsModel>[];
      final ownTalks = <PackItemsModel>[];
      for (final source in ref.watch(contentSourcesProvider)) {
        if (source is DharmaSeedSource) continue;
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
          ...catalogue.where((i) => libraryIds.contains(i.id)),
          ...catalogue.where((i) => !libraryIds.contains(i.id)),
        ];
        return [
          for (final item in all)
            if (seen.add(item.id)) item,
        ];
      }

      return DsSearchResults(
        teachers: [
          ...dharmaSeed.teachers.where((t) => libraryIds.contains(t.id)),
          ...dharmaSeed.teachers.where((t) => !libraryIds.contains(t.id)),
        ],
        courses: merge(ownCourses, dharmaSeed.courses),
        talks: merge(ownTalks, dharmaSeed.talks),
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
