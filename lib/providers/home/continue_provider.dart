import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // Sessions a personal course lists but their source has lost are not
  // counted or offered (`playableTracks`).
  PackItemsModel? nextIn(PackModel pack) =>
      pack.playableTracks.where((i) => !checked.contains(i.id)).firstOrNull;

  int? numberIn(PackModel? pack, String trackId) {
    final index = pack?.playableTracks.indexWhere((i) => i.id == trackId) ?? -1;
    return index < 0 ? null : index + 1;
  }

  int doneIn(PackModel pack) =>
      pack.playableTracks.where((i) => checked.contains(i.id)).length;

  ContinueItem fromItem(
    PackModel pack,
    PackItemsModel item,
    LibraryEntry? entry, {
    ResumePoint? resume,
    DateTime? lastPlayed,
  }) {
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
      sessionNumber: numberIn(pack, item.id),
      sessionTotal: pack.playableTracks.length,
      completedSessions: doneIn(pack),
    );
  }

  final candidates = <ContinueItem>[];
  final coursesWithPlace = <String>{};

  // Sessions left partway.
  for (final place in await store.savedPlaces()) {
    if (checked.contains(place.trackId)) continue;
    try {
      final track = await router.track(place.trackId);
      // A session in several courses counts towards the one it was opened
      // from, while that course still lists it; else its source's course.
      final opened = await store.sessionContext(place.trackId);
      final openedPack = opened == null ? null : await packOf(opened);
      final inOpened =
          openedPack?.items.any((i) => i.id == place.trackId) ?? false;
      final parentId = inOpened ? opened : await router.parentOf(place.trackId);
      final parent = parentId == null ? null : entryById[parentId];
      final own = entryById[place.trackId];
      final group =
          own?.group ??
          parent?.group ??
          (track.hasBackgroundSound
              ? LibraryGroup.practice
              : LibraryGroup.talks);
      final pack = inOpened
          ? openedPack
          : (parentId == null ? null : await packOf(parentId));
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
          sessionNumber: numberIn(pack, place.trackId),
          sessionTotal: pack?.playableTracks.length,
          completedSessions: pack == null ? 0 : doneIn(pack),
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
    final next = nextIn(pack);
    if (doneIn(pack) == 0 || next == null) continue;
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
