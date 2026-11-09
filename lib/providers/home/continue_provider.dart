import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/continue_dismissed_provider.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/home/next_session.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/utils/logger.dart';

/// What Home offers to carry on with: the first three things in progress,
/// sessions from any source that were started and not finished, practice
/// first and then the most recently played. Two kinds count: a session left
/// partway (it resumes where it stopped), and a course with some sessions
/// done and some not (it offers its next one). A course shows once. (The
/// Library has no In progress of its own: this covers it, #80.)
///
/// With nothing in progress this is the next session of a pinned course, or
/// else of the first course in the library (the starter set leads it on a
/// fresh install), so Home is not empty while there is anything to start.
final continueItemsProvider = FutureProvider.autoDispose<List<ContinueItem>>(
  (ref) => _readContinue(ref, limit: continueLimit, fallback: true),
);

Future<List<ContinueItem>> _readContinue(
  Ref ref, {
  required int? limit,
  required bool fallback,
}) async {
  ref.watch(libraryRevisionProvider);
  ref.watch(playbackPositionsRevisionProvider);
  final checked = {...?ref.watch(statsProvider).value?.tracksChecked};
  // Only pinned courses have a next session; a pinned session is its own.
  final pins = ref.read(pinnedCoursesProvider.notifier);
  final pinned = fallback
      ? [
          for (final id in ref.watch(pinnedCoursesProvider))
            if (!pins.isSession(id)) id,
        ]
      : const <String>[];
  // Only Home honours what the user removed from Continue.
  final dismissed = fallback
      ? ref.watch(continueDismissedProvider)
      : const <String, int>{};
  bool hidden(String key, DateTime lastPlayed) {
    final at = dismissed[key];
    return at != null && lastPlayed.millisecondsSinceEpoch <= at;
  }

  final store = ref.watch(libraryStoreProvider);
  final router = ref.watch(libraryContentRouterProvider);

  final entries = await store.entries();
  if (!ref.mounted) return const [];
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
  final places = {
    for (final place in await store.savedPlaces()) place.trackId: place,
  };
  if (!ref.mounted) return const [];
  final partial = {
    for (final place in places.values) place.trackId: place.updatedAt,
  };

  // The same rule as the course page's play button.
  NextSession? nextIn(PackModel pack) =>
      nextSessionFor(pack, partial: partial, completedIds: checked);

  int? numberIn(PackModel? pack, String trackId) {
    final index = pack?.playableTracks.indexWhere((i) => i.id == trackId) ?? -1;
    return index < 0 ? null : index + 1;
  }

  int doneIn(PackModel pack) =>
      pack.playableTracks.where((i) => checked.contains(i.id)).length;

  ContinueItem fromItem(PackModel pack, NextSession next, LibraryEntry? entry) {
    final item = next.item;
    final place = places[item.id];
    return ContinueItem(
      trackId: item.id,
      path: item.path,
      title: item.title,
      subtitle: item.subtitle ?? '',
      group: entry?.group ?? LibraryGroup.practice,
      lastPlayed:
          place?.updatedAt ??
          entry?.lastPlayedAt ??
          entry?.addedAt ??
          DateTime.fromMillisecondsSinceEpoch(0),
      courseId: pack.id,
      courseTitle: entry?.displayTitle ?? pack.title,
      coverUrl: item.coverUrl ?? pack.coverUrl ?? '',
      resume: place?.point,
      sessionNumber: numberIn(pack, item.id),
      sessionTotal: pack.playableTracks.length,
      completedSessions: doneIn(pack),
    );
  }

  final candidates = <ContinueItem>[];
  final coursesWithPlace = <String>{};

  // Sessions left partway.
  for (final place in places.values) {
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
      // The course it is shown under ranks it, as its cues are scoped.
      final group =
          (inOpened ? parent?.group : null) ??
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
    if (!ref.mounted) return const [];
    if (pack == null) continue;
    final next = nextIn(pack);
    if (doneIn(pack) == 0 || next == null) continue;
    // A session in several courses, left partway after opening it from
    // another, is already offered there: not twice.
    if (candidates.any((c) => c.trackId == next.item.id)) continue;
    candidates.add(fromItem(pack, next, entry));
  }

  candidates.removeWhere((c) => hidden(continueKeyOf(c), c.lastPlayed));
  final ranked = rankContinue(candidates, limit: limit);
  if (ranked.isNotEmpty || !fallback) return ranked;

  // Nothing in progress: the next session of a pinned course, else of the
  // first course in the library.
  final order = [
    ...pinned,
    for (final e in LibrarySections.of(entries).contentFirstPractice)
      if (e.isCourse) e.sourceId,
  ];
  for (final id in order) {
    final pack = await packOf(id);
    if (!ref.mounted) return const [];
    final next = pack == null ? null : nextIn(pack);
    if (pack != null && next != null) {
      final item = fromItem(pack, next, entryById[id]);
      if (hidden(continueKeyOf(item), item.lastPlayed)) continue;
      return [item];
    }
  }
  return const [];
}
