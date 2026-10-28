import 'dart:async';

import 'package:medito/services/library/library_store.dart';
import 'package:medito/utils/logger.dart';

/// Says where a session is being opened from, before it starts: the player
/// reads it for the session's cue scope and autoplay. [courseId] is the
/// course the user is working through, or null for a surface that has none
/// (search, a library row, a teacher page, a link), which forgets the course
/// the session was last opened from.
///
/// A course is written before the caller goes on. Forgetting is not waited
/// for: the store runs its calls in order, so it lands before the session's
/// own read, and a surface with no course never waits on the library opening.
/// A failure is logged and never stops the session.
Future<void> noteSessionOrigin(
  LibraryStore store,
  String trackId,
  String? courseId,
) async {
  void failed(Object e, StackTrace st) => AppLogger.e(
    'LIBRARY',
    'Could not note where a session was opened from',
    e,
    st,
  );
  try {
    final noted = store.noteSessionOrigin(trackId, courseId);
    if (courseId == null) {
      unawaited(noted.catchError(failed));
    } else {
      await noted;
    }
  } catch (e, st) {
    failed(e, st);
  }
}
