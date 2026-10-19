import 'package:medito/services/library/library_store.dart';

/// Remembers where the user is in a session, so it can be resumed, and brings
/// the course it belongs to to the front of the library.
///
/// Fed with the player's state as it changes. While playing it saves at most
/// every [interval] of listening, quietly; on pause or stop it saves once more
/// and tells lists to re-read. A finished session forgets its place. Sessions
/// the library has no use for (the timer, whose IDs [ignore] names) are
/// skipped.
class PlaybackPositionTracker {
  PlaybackPositionTracker(
    this.store, {
    required this.parentsOf,
    this.ignore = _neverIgnore,
    this.interval = const Duration(seconds: 5),
  });

  final LibraryStore store;

  /// Library IDs a session belongs to besides itself: its course.
  final Future<Iterable<String>> Function(String trackId) parentsOf;
  final bool Function(String trackId) ignore;
  final Duration interval;

  static bool _neverIgnore(String _) => false;

  String? _trackId;
  var _lastSavedMs = 0;
  var _wasPlaying = false;
  var _touched = false;

  /// One player state: the session's ID, the position and length in
  /// milliseconds, and whether it is playing or has finished.
  Future<void> onState({
    required String trackId,
    required int positionMs,
    required int durationMs,
    required bool isPlaying,
    required bool isCompleted,
    String fileId = '',
  }) async {
    if (trackId.isEmpty || ignore(trackId)) {
      _trackId = null;
      return;
    }
    if (trackId != _trackId) {
      _trackId = trackId;
      _lastSavedMs = 0;
      _wasPlaying = false;
      _touched = false;
    }

    if (isCompleted) {
      _wasPlaying = false;
      await store.clearPosition(trackId);
      return;
    }

    final paused = _wasPlaying && !isPlaying;
    _wasPlaying = isPlaying;

    if (isPlaying && !_touched) {
      _touched = true;
      await store.touchPlayed([trackId, ...await parentsOf(trackId)]);
    }

    if (paused) {
      _lastSavedMs = positionMs;
      await store.savePosition(trackId, positionMs, durationMs, fileId: fileId);
    } else if (isPlaying &&
        (positionMs - _lastSavedMs).abs() >= interval.inMilliseconds) {
      _lastSavedMs = positionMs;
      await store.savePosition(
        trackId,
        positionMs,
        durationMs,
        fileId: fileId,
        notify: false,
      );
    }
  }
}
