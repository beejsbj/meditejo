import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Both history and pending payloads use the legacy preferences cache. A
// failed write reloads the whole cache, so serialize these keys together.
final _statsPreferencesQueues = Expando<_StatsPreferencesQueue>();

Future<T> serializeStatsPreferences<T>(
  SharedPreferences prefs,
  Future<T> Function() operation,
) {
  final queue = _statsPreferencesQueues[prefs] ??= _StatsPreferencesQueue();
  final result = queue.tail.then((_) async {
    if (queue.needsReload) {
      await prefs.reload();
      queue.needsReload = false;
    }
    try {
      return await operation();
    } catch (_) {
      // Legacy preferences update their cache before the platform replies.
      // Reload actual storage rather than overwriting an ambiguous commit.
      queue.needsReload = true;
      await prefs.reload();
      queue.needsReload = false;
      rethrow;
    }
  });
  queue.tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  return result;
}

/// Pending completions share one mutation queue across storage instances in
/// this engine. A drain acknowledges entries against the current queue, never
/// replaces it with an older snapshot.
class CompletedTracksStorage {
  static const String completedTracksKey = 'completed_tracks_data';

  final SharedPreferences _prefs;

  CompletedTracksStorage(this._prefs);

  static Future<CompletedTracksStorage> create() async {
    return CompletedTracksStorage(await SharedPreferences.getInstance());
  }

  Future<T> _serialized<T>(Future<T> Function() operation) =>
      serializeStatsPreferences(_prefs, operation);

  Future<void> _write(List<String> tracks) async {
    final saved = await _prefs.setStringList(completedTracksKey, tracks);
    if (!saved) throw StateError('Could not save pending completions');
  }

  Future<void> addCompletedTrack(Map<String, dynamic> payload) =>
      _serialized(() => _write([...getPendingTracks(), jsonEncode(payload)]));

  List<String> getPendingTracks() =>
      List<String>.of(_prefs.getStringList(completedTracksKey) ?? []);

  /// Waits for earlier enqueues before taking a drain snapshot.
  Future<List<String>> loadPendingTracks() =>
      _serialized(() async => getPendingTracks());

  /// Removes one occurrence per acknowledged snapshot entry. New enqueues and
  /// failed/unreadable entries remain available for the next drain.
  Future<void> removeCompletedTracks(List<String> acknowledged) =>
      _serialized(() async {
        if (acknowledged.isEmpty) return;
        final current = getPendingTracks();
        for (final entry in acknowledged) {
          current.remove(entry);
        }
        await _write(current);
      });

  bool hasPendingTracks() => getPendingTracks().isNotEmpty;

  Future<void> clearPendingTracks() => _serialized(() => _write([]));
}

class _StatsPreferencesQueue {
  Future<void> tail = Future<void>.value();
  bool needsReload = false;
}
