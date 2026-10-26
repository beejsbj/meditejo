import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/utils/logger.dart';

/// What a finished session was, for the stats page: Practice or Talks, and
/// the course it was played from. Every field is null when unknown.
@immutable
class SessionLabel {
  const SessionLabel({this.kind, this.courseId, this.courseTitle});

  static const unknown = SessionLabel();

  /// [LocalAudioCompleted.kindPractice] or [LocalAudioCompleted.kindTalks].
  final String? kind;
  final String? courseId;
  final String? courseTitle;

  @override
  bool operator ==(Object other) =>
      other is SessionLabel &&
      kind == other.kind &&
      courseId == other.courseId &&
      courseTitle == other.courseTitle;

  @override
  int get hashCode => Object.hash(kind, courseId, courseTitle);
}

/// Remembers, per session, the Practice/Talks kind and course the player
/// resolved when it started it (the same answer the cues use), so the
/// completion that arrives from the platform later is labelled the same way.
/// Held in memory: a completion replayed after the app was killed falls back
/// to [labelSessionCompletion]'s own lookup.
abstract final class SessionLabelRegistry {
  static const _limit = 24;
  static final Map<String, SessionLabel> _byTrack = {};

  static void remember(String trackId, {String? kind, String? courseId}) {
    _byTrack.remove(trackId);
    _byTrack[trackId] = SessionLabel(kind: kind, courseId: courseId);
    while (_byTrack.length > _limit) {
      _byTrack.remove(_byTrack.keys.first);
    }
  }

  static SessionLabel? recall(String trackId) => _byTrack[trackId];

  @visibleForTesting
  static void clear() => _byTrack.clear();
}

/// How long a completion waits for a course's title from its source.
const kCourseTitleWait = Duration(seconds: 2);

/// Test seam: replaces [labelSessionCompletion].
@visibleForTesting
Future<SessionLabel> Function(String trackId)? sessionLabelOverride;

/// The label for the session [trackId] that just finished. Never throws:
/// stats must record the session even when the library cannot answer.
Future<SessionLabel> labelSessionCompletion(String trackId) async {
  final override = sessionLabelOverride;
  if (override != null) return override(trackId);
  // A timer is practice by definition; a manual entry is practice sat
  // outside the app. Neither has a course.
  if (isTimerSessionId(trackId)) {
    return const SessionLabel(kind: LocalAudioCompleted.kindPractice);
  }
  try {
    final context = navigatorKey.currentContext;
    if (context == null) {
      return SessionLabelRegistry.recall(trackId) ?? SessionLabel.unknown;
    }
    final container = ProviderScope.containerOf(context);
    final store = container.read(libraryStoreProvider);
    final router = container.read(contentRouterProvider);

    final remembered = SessionLabelRegistry.recall(trackId);
    var kind = remembered?.kind;
    var courseId = remembered?.courseId;
    if (remembered == null) {
      courseId = await router.parentOf(trackId);
      final group =
          (courseId == null ? null : await store.groupOf(courseId)) ??
          await store.groupOf(trackId);
      kind = switch (group) {
        LibraryGroup.practice => LocalAudioCompleted.kindPractice,
        LibraryGroup.talks => LocalAudioCompleted.kindTalks,
        _ => null,
      };
    }

    String? title;
    if (courseId != null) {
      title = (await store.entry(courseId))?.displayTitle;
      if (title == null || title.isEmpty) {
        // A course the library does not hold (a retreat played from Explore)
        // may need a network fetch for its title. Recording the session must
        // not wait on it: a short wait, then the session is saved untitled.
        try {
          title = (await router.pack(courseId).timeout(kCourseTitleWait)).title;
        } catch (_) {
          title = null;
        }
      }
    }
    return SessionLabel(kind: kind, courseId: courseId, courseTitle: title);
  } catch (e) {
    AppLogger.w('STATS', 'Could not label session $trackId: $e');
    return SessionLabelRegistry.recall(trackId) ?? SessionLabel.unknown;
  }
}
