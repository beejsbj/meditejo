import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/utils/logger.dart';

/// What Home offers to carry on with: up to three sessions, from any source,
/// that were started and not finished, practice first and then the most
/// recently played. Two kinds count: a session left partway (it resumes where
/// it stopped), and a course with some sessions done and some not (it offers
/// its next one). A course shows once.
///
/// With nothing in progress this is the next session of a pinned course, or
/// else of the first course in the library (the starter set leads it on a
/// fresh install), so Home is not empty while there is anything to start.
final continueItemsProvider = FutureProvider.autoDispose<List<ContinueItem>>((
  ref,
) async {
  ref.watch(libraryRevisionProvider);
  ref.watch(playbackPositionsRevisionProvider);
  final checked = {...?ref.watch(statsProvider).value?.tracksChecked};
  final pinned = ref.watch(pinnedCoursesProvider);
  final store = ref.watch(libraryStoreProvider);
  final router = ref.watch(libraryContentRouterProvider);

  final entries = await store.entries();
  final entryById = {for (final e in entries) e.sourceId: e};

  Future<PackModel?> packOf(String id) async {
    try {
      return await ref.watch(packDataProvider(packId: id).future);
    } catch (e) {
      AppLogger.d('HOME', 'Continue could not read $id: $e');
      return null;
    }
  }

  PackItemsModel? nextIn(PackModel pack) => pack.items
      .where((i) => i.type == TypeConstants.track && !checked.contains(i.id))
      .firstOrNull;

  ContinueItem fromItem(
    PackModel pack,
    PackItemsModel item,
    LibraryEntry? entry, {
    ResumePoint? resume,
    DateTime? lastPlayed,
  }) {
    final index = pack.items.indexWhere((i) => i.id == item.id);
    return ContinueItem(
      trackId: item.id,
      path: item.path,
      title: item.title,
      subtitle: item.subtitle ?? '',
      group: entry?.group ?? LibraryGroup.practice,
      lastPlayed:
          lastPlayed ??
          entry?.lastPlayedAt ??
          entry?.addedAt ??
          DateTime.fromMillisecondsSinceEpoch(0),
      courseId: pack.id,
      courseTitle: entry?.displayTitle ?? pack.title,
      coverUrl: item.coverUrl ?? pack.coverUrl ?? '',
      resume: resume,
      sessionNumber: index < 0 ? null : index + 1,
      sessionTotal: pack.items
          .where((i) => i.type == TypeConstants.track)
          .length,
      completedSessions: pack.items
          .where((i) => i.type == TypeConstants.track && checked.contains(i.id))
          .length,
    );
  }

  final candidates = <ContinueItem>[];
  final coursesWithPlace = <String>{};

  // Sessions left partway.
  for (final place in await store.savedPlaces()) {
    if (checked.contains(place.trackId)) continue;
    try {
      final track = await router.track(place.trackId);
      final parentId = await router.parentOf(place.trackId);
      final parent = parentId == null ? null : entryById[parentId];
      final own = entryById[place.trackId];
      final group =
          own?.group ??
          parent?.group ??
          (track.hasBackgroundSound
              ? LibraryGroup.practice
              : LibraryGroup.talks);
      final pack = parentId == null ? null : await packOf(parentId);
      final index = pack?.items.indexWhere((i) => i.id == place.trackId) ?? -1;
      if (parentId != null) coursesWithPlace.add(parentId);
      candidates.add(
        ContinueItem(
          trackId: place.trackId,
          path: '/tracks/${place.trackId}',
          title: own?.displayTitle ?? track.title,
          subtitle: track.subtitle ?? '',
          group: group,
          lastPlayed: place.updatedAt,
          courseId: parentId,
          courseTitle: parent?.displayTitle ?? pack?.title ?? '',
          coverUrl: track.coverUrl.isNotEmpty
              ? track.coverUrl
              : (pack?.coverUrl ?? ''),
          resume: place.point,
          sessionNumber: index < 0 ? null : index + 1,
          sessionTotal: pack?.items
              .where((i) => i.type == TypeConstants.track)
              .length,
          completedSessions:
              pack?.items
                  .where(
                    (i) =>
                        i.type == TypeConstants.track && checked.contains(i.id),
                  )
                  .length ??
              0,
        ),
      );
    } catch (e) {
      AppLogger.d('HOME', 'Continue skipped ${place.trackId}: $e');
    }
  }

  // Courses begun and not finished, with no session left partway.
  final started = entries.where(
    (e) => e.isCourse && !coursesWithPlace.contains(e.sourceId),
  );
  for (final entry in started) {
    final pack = await packOf(entry.sourceId);
    if (pack == null) continue;
    final tracks = pack.items.where((i) => i.type == TypeConstants.track);
    final done = tracks.where((i) => checked.contains(i.id)).length;
    final next = nextIn(pack);
    if (done == 0 || next == null) continue;
    candidates.add(fromItem(pack, next, entry));
  }

  final ranked = rankContinue(candidates);
  if (ranked.isNotEmpty) return ranked;

  // Nothing in progress: the next session of a pinned course, else of the
  // first course in the library.
  final order = [
    ...pinned,
    for (final e in LibrarySections.of(entries).contentFirstPractice)
      if (e.isCourse) e.sourceId,
  ];
  for (final id in order) {
    final pack = await packOf(id);
    final next = pack == null ? null : nextIn(pack);
    if (pack != null && next != null) {
      return [fromItem(pack, next, entryById[id])];
    }
  }
  return const [];
});
