import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/utils/logger.dart';

/// The course an episode's page names (#84): the one it was opened from
/// while that course still lists it, else the one its source says holds it
/// (a Dharma Seed talk's retreat, a podcast episode's feed, a YouTube
/// video's saved playlist). Null for a session no course holds, or when
/// that cannot be read. Read again when the library or a playlist the user
/// made changes, since saving a course, removing it, or taking the session
/// out of a playlist can change the answer.
final episodeCourseIdProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, trackId) async {
      ref.watch(libraryEntryIdsProvider);
      ref.watch(myCoursesRevisionProvider);
      final router = ref.watch(libraryContentRouterProvider);
      final store = ref.watch(libraryStoreProvider);
      try {
        return await router.courseOfSession(
          trackId,
          openedFrom: await store.sessionContext(trackId),
        );
      } catch (e, st) {
        AppLogger.e('TRACK', 'Could not read the course of $trackId', e, st);
        return null;
      }
    });
